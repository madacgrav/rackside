import Foundation

enum TimerKind: Codable, Sendable, Equatable {
    case rest
    case timedSet(plannedEntryId: UUID, instanceId: UUID)
}

/// One running countdown. Remaining time is always derived from `endAt`.
struct ActiveTimer: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var kind: TimerKind
    var startedAt: Date
    var endAt: Date

    /// Total length including any extensions; used to prefill a timed set.
    var seconds: Int { Int(endAt.timeIntervalSince(startedAt).rounded()) }

    var isRest: Bool { kind == .rest }
}
