import SwiftUI

/// Compact rest / timed-set countdown for the bottom of the run screen.
struct TimerBar: View {
    @Environment(TimerStore.self) private var timers

    var body: some View {
        Group {
            if let timer = timers.active {
                running(timer)
            } else {
                idle
            }
        }
        .padding(Theme.Spacing.sm)
        .background(.bar)
    }

    private var idle: some View {
        HStack {
            restMenu(label: "Rest")
            Spacer()
        }
    }

    private func running(_ timer: ActiveTimer) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Label(timer.isRest ? "Rest" : "Timed set", systemImage: timer.isRest ? "timer" : "stopwatch")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                    Text(timerInterval: timer.startedAt...timer.endAt, countsDown: true)
                        .font(Theme.Fonts.numeric)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if timer.isRest { restMenu(label: "Change").labelStyle(.iconOnly) }
                Button("+\(TimerMath.extendStep) s") { timers.extend() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Add \(TimerMath.extendStep) seconds")
                Button("Skip") { timers.skip() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
            GradientProgressBar(countdown: timer.startedAt...timer.endAt)
                .accessibilityHidden(true) // the combined label above already speaks the countdown
        }
    }

    private func restMenu(label: String) -> some View {
        Menu(label, systemImage: "timer") {
            ForEach(TimerMath.quickPicks, id: \.self) { seconds in
                Button("\(seconds) s") { timers.startRest(seconds: seconds) }
            }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .accessibilityLabel("Start a rest timer")
    }
}

#Preview("Timer bar") {
    let store = TimerStore.preview
    store.startRest(seconds: 90)
    return VStack {
        Spacer()
        TimerBar()
    }
    .environment(store)
}
