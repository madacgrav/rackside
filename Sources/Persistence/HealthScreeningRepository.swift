import Foundation
import SwiftData

protocol HealthScreeningRepository: Sendable {
    /// Newest `completedOn` first.
    func forClient(_ clientId: UUID) async throws -> [HealthScreeningDTO]
    func latest(clientId: UUID) async throws -> HealthScreeningDTO?
    func upsert(_ dto: HealthScreeningDTO) async throws
    func delete(id: UUID) async throws
}

@ModelActor
actor SwiftDataHealthScreeningRepository: HealthScreeningRepository {
    func forClient(_ clientId: UUID) async throws -> [HealthScreeningDTO] {
        try modelContext
            .fetch(FetchDescriptor<HealthScreening>(
                predicate: #Predicate { $0.clientId == clientId },
                sortBy: [SortDescriptor(\.completedOn, order: .reverse)]
            ))
            .map(HealthScreeningDTO.init)
    }

    func latest(clientId: UUID) async throws -> HealthScreeningDTO? {
        var descriptor = FetchDescriptor<HealthScreening>(
            predicate: #Predicate { $0.clientId == clientId },
            sortBy: [SortDescriptor(\.completedOn, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(HealthScreeningDTO.init)
    }

    func upsert(_ dto: HealthScreeningDTO) async throws {
        if let existing = try fetch(id: dto.id) {
            dto.apply(to: existing)
        } else {
            modelContext.insert(dto.toModel())
        }
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        guard let existing = try fetch(id: id) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    private func fetch(id: UUID) throws -> HealthScreening? {
        try modelContext.fetch(FetchDescriptor<HealthScreening>(predicate: #Predicate { $0.id == id })).first
    }
}
