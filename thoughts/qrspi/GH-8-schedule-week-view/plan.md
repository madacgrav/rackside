# Implementation Plan — Week view on Schedule (GH #8)

## Overview

The Schedule tab gets a segmented **Day | Week** toggle.
- **Day** is today's screen, unchanged.
- **Week** shows a `‹ title › Today` header and one `List` with a section for each of the 7 days in the
  locale-aware week that contains `selectedDate`. Each session is a `SessionRow` that taps through to
  `SessionRunView`, and empty days show "No sessions".
- The mode persists across launches.
- No repository or schema change.

**Conventions.** `S/` = `Sources/`, `T/` = `Tests/`. Swift 6 strict concurrency, iOS 26, SwiftUI, SwiftData,
XcodeGen, Swift Testing. Base: `main` at 7f5255d. Every phase ends green on:

```bash
xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5
```

**Project files.** `project.yml` picks up new files under `S/` and `T/`. `TrainMe.xcodeproj` is generated and gitignored, so
never edit it by hand. If `xcodegen` is missing, stop and ask the user to install it (`brew install xcodegen`).

**Device build and install** (madphone, UDID `00008140-001E31AE21DB001C`):

```bash
xcodebuild -project TrainMe.xcodeproj -scheme TrainMe -configuration Debug -destination 'id=00008140-001E31AE21DB001C' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008140-001E31AE21DB001C build/DerivedData/Build/Products/Debug-iphoneos/TrainMe.app
xcrun devicectl device process launch --device 00008140-001E31AE21DB001C com.madacgrav.trainme
```

**Baseline.** `grep -r "@Test" Tests | wc -l` gives 140.

**Untouched.** `S/Persistence/SessionRepository.swift`, the schema files and `S/RootView.swift` do not change. `RootView`
keeps compiling because every new init parameter has a default.

**Rules for all phases:**
- All week math uses the **injected** `calendar`. Use `dateInterval(of: .weekOfYear)` for bounds and
  `date(byAdding: .day)` for stepping, never `86_400`.
- Do not copy `firstWeekday = 1` or the English `["Sun"...]` array (design "Do not follow").

---

## Phase 1: Week mode shows the selected week

### Changes

#### 1. Week types and pure helpers
**File**: `S/Features/Schedule/ScheduleWeek.swift`
**Action**: create

```swift
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
}
```

`ScheduleDay: Equatable` needs `SessionDTO: Equatable`. Check this. If `SessionDTO` is not `Equatable`, drop
`Equatable` from `ScheduleDay`, because tests compare dates and ids, not whole days.

#### 2. View model: calendar injection, mode, week load
**File**: `S/Features/Schedule/ScheduleViewModel.swift`
**Action**: modify

- **New stored property:** `private let calendar: Calendar`.
- **New state, next to `sessionsForDay`:**
  ```swift
  var mode: ScheduleMode = .day
  var week: [ScheduleDay] = []
  var weekInterval: DateInterval { ScheduleWeek.weekInterval(containing: selectedDate, calendar: calendar) }
  ```
- **Init:** add `calendar: Calendar = .current` as the last parameter after `defaults`, and assign `self.calendar = calendar`.
- **`load()`:** replace the day-range lines (`:45-48`) with:

```swift
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
```

The client maps, `reminders.refresh()` and `refreshExportReminder()` stay as they are. Load errors are still swallowed
(design decision 9).

#### 3. View: toggle, shared row link, week list
**File**: `S/Features/Schedule/ScheduleView.swift`
**Action**: modify

- **Toggle.** Directly after the export banner `if` block, inside the `VStack`, add:
  ```swift
  Picker("View", selection: $viewModel.mode) {
      ForEach(ScheduleMode.allCases) { Text($0.title).tag($0) }
  }
  .pickerStyle(.segmented)
  .padding(.horizontal)
  .padding(.vertical, Theme.Spacing.sm)
  ```
- **Mode switch.** Wrap the existing `DatePicker` and `List(viewModel.sessionsForDay)` (with its `.overlay` and `.themedScreen()`)
  in a `switch viewModel.mode { case .day: ... case .week: weekList }`. The Day branch stays as it is,
  except that the row body becomes `sessionLink(session)`.
- **Shared row link.** Move the `NavigationLink { SessionRunView(...) } label: { SessionRow(...) }.themedRows()` body out of the
  day list into a shared helper:

