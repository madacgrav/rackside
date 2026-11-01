import Foundation
import Observation

@MainActor
@Observable
final class HealthScreeningEditViewModel {
    private let repo: any HealthScreeningRepository
    private let existing: HealthScreeningDTO?
    let clientId: UUID

    var completedOn: Date
    var answers: ScreeningAnswers
    var conditions: String
    var surgeries: String
    var medications: String
    var familyHeartHistory: Bool
    var symptoms: String
    var sleepHours: Double?
    /// 0 = not recorded, otherwise 1…5.
    var stressLevel: Int
    var tobacco: Bool
    var alcoholPerWeek: Int?
    var activityLevel: ActivityLevel?
    var hasClearance: Bool
    var clearanceReceivedOn: Date
    var notes: String
    var errorMessage: String?
    private(set) var savedScreening: HealthScreeningDTO?

    init(repo: any HealthScreeningRepository, clientId: UUID, existing: HealthScreeningDTO?) {
        self.repo = repo
        self.clientId = clientId
        self.existing = existing
        completedOn = existing?.completedOn ?? .now
        answers = existing?.answers ?? []
        conditions = existing?.conditions ?? ""
        surgeries = existing?.surgeries ?? ""
        medications = existing?.medications ?? ""
        familyHeartHistory = existing?.familyHeartHistory ?? false
        symptoms = existing?.symptoms ?? ""
        sleepHours = existing?.sleepHours
        stressLevel = existing?.stressLevel ?? 0
        tobacco = existing?.tobacco ?? false
        alcoholPerWeek = existing?.alcoholPerWeek
        activityLevel = existing?.activityLevel
        hasClearance = existing?.clearanceReceivedOn != nil
        clearanceReceivedOn = existing?.clearanceReceivedOn ?? .now
        notes = existing?.notes ?? ""
    }

    var isEditing: Bool { existing != nil }
    var anyYes: Bool { !answers.isEmpty }
    var canSave: Bool { true }

    func isYes(_ question: ScreeningAnswers) -> Bool { answers.contains(question) }

    func set(_ question: ScreeningAnswers, _ yes: Bool) {
        if yes { answers.insert(question) } else { answers.remove(question) }
    }

    func makeDTO() -> HealthScreeningDTO {
        HealthScreeningDTO(
            id: existing?.id ?? draftId,
            clientId: clientId,
            completedOn: completedOn,
            answers: answers,
            conditions: Self.nilIfBlank(conditions),
            surgeries: Self.nilIfBlank(surgeries),
            medications: Self.nilIfBlank(medications),
            familyHeartHistory: familyHeartHistory,
            symptoms: Self.nilIfBlank(symptoms),
            sleepHours: sleepHours,
            stressLevel: stressLevel == 0 ? nil : stressLevel,
            tobacco: tobacco,
            alcoholPerWeek: alcoholPerWeek,
            activityLevel: activityLevel,
            // Clearance only means something when there is a YES to clear.
            clearanceReceivedOn: anyYes && hasClearance ? clearanceReceivedOn : nil,
            notes: Self.nilIfBlank(notes),
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
    }

    func save() async -> Bool {
        errorMessage = nil
        let dto = makeDTO()
        do {
            try await repo.upsert(dto)
            savedScreening = dto
            return true
        } catch {
            Log.persistence.error("Screening save failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save the screening. Please try again."
            return false
        }
    }

    /// Stable id for a new screening, so repeated saves (intake flow) update one row.
    private let draftId = UUID()

    private static func nilIfBlank(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
