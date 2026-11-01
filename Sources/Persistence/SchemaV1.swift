import Foundation
import SwiftData

/// First versioned schema: a frozen snapshot of the models exactly as shipped in
/// 1.0. SwiftData needs each version's model classes to differ (identical classes
/// produce "duplicate version checksums"), so these copies live here and are never
/// edited; the live classes in Sources/Models form the current schema.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Exercise.self, Workout.self, WorkoutEntry.self,
         Session.self, WorkoutInstance.self, PlannedEntry.self, SetRecord.self]
    }
    /// Stable string for StoreBackup's defaults key ("1.0.0").
    static var versionString: String {
        let v = versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }

    @Model
    final class Client {
        @Attribute(.unique) var id: UUID
        var name: String
        var phoneE164: String = ""
        var goal: String?
        var injuries: String?
        var notes: String?
        var isArchived: Bool = false
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), name: String, phoneE164: String = "", goal: String? = nil, injuries: String? = nil,
             notes: String? = nil, isArchived: Bool = false, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id
            self.name = name
            self.phoneE164 = phoneE164
            self.goal = goal
            self.injuries = injuries
            self.notes = notes
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class Exercise {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String = ExerciseCategory.strength.rawValue
        var metricsRaw: Int = 0
        var defaultUnitRaw: String = Unit.lb.rawValue
        var isCustom: Bool = false
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), name: String, category: ExerciseCategory, metrics: MetricSet, defaultUnit: Unit,
             isCustom: Bool = false, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id
            self.name = name
            self.categoryRaw = category.rawValue
            self.metricsRaw = metrics.rawValue
            self.defaultUnitRaw = defaultUnit.rawValue
            self.isCustom = isCustom
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class Workout {
        @Attribute(.unique) var id: UUID
        var name: String
        @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout)
        var entries: [WorkoutEntry] = []
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), name: String, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class WorkoutEntry {
        @Attribute(.unique) var id: UUID
        var exerciseId: UUID
        var order: Int
        var targetSets: Int?
        var targetReps: Int?
        var targetWeight: Double?
        var targetDuration: Int?
        var workout: Workout?

        init(id: UUID = UUID(), exerciseId: UUID, order: Int, targetSets: Int? = nil, targetReps: Int? = nil,
             targetWeight: Double? = nil, targetDuration: Int? = nil) {
            self.id = id
            self.exerciseId = exerciseId
            self.order = order
            self.targetSets = targetSets
            self.targetReps = targetReps
            self.targetWeight = targetWeight
            self.targetDuration = targetDuration
        }
    }

    @Model
    final class Session {
        @Attribute(.unique) var id: UUID
        var clientId: UUID
        var startAt: Date
        var endAt: Date
        var statusRaw: String = SessionStatus.scheduled.rawValue
        var notes: String?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutInstance.session)
        var instances: [WorkoutInstance] = []
        var seriesId: UUID?
        var recurrenceData: Data?
        var eventIdentifier: String?
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), clientId: UUID, startAt: Date, endAt: Date, status: SessionStatus = .scheduled,
             notes: String? = nil, seriesId: UUID? = nil, recurrenceData: Data? = nil, eventIdentifier: String? = nil,
             createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id
            self.clientId = clientId
            self.startAt = startAt
            self.endAt = endAt
            self.statusRaw = status.rawValue
            self.notes = notes
            self.seriesId = seriesId
            self.recurrenceData = recurrenceData
            self.eventIdentifier = eventIdentifier
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class WorkoutInstance {
        @Attribute(.unique) var id: UUID
        var sourceWorkoutId: UUID
        var name: String = ""
        @Relationship(deleteRule: .cascade, inverse: \PlannedEntry.instance)
        var plannedEntries: [PlannedEntry] = []
        var session: Session?

        init(id: UUID = UUID(), sourceWorkoutId: UUID, name: String) {
            self.id = id
            self.sourceWorkoutId = sourceWorkoutId
            self.name = name
        }
    }

    @Model
    final class PlannedEntry {
        @Attribute(.unique) var id: UUID
        var exerciseId: UUID
        var order: Int
        var targetSets: Int?
        var targetReps: Int?
        var targetWeight: Double?
        var targetDuration: Int?
        var instance: WorkoutInstance?

        init(id: UUID = UUID(), exerciseId: UUID, order: Int, targetSets: Int? = nil, targetReps: Int? = nil,
             targetWeight: Double? = nil, targetDuration: Int? = nil) {
            self.id = id
            self.exerciseId = exerciseId
            self.order = order
            self.targetSets = targetSets
            self.targetReps = targetReps
            self.targetWeight = targetWeight
            self.targetDuration = targetDuration
        }
    }

    @Model
    final class SetRecord {
        @Attribute(.unique) var id: UUID
        var workoutInstanceId: UUID
        var exerciseId: UUID
        var setIndex: Int
        var weight: Double?
        var reps: Int?
        var duration: Int?
        var distance: Double?
        var rpe: Double?
        var performedAt: Date
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), workoutInstanceId: UUID, exerciseId: UUID, setIndex: Int, weight: Double? = nil,
             reps: Int? = nil, duration: Int? = nil, distance: Double? = nil, rpe: Double? = nil,
             performedAt: Date = .now, createdAt: Date = .now, updatedAt: Date = .now) {
            self.id = id
            self.workoutInstanceId = workoutInstanceId
            self.exerciseId = exerciseId
            self.setIndex = setIndex
            self.weight = weight
            self.reps = reps
            self.duration = duration
            self.distance = distance
            self.rpe = rpe
            self.performedAt = performedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

enum TrainMeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
         .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)]
    }
}
