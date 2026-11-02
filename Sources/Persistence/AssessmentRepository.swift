import Foundation
import SwiftData

protocol AssessmentRepository: Sendable {
    /// Newest `performedOn` first.
    func forClient(_ clientId: UUID) async throws -> [AssessmentDTO]
    /// The newest assessment performed strictly before `date`.
    func previous(before date: Date, clientId: UUID) async throws -> AssessmentDTO?
    func upsert(_ dto: AssessmentDTO) async throws
    func delete(id: UUID) async throws
}

@ModelActor
actor SwiftDataAssessmentRepository: AssessmentRepository {
    func forClient(_ clientId: UUID) async throws -> [AssessmentDTO] {
        try modelContext
            .fetch(FetchDescriptor<Assessment>(
                predicate: #Predicate { $0.clientId == clientId },
                sortBy: [SortDescriptor(\.performedOn, order: .reverse)]
            ))
            .map(AssessmentDTO.init)
    }

    func previous(before date: Date, clientId: UUID) async throws -> AssessmentDTO? {
        var descriptor = FetchDescriptor<Assessment>(
            predicate: #Predicate { $0.clientId == clientId && $0.performedOn < date },
            sortBy: [SortDescriptor(\.performedOn, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(AssessmentDTO.init)
    }

    func upsert(_ dto: AssessmentDTO) async throws {
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

    private func fetch(id: UUID) throws -> Assessment? {
        try modelContext.fetch(FetchDescriptor<Assessment>(predicate: #Predicate { $0.id == id })).first
    }
}
