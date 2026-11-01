import Foundation
import Observation

@MainActor
@Observable
final class ClientEditViewModel {
    private let repo: any ClientRepository
    private let existing: ClientDTO?
    /// Self-use profile: no phone number required and none shown.
    let isSelf: Bool

    var name: String
    var phoneRaw: String
    var goal: String
    var injuries: String
    var notes: String
    // Intake profile (v3)
    var hasDateOfBirth: Bool
    var dateOfBirth: Date
    var occupation: String
    var trainingHistory: String
    var availability: String
    var emergencyName: String
    var emergencyRelationship: String
    var emergencyPhoneRaw: String
    var physicianName: String
    var physicianPhoneRaw: String
    var errorMessage: String?
    /// The client as last saved from this form (used to offer intake after create).
    private(set) var savedClient: ClientDTO?

    init(repo: any ClientRepository, existing: ClientDTO?, isSelf: Bool = false) {
        self.repo = repo
        self.existing = existing
        self.isSelf = existing?.isSelf ?? isSelf
        self.name = existing?.name ?? ""
        self.phoneRaw = existing?.phoneE164 ?? ""
        self.goal = existing?.goal ?? ""
        self.injuries = existing?.injuries ?? ""
        self.notes = existing?.notes ?? ""
        self.hasDateOfBirth = existing?.dateOfBirth != nil
        self.dateOfBirth = existing?.dateOfBirth
            ?? Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
        self.occupation = existing?.occupation ?? ""
        self.trainingHistory = existing?.trainingHistory ?? ""
        self.availability = existing?.availability ?? ""
        self.emergencyName = existing?.emergencyName ?? ""
        self.emergencyRelationship = existing?.emergencyRelationship ?? ""
        self.emergencyPhoneRaw = existing?.emergencyPhoneE164 ?? ""
        self.physicianName = existing?.physicianName ?? ""
        self.physicianPhoneRaw = existing?.physicianPhoneE164 ?? ""
    }

    var isEditing: Bool { existing != nil }

    var phoneValid: Bool { normalizeE164(phoneRaw) != nil }

    /// Optional phones: empty is fine, anything typed must normalize.
    var emergencyPhoneValid: Bool { emergencyPhoneRaw.isEmpty || normalizeE164(emergencyPhoneRaw) != nil }
    var physicianPhoneValid: Bool { physicianPhoneRaw.isEmpty || normalizeE164(physicianPhoneRaw) != nil }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (isSelf || phoneValid)
            && emergencyPhoneValid && physicianPhoneValid
    }

    /// The DTO this form would save, or nil when the phone does not normalize.
    func makeDTO() -> ClientDTO? {
        let phone = isSelf ? (normalizeE164(phoneRaw) ?? "") : normalizeE164(phoneRaw)
        guard let phone else { return nil }
        return ClientDTO(
            id: existing?.id ?? draftId,
            name: name.trimmingCharacters(in: .whitespaces),
            phoneE164: phone,
            goal: goal.isEmpty ? nil : goal,
            injuries: injuries.isEmpty ? nil : injuries,
            notes: notes.isEmpty ? nil : notes,
            isArchived: existing?.isArchived ?? false,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now,
            isSelf: isSelf,
            dateOfBirth: hasDateOfBirth ? dateOfBirth : nil,
            emergencyName: Self.nilIfBlank(emergencyName),
            emergencyRelationship: Self.nilIfBlank(emergencyRelationship),
            emergencyPhoneE164: normalizeE164(emergencyPhoneRaw),
            physicianName: Self.nilIfBlank(physicianName),
            physicianPhoneE164: normalizeE164(physicianPhoneRaw),
            occupation: Self.nilIfBlank(occupation),
            trainingHistory: Self.nilIfBlank(trainingHistory),
            availability: Self.nilIfBlank(availability)
        )
    }

    func save() async -> Bool {
        errorMessage = nil
        guard let dto = makeDTO() else { return false }
        do {
            try await repo.upsert(dto)
            savedClient = dto
            return true
        } catch {
            errorMessage = "Couldn't save the client. Please try again."
            return false
        }
    }

    /// Stable id for a new client, so repeated saves (intake flow) update one row.
    private let draftId = UUID()

    private static func nilIfBlank(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
