import Foundation
import Observation

@MainActor
@Observable
final class ScheduleViewModel {
    let sessionRepo: any SessionRepository
    let clientRepo: any ClientRepository
    let workoutRepo: any WorkoutRepository
    let exerciseRepo: any ExerciseRepository
    let reminders: ReminderCoordinator
    private let defaults: UserDefaults
    private let calendar: Calendar

    var selectedDate: Date = .now
    var sessionsForDay: [SessionDTO] = []
    var mode: ScheduleMode = .day {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
    }
    var week: [ScheduleDay] = []
    var weekInterval: DateInterval { ScheduleWeek.weekInterval(containing: selectedDate, calendar: calendar) }
    var weekTitle: String { ScheduleWeek.weekTitle(weekInterval, calendar: calendar) }
    var clientNames: [UUID: String] = [:]
    var clientPhones: [UUID: String] = [:]
    var clientInjuries: [UUID: String?] = [:]
    /// Export is the only backup (PRD §9); the Schedule banner shows while true.
    var isExportReminderDue = false
    var isLoading = false

    private static let modeKey = "scheduleMode"
    private static let dismissedKey = "exportBannerDismissedAt"
    private static let dismissalWindow: TimeInterval = 3 * 86_400

    init(
        sessionRepo: any SessionRepository,
        clientRepo: any ClientRepository,
        workoutRepo: any WorkoutRepository,
        exerciseRepo: any ExerciseRepository,
        reminders: ReminderCoordinator,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.sessionRepo = sessionRepo
        self.clientRepo = clientRepo
        self.workoutRepo = workoutRepo
        self.exerciseRepo = exerciseRepo
        self.reminders = reminders
        self.defaults = defaults
        self.calendar = calendar
        mode = ScheduleMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .day
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case .day:
            let dayStart = calendar.startOfDay(for: selectedDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            sessionsForDay = (try? await sessionRepo.sessions(from: dayStart, to: dayEnd)) ?? []
        case .week:
            let interval = weekInterval
            let sessions = (try? await sessionRepo.sessions(from: interval.start, to: interval.end)) ?? []
            week = ScheduleWeek.group(sessions, into: ScheduleWeek.days(in: interval, calendar: calendar), calendar: calendar)
        }

        let clients = (try? await clientRepo.allIncludingArchived()) ?? []
        clientNames = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.name) })
        clientPhones = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.phoneE164) })
        clientInjuries = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.injuries) })

        await reminders.refresh()
        await refreshExportReminder()
    }

    func showPreviousWeek() { moveWeek(by: -7) }
    func showNextWeek() { moveWeek(by: 7) }
    func showToday(now: Date = .now) { selectedDate = now }
    func isShowingWeek(containing now: Date = .now) -> Bool { weekInterval.contains(now) }

    private func moveWeek(by days: Int) {
        selectedDate = calendar.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    private func refreshExportReminder() async {
        let last = defaults.double(forKey: "lastExportAt")
        let lastExport: Date? = last == 0 ? nil : Date(timeIntervalSince1970: last)
        let completed = (try? await sessionRepo.completedCount(since: lastExport)) ?? 0
        let dismissed = defaults.double(forKey: Self.dismissedKey)
        let recentlyDismissed = dismissed > 0
            && Date.now.timeIntervalSince1970 - dismissed < Self.dismissalWindow
        isExportReminderDue = !recentlyDismissed
            && exportReminderDue(lastExportAt: lastExport, now: .now, completedSinceExport: completed)
    }

    /// Hides the banner for a few days; the Settings badge stays until an export.
    func dismissExportReminder() {
        defaults.set(Date.now.timeIntervalSince1970, forKey: Self.dismissedKey)
        isExportReminderDue = false
    }
}
