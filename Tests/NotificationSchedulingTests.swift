import Foundation
import Testing
@testable import Rackside

private func session(hoursFromNow: Double, name: String = "Sam") -> (id: UUID, startAt: Date, clientName: String) {
    (UUID(), Date.now.addingTimeInterval(hoursFromNow * 3600), name)
}

@Test func onlySessionIdentifiersAreRemoved() {
    let ids = ["sess-A-24h", "other-app", "sess-B-1h", "reminder-x"]
    #expect(sessionAlertIdentifiers(from: ids) == ["sess-A-24h", "sess-B-1h"])
}

@Test func capNeverExceeded() {
    // 100 upcoming sessions → would want 200 alerts; must stay ≤64.
    let sessions = (1...100).map { session(hoursFromNow: Double($0 * 48)) }
    let alerts = selectAlerts(sessions: sessions, now: .now, cap: 64)
    #expect(alerts.count <= 64)
    #expect(alerts.count == 64) // 32 sessions × 2 alerts
}

@Test func nearestSessionsWin() {
    let near = session(hoursFromNow: 48, name: "Near")
    let far = (1...40).map { session(hoursFromNow: Double(100 + $0 * 48), name: "Far") }
    let alerts = selectAlerts(sessions: far + [near], now: .now, cap: 64)

    #expect(alerts.contains { $0.identifier == "sess-\(near.id.uuidString)-24h" })
    #expect(alerts.first?.body.contains("Near") == true)
}

@Test func pastSessionsAndPastAlertsSkipped() {
    let past = session(hoursFromNow: -2)
    let soon = session(hoursFromNow: 12) // 24h-before is already in the past
    let alerts = selectAlerts(sessions: [past, soon], now: .now)

    #expect(!alerts.contains { $0.identifier.hasPrefix("sess-\(past.id.uuidString)") })
    #expect(!alerts.contains { $0.identifier == "sess-\(soon.id.uuidString)-24h" })
    #expect(alerts.contains { $0.identifier == "sess-\(soon.id.uuidString)-1h" })
}

@Test func alertsCarryClientAndTime() {
    let s = session(hoursFromNow: 72, name: "Alex Smith")
    let alerts = selectAlerts(sessions: [s], now: .now)
    #expect(alerts.count == 2)
    #expect(alerts.allSatisfy { $0.body.contains("Alex Smith") })
}

@Test func reminderBodyUsesFirstNameAndTime() {
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
    let body = MessagingService.reminderBody(clientName: "Sam Jones", sessionDate: tomorrow)
    #expect(body.contains("Hi Sam"))
    #expect(body.contains("tomorrow"))
}
