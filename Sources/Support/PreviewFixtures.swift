import Foundation
import SwiftData

/// In-memory data for #Preview blocks. Seeds synchronously through ModelContext so
/// previews need no async setup.
@MainActor
enum PreviewFixtures {
    static let clientId = UUID()
    static let benchId = UUID()
    static let squatId = UUID()
    static let instanceId = UUID()

    static let client = ClientDTO(
        id: clientId, name: "Sam Rivera", phoneE164: "+15551234567",
        goal: "Add 20 lb to bench", injuries: "Left knee — avoid deep squats",
        notes: nil, isArchived: false, createdAt: .now, updatedAt: .now
    )

    static let bench = ExerciseDTO(
        id: benchId, name: "Bench Press", category: .strength,
        metrics: [.weight, .reps, .sets], defaultUnit: .lb, isCustom: false, createdAt: .now, updatedAt: .now
    )
    static let squat = ExerciseDTO(
        id: squatId, name: "Goblet Squat", category: .strength,
        metrics: [.weight, .reps, .sets], defaultUnit: .lb, isCustom: false, createdAt: .now, updatedAt: .now
    )

    static let workout = WorkoutDTO(id: UUID(), name: "Upper A", entries: [
        WorkoutEntryDTO(id: UUID(), exerciseId: benchId, order: 0, targetSets: 3, targetReps: 8, targetWeight: 135, targetDuration: nil),
        WorkoutEntryDTO(id: UUID(), exerciseId: squatId, order: 1, targetSets: 3, targetReps: 10, targetWeight: 50, targetDuration: nil),
    ], createdAt: .now, updatedAt: .now)

    static let scheduledSession = SessionDTO(
        id: UUID(), clientId: clientId,
        startAt: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!,
        endAt: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!,
        status: .scheduled, notes: "Felt strong last week.",
        instances: [WorkoutInstanceDTO(
            id: instanceId, sourceWorkoutId: workout.id, name: "Upper A",
            plannedEntries: workout.entries.map {
                PlannedEntryDTO(
                    id: UUID(), exerciseId: $0.exerciseId, order: $0.order, targetSets: $0.targetSets,
                    targetReps: $0.targetReps, targetWeight: $0.targetWeight, targetDuration: $0.targetDuration
                )
            }
        )],
        seriesId: nil, recurrence: nil, eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )

    /// `scheduledSession` as one occurrence of a weekly series (preview only).
    static let seriesSession: SessionDTO = {
        var session = scheduledSession
        session.seriesId = UUID()
        session.recurrence = AppRecurrence(
            frequency: .weekly, interval: 1,
            weekdays: [Calendar.current.component(.weekday, from: session.startAt)],
            endDate: nil, occurrenceCount: nil
        )
        return session
    }()

    static let loggedSets: [SetRecordDTO] = [
        SetRecordDTO(
            id: UUID(), workoutInstanceId: instanceId, exerciseId: benchId, setIndex: 0,
            weight: 135, reps: 8, duration: nil, distance: nil, rpe: nil,
            performedAt: .now, createdAt: .now, updatedAt: .now
        ),
        SetRecordDTO(
            id: UUID(), workoutInstanceId: instanceId, exerciseId: benchId, setIndex: 1,
            weight: 135, reps: 7, duration: nil, distance: nil, rpe: nil,
            performedAt: .now, createdAt: .now, updatedAt: .now
        ),
    ]

    /// Every repository a preview may need, over one seeded container. Built here
    /// rather than inside `#Preview` because `@ModelActor` initializers are not
    /// visible from within another macro expansion.
    struct Repositories {
        let container: ModelContainer
        let sessions: SwiftDataSessionRepository
        let clients: SwiftDataClientRepository
        let workouts: SwiftDataWorkoutRepository
        let exercises: SwiftDataExerciseRepository
        let reporting: SwiftDataReportingQueries
        let archive: DataArchiveActor
        let reminders: ReminderCoordinator
    }

    static func repositories() -> Repositories {
        let container = container()
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let clients = SwiftDataClientRepository(modelContainer: container)
        return Repositories(
            container: container,
            sessions: sessions,
            clients: clients,
            workouts: SwiftDataWorkoutRepository(modelContainer: container),
            exercises: SwiftDataExerciseRepository(modelContainer: container),
            reporting: SwiftDataReportingQueries(modelContainer: container),
            archive: DataArchiveActor(modelContainer: container),
            reminders: ReminderCoordinator(
                sessionRepo: sessions, clientRepo: clients, notifications: LocalNotificationService()
            )
        )
    }

    /// A seeded in-memory container. Each call builds a fresh store.
    static func container() -> ModelContainer {
        let container = try! PersistenceController.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        ctx.insert(client.toModel())
        ctx.insert(bench.toModel())
        ctx.insert(squat.toModel())
        ctx.insert(workout.toModel())
        ctx.insert(scheduledSession.toModel())
        for set in loggedSets { ctx.insert(set.toModel()) }
        try! ctx.save()
        return container
    }
}
