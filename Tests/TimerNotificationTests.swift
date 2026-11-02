import Foundation
import Testing
@testable import Rackside

@Test func identifiersUsePrefix() {
    let id = UUID()
    #expect(timerNotificationIdentifier(id) == "timer-\(id.uuidString)")
}

@Test func onlyTimerIdentifiersSelected() {
    let timer = timerNotificationIdentifier(UUID())
    let session = "sess-\(UUID().uuidString)-1h"
    #expect(timerNotificationIdentifiers(from: [session, timer, "other"]) == [timer])
}

@Test func textPerKind() {
    #expect(timerNotificationText(for: .rest).title == "Rest over")
    let timed = TimerKind.timedSet(plannedEntryId: UUID(), instanceId: UUID())
    #expect(timerNotificationText(for: timed).title == "Timed set done")
}
