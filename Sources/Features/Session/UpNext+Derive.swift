import Foundation

/// First planned entry (instance order, then entry order) that still has sets to
/// log, if that entry is timed and has a positive target (or previous) duration.
/// The next thing to do decides it: a strength entry first means no up-next set.
func deriveUpNext(
    instances: [WorkoutInstanceDTO],
    recorded: [UUID: [SetRecordDTO]],
    exercises: [UUID: ExerciseDTO],
    previous: [UUID: SetRecordDTO]
) -> UpNext? {
    for instance in instances {
        for entry in instance.plannedEntries.sorted(by: { $0.order < $1.order }) {
            guard let exercise = exercises[entry.exerciseId] else { continue }
            let logged = recorded[instance.id, default: []].filter { $0.exerciseId == entry.exerciseId }.count
            guard logged < max(entry.targetSets ?? 1, 1) else { continue }
            guard exercise.metrics.contains(.duration) else { return nil }
            let seconds = entry.targetDuration ?? previous[entry.exerciseId]?.duration ?? 0
            return seconds > 0
                ? UpNext(plannedEntryId: entry.id, instanceId: instance.id, exerciseName: exercise.name, seconds: seconds)
                : nil
        }
    }
    return nil
}
