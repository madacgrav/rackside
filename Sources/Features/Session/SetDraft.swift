import Foundation

/// Editable values for one not-yet-logged set.
struct SetDraft: Equatable, Sendable {
    var weight: Double?
    var reps: Int?
    var duration: Int?
    var distance: Double?

    init(target entry: PlannedEntryDTO, metrics: MetricSet) {
        weight = metrics.contains(.weight) ? (entry.targetWeight ?? 0) : nil
        reps = metrics.contains(.reps) ? (entry.targetReps ?? 0) : nil
        duration = metrics.contains(.duration) ? (entry.targetDuration ?? 0) : nil
        distance = metrics.contains(.distance) ? 0 : nil
    }

    init(from record: SetRecordDTO, metrics: MetricSet) {
        weight = metrics.contains(.weight) ? record.weight : nil
        reps = metrics.contains(.reps) ? record.reps : nil
        duration = metrics.contains(.duration) ? record.duration : nil
        distance = metrics.contains(.distance) ? record.distance : nil
    }

    /// Countdown result → draft; a no-op for exercises that don't track duration.
    func prefilled(duration: Int, metrics: MetricSet) -> SetDraft {
        guard metrics.contains(.duration) else { return self }
        var copy = self
        copy.duration = duration
        return copy
    }
}
