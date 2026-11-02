#if DEBUG
import Foundation

/// Debug-only sample timer state for screenshots: `-demoData [-demoWatch running|idle]`.
enum WatchDemo {
    static func snapshot(arguments: [String] = ProcessInfo.processInfo.arguments, now: Date = .now) -> TimerSnapshot? {
        guard arguments.contains("-demoData") else { return nil }
        var state = "running"
        if let i = arguments.firstIndex(of: "-demoWatch"), arguments.indices.contains(i + 1) {
            state = arguments[i + 1]
        }
        var snapshot = TimerSnapshot(timer: nil, upNext: nil, defaultRest: TimerMath.defaultRest,
                                     quickPicks: TimerMath.quickPicks, sentAt: now)
        if state == "idle" {
            snapshot.upNext = UpNext(plannedEntryId: UUID(), instanceId: UUID(), exerciseName: "Plank", seconds: 45)
        } else {
            // A 2-minute rest started 20 s ago, so there is time left when the screenshot is taken.
            snapshot.timer = ActiveTimer(id: UUID(), kind: .rest, startedAt: now.addingTimeInterval(-20),
                                         endAt: now.addingTimeInterval(100))
        }
        return snapshot
    }
}
#endif
