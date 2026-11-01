import Foundation

struct HealthScreeningDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var clientId: UUID
    var completedOn: Date
    var answers: ScreeningAnswers
    var conditions: String?
    var surgeries: String?
    var medications: String?
    var familyHeartHistory: Bool
    var symptoms: String?
    var sleepHours: Double?
    var stressLevel: Int?
    var tobacco: Bool
    var alcoholPerWeek: Int?
    var activityLevel: ActivityLevel?
    var clearanceReceivedOn: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

extension HealthScreeningDTO {
    init(_ model: HealthScreening) {
        self.init(
            id: model.id,
            clientId: model.clientId,
            completedOn: model.completedOn,
            answers: ScreeningAnswers(rawValue: model.answersRaw),
            conditions: model.conditions,
            surgeries: model.surgeries,
            medications: model.medications,
            familyHeartHistory: model.familyHeartHistory,
            symptoms: model.symptoms,
            sleepHours: model.sleepHours,
            stressLevel: model.stressLevel,
            tobacco: model.tobacco,
            alcoholPerWeek: model.alcoholPerWeek,
            activityLevel: model.activityLevelRaw.flatMap(ActivityLevel.init(rawValue:)),
            clearanceReceivedOn: model.clearanceReceivedOn,
            notes: model.notes,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    func apply(to model: HealthScreening) {
        model.completedOn = completedOn
        model.answersRaw = answers.rawValue
        model.conditions = conditions
        model.surgeries = surgeries
        model.medications = medications
        model.familyHeartHistory = familyHeartHistory
        model.symptoms = symptoms
        model.sleepHours = sleepHours
        model.stressLevel = stressLevel
        model.tobacco = tobacco
        model.alcoholPerWeek = alcoholPerWeek
        model.activityLevelRaw = activityLevel?.rawValue
        model.clearanceReceivedOn = clearanceReceivedOn
        model.notes = notes
        model.updatedAt = .now
    }

    func toModel() -> HealthScreening {
        HealthScreening(
            id: id,
            clientId: clientId,
            completedOn: completedOn,
            answersRaw: answers.rawValue,
            conditions: conditions,
            surgeries: surgeries,
            medications: medications,
            familyHeartHistory: familyHeartHistory,
            symptoms: symptoms,
            sleepHours: sleepHours,
            stressLevel: stressLevel,
            tobacco: tobacco,
            alcoholPerWeek: alcoholPerWeek,
            activityLevelRaw: activityLevel?.rawValue,
            clearanceReceivedOn: clearanceReceivedOn,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum ClearanceStatus: Equatable, Sendable {
    case notScreened, clear, needed, received(Date)
}

extension HealthScreeningDTO {
    static let reviewInterval = DateComponents(month: 12)

    /// The latest screening decides: any YES without a clearance date → needed.
    static func clearance(for latest: HealthScreeningDTO?) -> ClearanceStatus {
        guard let latest else { return .notScreened }
        guard !latest.answers.isEmpty else { return .clear }
        if let on = latest.clearanceReceivedOn { return .received(on) }
        return .needed
    }

    /// Screenings are reviewed at least every 12 months.
    static func reviewDue(_ latest: HealthScreeningDTO?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let latest, let due = calendar.date(byAdding: reviewInterval, to: latest.completedOn) else { return false }
        return now >= due
    }
}
