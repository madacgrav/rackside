import Foundation
import Testing
@testable import TrainMe

/// Gregorian in New York, so the 2026-11-01 DST change falls inside the test week.
private func calendar(firstWeekday: Int) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.firstWeekday = firstWeekday
    return cal
}

private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func session(at start: Date) -> SessionDTO {
    SessionDTO(
        id: UUID(), clientId: UUID(), startAt: start,
        endAt: start.addingTimeInterval(3600), status: .scheduled,
        notes: nil, instances: [], seriesId: nil, recurrence: nil,
        eventIdentifier: nil, createdAt: .now, updatedAt: .now
    )
}

/// Two on Mon 11-02 (out of order), one on Wed 11-04, one in the next week.
private func weekSeed(_ cal: Calendar) -> [SessionDTO] {
    [
        session(at: date(cal, 2026, 11, 2, 17)),
        session(at: date(cal, 2026, 11, 2, 7)),
        session(at: date(cal, 2026, 11, 4, 9)),
        session(at: date(cal, 2026, 11, 8, 0)),
    ]
}

@MainActor
private func makeViewModel(calendar: Calendar, defaults: UserDefaults? = nil) throws
    -> (ScheduleViewModel, SwiftDataSessionRepository) {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let sessions = SwiftDataSessionRepository(modelContainer: container)
    let clients = SwiftDataClientRepository(modelContainer: container)
    let vm = ScheduleViewModel(
        sessionRepo: sessions,
        clientRepo: clients,
        workoutRepo: SwiftDataWorkoutRepository(modelContainer: container),
        exerciseRepo: SwiftDataExerciseRepository(modelContainer: container),
        reminders: ReminderCoordinator(sessionRepo: sessions, clientRepo: clients, notifications: FakeNotifications()),
        defaults: defaults ?? UserDefaults(suiteName: "ScheduleViewModelTests-\(UUID().uuidString)")!,
        calendar: calendar
    )
    return (vm, sessions)
}

@Test func weekIntervalSundayFirst() {
    let cal = calendar(firstWeekday: 1)
    let interval = ScheduleWeek.weekInterval(containing: date(cal, 2026, 11, 4, 12), calendar: cal)
    #expect(interval.start == date(cal, 2026, 11, 1))
    #expect(interval.end == date(cal, 2026, 11, 8))
}

@Test func weekIntervalMondayFirst() {
    let cal = calendar(firstWeekday: 2)
    let interval = ScheduleWeek.weekInterval(containing: date(cal, 2026, 11, 4, 12), calendar: cal)
    #expect(interval.start == date(cal, 2026, 11, 2))
    #expect(interval.end == date(cal, 2026, 11, 9))
}

@Test func daysAcrossDSTGivesSevenMidnights() {
    let cal = calendar(firstWeekday: 1)
    let interval = ScheduleWeek.weekInterval(containing: date(cal, 2026, 11, 4, 12), calendar: cal)
    let days = ScheduleWeek.days(in: interval, calendar: cal)
    #expect(days.count == 7)
    #expect(days.allSatisfy { cal.component(.hour, from: $0) == 0 })
    #expect(days[1] == date(cal, 2026, 11, 2))
    #expect(interval.duration == 7 * 86_400 + 3600)
}

@Test func groupBucketsByLocalDayAndKeepsEmptyDays() {
    let cal = calendar(firstWeekday: 1)
    let seed = weekSeed(cal)
    let interval = ScheduleWeek.weekInterval(containing: date(cal, 2026, 11, 4, 12), calendar: cal)
    let days = ScheduleWeek.group(seed, into: ScheduleWeek.days(in: interval, calendar: cal), calendar: cal)
    #expect(days.count == 7)
    #expect(days[1].sessions.map(\.id) == [seed[1].id, seed[0].id])
    #expect(days[3].sessions.count == 1)
    #expect([0, 2, 4, 5, 6].allSatisfy { days[$0].sessions.isEmpty })
    #expect(days.flatMap(\.sessions).count == 3)
}

@MainActor
@Test func weekModeLoadsWholeWeek() async throws {
    let cal = calendar(firstWeekday: 1)
    let (vm, sessions) = try makeViewModel(calendar: cal)
    for dto in weekSeed(cal) { try await sessions.schedule(dto, attaching: []) }
    vm.selectedDate = date(cal, 2026, 11, 4, 12)
    vm.mode = .week
    await vm.load()
    #expect(vm.week.count == 7)
    #expect(vm.week.flatMap(\.sessions).count == 3)
}

@MainActor
@Test func dayModeStillLoadsOneDay() async throws {
    let cal = calendar(firstWeekday: 1)
    let (vm, sessions) = try makeViewModel(calendar: cal)
    for dto in weekSeed(cal) { try await sessions.schedule(dto, attaching: []) }
    vm.selectedDate = date(cal, 2026, 11, 2, 12)
    vm.mode = .day
    await vm.load()
    #expect(vm.sessionsForDay.count == 2)
}

@MainActor
@Test func nextWeekCrossesYear() throws {
    let cal = calendar(firstWeekday: 1)
    let (vm, _) = try makeViewModel(calendar: cal)
    vm.selectedDate = date(cal, 2026, 12, 30, 12)
    vm.showNextWeek()
    #expect(vm.selectedDate == date(cal, 2027, 1, 6, 12))
    #expect(vm.weekInterval.start == date(cal, 2027, 1, 3))
}

@MainActor
@Test func previousWeekCrossesMonth() throws {
    let cal = calendar(firstWeekday: 1)
    let (vm, _) = try makeViewModel(calendar: cal)
    vm.selectedDate = date(cal, 2026, 11, 4, 12)
    vm.showPreviousWeek()
    #expect(vm.weekInterval.start == date(cal, 2026, 10, 25))
}

@MainActor
@Test func showTodayJumpsToWeekOfNow() throws {
    let cal = calendar(firstWeekday: 1)
    let (vm, _) = try makeViewModel(calendar: cal)
    vm.selectedDate = date(cal, 2026, 1, 7)
    let now = date(cal, 2026, 11, 4, 12)
    vm.showToday(now: now)
    #expect(vm.isShowingWeek(containing: now))
    #expect(vm.weekInterval.start == date(cal, 2026, 11, 1))
}

@Test func lastDayIsInclusive() {
    let cal = calendar(firstWeekday: 1)
    let interval = ScheduleWeek.weekInterval(containing: date(cal, 2026, 11, 4, 12), calendar: cal)
    #expect(ScheduleWeek.lastDay(of: interval, calendar: cal) == date(cal, 2026, 11, 7))
}
