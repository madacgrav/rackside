# Design Discussion — Week view on Schedule (#8)

## Current State
- **Screen.** The Schedule tab is a `NavigationStack` containing, from top to bottom:
  - an optional export banner;
  - a graphical month `DatePicker` bound to `selectedDate`;
  - a `List(sessionsForDay)` of `SessionRow`s (`Sources/Features/Schedule/ScheduleView.swift:12-95`).
  - Empty and loading states are list overlays (`:59-65`).
- **Loading.** `ScheduleViewModel.load()` always fetches one day, `[startOfDay(selectedDate), +1 day)`, using
  `Calendar.current` (`Sources/Features/Schedule/ScheduleViewModel.swift:42-57`). It turns a failed load into an empty list with `try?`.
- **Reloads** happen when the screen appears, when `selectedDate` changes, after the new-session sheet saves, and through
  `onStatusChanged` from the pushed `SessionRunView` (`ScheduleView.swift:52, 80, 91-94`).
- **The range query already handles any width.** `SessionRepository.sessions(from:to:)` is one half-open
  fetch on `startAt`, sorted ascending (`Sources/Persistence/SessionRepository.swift:178-185`). Series
  occurrences are stored rows, so a week range needs no recurrence logic.
- **Week math is inconsistent.** Recurrence forces a Sunday start (`SessionRepository.swift:80-81`), while
  `weeklyVolumes` follows the device locale (`Sources/Persistence/ReportingQueries.swift:237-248`). There is no
  `ScheduleViewModel` test, and nothing injects a calendar into the view model.
- **PRD §5.4** asks for a calendar view of the trainer's day *and week*. Only the day view exists today.

## Desired End State
- **Toggle.** A segmented **Day | Week** picker sits at the top of the Schedule tab.
  - **Day** is today's screen, unchanged: month picker plus the one-day list.
  - **Week** replaces the month picker with a header row, `‹  Oct 26 – Nov 1  ›  Today`, and shows one
    `List` with a section for each of the 7 days of the week that contains `selectedDate`.
- **Week start.** The week starts on the device locale's first weekday (`Calendar.current.firstWeekday`).
- **Sections.** Each section header shows the day, for example "Mon Oct 27". Rows are the existing `SessionRow`, sorted by start
  time, and tap through to `SessionRunView` exactly as in Day mode. Days with no sessions show a short
  secondary "No sessions" line.
- **Navigation.** `‹` and `›` move `selectedDate` back or forward 7 days. **Today** sets `selectedDate` to now. Switching back to
  Day shows the selected date, so the two modes share one `selectedDate`.
- **Add.** The toolbar's Add button opens `SessionEditView` with `initialDate: selectedDate`, as it does now, in both modes.
- **Refresh.** Saving, editing, cancelling or deleting from the week list refreshes the week, through the same `onSaved` and
  `onStatusChanged` callbacks.
- **Persistence.** The chosen mode is remembered across launches.

**How we verify:**
- New `ScheduleViewModelTests`:
  - The week covers the right 7 days for Sunday-first and Monday-first calendars.
  - The query range is half-open, so a session at the next week's start is excluded.
  - Sessions land in the correct day bucket, including across a DST change.
  - Empty days are present in the grouping.
  - Day mode still loads a single day.
- `#Preview`s for Week mode with sessions spread across several days.
- A manual pass on the simulator and on the "madphone" device:
  - toggle between Day and Week, use the chevrons and Today;
  - tap a row, then cancel a series session and confirm the week refreshes;
  - add a session from Week mode.

## Patterns to Follow
- **View model shape.** Keep `ScheduleViewModel` a `@MainActor @Observable final class` with dependencies injected in `init`
  (`ScheduleViewModel.swift:4-6, 26-40`). Add parameters with defaults so `RootView.swift:30-41` does not need to change.
- **Date logic** goes in static pure functions that take `now` and `calendar`, as in
  `ClientDetailViewModel.splitSessions(_:now:)` (`Sources/Features/Clients/ClientDetailViewModel.swift:61`).
  Defaulted `calendar: Calendar = .current` parameters already appear in `SeriesActions.swift:30-39` and `ReportingQueries.swift:55-61`.
- **Segmented switch with reload.** Follow `Picker(...).pickerStyle(.segmented)` plus `.onChange { Task { await load() } }` from
  `Sources/Features/Reports/ClientReportView.swift:21-24, 75`.
