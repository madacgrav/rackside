import Foundation

struct ClientDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var phoneE164: String
    var goal: String?
    var injuries: String?
    var notes: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Device-local flag; intentionally excluded from the export format.
    var isSelf: Bool = false
    // v3 intake profile (exported)
    var dateOfBirth: Date? = nil
    var emergencyName: String? = nil
    var emergencyRelationship: String? = nil
    var emergencyPhoneE164: String? = nil
    var physicianName: String? = nil
    var physicianPhoneE164: String? = nil
    var occupation: String? = nil
    var trainingHistory: String? = nil
    var availability: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, phoneE164, goal, injuries, notes, isArchived, createdAt, updatedAt
        case dateOfBirth, emergencyName, emergencyRelationship, emergencyPhoneE164, physicianName, physicianPhoneE164, occupation, trainingHistory, availability
    }
}

extension ClientDTO {
    /// Any intake profile field filled in (drives the detail screen's Profile section).
    var hasProfile: Bool {
        dateOfBirth != nil || occupation != nil || trainingHistory != nil || availability != nil
            || emergencyName != nil || emergencyRelationship != nil || emergencyPhoneE164 != nil
            || physicianName != nil || physicianPhoneE164 != nil
    }

    init(_ model: Client) {
        self.init(
            id: model.id,
            name: model.name,
            phoneE164: model.phoneE164,
            goal: model.goal,
            injuries: model.injuries,
            notes: model.notes,
            isArchived: model.isArchived,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            isSelf: model.isSelf,
            dateOfBirth: model.dateOfBirth,
            emergencyName: model.emergencyName,
            emergencyRelationship: model.emergencyRelationship,
            emergencyPhoneE164: model.emergencyPhoneE164,
            physicianName: model.physicianName,
            physicianPhoneE164: model.physicianPhoneE164,
            occupation: model.occupation,
            trainingHistory: model.trainingHistory,
            availability: model.availability
        )
    }

    func apply(to model: Client) {
        model.name = name
        model.phoneE164 = phoneE164
        model.goal = goal
        model.injuries = injuries
        model.notes = notes
        model.isArchived = isArchived
        model.isSelf = isSelf
        model.dateOfBirth = dateOfBirth
        model.emergencyName = emergencyName
        model.emergencyRelationship = emergencyRelationship
        model.emergencyPhoneE164 = emergencyPhoneE164
        model.physicianName = physicianName
        model.physicianPhoneE164 = physicianPhoneE164
        model.occupation = occupation
        model.trainingHistory = trainingHistory
        model.availability = availability
        model.updatedAt = .now
    }

    func toModel() -> Client {
        Client(
            id: id,
            name: name,
            phoneE164: phoneE164,
            goal: goal,
            injuries: injuries,
            notes: notes,
            isArchived: isArchived,
            isSelf: isSelf,
            dateOfBirth: dateOfBirth,
            emergencyName: emergencyName,
            emergencyRelationship: emergencyRelationship,
            emergencyPhoneE164: emergencyPhoneE164,
            physicianName: physicianName,
            physicianPhoneE164: physicianPhoneE164,
            occupation: occupation,
            trainingHistory: trainingHistory,
            availability: availability,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
