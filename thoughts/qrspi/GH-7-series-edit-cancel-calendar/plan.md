# Implementation Plan — Series edit/cancel and shared calendar event (GH #7)

## Overview

From a series occurrence, Edit / Cancel / Delete offer **"This session only"** or **"This
and following sessions"**. One-session edits detach the occurrence from the series (own
standalone calendar event); cancel/delete remove just that date from the recurring event;
"following" ends the old recurring event before the date and, for edits, starts a new
series segment with its own recurring event. No schema or archive change.

Conventions: `S/` = `Sources/`, `T/` = `Tests/`. Swift 6 strict concurrency, iOS 26,
SwiftUI, SwiftData, XcodeGen, Swift Testing. Base: `main` at `origin/main` 01ddbaf + the
#38 backlog commit. Every phase ends green on:

```bash
xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5
```

New files under `S/` and `T/` are picked up by `project.yml`; `TrainMe.xcodeproj` is
generated and gitignored, so never edit it by hand. If `xcodegen` is missing, stop and ask
the user to install it (`brew install xcodegen`).

Device build/install (madphone, UDID `00008140-001E31AE21DB001C`):

```bash
xcodebuild -project TrainMe.xcodeproj -scheme TrainMe -configuration Debug -destination 'id=00008140-001E31AE21DB001C' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008140-001E31AE21DB001C build/DerivedData/Build/Products/Debug-iphoneos/TrainMe.app
xcrun devicectl device process launch --device 00008140-001E31AE21DB001C com.madacgrav.trainme
```

Baseline: `grep -r "@Test" Tests | wc -l` → 115. `T/Fixtures/export-v1.json`,
`S/Persistence/SchemaV1.swift`, `SchemaV2.swift`, `S/Services/Archive/ArchiveV1.swift`
stay untouched.

Shared invariant (design decision 6): **a row that still has a `seriesId` is never edited
in place**, so its `startAt` is the occurrence's original date in the recurring event.
Every single-occurrence edit detaches first.

---

## Phase 1: "This session only" cancel/delete clean up the calendar

### Changes

#### 1. Occurrence lookup in the calendar service
**File**: `S/Services/CalendarService.swift` — **modify**

Add a pure picker next to `makeEKRecurrenceRule` (unit-testable without a store):

```swift
/// Picks the occurrence of a recurring event whose original date matches
/// `target`. EventKit keeps `occurrenceDate` at the original start even after an
/// occurrence is moved, so this is stable for detached occurrences. Tolerates a
/// one-hour skew (DST); prefers the closest. Pure for testing.
func pickOccurrence(
    _ candidates: [(eventIdentifier: String?, occurrenceDate: Date?)],
    eventIdentifier: String,
    target: Date
) -> Int? {
    candidates.indices
        .filter { candidates[$0].eventIdentifier == eventIdentifier }
        .compactMap { i in candidates[i].occurrenceDate.map { (i, abs($0.timeIntervalSince(target))) } }
        .filter { $0.1 <= 3600 }
        .min { $0.1 < $1.1 }?.0
}
```

Extend the protocol:

```swift
protocol CalendarSyncing: Sendable {
    // …existing…
    /// Removes one occurrence of a recurring event (EKSpan.thisEvent). No-op
    /// when the event or occurrence is gone.
    func removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws
}
```

Implement in `EventKitCalendarService`:

```swift
func removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws {
    guard let event = occurrence(eventIdentifier, at: occurrenceStart) else { return }
    try store.remove(event, span: .thisEvent, commit: true)
}

/// Searches ±1 day around the date; `event(withIdentifier:)` would return the
/// first occurrence of a recurring event, not this one.
private func occurrence(_ eventIdentifier: String, at start: Date) -> EKEvent? {
    let window = store.predicateForEvents(
        withStart: start.addingTimeInterval(-86_400),
        end: start.addingTimeInterval(86_400),
        calendars: nil
    )
    let events = store.events(matching: window)
    let pick = pickOccurrence(
        events.map { ($0.eventIdentifier, $0.occurrenceDate) },
        eventIdentifier: eventIdentifier, target: start
    )
    return pick.map { events[$0] }
}
```

(No auth guard, matching `remove` at `CS:108-111`: without access `events(matching:)`
returns nothing and this is a no-op.)

#### 2. `SeriesActions` orchestrator
**File**: `S/Features/Session/SeriesActions.swift` — **create**

