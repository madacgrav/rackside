import Foundation
import Observation

@MainActor
@Observable
final class WatchTimerModel {
    private(set) var snapshot: TimerSnapshot?
    @ObservationIgnored private let link = PhoneLink()

    init(snapshot: TimerSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func activate() {
        link.onSnapshot = { [weak self] snap in Task { @MainActor in self?.apply(snap) } }
        link.activate()
    }

    /// Newest wins, so a late application context can't roll back a newer message.
    func apply(_ snap: TimerSnapshot) {
        if let current = snapshot, current.sentAt > snap.sentAt { return }
        snapshot = snap
    }
}
