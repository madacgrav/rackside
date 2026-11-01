import Foundation

struct WaiverTemplateDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var version: Int
    var body: String
    var updatedAt: Date
}

extension WaiverTemplateDTO {
    init(_ model: WaiverTemplate) {
        self.init(id: model.id, version: model.version, body: model.body, updatedAt: model.updatedAt)
    }

    func toModel() -> WaiverTemplate {
        WaiverTemplate(id: id, version: version, body: body, updatedAt: updatedAt)
    }
}

struct WaiverRecordDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var clientId: UUID
    var sentOn: Date
    var templateVersion: Int
    var templateBody: String
    var returnedSignedOn: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

extension WaiverRecordDTO {
    init(_ model: WaiverRecord) {
        self.init(
            id: model.id,
            clientId: model.clientId,
            sentOn: model.sentOn,
            templateVersion: model.templateVersion,
            templateBody: model.templateBody,
            returnedSignedOn: model.returnedSignedOn,
            notes: model.notes,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    func toModel() -> WaiverRecord {
        WaiverRecord(
            id: id,
            clientId: clientId,
            sentOn: sentOn,
            templateVersion: templateVersion,
            templateBody: templateBody,
            returnedSignedOn: returnedSignedOn,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum WaiverStatus: Equatable, Sendable {
    case none, sent(Date), signed(Date)
}

extension WaiverRecordDTO {
    /// Any signed record wins over a later unsigned resend; otherwise the newest send.
    static func status(_ records: [WaiverRecordDTO]) -> WaiverStatus {
        if let signed = records.compactMap(\.returnedSignedOn).max() { return .signed(signed) }
        if let sent = records.map(\.sentOn).max() { return .sent(sent) }
        return .none
    }
}