```swift
import Foundation

/// Which sessions a series action applies to.
enum SeriesScope: Sendable { case thisOnly, following }

/// Calendar side-effect summary; the store change has already happened.
struct SeriesOutcome: Equatable, Sendable {
    var calendarWarning: String?
}

/// Orchestrates store + calendar changes for sessions in a recurring series.
/// Store first, then calendar; calendar failures become a warning and never
/// undo the store change (same contract as `resolveEventIdentifier`).
struct SeriesActions: Sendable {
    let sessionRepo: any SessionRepository
    let calendar: any CalendarSyncing

    static let removeWarning = "Saved, but the calendar event couldn't be removed."

    func cancelOccurrence(_ session: SessionDTO) async throws -> SeriesOutcome {
        try await sessionRepo.setStatus(id: session.id, .cancelled)
        return await removeFromEvent(session)
    }

    func deleteOccurrence(_ session: SessionDTO) async throws -> SeriesOutcome {
        try await sessionRepo.delete(id: session.id)
        return await removeFromEvent(session)
    }

    /// Takes one date out of the shared recurring event. The row keeps its
    /// identifier (other occurrences still point at the same event).
    private func removeFromEvent(_ session: SessionDTO) async -> SeriesOutcome {
        guard let eventId = session.eventIdentifier else { return SeriesOutcome() }
        do {
            try await calendar.removeOccurrence(eventIdentifier: eventId, occurrenceStart: session.startAt)
            return SeriesOutcome()
        } catch {
            Log.calendar.error("removeOccurrence failed: \(error.localizedDescription)")
            return SeriesOutcome(calendarWarning: Self.removeWarning)
        }
    }
}
```

`Log.calendar` is in `S/Support/Log.swift:8`.

#### 3. Route series cancel/delete through `SeriesActions`
**File**: `S/Features/Session/SessionRunViewModel.swift` — **modify**

- Add `var calendarWarning: String?` next to `errorMessage` (`:23`), and
  `private var series: SeriesActions { SeriesActions(sessionRepo: sessionRepo, calendar: calendar) }`.
- `delete()` (`:99-118`): keep the non-series path unchanged. Prepend a series branch:

```swift
func delete() async -> Bool {
    errorMessage = nil
    if session.seriesId != nil {
        do {
            calendarWarning = try await series.deleteOccurrence(session).calendarWarning
        } catch {
            Log.ui.error("delete session failed: \(error.localizedDescription)")
            errorMessage = "Couldn't delete the session. Please try again."
            return false
        }
        await onStatusChanged()
        return true
    }
    // existing non-series body, with the `session.seriesId == nil` condition at :101 dropped
    …
}
```

- `setStatus(_:)` (`:205-228`): for `status == .cancelled && session.seriesId != nil` call
  `series.cancelOccurrence(session)` instead of `sessionRepo.setStatus`, set
  `calendarWarning`, then `refreshSession()` + `onStatusChanged()`; on throw use the existing
  error message (`:210-212`). Drop `session.seriesId == nil` from the guard at `:217` (that
  branch now only sees non-series rows). Completed/no-show unchanged.
- Update the `canEdit` doc comment (`:44-45`) to "editing a series occurrence arrives in
  Phase 2" — leave `canEdit` itself as is for this phase.

#### 4. Surface the warning and fix delete copy
**File**: `S/Features/Session/SessionRunView.swift` — **modify**

- The "Calendar" alert (`:132-139`) currently binds the view's `calendarWarning`. Also
  show `viewModel.calendarWarning`: change the binding's getter to
  `calendarWarning ?? viewModel.calendarWarning` and the setter/OK to clear both.
- Delete alert message (`:150-152`) series text →
  `"Only this occurrence is deleted and removed from your calendar; the rest of the series stays."`
- A successful delete dismisses the screen, which would hide a calendar warning. Add
  `@State private var dismissAfterWarning = false` and:

```swift
Button("Delete", role: .destructive) {
    Task {
        guard await viewModel.delete() else { return }
        if viewModel.calendarWarning == nil { dismiss() } else { dismissAfterWarning = true }
    }
}
```
  The Calendar alert's OK clears both warnings and calls `dismiss()` when
  `dismissAfterWarning` is set.

#### 5. Tests
**File**: `T/SessionRunViewModelTests.swift` — **modify**

- `FakeCalendar`: add `private(set) var removedOccurrences: [String] = []` and

```swift
func removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws {
    if let removeError { throw removeError }
    removedOccurrences.append("\(eventIdentifier)@\(occurrenceStart.timeIntervalSince1970)")
}
```
  Strings keep the actor's state `Sendable`/`Equatable` without a new struct. Add a helper
  `static func key(_ id: String, _ date: Date) -> String` used by both the fake and the tests.

**File**: `T/SeriesActionsTests.swift` — **create** (`@MainActor` where a VM is used)

Helper `makeSeries(weeks: Int, eventId: String?) async throws -> (SwiftDataSessionRepository, ScheduledSeries, [SessionDTO])`:
in-memory container (`PersistenceController.makeContainer(inMemory: true)`), a weekly
`AppRecurrence` on today's weekday, `scheduleSeries(… horizonWeeks: weeks)`, then
`setEventIdentifierForSeries(seriesId, eventId)` when non-nil, then `sessions(from:to:)` sorted.

Tests:
- `cancelOccurrenceCancelsOneAndRemovesThatDate` — 3 weeks, `evt-s`; cancel week 2 via VM
  with a series session → week 2 `.cancelled`, weeks 1/3 `.scheduled`, all still `evt-s`,
  `removedOccurrences == [key("evt-s", week2.startAt)]`, `removed.isEmpty`.
