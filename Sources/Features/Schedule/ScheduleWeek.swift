import Foundation

enum ScheduleMode: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        }
    }
}

/// One day of the week list. Empty days are kept so the list always shows 7 sections.
struct ScheduleDay: Identifiable, Equatable {
    let date: Date
    let sessions: [SessionDTO]
    var id: Date { date }
}

/// Week math for the Schedule week view. Pure, and always takes the calendar, so the week start
/// follows the user's locale and tests can pin one.
enum ScheduleWeek {
    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) { return interval }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// Start of each day in `interval`, stepping by calendar day so DST weeks still give 7.
    static func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Buckets sessions by local day. Sessions outside `days` are dropped, and each day is sorted by start.
    static func group(_ sessions: [SessionDTO], into days: [Date], calendar: Calendar) -> [ScheduleDay] {
        let buckets = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startAt) }
        return days.map { day in
            ScheduleDay(date: day, sessions: (buckets[day] ?? []).sorted { $0.startAt < $1.startAt })
        }
    }

    /// The last day of the week (`interval.end` is exclusive).
    static func lastDay(of interval: DateInterval, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: interval.end)) ?? interval.start
    }

    static func weekTitle(_ interval: DateInterval, calendar: Calendar) -> String {
        let style = Date.IntervalFormatStyle(
            date: .abbreviated, time: .omitted,
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone
        )
        return style.format(interval.start..<lastDay(of: interval, calendar: calendar))
    }
}
