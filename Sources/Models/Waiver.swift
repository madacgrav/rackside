import Foundation
import SwiftData

/// The trainer's liability-waiver text (a single row). `version` bumps whenever
/// the body changes, and each sent waiver records the version it used.
@Model
final class WaiverTemplate {
    @Attribute(.unique) var id: UUID
    var version: Int = 1
    var body: String = ""
    var updatedAt: Date

    init(id: UUID = UUID(), version: Int = 1, body: String, updatedAt: Date = .now) {
        self.id = id
        self.version = version
        self.body = body
        self.updatedAt = updatedAt
    }
}

/// One waiver sent to a client, with a snapshot of exactly what was sent (v3).
/// Linked by `clientId`, not a relationship, so client deletes remove these explicitly.
@Model
final class WaiverRecord {
    @Attribute(.unique) var id: UUID
    var clientId: UUID
    var sentOn: Date
    var templateVersion: Int = 1
    var templateBody: String = ""
    var returnedSignedOn: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        clientId: UUID,
        sentOn: Date,
        templateVersion: Int,
        templateBody: String,
        returnedSignedOn: Date? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.clientId = clientId
        self.sentOn = sentOn
        self.templateVersion = templateVersion
        self.templateBody = templateBody
        self.returnedSignedOn = returnedSignedOn
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
