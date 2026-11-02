import Foundation

enum TimerMath {
    static let quickPicks = [60, 90, 120]
    static let extendStep = 15
    static let defaultRest = 90

    static func make(kind: TimerKind, seconds: Int, now: Date) -> ActiveTimer {
        ActiveTimer(id: UUID(), kind: kind, startedAt: now, endAt: now.addingTimeInterval(TimeInterval(seconds)))
    }

    static func remaining(_ timer: ActiveTimer, now: Date) -> TimeInterval { max(0, timer.endAt.timeIntervalSince(now)) }

    static func isComplete(_ timer: ActiveTimer, now: Date) -> Bool { now >= timer.endAt }

    /// Adds time to the end; a timer already at zero restarts from now.
    static func extended(_ timer: ActiveTimer, by seconds: Int, now: Date) -> ActiveTimer {
        var copy = timer
        copy.endAt = max(timer.endAt, now).addingTimeInterval(TimeInterval(seconds))
        return copy
    }

    /// One timer at a time: a rest may not replace a running timed set.
    static func canReplace(_ current: ActiveTimer?, with next: ActiveTimer, now: Date) -> Bool {
        guard let current, current.id != next.id, !isComplete(current, now: now) else { return true }
        return !(next.isRest && !current.isRest)
    }
}