- `deleteOccurrenceDeletesOneAndRemovesThatDate` — same for delete; row gone.
- `seriesWithoutEventMakesNoCalendarCalls` — `eventId: nil`; cancel + delete → both fake
  arrays empty, `calendarWarning == nil`.
- `calendarFailureWarnsButKeepsStoreChange` — `configure(removeError: Boom())`; cancel →
  status cancelled, `vm.calendarWarning == SeriesActions.removeWarning`.
- `pickOccurrenceMatchesIdAndClosestDate` — pure: candidates with other ids, nil dates,
  +30 min, +2 h; picks the +30 min index; nothing within 1 h → nil.

### Verification
#### Automated
- [x] Test command passes; `grep -r "@Test" Tests | wc -l` ≥ 120. (120 tests passed.)
- [x] ~~`grep -n "seriesId == nil" … ` shows only `canEdit`~~ — **deviation**: the cancel-cleanup
      guard keeps `session.seriesId == nil`. Series rows still reach that branch after
      `cancelOccurrence`, and dropping the guard would remove the whole recurring event.
      `seriesId == nil` now appears in `canEdit` and that guard only.

#### Manual (device spike — gate for the rest of the plan)
- [x] Build/install on madphone. Create a 3-week weekly series with "Add to iPhone calendar".
- [x] Cancel week 2 in the app → iPhone Calendar shows weeks 1 and 3 only.
- [x] Delete week 3 in the app → Calendar shows week 1 only; app keeps week 1 scheduled, week 2 cancelled.
- [x] Turn off calendar access in Settings, cancel an occurrence → no crash, no warning (no-op).
- [x] **If occurrence lookup fails on device, stop and revisit design decision 6 before Phase 2.** — Passed on madphone (user confirmed 2026-11-01).

---

## Phase 2: Edit "this session only" by detaching

### Changes

#### 1. Repository: detach
**File**: `S/Persistence/SessionRepository.swift` — **modify**

Protocol (after `setEventIdentifierForSeries`, `:29`):

```swift
/// Takes one session out of its series: clears `seriesId` and the shared
/// event identifier (the caller pushes a standalone event). Keeps
/// `recurrenceData` as history; nothing reads it for a non-series row.
func detach(id: UUID) async throws
```

Implementation (next to `setEventIdentifier`, `:200-205`):

```swift
func detach(id: UUID) async throws {
    guard let session = try fetch(id: id) else { return }
    session.seriesId = nil
    session.eventIdentifier = nil
    session.updatedAt = .now
    try modelContext.save()
}
```

**File**: `T/SessionRunViewModelTests.swift` — `FailingSessionRepo` gains
`func detach(id: UUID) async throws { try await inner.detach(id: id) }`.

#### 2. `SeriesActions.detach`
**File**: `S/Features/Session/SeriesActions.swift` — **modify**

```swift
static let pushWarning = "Saved, but the calendar couldn't be updated."

/// Store first (detach), then calendar: drop the date from the shared event and
/// give the session its own event if the series had one. Returns the detached DTO.
func detach(_ session: SessionDTO, clientName: String) async throws -> (SessionDTO, SeriesOutcome) {
    try await sessionRepo.detach(id: session.id)
    var outcome = await removeFromEvent(session)
    if session.eventIdentifier != nil {
        var standalone = session
        standalone.seriesId = nil
        standalone.eventIdentifier = nil
        do {
            if let newId = try await calendar.push(standalone, clientName: clientName, recurrence: nil) {
                try await sessionRepo.setEventIdentifier(id: session.id, newId)
            }
        } catch {
            Log.calendar.error("standalone push failed: \(error.localizedDescription)")
            outcome.calendarWarning = outcome.calendarWarning ?? Self.pushWarning
        }
    }
    let refreshed = try await sessionRepo.get(id: session.id) ?? session
    return (refreshed, outcome)
}
```

(`push` returns nil without full access; the session then simply has no event, same as
a non-series session added without access.)

#### 3. Edit sheet detaches on save
**File**: `S/Features/Schedule/SessionEditView.swift` — **modify**

- In `save()` (`:165-171`), when `existing.seriesId != nil`, detach first, then run the
  normal edit against the detached copy:

```swift
if let existing {
    var base = existing
    if existing.seriesId != nil {
        let clientName = clients.first { $0.id == existing.clientId }?.name ?? "Client"
        do {
            let (detached, outcome) = try await SeriesActions(sessionRepo: sessionRepo, calendar: calendar)
                .detach(existing, clientName: clientName)
            base = detached
            calendarWarning = outcome.calendarWarning
        } catch {
            errorMessage = "Couldn't save the session. Please try again."
            return false
        }
    }
    return await saveEdit(of: base, clientId: clientId)
}
```

- `saveEdit` (`:249-288`) already updates `existing.eventIdentifier` when set, so the new
  standalone event gets the edited time. Keep a detach warning: in `saveEdit`, do not
  reset `calendarWarning` (it is reset once at the top of `save()`, `:168`); `apply`
  overwrites it only on a new failure, which is the more recent message.
