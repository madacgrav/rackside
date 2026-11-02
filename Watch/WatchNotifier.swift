import Foundation
import UserNotifications

/// Local notification at the timer's end, so a lowered wrist still gets the cue
/// while the watch app is suspended. The open app gets a haptic instead
/// (a foreground notification isn't presented without a delegate).
struct WatchNotifier: Sendable {
    private static let prefix = "timer-"

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func reschedule(_ timer: ActiveTimer?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let timer else { return }
        let interval = timer.endAt.timeIntervalSinceNow
        guard interval >= 1 else { return }
        // Same wording as the phone's alert; Sources/ isn't compiled into the watch.
        let content = UNMutableNotificationContent()
        content.title = timer.isRest ? "Rest over" : "Timed set done"
        content.body = timer.isRest ? "Time for the next set." : "Log the set in TrainMe."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.prefix + timer.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await center.add(request)
    }
}
