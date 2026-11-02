import Foundation
import SwiftData
import Testing
@testable import Rackside

private struct Env {
    let clients: SwiftDataClientRepository
    let intake: IntakeRepositories
    let client: ClientDTO
}

private func makeEnv(health: (any HealthScreeningRepository)? = nil) async throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let clients = SwiftDataClientRepository(modelContainer: container)
    let client = ClientDTO(
        id: UUID(), name: "Pat", phoneE164: "+15551230000", goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    )
    try await clients.upsert(client)
    let defaults = IntakeRepositories(container: container)
    let intake = IntakeRepositories(
        health: health ?? defaults.health, assessments: defaults.assessments, waivers: defaults.waivers
    )
    return Env(clients: clients, intake: intake, client: client)
}

@MainActor
private func makeFlow(_ env: Env) -> IntakeFlowViewModel {
    IntakeFlowViewModel(client: env.client, clientRepo: env.clients, intake: env.intake, weightUnit: .kg)
}

private struct FailingHealthRepository: HealthScreeningRepository {
    struct Failure: Error {}
    func forClient(_ clientId: UUID) async throws -> [HealthScreeningDTO] { [] }
    func latest(clientId: UUID) async throws -> HealthScreeningDTO? { nil }
    func upsert(_ dto: HealthScreeningDTO) async throws { throw Failure() }
    func delete(id: UUID) async throws {}
}

@Test func stepsFollowSections() {
    #expect(IntakeFlowViewModel.steps(for: .all)
        == [.sections, .profile, .health, .waiver, .measurements, .movement, .review])
    #expect(IntakeFlowViewModel.steps(for: []) == [.sections, .profile, .review])
    #expect(IntakeFlowViewModel.steps(for: [.overheadSquat]) == [.sections, .profile, .movement, .review])
}

@MainActor
@Test func nextSavesProfileThenHealth() async throws {
    let env = try await makeEnv()
    let flow = makeFlow(env)

    #expect(await flow.next())          // sections → profile
    flow.profile.occupation = "Chef"
    #expect(await flow.next())          // profile saved → health
    #expect(try await env.clients.all().first?.occupation == "Chef")
    #expect(flow.current == .health)

    flow.health.set(.chestPain, true)
    #expect(await flow.next())          // health saved → waiver
    #expect(try await env.intake.health.latest(clientId: env.client.id)?.answers == [.chestPain])
    #expect(flow.current == .waiver)
}

@MainActor
@Test func measurementsAndMovementSaveOneAssessment() async throws {
    let env = try await makeEnv()
    let flow = makeFlow(env)
    flow.sections = [.measurements, .overheadSquat]

    #expect(await flow.next())          // → profile
    #expect(await flow.next())          // → measurements
    flow.assessment.weight = 70
    #expect(await flow.next())          // → movement
    flow.assessment.ohsLateral = [.armsFallForward]
    #expect(await flow.next())          // → review
    #expect(flow.current == .review)

    let saved = try await env.intake.assessments.forClient(env.client.id)
    #expect(saved.count == 1)
    #expect(saved.first?.measurements.weightKg == 70)
    #expect(saved.first?.ohsLateral == [.armsFallForward])
    #expect(saved.first?.sections == [.measurements, .overheadSquat])
}

@MainActor
@Test func unsavedEditsFlag() async throws {
    let env = try await makeEnv()
    let flow = makeFlow(env)
    #expect(!flow.hasUnsavedEdits)

    #expect(await flow.next())          // → profile
    flow.profile.availability = "Mornings"
    #expect(flow.hasUnsavedEdits)

    #expect(await flow.next())          // profile saved
    #expect(!flow.hasUnsavedEdits)
}

@MainActor
@Test func failedSaveDoesNotAdvance() async throws {
    let env = try await makeEnv(health: FailingHealthRepository())
    let flow = makeFlow(env)
    #expect(await flow.next())          // → profile
    #expect(await flow.next())          // → health
    #expect(flow.current == .health)

    #expect(await flow.next() == false)
    #expect(flow.current == .health)
    #expect(flow.errorMessage != nil)
}
