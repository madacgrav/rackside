import Foundation
import SwiftData
import Testing
@testable import TrainMe

/// Anchor for locating the test bundle's fixture resources.
private final class BundleToken {}

private struct Env {
    let container: ModelContainer
    let archive: DataArchiveActor
    let clients: SwiftDataClientRepository
    let exercises: SwiftDataExerciseRepository
    let workouts: SwiftDataWorkoutRepository
    let sessions: SwiftDataSessionRepository
}

private func makeEnv() throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return Env(
        container: container,
        archive: DataArchiveActor(modelContainer: container),
        clients: SwiftDataClientRepository(modelContainer: container),
        exercises: SwiftDataExerciseRepository(modelContainer: container),
        workouts: SwiftDataWorkoutRepository(modelContainer: container),
        sessions: SwiftDataSessionRepository(modelContainer: container)
    )
}

/// Builds a populated store: client, exercise, workout, completed session with sets.
private func populate(_ env: Env) async throws {
    try await env.clients.upsert(ClientDTO(
        id: UUID(), name: "Sam", phoneE164: "+15551234567",
        goal: "Strength", injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    ))
    let exercise = try await env.exercises.create(ExerciseDTO(
        id: UUID(), name: "Back Squat", category: .strength,
        metrics: [.weight, .reps, .sets], defaultUnit: .lb,
        isCustom: false, createdAt: .now, updatedAt: .now
    ))
    let workout = WorkoutDTO(
        id: UUID(), name: "Legs",
        entries: [WorkoutEntryDTO(id: UUID(), exerciseId: exercise.id, order: 0, targetSets: 3, targetReps: 5, targetWeight: 185, targetDuration: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await env.workouts.upsert(workout)
    let clientId = try await env.clients.all().first!.id
    let session = SessionDTO(
        id: UUID(), clientId: clientId, startAt: .now,
        endAt: Date.now.addingTimeInterval(3600), status: .scheduled,
        notes: "notes", instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    try await env.sessions.schedule(session, attaching: [workout.id])
    let instanceId = try await env.sessions.get(id: session.id)!.instances.first!.id
    try await env.sessions.recordSet(SetRecordDTO(
        id: UUID(), workoutInstanceId: instanceId, exerciseId: exercise.id,
        setIndex: 0, weight: 185, reps: 5, duration: nil, distance: nil,
        rpe: nil, performedAt: .now, createdAt: .now, updatedAt: .now
    ))
    try await env.sessions.setStatus(id: session.id, .completed)
}

@Test func exportThenReplaceImportRestoresIdenticalGraph() async throws {
    let source = try makeEnv()
    try await populate(source)
    let url = try await source.archive.export()
    defer { try? FileManager.default.removeItem(at: url) }

    // Import into a completely fresh store.
    let dest = try makeEnv()
    try await dest.archive.importArchive(url: url, mode: .replace)

    let clients = try await dest.clients.all()
    #expect(clients.count == 1)
    #expect(clients.first?.name == "Sam")
    #expect(clients.first?.goal == "Strength")

    #expect(try await dest.exercises.count() == 1)
    #expect(try await dest.workouts.all().count == 1)
    #expect(try await dest.workouts.all().first?.entries.count == 1)

    let sessions = try await dest.sessions.forClient(clients.first!.id)
    #expect(sessions.count == 1)
    #expect(sessions.first?.status == .completed)
    #expect(sessions.first?.instances.count == 1)
    let instanceId = sessions.first!.instances.first!.id
    let sets = try await dest.sessions.setsFor(instanceId: instanceId)
    #expect(sets.count == 1)
    #expect(sets.first?.weight == 185)

    // Source and destination exports match structurally (same ids round-trip).
    let sourceSessions = try await source.sessions.forClient(clients.first!.id)
    #expect(sourceSessions.first?.id == sessions.first?.id)
    #expect(sourceSessions.first?.instances.first?.id == instanceId)
}

@Test func mergeUpsertsById() async throws {
    let env = try makeEnv()
    try await populate(env)
    let url = try await env.archive.export()
    defer { try? FileManager.default.removeItem(at: url) }

    // Locally rename the client, then merge the export back: archive wins.
    var client = try await env.clients.all().first!
    let originalName = client.name
    client.name = "Renamed Locally"
    try await env.clients.upsert(client)

    // Add a local-only client that must survive the merge.
    try await env.clients.upsert(ClientDTO(
        id: UUID(), name: "Local Only", phoneE164: "+15550000000",
        goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    ))

    try await env.archive.importArchive(url: url, mode: .merge)

    let clients = try await env.clients.all()
    #expect(clients.count == 2)
    #expect(clients.contains { $0.name == originalName })
    #expect(clients.contains { $0.name == "Local Only" })
    #expect(!clients.contains { $0.name == "Renamed Locally" })
    // No duplication of graph entities on merge.
    #expect(try await env.workouts.all().count == 1)
}

@Test func newerSchemaVersionRejected() async throws {
    let env = try makeEnv()
    let data = Data(#"{"schemaVersion": 99, "exportedAt": "2030-01-01T00:00:00Z"}"#.utf8)

    await #expect(throws: ArchiveError.newerThanApp(99)) {
        try await env.archive.importData(data, mode: .merge)
    }
}

@Test func unreadableDataRejected() async throws {
    let env = try makeEnv()
    await #expect(throws: ArchiveError.unreadable) {
        try await env.archive.importData(Data("not json".utf8), mode: .merge)
    }
}

// GOLDEN FIXTURE TEST — the backward-compatibility contract.
// Tests/Fixtures/export-v1.json is a frozen v1 export and must import
// successfully in every future version of the app. Never regenerate it.
@Test func goldenV1FixtureImports() async throws {
    let bundle = Bundle(for: BundleToken.self)
    let url = try #require(bundle.url(forResource: "export-v1", withExtension: "json"))
    let data = try Data(contentsOf: url)

    let env = try makeEnv()
    try await env.archive.importData(data, mode: .replace)

    let clients = try await env.clients.allIncludingArchived()
    #expect(clients.count == 2)
    #expect(clients.contains { $0.name == "Sam Jones" && $0.injuries == "Left knee" })

    #expect(try await env.exercises.count() == 3)
    let workout = try await env.workouts.all().first
    #expect(workout?.name == "Leg Day A")
    #expect(workout?.entries.count == 2)
    #expect(workout?.entries.first?.targetWeight == 185)

    let samId = clients.first { $0.name == "Sam Jones" }!.id
    let sessions = try await env.sessions.forClient(samId)
    #expect(sessions.count == 1)
    #expect(sessions.first?.status == .completed)
    let instanceId = sessions.first!.instances.first!.id
    let sets = try await env.sessions.setsFor(instanceId: instanceId)
    #expect(sets.count == 2)
    #expect(sets.map(\.weight) == [185, 195])
}

@Test func profileFieldsRoundTrip() async throws {
    let source = try makeEnv()
    // Whole seconds: the archive's ISO 8601 dates drop fractions.
    let dob = Date(timeIntervalSince1970: 650_000_000)
    let client = ClientDTO(
        id: UUID(), name: "Pat", phoneE164: "+15551230000",
        goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: dob, updatedAt: dob,
        dateOfBirth: dob, emergencyName: "Lee", emergencyRelationship: "Partner",
        emergencyPhoneE164: "+15551239999", physicianName: "Dr. Ng", physicianPhoneE164: "+15551238888",
        occupation: "Chef", trainingHistory: "Ran a marathon in 2019", availability: "Mornings"
    )
    try await source.clients.upsert(client)
    let data = try await source.archive.exportData()

    let dest = try makeEnv()
    try await dest.archive.importData(data, mode: .replace)
    let restored = try #require(try await dest.clients.all().first)
    #expect(restored.dateOfBirth == dob)
    #expect(restored.emergencyName == "Lee")
    #expect(restored.emergencyRelationship == "Partner")
    #expect(restored.emergencyPhoneE164 == "+15551239999")
    #expect(restored.physicianName == "Dr. Ng")
    #expect(restored.physicianPhoneE164 == "+15551238888")
    #expect(restored.occupation == "Chef")
    #expect(restored.trainingHistory == "Ran a marathon in 2019")
    #expect(restored.availability == "Mornings")
}

@Test func exportWritesSchemaVersion2() async throws {
    let env = try makeEnv()
    let data = try await env.archive.exportData()
    let decoder = JSONDecoder()
    #expect(try decoder.decode(VersionProbe.self, from: data).schemaVersion == 2)
}
