import EventKit
import Foundation
import SwiftData
import Testing
@testable import TrainMe

actor FakeCalendar: CalendarSyncing {
    private(set) var removed: [String] = []
    private(set) var updated: [String] = []
    /// `key(eventIdentifier, occurrenceStart)` per removed occurrence.
    private(set) var removedOccurrences: [String] = []
    /// `key(eventIdentifier, occurrenceStart)` per `endSeries` call.
    private(set) var endedSeries: [String] = []
    /// Start and recurrence of every push, in order (two arrays keep the actor
    /// state `Sendable` without a new type).
    private(set) var pushedStarts: [Date] = []
    private(set) var pushedRecurrences: [AppRecurrence?] = []
    private var pushResult: Result<String?, any Error> = .success("evt-new")
    /// nil → echo the identifier back, like a successful in-place update.
    private var updateResult: Result<String?, any Error>?
    private var removeError: (any Error)?
    private var status: EKAuthorizationStatus = .fullAccess

    func configure(
        push: Result<String?, any Error>? = nil,
        update: Result<String?, any Error>? = nil,
        removeError: (any Error)? = nil,
        status: EKAuthorizationStatus? = nil
    ) {
        if let push { pushResult = push }
        if let update { updateResult = update }
        self.removeError = removeError
        if let status { self.status = status }
    }

    func requestAccess() async -> Bool { status == .fullAccess }

    func authorizationStatus() async -> EKAuthorizationStatus { status }

    func push(_ session: SessionDTO, clientName: String, recurrence: AppRecurrence?) async throws -> String? {
        pushedStarts.append(session.startAt)
        pushedRecurrences.append(recurrence)
        return try pushResult.get()
    }

    func update(eventIdentifier: String, _ session: SessionDTO, clientName: String) async throws -> String? {
        updated.append(eventIdentifier)
        if let updateResult { return try updateResult.get() }
        return eventIdentifier
    }

    func remove(eventIdentifier: String) async throws {
        if let removeError { throw removeError }
        removed.append(eventIdentifier)
    }

    func removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws {
        if let removeError { throw removeError }
        removedOccurrences.append(Self.key(eventIdentifier, occurrenceStart))
    }

    func endSeries(eventIdentifier: String, before occurrenceStart: Date) async throws {
        if let removeError { throw removeError }
        endedSeries.append(Self.key(eventIdentifier, occurrenceStart))
    }

    /// Stable string for an (event, occurrence date) pair, so recorded calls
    /// stay `Sendable` and `Equatable` without a new type.
    static func key(_ eventIdentifier: String, _ date: Date) -> String {
        "\(eventIdentifier)@\(date.timeIntervalSince1970)"
    }
}

@MainActor
private final class Flag {
    var raised = false
}

@MainActor
@Test func deleteRemovesCalendarEventAndSession() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let sessions = SwiftDataSessionRepository(modelContainer: container)
    let dto = SessionDTO(
        id: UUID(), clientId: UUID(), startAt: .now, endAt: .now.addingTimeInterval(3600),
        status: .scheduled, notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    try await sessions.schedule(dto, attaching: [])
    try await sessions.setEventIdentifier(id: dto.id, "evt-1")
    let stored = try #require(try await sessions.get(id: dto.id))
    let calendar = FakeCalendar()
    let reloaded = Flag()

    let vm = SessionRunViewModel(
        sessionRepo: sessions,
        exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
        clientRepo: SwiftDataClientRepository(modelContainer: container),
        calendar: calendar,
        session: stored,
        clientName: "Sam",
        onStatusChanged: { reloaded.raised = true }
    )
    #expect(!vm.isSeries)

    await vm.delete()

    #expect(await calendar.removed == ["evt-1"])
    let after = try await sessions.get(id: dto.id)
    #expect(after == nil)
    #expect(reloaded.raised)
}

