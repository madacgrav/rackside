# Structure Outline

## Approach
Detach-and-split on the existing shared recurring event: new occurrence-targeted
`CalendarSyncing` operations, series queries/mutations on `SessionRepository`, and a
testable `SeriesActions` orchestrator that `SessionRunViewModel` and `SessionEditView`
call. Each phase adds one user-visible capability end to end. No schema/archive change.

Test command (every phase):
```bash
xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -5
```

---

## Phase 1: "This session only" cancel/delete clean up the calendar
Fixes the bug in #7 directly: cancelling or deleting one series occurrence removes just
that date from the recurring event. Also establishes the occurrence lookup and the
`SeriesActions` type, and checks EventKit behaviour on a device early.

**Files**: `Sources/Services/CalendarService.swift`, `Sources/Features/Session/SeriesActions.swift`
(new), `Sources/Features/Session/SessionRunViewModel.swift`,
`Sources/Features/Session/SessionRunView.swift`, `Tests/SessionRunViewModelTests.swift`,
`Tests/SeriesActionsTests.swift` (new)

**Key changes**:
- `CalendarSyncing.removeOccurrence(eventIdentifier: String, occurrenceStart: Date) async throws` — new;
  EventKit impl searches a ±1 day window, matches `eventIdentifier` + `occurrenceDate`,
  removes with `.thisEvent`; not found → no-op.
- `struct SeriesActions { init(sessionRepo:, calendar:) }` with
  `func cancelOccurrence(_ s: SessionDTO) async throws -> SeriesOutcome` and
  `func deleteOccurrence(_ s: SessionDTO) async throws -> SeriesOutcome`.
- `struct SeriesOutcome: Equatable { var calendarWarning: String? }`.
- `SRVM.setStatus` / `delete`: series sessions route to `SeriesActions`; the
  `seriesId == nil` skips at `:101` / `:217` become "series → removeOccurrence". DB first,
  then calendar (also fixes delete ordering for series).
- `FakeCalendar` records `removedOccurrences: [(String, Date)]`.
- `SessionRunView`: delete alert copy says the occurrence is removed from the calendar.

**Verify**: tests pass; new tests: series cancel → status cancelled + one
`removedOccurrences` entry for its `startAt`; series delete → row gone + same; series
without `eventIdentifier` → no calendar call; calendar throw → warning, DB change kept.
**Device spike** (madphone): create a 3-week series with calendar on, cancel week 2 in
the app, confirm only that date disappears from iPhone Calendar; delete week 3, same.

---

## Phase 2: Edit "this session only" by detaching
Series occurrences become editable for one session: the occurrence leaves the series
and gets its own event, then the existing single edit runs.

**Files**: `Sources/Persistence/SessionRepository.swift`, `SeriesActions.swift`,
`SessionRunViewModel.swift`, `SessionRunView.swift`,
`Sources/Features/Schedule/SessionEditView.swift`, `Sources/Features/Schedule/ScheduleView.swift`,
`Sources/Support/PreviewFixtures.swift`, `Tests/SessionRepositoryTests.swift`,
`Tests/SeriesActionsTests.swift`

**Key changes**:
- `SessionRepository.detach(id: UUID) async throws` — clears `seriesId`, sets
  `eventIdentifier = nil`, one save.
- `SeriesActions.detach(_ s: SessionDTO, clientName: String) async throws -> (SessionDTO, SeriesOutcome)` —
  `removeOccurrence` on the old event, `push(recurrence: nil)` a standalone event if the
  series had one, `setEventIdentifier`; returns the refreshed DTO.
