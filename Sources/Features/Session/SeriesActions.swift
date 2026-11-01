import Foundation

/// Which sessions a series action applies to.
enum SeriesScope: Sendable { case thisOnly, following }

/// Calendar side-effect summary; the store change has already happened.
struct SeriesOutcome: Equatable, Sendable {
    var calendarWarning: String?
}

/// Result of a "this and following" action.
struct FollowingResult: Equatable, Sendable {
    /// Occurrences cancelled or deleted (protected ones are detached, not counted).
    var changed: Int
    var outcome: SeriesOutcome
}

/// Splits "this and following" occurrences: `affected` are still scheduled with
/// no logged sets; `protected` are scheduled but already have sets. Completed,
/// cancelled and no-show occurrences are left out entirely.
func partitionFollowing(_ occurrences: [SeriesOccurrence]) -> (affected: [SessionDTO], protected: [SessionDTO]) {
    let scheduled = occurrences.filter { $0.session.status == .scheduled }
    return (
        scheduled.filter { !$0.hasLoggedSets }.map(\.session),
        scheduled.filter { $0.hasLoggedSets }.map(\.session)
    )
}

/// Moves a date to the given time of day on the same calendar day, seconds zeroed.
func retime(_ date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
}

/// Weekly rule for a new series segment: the old rule's weekdays (or the
/// weekdays of the given dates when the stored rule is missing), ending on the
/// last date.
func segmentRule(from old: AppRecurrence?, dates: [Date], calendar: Calendar = .current) -> AppRecurrence {
    let stored = old.map(\.weekdays).flatMap { $0.isEmpty ? nil : $0 }
    let weekdays = stored ?? Array(Set(dates.map { calendar.component(.weekday, from: $0) })).sorted()
    return AppRecurrence(
        frequency: .weekly, interval: max(1, old?.interval ?? 1),
        weekdays: weekdays, endDate: dates.last, occurrenceCount: nil
    )
}

/// Dates the new recurring event would generate between the first and last
/// kept date that have no session (earlier cancellations, protected or deleted
/// occurrences). They are removed from the new event after it is created.
func gapDates(rule: AppRecurrence, keep: [Date]) -> [Date] {
    guard let first = keep.first, let last = keep.last else { return [] }
    let kept = Set(keep)
    return expandRecurrence(rule, from: first, to: last).filter { !kept.contains($0) }
}

/// Orchestrates store and calendar changes for sessions in a recurring series.
/// Store first, then calendar; calendar failures become a warning and never
/// undo the store change (same contract as `resolveEventIdentifier`).
struct SeriesActions: Sendable {
    let sessionRepo: any SessionRepository
    let calendar: any CalendarSyncing

    static let removeWarning = "Saved, but the calendar event couldn't be removed."
    static let pushWarning = "Saved, but the calendar couldn't be updated."

    func cancelOccurrence(_ session: SessionDTO) async throws -> SeriesOutcome {
        try await sessionRepo.setStatus(id: session.id, .cancelled)
        return await removeFromEvent(session)
    }

    func deleteOccurrence(_ session: SessionDTO) async throws -> SeriesOutcome {
        try await sessionRepo.delete(id: session.id)
        return await removeFromEvent(session)
    }

    func cancelFollowing(from session: SessionDTO, clientName: String) async throws -> FollowingResult {
        try await following(from: session, clientName: clientName) { ids in
            try await sessionRepo.setStatus(ids: ids, .cancelled)
        }
    }

    func deleteFollowing(from session: SessionDTO, clientName: String) async throws -> FollowingResult {
        try await following(from: session, clientName: clientName) { ids in
            try await sessionRepo.delete(ids: ids)
        }
    }

