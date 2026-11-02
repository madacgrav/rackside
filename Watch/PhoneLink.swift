import Foundation
import WatchConnectivity

/// Watch side of WatchConnectivity: decodes timer snapshots from the phone and
/// sends timer commands back.
/// `WCSession` is documented thread-safe; `onSnapshot` is set once before `activate()`.
final class PhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    var onSnapshot: (@Sendable (TimerSnapshot) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Live when the phone app is reachable, otherwise queued until it is.
    func send(_ command: TimerCommand) {
        guard let payload = try? SyncCodec.encode(command, kind: "command") else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // The latest context may have arrived while the app was not running.
        deliver(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    private nonisolated func deliver(_ payload: [String: Any]) {
        guard let snapshot = SyncCodec.decode(TimerSnapshot.self, from: payload, kind: "snapshot") else { return }
        onSnapshot?(snapshot)
    }
}
