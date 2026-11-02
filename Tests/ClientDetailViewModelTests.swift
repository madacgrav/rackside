import Foundation
import Testing
@testable import Rackside

private func session(hoursFromNow: Double, status: SessionStatus = .scheduled) -> SessionDTO {
    let start = Date.now.addingTimeInterval(hoursFromNow * 3600)
    return SessionDTO(
        id: UUID(), clientId: UUID(), startAt: start, endAt: start.addingTimeInterval(3600),
        status: status, notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
}

@Test @MainActor func splitsUpcomingFromRecent() {
    let futureScheduled = session(hoursFromNow: 48)
    let soonScheduled = session(hoursFromNow: 2)
    let futureCancelled = session(hoursFromNow: 24, status: .cancelled)
    let pastCompleted = session(hoursFromNow: -24, status: .completed)
    let pastScheduled = session(hoursFromNow: -48) // never marked: counts as history

    let split = ClientDetailViewModel.splitSessions(
        [futureScheduled, pastCompleted, futureCancelled, soonScheduled, pastScheduled],
        now: .now
    )

    #expect(split.upcoming.map(\.id) == [soonScheduled.id, futureScheduled.id])
    #expect(split.recent.map(\.id) == [futureCancelled.id, pastCompleted.id, pastScheduled.id])
}

@Test @MainActor func recentIsCapped() {
    let many = (1...20).map { session(hoursFromNow: -Double($0), status: .completed) }
    let split = ClientDetailViewModel.splitSessions(many, now: .now)
    #expect(split.recent.count == ClientDetailViewModel.recentLimit)
    #expect(split.recent.first?.id == many.first?.id)
}
