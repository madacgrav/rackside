# Design Discussion — Series edit/cancel and shared calendar event (GH #7)

`SR` = `Sources/Persistence/SessionRepository.swift`, `SEV` =
`Sources/Features/Schedule/SessionEditView.swift`, `SRVM` =
`Sources/Features/Session/SessionRunViewModel.swift`, `CS` =
`Sources/Services/CalendarService.swift`.

## Current State
- A series is implicit: rows sharing `seriesId`, each with a copy of the rule in
  `recurrenceData` and the **same** `eventIdentifier` for one recurring EKEvent
  (`SR:113-149`, `SEV:203-225`, `SR:207-216`). No series entity, no series queries
  besides `setEventIdentifierForSeries`.
- Series occurrences cannot be edited (`SRVM:46` `canEdit`, `SessionRunView.swift:81-87`,
  `:91-93`). Cancel and delete work on the one row but **skip the calendar**
  (`SRVM:101`, `SRVM:217`), leaving the occurrence on the user's calendar. Delete of the
  row is allowed with the copy "Only this occurrence is deleted…" (`SessionRunView.swift:150-152`).
- `CalendarSyncing` (`CS:39-50`) only knows whole-event operations: `update` saves with
  `.thisEvent` on whatever `event(withIdentifier:)` returns (the series' first occurrence
  for a recurring event), and falls back to a non-recurring re-push (`CS:94-106`);
  `remove` uses `.futureEvents` (`CS:108-111`). Neither can target a specific occurrence.
- Reminders are derived: rebuilt from `upcoming` (scheduled only), keyed by session id
  (`NotificationService.swift:32`, `:41`), refreshed via `onStatusChanged` /
  `reloadAfterEdit` (`SRVM:90-93`, `:227`, `:116`). No series awareness needed.
- Edit orchestration lives inline in a View with no tests (`SEV:249-307`); status/delete
  orchestration is in the tested `SessionRunViewModel` with an injected `CalendarSyncing`.
- No test covers any series path (research Q7 "Not covered").

## Desired End State
From a series occurrence in `SessionRunView`, Edit, Cancel and Delete each ask
**"This session only" / "This and following sessions"** (Apple Calendar wording), and:

| Action | This session only | This and following |
|---|---|---|
| Edit (time, duration, notes; client only for "this") | Occurrence is **detached**: removed from the recurring event, gets its own standalone event, `seriesId` cleared, then the normal single edit runs | Affected occurrences get the new time/duration/notes and a **new `seriesId`**; old recurring event is **ended before** this date; one new recurring event covers the affected occurrences |
| Cancel | Status → cancelled; that occurrence removed from the recurring event; row keeps `seriesId` | All affected occurrences → cancelled; old recurring event ended before this date |
| Delete | Row deleted; that occurrence removed from the recurring event | Affected rows deleted; old recurring event ended before this date |

"Affected" = occurrences in the same series with `startAt >= this.startAt`, status
`.scheduled`, and no logged sets. Protected occurrences in that range (scheduled with
logged sets) are detached and given their own standalone event, so ending the recurring
event never strands them; non-scheduled ones are left as they are.

Reminders stay correct by the existing `onStatusChanged` → `refresh()` path. Calendar
failures stay non-blocking and surface through the existing `calendarWarning` alert.

**Verification**: unit tests (Swift Testing, in-memory container, extended
`FakeCalendar`) for every cell of the table plus the protected-occurrence rules; a
manual device check that the iPhone Calendar shows the expected occurrences after each
action (EventKit occurrence handling is not unit-testable).

## Patterns to Follow
- **Repository-as-actor + DTOs**: new series queries/mutations go on `SessionRepository`
  and `SwiftDataSessionRepository` with predicates on `seriesId` (as `SR:207-216`), one
  `modelContext.save()` per call (as `SR:147`).
- **Calendar outcome plumbing**: wrap calendar calls in `capturing` and turn results into
  user-visible warnings, never blocking the DB write (`EventIdentifierResolution.swift:17-59`,
  `SEV:292-307`). Reuse the "Saved, but …" message style.
- **Injected `CalendarSyncing` + `FakeCalendar`** (`Tests/SessionRunViewModelTests.swift:7-46`):
  extend the fake to record pushes (with recurrence), occurrence removals and series
  truncations instead of creating a second fake.
- **Pure, separately tested helpers** like `expandRecurrence` (`SR:56-103`) and
  `makeEKRecurrenceRule` (`CS:6-32`): put "which occurrences are affected / protected" and
  "which rule dates to exclude" into pure functions with direct tests.
- **Logging**: `Log.calendar.error` / `Log.ui.error` on failures (`SRVM:106`, `:210`).
- **Theme tokens and previews** from the UI refresh: `Theme.Colors` / `Theme.Spacing`
  (`Sources/Support/Theme.swift:6-34`), `.themedRows()` / `.themedScreen()`, a `#Preview`
  per screen backed by `PreviewFixtures` (`Sources/Support/PreviewFixtures.swift:33`,
  `:77`). Add a series fixture and a series variant to the "Session row" preview
  (`ScheduleView.swift:135`) rather than ad-hoc colours or untested visuals.
- **Confirmation alerts** in `SessionRunView` (`:140-179`) — extend them with the scope
  choice rather than adding a separate screen.
- **Do NOT follow**:
  - Orchestration inline in a View (`SEV:249-307`) — series logic goes in a testable
    type, and `SessionEditView` only collects fields + scope.
  - `update`'s silent non-recurring re-push (`CS:96-99`) — never call it with a series
    identifier.
  - Calendar-before-DB ordering in delete (`SRVM:101-110`) — new series paths write the DB
    first, then the calendar, matching edit and cancel.
  - Silent no-op on missing ids (`SR:183-238`) is fine for single rows, but bulk methods
    should return what they changed so the caller can drive the calendar.

