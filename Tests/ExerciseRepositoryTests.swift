import Foundation
import Testing
@testable import Rackside

private func makeRepo() throws -> SwiftDataExerciseRepository {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return SwiftDataExerciseRepository(modelContainer: container)
}

private func dto(name: String, category: ExerciseCategory = .strength) -> ExerciseDTO {
    ExerciseDTO(
        id: UUID(), name: name, category: category,
        metrics: [.weight, .reps, .sets], defaultUnit: .lb,
        isCustom: true, createdAt: .now, updatedAt: .now
    )
}

@Test func createAndSearchBySubstring() async throws {
    let repo = try makeRepo()
    _ = try await repo.create(dto(name: "Barbell Bench Press"))
    _ = try await repo.create(dto(name: "Back Squat"))

    let results = try await repo.search(prefix: "bench")
    #expect(results.count == 1)
    #expect(results.first?.name == "Barbell Bench Press")

    let prefixResults = try await repo.search(prefix: "Back")
    #expect(prefixResults.count == 1)

    let all = try await repo.search(prefix: "")
    #expect(all.count == 2)
}

@Test func metricsRoundTrip() async throws {
    let repo = try makeRepo()
    var cardio = dto(name: "Treadmill Run", category: .cardio)
    cardio.metrics = [.distance, .duration]
    cardio.defaultUnit = .mi
    _ = try await repo.create(cardio)

    let fetched = try await repo.all().first
    #expect(fetched?.metrics == [.distance, .duration])
    #expect(fetched?.defaultUnit == .mi)
    #expect(fetched?.category == .cardio)
}
