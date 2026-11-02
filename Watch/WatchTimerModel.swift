import Foundation
import Observation
import WatchKit

@MainActor
@Observable
final class WatchTimerModel {
    private(set) var snapshot: TimerSnapshot?
    @ObservationIgnored private let link = PhoneLink()
    @ObservationIgnored private let notifier = WatchNotifier()
    @ObservationIgnored private var hapticTask: Task<Void, Never>?

    init(snapshot: TimerSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func activate() {
        link.onSnapshot = { [weak self] snap in Task { @MainActor in self?.apply(snap) } }
        link.activate()
        Task { [notifier] in await notifier.requestAuthorization() }
    }

    /// Newest wins, so a late application context can't roll back a newer message.
    func apply(_ snap: TimerSnapshot) {
        if let current = snapshot, current.sentAt > snap.sentAt { return }
        snapshot = snap
        timerChanged()
    }

    func startRest(seconds: Int) { adopt(TimerMath.make(kind: .rest, seconds: seconds, now: .now)) }

    func startUpNext() {
        guard let next = snapshot?.upNext else { return }
        adopt(TimerMath.make(kind: .timedSet(plannedEntryId: next.plannedEntryId, instanceId: next.instanceId),
                             seconds: next.seconds, now: .now))
    }

    func extend() {
        guard let timer = snapshot?.timer else { return }
        adopt(TimerMath.extended(timer, by: TimerMath.extendStep, now: .now))
    }

    func skip() {
        guard let timer = snapshot?.timer else { return }
        updateLocal(timer: nil)
        link.send(.skip(timerId: timer.id))
    }

    // MARK: - Private

    /// Shows the timer right away; the phone's next snapshot confirms or corrects it.
    private func adopt(_ timer: ActiveTimer) {
        guard TimerMath.canReplace(snapshot?.timer, with: timer, now: .now) else { return }
        updateLocal(timer: timer)
        link.send(.adopt(timer))
    }

    private func updateLocal(timer: ActiveTimer?) {
        var snap = snapshot ?? TimerSnapshot(timer: nil, upNext: nil, defaultRest: TimerMath.defaultRest,
                                             quickPicks: TimerMath.quickPicks, sentAt: .now)
        snap.timer = timer
        snap.sentAt = .now
        snapshot = snap
        timerChanged()
    }

    /// Re-plans both cues for the current timer: the wrist-down notification and
    /// the haptic while the app is open.
    private func timerChanged() {
        let timer = snapshot?.timer
        Task { [notifier] in await notifier.reschedule(timer) }
        hapticTask?.cancel()
        guard let timer else { return }
        hapticTask = Task {
            try? await Task.sleep(for: .seconds(max(0, timer.endAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.stop)
        }
    }
}