- The `addToCalendar` toggle default (`:51`) is from `existing.eventIdentifier`, so a series
  with an event shows "Keep in iPhone calendar" on — correct for the detached event.

#### 4. Run screen: series is editable; series glyph
**File**: `S/Features/Session/SessionRunViewModel.swift` — **modify**
- Replace `canEdit` (`:44-46`) with `var isSeries: Bool { session.seriesId != nil }`; every
  session is now editable, so `canEdit` is deleted and its call sites updated.

**File**: `S/Features/Session/SessionRunView.swift` — **modify**
- Remove the footnote section (`:81-87`).
- Menu (`:109-117`): show "Edit session" unconditionally.
- Delete alert message (`:150-152`): `viewModel.isSeries ? <series copy> : <existing copy>`.
- Below the Time row (`:31` area), when `isSeries`: `Label("Repeats weekly", systemImage: "repeat")`
  in `.font(.caption)` / `.foregroundStyle(.secondary)`.

**File**: `S/Features/Schedule/ScheduleView.swift` — **modify** `SessionRow` (`:99-122`)

```swift
Spacer()
if session.seriesId != nil {
    Image(systemName: "repeat")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Repeating")
}
StatusChip(status: session.status)
```

Add a series row to `#Preview("Session row")` (`:135`):
`SessionRow(session: PreviewFixtures.seriesSession, clientName: "Sam Rivera")`.

**File**: `S/Support/PreviewFixtures.swift` — **modify**
```swift
static let seriesSession: SessionDTO = {
    var s = scheduledSession
    s.seriesId = UUID()
    s.recurrence = AppRecurrence(frequency: .weekly, interval: 1,
        weekdays: [Calendar.current.component(.weekday, from: s.startAt)], endDate: nil, occurrenceCount: nil)
    return s
}()
```
(`scheduledSession.id` is reused; preview-only, never inserted twice.)

#### 5. Tests
**File**: `T/SessionRepositoryTests.swift` — add `detachClearsSeriesAndEventOnlyForThatRow`:
series of 3 with `evt-s`; detach week 2 → week 2 `seriesId == nil`, `eventIdentifier == nil`,
`recurrence` unchanged; weeks 1/3 keep `seriesId` and `evt-s`.

**File**: `T/SeriesActionsTests.swift` — add:
- `detachPushesStandaloneAndRemovesOccurrence` — `configure(push: .success("evt-solo"))`;
  detach week 2 → one `removedOccurrences` for week 2, week 2 `eventIdentifier == "evt-solo"`,
  returned DTO has `seriesId == nil`.
- `detachWithoutSeriesEventMakesNoCalendarCalls` — `eventId: nil` → no removal; returned
  DTO `eventIdentifier == nil`.
- `detachPushFailureWarns` — `configure(push: .failure(Boom()))` → warning `pushWarning`,
  row detached, `eventIdentifier == nil`.
- In `T/SessionRunViewModelTests.swift`, `deleteRemovesCalendarEventAndSession` asserts
  `vm.canEdit` (`:77`) → change to `#expect(!vm.isSeries)`.

### Verification
#### Automated
- [x] Test command passes; `@Test` count ≥ 124. (124 passed.)
- [x] `grep -rn "canEdit\|isn't available yet" Sources` → no matches.

#### Manual
- [x] Xcode canvas: "Session row" preview shows the repeat glyph on the series row (light + dark).
- [x] Simulator: create a 3-week series, open week 2, Edit, move it 1 h later, Save → week 2
      row has no glyph and shows the new time; weeks 1/3 keep the glyph.
- [x] Device: same with calendar on → Calendar shows week 2 as its own event at the new
      time, the series no longer has week 2 at the old time, weeks 1/3 unchanged.

---

## Phase 3: Cancel/delete "this and following"

### Changes

#### 1. Repository: series reads and bulk writes
**File**: `S/Persistence/SessionRepository.swift` — **modify**

```swift
/// A series occurrence plus whether any sets were logged against it.
struct SeriesOccurrence: Sendable, Equatable {
    let session: SessionDTO
    let hasLoggedSets: Bool
}
```

Protocol:
```swift
/// Occurrences in the series starting at or after `from`, ascending.
func seriesOccurrences(seriesId: UUID, from: Date) async throws -> [SeriesOccurrence]
func setStatus(ids: [UUID], _ status: SessionStatus) async throws
/// Deletes each session and its set records (same rules as `delete(id:)`), one save.
func delete(ids: [UUID]) async throws
```

Implementation:

