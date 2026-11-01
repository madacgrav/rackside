# Research Findings

All paths are relative to the repo root. References were gathered by three research agents
and spot-checked against the source (`ScheduleView.swift`, `ScheduleViewModel.swift`,
`SessionRepository.swift`, `ClientReportView.swift`).

## Q1: How is the Schedule screen built today?

### Findings
- **Construction.** `RootView` builds the Schedule tab (tab value 0) as
  `ScheduleView(viewModel: ScheduleViewModel(...), openSettings: { selectedTab = 4 })`. It passes
  new `SwiftDataSessionRepository`, `SwiftDataClientRepository`, `SwiftDataWorkoutRepository` and
  `SwiftDataExerciseRepository` instances on the shared container, plus the shared
  `ReminderCoordinator` (`Sources/RootView.swift:15-22`, `:30-41`).
- **View model shape.** `ScheduleViewModel` is a `@MainActor @Observable final class`
  (`Sources/Features/Schedule/ScheduleViewModel.swift:4-6`). Its init stores the four repos,
  `reminders`, and `defaults: UserDefaults = .standard` (`:26-40`). The view owns it as
  `@State var viewModel` (`Sources/Features/Schedule/ScheduleView.swift:5`).
- **State** (`ScheduleViewModel.swift:14-21`):
  - `selectedDate = .now` and `sessionsForDay: [SessionDTO]`.
  - `clientNames`, `clientPhones` and `clientInjuries`, all keyed by client id.
  - `isExportReminderDue` and `isLoading`.
  - There is no error property.
- **`load()`** (`ScheduleViewModel.swift:42-57`):
  - Builds `[startOfDay(selectedDate), +1 day)` with `Calendar.current` (`:45-47`).
  - Fetches with `try? await sessionRepo.sessions(from:to:)`. A failure becomes `[]` (`:48`).
  - Rebuilds the three client maps from `clientRepo.allIncludingArchived()` (`:50-53`).
  - Ends with `await reminders.refresh()` and `refreshExportReminder()` (`:55-56`).
- **Reload triggers** (`ScheduleView.swift`):
  - `.task { await viewModel.load() }` when the view appears (`:91`).
  - `.onChange(of: viewModel.selectedDate)` (`:92-94`).
  - The new-session sheet's save callback (`:80`).
  - `onStatusChanged` passed into a pushed `SessionRunViewModel` (`:52`).
- **Layout** (`ScheduleView.swift:12-95`): a `NavigationStack` containing a `VStack(spacing: 0)`, which holds:
  1. An optional export-reminder banner (`:14-36`, backed by `ScheduleViewModel.swift:59-74`, with a 3-day dismissal window at `:24`).
  2. `DatePicker(..., displayedComponents: .date).datePickerStyle(.graphical)` bound to `$viewModel.selectedDate` (`:38-40`).
  3. `List(viewModel.sessionsForDay)` (`:42`).
  - The list overlay shows a `ProgressView` while loading with no rows, and otherwise
    `EmptyState("No sessions this day", "calendar")` when there are no rows (`:59-65`).
  - `.themedScreen()` is applied at `:66`. The title is "Schedule" (`:68`).
- **Toolbar.** There is one "Add" `plus` button (`:69-71`). It opens a `.sheet` with `SessionEditView`
  in create mode with `initialDate: viewModel.selectedDate` (`:72-82`). The sheet's callback
  receives `warning: String?`, which is shown in a "Calendar" `.alert` (`:83-90`).
- **Row tap.** A `NavigationLink` pushes `SessionRunView(viewModel: SessionRunViewModel(...), workoutRepo:)`.
  It passes the client's name (falling back to "Client"), phone, injuries and
  `onStatusChanged: { await viewModel.load() }` (`:43-56`).
