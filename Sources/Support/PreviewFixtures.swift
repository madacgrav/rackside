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

    /// Four sessions across the current week for the week preview. Instance and entry ids are fresh
    /// because they are unique in the store.
    static let weekSessions: [SessionDTO] = {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        let base = scheduledSession
        let recurrence = seriesSession.recurrence
        func make(day: Int, hour: Int, minute: Int = 0, status: SessionStatus, series: Bool = false) -> SessionDTO {
            let dayStart = calendar.date(byAdding: .day, value: day, to: weekStart)!
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
            return SessionDTO(
                id: UUID(), clientId: base.clientId, startAt: start,
                endAt: start.addingTimeInterval(3600), status: status, notes: base.notes,
                instances: base.instances.map { instance in
                    WorkoutInstanceDTO(
                        id: UUID(), sourceWorkoutId: instance.sourceWorkoutId, name: instance.name,
                        plannedEntries: instance.plannedEntries.map {
                            PlannedEntryDTO(
                                id: UUID(), exerciseId: $0.exerciseId, order: $0.order, targetSets: $0.targetSets,
                                targetReps: $0.targetReps, targetWeight: $0.targetWeight, targetDuration: $0.targetDuration
                            )
                        }
                    )
                },
                seriesId: series ? UUID() : nil, recurrence: series ? recurrence : nil,
                eventIdentifier: nil, createdAt: .now, updatedAt: .now
            )
        }
        return [
            make(day: 1, hour: 7, status: .completed),
            make(day: 1, hour: 17, minute: 30, status: .scheduled, series: true),
            make(day: 3, hour: 9, status: .scheduled),
            make(day: 4, hour: 6, status: .cancelled),
        ]
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

    static func repositories(seedingWeek: Bool = false) -> Repositories {
        let container = container(seedingWeek: seedingWeek)
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
    static func container(seedingWeek: Bool = false) -> ModelContainer {
        let container = try! PersistenceController.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        ctx.insert(client.toModel())
        ctx.insert(bench.toModel())
        ctx.insert(squat.toModel())
        ctx.insert(workout.toModel())
        ctx.insert(scheduledSession.toModel())
        for set in loggedSets { ctx.insert(set.toModel()) }
        if seedingWeek { weekSessions.forEach { ctx.insert($0.toModel()) } }
        try! ctx.save()
        return container
    }
}
