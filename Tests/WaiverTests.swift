import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Rackside

private struct Env {
    let clients: SwiftDataClientRepository
    let waivers: SwiftDataWaiverRepository
    let archive: DataArchiveActor
}

private func makeEnv() throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return Env(
        clients: SwiftDataClientRepository(modelContainer: container),
        waivers: SwiftDataWaiverRepository(modelContainer: container),
        archive: DataArchiveActor(modelContainer: container)
    )
}

private func record(sent: TimeInterval, returned: TimeInterval? = nil) -> WaiverRecordDTO {
    WaiverRecordDTO(
        id: UUID(), clientId: UUID(), sentOn: Date(timeIntervalSince1970: sent), templateVersion: 1,
        templateBody: "x", returnedSignedOn: returned.map(Date.init(timeIntervalSince1970:)), notes: nil,
        createdAt: .now, updatedAt: .now
    )
}

@Test func templateSeedsFromStarterText() async throws {
    let env = try makeEnv()
    let template = try await env.waivers.template()
    #expect(template.version == 1)
    #expect(template.body.contains("ASSUMPTION OF RISK"))
    #expect(try await env.waivers.template().id == template.id)
}

@Test func saveTemplateBumpsVersionOnlyWhenChanged() async throws {
    let env = try makeEnv()
    let original = try await env.waivers.template()
    #expect(try await env.waivers.saveTemplate(body: original.body).version == 1)
    #expect(try await env.waivers.saveTemplate(body: original.body + "\nExtra").version == 2)
}

@Test func recordSnapshotsTemplate() async throws {
    let env = try makeEnv()
    let clientId = UUID()
    let original = try await env.waivers.template()
    let sent = try await env.waivers.recordSent(clientId: clientId, on: .now)
    _ = try await env.waivers.saveTemplate(body: "NEW TEXT")

    let stored = try #require(try await env.waivers.records(clientId: clientId).first)
    #expect(stored.id == sent.id)
    #expect(stored.templateVersion == 1)
    #expect(stored.templateBody == original.body)
}

@Test func statusDerivation() {
    #expect(WaiverRecordDTO.status([]) == .none)
    #expect(WaiverRecordDTO.status([record(sent: 100), record(sent: 200)]) == .sent(Date(timeIntervalSince1970: 200)))
    // A signed waiver still counts after a later unsigned resend.
    #expect(WaiverRecordDTO.status([record(sent: 100, returned: 150), record(sent: 300)])
        == .signed(Date(timeIntervalSince1970: 150)))
}

@Test func markReturnedAndClear() async throws {
    let env = try makeEnv()
    let clientId = UUID()
    let sent = try await env.waivers.recordSent(clientId: clientId, on: .now)
    let returned = Date(timeIntervalSince1970: 1_700_000_000)

    try await env.waivers.markReturned(id: sent.id, on: returned)
    #expect(try await env.waivers.records(clientId: clientId).first?.returnedSignedOn == returned)

    try await env.waivers.markReturned(id: sent.id, on: nil)
    #expect(try await env.waivers.records(clientId: clientId).first?.returnedSignedOn == nil)
}

@Test func longBodyRendersMultiplePages() throws {
    let body = "WAIVER\n" + String(repeating: "Lorem ipsum dolor sit amet. ", count: 800)
    let url = try WaiverPDFRenderer.render(body: body, clientName: "Sam / Rivera", trainerName: "Jo", version: 1, date: .now)
    defer { WaiverPDFRenderer.removeAll() }

    let document = try #require(PDFDocument(url: url))
    #expect(document.pageCount > 1)
    let firstPage = try #require(document.page(at: 0)?.string)
    #expect(firstPage.contains("Template v1"))
    #expect(firstPage.contains("Sam / Rivera"))
    #expect(url.lastPathComponent == "Waiver - Sam - Rivera.pdf")
}

@Test func rendererSkipsCommentLinesAndStripsMarkers() throws {
    let data = WaiverPDFRenderer.pdfData(
        body: SwiftDataWaiverRepository.starterText(), clientName: "Pat", trainerName: nil, version: 3, date: .now
    )
    let document = try #require(PDFDocument(data: data))
    let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    #expect(text.contains("ordinary negligence"))
    #expect(!text.contains("!!"))
    #expect(!text.contains("not legal advice"))  // the # comment line
}

@Test func deletingClientDeletesWaiverRecords() async throws {
    let env = try makeEnv()
    let client = ClientDTO(
        id: UUID(), name: "Pat", phoneE164: "+15551230000", goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    )
    try await env.clients.upsert(client)
    _ = try await env.waivers.recordSent(clientId: client.id, on: .now)

    try await env.clients.delete(id: client.id)

    #expect(try await env.waivers.records(clientId: client.id).isEmpty)
}

@Test func waiversRoundTripThroughArchive() async throws {
    let source = try makeEnv()
    let clientId = UUID()
    let template = try await source.waivers.saveTemplate(body: "MY WAIVER\nText")
    let sent = try await source.waivers.recordSent(clientId: clientId, on: Date(timeIntervalSince1970: 1_700_000_000))
    try await source.waivers.markReturned(id: sent.id, on: Date(timeIntervalSince1970: 1_700_100_000))
    let data = try await source.archive.exportData()

    let dest = try makeEnv()
    try await dest.archive.importData(data, mode: .replace)

    let restored = try await dest.waivers.template()
    #expect(restored.version == template.version)
    #expect(restored.body == "MY WAIVER\nText")
    let records = try await dest.waivers.records(clientId: clientId)
    #expect(records.count == 1)
    #expect(records.first?.returnedSignedOn == Date(timeIntervalSince1970: 1_700_100_000))
    #expect(records.first?.templateBody == "MY WAIVER\nText")
}