```swift
func seriesOccurrences(seriesId: UUID, from: Date) async throws -> [SeriesOccurrence] {
    let rows = try modelContext.fetch(FetchDescriptor<Session>(
        predicate: #Predicate { $0.seriesId == seriesId && $0.startAt >= from },
        sortBy: [SortDescriptor(\.startAt)]
    ))
    return try rows.map { row in
        let instanceIds = row.instances.map(\.id)
        let logged = instanceIds.isEmpty ? 0 : try modelContext.fetchCount(FetchDescriptor<SetRecord>(
            predicate: #Predicate { instanceIds.contains($0.workoutInstanceId) }
        ))
        return SeriesOccurrence(session: SessionDTO(row), hasLoggedSets: logged > 0)
    }
}

func setStatus(ids: [UUID], _ status: SessionStatus) async throws {
    for id in ids { if let s = try fetch(id: id) { s.statusRaw = status.rawValue; s.updatedAt = .now } }
    try modelContext.save()
}

func delete(ids: [UUID]) async throws {
    for id in ids {
        guard let session = try fetch(id: id) else { continue }
        let instanceIds = session.instances.map(\.id)
        if !instanceIds.isEmpty {
            try modelContext.delete(model: SetRecord.self, where: #Predicate { instanceIds.contains($0.workoutInstanceId) })
        }
        modelContext.delete(session)
    }
    try modelContext.save()
}
```

`FailingSessionRepo` gains three forwarders.

#### 2. Pure partition
**File**: `S/Features/Session/SeriesActions.swift` — **modify** (top level)

```swift
/// Splits "this and following" occurrences: `affected` are still scheduled with
/// no logged sets; `protected` are scheduled but already have sets. Completed,
/// cancelled and no-show occurrences are left out entirely.
func partitionFollowing(_ occurrences: [SeriesOccurrence]) -> (affected: [SessionDTO], protected: [SessionDTO]) {
    let scheduled = occurrences.filter { $0.session.status == .scheduled }
    return (scheduled.filter { !$0.hasLoggedSets }.map(\.session),
            scheduled.filter { $0.hasLoggedSets }.map(\.session))
}
```

#### 3. Calendar: end a recurring event before a date
**File**: `S/Services/CalendarService.swift` — **modify**

```swift
/// Ends a recurring event before the given occurrence (EKSpan.futureEvents on
/// that occurrence). On the first occurrence this removes the whole event.
func endSeries(eventIdentifier: String, before occurrenceStart: Date) async throws
```

```swift
func endSeries(eventIdentifier: String, before occurrenceStart: Date) async throws {
    guard let event = occurrence(eventIdentifier, at: occurrenceStart) else { return }
    try store.remove(event, span: .futureEvents, commit: true)
}
```

`FakeCalendar` records `endedSeries: [String]` using the same `key(_:_:)`.

#### 4. `SeriesActions` following operations
**File**: `S/Features/Session/SeriesActions.swift` — **modify**

```swift
struct FollowingResult: Equatable, Sendable {
    var changed: Int
    var outcome: SeriesOutcome
}

func cancelFollowing(from session: SessionDTO, clientName: String) async throws -> FollowingResult {
    try await following(from: session, clientName: clientName) { ids in
        try await sessionRepo.setStatus(ids: ids, .cancelled)
    }
}

func deleteFollowing(from session: SessionDTO, clientName: String) async throws -> FollowingResult {
    try await following(from: session, clientName: clientName) { ids in
        try await sessionRepo.delete(ids: ids)
    }
}

/// Store: apply `change` to affected rows, then detach protected rows (each
/// gets its own event). Calendar: end the old event at this occurrence. Ending
/// happens after protected pushes so a failed end leaves duplicates, not gaps.
private func following(
    from session: SessionDTO, clientName: String,
    change: ([UUID]) async throws -> Void
) async throws -> FollowingResult {
    guard let seriesId = session.seriesId else { return FollowingResult(changed: 0, outcome: SeriesOutcome()) }
    let (affected, protected) = partitionFollowing(
        try await sessionRepo.seriesOccurrences(seriesId: seriesId, from: session.startAt)
    )
    try await change(affected.map(\.id))
    var outcome = SeriesOutcome()
    for p in protected {
        let (_, o) = try await detachKeepingEvent(p, clientName: clientName)
        outcome.calendarWarning = outcome.calendarWarning ?? o.calendarWarning
    }
    if let eventId = session.eventIdentifier {
        do {
            try await calendar.endSeries(eventIdentifier: eventId, before: session.startAt)
        } catch {
            Log.calendar.error("endSeries failed: \(error.localizedDescription)")
            outcome.calendarWarning = outcome.calendarWarning ?? Self.removeWarning
        }
    }
    return FollowingResult(changed: affected.count, outcome: outcome)
}
```

`detachKeepingEvent` = `detach` minus the `removeFromEvent` step (the following
`endSeries` removes those dates anyway). Refactor `detach` into
`detach(_:clientName:removeOccurrence: Bool = true)` and call it with `false` here.

If `session` itself is protected (has sets) the loop detaches it too — expected: it keeps
its own event and the rest is cancelled/deleted.

#### 5. View model and scope dialog
**File**: `S/Features/Session/SessionRunViewModel.swift` — **modify**

