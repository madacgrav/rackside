import Foundation
import SwiftData
import Testing
@testable import TrainMe

private struct Env {
    let clients: SwiftDataClientRepository
    let health: SwiftDataHealthScreeningRepository
    let archive: DataArchiveActor
}

private func makeEnv() throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return Env(
        clients: SwiftDataClientRepository(modelContainer: container),
        health: SwiftDataHealthScreeningRepository(modelContainer: container),
        archive: DataArchiveActor(modelContainer: container)
    )
}

private func screening(
    clientId: UUID,
    on date: Date = Date(timeIntervalSince1970: 1_700_000_000),
    answers: ScreeningAnswers = [],
    clearance: Date? = nil
) -> HealthScreeningDTO {
    HealthScreeningDTO(
        id: UUID(), clientId: clientId, completedOn: date, answers: answers,
        conditions: "Asthma", surgeries: nil, medications: "Inhaler", familyHeartHistory: true,
        symptoms: nil, sleepHours: 7.5, stressLevel: 2, tobacco: false, alcoholPerWeek: 3,
        activityLevel: .moderate, clearanceReceivedOn: clearance, notes: nil,
        createdAt: date, updatedAt: date
    )
}

@Test func clearanceStates() {
    let id = UUID()
    let cleared = Date(timeIntervalSince1970: 1_700_100_000)
    #expect(HealthScreeningDTO.clearance(for: nil) == .notScreened)
    #expect(HealthScreeningDTO.clearance(for: screening(clientId: id)) == .clear)
    #expect(HealthScreeningDTO.clearance(for: screening(clientId: id, answers: [.chestPain])) == .needed)
    #expect(HealthScreeningDTO.clearance(for: screening(clientId: id, answers: [.chestPain], clearance: cleared)) == .received(cleared))
}

@Test func reviewDueAfter12Months() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let done = try #require(calendar.date(from: DateComponents(year: 2025, month: 3, day: 10)))
    let s = screening(clientId: UUID(), on: done)
    let elevenMonths = try #require(calendar.date(byAdding: .month, value: 11, to: done))
    let twelvePlusDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 11)))
    #expect(!HealthScreeningDTO.reviewDue(s, now: elevenMonths, calendar: calendar))
    #expect(HealthScreeningDTO.reviewDue(s, now: twelvePlusDay, calendar: calendar))
    #expect(!HealthScreeningDTO.reviewDue(nil, now: twelvePlusDay, calendar: calendar))
}

@Test func forClientNewestFirstAndLatest() async throws {
    let env = try makeEnv()
    let clientId = UUID()
    let older = screening(clientId: clientId, on: Date(timeIntervalSince1970: 1_600_000_000))
    let newer = screening(clientId: clientId, on: Date(timeIntervalSince1970: 1_700_000_000), answers: [.dizzinessOrFainting])
    try await env.health.upsert(older)
    try await env.health.upsert(newer)
    try await env.health.upsert(screening(clientId: UUID()))

    let list = try await env.health.forClient(clientId)
    #expect(list.map(\.id) == [newer.id, older.id])
    #expect(try await env.health.latest(clientId: clientId)?.id == newer.id)
}

@Test func answersRoundTripThroughModel() {
    let dto = screening(clientId: UUID(), answers: [.heartOrBloodPressure, .supervisedOnly])
    let back = HealthScreeningDTO(dto.toModel())
    #expect(back == dto)
    #expect(back.answers.rawValue == (1 << 0 | 1 << 6))
}

@Test func deletingClientDeletesScreenings() async throws {
    let env = try makeEnv()
    let client = ClientDTO(
        id: UUID(), name: "Pat", phoneE164: "+15551230000", goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    )
    try await env.clients.upsert(client)
    try await env.health.upsert(screening(clientId: client.id, answers: [.chestPain]))

    try await env.clients.delete(id: client.id)

    #expect(try await env.health.forClient(client.id).isEmpty)
}

@Test func screeningsRoundTripThroughArchive() async throws {
    let source = try makeEnv()
    let original = screening(clientId: UUID(), answers: [.boneJointSoftTissue], clearance: Date(timeIntervalSince1970: 1_700_200_000))
    try await source.health.upsert(original)
    let data = try await source.archive.exportData()

    let dest = try makeEnv()
    try await dest.archive.importData(data, mode: .replace)

    #expect(try await dest.health.forClient(original.clientId) == [original])
}
