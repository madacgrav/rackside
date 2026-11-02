import Foundation
import Observation

enum TimerSettings {
    static let defaultRestKey = "defaultRestSeconds"
    static let restChoices = [30, 45, 60, 90, 120, 150, 180]
}

struct TimerCompletion: Equatable, Sendable {
    let timerId: UUID
    let kind: TimerKind
    let seconds: Int
}

/// App-level owner of the single running timer. Lives above `LockGateView`
/// (which tears down its content on background) so timers survive the lock.
@MainActor
@Observable
final class TimerStore {
    static let storageKey = "activeTimer"

    private(set) var active: ActiveTimer?
    /// Bumps on every natural completion; drives `.sensoryFeedback`.
    private(set) var completionTick = 0
    /// Set on natural completion only (skip never sets it).
    private(set) var lastCompletion: TimerCompletion?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: any TimerNotifying
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let autoComplete: Bool
    @ObservationIgnored private var watcher: Task<Void, Never>?
    /// Serialises async side effects so cancel/schedule never interleave.
    @ObservationIgnored private var outbox: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        notifier: any TimerNotifying = LocalTimerNotifier(),
        autoComplete: Bool = true,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.notifier = notifier
        self.autoComplete = autoComplete
        self.now = now
        // A timer that finished while the app was dead is dropped silently; its
        // notification has already fired. A running one keeps its pending notification.
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(ActiveTimer.self, from: data),
           !TimerMath.isComplete(saved, now: now()) {
            active = saved
            armWatcher()
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    static var preview: TimerStore {
        TimerStore(defaults: UserDefaults(suiteName: "TimerPreview")!, notifier: NoopTimerNotifier(), autoComplete: false)
    }

    func startRest(seconds: Int) {
        start(TimerMath.make(kind: .rest, seconds: seconds, now: now()))
    }

    func startTimedSet(plannedEntryId: UUID, instanceId: UUID, seconds: Int) {
        guard seconds > 0 else { return }
        start(TimerMath.make(kind: .timedSet(plannedEntryId: plannedEntryId, instanceId: instanceId),
                             seconds: seconds, now: now()))
    }

    func extend(by seconds: Int = TimerMath.extendStep) {
        guard let active else { return }
        set(TimerMath.extended(active, by: seconds, now: now()))
    }

    func skip() { set(nil) }

    /// Completes the timer if its end has passed, otherwise re-arms the watcher
    /// (its sleep may have been suspended in the background). Called by the
    /// watcher and on `.active`.
    func refresh() {
        guard let active else { return }
        if TimerMath.isComplete(active, now: now()) {
            complete(active)
        } else {
            armWatcher()
        }
    }

    /// Test hook: waits for queued side effects.
    func flush() async { await outbox?.value }

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
        lastCompletion = TimerCompletion(timerId: timer.id, kind: timer.kind, seconds: timer.seconds)
        completionTick += 1
    }

    /// Single mutation point for the running timer.
    private func set(_ timer: ActiveTimer?) {
        active = timer
        persist()
        armWatcher()
        enqueue { [notifier] in
            await notifier.cancelAll()
            if let timer { await notifier.schedule(timer) }
        }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = outbox
        outbox = Task {
            await previous?.value
            await work()
        }
    }

    private func persist() {
        if let active, let data = try? JSONEncoder().encode(active) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
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
