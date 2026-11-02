import Foundation
import Testing
@testable import Rackside

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

@Test func neverExportedIsDueOnlyOnceThereIsData() {
    #expect(exportReminderDue(lastExportAt: nil, now: now, completedSinceExport: 0) == false)
    #expect(exportReminderDue(lastExportAt: nil, now: now, completedSinceExport: 1) == true)
}

@Test func underBothThresholdsNotDue() {
    #expect(exportReminderDue(lastExportAt: daysAgo(13), now: now, completedSinceExport: 4) == false)
}

@Test func dayThresholdTriggers() {
    #expect(exportReminderDue(lastExportAt: daysAgo(14), now: now, completedSinceExport: 0) == true)
}

@Test func sessionThresholdTriggers() {
    #expect(exportReminderDue(lastExportAt: daysAgo(1), now: now, completedSinceExport: 5) == true)
}
