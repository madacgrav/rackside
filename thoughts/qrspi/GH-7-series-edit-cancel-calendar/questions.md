# Research Questions

## Context
Focus on session scheduling and its side effects: the `Session` model and
`SessionRepository` (`Sources/Models/Session.swift`, `Sources/Persistence/`), the
Schedule and Session feature screens and view models (`Sources/Features/Schedule/`,
`Sources/Features/Session/`, `Sources/Features/Clients/ClientDetailViewModel.swift`),
calendar sync in `Sources/Services/CalendarService.swift`, reminders in
`Sources/Services/ReminderCoordinator.swift` / `NotificationService.swift`, the archive
format in `Sources/Services/Archive/`, and the matching tests and fakes in `Tests/`.

## Questions
1. How is a recurring series created end to end? Trace from `SessionEditView` through
   `SessionRepository` to the stored `Session` rows: what fields (`seriesId`,
   recurrence, start dates, `eventIdentifier`) are set on each occurrence, how many
   occurrences are generated and over what horizon, and how `AppRecurrence` is modelled.

2. How does `EventKitCalendarService` (and the `CalendarSyncing` protocol) create, update
   and remove events today? Specifically, how is a recurring event created, which
   `EKSpan` values (if any) are used, how `eventIdentifier` values are stored and resolved
   (`EventIdentifierResolution.swift`), and what happens for the share-sheet path.

3. What do the existing single-session edit, status change (completed / cancelled /
   no-show) and delete flows do, step by step, in `SessionEditView`,
   `SessionRunViewModel`, `ScheduleViewModel` and `ClientDetailViewModel`? Where are
   `seriesId` checks applied, and what is the order of repository writes versus calendar
   and reminder calls, including error handling and logging?

4. Which `SessionRepository` methods query or mutate sessions by series (by `seriesId`,
   date range, or status), and what guarantees exist about occurrences that already have
   logged sets or a non-scheduled status?

5. How does `ReminderCoordinator` decide which notifications to schedule or clear, and
   what triggers a refresh after a session is added, edited, cancelled or deleted?

6. How are series and recurrence fields represented in `SchemaV1`, `SessionDTO` and the
   v1 archive (`ArchiveV1`, `DataArchive`, `Tests/Fixtures/export-v1.json`), and what
   would a change to `Session` stored properties imply for the migration plan and the
   archive round-trip tests?

7. What test doubles exist for calendar, notifications and repositories (in
   `Tests/SessionRunViewModelTests.swift`, `CalendarServiceTests.swift`,
   `CalendarMappingTests.swift`, `SchedulingTests.swift`, etc.), and what series-related
   behaviour do current tests already cover?
