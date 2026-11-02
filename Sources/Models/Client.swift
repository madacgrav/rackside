import Foundation
import SwiftData

@Model
final class Client {
    @Attribute(.unique) var id: UUID
    var name: String
    // Defaults on all post-v0 properties keep SwiftData lightweight migration happy.
    var phoneE164: String = ""
    var goal: String?
    var injuries: String?
    var notes: String?
    var isArchived: Bool = false
    /// The trainer's own profile when they use the app for themselves (v2).
    var isSelf: Bool = false
    // v3 intake profile
    var dateOfBirth: Date?
    var emergencyName: String?
    var emergencyRelationship: String?
    var emergencyPhoneE164: String?
    var physicianName: String?
    var physicianPhoneE164: String?
    var occupation: String?
    var trainingHistory: String?
    var availability: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        phoneE164: String = "",
        goal: String? = nil,
        injuries: String? = nil,
        notes: String? = nil,
        isArchived: Bool = false,
        isSelf: Bool = false,
        dateOfBirth: Date? = nil,
        emergencyName: String? = nil,
        emergencyRelationship: String? = nil,
        emergencyPhoneE164: String? = nil,
        physicianName: String? = nil,
        physicianPhoneE164: String? = nil,
        occupation: String? = nil,
        trainingHistory: String? = nil,
        availability: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.phoneE164 = phoneE164
        self.goal = goal
        self.injuries = injuries
        self.notes = notes
        self.isArchived = isArchived
        self.isSelf = isSelf
        self.dateOfBirth = dateOfBirth
        self.emergencyName = emergencyName
        self.emergencyRelationship = emergencyRelationship
        self.emergencyPhoneE164 = emergencyPhoneE164
        self.physicianName = physicianName
        self.physicianPhoneE164 = physicianPhoneE164
        self.occupation = occupation
        self.trainingHistory = trainingHistory
        self.availability = availability
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