```swift
private func sessionLink(_ session: SessionDTO) -> some View {
    NavigationLink {
        SessionRunView(viewModel: SessionRunViewModel(
            sessionRepo: viewModel.sessionRepo,
            exerciseRepo: viewModel.exerciseRepo,
            clientRepo: viewModel.clientRepo,
            session: session,
            clientName: viewModel.clientNames[session.clientId] ?? "Client",
            clientPhone: viewModel.clientPhones[session.clientId],
            clientInjuries: viewModel.clientInjuries[session.clientId] ?? nil,
            onStatusChanged: { await viewModel.load() }
        ), workoutRepo: viewModel.workoutRepo)
    } label: {
        SessionRow(session: session, clientName: viewModel.clientNames[session.clientId] ?? "Client")
    }
    .themedRows()
}

private var weekList: some View {
    List {
        ForEach(viewModel.week) { day in
            Section(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) {
                if day.sessions.isEmpty {
                    Text("No sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themedRows()
                } else {
                    ForEach(day.sessions) { sessionLink($0) }
                }
            }
        }
    }
    .overlay {
        if viewModel.isLoading && viewModel.week.isEmpty { ProgressView() }
    }
    .themedScreen()
}
```

- **Reload on mode change.** Next to the existing `.onChange(of: viewModel.selectedDate)`, add:
  ```swift
  .onChange(of: viewModel.mode) { Task { await viewModel.load() } }
  ```
- **Unchanged:** the toolbar Add button, the sheet (`initialDate: viewModel.selectedDate`) and the calendar alert. In Week mode, Add
  still uses `selectedDate`.

#### 4. Tests
**File**: `T/ScheduleViewModelTests.swift`
**Action**: create

Shared helpers, which also live in this file:

```swift
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
```

`FakeNotifications` is the internal actor in `T/ReminderCoordinatorTests.swift:6`. Reuse it rather than redefining it.

Tests. Wednesday 2026-11-04 is the reference day, and Sunday 2026-11-01 is the DST change.
- `weekIntervalSundayFirst`: with `calendar(firstWeekday: 1)`, the interval runs from 11-01 00:00 to 11-08 00:00.
- `weekIntervalMondayFirst`: with `calendar(firstWeekday: 2)`, the interval runs from 11-02 00:00 to 11-09 00:00.
- `daysAcrossDSTGivesSevenMidnights`: in the Sunday-first week, `days` has count 7, every element has hour 0, and
  `days[1] == date(cal, 2026, 11, 2)`. Also check that `interval.duration == 7 * 86_400 + 3600`, which proves the DST week is not 7 × 24 h.
- `groupBucketsByLocalDayAndKeepsEmptyDays`: sessions at 11-02 17:00, 11-02 07:00 (deliberately out of order), 11-04 09:00 and
  11-08 00:00 (the next week).
  - 7 days come back.
  - `days[1]` has 2 sessions, the 07:00 one first.
  - `days[3]` has 1.
  - The other days are empty.
  - The total is 3.
- `weekModeLoadsWholeWeek` (`@MainActor`):
  - Schedule the same four sessions with `try await sessions.schedule(dto, attaching: [])`.
  - Set `vm.selectedDate = date(cal, 2026, 11, 4, 12)` and `vm.mode = .week`, then call `await vm.load()`.
  - Expect `vm.week.count == 7` and `vm.week.flatMap(\.sessions).count == 3`.
- `dayModeStillLoadsOneDay` (`@MainActor`): with the same seed, `vm.selectedDate = 11-02 12:00` in mode `.day` gives
  `vm.sessionsForDay.count == 2`.

### Verification
#### Automated
- [x] The test command passes.
- [x] `grep -r "@Test" Tests | wc -l` gives 146 (140 + 6).
- [x] `grep -n "Calendar.current" Sources/Features/Schedule/ScheduleViewModel.swift` prints nothing.

#### Manual (iPhone 17 simulator)
- [ ] Schedule opens in Day mode looking as it does today, with the toggle above the month picker.
- [ ] Switching to Week shows 7 day sections for the selected date's week, with "No sessions" on empty days.
- [ ] Tapping a row opens the session. Marking it Cancelled and going back shows the Cancelled chip in the week list.
- [ ] Add in Week mode creates a session on `selectedDate`, and it appears in the week list.
- [ ] Picking a date in another week in Day mode and switching to Week shows that week.

---

## Phase 2: Move between weeks

### Changes

