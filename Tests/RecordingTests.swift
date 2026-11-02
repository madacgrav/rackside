import Foundation
import Testing
@testable import Rackside

private struct Env {
    let sessions: SwiftDataSessionRepository
    let workouts: SwiftDataWorkoutRepository
    let clientId = UUID()
    let exerciseId = UUID()
    var sessionId = UUID()
    var instanceId: UUID!
}

private func makeEnvWithScheduledSession() async throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    var env = Env(
        sessions: SwiftDataSessionRepository(modelContainer: container),
        workouts: SwiftDataWorkoutRepository(modelContainer: container)
    )
    let template = WorkoutDTO(
        id: UUID(), name: "Legs",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: env.exerciseId, order: 0, targetSets: 3, targetReps: 5, targetWeight: 185, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await env.workouts.upsert(template)

    let dto = SessionDTO(
        id: env.sessionId, clientId: env.clientId, startAt: .now,
        endAt: Date.now.addingTimeInterval(3600), status: .scheduled,
        notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    try await env.sessions.schedule(dto, attaching: [template.id])
    env.instanceId = try await env.sessions.get(id: dto.id)!.instances.first!.id
    return env
}

private func set(_ env: Env, index: Int, weight: Double, performedAt: Date = .now) -> SetRecordDTO {
    SetRecordDTO(
        id: UUID(), workoutInstanceId: env.instanceId, exerciseId: env.exerciseId,
        setIndex: index, weight: weight, reps: 5, duration: nil, distance: nil,
        rpe: nil, performedAt: performedAt, createdAt: .now, updatedAt: .now
    )
}

@Test func recordSetsAgainstInstance() async throws {
    let env = try await makeEnvWithScheduledSession()

    try await env.sessions.recordSet(set(env, index: 0, weight: 185))
    try await env.sessions.recordSet(set(env, index: 1, weight: 190))

    let sets = try await env.sessions.setsFor(instanceId: env.instanceId)
    #expect(sets.count == 2)
    #expect(sets.map(\.setIndex) == [0, 1])
    #expect(sets.map(\.weight) == [185, 190])
}

@Test func lastSetReturnsMostRecentAcrossSessions() async throws {
    let env = try await makeEnvWithScheduledSession()
    let earlier = Date.now.addingTimeInterval(-86400)

    try await env.sessions.recordSet(set(env, index: 0, weight: 175, performedAt: earlier))
    try await env.sessions.recordSet(set(env, index: 1, weight: 195, performedAt: .now))

    let last = try await env.sessions.lastSet(clientId: env.clientId, exerciseId: env.exerciseId)
    #expect(last?.weight == 195)

    // Unknown client / exercise yields nil.
    #expect(try await env.sessions.lastSet(clientId: UUID(), exerciseId: env.exerciseId) == nil)
    #expect(try await env.sessions.lastSet(clientId: env.clientId, exerciseId: UUID()) == nil)
}

@Test func deleteSetRemovesRecord() async throws {
    let env = try await makeEnvWithScheduledSession()
    let record = set(env, index: 0, weight: 185)
    try await env.sessions.recordSet(record)
    try await env.sessions.deleteSet(id: record.id)
    #expect(try await env.sessions.setsFor(instanceId: env.instanceId).isEmpty)
}