## Design Decisions
1. **Scopes: this only + this and following** — matches EventKit's `.thisEvent` /
   `.futureEvents` and Apple Calendar; "all" is "following" from the first occurrence.
2. **Calendar strategy: detach and split, one recurring event per series segment** —
   no schema change, the user's calendar stays tidy, and detached sessions reuse the
   existing single-session paths unchanged (`canEdit`, `SEV` edit, `SRVM` cancel/delete).
3. **Edit fields for "following": time-of-day, duration, notes** — weekday or length
   changes are done by cancelling "following" and creating a new series. Client changes
   stay "this session only" (via detach).
4. **Protected occurrences**: bulk operations touch only `.scheduled` occurrences
   without logged sets; scheduled ones with sets in the range are detached with their
   own event; completed/cancelled/no-show are left alone.
5. **No schema or archive change**: everything uses existing `seriesId`,
   `recurrenceData`, `eventIdentifier`. A detached session has `seriesId = nil`, its own
   `eventIdentifier`, and keeps `recurrenceData` (unused once detached; it is never read
   to drive behaviour). New segments get a fresh `seriesId`, a rule copy with updated
   time, and the new event id. The live schema (`SchemaV2`, `Sources/Persistence/SchemaV2.swift:7-10`),
   the frozen `SchemaV1` copies, `ArchiveV1` and the v1 fixture are untouched — no SchemaV3.
6. **New `CalendarSyncing` operations keyed by occurrence date**:
   - `removeOccurrence(eventIdentifier:, occurrenceStart:)` — find the occurrence in a
     small window around the date (`predicateForEvents`), match `eventIdentifier` and
     `occurrenceDate`, remove with `.thisEvent`; not found → no-op.
   - `endSeries(eventIdentifier:, before occurrenceStart:)` — find that occurrence and
     remove with `.futureEvents` (EventKit truncates the rule; on the first occurrence
     this removes the whole event).
   - The occurrence's current `startAt` is its original date, because series rows are
     never edited in place — any single edit detaches first. This invariant is what makes
     date-based lookup reliable.
7. **New recurring segment**: push one recurring event anchored at the first affected
   occurrence with the old rule's weekdays at the new time and `endDate` = last affected
   occurrence; then `removeOccurrence` for every rule date in that span that has no
   affected row (cancelled, protected, deleted gaps). The gap list comes from a pure
   function using `expandRecurrence`.
8. **Orchestration lives in a new `SeriesActions` type** (MainActor-free, injected
   `SessionRepository` + `CalendarSyncing`), returning a result with an optional
   calendar warning. `SessionRunViewModel` calls it for series sessions;
   `SessionEditView` gains a `scope` input and calls it instead of `saveEdit` when the
   scope is "following" or when detaching.
9. **New repository surface** (names indicative): `seriesOccurrences(seriesId:, from:)`
   returning DTOs plus a has-logged-sets flag; `detach(id:)`; `reassignSeries(ids:,
   to: newSeriesId, recurrence:)`; bulk `update` / `setStatus` / `delete` over ids. Each
   is one save.
10. **UI**: series rows get a small repeat glyph in `SessionRow` (`ScheduleView.swift:99-122`,
    beside `StatusChip`, used by Schedule `:55` and client detail `ClientDetailView.swift:117`)
    so the scope dialog is not a surprise; `canEdit` becomes true for series;
    the "editing individual occurrences isn't available yet" footnote goes away.

## What We're NOT Doing
- "All sessions in series" scope that also rewrites past occurrences.
- Changing weekdays, interval, or series length of an existing series; daily or
  every-N-weeks UI (backlog row 12 / #14).
- Re-assigning a whole series to another client.
- Converting existing series to one-event-per-session, or rebuilding whole events.
- A new schema version (SchemaV3), archive changes, or fixture changes.
- Share sheet / .ics / Google Calendar API (decision #4), double-booking checks
  (decision #3).
- Re-linking calendar events the user moved or deleted in the Calendar app (not-found
  stays a no-op, as `CS:109`).
- Fixing the `ReminderCoordinator.refresh` "failed fetch clears all alerts" bug — a
  separate small fix.
- Tests for real EventKit (still on issue #28).

## Open Risks
- **EventKit occurrence semantics are unverified in this codebase** (research Open
  Areas): matching by `occurrenceDate`, `.futureEvents` truncation on a mid-series
  occurrence, and how detached occurrences edited by the user in Calendar behave. Plan a
  short device spike before building the UI.
- **Time zone / DST**: occurrence lookup by exact date must tolerate DST shifts — use a
  window plus `occurrenceDate` match, not exact `startDate` equality.
- **Series created without "Add to calendar"** have `eventIdentifier == nil`: all paths
  must skip calendar work cleanly, and new segments must not start creating events the
  user never asked for.
- **Partial failure**: DB succeeds and calendar fails midway (e.g. new segment pushed
  but old not ended). Calendar steps report a warning and are ordered so a retry is
  safe: end old series before pushing the new segment.
- **Legacy rows**: sessions with `seriesId` but missing or undecodable `recurrenceData`
  (`SessionDTO.swift:83` `try?`) — "following" edit needs the rule's weekdays; fall back
  to deriving weekdays from the affected rows' dates.
- `SessionEditView` grows a scope mode; keep its own logic thin or the untested-View
  problem gets worse.
