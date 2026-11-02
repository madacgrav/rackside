import SwiftUI

/// Idle state: one tap starts the phone's up-next timed set or a rest.
struct QuickStartView: View {
    @Environment(WatchTimerModel.self) private var model

    private var quickPicks: [Int] { model.snapshot?.quickPicks ?? TimerMath.quickPicks }
    private var defaultRest: Int { model.snapshot?.defaultRest ?? TimerMath.defaultRest }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let next = model.snapshot?.upNext {
                    Button("\(next.exerciseName) · \(next.seconds) s", systemImage: "stopwatch") {
                        model.startUpNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.upNext)
                }
                ForEach(quickPicks, id: \.self) { seconds in
                    if seconds == defaultRest {
                        restButton(seconds).buttonStyle(.borderedProminent)
                    } else {
                        restButton(seconds).buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func restButton(_ seconds: Int) -> some View {
        Button("Rest \(seconds) s", systemImage: "timer") { model.startRest(seconds: seconds) }
    }
}
