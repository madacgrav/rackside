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
private func makeSeries(weeks: Int, eventId: String?, withWorkout: Bool = false) async throws -> SeriesEnv {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let sessions = SwiftDataSessionRepository(modelContainer: container)
    var workoutIds: [UUID] = []
    if withWorkout {
        let template = WorkoutDTO(
            id: UUID(), name: "Legs",
            entries: [WorkoutEntryDTO(id: UUID(), exerciseId: UUID(), order: 0, targetSets: 3, targetReps: 5, targetWeight: 185, targetDuration: nil)],
            createdAt: .now, updatedAt: .now
        )
        try await SwiftDataWorkoutRepository(modelContainer: container).upsert(template)
        workoutIds = [template.id]
    }
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
    let series = try await sessions.scheduleSeries(dto, recurrence: rule, attaching: workoutIds, horizonWeeks: weeks)
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

// MARK: - Detach (Phase 2)

private func actions(_ env: SeriesEnv) -> SeriesActions {
    SeriesActions(sessionRepo: env.sessions, calendar: env.calendar)
}

@Test func detachPushesStandaloneAndRemovesOccurrence() async throws {
    let env = try await makeSeries(weeks: 3, eventId: "evt-s")
    await env.calendar.configure(push: .success("evt-solo"))
    let week2 = env.occurrences[1]

    let (detached, outcome) = try await actions(env).detach(week2, clientName: "Sam")

    #expect(detached.seriesId == nil)
    #expect(detached.eventIdentifier == "evt-solo")
    #expect(outcome.calendarWarning == nil)
    #expect(await env.calendar.removedOccurrences == [FakeCalendar.key("evt-s", week2.startAt)])
    let after = try await env.reload()
    #expect(after[0].seriesId == env.seriesId && after[0].eventIdentifier == "evt-s")
    #expect(after[2].seriesId == env.seriesId && after[2].eventIdentifier == "evt-s")
}

@Test func detachWithoutSeriesEventMakesNoCalendarCalls() async throws {
    let env = try await makeSeries(weeks: 2, eventId: nil)

    let (detached, outcome) = try await actions(env).detach(env.occurrences[0], clientName: "Sam")

    #expect(detached.seriesId == nil)
    #expect(detached.eventIdentifier == nil)
    #expect(outcome.calendarWarning == nil)
    #expect(await env.calendar.removedOccurrences.isEmpty)
}

@Test func detachPushFailureWarns() async throws {
    let env = try await makeSeries(weeks: 2, eventId: "evt-s")
    await env.calendar.configure(push: .failure(Boom()))

    let (detached, outcome) = try await actions(env).detach(env.occurrences[0], clientName: "Sam")

    #expect(detached.seriesId == nil)
    #expect(detached.eventIdentifier == nil)
    #expect(outcome.calendarWarning == SeriesActions.pushWarning)
}

// MARK: - This and following (Phase 3)

/// Logs one set against the session's first workout instance.
private func logSet(on session: SessionDTO, in env: SeriesEnv) async throws {
    let instance = try #require(session.instances.first)
    let entry = try #require(instance.plannedEntries.first)
    try await env.sessions.recordSet(SetRecordDTO(
        id: UUID(), workoutInstanceId: instance.id, exerciseId: entry.exerciseId, setIndex: 0,
        weight: 185, reps: 5, duration: nil, distance: nil, rpe: nil,
        performedAt: .now, createdAt: .now, updatedAt: .now
    ))
}

private func occurrence(_ dto: SessionDTO, status: SessionStatus = .scheduled, sets: Bool = false) -> SeriesOccurrence {
    var copy = dto
    copy.status = status
    return SeriesOccurrence(session: copy, hasLoggedSets: sets)
}

@Test func partitionSkipsNonScheduledAndProtectsLoggedSets() async throws {
    let env = try await makeSeries(weeks: 5, eventId: nil)
    let o = env.occurrences
    let (affected, protected) = partitionFollowing([
        occurrence(o[0]),
        occurrence(o[1], sets: true),
        occurrence(o[2], status: .completed),
        occurrence(o[3], status: .cancelled),
        occurrence(o[4], status: .noShow, sets: true),
    ])
    #expect(affected.map(\.id) == [o[0].id])
    #expect(protected.map(\.id) == [o[1].id])
}

@MainActor
@Test func cancelFollowingFromWeek2Of4() async throws {
    let env = try await makeSeries(weeks: 4, eventId: "evt-s")
    let week2 = env.occurrences[1]

    let result = try await actions(env).cancelFollowing(from: week2, clientName: "Sam")

    #expect(result.changed == 3)
    #expect(result.outcome.calendarWarning == nil)
    let after = try await env.reload()
    #expect(after.map(\.status) == [.scheduled, .cancelled, .cancelled, .cancelled])
    #expect(await env.calendar.endedSeries == [FakeCalendar.key("evt-s", week2.startAt)])
    #expect(await env.calendar.removedOccurrences.isEmpty)
}

@MainActor
@Test func cancelFollowingViaViewModelUsesScope() async throws {
    let env = try await makeSeries(weeks: 3, eventId: "evt-s")
    let vm = env.viewModel(for: env.occurrences[0])

    await vm.setStatus(.cancelled, scope: .following)

    #expect(try await env.reload().allSatisfy { $0.status == .cancelled })
    #expect(await env.calendar.endedSeries == [FakeCalendar.key("evt-s", env.occurrences[0].startAt)])
    #expect(await env.calendar.removed.isEmpty)
}

@Test func cancelFollowingDetachesProtectedOccurrence() async throws {
    let env = try await makeSeries(weeks: 4, eventId: "evt-s", withWorkout: true)
    await env.calendar.configure(push: .success("evt-solo"))
    try await logSet(on: env.occurrences[2], in: env)

    let result = try await actions(env).cancelFollowing(from: env.occurrences[1], clientName: "Sam")

    #expect(result.changed == 2)
    let after = try await env.reload()
    #expect(after.map(\.status) == [.scheduled, .cancelled, .scheduled, .cancelled])
    #expect(after[2].seriesId == nil)
    #expect(after[2].eventIdentifier == "evt-solo")
    // The protected date is covered by endSeries, so no separate removal.
    #expect(await env.calendar.removedOccurrences.isEmpty)
    #expect(await env.calendar.endedSeries == [FakeCalendar.key("evt-s", env.occurrences[1].startAt)])
}

@Test func cancelFollowingLeavesCompletedAlone() async throws {
    let env = try await makeSeries(weeks: 3, eventId: "evt-s")
    try await env.sessions.setStatus(id: env.occurrences[2].id, .completed)

    _ = try await actions(env).cancelFollowing(from: env.occurrences[1], clientName: "Sam")

    let after = try await env.reload()
    #expect(after.map(\.status) == [.scheduled, .cancelled, .completed])
    #expect(after[2].seriesId == env.seriesId)
}

@MainActor
@Test func deleteFollowingFromFirstDeletesAllScheduled() async throws {
    let env = try await makeSeries(weeks: 3, eventId: "evt-s")
    let vm = env.viewModel(for: env.occurrences[0])

    #expect(await vm.delete(scope: .following))

    #expect(try await env.reload().isEmpty)
    #expect(await env.calendar.endedSeries == [FakeCalendar.key("evt-s", env.occurrences[0].startAt)])
}

@Test func followingWithoutEventMakesNoCalendarCalls() async throws {
    let env = try await makeSeries(weeks: 3, eventId: nil)

    _ = try await actions(env).cancelFollowing(from: env.occurrences[0], clientName: "Sam")
    _ = try await actions(env).deleteFollowing(from: env.occurrences[1], clientName: "Sam")

    #expect(await env.calendar.endedSeries.isEmpty)
    #expect(await env.calendar.removedOccurrences.isEmpty)
}