#### 1. Title helpers
**File**: `S/Features/Schedule/ScheduleWeek.swift`
**Action**: modify. Add to `enum ScheduleWeek`:

```swift
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
```

#### 2. View model navigation
**File**: `S/Features/Schedule/ScheduleViewModel.swift`
**Action**: modify

```swift
var weekTitle: String { ScheduleWeek.weekTitle(weekInterval, calendar: calendar) }

func showPreviousWeek() { moveWeek(by: -7) }
func showNextWeek() { moveWeek(by: 7) }
func showToday(now: Date = .now) { selectedDate = now }
func isShowingWeek(containing now: Date = .now) -> Bool { weekInterval.contains(now) }

private func moveWeek(by days: Int) {
    selectedDate = calendar.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
}
```

These need no explicit reload. The view's existing `.onChange(of: viewModel.selectedDate)` handles it.

#### 3. Week header
**File**: `S/Features/Schedule/ScheduleView.swift`
**Action**: modify. In the `.week` branch, put `weekHeader` above `weekList`:

```swift
private var weekHeader: some View {
    HStack(spacing: Theme.Spacing.sm) {
        IconButton(title: "Previous week", systemImage: "chevron.left") { viewModel.showPreviousWeek() }
        Text(viewModel.weekTitle)
            .font(Theme.Fonts.display())
            .frame(maxWidth: .infinity)
        IconButton(title: "Next week", systemImage: "chevron.right") { viewModel.showNextWeek() }
        Button("Today") { viewModel.showToday() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isShowingWeek())
    }
    .padding(.horizontal)
}
```

#### 4. Tests
**File**: `T/ScheduleViewModelTests.swift`
**Action**: modify. Add these tests, all `@MainActor` and Sunday-first unless noted:
- `nextWeekCrossesYear`: selected 2026-12-30 12:00, then `showNextWeek()`. Expect `selectedDate == 2027-01-06 12:00` and
  `weekInterval.start == 2027-01-03 00:00`.
- `previousWeekCrossesMonth`: selected 2026-11-04 12:00, then `showPreviousWeek()`. Expect `weekInterval.start == 2026-10-25 00:00`.
- `showTodayJumpsToWeekOfNow`: selected 2026-01-07, then `showToday(now: 2026-11-04 12:00)`. Expect
  `isShowingWeek(containing: 2026-11-04 12:00)` to be true and `weekInterval.start == 2026-11-01`.
- `lastDayIsInclusive`: for the week of 2026-11-04, `ScheduleWeek.lastDay(of:calendar:) == 2026-11-07 00:00`. This is a pure test with no
  view model.

### Verification
#### Automated
- [x] The test command passes.
- [x] `grep -r "@Test" Tests | wc -l` gives 150.

#### Manual
- [ ] In Week mode the header reads, for example, "Nov 1 – 7, 2026". The exact text depends on the locale.
- [ ] `‹` and `›` change the week and reload its sessions. Today is disabled on the current week and jumps back from other weeks.
- [ ] Moving 3 weeks ahead and switching to Day shows the same date selected in the month picker.
- [ ] VoiceOver reads "Previous week", "Next week" and "Today".

---

## Phase 3: Remember the mode, and add previews

### Changes

#### 1. Persist the mode
**File**: `S/Features/Schedule/ScheduleViewModel.swift`
**Action**: modify

```swift
private static let modeKey = "scheduleMode"

var mode: ScheduleMode = .day {
    didSet { defaults.set(mode.rawValue, forKey: Self.modeKey) }
}
```

At the end of `init`, after `self.defaults = defaults`, add:

```swift
mode = ScheduleMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .day
```

`didSet` runs here too, and writing back the same value is harmless.

#### 2. Week preview data
**File**: `S/Support/PreviewFixtures.swift`
**Action**: modify

- **`weekSessions`.** Add `static let weekSessions: [SessionDTO]`. Build it from
  `Calendar.current.dateInterval(of: .weekOfYear, for: .now)!.start`, copying `scheduledSession` with a new `id` and new
  `startAt`/`endAt` for each entry:
  - day +1 at 07:00, `.completed`
  - day +1 at 17:30, with `seriesId: UUID()` and the weekly `recurrence` from `seriesSession`
  - day +3 at 09:00, `.scheduled`
  - day +4 at 06:00, `.cancelled`
