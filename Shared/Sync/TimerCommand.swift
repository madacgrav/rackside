import Foundation

/// Watch → phone. The watch builds timers itself with `TimerMath`, so the same
/// command works whether delivered live (`sendMessage`) or queued (`transferUserInfo`).
enum TimerCommand: Codable, Sendable, Equatable {
    /// Start, extend, or start the up-next set: the phone adopts this exact timer.
    case adopt(ActiveTimer)
    case skip(timerId: UUID)
}
