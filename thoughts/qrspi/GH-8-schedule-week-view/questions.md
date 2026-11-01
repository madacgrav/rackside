# Research Questions

## Context
Focus on the Schedule feature (`Sources/Features/Schedule/`), the session persistence layer
(`Sources/Persistence/SessionRepository.swift`, `ReportingQueries.swift`), shared UI
(`Sources/Support/Theme.swift`, `Sources/Features/Components/`, `PreviewFixtures.swift`) and
the related tests under `Tests/`.

## Questions
1. How is the Schedule screen built today? Trace `ScheduleView` and `ScheduleViewModel` from
   when the tab appears to rendered rows: what state they hold (selected date, loaded
   sessions, errors), when and how they reload, and which navigation destinations, sheets and
   actions (create, edit, run, series actions) each row or toolbar item leads to.
2. How does `SessionRepository.sessions(from:to:)` return sessions for a date range? Trace how
   stored one-off sessions and recurring series are combined (`expandRecurrence`, the recurrence
   horizon, detached occurrences), how results are ordered, and how the cost scales with the
   width of the range.
3. How does the codebase work out weeks and days? List every place that computes a week
   interval, first weekday, start of day or day bucket (`expandRecurrence`,
   `ReportingQueries.weeklyVolumes`, the report range enum, `SessionEditView`), and say which
   `Calendar` each uses (`Calendar.current`, an injected calendar, a fixed `firstWeekday`) and
   how time zone and locale are handled.
4. What does a session row show on Schedule and elsewhere (client detail, reports)? Describe
   the row components (`TitleCaptionRow`, `StatusChip`, etc.), the theme tokens and spacing
   they use, how status, time, client name and series membership are displayed, and how empty
   and error states are shown (`EmptyState`, `ErrorBanner`).
5. How are view models built and tested in this project? Using existing view model tests
   (`SessionRunViewModelTests`, `ClientDetailViewModelTests`) and repository tests
   (`SessionRepositoryTests`, `SchedulingTests`), describe how dates and calendars are injected
   or fixed in tests, what in-memory container or fake setup is used, and how `PreviewFixtures`
   seeds sessions for previews.
6. How do other screens change content in response to changing data or the selected date?
   Describe the patterns used for refresh after a sheet dismisses or a session is saved,
   cancelled or deleted (including series actions and calendar/notification side effects), and
   whether any screen uses paging, swiping or segmented controls to switch between views of
   the same data.
