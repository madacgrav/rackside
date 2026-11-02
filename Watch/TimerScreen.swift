import SwiftUI

struct TimerScreen: View {
    @Environment(WatchTimerModel.self) private var model

    var body: some View {
        if let timer = model.snapshot?.timer {
            TimelineView(.explicit([timer.endAt])) { context in
                if context.date < timer.endAt {
                    running(timer)
                } else {
                    idle
                }
            }
        } else {
            idle
        }
    }

    private func running(_ timer: ActiveTimer) -> some View {
        VStack(spacing: 6) {
            Text(timer.isRest ? "Rest" : "Timed set")
                .font(.headline)
            ProgressView(timerInterval: timer.startedAt...timer.endAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(timerInterval: timer.startedAt...timer.endAt, countsDown: true)
                    .font(.title3.monospacedDigit())
            }
            .progressViewStyle(.circular)
            HStack {
                Button("+\(TimerMath.extendStep) s") { model.extend() }
                Button("Skip", role: .destructive) { model.skip() }
            }
        }
    }

    private var idle: some View {
        QuickStartView()
    }
}

#Preview("Running rest") {
    let now = Date()
    let snapshot = TimerSnapshot(
        timer: ActiveTimer(id: UUID(), kind: .rest, startedAt: now, endAt: now.addingTimeInterval(90)),
        upNext: nil, defaultRest: 90, quickPicks: TimerMath.quickPicks, sentAt: now
    )
    return TimerScreen().environment(WatchTimerModel(snapshot: snapshot))
}

#Preview("Idle with up next") {
    let snapshot = TimerSnapshot(
        timer: nil,
        upNext: UpNext(plannedEntryId: UUID(), instanceId: UUID(), exerciseName: "Plank", seconds: 45),
        defaultRest: 90, quickPicks: TimerMath.quickPicks, sentAt: Date()
    )
    return TimerScreen().environment(WatchTimerModel(snapshot: snapshot))
}
