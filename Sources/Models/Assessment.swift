import Foundation
import SwiftData

/// A checklist of compensations (NASM form page 1) packed into an Int, like MetricSet.
protocol CompensationSet: OptionSet, Codable, Sendable, Hashable where RawValue == Int, Element == Self {
    /// Display order and the form's labels.
    static var items: [(Self, String)] { get }
}

struct AssessmentSections: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int
    static let measurements = AssessmentSections(rawValue: 1 << 0)
    static let overheadSquat = AssessmentSections(rawValue: 1 << 1)
    static let singleLegSquat = AssessmentSections(rawValue: 1 << 2)
    static let all: AssessmentSections = [.measurements, .overheadSquat, .singleLegSquat]

    /// "Measurements · OHS · SLS".
    var caption: String {
        [(Self.measurements, "Measurements"), (.overheadSquat, "OHS"), (.singleLegSquat, "SLS")]
            .filter { contains($0.0) }
            .map(\.1)
            .joined(separator: " · ")
    }
}

/// Overhead Squat — anterior view, scored per side.
struct OHSAnterior: CompensationSet {
    let rawValue: Int
    static let footTurnsOut = OHSAnterior(rawValue: 1 << 0)
    static let kneeMovesInward = OHSAnterior(rawValue: 1 << 1)
    static let kneeMovesOutward = OHSAnterior(rawValue: 1 << 2)
    static let items: [(OHSAnterior, String)] = [
        (.footTurnsOut, "Foot turns out"),
        (.kneeMovesInward, "Knee moves inward"),
        (.kneeMovesOutward, "Knee moves outward"),
    ]
}

/// Overhead Squat — lateral view (right side), yes/no.
struct OHSLateral: CompensationSet {
    let rawValue: Int
    static let excessiveForwardLean = OHSLateral(rawValue: 1 << 0)
    static let lowBackArches = OHSLateral(rawValue: 1 << 1)
    static let lowBackRounds = OHSLateral(rawValue: 1 << 2)
    static let armsFallForward = OHSLateral(rawValue: 1 << 3)
    static let items: [(OHSLateral, String)] = [
        (.excessiveForwardLean, "Excessive forward lean"),
        (.lowBackArches, "Low back arches"),
        (.lowBackRounds, "Low back rounds"),
        (.armsFallForward, "Arms fall forward"),
    ]
}

/// Overhead Squat — posterior view, scored per side.
struct OHSPosterior: CompensationSet {
    let rawValue: Int
    static let heelOfFootRises = OHSPosterior(rawValue: 1 << 0)
    static let footFlattens = OHSPosterior(rawValue: 1 << 1)
    static let asymmetricalWeightShift = OHSPosterior(rawValue: 1 << 2)
    static let items: [(OHSPosterior, String)] = [
        (.heelOfFootRises, "Heel of foot rises"),
        (.footFlattens, "Foot flattens"),
        (.asymmetricalWeightShift, "Asymmetrical weight shift"),
    ]
}

/// Modified retests (heels elevated / arms down): regions where the compensation went away.
struct OHSRegions: CompensationSet {
    let rawValue: Int
    static let feet = OHSRegions(rawValue: 1 << 0)
    static let knees = OHSRegions(rawValue: 1 << 1)
    static let lphc = OHSRegions(rawValue: 1 << 2)
    static let upperBody = OHSRegions(rawValue: 1 << 3)
    static let items: [(OHSRegions, String)] = [
        (.feet, "Feet"), (.knees, "Knees"), (.lphc, "LPHC"), (.upperBody, "Upper body"),
    ]
}

/// Single Leg Squat, scored per leg.
struct SLSCompensations: CompensationSet {
    let rawValue: Int
    static let footFlattens = SLSCompensations(rawValue: 1 << 0)
    static let kneeMovesInward = SLSCompensations(rawValue: 1 << 1)
    static let kneeMovesOutward = SLSCompensations(rawValue: 1 << 2)
    static let hipHike = SLSCompensations(rawValue: 1 << 3)
    static let hipDrop = SLSCompensations(rawValue: 1 << 4)
    static let inwardTrunkRotation = SLSCompensations(rawValue: 1 << 5)
    static let outwardTrunkRotation = SLSCompensations(rawValue: 1 << 6)
    static let items: [(SLSCompensations, String)] = [
        (.footFlattens, "Foot flattens"),
        (.kneeMovesInward, "Knee moves inward"),
        (.kneeMovesOutward, "Knee moves outward"),
        (.hipHike, "Hip hike"),
        (.hipDrop, "Hip drop"),
        (.inwardTrunkRotation, "Inward trunk rotation"),
        (.outwardTrunkRotation, "Outward trunk rotation"),
    ]
}

/// Baseline measurements, stored metric (kg, cm).
struct Measurements: Codable, Equatable, Sendable {
    var restingHR: Int?
    var systolic: Int?
    var diastolic: Int?
    var heightCm: Double?
    var weightKg: Double?
    var waistCm: Double?
    var hipCm: Double?
    var bodyFatPct: Double?
    var pushUps: Int?
    var plankSeconds: Int?

    static let cmPerInch = 2.54
    static let kgPerLb = 0.45359237

    var waistToHip: Double? {
        guard let waistCm, let hipCm, hipCm > 0 else { return nil }
        return waistCm / hipCm
    }

    var bmi: Double? {
        guard let heightCm, let weightKg, heightCm > 0 else { return nil }
        return weightKg / pow(heightCm / 100, 2)
    }

    var isEmpty: Bool { self == Measurements() }
}

/// A dated movement/measurement assessment for a client (v3). Linked by
/// `clientId`, not a relationship, so client deletes remove these explicitly.
@Model
final class Assessment {
    @Attribute(.unique) var id: UUID
    var clientId: UUID
    var performedOn: Date
    var sectionsRaw: Int = 0
    /// JSON-encoded `Measurements`, like Session.recurrenceData.
    var measurementsData: Data?
    var ohsAnteriorRightRaw: Int = 0
    var ohsAnteriorLeftRaw: Int = 0
    var ohsLateralRaw: Int = 0
    var ohsPosteriorRightRaw: Int = 0
    var ohsPosteriorLeftRaw: Int = 0
    var ohsHeelsElevatedRaw: Int = 0
    var ohsArmsDownRaw: Int = 0
    var ohsNotes: String?
    var slsRightRaw: Int = 0
    var slsLeftRaw: Int = 0
    var slsNotes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        clientId: UUID,
        performedOn: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.clientId = clientId
        self.performedOn = performedOn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
