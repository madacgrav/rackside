import Foundation
import WatchConnectivity

protocol WatchSyncing: Sendable {
    func activate() async
    func send(_ snapshot: TimerSnapshot) async
}

struct NoopWatchSync: WatchSyncing {
    func activate() async {}
    func send(_ snapshot: TimerSnapshot) async {}
}

/// Pushes timer snapshots to the companion watch app. `WCSession` is documented
/// thread-safe; this class holds no mutable state of its own.
final class WCSessionWatchSync: NSObject, WatchSyncing, WCSessionDelegate, @unchecked Sendable {
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    func activate() async {
        session?.delegate = self
        session?.activate()
    }

    func send(_ snapshot: TimerSnapshot) async {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let payload = try? SyncCodec.encode(snapshot, kind: "snapshot") else { return }
        // Context reaches the watch whenever it next runs; a live message is
        // faster while the watch app is open.
        do { try session.updateApplicationContext(payload) } catch {
            Log.sync.error("context update failed: \(error.localizedDescription)")
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                Log.sync.debug("sendMessage failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error { Log.sync.error("activation failed: \(error.localizedDescription)") }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches; reactivate for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
