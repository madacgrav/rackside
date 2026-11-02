import Foundation
import SwiftData

protocol WaiverRepository: Sendable {
    /// The single template row, created from waiver_starter.txt on first use.
    func template() async throws -> WaiverTemplateDTO
    /// Saves the body; bumps `version` only when the text actually changed.
    func saveTemplate(body: String) async throws -> WaiverTemplateDTO
    /// Newest `sentOn` first.
    func records(clientId: UUID) async throws -> [WaiverRecordDTO]
    /// Snapshots the current template into a new record.
    func recordSent(clientId: UUID, on date: Date) async throws -> WaiverRecordDTO
    /// nil clears the returned date.
    func markReturned(id: UUID, on date: Date?) async throws
    func delete(id: UUID) async throws
}

@ModelActor
actor SwiftDataWaiverRepository: WaiverRepository {
    /// The bundled starter text, or a placeholder if the resource is missing.
    nonisolated static func starterText(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "waiver_starter", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            Log.persistence.error("waiver_starter.txt missing from bundle")
            return "LIABILITY WAIVER\n\nEdit this template in Settings before sending it to clients."
        }
        return text
    }

    func template() async throws -> WaiverTemplateDTO {
        WaiverTemplateDTO(try templateModel())
    }

    func saveTemplate(body: String) async throws -> WaiverTemplateDTO {
        let model = try templateModel()
        if model.body != body {
            model.body = body
            model.version += 1
            model.updatedAt = .now
            try modelContext.save()
        }
        return WaiverTemplateDTO(model)
    }

    func records(clientId: UUID) async throws -> [WaiverRecordDTO] {
        try modelContext
            .fetch(FetchDescriptor<WaiverRecord>(
                predicate: #Predicate { $0.clientId == clientId },
                sortBy: [SortDescriptor(\.sentOn, order: .reverse)]
            ))
            .map(WaiverRecordDTO.init)
    }

    func recordSent(clientId: UUID, on date: Date) async throws -> WaiverRecordDTO {
        let template = try templateModel()
        let record = WaiverRecord(
            clientId: clientId, sentOn: date,
            templateVersion: template.version, templateBody: template.body
        )
        modelContext.insert(record)
        try modelContext.save()
        return WaiverRecordDTO(record)
    }

    func markReturned(id: UUID, on date: Date?) async throws {
        guard let record = try fetch(id: id) else { return }
        record.returnedSignedOn = date
        record.updatedAt = .now
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        guard let record = try fetch(id: id) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func templateModel() throws -> WaiverTemplate {
        var descriptor = FetchDescriptor<WaiverTemplate>()
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first { return existing }
        let seeded = WaiverTemplate(body: Self.starterText())
        modelContext.insert(seeded)
        try modelContext.save()
        return seeded
    }

    private func fetch(id: UUID) throws -> WaiverRecord? {
        try modelContext.fetch(FetchDescriptor<WaiverRecord>(predicate: #Predicate { $0.id == id })).first
    }
}