```swift
func setStatus(_ status: SessionStatus, scope: SeriesScope = .thisOnly) async
func delete(scope: SeriesScope = .thisOnly) async -> Bool
```
- `scope == .following` (only reachable for series + cancel/delete): call
  `series.cancelFollowing` / `deleteFollowing` with `clientName`, set `calendarWarning`,
  then the same refresh / `onStatusChanged` path. Errors → existing messages.
- `.thisOnly` → Phase 1 behaviour.

**File**: `S/Features/Session/SessionRunView.swift` — **modify**

- New `@State private var scopePrompt: ScopePrompt?` with
  `enum ScopePrompt: Identifiable { case cancel, delete; var id: Self { self } }`.
- "Cancelled" button (`:72-73`) and the "Delete session" menu item (`:113`): if
  `viewModel.isSeries`, set `scopePrompt = .cancel` / `.delete`; else keep the current
  `pendingStatus` / `confirmingDelete` alerts.
- Add:

```swift
.confirmationDialog(
    scopePrompt == .delete ? "Delete repeating session" : "Cancel repeating session",
    isPresented: Binding(get: { scopePrompt != nil }, set: { if !$0 { scopePrompt = nil } }),
    titleVisibility: .visible,
    presenting: scopePrompt
) { prompt in
    Button("This session only", role: .destructive) { run(prompt, .thisOnly) }
    Button("This and following sessions", role: .destructive) { run(prompt, .following) }
    Button("Keep", role: .cancel) {}
} message: { prompt in
    Text(prompt == .delete
         ? "Logged sets are deleted with a session. Sessions that already have logged sets are kept and leave the series."
         : "Completed sessions and sessions with logged sets aren't changed.")
}
```
  with `run` calling `viewModel.setStatus(.cancelled, scope:)` or `viewModel.delete(scope:)`
  (dismiss on delete success as in Phase 1). No-show and completed stay this-only through
  the existing status alert.

#### 6. Tests
**File**: `T/SeriesActionsTests.swift` — add:
- `partitionSkipsNonScheduledAndProtectsLoggedSets` — pure: scheduled/no sets → affected;
  scheduled/sets → protected; completed/cancelled/noShow → neither.
- `cancelFollowingFromWeek2Of4` — `evt-s`; cancel following from week 2 → weeks 2–4
  `.cancelled`, week 1 `.scheduled`, `endedSeries == [key("evt-s", week2.startAt)]`, result
  `changed == 3`.
- `cancelFollowingDetachesProtectedOccurrence` — attach a workout (as
  `SessionRepositoryTests.swift:27`), `recordSet` on week 3's instance; cancel following
  from week 2 → week 3 still `.scheduled`, `seriesId == nil`, its own pushed id; weeks 2, 4 cancelled.
- `cancelFollowingLeavesCompletedAlone` — week 3 set `.completed` first → stays completed and in the series.
- `deleteFollowingFromFirstDeletesAllScheduled` — delete following from week 1 → all rows
  gone, one `endedSeries` for week 1.
- `followingWithoutEventMakesNoCalendarCalls`.

**File**: `T/SessionRepositoryTests.swift` — add `seriesOccurrencesReportsLoggedSets`,
`bulkSetStatusAndDelete` (sets of deleted rows are gone: `setsFor(instanceId:)` empty).

### Verification
#### Automated
- [x] Test command passes; `@Test` count ≥ 132. (132 passed.)

#### Manual
- [x] Simulator: 4-week series; on week 2 tap Cancelled → dialog shows both options;
      "This and following" → weeks 2–4 cancelled, week 1 scheduled.
- [x] Non-series session: Cancelled and Delete still show the original alerts.
- [x] Device: same with calendar on → Calendar keeps only week 1; delete following from
      week 1 of another series → whole event gone.

---

## Phase 4: Edit "this and following"

### Changes

#### 1. Pure segment helpers
**File**: `S/Features/Session/SeriesActions.swift` — **modify** (top level)

```swift
/// Moves a date to the given time of day (same calendar day), seconds zeroed.
func retime(_ date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
}

/// Weekly rule for a new segment: the old rule's weekdays (or the weekdays of
/// the affected dates when the stored rule is missing), ending on the last date.
func segmentRule(from old: AppRecurrence?, dates: [Date], calendar: Calendar = .current) -> AppRecurrence {
    let weekdays = old.map(\.weekdays).flatMap { $0.isEmpty ? nil : $0 }
        ?? Array(Set(dates.map { calendar.component(.weekday, from: $0) })).sorted()
    return AppRecurrence(frequency: .weekly, interval: max(1, old?.interval ?? 1),
                         weekdays: weekdays, endDate: dates.last, occurrenceCount: nil)
}

/// Dates the new recurring event would generate between the first and last
/// kept date that have no session (earlier cancellations, protected or deleted
/// occurrences). These are removed from the new event after it is created.
func gapDates(rule: AppRecurrence, keep: [Date]) -> [Date] {
    guard let first = keep.first, let last = keep.last else { return [] }
    let keepSet = Set(keep)
    return expandRecurrence(rule, from: first, to: last).filter { !keepSet.contains($0) }
}
```

