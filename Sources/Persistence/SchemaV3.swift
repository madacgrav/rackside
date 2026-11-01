import SwiftData

/// Current schema: the live model classes in Sources/Models. Adds client intake
/// (profile fields, HealthScreening, Assessment, WaiverTemplate, WaiverRecord).
/// Editable until the intake branch merges; then freeze it like SchemaV2.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Exercise.self, Workout.self, WorkoutEntry.self,
         Session.self, WorkoutInstance.self, PlannedEntry.self, SetRecord.self,
         HealthScreening.self, Assessment.self]
    }
    /// Stable string for StoreBackup's defaults key ("3.0.0").
    static var versionString: String {
        let v = versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }
}
