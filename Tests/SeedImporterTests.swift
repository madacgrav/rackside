import Foundation
import Testing
@testable import Rackside

@Test func seedLoadsOnceAndIsIdempotent() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataExerciseRepository(modelContainer: container)

    try await SeedImporter.seedIfEmpty(repo: repo)
    let countAfterFirst = try await repo.count()
    #expect(countAfterFirst >= 25)
    #expect(countAfterFirst <= 40)

    // Second call must not duplicate.
    try await SeedImporter.seedIfEmpty(repo: repo)
    #expect(try await repo.count() == countAfterFirst)

    // Seeded items are not custom and have sensible metrics.
    let all = try await repo.all()
    #expect(all.allSatisfy { !$0.isCustom })
    #expect(all.allSatisfy { !$0.metrics.isEmpty })
}

@Test func seedSkipsNonEmptyStore() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataExerciseRepository(modelContainer: container)
    _ = try await repo.create(ExerciseDTO(
        id: UUID(), name: "My Custom Move", category: .strength,
        metrics: [.reps], defaultUnit: .lb, isCustom: true,
        createdAt: .now, updatedAt: .now
    ))

    try await SeedImporter.seedIfEmpty(repo: repo)
    #expect(try await repo.count() == 1)
}
