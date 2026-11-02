import Foundation
import Testing
@testable import Rackside

private func makeRepo() throws -> SwiftDataWorkoutRepository {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return SwiftDataWorkoutRepository(modelContainer: container)
}

private func entry(exerciseId: UUID = UUID(), order: Int, sets: Int? = 3, reps: Int? = 5, weight: Double? = 185) -> WorkoutEntryDTO {
    WorkoutEntryDTO(id: UUID(), exerciseId: exerciseId, order: order, targetSets: sets, targetReps: reps, targetWeight: weight, targetDuration: nil)
}

@Test func buildTemplateRoundTrip() async throws {
    let repo = try makeRepo()
    let dto = WorkoutDTO(
        id: UUID(), name: "Leg Day A",
        entries: [entry(order: 0), entry(order: 1, sets: 3, reps: 12, weight: nil)],
        createdAt: .now, updatedAt: .now
    )
    try await repo.upsert(dto)

    let fetched = try await repo.get(id: dto.id)
    #expect(fetched?.name == "Leg Day A")
    #expect(fetched?.entries.count == 2)
    #expect(fetched?.entries[0].order == 0)
    #expect(fetched?.entries[0].targetWeight == 185)
    #expect(fetched?.entries[1].targetReps == 12)
}

@Test func duplicateIsDeepCopyWithNewIds() async throws {
    let repo = try makeRepo()
    let exerciseId = UUID()
    let original = WorkoutDTO(
        id: UUID(), name: "Push Day",
        entries: [entry(exerciseId: exerciseId, order: 0)],
        createdAt: .now, updatedAt: .now
    )
    try await repo.upsert(original)

    let copy = try await repo.duplicate(id: original.id)
    #expect(copy != nil)
    #expect(copy?.id != original.id)
    #expect(copy?.name == "Push Day Copy")
    #expect(copy?.entries.count == 1)
    #expect(copy?.entries.first?.id != original.entries.first?.id)
    #expect(copy?.entries.first?.exerciseId == exerciseId)

    // Editing the copy leaves the original untouched.
    var edited = copy!
    edited.name = "Push Day B"
    edited.entries[0].targetReps = 8
    try await repo.upsert(edited)

    let originalAfter = try await repo.get(id: original.id)
    #expect(originalAfter?.name == "Push Day")
    #expect(originalAfter?.entries.first?.targetReps == 5)
    #expect(try await repo.all().count == 2)
}

@Test func reorderPersistsNewOrder() async throws {
    let repo = try makeRepo()
    let e0 = entry(order: 0, weight: 100)
    let e1 = entry(order: 1, weight: 200)
    let e2 = entry(order: 2, weight: 300)
    let dto = WorkoutDTO(id: UUID(), name: "Full Body", entries: [e0, e1, e2], createdAt: .now, updatedAt: .now)
    try await repo.upsert(dto)

    try await repo.reorder(workoutId: dto.id, entryIds: [e2.id, e0.id, e1.id])

    let fetched = try await repo.get(id: dto.id)
    #expect(fetched?.entries.map(\.targetWeight) == [300, 100, 200])
}

@Test func deleteCascadesEntries() async throws {
    let repo = try makeRepo()
    let dto = WorkoutDTO(id: UUID(), name: "Temp", entries: [entry(order: 0)], createdAt: .now, updatedAt: .now)
    try await repo.upsert(dto)
    try await repo.delete(id: dto.id)
    #expect(try await repo.all().isEmpty)
}