    /// Moves this and the later scheduled occurrences to a new time, duration
    /// and notes as a new series segment with its own recurring event.
    func editFollowing(
        from session: SessionDTO, hour: Int, minute: Int,
        duration: TimeInterval, notes: String?, clientName: String
    ) async throws -> FollowingResult {
        guard let seriesId = session.seriesId else {
            return FollowingResult(changed: 0, outcome: SeriesOutcome())
        }
        let (affected, protected) = partitionFollowing(
            try await sessionRepo.seriesOccurrences(seriesId: seriesId, from: session.startAt)
        )
        var outcome = SeriesOutcome()
        // Protected rows leave first so their standalone events keep the old time.
        for occurrence in protected {
            let (_, detachOutcome) = try await detach(occurrence, clientName: clientName, removeOccurrence: false)
            outcome.calendarWarning = outcome.calendarWarning ?? detachOutcome.calendarWarning
        }
        let newDates = affected.map { retime($0.startAt, hour: hour, minute: minute) }
        let rule = segmentRule(from: session.recurrence, dates: newDates)
        let newSeriesId = UUID()
        try await sessionRepo.resegment(
            ids: affected.map(\.id), newSeriesId: newSeriesId, recurrence: rule,
            hour: hour, minute: minute, duration: duration, notes: notes
        )
        guard let oldEventId = session.eventIdentifier else {
            return FollowingResult(changed: affected.count, outcome: outcome)
        }
        // End the old event before pushing the new one: a failed push then
        // leaves missing sessions plus a warning, not a duplicate series.
        do {
            try await calendar.endSeries(eventIdentifier: oldEventId, before: session.startAt)
            if var anchor = affected.first, let firstDate = newDates.first {
                anchor.startAt = firstDate
                anchor.endAt = firstDate.addingTimeInterval(duration)
                anchor.notes = notes
                if let newId = try await calendar.push(anchor, clientName: clientName, recurrence: rule) {
                    for gap in gapDates(rule: rule, keep: newDates) {
                        try await calendar.removeOccurrence(eventIdentifier: newId, occurrenceStart: gap)
                    }
                    try await sessionRepo.setEventIdentifierForSeries(newSeriesId, newId)
                }
            }
        } catch {
            Log.calendar.error("editFollowing calendar step failed: \(error.localizedDescription)")
            outcome.calendarWarning = outcome.calendarWarning ?? Self.pushWarning
        }
        return FollowingResult(changed: affected.count, outcome: outcome)
    }

    /// Store: apply `change` to affected rows, then detach protected rows (each
    /// gets its own event). Calendar: end the old event at this occurrence.
    /// Ending happens after the protected pushes, so a failed end leaves
    /// duplicates in the calendar rather than missing sessions.
    private func following(
        from session: SessionDTO,
        clientName: String,
        change: ([UUID]) async throws -> Void
    ) async throws -> FollowingResult {
        guard let seriesId = session.seriesId else {
            return FollowingResult(changed: 0, outcome: SeriesOutcome())
        }
        let (affected, protected) = partitionFollowing(
            try await sessionRepo.seriesOccurrences(seriesId: seriesId, from: session.startAt)
        )
        try await change(affected.map(\.id))
        var outcome = SeriesOutcome()
        for occurrence in protected {
            let (_, detachOutcome) = try await detach(occurrence, clientName: clientName, removeOccurrence: false)
            outcome.calendarWarning = outcome.calendarWarning ?? detachOutcome.calendarWarning
        }
        if let eventId = session.eventIdentifier {
            do {
                try await calendar.endSeries(eventIdentifier: eventId, before: session.startAt)
            } catch {
                Log.calendar.error("endSeries failed: \(error.localizedDescription)")
                outcome.calendarWarning = outcome.calendarWarning ?? Self.removeWarning
            }
        }
        return FollowingResult(changed: affected.count, outcome: outcome)
    }

    /// Store first (detach), then calendar: drop the date from the shared event
    /// and give the session its own event if the series had one. Returns the
    /// detached DTO. `removeOccurrence: false` is for callers that end the
    /// recurring event themselves.
    func detach(
        _ session: SessionDTO, clientName: String, removeOccurrence: Bool = true
    ) async throws -> (SessionDTO, SeriesOutcome) {
        try await sessionRepo.detach(id: session.id)
        var outcome = removeOccurrence ? await removeFromEvent(session) : SeriesOutcome()
        if session.eventIdentifier != nil {
            var standalone = session
            standalone.seriesId = nil
            standalone.eventIdentifier = nil
            do {
                if let newId = try await calendar.push(standalone, clientName: clientName, recurrence: nil) {
                    try await sessionRepo.setEventIdentifier(id: session.id, newId)
                }
            } catch {
                Log.calendar.error("standalone push failed: \(error.localizedDescription)")
                outcome.calendarWarning = outcome.calendarWarning ?? Self.pushWarning
            }
        }
        let refreshed = try await sessionRepo.get(id: session.id) ?? session
        return (refreshed, outcome)
    }

    /// Takes one date out of the shared recurring event. The row keeps its
    /// identifier because the other occurrences still point at the same event.
    private func removeFromEvent(_ session: SessionDTO) async -> SeriesOutcome {
        guard let eventId = session.eventIdentifier else { return SeriesOutcome() }
        do {
            try await calendar.removeOccurrence(eventIdentifier: eventId, occurrenceStart: session.startAt)
            return SeriesOutcome()
        } catch {
            Log.calendar.error("removeOccurrence failed: \(error.localizedDescription)")
            return SeriesOutcome(calendarWarning: Self.removeWarning)
        }
    }
}