- **Refresh** through explicit `.task`, `.onChange` and callbacks (`ScheduleView.swift:52, 80, 91-94`). Do not add `@Query`.
- **Reuse components.** Use `SessionRow` (`ScheduleView.swift:99-128`) and `EmptyState`. Use theme tokens and modifiers
  `themedScreen()`, `themedRows()` and `Theme.Spacing` (`Sources/Support/Theme.swift:26-49`).
- **Tests** use Swift Testing with real repositories over `PersistenceController.makeContainer(inMemory: true)`
  (`Tests/SessionRepositoryTests.swift:11`). Fixed dates come from `DateComponents` (`Tests/SchedulingTests.swift:6`).
  Unlike existing tests, the new tests pin an explicit `Calendar` with a fixed time zone and `firstWeekday`, so results don't depend
  on the machine's locale.
- **Previews** seed through `PreviewFixtures` (`Sources/Support/PreviewFixtures.swift:89-119`).

**Do not follow:**
- **Hard-coded Sunday-first.** Do not copy the hard-coded `firstWeekday = 1` or the English `["Sun"..."Sat"]` array
  (`SessionRepository.swift:80-81`, `SessionEditView.swift:126-127`). Week headers use the calendar and
  `Date.formatted` so they follow the user's locale.
- **Calendar reads inside methods.** Do not read `Calendar.current` inside `load()` with no way to inject it (`ScheduleViewModel.swift:45`). The
  new code takes the calendar as a parameter.

## Design Decisions
1. **Layout: a Day | Week segmented toggle, where Week is a list with a section per day.** It reuses `SessionRow`,
   navigation and refresh with no new custom drawing, and it matches the app's existing segmented pattern. A time grid
   would be cramped on a phone and need custom layout. A week strip never shows the whole week's sessions at once.
2. **Week start follows the device locale.** This matches `weeklyVolumes` and the chart week bars. Recurrence storage stays
   Sunday-based internally. That is invisible to users and out of scope.
3. **Navigation: chevrons plus Today, with no swipe.** The app has no paging or gesture code, and buttons are simpler to make accessible and to test.
4. **Show all 7 days in the week.** Empty days show "No sessions", so free slots stand out when booking. Week mode doesn't need a whole-list
   `EmptyState`.
5. **One shared `selectedDate`.** Week mode shows the week containing `selectedDate`. The chevrons move it by ±7 days, and
   switching modes keeps it. This keeps the state small and makes "Add" behave the same in both modes.
6. **Mode is view model state, persisted in `UserDefaults`.** `ScheduleViewModel` already takes `defaults`
   (`:26-40`), and the view reloads on `.onChange(of: mode)`. `load()` picks a day range or a week range based on the mode.
7. **One fetch per week.** Call `sessions(from: weekStart, to: weekEnd)` once and group the results into 7 day buckets in memory
   with a pure function. Don't make 7 per-day calls.
8. **Calendar injected into `ScheduleViewModel`.** Add `calendar: Calendar = .current` to the init and use it for both modes, so the
   week-boundary and DST tests are deterministic.
9. **Swallowed load errors stay as they are.** Keep the `try?` behavior to match today's Day mode. It is noted as a gap, not fixed here.

## What We're NOT Doing
- No hourly time grid, drag-to-reschedule, or swipe or paging between weeks.
- No changes to `SessionRepository`, the schema, recurrence expansion, or the Sunday-first weekday toggles in
  `SessionEditView`.
- No per-day "+" add buttons and no long-press "add at this day". Add keeps using `selectedDate`.
- Tapping a day header does not jump to Day mode. This can come later.
- No session counts or dots on the month `DatePicker` in Day mode.
- No new error UI for failed Schedule loads (see Decision 9).
- No session notes on rows. That is backlog row 17, #19.
- No `startAt` index or performance work. A week fetch is small.

## Open Risks
- **List identity.** A `List` with seven `Section`s and placeholder rows needs stable ids, for example the day's start date. Otherwise SwiftUI
  may animate oddly when the week changes.
- **DST weeks.** A week containing a DST change is not exactly 7 × 86,400 seconds. Bounds must come from
  `calendar.dateInterval(of: .weekOfYear, for:)` and day stepping must use `date(byAdding: .day)`, never raw seconds.
- **Layout in Week mode.** The month picker uses a lot of vertical space in Day mode. Hiding it in Week mode changes the layout, so check that the
  export banner and toolbar still look right in both modes, in light and dark appearance.
- **Mismatched week starts.** Under a Monday-first locale, the week view starts on Monday while repeat-day toggles still read Sun–Sat. That's
  a small inconsistency we are accepting for now.
- **Reminder refresh on every load.** `load()` calls `reminders.refresh()` each time. Changing weeks quickly fires several refreshes. It's harmless today,
  but watch for it.
