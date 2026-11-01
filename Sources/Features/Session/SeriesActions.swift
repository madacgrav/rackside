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

    func cancelOccurrence(_ session: SessionDTO) async throws -> SeriesOutcome {
        try await sessionRepo.setStatus(id: session.id, .cancelled)
        return await removeFromEvent(session)
    }

    func deleteOccurrence(_ session: SessionDTO) async throws -> SeriesOutcome {
        try await sessionRepo.delete(id: session.id)
        return await removeFromEvent(session)
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
