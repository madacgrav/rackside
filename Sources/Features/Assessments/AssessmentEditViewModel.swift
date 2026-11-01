import Foundation
import Observation

@MainActor
@Observable
final class AssessmentEditViewModel {
    private let repo: any AssessmentRepository
    private let existing: AssessmentDTO?
    let clientId: UUID
    /// lb → weights in lb and lengths in inches; otherwise kg and cm.
    let usesImperial: Bool

    var performedOn: Date
    var sections: AssessmentSections
    // Measurements, in display units.
    var restingHR: Int?
    var systolic: Int?
    var diastolic: Int?
    var height: Double?
    var weight: Double?
    var waist: Double?
    var hip: Double?
    var bodyFatPct: Double?
    var pushUps: Int?
    var plankSeconds: Int?
    // Movement.
    var ohsAnteriorRight: OHSAnterior
    var ohsAnteriorLeft: OHSAnterior
    var ohsLateral: OHSLateral
    var ohsPosteriorRight: OHSPosterior
    var ohsPosteriorLeft: OHSPosterior
    var ohsHeelsElevated: OHSRegions
    var ohsArmsDown: OHSRegions
    var ohsNotes: String
    var slsRight: SLSCompensations
    var slsLeft: SLSCompensations
    var slsNotes: String
    var errorMessage: String?
    private(set) var savedAssessment: AssessmentDTO?
    /// The DTO as last loaded or saved (timestamps cleared); drives `isDirty`.
    private var baseline: AssessmentDTO?

    init(
        repo: any AssessmentRepository,
        clientId: UUID,
        existing: AssessmentDTO?,
        sections: AssessmentSections = .all,
        weightUnit: Unit
    ) {
        self.repo = repo
        self.clientId = clientId
        self.existing = existing
        usesImperial = weightUnit == .lb
        performedOn = existing?.performedOn ?? .now
        self.sections = existing?.sections ?? sections
        let m = existing?.measurements ?? Measurements()
        let length = weightUnit == .lb ? 1 / Measurements.cmPerInch : 1
        let mass = weightUnit == .lb ? 1 / Measurements.kgPerLb : 1
        restingHR = m.restingHR
        systolic = m.systolic
        diastolic = m.diastolic
        height = m.heightCm.map { Self.round1($0 * length) }
        weight = m.weightKg.map { Self.round1($0 * mass) }
        waist = m.waistCm.map { Self.round1($0 * length) }
        hip = m.hipCm.map { Self.round1($0 * length) }
        bodyFatPct = m.bodyFatPct
        pushUps = m.pushUps
        plankSeconds = m.plankSeconds
        ohsAnteriorRight = existing?.ohsAnteriorRight ?? []
        ohsAnteriorLeft = existing?.ohsAnteriorLeft ?? []
        ohsLateral = existing?.ohsLateral ?? []
        ohsPosteriorRight = existing?.ohsPosteriorRight ?? []
        ohsPosteriorLeft = existing?.ohsPosteriorLeft ?? []
        ohsHeelsElevated = existing?.ohsHeelsElevated ?? []
        ohsArmsDown = existing?.ohsArmsDown ?? []
        ohsNotes = existing?.ohsNotes ?? ""
        slsRight = existing?.slsRight ?? []
        slsLeft = existing?.slsLeft ?? []
        slsNotes = existing?.slsNotes ?? ""
        baseline = comparable
    }

    /// True when the form differs from what was loaded or last saved.
    var isDirty: Bool { comparable != baseline }

    private var comparable: AssessmentDTO {
        var dto = makeDTO()
        dto.createdAt = .distantPast
        dto.updatedAt = .distantPast
        return dto
    }

    var isEditing: Bool { existing != nil }
    var canSave: Bool { !sections.isEmpty }
    var lengthUnit: String { usesImperial ? "in" : "cm" }
    var massUnit: String { usesImperial ? "lb" : "kg" }

    func makeDTO() -> AssessmentDTO {
        let length = usesImperial ? Measurements.cmPerInch : 1
        let mass = usesImperial ? Measurements.kgPerLb : 1
        let measurements = sections.contains(.measurements) ? Measurements(
            restingHR: restingHR,
            systolic: systolic,
            diastolic: diastolic,
            heightCm: height.map { $0 * length },
            weightKg: weight.map { $0 * mass },
            waistCm: waist.map { $0 * length },
            hipCm: hip.map { $0 * length },
            bodyFatPct: bodyFatPct,
            pushUps: pushUps,
            plankSeconds: plankSeconds
        ) : Measurements()
        let ohs = sections.contains(.overheadSquat)
        let sls = sections.contains(.singleLegSquat)
        return AssessmentDTO(
            id: existing?.id ?? draftId,
            clientId: clientId,
            performedOn: performedOn,
            sections: sections,
            measurements: measurements,
            ohsAnteriorRight: ohs ? ohsAnteriorRight : [],
            ohsAnteriorLeft: ohs ? ohsAnteriorLeft : [],
            ohsLateral: ohs ? ohsLateral : [],
            ohsPosteriorRight: ohs ? ohsPosteriorRight : [],
            ohsPosteriorLeft: ohs ? ohsPosteriorLeft : [],
            ohsHeelsElevated: ohs ? ohsHeelsElevated : [],
            ohsArmsDown: ohs ? ohsArmsDown : [],
            ohsNotes: ohs ? Self.nilIfBlank(ohsNotes) : nil,
            slsRight: sls ? slsRight : [],
            slsLeft: sls ? slsLeft : [],
            slsNotes: sls ? Self.nilIfBlank(slsNotes) : nil,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
    }

    func save() async -> Bool {
        errorMessage = nil
        let dto = makeDTO()
        do {
            try await repo.upsert(dto)
            savedAssessment = dto
            baseline = comparable
            return true
        } catch {
            Log.persistence.error("Assessment save failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save the assessment. Please try again."
            return false
        }
    }

    /// Stable id for a new assessment, so repeated saves (intake flow) update one row.
    private let draftId = UUID()

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    private static func nilIfBlank(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
