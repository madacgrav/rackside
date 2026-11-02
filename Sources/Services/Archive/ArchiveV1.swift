import Foundation

/// Version 1 of the export archive. FROZEN once shipped — never edit after
/// release. A future breaking change adds Archive/V2 with its own types plus a
/// pure `migrate(_ v1:) -> ArchiveV2.Envelope`, leaving this file untouched.
/// (For v1 the DTO types are shared with the live app; V2 snapshots copies
/// before diverging.)
enum ArchiveV1 {
    static let schemaVersion = 1

    struct Envelope: Codable, Sendable {
        var schemaVersion: Int = ArchiveV1.schemaVersion
        let exportedAt: Date
        let appVersion: String
        var clients: [ClientDTO]
        var exercises: [ExerciseDTO]
        var workouts: [WorkoutDTO]
        var sessions: [SessionDTO]
        var setRecords: [SetRecordDTO]
    }
}

/// Decoded FIRST on import, before attempting the full envelope, so unknown
/// newer formats fail with a clear error instead of a keyNotFound mess.
struct VersionProbe: Decodable {
    let schemaVersion: Int
}
