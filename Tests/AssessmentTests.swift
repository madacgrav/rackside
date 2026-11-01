import Foundation
import SwiftData
import Testing
@testable import TrainMe

private struct Env {
    let clients: SwiftDataClientRepository
    let assessments: SwiftDataAssessmentRepository
    let archive: DataArchiveActor
}

private func makeEnv() throws -> Env {
    let container = try PersistenceController.makeContainer(inMemory: true)
    return Env(
        clients: SwiftDataClientRepository(modelContainer: container),
        assessments: SwiftDataAssessmentRepository(modelContainer: container),
        archive: DataArchiveActor(modelContainer: container)
    )
}

private func assessment(
    clientId: UUID = UUID(),
    on date: Date = Date(timeIntervalSince1970: 1_700_000_000),
    sections: AssessmentSections = .all,
    measurements: Measurements = Measurements()
) -> AssessmentDTO {
    AssessmentDTO(
        id: UUID(), clientId: clientId, performedOn: date, sections: sections,
        measurements: measurements, createdAt: date, updatedAt: date
    )
}

@Test func optionSetsRoundTripThroughModel() {
    var dto = assessment(measurements: Measurements(restingHR: 60, weightKg: 80.5, plankSeconds: 90))
    dto.ohsAnteriorRight = [.kneeMovesInward]
    dto.ohsAnteriorLeft = [.footTurnsOut, .kneeMovesOutward]
    dto.ohsLateral = [.lowBackArches, .armsFallForward]
    dto.ohsPosteriorRight = [.heelOfFootRises]
    dto.ohsPosteriorLeft = [.asymmetricalWeightShift]
    dto.ohsHeelsElevated = [.feet, .knees]
    dto.ohsArmsDown = [.upperBody]
    dto.ohsNotes = "Better with heels up"
    dto.slsRight = [.hipDrop, .inwardTrunkRotation]
    dto.slsLeft = [.outwardTrunkRotation]
    dto.slsNotes = "Wobbly"

    #expect(AssessmentDTO(dto.toModel()) == dto)
}

@Test func diffResolvedAndNew() {
    var previous = assessment(on: Date(timeIntervalSince1970: 1_600_000_000))
    previous.ohsAnteriorRight = [.kneeMovesInward]
    var current = assessment()
    current.ohsAnteriorLeft = [.footTurnsOut]

    let diff = AssessmentDTO.diff(current, previous: previous)

    #expect(diff.resolved == ["Overhead squat · Anterior · Right: Knee moves inward"])
    #expect(diff.new == ["Overhead squat · Anterior · Left: Foot turns out"])
}

@Test func diffMeasurementDeltasOnlyWhenBothPresent() {
    let previous = assessment(measurements: Measurements(weightKg: 82, waistCm: 86, pushUps: 15))
    let current = assessment(measurements: Measurements(restingHR: 60, weightKg: 80, waistCm: 86, pushUps: 20))

    let deltas = AssessmentDTO.diff(current, previous: previous).measurementDeltas

    #expect(deltas == [MeasurementDelta(field: .weight, delta: -2), MeasurementDelta(field: .pushUps, delta: 5)])
}

@Test func diffIgnoresSectionsMissingFromEither() {
    var previous = assessment(sections: [.overheadSquat, .singleLegSquat])
    previous.slsLeft = [.hipHike]
    previous.ohsLateral = [.lowBackRounds]
    var current = assessment(sections: [.overheadSquat])
    current.ohsLateral = [.lowBackRounds]

    #expect(AssessmentDTO.diff(current, previous: previous).isEmpty)
}

@Test func diffWithNoPreviousIsEmpty() {
    var current = assessment()
    current.slsRight = [.hipDrop]
    #expect(AssessmentDTO.diff(current, previous: nil).isEmpty)
}

@Test func bmiAndWaistToHip() throws {
    let m = Measurements(heightCm: 180, weightKg: 81, waistCm: 80, hipCm: 100)
    #expect(abs(try #require(m.bmi) - 25) < 0.001)
    #expect(abs(try #require(m.waistToHip) - 0.8) < 0.001)
    #expect(Measurements().bmi == nil)
}

@MainActor
@Test func editViewModelConvertsPoundsToKg() throws {
    let env = try makeEnv()
    let vm = AssessmentEditViewModel(
        repo: env.assessments, clientId: UUID(), existing: nil, sections: [.measurements], weightUnit: .lb
    )
    vm.weight = 200
    vm.waist = 10

    let m = vm.makeDTO().measurements
    #expect(abs(try #require(m.weightKg) - 90.718474) < 0.001)
    #expect(abs(try #require(m.waistCm) - 25.4) < 0.001)
}

@Test func forClientNewestFirstAndPrevious() async throws {
    let env = try makeEnv()
    let clientId = UUID()
    let first = assessment(clientId: clientId, on: Date(timeIntervalSince1970: 1_600_000_000))
    let second = assessment(clientId: clientId, on: Date(timeIntervalSince1970: 1_650_000_000))
    let third = assessment(clientId: clientId, on: Date(timeIntervalSince1970: 1_700_000_000))
    for a in [second, first, third] { try await env.assessments.upsert(a) }
    try await env.assessments.upsert(assessment())

    #expect(try await env.assessments.forClient(clientId).map(\.id) == [third.id, second.id, first.id])
    #expect(try await env.assessments.previous(before: third.performedOn, clientId: clientId)?.id == second.id)
    #expect(try await env.assessments.previous(before: first.performedOn, clientId: clientId) == nil)
}

@Test func deletingClientDeletesAssessments() async throws {
    let env = try makeEnv()
    let client = ClientDTO(
        id: UUID(), name: "Pat", phoneE164: "+15551230000", goal: nil, injuries: nil, notes: nil,
        isArchived: false, createdAt: .now, updatedAt: .now
    )
    try await env.clients.upsert(client)
    try await env.assessments.upsert(assessment(clientId: client.id))

    try await env.clients.delete(id: client.id)

    #expect(try await env.assessments.forClient(client.id).isEmpty)
}

@Test func assessmentsRoundTripThroughArchive() async throws {
    let source = try makeEnv()
    var original = assessment(measurements: Measurements(systolic: 120, diastolic: 80, bodyFatPct: 18.5))
    original.ohsPosteriorLeft = [.footFlattens]
    original.slsLeft = [.kneeMovesInward]
    try await source.assessments.upsert(original)
    let data = try await source.archive.exportData()

    let dest = try makeEnv()
    try await dest.archive.importData(data, mode: .replace)

    #expect(try await dest.assessments.forClient(original.clientId) == [original])
}