/// Wraps a real repository and fails selected calls.
actor FailingSessionRepo: SessionRepository {
    struct Boom: Error {}
    let inner: SwiftDataSessionRepository
    private var failDelete = false
    private var failSetStatus = false
    private var failRecordSet = false

    init(inner: SwiftDataSessionRepository) { self.inner = inner }

    func fail(delete: Bool = false, setStatus: Bool = false, recordSet: Bool = false) {
        failDelete = delete
        failSetStatus = setStatus
        failRecordSet = recordSet
    }

    func delete(id: UUID) async throws {
        if failDelete { throw Boom() }
        try await inner.delete(id: id)
    }
    func setStatus(id: UUID, _ status: SessionStatus) async throws {
        if failSetStatus { throw Boom() }
        try await inner.setStatus(id: id, status)
    }
    func recordSet(_ dto: SetRecordDTO) async throws {
        if failRecordSet { throw Boom() }
        try await inner.recordSet(dto)
    }

    // Everything else forwards verbatim.
    func schedule(_ dto: SessionDTO, attaching workoutIds: [UUID]) async throws {
        try await inner.schedule(dto, attaching: workoutIds)
    }
    func scheduleSeries(_ dto: SessionDTO, recurrence: AppRecurrence, attaching workoutIds: [UUID], horizonWeeks: Int) async throws -> ScheduledSeries {
        try await inner.scheduleSeries(dto, recurrence: recurrence, attaching: workoutIds, horizonWeeks: horizonWeeks)
    }
    func get(id: UUID) async throws -> SessionDTO? { try await inner.get(id: id) }
    func sessions(from: Date, to: Date) async throws -> [SessionDTO] { try await inner.sessions(from: from, to: to) }
    func upcoming(after: Date, limit: Int) async throws -> [SessionDTO] { try await inner.upcoming(after: after, limit: limit) }
    func forClient(_ clientId: UUID) async throws -> [SessionDTO] { try await inner.forClient(clientId) }
    func update(_ dto: SessionDTO) async throws { try await inner.update(dto) }
    func setEventIdentifier(id: UUID, _ eventIdentifier: String?) async throws {
        try await inner.setEventIdentifier(id: id, eventIdentifier)
    }
    func setEventIdentifierForSeries(_ seriesId: UUID, _ eventIdentifier: String?) async throws {
        try await inner.setEventIdentifierForSeries(seriesId, eventIdentifier)
    }
    func detach(id: UUID) async throws { try await inner.detach(id: id) }
    func seriesOccurrences(seriesId: UUID, from: Date) async throws -> [SeriesOccurrence] {
        try await inner.seriesOccurrences(seriesId: seriesId, from: from)
    }
    func setStatus(ids: [UUID], _ status: SessionStatus) async throws { try await inner.setStatus(ids: ids, status) }
    func delete(ids: [UUID]) async throws { try await inner.delete(ids: ids) }
    func resegment(
        ids: [UUID], newSeriesId: UUID, recurrence: AppRecurrence,
        hour: Int, minute: Int, duration: TimeInterval, notes: String?
    ) async throws {
        try await inner.resegment(
            ids: ids, newSeriesId: newSeriesId, recurrence: recurrence,
            hour: hour, minute: minute, duration: duration, notes: notes
        )
    }
    func updateNotes(id: UUID, _ notes: String?) async throws { try await inner.updateNotes(id: id, notes) }
    func completedCount(since: Date?) async throws -> Int { try await inner.completedCount(since: since) }
    func deleteSet(id: UUID) async throws { try await inner.deleteSet(id: id) }
    func setsFor(instanceId: UUID) async throws -> [SetRecordDTO] { try await inner.setsFor(instanceId: instanceId) }
    func lastSet(clientId: UUID, exerciseId: UUID) async throws -> SetRecordDTO? {
        try await inner.lastSet(clientId: clientId, exerciseId: exerciseId)
    }
}

private struct FailingEnv {
    let container: ModelContainer
    let real: SwiftDataSessionRepository
    let repo: FailingSessionRepo
    let calendar: FakeCalendar
    let dto: SessionDTO
    let instanceId: UUID
    let exerciseId: UUID
    let vm: SessionRunViewModel
}