- **`repositories(seedingWeek:)`.** Change `repositories()` to `repositories(seedingWeek: Bool = false)` and `container()` to
  `container(seedingWeek: Bool = false)`. When the flag is true, `container` also inserts `weekSessions` with
  `ctx.insert($0.toModel())`. Existing callers keep the defaults, so other previews are unchanged.

#### 3. Week preview
**File**: `S/Features/Schedule/ScheduleView.swift`
**Action**: modify. Add:

```swift
#Preview("Schedule — Week") {
    let repos = PreviewFixtures.repositories(seedingWeek: true)
    let viewModel = ScheduleViewModel(
        sessionRepo: repos.sessions,
        clientRepo: repos.clients,
        workoutRepo: repos.workouts,
        exerciseRepo: repos.exercises,
        reminders: repos.reminders,
        defaults: UserDefaults(suiteName: "ScheduleWeekPreview")!
    )
    viewModel.mode = .week
    return ScheduleView(viewModel: viewModel)
}
```

#### 4. Tests
**File**: `T/ScheduleViewModelTests.swift`
**Action**: modify
- `modePersistsAcrossInstances`:
  - Build a view model with a fresh suite. Set `vm.mode = .week`.
  - Expect `defaults.string(forKey: "scheduleMode") == "week"`.
  - Build a second view model on the same suite and expect its `mode == .week`.
- `invalidStoredModeFallsBackToDay`: set `defaults.set("month", forKey: "scheduleMode")`, build a view model, and expect `mode == .day`.

### Verification
#### Automated
- [x] The test command passes.
- [x] `grep -r "@Test" Tests | wc -l` gives 152.

#### Manual
- [ ] The "Schedule — Week" preview renders, in light and dark, with filled days, empty days, a repeat icon, and Completed and Cancelled chips.
- [ ] The existing "Schedule" and other previews still render with only their old data.
- [ ] On the simulator: switch to Week, kill the app, and relaunch. It opens in Week mode.

---

## Phase 4: Device verification and docs

### Changes

#### 1. Backlog
**File**: `BACKLOG.md`
**Action**: modify
- Remove row 6 from the P1 table.
- Add an intro paragraph like the #39 one: "Week view on Schedule (row 6) was addressed in [#NN](...); see the
  [Done](#done) table and `thoughts/qrspi/GH-8-schedule-week-view/` for the design and plan."
- Add a Done table:

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 6 | Week view on Schedule | Day/Week segmented toggle; week of `selectedDate` (locale first weekday) as 7 day sections with `SessionRow`; chevrons + Today; mode persisted; `ScheduleViewModel` takes an injected `Calendar`; `ScheduleViewModelTests` | [#8](https://github.com/madacgrav/trainme/issues/8) |

Fill in the PR number when the PR exists (step 8-pr).

#### 2. Plan record
**File**: `thoughts/qrspi/GH-8-schedule-week-view/plan.md`
**Action**: modify. Append a "Device pass" section with the date and the results of the checklist below.

### Verification
#### Automated
- [x] The test command passes, and the test count is 152.
- [x] The device build, install and launch commands from the Overview succeed.

#### Manual (madphone)
- [x] The Day and Week toggle works, and both modes look right with the export banner showing and hidden, in light and dark.
- [x] Chevrons and Today work, and the week of 2026-11-01 (DST change) shows 7 days with sessions on the right days.
- [x] From the week list, open a series session, choose Cancel, then "This session only". On return, only that row shows Cancelled.
- [x] Add a session from Week mode, and it appears in the right section.
- [x] Relaunch the app, and it reopens in the last-used mode.

---

## Implementation notes (2026-11-01)

- Phases 1–3 landed one commit each. The simulator test run is green with 152 `@Test`s.
- Phase 3 deviation: `PreviewFixtures.weekSessions` gives every copied `WorkoutInstance` and `PlannedEntry`
  a fresh id, because those ids are `@Attribute(.unique)`. A straight copy of `scheduledSession` would have upserted
  one instance across all the sessions. Its values are captured before the nested builder, which is nonisolated
  under Swift 6.
- BACKLOG.md uses `#NN` placeholders for the PR number. Fill them in at step 8-pr.

## Device pass (2026-11-01)

- Built from branch `GH-8-schedule-week-view` with the device commands in the Overview, then installed and launched on madphone (iPhone 16 Pro Max).
- The user ran the Phase 4 checklist on the device and reported every item passing: Day/Week toggle, chevrons and Today, the 2026-11-01 DST week,
  series cancel "This session only" from the week list, add from Week mode, and the mode persisting across relaunch.
