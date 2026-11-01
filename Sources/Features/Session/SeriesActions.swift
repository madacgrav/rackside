import Foundation

/// Which sessions a series action applies to.
enum SeriesScope: Sendable { case thisOnly, following }

/// Calendar side-effect summary; the store change has already happened.
struct SeriesOutcome: Equatable, Sendable {
    var calendarWarning: String?
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
