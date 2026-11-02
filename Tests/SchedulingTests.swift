import Foundation
import Testing
@testable import Rackside

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 7) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Test func weeklyTueThuExpansion() {
    // 2026-07-14 is a Tuesday.
    let start = date(2026, 7, 14)
    let horizon = date(2026, 7, 28) // two weeks later (Tuesday)
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5], endDate: nil, occurrenceCount: nil)

    let dates = expandRecurrence(rule, from: start, to: horizon)

    let calendar = Calendar.current
    #expect(dates.count == 5) // Tue 14, Thu 16, Tue 21, Thu 23, Tue 28
    #expect(dates.allSatisfy { [3, 5].contains(calendar.component(.weekday, from: $0)) })
    #expect(dates.allSatisfy { calendar.component(.hour, from: $0) == 7 })
    #expect(dates == dates.sorted())
    #expect(dates.first == start)
}

@Test func weeklyExpansionRespectsOccurrenceCount() {
    let start = date(2026, 7, 14)
    let horizon = date(2026, 12, 31)
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5], endDate: nil, occurrenceCount: 6)

    #expect(expandRecurrence(rule, from: start, to: horizon).count == 6)
}

@Test func weeklyExpansionRespectsEndDate() {
    let start = date(2026, 7, 14)
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3], endDate: date(2026, 7, 21, 23), occurrenceCount: nil)

    let dates = expandRecurrence(rule, from: start, to: date(2026, 12, 31))
    #expect(dates.count == 2) // Tue 14, Tue 21
}

@Test func dailyExpansionWithInterval() {
    let start = date(2026, 7, 14)
    let rule = AppRecurrence(frequency: .daily, interval: 2, weekdays: [], endDate: nil, occurrenceCount: nil)

    let dates = expandRecurrence(rule, from: start, to: date(2026, 7, 20))
    #expect(dates.count == 4) // 14, 16, 18, 20
}

@Test func weeklyWithNoWeekdaysUsesStartWeekday() {
    let start = date(2026, 7, 14) // Tuesday
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [], endDate: nil, occurrenceCount: nil)

    let dates = expandRecurrence(rule, from: start, to: date(2026, 7, 28))
    #expect(dates.count == 3)
    #expect(dates.allSatisfy { Calendar.current.component(.weekday, from: $0) == 3 })
}

@Test func startWithSecondsStillYieldsFirstOccurrence() {
    // 07:00:30 anchor: the first Tuesday must not be dropped just because the
    // generated occurrences are on the minute.
    let start = date(2026, 7, 14).addingTimeInterval(30)
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3], endDate: nil, occurrenceCount: nil)

    let dates = expandRecurrence(rule, from: start, to: date(2026, 7, 28))
    #expect(dates.count == 3)
    #expect(dates.first == date(2026, 7, 14))
}

// MARK: - Series segments

@Test func retimeKeepsDayChangesTime() {
    let moved = retime(date(2026, 7, 14, 7), hour: 8, minute: 30)
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moved)
    #expect(parts == DateComponents(year: 2026, month: 7, day: 14, hour: 8, minute: 30, second: 0))
}

@Test func segmentRuleUsesOldWeekdaysOrDerivesThem() {
    // 2026-07-14 is a Tuesday (3), 2026-07-16 a Thursday (5).
    let dates = [date(2026, 7, 14), date(2026, 7, 16), date(2026, 7, 21)]
    let old = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [5, 3], endDate: nil, occurrenceCount: 8)
    let fromOld = segmentRule(from: old, dates: dates)
    #expect(fromOld.weekdays == [5, 3])
    #expect(fromOld.endDate == dates.last)
    #expect(fromOld.occurrenceCount == nil)
    #expect(segmentRule(from: nil, dates: dates).weekdays == [3, 5])
}

@Test func gapDatesFindsMissingWeeks() {
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5], endDate: date(2026, 7, 23), occurrenceCount: nil)
    let keep = [date(2026, 7, 14), date(2026, 7, 16), date(2026, 7, 21), date(2026, 7, 23)]
    #expect(gapDates(rule: rule, keep: keep).isEmpty)
    var missing = keep
    missing.remove(at: 1)
    #expect(gapDates(rule: rule, keep: missing) == [date(2026, 7, 16)])
}

@Test func gapDatesAcrossDSTBoundary() {
    // US spring-forward is 2027-03-14 (a Sunday); weekly Tuesdays at 07:00 around it.
    let keep = [date(2027, 3, 9), date(2027, 3, 16), date(2027, 3, 23)]
    let rule = AppRecurrence(frequency: .weekly, interval: 1, weekdays: [3], endDate: keep.last, occurrenceCount: nil)
    #expect(gapDates(rule: rule, keep: keep).isEmpty)
}