- `SRVM.canEdit` → always true; `SessionRunView` "Edit session" on a series first asks
  scope (only "This session only" enabled in this phase, or the dialog is introduced in
  Phase 3 — implementer's call), detaches, then opens `SessionEditView` with the detached DTO.
- Remove the "editing individual occurrences isn't available yet" footnote.
- `SessionRow` (`ScheduleView.swift:99-122`, used by Schedule and client detail) shows a
  repeat glyph beside `StatusChip` when `seriesId != nil`; add a series fixture to
  `PreviewFixtures` and a series row to the "Session row" preview.

**Verify**: tests pass; new tests: detach clears `seriesId`, pushes one standalone event,
removes one occurrence, stores the new id; series without calendar → no calendar calls;
other occurrences keep `seriesId` and old id. Manual: on simulator, edit week 2's time,
confirm the row loses the glyph and the change sticks; on device, the calendar shows the
moved session as its own event.

---

## Phase 3: Cancel/delete "this and following"
Bulk actions on the rest of a series, with the old recurring event ended before the date.

**Files**: `SessionRepository.swift`, `CalendarService.swift`, `SeriesActions.swift`,
`SessionRunViewModel.swift`, `SessionRunView.swift`, tests as above.

**Key changes**:
- `struct SeriesOccurrence: Sendable, Equatable { let session: SessionDTO; let hasLoggedSets: Bool }`.
- `SessionRepository.seriesOccurrences(seriesId: UUID, from: Date) async throws -> [SeriesOccurrence]` (ascending).
- `SessionRepository.setStatus(ids: [UUID], _ status: SessionStatus)` and `delete(ids: [UUID])` — bulk, one save each.
- Pure `func partitionFollowing(_ occ: [SeriesOccurrence]) -> (affected: [SessionDTO], protected: [SessionDTO])`
  — affected = scheduled without sets; protected = scheduled with sets; others ignored.
- `CalendarSyncing.endSeries(eventIdentifier: String, before occurrenceStart: Date) async throws` —
  finds the occurrence, removes with `.futureEvents`.
- `SeriesActions.cancelFollowing(from:)` / `deleteFollowing(from:)` → DB bulk op, detach
  each protected occurrence (Phase 2 path), then `endSeries`. Returns count + warning.
- `enum SeriesScope { case thisOnly, following }`; `SessionRunView` shows a
  confirmationDialog with both scopes for series cancel and delete (completed and no-show
  stay this-only, no calendar change); `SRVM.setStatus(_:scope:)`, `delete(scope:)`.

**Verify**: tests pass; new tests: partition rules (completed/cancelled ignored, sets →
protected); cancelFollowing from week 2 of 4 cancels 2–4, leaves week 1, calls
`endSeries` once with week 2's date; protected week 3 is detached with its own push;
deleteFollowing from week 1 deletes all scheduled rows. Device: cancel following from
week 2; Calendar keeps only week 1.

---

## Phase 4: Edit "this and following"
New time/duration/notes for the rest of a series as a new segment with its own
recurring event.

**Files**: `SessionRepository.swift`, `SeriesActions.swift`, `SessionEditView.swift`,
`SessionRunView.swift`, `Tests/SeriesActionsTests.swift`, `Tests/SchedulingTests.swift`.

**Key changes**:
- `SessionRepository.resegment(ids: [UUID], newSeriesId: UUID, recurrence: AppRecurrence, shiftTo time: DateComponents, duration: TimeInterval, notes: String?) async throws`
  — updates start/end/notes, `seriesId`, `recurrenceData`, clears `eventIdentifier`; one save.
- Pure `func segmentRule(from old: AppRecurrence?, affected: [Date]) -> AppRecurrence`
  (weekdays from the old rule, or derived from dates if the rule is missing; `endDate` =
  last affected) and `func gapDates(rule:, anchor:, keep: [Date]) -> [Date]` built on
  `expandRecurrence`.
- `SeriesActions.editFollowing(from:, time:, duration:, notes:, clientName:)` → partition,
  detach protected, resegment, `endSeries` on old event, `push(anchor, recurrence:)` the new
  segment, `removeOccurrence` for each gap, `setEventIdentifierForSeries(newId, …)`.
- `SessionEditView` gains `scope: SeriesScope?`; in `.following` it hides the client
  picker and calls `SeriesActions.editFollowing` instead of `saveEdit`.

**Verify**: tests pass; new tests: segment rule and gap dates (incl. a cancelled week in
the middle, DST week); editFollowing moves weeks 2–4 to the new time with one new
`seriesId`, week 1 untouched, one `endSeries`, one push with recurrence, one
`removeOccurrence` per gap. Device: move weeks 2–4 by an hour; Calendar shows week 1 at
the old time, weeks 2–4 at the new time, no duplicates.

---

## Phase 5: Device verification and docs
Full manual pass on madphone across all six cells of the design table, including a
series created without calendar, and DST if a boundary is in range. Update
`BACKLOG.md` (row 5 → Done), the plan with results, and link the PR.

**Verify**: checklist in plan.md ticked with notes; screenshots optional.

## Testing Checkpoints
- **After 1**: series cancel/delete (this only) remove exactly one calendar occurrence;
  device spike confirms `occurrenceDate` lookup. If the spike fails, stop and revisit
  design decision 6.
- **After 2**: any series occurrence can be edited alone; it becomes a standalone session
  with its own event; series rows show a repeat glyph.
- **After 3**: scope dialog for cancel/delete; "following" ends the old event and
  respects protected/ignored occurrences.
- **After 4**: "following" edit creates a new segment; calendar has no duplicates or
  phantom gap dates.
- **After 5**: device checklist done; BACKLOG and issue #7 updated.
