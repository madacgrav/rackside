import Foundation
import WatchConnectivity

struct CueState: Sendable, Equatable {
    var watchAppInstalled: Bool
    var paired: Bool
    var reachable: Bool

    static let noWatch = CueState(watchAppInstalled: false, paired: false, reachable: false)
}

/// The watch owns the zero cue only when it can certainly hear about the timer
/// now; otherwise the phone notifies (and mirrors to a worn watch when locked).
func phoneOwnsCue(_ cue: CueState) -> Bool {
    !(cue.watchAppInstalled && cue.paired && cue.reachable)
}

protocol WatchSyncing: Sendable {
    func activate() async
    func send(_ snapshot: TimerSnapshot) async
    func cueState() async -> CueState
    var commands: AsyncStream<TimerCommand> { get }
}

struct NoopWatchSync: WatchSyncing {
    func activate() async {}
    func send(_ snapshot: TimerSnapshot) async {}
    func cueState() async -> CueState { .noWatch }
    var commands: AsyncStream<TimerCommand> { AsyncStream { $0.finish() } }
}

/// Pushes timer snapshots to the companion watch app. `WCSession` is documented
/// thread-safe; this class holds no mutable state of its own.
final class WCSessionWatchSync: NSObject, WatchSyncing, WCSessionDelegate, @unchecked Sendable {
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    let commands: AsyncStream<TimerCommand>
    private let continuation: AsyncStream<TimerCommand>.Continuation

    override init() {
        (commands, continuation) = AsyncStream.makeStream()
        super.init()
    }

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

    func cueState() async -> CueState {
        guard let session, session.activationState == .activated else { return .noWatch }
        return CueState(watchAppInstalled: session.isWatchAppInstalled, paired: session.isPaired,
                        reachable: session.isReachable)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error { Log.sync.error("activation failed: \(error.localizedDescription)") }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    /// Queued commands sent while the phone app was not reachable.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    private nonisolated func receive(_ payload: [String: Any]) {
        guard let command = SyncCodec.decode(TimerCommand.self, from: payload, kind: "command") else { return }
        continuation.yield(command)
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches; reactivate for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