- **Actions on the Schedule screen itself.** There are no swipe actions, context menus or series actions on Schedule. All session
  actions live in `SessionRunView` (`Sources/Features/Session/SessionRunView.swift`):
  - A "Text reminder" button (`:129-132`).
  - A "More" menu with Edit and Delete (`:134-144`).
  - Mark Completed, Cancelled and No-show, shown only while the session is scheduled (`:100-112`).
  - A scope dialog with "This session only" and "This and following sessions" for series sessions (`:210-222`).
  - Each action is routed through `run(_:scope:)` (`:237-254`) to `SeriesActions`
    (`Sources/Features/Session/SeriesActions.swift:58-`).
  - `SessionRunViewModel` calls `onStatusChanged` after a status change, after a delete, and in
    `reloadAfterEdit` (`Sources/Features/Session/SessionRunViewModel.swift:96, 118, 136, 255`).

## Q2: How does `SessionRepository.sessions(from:to:)` return sessions for a date range?

### Findings
- **One plain fetch.** `sessions(from:to:)` runs a single `FetchDescriptor<Session>`. Its predicate is
  `$0.startAt >= from && $0.startAt < to`, a half-open range on `startAt` only. The sort is
  `SortDescriptor(\.startAt)` with no limit, and rows are mapped to `SessionDTO`
  (`Sources/Persistence/SessionRepository.swift:178-185`). The repository is a `@ModelActor` (`:128-129`).
- **No recurrence logic at query time.** Series occurrences are stored as ordinary `Session` rows. One-off
  sessions and occurrences come back together, ordered by `startAt`, with no secondary sort key.
- **Series are materialized when scheduled.** `scheduleSeries` (`SessionRepository.swift:135-172`):
  - Computes a horizon of `Calendar.current` + `horizonWeeks` weeks minus 1 second (`:144-146`).
    The actor's default is 12 weeks (`:140`). The UI stepper defaults to 8 and allows 1...26
    (`Sources/Features/Schedule/SessionEditView.swift:20, 140`).
  - Calls `expandRecurrence` (`:147`), then inserts one `Session` per date with the shared `seriesId`,
    status `.scheduled`, `recurrenceData`, and its own `WorkoutInstance`/`PlannedEntry` copies (`:152-169`, `:388`, `:395-414`).
  - Saves once (`:170`).
  - Nothing extends a series after it is scheduled.
- **`expandRecurrence`** (`SessionRepository.swift:79-126`) is a pure function:
  - Daily rules step by `max(1, interval)` days (`:94-100`).
  - Weekly rules walk week intervals with `dateInterval(of: .weekOfYear)` from a Sunday-first calendar and add
    `weekday - 1` days (`:102-121`).
  - It is also used by `gapDates` (`SeriesActions.swift:49-53`).
- **Detached occurrences.** `detach(id:)` clears `seriesId` and `eventIdentifier` but keeps `recurrenceData`
  (`SessionRepository.swift:241-247`, comment at `:30-33`). The detached row is still returned by
  `sessions(from:to:)` like any other row. `resegment` rewrites times, notes, series id, rule and
  event id on existing rows (`:288-304`).
- **Related fetches:**
  - `seriesOccurrences(seriesId:from:)` (`:249-261`).
  - `upcoming(after:limit:)`, which fetches scheduled sessions after a date, ascending, with `fetchLimit` (`:187-195`).
  - `completedCount(since:)` (`:328`).
- **Model.** `Session` has `id`, `clientId`, `startAt`, `endAt`, `statusRaw`/`status`, `notes`,
  `instances` (cascade delete), `seriesId?`, `recurrenceData?`, `eventIdentifier?`, `createdAt` and `updatedAt`
  (`Sources/Models/Session.swift:22-65`). `AppRecurrence` has `frequency` (daily or weekly), `interval`,
  `weekdays` (1=Sun...7=Sat), `endDate?` and `occurrenceCount?` (`:10-20`).
- **No indexes.** There are no `#Index` declarations. The container uses a plain
  `ModelConfiguration(isStoredInMemoryOnly:)` (`Sources/Persistence/PersistenceController.swift:17`).
- **Cost and callers.** Cost scales with the number of stored rows inside the range: one fetch plus one DTO per row.
  It does not depend on the number of series or on their rules. The only caller is
  `ScheduleViewModel.load()`, which always passes a one-day range (`ScheduleViewModel.swift:45-48`).

