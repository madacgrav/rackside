import Foundation

/// Version 2 of the export archive: adds client intake data. Editable until the
/// intake branch merges, then FROZEN like ArchiveV1. V1 files decode through
/// ArchiveV1.Envelope and `migrate` (new arrays empty; new optional ClientDTO
/// fields decode as nil, guarded by goldenV1FixtureImports).
enum ArchiveV2 {
    static let schemaVersion = 2

    struct Envelope: Codable, Sendable {
        var schemaVersion: Int = ArchiveV2.schemaVersion
        let exportedAt: Date
        let appVersion: String
        var clients: [ClientDTO]
        var exercises: [ExerciseDTO]
        var workouts: [WorkoutDTO]
        var sessions: [SessionDTO]
        var setRecords: [SetRecordDTO]
        var healthScreenings: [HealthScreeningDTO]
    }

    static func migrate(_ v1: ArchiveV1.Envelope) -> Envelope {
        Envelope(
            exportedAt: v1.exportedAt,
            appVersion: v1.appVersion,
            clients: v1.clients,
            exercises: v1.exercises,
            workouts: v1.workouts,
            sessions: v1.sessions,
            setRecords: v1.setRecords,
            healthScreenings: []
        )
    }
}

/// Repointed when a new archive version ships.
typealias CurrentArchive = ArchiveV2.Envelope
