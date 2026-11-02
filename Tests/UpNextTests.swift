import Foundation
import Testing
@testable import Rackside

private func exercise(_ name: String, _ metrics: MetricSet) -> ExerciseDTO {
    ExerciseDTO(id: UUID(), name: name, category: .bodyweight, metrics: metrics, defaultUnit: .sec,
                isCustom: false, createdAt: .now, updatedAt: .now)
}

private func entry(_ exercise: ExerciseDTO, order: Int, sets: Int = 2, duration: Int? = nil) -> PlannedEntryDTO {
    PlannedEntryDTO(id: UUID(), exerciseId: exercise.id, order: order, targetSets: sets,
                    targetReps: nil, targetWeight: nil, targetDuration: duration)
}

private func set(_ exercise: ExerciseDTO, instance: UUID, duration: Int? = nil) -> SetRecordDTO {
    SetRecordDTO(id: UUID(), workoutInstanceId: instance, exerciseId: exercise.id, setIndex: 0,
                 weight: nil, reps: nil, duration: duration, distance: nil, rpe: nil,
                 performedAt: .now, createdAt: .now, updatedAt: .now)
}

private let plank = exercise("Plank", [.duration])
private let bench = exercise("Bench", [.weight, .reps])
private let exercises = [plank.id: plank, bench.id: bench]

@Test func firstUnfinishedTimedEntryWins() {
    let planked = entry(plank, order: 0, duration: 45)
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A", plannedEntries: [planked])
    let next = deriveUpNext(instances: [instance], recorded: [:], exercises: exercises, previous: [:])
    #expect(next == UpNext(plannedEntryId: planked.id, instanceId: instance.id, exerciseName: "Plank", seconds: 45))
}

@Test func skipsFinishedEntries() {
    let benched = entry(bench, order: 0, sets: 1)
    let planked = entry(plank, order: 1, duration: 30)
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A", plannedEntries: [benched, planked])
    let recorded = [instance.id: [set(bench, instance: instance.id)]]
    #expect(deriveUpNext(instances: [instance], recorded: recorded, exercises: exercises, previous: [:])?.plannedEntryId == planked.id)
}

@Test func nilWhenNextEntryNotTimed() {
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A",
                                      plannedEntries: [entry(bench, order: 0), entry(plank, order: 1, duration: 30)])
    #expect(deriveUpNext(instances: [instance], recorded: [:], exercises: exercises, previous: [:]) == nil)
}

@Test func usesPreviousDurationWithoutTarget() {
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A", plannedEntries: [entry(plank, order: 0)])
    let previous = [plank.id: set(plank, instance: UUID(), duration: 50)]
    #expect(deriveUpNext(instances: [instance], recorded: [:], exercises: exercises, previous: previous)?.seconds == 50)
}

@Test func nilWhenNoDuration() {
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A", plannedEntries: [entry(plank, order: 0)])
    #expect(deriveUpNext(instances: [instance], recorded: [:], exercises: exercises, previous: [:]) == nil)
}

@Test func respectsEntryOrderNotArrayOrder() {
    let later = entry(bench, order: 1)
    let first = entry(plank, order: 0, duration: 20)
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A", plannedEntries: [later, first])
    #expect(deriveUpNext(instances: [instance], recorded: [:], exercises: exercises, previous: [:])?.plannedEntryId == first.id)
}

@MainActor
@Test func viewModelUpNextNilWhenNotScheduled() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let planked = entry(plank, order: 0, duration: 45)
    let instance = WorkoutInstanceDTO(id: UUID(), sourceWorkoutId: UUID(), name: "A", plannedEntries: [planked])
    let session = SessionDTO(
        id: UUID(), clientId: UUID(), startAt: .now, endAt: .now.addingTimeInterval(3600),
        status: .completed, notes: nil, instances: [instance], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
    let vm = SessionRunViewModel(
        sessionRepo: SwiftDataSessionRepository(modelContainer: container),
        exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
        clientRepo: SwiftDataClientRepository(modelContainer: container),
        session: session, clientName: "Sam"
    )
    vm.exercises = exercises
    #expect(vm.upNext == nil)
    vm.session.status = .scheduled
    #expect(vm.upNext?.plannedEntryId == planked.id)
}
