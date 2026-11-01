import Foundation

struct AssessmentDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var clientId: UUID
    var performedOn: Date
    var sections: AssessmentSections
    var measurements: Measurements
    var ohsAnteriorRight: OHSAnterior = []
    var ohsAnteriorLeft: OHSAnterior = []
    var ohsLateral: OHSLateral = []
    var ohsPosteriorRight: OHSPosterior = []
    var ohsPosteriorLeft: OHSPosterior = []
    var ohsHeelsElevated: OHSRegions = []
    var ohsArmsDown: OHSRegions = []
    var ohsNotes: String?
    var slsRight: SLSCompensations = []
    var slsLeft: SLSCompensations = []
    var slsNotes: String?
    var createdAt: Date
    var updatedAt: Date
}

extension AssessmentDTO {
    init(_ model: Assessment) {
        self.init(
            id: model.id,
            clientId: model.clientId,
            performedOn: model.performedOn,
            sections: AssessmentSections(rawValue: model.sectionsRaw),
            measurements: model.measurementsData.flatMap { try? JSONDecoder().decode(Measurements.self, from: $0) }
                ?? Measurements(),
            ohsAnteriorRight: OHSAnterior(rawValue: model.ohsAnteriorRightRaw),
            ohsAnteriorLeft: OHSAnterior(rawValue: model.ohsAnteriorLeftRaw),
            ohsLateral: OHSLateral(rawValue: model.ohsLateralRaw),
            ohsPosteriorRight: OHSPosterior(rawValue: model.ohsPosteriorRightRaw),
            ohsPosteriorLeft: OHSPosterior(rawValue: model.ohsPosteriorLeftRaw),
            ohsHeelsElevated: OHSRegions(rawValue: model.ohsHeelsElevatedRaw),
            ohsArmsDown: OHSRegions(rawValue: model.ohsArmsDownRaw),
            ohsNotes: model.ohsNotes,
            slsRight: SLSCompensations(rawValue: model.slsRightRaw),
            slsLeft: SLSCompensations(rawValue: model.slsLeftRaw),
            slsNotes: model.slsNotes,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    func apply(to model: Assessment) {
        model.performedOn = performedOn
        model.sectionsRaw = sections.rawValue
        model.measurementsData = measurements.isEmpty ? nil : try? JSONEncoder().encode(measurements)
        model.ohsAnteriorRightRaw = ohsAnteriorRight.rawValue
        model.ohsAnteriorLeftRaw = ohsAnteriorLeft.rawValue
        model.ohsLateralRaw = ohsLateral.rawValue
        model.ohsPosteriorRightRaw = ohsPosteriorRight.rawValue
        model.ohsPosteriorLeftRaw = ohsPosteriorLeft.rawValue
        model.ohsHeelsElevatedRaw = ohsHeelsElevated.rawValue
        model.ohsArmsDownRaw = ohsArmsDown.rawValue
        model.ohsNotes = ohsNotes
        model.slsRightRaw = slsRight.rawValue
        model.slsLeftRaw = slsLeft.rawValue
        model.slsNotes = slsNotes
        model.updatedAt = updatedAt
    }

    func toModel() -> Assessment {
        let model = Assessment(id: id, clientId: clientId, performedOn: performedOn, createdAt: createdAt, updatedAt: updatedAt)
        apply(to: model)
        return model
    }
}

/// Which numbers the "changes since" summary compares.
enum MeasurementField: CaseIterable, Sendable {
    case weight, waist, hip, bodyFat, restingHR, pushUps, plank

    var label: String {
        switch self {
        case .weight: "Weight"
        case .waist: "Waist"
        case .hip: "Hip"
        case .bodyFat: "Body fat"
        case .restingHR: "Resting HR"
        case .pushUps: "Push-ups"
        case .plank: "Plank"
        }
    }

    /// Metric value (kg, cm, %, bpm, count, seconds).
    func value(in m: Measurements) -> Double? {
        switch self {
        case .weight: m.weightKg
        case .waist: m.waistCm
        case .hip: m.hipCm
        case .bodyFat: m.bodyFatPct
        case .restingHR: m.restingHR.map(Double.init)
        case .pushUps: m.pushUps.map(Double.init)
        case .plank: m.plankSeconds.map(Double.init)
        }
    }
}

struct MeasurementDelta: Equatable, Sendable {
    let field: MeasurementField
    /// current − previous, in the field's metric unit.
    let delta: Double
}

struct AssessmentDiff: Equatable, Sendable {
    var resolved: [String] = []
    var new: [String] = []
    var measurementDeltas: [MeasurementDelta] = []

    var isEmpty: Bool { resolved.isEmpty && new.isEmpty && measurementDeltas.isEmpty }
}

extension AssessmentDTO {
    /// What changed versus the previous assessment. Only sections present in
    /// BOTH are compared, so a skipped section never reads as "resolved".
    static func diff(_ current: AssessmentDTO, previous: AssessmentDTO?) -> AssessmentDiff {
        var result = AssessmentDiff()
        guard let previous else { return result }
        let shared = current.sections.intersection(previous.sections)

        func compare<T: CompensationSet>(_ cur: T, _ prev: T, _ prefix: String) {
            for (item, label) in T.items {
                if prev.contains(item) && !cur.contains(item) { result.resolved.append("\(prefix): \(label)") }
                if cur.contains(item) && !prev.contains(item) { result.new.append("\(prefix): \(label)") }
            }
        }

        if shared.contains(.overheadSquat) {
            compare(current.ohsAnteriorRight, previous.ohsAnteriorRight, "Overhead squat · Anterior · Right")
            compare(current.ohsAnteriorLeft, previous.ohsAnteriorLeft, "Overhead squat · Anterior · Left")
            compare(current.ohsLateral, previous.ohsLateral, "Overhead squat · Lateral")
            compare(current.ohsPosteriorRight, previous.ohsPosteriorRight, "Overhead squat · Posterior · Right")
            compare(current.ohsPosteriorLeft, previous.ohsPosteriorLeft, "Overhead squat · Posterior · Left")
        }
        if shared.contains(.singleLegSquat) {
            compare(current.slsRight, previous.slsRight, "Single leg squat · Right")
            compare(current.slsLeft, previous.slsLeft, "Single leg squat · Left")
        }
        if shared.contains(.measurements) {
            for field in MeasurementField.allCases {
                if let cur = field.value(in: current.measurements), let prev = field.value(in: previous.measurements), cur != prev {
                    result.measurementDeltas.append(MeasurementDelta(field: field, delta: cur - prev))
                }
            }
        }
        return result
    }
}
