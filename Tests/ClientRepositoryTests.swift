import Foundation
import Testing
@testable import Rackside

private func makeRepo() throws -> SwiftDataClientRepository {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return SwiftDataClientRepository(modelContainer: container)
}

private func dto(id: UUID = UUID(), name: String, phone: String = "+15551234567") -> ClientDTO {
    ClientDTO(
        id: id, name: name, phoneE164: phone,
        goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    )
}

@Test func upsertAndFetchRoundTrip() async throws {
    let repo = try makeRepo()
    try await repo.upsert(dto(name: "Sam"))

    let all = try await repo.all()
    #expect(all.count == 1)
    #expect(all.first?.name == "Sam")
    #expect(all.first?.phoneE164 == "+15551234567")
}

@Test func upsertUpdatesExistingById() async throws {
    let repo = try makeRepo()
    let id = UUID()

    try await repo.upsert(dto(id: id, name: "Sam"))
    var updated = dto(id: id, name: "Samantha")
    updated.goal = "Strength"
    updated.injuries = "Left knee"
    updated.notes = "Prefers mornings"
    try await repo.upsert(updated)

    let all = try await repo.all()
    #expect(all.count == 1)
    #expect(all.first?.name == "Samantha")
    #expect(all.first?.goal == "Strength")
    #expect(all.first?.injuries == "Left knee")
    #expect(all.first?.notes == "Prefers mornings")
}

@Test func deleteRemovesClient() async throws {
    let repo = try makeRepo()
    let id = UUID()

    try await repo.upsert(dto(id: id, name: "Sam"))
    try await repo.delete(id: id)

    #expect(try await repo.all().isEmpty)
}

@Test func searchMatchesSubstringCaseInsensitive() async throws {
    let repo = try makeRepo()
    try await repo.upsert(dto(name: "Samantha Jones"))
    try await repo.upsert(dto(name: "Alex Smith"))

    let results = try await repo.search("sam")
    #expect(results.count == 1)
    #expect(results.first?.name == "Samantha Jones")

    let empty = try await repo.search("")
    #expect(empty.count == 2)
}

@Test func archivedClientsLeaveActiveListAndSearch() async throws {
    let repo = try makeRepo()
    let id = UUID()
    try await repo.upsert(dto(id: id, name: "Sam"))
    try await repo.upsert(dto(name: "Alex"))

    try await repo.setArchived(id: id, true)

    let active = try await repo.all()
    #expect(active.count == 1)
    #expect(active.first?.name == "Alex")
    #expect(try await repo.search("Sam").isEmpty)
    #expect(try await repo.allIncludingArchived().count == 2)

    try await repo.setArchived(id: id, false)
    #expect(try await repo.all().count == 2)
}

// MARK: - Self-use client (SchemaV2)

@Test func selfClientRoundTrip() async throws {
    let repo = try makeRepo()
    var me = dto(name: "Me", phone: "")
    me.isSelf = true
    try await repo.upsert(me)
    try await repo.upsert(dto(name: "Alex"))

    let found = try await repo.selfClient()
    #expect(found?.name == "Me")
    #expect(found?.isSelf == true)
    #expect(try await repo.all().count == 2)
    #expect(try await repo.all().first { $0.name == "Alex" }?.isSelf == false)
}

@MainActor
@Test func selfClientSkipsPhoneValidation() async throws {
    let repo = try makeRepo()
    let vm = ClientEditViewModel(repo: repo, existing: nil, isSelf: true)
    vm.name = "Me"
    #expect(vm.canSave)

    let saved = await vm.save()

    #expect(saved)
    let stored = try #require(try await repo.selfClient())
    #expect(stored.phoneE164 == "")
    #expect(stored.isSelf)

    // A regular client still needs a valid phone number.
    let regular = ClientEditViewModel(repo: repo, existing: nil)
    regular.name = "Alex"
    #expect(!regular.canSave)
}

@Test func exportOmitsIsSelf() throws {
    var me = dto(name: "Me")
    me.isSelf = true

    let data = try JSONEncoder().encode(me)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["isSelf"] == nil)
    #expect(object["name"] as? String == "Me")

    let decoded = try JSONDecoder().decode(ClientDTO.self, from: data)
    #expect(decoded.isSelf == false)
    #expect(decoded.name == "Me")
}

@Test func exportIncludesProfileFields() throws {
    var client = dto(name: "Pat")
    client.emergencyName = "Lee"
    client.occupation = "Chef"

    let data = try JSONEncoder().encode(client)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["emergencyName"] as? String == "Lee")

    let decoded = try JSONDecoder().decode(ClientDTO.self, from: data)
    #expect(decoded.emergencyName == "Lee")
    #expect(decoded.occupation == "Chef")
}
