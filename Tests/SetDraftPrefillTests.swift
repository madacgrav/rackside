import Foundation
import Testing
@testable import TrainMe

private func draft(_ metrics: MetricSet, weight: Double? = nil, reps: Int? = nil, duration: Int? = nil) -> SetDraft {
    let entry = PlannedEntryDTO(id: UUID(), exerciseId: UUID(), order: 0, targetSets: 3,
                                targetReps: reps, targetWeight: weight, targetDuration: duration)
    return SetDraft(target: entry, metrics: metrics)
}

@Test func prefillSetsDuration() {
    #expect(draft([.duration], duration: 0).prefilled(duration: 60, metrics: [.duration]).duration == 60)
}

@Test func prefillIgnoredWithoutDurationMetric() {
    let strength = draft([.weight, .reps], weight: 100, reps: 8)
    #expect(strength.prefilled(duration: 60, metrics: [.weight, .reps]) == strength)
}

@Test func prefillKeepsOtherMetrics() {
    var cardio = draft([.duration, .distance], duration: 30)
    cardio.distance = 1.5
    let filled = cardio.prefilled(duration: 45, metrics: [.duration, .distance])
    #expect(filled.distance == 1.5)
    #expect(filled.duration == 45)
}