/// A stored session with one workout instance, an event identifier, and a
/// view model wired to a failing repository wrapper.
@MainActor
private func makeFailingEnv() async throws -> FailingEnv {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let real = SwiftDataSessionRepository(modelContainer: container)
    let workouts = SwiftDataWorkoutRepository(modelContainer: container)
    let exerciseId = UUID()
    let template = WorkoutDTO(
        id: UUID(), name: "Legs",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: 3, targetReps: 5, targetWeight: 185, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await workouts.upsert(template)
    let dto = SessionDTO(
        id: UUID(), clientId: UUID(), startAt: .now, endAt: .now.addingTimeInterval(3600),
        status: .scheduled, notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    try await real.schedule(dto, attaching: [template.id])
    try await real.setEventIdentifier(id: dto.id, "evt-1")
    let stored = try #require(try await real.get(id: dto.id))
    let repo = FailingSessionRepo(inner: real)
    let calendar = FakeCalendar()
    let vm = SessionRunViewModel(
        sessionRepo: repo,
        exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
        clientRepo: SwiftDataClientRepository(modelContainer: container),
        calendar: calendar,
        session: stored,
        clientName: "Sam"
    )
    return FailingEnv(
        container: container, real: real, repo: repo, calendar: calendar, dto: stored,
        instanceId: stored.instances.first!.id, exerciseId: exerciseId, vm: vm
    )
}

@MainActor
@Test func failedDeleteReturnsFalseAndSetsError() async throws {
    let env = try await makeFailingEnv()
    await env.repo.fail(delete: true)

    let ok = await env.vm.delete()

    #expect(!ok)
    #expect(env.vm.errorMessage != nil)
    #expect(try await env.real.get(id: env.dto.id) != nil)
}

@MainActor
@Test func failedSetStatusKeepsEventIdentifier() async throws {
    let env = try await makeFailingEnv()
    await env.repo.fail(setStatus: true)

    await env.vm.setStatus(.cancelled)

    #expect(env.vm.errorMessage != nil)
    #expect(try await env.real.get(id: env.dto.id)?.eventIdentifier == "evt-1")
    #expect(await env.calendar.removed.isEmpty)
    #expect(try await env.real.get(id: env.dto.id)?.status == .scheduled)
}

@MainActor
@Test func failedRecordLeavesSetsUnchanged() async throws {
    let env = try await makeFailingEnv()
    await env.vm.load()
    let before = env.vm.recordedSets
    await env.repo.fail(recordSet: true)

    await env.vm.record(instanceId: env.instanceId, exerciseId: env.exerciseId, weight: 100, reps: 5, duration: nil, distance: nil)

    #expect(env.vm.errorMessage != nil)
    #expect(env.vm.recordedSets == before)
    #expect(try await env.real.setsFor(instanceId: env.instanceId).isEmpty)
}

// MARK: - Inline set table (Phase 3)

private struct SessionEnv {
    let sessions: SwiftDataSessionRepository
    let exerciseId: UUID
    let instanceId: UUID
    let entry: PlannedEntryDTO
    let vm: SessionRunViewModel
}

/// One exercise with the given metrics, a 3×8 @ 100 template attached to a
/// stored session, and a view model over real repositories.
@MainActor
private func makeSessionEnv(metrics: MetricSet = [.weight, .reps]) async throws -> SessionEnv {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let sessions = SwiftDataSessionRepository(modelContainer: container)
    let exercises = SwiftDataExerciseRepository(modelContainer: container)
    let clients = SwiftDataClientRepository(modelContainer: container)
    let workouts = SwiftDataWorkoutRepository(modelContainer: container)
    let exerciseId = UUID()
    _ = try await exercises.create(ExerciseDTO(
        id: exerciseId, name: "Bench", category: .strength,
        metrics: metrics, defaultUnit: .lb, isCustom: true, createdAt: .now, updatedAt: .now
    ))
    let template = WorkoutDTO(
        id: UUID(), name: "W",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: 0, targetSets: 3, targetReps: 8, targetWeight: 100, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await workouts.upsert(template)
    let dto = SessionDTO(
        id: UUID(), clientId: UUID(), startAt: .now, endAt: .now.addingTimeInterval(3600),
        status: .scheduled, notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    try await sessions.schedule(dto, attaching: [template.id])
    let stored = try #require(try await sessions.get(id: dto.id))
    let instance = try #require(stored.instances.first)
    let vm = SessionRunViewModel(
        sessionRepo: sessions, exerciseRepo: exercises, clientRepo: clients,
        calendar: FakeCalendar(), session: stored, clientName: "C"
    )
    return SessionEnv(
        sessions: sessions, exerciseId: exerciseId, instanceId: instance.id,
        entry: try #require(instance.plannedEntries.first), vm: vm
    )
}

@MainActor
@Test func previousSetsLoadedPerExercise() async throws {
    let env = try await makeSessionEnv()
    try await env.sessions.recordSet(SetRecordDTO(
        id: UUID(), workoutInstanceId: env.instanceId, exerciseId: env.exerciseId, setIndex: 0,
        weight: 95, reps: 8, duration: nil, distance: nil, rpe: nil,
        performedAt: .now, createdAt: .now, updatedAt: .now
    ))

    await env.vm.load()

    #expect(env.vm.previousSets[env.exerciseId]?.weight == 95)
    #expect(env.vm.plannedSetCount == 3)
    #expect(env.vm.loggedSetCount == 1)
    #expect(abs(env.vm.progress - 1.0 / 3.0) < 0.001)
}

@MainActor
@Test func progressReflectsLoggedOverPlanned() async throws {
    let env = try await makeSessionEnv()
    await env.vm.load()
    #expect(env.vm.progress == 0)
    let draft = SetDraft(target: env.entry, metrics: [.weight, .reps])

    for _ in 0..<3 {
        await env.vm.record(draft: draft, instanceId: env.instanceId, exerciseId: env.exerciseId)
    }
    #expect(env.vm.loggedSetCount == 3)
    #expect(env.vm.progress == 1.0)

    // A fourth set beyond the plan never pushes progress past 100%.
    await env.vm.record(draft: draft, instanceId: env.instanceId, exerciseId: env.exerciseId)
    #expect(env.vm.sets(instanceId: env.instanceId, exerciseId: env.exerciseId).count == 4)
    #expect(env.vm.progress == 1.0)
}

@MainActor
@Test func recordDraftOmitsMetricsNotInExercise() async throws {
    let env = try await makeSessionEnv(metrics: [.reps])
    await env.vm.load()
    #expect(env.vm.lastLoggedSetId == nil)
    var draft = SetDraft(target: env.entry, metrics: [.weight, .reps])
    draft.weight = 50
    draft.reps = 8

    await env.vm.record(draft: draft, instanceId: env.instanceId, exerciseId: env.exerciseId)

    let stored = try #require(try await env.sessions.setsFor(instanceId: env.instanceId).first)
    #expect(stored.weight == nil)
    #expect(stored.reps == 8)
    #expect(env.vm.errorMessage == nil)
    #expect(env.vm.lastLoggedSetId != nil)
}
