import Foundation
import SwiftData
import Testing
@testable import TrainMe

/// Writes a store with the frozen V2 classes, then reopens it through the
/// migration plan as V3 — the path an existing install takes on upgrade.
@Test func v2StoreOpensAsV3WithClientIntact() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mig-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "test.store")
    let id = UUID()

    try writeV2Store(at: url, clientId: id)

    let v3 = try ModelContainer(
        for: Schema(versionedSchema: SchemaV3.self),
        migrationPlan: TrainMeMigrationPlan.self,
        configurations: ModelConfiguration(url: url)
    )
    let clients = try ModelContext(v3).fetch(FetchDescriptor<Client>())
    #expect(clients.count == 1)
    #expect(clients.first?.id == id)
    #expect(clients.first?.injuries == "Knee")
    #expect(clients.first?.emergencyName == nil)
    #expect(clients.first?.dateOfBirth == nil)
}

/// Separate function so the V2 container is released before V3 opens the file.
private func writeV2Store(at url: URL, clientId: UUID) throws {
    let v2 = try ModelContainer(
        for: Schema(versionedSchema: SchemaV2.self),
        configurations: ModelConfiguration(url: url)
    )
    let ctx = ModelContext(v2)
    ctx.insert(SchemaV2.Client(id: clientId, name: "Pat", phoneE164: "+15551230000", injuries: "Knee"))
    try ctx.save()
}
