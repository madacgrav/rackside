import Foundation
import SwiftData

/// Yes answers to the app's own health-screening questions (not PAR-Q+ text).
struct ScreeningAnswers: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    static let heartOrBloodPressure = ScreeningAnswers(rawValue: 1 << 0)
    static let chestPain = ScreeningAnswers(rawValue: 1 << 1)
    static let dizzinessOrFainting = ScreeningAnswers(rawValue: 1 << 2)
    static let otherChronicCondition = ScreeningAnswers(rawValue: 1 << 3)
    static let chronicMedication = ScreeningAnswers(rawValue: 1 << 4)
    static let boneJointSoftTissue = ScreeningAnswers(rawValue: 1 << 5)
    static let supervisedOnly = ScreeningAnswers(rawValue: 1 << 6)

    /// Display order and wording.
    static let questions: [(ScreeningAnswers, String)] = [
        (.heartOrBloodPressure, "Has a doctor ever told you that you have a heart condition or high blood pressure?"),
        (.chestPain, "Do you feel pain or pressure in your chest at rest, during daily activities, or when active?"),
        (.dizzinessOrFainting, "In the last 12 months, have you lost your balance because of dizziness, or passed out?"),
        (.otherChronicCondition, "Have you been diagnosed with another long-term medical condition?"),
        (.chronicMedication, "Do you currently take prescription medication for a long-term condition?"),
        (.boneJointSoftTissue, "Do you have a bone, joint, muscle, or ligament problem (now or in the last 12 months) that activity could make worse?"),
        (.supervisedOnly, "Has a doctor said you should only be physically active under medical supervision?"),
    ]
}

enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, vigorous

    var title: String { rawValue.capitalized }
}

/// A dated health screening for a client (v3). Linked by `clientId`, not a
/// relationship, so client deletes remove these explicitly.
@Model
final class HealthScreening {
    @Attribute(.unique) var id: UUID
    var clientId: UUID
    var completedOn: Date
    var answersRaw: Int = 0
    var conditions: String?
    var surgeries: String?
    var medications: String?
    var familyHeartHistory: Bool = false
    var symptoms: String?
    var sleepHours: Double?
    /// 1 (low) … 5 (high).
    var stressLevel: Int?
    var tobacco: Bool = false
    var alcoholPerWeek: Int?
    var activityLevelRaw: String?
    var clearanceReceivedOn: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        clientId: UUID,
        completedOn: Date,
        answersRaw: Int = 0,
        conditions: String? = nil,
        surgeries: String? = nil,
        medications: String? = nil,
        familyHeartHistory: Bool = false,
        symptoms: String? = nil,
        sleepHours: Double? = nil,
        stressLevel: Int? = nil,
        tobacco: Bool = false,
        alcoholPerWeek: Int? = nil,
        activityLevelRaw: String? = nil,
        clearanceReceivedOn: Date? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.clientId = clientId
        self.completedOn = completedOn
        self.answersRaw = answersRaw
        self.conditions = conditions
        self.surgeries = surgeries
        self.medications = medications
        self.familyHeartHistory = familyHeartHistory
        self.symptoms = symptoms
        self.sleepHours = sleepHours
        self.stressLevel = stressLevel
        self.tobacco = tobacco
        self.alcoholPerWeek = alcoholPerWeek
        self.activityLevelRaw = activityLevelRaw
        self.clearanceReceivedOn = clearanceReceivedOn
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
