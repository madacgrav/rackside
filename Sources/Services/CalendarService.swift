import EventKit
import Foundation

/// Maps the app's recurrence model to EventKit. Pure function — unit-testable
/// without an event store.
func makeEKRecurrenceRule(_ rule: AppRecurrence) -> EKRecurrenceRule {
    let frequency: EKRecurrenceFrequency = switch rule.frequency {
    case .daily: .daily
    case .weekly: .weekly
    }
    let days: [EKRecurrenceDayOfWeek]? = rule.weekdays.isEmpty
        ? nil
        : rule.weekdays.compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
    let end: EKRecurrenceEnd? = if let count = rule.occurrenceCount {
        EKRecurrenceEnd(occurrenceCount: count)
    } else if let endDate = rule.endDate {
        EKRecurrenceEnd(end: endDate)
    } else {
        nil
    }
    return EKRecurrenceRule(
        recurrenceWith: frequency,
        interval: max(1, rule.interval),
        daysOfTheWeek: days,
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: end
    )
}

/// Picks the occurrence of a recurring event whose original date matches
/// `target`. EventKit keeps `occurrenceDate` at the original start even after an
/// occurrence is moved, so this is stable for detached occurrences. Tolerates a
/// one-hour skew (DST) and prefers the closest. Pure function for testing.
func pickOccurrence(
    _ candidates: [(eventIdentifier: String?, occurrenceDate: Date?)],
    eventIdentifier: String,
    target: Date
) -> Int? {
    candidates.indices
        .filter { candidates[$0].eventIdentifier == eventIdentifier }
        .compactMap { i in candidates[i].occurrenceDate.map { (i, abs($0.timeIntervalSince(target))) } }
        .filter { $0.1 <= 3600 }
        .min { $0.1 < $1.1 }?.0
}

enum CalendarError: Error, Equatable {
    /// No default calendar and no calendar that allows modifications.
    case noWritableCalendar
}

protocol CalendarSyncing: Sendable {
    func requestAccess() async -> Bool
    func authorizationStatus() async -> EKAuthorizationStatus
    /// One-way push to the default calendar. Returns the eventIdentifier to
    /// store for later update/removal.
    func push(_ session: SessionDTO, clientName: String, recurrence: AppRecurrence?) async throws -> String?
    /// Edits the pushed event in place. Returns the identifier to store: the
    /// same one, a new one if the event had vanished and was re-pushed, or nil
    /// without calendar access.
    func update(eventIdentifier: String, _ session: SessionDTO, clientName: String) async throws -> String?
    func remove(eventIdentifier: String) async throws
    /// Removes one occurrence of a recurring event (EKSpan.thisEvent). No-op
    /// when the event or occurrence is gone.
    func removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws
    /// Ends a recurring event before the given occurrence (EKSpan.futureEvents
    /// on that occurrence). On the first occurrence this removes the whole event.
    func endSeries(eventIdentifier: String, before occurrenceStart: Date) async throws
}

actor EventKitCalendarService: CalendarSyncing {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            Log.calendar.error("requestFullAccessToEvents failed: \(error.localizedDescription)")
            return false
        }
    }

    func authorizationStatus() async -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// The default calendar when the user has one, otherwise the first calendar
    /// that accepts new events. Throws when neither exists.
    private func writableCalendar() throws -> EKCalendar {
        if let preferred = store.defaultCalendarForNewEvents { return preferred }
        if let fallback = store.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            Log.calendar.info("No default calendar; using \(fallback.title)")
            return fallback
        }
        throw CalendarError.noWritableCalendar
    }

    func push(_ session: SessionDTO, clientName: String, recurrence: AppRecurrence?) async throws -> String? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = "Training: \(clientName)"
        event.startDate = session.startAt
        event.endDate = session.endAt
        event.notes = session.notes
        event.calendar = try writableCalendar()
        if let recurrence {
            event.recurrenceRules = [makeEKRecurrenceRule(recurrence)]
        }
        try store.save(event, span: .futureEvents, commit: true)
        return event.eventIdentifier
    }

    func update(eventIdentifier: String, _ session: SessionDTO, clientName: String) async throws -> String? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            // The user deleted or moved it; re-create so the calendar matches the app.
            return try await push(session, clientName: clientName, recurrence: nil)
        }
        event.title = "Training: \(clientName)"
        event.startDate = session.startAt
        event.endDate = session.endAt
        event.notes = session.notes
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func remove(eventIdentifier: String) async throws {
        guard let event = store.event(withIdentifier: eventIdentifier) else { return }
        try store.remove(event, span: .futureEvents, commit: true)
    }

    func removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws {
        guard let event = occurrence(eventIdentifier, at: occurrenceStart) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func endSeries(eventIdentifier: String, before occurrenceStart: Date) async throws {
        guard let event = occurrence(eventIdentifier, at: occurrenceStart) else { return }
        try store.remove(event, span: .futureEvents, commit: true)
    }

    /// Searches a day either side of the date: `event(withIdentifier:)` returns
    /// the first occurrence of a recurring event, not this one.
    private func occurrence(_ eventIdentifier: String, at start: Date) -> EKEvent? {
        let window = store.predicateForEvents(
            withStart: start.addingTimeInterval(-86_400),
            end: start.addingTimeInterval(86_400),
            calendars: nil
        )
        let events = store.events(matching: window)
        let pick = pickOccurrence(
            events.map { ($0.eventIdentifier, $0.occurrenceDate) },
            eventIdentifier: eventIdentifier,
            target: start
        )
        return pick.map { events[$0] }
    }
}