`expandRecurrence` is at `SR:56-103` (top-level, internal).

#### 2. Repository: resegment
**File**: `S/Persistence/SessionRepository.swift` — **modify**

```swift
/// Moves the given series rows into a new series segment: new time of day and
/// duration on the same dates, notes, `seriesId`, rule; clears the event id. One save.
func resegment(
    ids: [UUID], newSeriesId: UUID, recurrence: AppRecurrence,
    hour: Int, minute: Int, duration: TimeInterval, notes: String?
) async throws
```

Implementation loops rows, sets `startAt = retime(row.startAt, hour:minute:)`,
`endAt = startAt + duration`, `notes`, `seriesId = newSeriesId`,
`recurrenceData = try? JSONEncoder().encode(recurrence)`, `eventIdentifier = nil`,
`updatedAt = .now`; one `save()`. `FailingSessionRepo` gains a forwarder.

#### 3. `SeriesActions.editFollowing`
**File**: `S/Features/Session/SeriesActions.swift` — **modify**

```swift
func editFollowing(
    from session: SessionDTO, hour: Int, minute: Int,
    duration: TimeInterval, notes: String?, clientName: String
) async throws -> FollowingResult {
    guard let seriesId = session.seriesId else { return FollowingResult(changed: 0, outcome: SeriesOutcome()) }
    let (affected, protected) = partitionFollowing(
        try await sessionRepo.seriesOccurrences(seriesId: seriesId, from: session.startAt)
    )
    var outcome = SeriesOutcome()
    for p in protected {
        let (_, o) = try await detach(p, clientName: clientName, removeOccurrence: false)
        outcome.calendarWarning = outcome.calendarWarning ?? o.calendarWarning
    }
    let newDates = affected.map { retime($0.startAt, hour: hour, minute: minute) }
    let rule = segmentRule(from: session.recurrence, dates: newDates)
    let newSeriesId = UUID()
    try await sessionRepo.resegment(
        ids: affected.map(\.id), newSeriesId: newSeriesId, recurrence: rule,
        hour: hour, minute: minute, duration: duration, notes: notes
    )
    guard let oldEventId = session.eventIdentifier else {
        return FollowingResult(changed: affected.count, outcome: outcome)
    }
    // Calendar: end old first so a failure leaves a gap the user can see, not duplicates.
    do {
        try await calendar.endSeries(eventIdentifier: oldEventId, before: session.startAt)
        if let first = affected.first, let firstDate = newDates.first {
            var anchor = first
            anchor.startAt = firstDate
            anchor.endAt = firstDate.addingTimeInterval(duration)
            anchor.notes = notes
            if let newId = try await calendar.push(anchor, clientName: clientName, recurrence: rule) {
                for gap in gapDates(rule: rule, keep: newDates) {
                    try await calendar.removeOccurrence(eventIdentifier: newId, occurrenceStart: gap)
                }
                try await sessionRepo.setEventIdentifierForSeries(newSeriesId, newId)
            }
        }
    } catch {
        Log.calendar.error("editFollowing calendar step failed: \(error.localizedDescription)")
        outcome.calendarWarning = outcome.calendarWarning ?? Self.pushWarning
    }
    return FollowingResult(changed: affected.count, outcome: outcome)
}
```

Protected rows are detached before `resegment` so their standalone events carry the
old time. The old event is ended **before** the new segment is pushed: if the push then
fails, the user sees missing sessions plus a warning, which is easier to fix than a
duplicate recurring series.

#### 4. Edit sheet: following mode
**File**: `S/Features/Schedule/SessionEditView.swift` — **modify**

- New init parameter `scope: SeriesScope? = nil` stored as `private let scope`.
  `private var editsFollowing: Bool { scope == .following && existing?.seriesId != nil }`.
- In the form: when `editsFollowing`, hide the Client section (`:68-75`) and the calendar
  toggle section (`:129-133`); in "When" (`:76-79`) use
  `DatePicker("Starts", selection: $startAt, displayedComponents: .hourAndMinute)` and add
  a footer `Text("Changes this session and the scheduled sessions after it.")`.
  Title: `"Edit Following Sessions"`.
- In `save()`, before the Phase 2 detach branch:

```swift
if let existing, editsFollowing {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: startAt)
    let clientName = clients.first { $0.id == existing.clientId }?.name ?? "Client"
    do {
        let result = try await SeriesActions(sessionRepo: sessionRepo, calendar: calendar).editFollowing(
            from: existing, hour: parts.hour ?? 9, minute: parts.minute ?? 0,
            duration: TimeInterval(durationMinutes * 60),
            notes: notes.isEmpty ? nil : notes, clientName: clientName
        )
        calendarWarning = result.outcome.calendarWarning
        return true
    } catch {
        errorMessage = "Couldn't save the sessions. Please try again."
        return false
    }
}
```
- Thread `scope` through: the Phase 2 detach branch applies when
  `existing.seriesId != nil && !editsFollowing`.