## Q3: How does the codebase work out weeks and days?

### Findings
- **Which calendar.** Every site uses `Calendar.current`, either directly or through a defaulted `calendar: Calendar = .current`
  parameter. No code injects a non-default calendar. There are no `TimeZone`, `Locale` or
  `minimumDaysInFirstWeek` references in `Sources/`. Dates are stored as absolute `Date`s, and local day, week and
  time of day are derived when each calendar call runs.
- **Fixed `firstWeekday`.** The only fixed `firstWeekday` is in `expandRecurrence`, where `firstWeekday = 1` ("Sunday, matching EKWeekday
  numbering", `SessionRepository.swift:80-81`).

| Site | Operation | Calendar |
|---|---|---|
| `SessionRepository.swift:80-121` | week interval, weekday offsets, add `.weekOfYear`, `bySettingHour` | `.current` copy, `firstWeekday = 1` |
| `SessionRepository.swift:144-146` | series horizon, + N `.weekOfYear` | `.current` |
| `ReportingQueries.swift:55-61` (`ReportWindow.start`) | −4 or −12 `.weekOfYear` from now | `calendar = .current` param; only caller `ClientReportViewModel.swift:67` uses the default |
| `ReportingQueries.swift:237-248` (`weeklyVolumes`) | bucket by `dateInterval(of: .weekOfYear).start`, fallback `startOfDay` | `.current`, so the week start follows the device locale |
| `ReportingQueries.swift:156-157` (`progression`) | day bucket `startOfDay(performedAt)` | `.current` |
| `ReportingQueries.swift:197-202` (`consistency`) | raw `startAt` range; nil `from` means `.distantPast` | none |
| `ScheduleViewModel.swift:45-47` | `startOfDay(selectedDate)` + 1 day | `.current` |
| `SessionEditView.swift:58-60` | default start = `startOfDay(initialDate)` at 09:00 | `.current` |
| `SessionEditView.swift:191` | hour/minute components for "following" edits | `.current` |
| `SessionEditView.swift:70, 126-127` | weekday toggles 1...7 shown with a hard-coded `["Sun"..."Sat"]` | none, always Sunday-first, English |
| `SeriesActions.swift:30-39` (`retime`, `segmentRule`) | `bySettingHour`, `component(.weekday)` | `calendar = .current` param |
| `ExportReminder.swift:15` | day difference against a 14-day threshold | `.current` |
| `NotificationService.swift:102-106` | trigger date components | `.current`, no explicit time zone |
| `MessagingService.swift:12` | `isDateInTomorrow` | `.current` |
| `ClientReportView.swift:133, 180` | `startOfDay` chart x; Charts `unit: .weekOfYear` | `.current`; the Charts environment calendar is implicit |
| `ScheduleView.swift:38, 108-109` | graphical `DatePicker`; `.formatted(date: .omitted, time: .shortened)` | system locale |
| `CalendarService.swift:11-13, 105, 123` | `rule.weekdays` mapped to `EKWeekday(rawValue:)`; `startDate = startAt` | EventKit defaults |

- **Not calendar math:**
  - `ScheduleViewModel.dismissalWindow` is `3 * 86_400` seconds (`ScheduleViewModel.swift:24`).
  - `ReminderCoordinator` has no calendar code of its own. It calls `upcoming(after: .now, limit: 64)`
    (`Sources/Services/ReminderCoordinator.swift:54`).

## Q4: What does a session row show on Schedule and elsewhere?

### Findings
- **`SessionRow`** (`ScheduleView.swift:99-128`) takes `session` and `clientName`. Its layout is
  `HStack { VStack(alignment: .leading) {...}; Spacer(); repeat icon; StatusChip }`:
  - The client name in `Theme.Fonts.display()`.
  - The time range `start – end` (`.formatted(date: .omitted, time: .shortened)`) in `.caption` `.secondary`.
  - Workout instance names joined with ", ", in `.caption2` `.tertiary`, only when there are instances.
  - An `Image(systemName: "repeat")` when `seriesId != nil`, with accessibility label "Repeating" (`:119-124`).
  - `StatusChip(status:)`.
  - It sets no explicit spacing. Previews cover scheduled, completed, no-show and series rows (`:141-148`).
- **`StatusChip`** (`Sources/Features/Components/StatusChip.swift`):
  - Renders nothing for `.scheduled`.
  - Completed shows `checkmark.circle.fill` in `Theme.Colors.success`.
  - Cancelled shows `xmark.circle.fill` in `.secondary`.
  - No-show shows `person.fill.xmark` in `Theme.Colors.warning`.
  - The label uses `.caption.weight(.semibold)` with padding `sm` (8) horizontally and `xs` (4) vertically, on a capsule filled with the color at 0.18 opacity.
- **`TitleCaptionRow<Trailing>`** (`Sources/Features/Components/TitleCaptionRow.swift:4-36`):
  - Title, optional caption and optional tertiary line, plus a trailing view.
  - Layout is `HStack(spacing: md)` around `VStack(spacing: 2)`. Children are combined for accessibility.
  - `SessionRow` does not use it. The report screens and `SessionRunView`'s planned entries do.
- **`EmptyState`** wraps `ContentUnavailableView` (title, systemImage, optional description and
  action button) (`Sources/Features/Components/EmptyState.swift`).
- **`ErrorBanner`** is a `Section` with a `Label` in `Theme.Colors.danger`. It renders nothing when the message is nil
  (`Sources/Features/Components/ErrorBanner.swift`). Schedule does not use it.
- **`HeroScreen`** is a centered icon, title, message and primary button. Its doc comment names the lock and recovery
  screens. It is not used on Schedule, client detail or reports (`Sources/Features/Components/HeroScreen.swift`).
- **Theme** (`Sources/Support/Theme.swift`):
  - Asset colors: accent, brandPrimary, brandSecondary, success, warning, danger, personalBest,
    surface and surfaceRaised (`:5-15`).
  - Fonts: `display()` is rounded semibold headline (`:19-21`). `numeric` is rounded monospaced (`:23`).
  - Spacing: xs 4, sm 8, md 12, lg 20 (`:26-31`). The row radius is 12 (`:33-35`).
  - `themedScreen()` hides the scroll background and sets the surface background. `themedRows()` sets the row background to
    `surfaceRaised` (`:38-49`).
- **Client detail** (`Sources/Features/Clients/ClientDetailView.swift`):
  - It reuses `SessionRow`, passing the abbreviated date in the `clientName` slot (`:117`).
  - "Upcoming Sessions" and "Recent Sessions" sections (`:27-43`) show plain `.secondary` text when empty (`:29, 38`).
  - `ErrorBanner` sits at `:10`.
  - The upcoming/recent split comes from the pure `splitSessions(_:now:)` (`ClientDetailViewModel.swift:61-64`).
- **Reports** do not use `SessionRow` or `StatusChip`:
  - `ClientReportView` uses `LabeledContent` rows for sessions (`:46-55`) and a raw
    `ContentUnavailableView` for its empty state (`:13-18`).
  - `ExerciseReportView`'s History section uses `TitleCaptionRow` (`:32-42`).
- **`SessionRunView`** displays:
  - A "Time" row with the abbreviated date and short time (`:58`).
  - A "Repeats weekly" label when the session is in a series (`:59-63`).
  - Status as plain `LabeledContent` text, not a chip (`:64, 292-299`).

## Q5: How are view models built and tested in this project?

### Findings
- **Shape.** All feature view models are `@MainActor @Observable final class`. Dependencies are stored as `let` and
  injected through `init` as existential protocols (`any SessionRepository`, etc.):
  - `ScheduleViewModel.swift:7-11, 26-40`.
  - `SessionRunViewModel.swift:52-73`, which also takes `calendar: any CalendarSyncing = EventKitCalendarService()` and an
    `onStatusChanged` closure.
  - `ClientDetailViewModel.swift:21-35`.
- **Clocks and calendars in view models.** Date logic meant for tests is pulled out as a static pure function that takes `now`:
  `ClientDetailViewModel.splitSessions(_:now:)` (`:61`). `ScheduleViewModel` builds its window from
  `Calendar.current` inside `load()` and takes no injected clock or calendar.
- **How tests fix dates.** No test pins a `Calendar`, `TimeZone` or clock:
  - Absolute dates come from `Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 7))`
    (`Tests/SchedulingTests.swift:6`, `Tests/SessionRepositoryTests.swift:79-86, 114`).
  - Relative dates use `Date.now.addingTimeInterval` (`Tests/ClientDetailViewModelTests.swift:5-12`) or
    `bySettingHour` on `.now + 1 day` (`Tests/SessionRepositoryTests.swift:213, 244`).
- **Test setup:**
  - Real `@ModelActor` repositories over `PersistenceController.makeContainer(inMemory: true)`
    (`Tests/SessionRepositoryTests.swift:11`, `Tests/SessionRunViewModelTests.swift:81, 199, 286`,
    `Tests/SeriesActionsTests.swift:36`).
  - `FakeCalendar`, an actor conforming to `CalendarSyncing`, records removals, updates, pushes and series endings
    (`Tests/SessionRunViewModelTests.swift:7-72`).
  - `FailingSessionRepo` wraps a real repository and throws on demand (`:114-170`).
  - A `Flag` class captured by `onStatusChanged` records that a reload happened (`:74-77, 101, 110`).
  - `ClientDetailViewModelTests` tests only the pure split function, with no container (`:14, 30`).
  - Tests use Swift Testing (`@Test`, `#expect`).
- **No `ScheduleViewModel` test exists.** Nothing in `Tests/` references `ScheduleViewModel`, `selectedDate` or its `load()`.
- **`PreviewFixtures`** (`Sources/Support/PreviewFixtures.swift`) is a `@MainActor enum`:
  - Static DTOs: `client` (`:13`), `bench`/`squat` (`:19-26`), `workout` (`:28`), and `scheduledSession`, which runs 9:00-10:00 today
    (`:33-36`).
  - `seriesSession` adds a weekly rule for today's weekday (`:51-60`). It is not inserted into the preview container.
  - `loggedSets` (`:62`).
  - `container()` seeds an in-memory store with one session (`:108-119`).
  - `repositories()` returns every repository plus a `ReminderCoordinator` (`:89-105`).
  - Used by `#Preview`s in Schedule (`ScheduleView.swift:131, 143-146`), SessionEdit, SessionRun, SetTable, the client screens,
    the workout and exercise screens, the reports and Settings.

## Q6: How do other screens change content in response to changing data or the selected date?

### Findings
- **No reactive store queries.** There is no `@Query`, `NotificationCenter` or `.onReceive` in `Sources/`. Views render DTOs held by view models, and
  view models refetch from repositories.
- **Initial load.** `.task { await viewModel.load()/reload() }` is used on every list and detail screen:
  - `ScheduleView.swift:91`, `WorkoutListView.swift:77`, `ExerciseListView.swift:61`, `ClientListView.swift:56`.
  - `ClientDetailView.swift:101`, `SessionRunView.swift:234`, `ClientReportView.swift:74`, `ExerciseReportView.swift:50`.
  - `.task(id:)` is not used anywhere.
- **Input changes.** `.onChange(of:)` plus `Task { await ... }` handles input changes:
  - `selectedDate` (`ScheduleView.swift:92-94`).
  - Search query (`ExerciseListView.swift:62`, `ClientListView.swift:61`).
  - Report window (`ClientReportView.swift:75`, which reloads and re-renders the report).
- **After a sheet saves.** The sheet content receives an `onSaved` closure. It calls the closure and then `dismiss()` after a
  successful save, and the presenter reloads inside the closure:
  - `SessionEditView.swift:163-168` calls back to `ScheduleView.swift:72-82`.
  - Also `SessionRunView.swift:147-159` (`reloadAfterEdit`), `ClientDetailView.swift:96-100` and `WorkoutListView.swift:46-63`.
  - `.sheet(onDismiss:)` appears only at `SessionRunView.swift:147`, where it resets `editScope`.
- **After a status change, cancel or delete.** `SessionRunViewModel.onStatusChanged` comes from the presenting screen
  (`ScheduleView.swift:52`, `ClientDetailView.swift:114`). The presenter's reload calls `reminders.refresh()`
  (`ScheduleViewModel.swift:55`, `ClientDetailViewModel.swift:57`), which re-plans notifications from
  `upcoming(after: .now, limit: 64)` (`ReminderCoordinator.swift:51-71`). After a delete, `SessionRunView` dismisses itself,
  waiting for any calendar warning to be acknowledged first (`SessionRunView.swift:171-177, 250-263`).
- **On foreground.** `RootView.swift:78-90` runs `reminders.refresh()` and recomputes the export reminder on
  `scenePhase == .active`. Settings and LockGate also watch `scenePhase` (`SettingsView.swift:111-112`, `LockGateView.swift:18-19`).
- **Calendar side effects.** `SeriesActions` changes the store first and then the calendar. A calendar failure becomes a
  `calendarWarning` string and never rolls back the store change (`SeriesActions.swift:55-63, 65-206`).
  Single sessions call `calendar.remove` from the view model (`SessionRunViewModel.swift:121-135, 245-253`).
  `CalendarSyncing` is defined at `Sources/Services/CalendarService.swift:55-71`.
- **Switching views:**
  - There is no `TabView` with `.page` style, no `DragGesture` and no `.tabViewStyle` in `Sources/`. The only
    `TabView` is the root tab bar (`RootView.swift:60-65`).
  - The only swipe is `.swipeActions(edge: .trailing)` on workout rows (`WorkoutListView.swift:24-31`).
  - The only segmented control that switches views of the same data is
    `Picker("Window", selection: $viewModel.window).pickerStyle(.segmented)` over `ReportWindow.allCases`
    (`ClientReportView.swift:21-24`), reloaded by `.onChange` at `:75`. The other segmented pickers are form or settings fields
    (`ExerciseEditView.swift:72`, `SettingsView.swift:57`).
  - Schedule changes the selected day only through the graphical `DatePicker`.

## Cross-Cutting Observations
- **Load pattern.** Each screen pairs an `@Observable` view model with a `load()`/`reload()` that refetches DTOs from the repository.
  Refresh is triggered explicitly by `.task`, `.onChange` or callbacks. SwiftData change observation is not used.
- **Week start.** Two conventions exist. Recurrence expansion forces a Sunday start (`firstWeekday = 1`), and the
  weekday toggles are hard-coded Sunday-first in English. Reporting's `weeklyVolumes` and the Charts week bars follow the device
  locale's first weekday through `Calendar.current`.
- **Stored occurrences.** Series occurrences are real rows. Any range query sees one-off, series and detached sessions in the same way, and
  `seriesId != nil` is the only marker of series membership (shown as the `repeat` icon).
- **Silent failures.** Schedule swallows load errors (`try?` → `[]`) and shows no error UI. Client detail logs and swallows session-load
  errors but has an `ErrorBanner` for other failures.
- **Calendar parameters.** Testable date logic takes `now` or `calendar` parameters with `.current` defaults (`SeriesActions`,
  `ReportWindow`, `splitSessions`). Tests still rely on the device calendar.

## Open Areas
- `SessionDTO` was not opened directly. That its mapping touches the `instances` relationship is inferred from usage
  (`SessionRepository.swift:255`).
- No tests ran, so behavior under non-Gregorian calendars or locales whose week starts on Monday is unverified.
- Performance of `sessions(from:to:)` over wider ranges was not measured. There are no indexes on `startAt`.
- How the `ReminderCoordinator` alert offsets (24 h / 1 h) are computed in `NotificationService.selectAlerts` was
  not traced.
