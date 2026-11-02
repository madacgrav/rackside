import EventKit
import Foundation
import Testing
@testable import Rackside

@Test func weeklyTueThuMapsToEKRule() {
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5], endDate: nil, occurrenceCount: nil)
    let ek = makeEKRecurrenceRule(rule)

    #expect(ek.frequency == .weekly)
    #expect(ek.interval == 1)
    #expect(ek.daysOfTheWeek?.map(\.dayOfTheWeek) == [.tuesday, .thursday])
    #expect(ek.recurrenceEnd == nil)
}

@Test func occurrenceCountEndMaps() {
    let rule = AppRecurrence(frequency: .weekly, interval: 2, weekdays: [2], endDate: nil, occurrenceCount: 8)
    let ek = makeEKRecurrenceRule(rule)

    #expect(ek.interval == 2)
    #expect(ek.recurrenceEnd?.occurrenceCount == 8)
}

@Test func endDateMaps() {
    let end = Date.now.addingTimeInterval(86400 * 30)
    let rule = AppRecurrence(frequency: .daily, interval: 1, weekdays: [], endDate: end, occurrenceCount: nil)
    let ek = makeEKRecurrenceRule(rule)

    #expect(ek.frequency == .daily)
    #expect(ek.daysOfTheWeek == nil)
    #expect(ek.recurrenceEnd?.endDate != nil)
}

@Test func invalidIntervalClampedToOne() {
    let rule = AppRecurrence(frequency: .weekly, interval: 0, weekdays: [2], endDate: nil, occurrenceCount: nil)
    #expect(makeEKRecurrenceRule(rule).interval == 1)
}