#### 5. Run screen: scope prompt for Edit
**File**: `S/Features/Session/SessionRunView.swift` — **modify**
- `ScopePrompt` gains `.edit`; "Edit session" sets `scopePrompt = .edit` when `isSeries`,
  else `showingEdit = true`.
- Add `@State private var editScope: SeriesScope?`; the dialog's buttons for `.edit` set
  `editScope` then `showingEdit = true`; title "Edit repeating session", no destructive
  roles, message "Changing the time for following sessions moves them to a new series."
- Pass `scope: editScope` into `SessionEditView` (`:120-131`); reset `editScope = nil` in
  `onSaved` and on sheet dismissal.
- After a following edit the current session may have moved; `reloadAfterEdit()` re-reads
  by id (`SRVM:90-93`), which still exists — no change needed.

#### 6. Tests
**File**: `T/SchedulingTests.swift` — add (use the `date(y,m,d,h)` helper at `:5`):
- `retimeKeepsDayChangesTime`.
- `segmentRuleUsesOldWeekdaysOrDerivesThem` — old rule [3,5] → [3,5]; nil rule with Tue/Thu
  dates → [3,5]; `endDate == last`.
- `gapDatesFindsMissingWeeks` — Tue/Thu rule, keep dates missing one Thursday → that Thursday.
- `gapDatesAcrossDSTBoundary` — keep dates spanning the US spring-forward Sunday (2027-03-14)
  at 07:00 → no gaps (expandRecurrence keeps wall-clock time).

**File**: `T/SeriesActionsTests.swift` — add:
- `editFollowingMovesRestToNewSegment` — 4 weeks at 07:00, `evt-s`, push → `evt-new`;
  edit following from week 2 to 08:30, 45 min, notes "x" → weeks 2–4 at 08:30, 45 min,
  notes "x", one shared new `seriesId` ≠ old, `eventIdentifier == "evt-new"`; week 1 at
  07:00 with old `seriesId` and `evt-s`; `endedSeries == [key("evt-s", oldWeek2)]`.
- `editFollowingRemovesGapsFromNewEvent` — cancel week 3 (this only) first; then edit
  following from week 2 → `removedOccurrences` contains `key("evt-new", week3 at 08:30)`.
- `editFollowingWithoutEventMakesNoCalendarCalls`.
- `editFollowingCalendarFailureWarns` — `configure(push: .failure(Boom()))` → store
  change kept, warning `pushWarning`.
- `FakeCalendar.push` now records `private(set) var pushedStarts: [Date]` and
  `pushedRecurrences: [AppRecurrence?]` (two arrays keep the actor state `Sendable`);
  `editFollowingMovesRestToNewSegment` asserts exactly one push with a non-nil recurrence
  whose `weekdays` equal the old rule's.

### Verification
#### Automated
- [x] Test command passes; `@Test` count ≥ 140. (140 passed.)

#### Manual
- [x] Simulator: 4-week series; on week 2 tap Edit → dialog; "This and following" → sheet
      shows time-only picker, no client/calendar sections; set 08:30 → weeks 2–4 at 08:30,
      week 1 unchanged.
- [x] Device: same with calendar on → Calendar shows week 1 at the old time and weeks 2–4
      at 08:30, no duplicates; with week 3 cancelled beforehand, week 3 does not appear.

---

## Phase 5: Device verification and docs

### Changes

#### 1. Full device pass
Build/install on madphone (commands in Overview). With calendar access on, create fresh
series for each row and record the result in this plan:

- [x] Edit, this only (Phase 2 checks).
- [x] Edit, following — including a series with an earlier cancelled week.
- [x] Cancel, this only / following.
- [x] Delete, this only / following (from first and from a middle week).
- [x] Series created **without** "Add to iPhone calendar": all six actions, Calendar untouched.
- [x] Protected occurrence: log one set on a future week, cancel following before it → that
      week stays scheduled, gets its own event.
- [x] Reminders: after cancel following, Settings → Notifications shows no pending
      alerts for cancelled weeks (or check that no "Session tomorrow" fires for them).
- [x] DST: only if a boundary falls inside a test series' range; otherwise note "not exercised".

#### 2. Docs
**File**: `BACKLOG.md` — **modify**
- Remove row 5 from "P1 — features"; add an "Addressed in [#PR]" block with a Done row:
  `| 5 | Series edit/cancel and shared calendar event update/removal | "This session only" / "This and following" for edit, cancel, delete; detach-and-split over one recurring event per segment; protected occurrences keep their own event | [#7](https://github.com/madacgrav/trainme/issues/7) |`
- Add a line under P2 or "Still worth a look" if the device pass finds EventKit caveats.

**File**: this `plan.md` — tick boxes, add a "Results" note per phase.

### Verification
#### Automated
- [x] Test command passes. (140 passed.)

#### Manual
- [x] Device checklist above complete with notes. — All passed on madphone (user confirmed 2026-11-01); DST not exercised (no boundary in the test series).
- [x] `BACKLOG.md`: row 5 gone from P1, present in Done (PR link to add when the PR is opened).
