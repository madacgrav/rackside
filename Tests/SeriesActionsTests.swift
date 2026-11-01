import Foundation
import SwiftData
import Testing
@testable import TrainMe

private struct Boom: Error {}

private struct SeriesEnv {
    let container: ModelContainer
    let sessions: SwiftDataSessionRepository
    let calendar: FakeCalendar
    let seriesId: UUID
    /// Stored occurrences, ascending.
    let occurrences: [SessionDTO]

    @MainActor
    func viewModel(for session: SessionDTO) -> SessionRunViewModel {
        SessionRunViewModel(
            sessionRepo: sessions,
            exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
            clientRepo: SwiftDataClientRepository(modelContainer: container),
            calendar: calendar,
            session: session,
            clientName: "Sam"
        )
    }

    func reload() async throws -> [SessionDTO] {
        try await sessions.sessions(from: .distantPast, to: .distantFuture)
    }
}

/// A weekly series on the start's weekday, `weeks` long, optionally linked to
/// one shared calendar event like `SessionEditView` does after a push.
private func makeSeries(weeks: Int, eventId: String?) async throws -> SeriesEnv {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let sessions = SwiftDataSessionRepository(modelContainer: container)
    let start = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now.addingTimeInterval(86_400))!
    let dto = SessionDTO(
        id: UUID(), clientId: UUID(), startAt: start, endAt: start.addingTimeInterval(3600),
        status: .scheduled, notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    let rule = AppRecurrence(
        frequency: .weekly, interval: 1,
        weekdays: [Calendar.current.component(.weekday, from: start)],
        endDate: nil, occurrenceCount: nil
    )
    let series = try await sessions.scheduleSeries(dto, recurrence: rule, attaching: [], horizonWeeks: weeks)
    if let eventId {
        try await sessions.setEventIdentifierForSeries(series.seriesId, eventId)
    }
    let stored = try await sessions.sessions(from: .distantPast, to: .distantFuture)
    return SeriesEnv(container: container, sessions: sessions, calendar: FakeCalendar(), seriesId: series.seriesId, occurrences: stored)
}

@MainActor
@Test func cancelOccurrenceCancelsOneAndRemovesThatDate() async throws {
    let env = try await makeSeries(weeks: 3, eventId: "evt-s")
    let week2 = env.occurrences[1]
    let vm = env.viewModel(for: week2)

    await vm.setStatus(.cancelled)

    let after = try await env.reload()
    #expect(after.map(\.status) == [.scheduled, .cancelled, .scheduled])
    #expect(after.allSatisfy { $0.eventIdentifier == "evt-s" && $0.seriesId == env.seriesId })
    #expect(await env.calendar.removedOccurrences == [FakeCalendar.key("evt-s", week2.startAt)])
    #expect(await env.calendar.removed.isEmpty)
    #expect(vm.calendarWarning == nil)
}

@MainActor
@Test func deleteOccurrenceDeletesOneAndRemovesThatDate() async throws {
    let env = try await makeSeries(weeks: 3, eventId: "evt-s")
    let week2 = env.occurrences[1]
    let vm = env.viewModel(for: week2)

    #expect(await vm.delete())

    let after = try await env.reload()
    #expect(after.map(\.id) == [env.occurrences[0].id, env.occurrences[2].id])
    #expect(await env.calendar.removedOccurrences == [FakeCalendar.key("evt-s", week2.startAt)])
    #expect(await env.calendar.removed.isEmpty)
}

@MainActor
@Test func seriesWithoutEventMakesNoCalendarCalls() async throws {
    let env = try await makeSeries(weeks: 3, eventId: nil)

    await env.viewModel(for: env.occurrences[0]).setStatus(.cancelled)
    #expect(await env.viewModel(for: env.occurrences[1]).delete())

    #expect(await env.calendar.removedOccurrences.isEmpty)
    #expect(await env.calendar.removed.isEmpty)
}

@MainActor
@Test func calendarFailureWarnsButKeepsStoreChange() async throws {
    let env = try await makeSeries(weeks: 2, eventId: "evt-s")
    await env.calendar.configure(removeError: Boom())
    let vm = env.viewModel(for: env.occurrences[0])

    await vm.setStatus(.cancelled)

    #expect(try await env.reload().first?.status == .cancelled)
    #expect(vm.calendarWarning == SeriesActions.removeWarning)
    #expect(vm.errorMessage == nil)
}

@Test func pickOccurrenceMatchesIdAndClosestDate() {
    let target = Date(timeIntervalSince1970: 1_800_000_000)
    let candidates: [(eventIdentifier: String?, occurrenceDate: Date?)] = [
        ("other", target),
        ("evt", nil),
        ("evt", target.addingTimeInterval(2 * 3600)),
        ("evt", target.addingTimeInterval(30 * 60)),
    ]
    #expect(pickOccurrence(candidates, eventIdentifier: "evt", target: target) == 3)
    #expect(pickOccurrence(Array(candidates.prefix(3)), eventIdentifier: "evt", target: target) == nil)
}
