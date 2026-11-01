# Structure Outline

## Approach
Add a Day | Week segmented toggle to the Schedule tab. Day mode stays as it is today. Week mode makes one
`sessions(from:to:)` fetch for the locale-aware week that contains `selectedDate`, groups the results into 7 day
buckets with pure functions, and shows them as a list with one section per day using the existing `SessionRow`. The repository and
schema don't change. `ScheduleViewModel` gets an injected `Calendar` so week math can be tested reliably.

**Test command** (from the GH-7 plan):
`xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5`

---

## Phase 1: Week mode shows the selected week
The toggle switches to a 7-section week list for the week that contains `selectedDate`. Rows open
`SessionRunView`, and saves, status changes and deletes refresh the week through the existing callbacks. To reach another
week in this phase, pick a date in Day mode and switch back to Week.

**Files**: `Sources/Features/Schedule/ScheduleViewModel.swift`, `Sources/Features/Schedule/ScheduleView.swift`,
new `Sources/Features/Schedule/ScheduleWeek.swift`, new `Tests/ScheduleViewModelTests.swift`
**Key changes**:
- New `enum ScheduleMode: String, CaseIterable, Identifiable { case day, week }`, with `title` for the picker.
- New pure helpers in `ScheduleWeek.swift`:
  - `static func weekInterval(containing: Date, calendar: Calendar) -> DateInterval`, built from
    `calendar.dateInterval(of: .weekOfYear, for:)`.
  - `static func days(in: DateInterval, calendar: Calendar) -> [Date]`, which returns 7 day starts, stepping with `date(byAdding: .day)`.
  - `static func group(_ sessions: [SessionDTO], into days: [Date], calendar: Calendar) -> [ScheduleDay]`.
  - New `struct ScheduleDay: Identifiable { let date: Date; let sessions: [SessionDTO]; var id: Date { date } }`.
- `ScheduleViewModel`:
  - `init(..., defaults: UserDefaults = .standard, calendar: Calendar = .current)`. This is source-compatible with `RootView`.
  - `var mode: ScheduleMode = .day`.
  - `var week: [ScheduleDay] = []`.
  - `var weekInterval: DateInterval { get }`.
  - `load()` branches on `mode`. Day mode keeps the existing one-day range and `sessionsForDay`. Week mode makes one fetch for
    `weekInterval` and sets `week`. Both modes use the injected `calendar` instead of `Calendar.current`.
- `ScheduleView`:
  - A segmented `Picker` bound to `viewModel.mode`, and `.onChange(of: viewModel.mode)` reloads.
  - In Week mode, the month `DatePicker` is hidden and a `List` shows a `Section(header: day.date.formatted(...))` for each `ScheduleDay`.
    Empty days get a secondary "No sessions" row.
  - The row's `NavigationLink` and `SessionRunView` construction move into a private `sessionLink(_:)` that both modes
    share, so `onStatusChanged: { await viewModel.load() }` refreshes whichever mode is showing.

**Verify**:
- The test command passes, including the new `ScheduleViewModelTests`:
  - `weekInterval` with Sunday-first and Monday-first calendars in a fixed time zone.
  - `days` returns 7 day starts across a DST change.
  - `group` puts each session in the right day, keeps empty days, and excludes a session at the next week's start.
  - Week-mode `load()` over an in-memory container with sessions on 3 days fills `week`.
  - Day-mode `load()` still returns only the selected day.
- Manual check on the simulator:
  - Toggle to Week and see 7 sections.
  - Tap a row, cancel the session, go back, and see the chip on the week list.
  - Add a session from Week mode and see it appear.

---

## Phase 2: Move between weeks
A header row in Week mode, `‹  Oct 26 – Nov 1  ›  Today`, moves between weeks without leaving Week mode.

**Files**: `Sources/Features/Schedule/ScheduleViewModel.swift`, `Sources/Features/Schedule/ScheduleView.swift`,
`Sources/Features/Schedule/ScheduleWeek.swift`, `Tests/ScheduleViewModelTests.swift`
**Key changes**:
- `ScheduleViewModel`:
  - `func showPreviousWeek()` and `func showNextWeek()` move `selectedDate` by ∓7 days with `calendar.date(byAdding: .day)`.
  - `func showToday(now: Date = .now)`.
  - `var isShowingCurrentWeek: Bool`, which disables Today when the current week is already showing.
  - The existing `.onChange(of: selectedDate)` reloads.
- `static func weekTitle(_ interval: DateInterval, calendar: Calendar) -> String` uses a locale-aware date interval format.
  The end of the title is the last day, not the exclusive end.
- `ScheduleView`:
  - A header `HStack` with `IconButton`/`Button` chevrons, the title and a Today button, all with accessibility labels
    "Previous week", "Next week" and "Today".
  - It is shown only in Week mode.

**Verify**:
- The test command passes. New tests cover:
  - previous and next cross month and year boundaries and keep the time of day irrelevant;
  - `showToday` lands in the week containing the injected `now`;
  - `weekTitle` shows the last day, not the day after.
- Manual check: page forward and back several weeks, tap Today, and switch to Day. The date picker shows the same `selectedDate`.

---

## Phase 3: Remember the mode, and add previews
The chosen mode survives relaunch. Previews show Week mode filled with sessions.

**Files**: `Sources/Features/Schedule/ScheduleViewModel.swift`, `Sources/Features/Schedule/ScheduleView.swift`,
`Sources/Support/PreviewFixtures.swift`, `Tests/ScheduleViewModelTests.swift`
**Key changes**:
- `ScheduleViewModel.mode` reads its initial value from `defaults` under the key `"scheduleMode"` and writes it back in `didSet`.
  An unknown or missing value falls back to `.day`.
- `PreviewFixtures`:
  - `static var weekSessions: [SessionDTO]`, with sessions on 3 to 4 days of the current week in mixed statuses and one series.
  - Seed them into `container()`, or a separate `weekContainer()` if seeding them into `container()` changes other previews.
- `#Preview("Week")` for `ScheduleView` with the mode set to `.week`.

**Verify**:
- The test command passes. A new test checks that the mode round-trips through an isolated `UserDefaults(suiteName:)` and that an invalid
  stored value falls back to Day.
- Manual check: the Week preview renders in light and dark. Kill and relaunch the app and it still opens in Week.

---

## Phase 4: Device verification and docs
Run the full manual pass on the "madphone" device and record it.

**Files**: `BACKLOG.md`, `thoughts/qrspi/GH-8-schedule-week-view/plan.md`
**Key changes**:
- Move row 6 to the Done table, linked to the PR.
- Record the device pass in the plan.

**Verify**:
- The device build and install succeed with the commands in the memory note.
- On the device:
  - Day and Week toggle.
  - Chevrons and Today work.
  - Cancel a series session from the week list, choosing "This session only", and the week refreshes.
  - Add a session from Week mode.
  - Check a week containing the DST change, for example the week of 2026-11-01 in the US.
  - Check the export banner and toolbar layout in both modes.

---

## Testing Checkpoints
- **After Phase 1:**
  - Week mode exists and shows 7 sections for the week containing `selectedDate`.
  - Rows navigate, and mutations refresh the week.
  - Day mode behaves as before.
  - `ScheduleViewModelTests` covers week math, grouping and both load modes.
  - The calendar is injected, with `.current` as the default.
- **After Phase 2:** The chevrons and Today change weeks inside Week mode. The header title is locale-formatted and correct at the end of the range.
- **After Phase 3:** The mode persists across launches, and the Week preview shows filled and empty days.
- **After Phase 4:** The device pass is recorded and BACKLOG row 6 is moved to Done. Ready for PR.
