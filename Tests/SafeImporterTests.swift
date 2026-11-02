import Foundation
import SwiftData
import Testing
@testable import Rackside

/// Delegates to a real actor but fails importArchive(url:) on demand.
actor FlakyArchive: DataArchiving {
    let inner: DataArchiveActor
    private var failImportArchive = false

    init(inner: DataArchiveActor) { self.inner = inner }

    func setFail(_ fail: Bool) { failImportArchive = fail }

    func export() async throws -> URL { try await inner.export() }
    func exportData() async throws -> Data { try await inner.exportData() }

    func importArchive(url: URL, mode: ImportMode) async throws {
        if failImportArchive { throw ArchiveError.unreadable }
        try await inner.importArchive(url: url, mode: mode)
    }

    func importData(_ data: Data, mode: ImportMode) async throws {
        try await inner.importData(data, mode: mode)
    }
}

private func tmpURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "safe-import-\(UUID().uuidString)-\(name)")
}

private func client(named name: String) -> ClientDTO {
    ClientDTO(id: UUID(), name: name, phoneE164: "", goal: nil, injuries: nil, notes: nil,
              isArchived: false, createdAt: .now, updatedAt: .now)
}

@Test func failedReplaceImportRestoresSnapshot() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let clients = SwiftDataClientRepository(modelContainer: container)
    try await clients.upsert(client(named: "Keep Me"))
    let flaky = FlakyArchive(inner: DataArchiveActor(modelContainer: container))
    await flaky.setFail(true)
    let sut = SafeImporter(archive: flaky, snapshotURL: tmpURL("snap.json"))

    await #expect(throws: ImportOutcome.self) {
        try await sut.importReplacing(url: tmpURL("ignored.json"))
    }
    #expect(try await clients.all().map(\.name) == ["Keep Me"])
    #expect(!FileManager.default.fileExists(atPath: sut.snapshotURL.path))
}

@Test func replaceImportIntoNonEmptyStoreRemovesLocalRows() async throws {
    // Source store with one client → export to a file.
    let src = try PersistenceController.makeContainer(inMemory: true)
    try await SwiftDataClientRepository(modelContainer: src).upsert(client(named: "From Archive"))
    let archiveFile = tmpURL("archive.json")
    try await DataArchiveActor(modelContainer: src).exportData().write(to: archiveFile)
    defer { try? FileManager.default.removeItem(at: archiveFile) }

    // Target store with a different client → replace-import.
    let dst = try PersistenceController.makeContainer(inMemory: true)
    let dstClients = SwiftDataClientRepository(modelContainer: dst)
    try await dstClients.upsert(client(named: "Local Only"))
    let sut = SafeImporter(archive: DataArchiveActor(modelContainer: dst), snapshotURL: tmpURL("snap.json"))

    try await sut.importReplacing(url: archiveFile)

    #expect(try await dstClients.all().map(\.name) == ["From Archive"])
    #expect(!FileManager.default.fileExists(atPath: sut.snapshotURL.path))
}

@Test func importArchiveMissingFileIsUnreadable() async throws {
    let archive = DataArchiveActor(modelContainer: try PersistenceController.makeContainer(inMemory: true))
    await #expect(throws: ArchiveError.unreadable) {
        try await archive.importArchive(url: tmpURL("does-not-exist.json"), mode: .merge)
    }
}

@Test func validProbeMalformedBodyIsDecodeFailed() async throws {
    let archive = DataArchiveActor(modelContainer: try PersistenceController.makeContainer(inMemory: true))
    let data = Data(#"{"schemaVersion":1,"exportedAt":"not-a-date"}"#.utf8)
    await #expect(throws: ArchiveError.decodeFailed) {
        try await archive.importData(data, mode: .merge)
    }
}
