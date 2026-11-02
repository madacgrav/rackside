import Foundation
import UserNotifications

let timerNotificationPrefix = "timer-"

func timerNotificationIdentifier(_ id: UUID) -> String { timerNotificationPrefix + id.uuidString }

/// Only our own timer requests; session reminders (`sess-`) are never touched.
func timerNotificationIdentifiers(from pending: [String]) -> [String] {
    pending.filter { $0.hasPrefix(timerNotificationPrefix) }
}

func timerNotificationText(for kind: TimerKind) -> (title: String, body: String) {
    switch kind {
    case .rest: ("Rest over", "Time for the next set.")
    case .timedSet: ("Timed set done", "Log the set in Rackside.")
    }
}

protocol TimerNotifying: Sendable {
    func schedule(_ timer: ActiveTimer) async
    func cancelAll() async
}

struct NoopTimerNotifier: TimerNotifying {
    func schedule(_ timer: ActiveTimer) async {}
    func cancelAll() async {}
}

/// Local notification at the timer's end, so a locked phone (and a worn watch,
/// via mirroring) still gets the cue.
struct LocalTimerNotifier: TimerNotifying {
    func schedule(_ timer: ActiveTimer) async {
        let center = UNUserNotificationCenter.current()
        guard canScheduleAlerts(await center.notificationSettings().authorizationStatus) else { return }
        let interval = timer.endAt.timeIntervalSinceNow
        guard interval >= 1 else { return }
        let text = timerNotificationText(for: timer.kind)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: timerNotificationIdentifier(timer.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        do { try await center.add(request) } catch {
            Log.notifications.error("timer alert failed: \(error.localizedDescription)")
        }
    }

    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: timerNotificationIdentifiers(from: pending))
    }
}
