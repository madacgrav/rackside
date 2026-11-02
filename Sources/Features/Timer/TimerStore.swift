import Foundation
import Observation

enum TimerSettings {
    static let defaultRestKey = "defaultRestSeconds"
    static let restChoices = [30, 45, 60, 90, 120, 150, 180]
}

/// App-level owner of the single running timer. Lives above `LockGateView`
/// (which tears down its content on background) so timers survive the lock.
@MainActor
@Observable
final class TimerStore {
    private(set) var active: ActiveTimer?
    /// Bumps on every natural completion; drives `.sensoryFeedback`.
    private(set) var completionTick = 0

    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let autoComplete: Bool
    @ObservationIgnored private var watcher: Task<Void, Never>?

    init(autoComplete: Bool = true, now: @escaping @Sendable () -> Date = { Date() }) {
        self.autoComplete = autoComplete
        self.now = now
    }

    static var preview: TimerStore { TimerStore(autoComplete: false) }

    func startRest(seconds: Int) {
        start(TimerMath.make(kind: .rest, seconds: seconds, now: now()))
    }

    func extend(by seconds: Int = TimerMath.extendStep) {
        guard let active else { return }
        set(TimerMath.extended(active, by: seconds, now: now()))
    }

    func skip() { set(nil) }

    /// Completes the timer if its end has passed. Called by the watcher and on `.active`.
    func refresh() {
        guard let active, TimerMath.isComplete(active, now: now()) else { return }
        complete(active)
    }

    // MARK: - Private

    /// Returns false when the one-timer rule rejects `timer`.
    @discardableResult
    private func start(_ timer: ActiveTimer) -> Bool {
        guard TimerMath.canReplace(active, with: timer, now: now()) else { return false }
        set(timer)
        return true
    }

    private func complete(_ timer: ActiveTimer) {
        set(nil)
        completionTick += 1
    }

    /// Single mutation point for the running timer.
    private func set(_ timer: ActiveTimer?) {
        active = timer
        armWatcher()
    }

    private func armWatcher() {
        watcher?.cancel()
        watcher = nil
        guard autoComplete, let end = active?.endAt else { return }
        let delay = max(0, end.timeIntervalSince(now()))
        watcher = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
