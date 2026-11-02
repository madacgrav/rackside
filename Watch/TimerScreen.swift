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
        VStack(spacing: 8) {
            Text(timer.isRest ? "Rest" : "Timed set")
                .font(.headline)
            ProgressView(timerInterval: timer.startedAt...timer.endAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(timerInterval: timer.startedAt...timer.endAt, countsDown: true)
                    .font(.title2.monospacedDigit())
            }
            .progressViewStyle(.circular)
        }
    }

    private var idle: some View {
        VStack(spacing: 4) {
            Image(systemName: "timer").font(.title2)
            Text("No timer running").font(.headline)
            Text("Start one from TrainMe on iPhone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
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

#Preview("Idle") {
    TimerScreen().environment(WatchTimerModel())
}
