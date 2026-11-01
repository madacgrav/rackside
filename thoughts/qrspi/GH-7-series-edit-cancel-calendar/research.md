# Research Findings

Refreshed 2026-11-01 against `origin/main` @ 01ddbaf (after the UI refresh, PR #36). Q1, Q2 and Q4
cite files that did not change in that merge (`SessionRepository.swift`, `CalendarService.swift`,
`EventIdentifierResolution.swift`) except `SessionEditView.swift`, whose references were re-checked.

Paths are relative to the repo root. `SR` = `Sources/Persistence/SessionRepository.swift`,
`SEV` = `Sources/Features/Schedule/SessionEditView.swift`, `SRVM` =
`Sources/Features/Session/SessionRunViewModel.swift`, `CS` =
`Sources/Services/CalendarService.swift`.

## Q1: How is a recurring series created end to end?

### Findings
- **No view model**: `SessionEditView` holds the create/edit logic itself; it takes
  `sessionRepo`, `clientRepo`, `workoutRepo`, `calendar: any CalendarSyncing`
  (default `EventKitCalendarService()`) and `existing: SessionDTO?` (`SEV:31-39`).
- Form state for series: `repeats = false`, `repeatWeekdays: Set<Int>`, `repeatWeeks = 8`,
  `addToCalendar = false` (`SEV:18-21`). The Repeat section is shown only when
  `!isEditing` (`SEV:80`, section `SEV:103-123`): toggle "Repeats weekly" (`:104`),
  Sun…Sat weekday buttons 1…7 (`:63`, `:107-119`), `Stepper("For N weeks", in: 1...26)` (`:121`).
- `save()` (`SEV:165-246`) routes to `saveEdit` when `existing != nil` (`:169-171`).
  Otherwise it builds a base DTO: new UUID, picker `startAt`, `endAt = startAt + duration`,
  `.scheduled`, notes, `seriesId/recurrence/eventIdentifier = nil` (`SEV:172-185`).
- Rule built in the UI is always `AppRecurrence(frequency: .weekly, interval: 1,
  weekdays: repeatWeekdays.sorted(), endDate: nil, occurrenceCount: nil)` (`SEV:189-195`).
  The UI never sets daily frequency, interval ≠ 1, end date, or count.
- Call: `sessionRepo.scheduleSeries(dto, recurrence: rule, attaching: workoutIds,
  horizonWeeks: repeatWeeks)` (`SEV:198`); failure → "Couldn't schedule the session…"
  and `save()` returns false (`SEV:200-201`).
- **`AppRecurrence`** (`Sources/Models/Session.swift:10-20`): `Codable, Sendable, Equatable`
  struct; `Frequency { daily, weekly }` (`:11-13`), `interval`, `weekdays: [Int]`
  (EKWeekday numbering 1=Sun…7=Sat per comment `:8-9`), `endDate: Date?`,
  `occurrenceCount: Int?`. Not a SwiftData model.
- **`Session`** (`Session.swift:22-65`): `id`, `clientId`, `startAt`, `endAt`, `statusRaw`,
  `notes`, `instances` (cascade, `:30`), `seriesId: UUID?` (`:32`), `recurrenceData: Data?`
  (`:33`), `eventIdentifier: String?` (`:34`), `createdAt`, `updatedAt`.
  `SessionStatus` = scheduled/completed/cancelled/noShow (`:4-6`). There is no series
  entity — a series is the set of rows sharing `seriesId`.
- **`scheduleSeries`** (`SR:113-149`):
  - Default `horizonWeeks` 12 (`SR:117`); horizon = start + N weeks − 1 s, exclusive
    (`SR:121-123`; protocol doc `SR:9-12` "8 weeks of Tuesdays gives 8 sessions").
  - Dates from pure `expandRecurrence(recurrence, from:to:)` (`SR:124`).
  - One `seriesId = UUID()` (`SR:125`); `duration` from the base DTO (`SR:126`);
    `recurrenceData` JSON-encoded once (`SR:127`).
  - Per date: fresh `id`, same client/notes, `.scheduled`, shared `seriesId` and
    `recurrence`, `eventIdentifier: nil` (`SR:129-146`, `:140`); inserted via
    `insertSession` (`SR:144`), `recurrenceData` set on the model (`SR:145`); one
    `modelContext.save()` (`SR:147`).
  - Returns `ScheduledSeries(seriesId:, occurrences: [Date])` (`SR:45-49`, `:148`).
- `insertSession` (`SR:290-328`) deep-copies each attached workout template into a new
  `WorkoutInstance` + `PlannedEntry` rows per occurrence (`SR:308-325`).
- **`expandRecurrence`** (`SR:56-103`): `Calendar.current` with `firstWeekday = 1`;
  `maxCount = occurrenceCount ?? Int.max`; `end = min(endDate, horizon)`; start with
  seconds zeroed (`SR:57-68`). Daily steps `max(1, interval)` days (`SR:71-77`). Weekly
  walks from the start of the week containing `start`, steps `max(1, interval)` weeks,
  emits each weekday at start's hour/minute within `[start, end]`; empty weekdays → the
  start's weekday (`SR:78-100`).
- **Calendar step for a series** (`SEV:203-225`), only if `addToCalendar` and an
  occurrence exists:
  1. `calendar.requestAccess()` (`:204`).
  2. Anchor DTO with `startAt = series.occurrences.first` and same duration (`:212-214`);
     comment `:207-211` says this avoids a phantom EventKit entry on the picker weekday.
  3. `boundedRule.occurrenceCount = series.occurrences.count` (`:215-216`).
  4. One `calendar.push(anchor, clientName:, recurrence: boundedRule)` via `capturing`
     (`:217-219`) → `resolveEventIdentifier(existing: nil, …)` (`:222`) → `apply` with
     `sessionRepo.setEventIdentifierForSeries(series.seriesId, $0)` (`:223`).
  - Result: **every occurrence stores the same `eventIdentifier`** (the recurring event's).
  - Calendar failure never blocks the save; `save()` returns true (`SEV:245`).
- Single (non-series) add for comparison: `schedule` → `push(dto, recurrence: nil)` →
  `setEventIdentifier(id:)` (`SEV:226-244`).

## Q2: How does `EventKitCalendarService` / `CalendarSyncing` create, update, remove?

### Findings
- Protocol `CalendarSyncing: Sendable` (`CS:39-50`): `requestAccess() async -> Bool`,
  `authorizationStatus() async -> EKAuthorizationStatus`, `push(_ session: SessionDTO,
  clientName:, recurrence: AppRecurrence?) async throws -> String?` (`:44`),
  `update(eventIdentifier:, _ session:, clientName:) async throws -> String?` (`:48`),
  `remove(eventIdentifier:) async throws` (`:49`).
- Conformers: `actor EventKitCalendarService` (`CS:52`, private `EKEventStore()` `:53`) and
  test `actor FakeCalendar` (`Tests/SessionRunViewModelTests.swift:7-46`).
- **push** (`CS:79-92`): returns nil unless `.fullAccess` (`:80`); new `EKEvent`, title
  `"Training: \(clientName)"`, start/end/notes from DTO, `calendar = try writableCalendar()`
  (`:81-86`); if recurrence → `recurrenceRules = [makeEKRecurrenceRule(r)]` (`:87-89`);
  `store.save(event, span: .futureEvents, commit: true)` (`:90`); returns
  `event.eventIdentifier` (`:91`).
- **update** (`CS:94-106`): nil without full access (`:95`); if
  `store.event(withIdentifier:)` is nil → re-creates via `push(…, recurrence: nil)`
  (`:96-99`, so a re-created event has no recurrence); else rewrites title/start/end/notes
  and saves with `span: .thisEvent` (`:100-105`).
- **remove** (`CS:108-111`): no auth guard; missing event → silent return (`:109`);
  `store.remove(event, span: .futureEvents, commit: true)` (`:110`).
- **EKSpan usage, complete**: push `.futureEvents` (`:90`), update `.thisEvent` (`:104`),
  remove `.futureEvents` (`:110`). `store.event(withIdentifier:)` on a recurring event
  returns the series' first occurrence (EventKit behaviour; not exercised in tests).
- **Recurrence mapping** `makeEKRecurrenceRule` (`CS:6-32`, pure): `.daily/.weekly` →
  EK frequency (`:7-10`); empty weekdays → nil, else `EKRecurrenceDayOfWeek` via
  `EKWeekday(rawValue:)` with `compactMap` (`:11-13`); end = `occurrenceCount` first, else
  `endDate`, else nil (`:14-19`); `interval: max(1, interval)` (`:23`).
- **Authorization / calendar choice**: `requestAccess` → `requestFullAccessToEvents()`,
  errors logged and false (`CS:57-61`); `authorizationStatus` static (`:65`);
  `writableCalendar()` = `defaultCalendarForNewEvents` ?? first calendar with
  `allowsContentModifications` (logged) ?? throw `CalendarError.noWritableCalendar`
  (`CS:70-77`); `CalendarError` has one case (`CS:34-37`). Usage string
  `NSCalendarsFullAccessUsageDescription` (`Sources/Info.plist:27`).
- **Identifier storage**: `Session.eventIdentifier` (`Session.swift:34`),
  `SessionDTO.eventIdentifier` (`SessionDTO.swift:30`); setters `setEventIdentifier(id:_:)`
  (`SR:200-205`) and `setEventIdentifierForSeries(_:_:)` (`SR:207-216`).
- **Resolution** (`Sources/Features/Schedule/EventIdentifierResolution.swift`):
  `enum CalendarOutcome { unchanged, store(String?), failed(String) }` (`:4-11`);
  pure `resolveEventIdentifier(existing:wantsCalendar:hasAccess:result:)` (`:17-46`):
  - toggle off: no id/result → `.unchanged`; remove ok → `.store(nil)`; remove failed →
    `.failed("Saved, but the calendar event couldn't be removed.")` (`:23-30`).
  - toggle on, no access: no existing id → `.failed("…calendar access is off…")`, else
    `.unchanged` (`:31-35`).
  - toggle on, access: same id → `.unchanged`; new id → `.store(id)`; nil →
    `.failed("…no calendar was available.")`; `noWritableCalendar` → `.failed("…no
    writable calendar…")`; other error → `.failed("…couldn't be updated.")` (`:36-45`).
  - `capturing(isolation:_:)` wraps an async throwing body into `Result` (`:50-59`).
  - `SessionEditView.apply(_:store:)` (`SEV:292-307`) persists `.store` and turns
    `.failed` into `calendarWarning`, logged via `Log.calendar.error` (`:300`, `:304`).
- **Callers**: `requestAccess` `SEV:204` (series), `:235` (single), `:262` (edit);
  `authorizationStatus` `Sources/Features/Settings/SettingsView.swift:167`; `push`
  `SEV:218` (series), `:237` (single), `:269` (edit, no id); `update` `SEV:267` (edit,
  id exists); `remove` `SEV:274` (edit, toggle off), `SRVM:103` (delete), `SRVM:219`
  (cancel).
- Edit-mode toggle: initialised from `existing.eventIdentifier != nil` (`SEV:51`),
  label "Keep in iPhone calendar" vs "Add to iPhone calendar" (`SEV:130`), footer
  mentions Google Calendar via default account (`SEV:132`).
- **Share sheet / .ics**: none exists. No `.ics`, `EKEventEditViewController`,
  `UIActivityViewController` or calendar `ShareLink`. Only `ShareLink`s are report
  PDF/PNG in `Sources/Features/Components/ShareReportMenu.swift:10-11`.

## Q3: Existing single-session edit, status change and delete flows

### Findings
- **All `seriesId` logic checks in Sources/** (3, all in `SRVM`):
  - `:46` `canEdit: Bool { session.seriesId == nil }` (doc `:44-45`: series occurrences
    share one recurring event and are created in bulk; see BACKLOG).
  - `:101` delete: calendar remove only if `seriesId == nil` and an id exists.
  - `:217` setStatus: calendar remove only if `status == .cancelled`, `seriesId == nil`,
    and an id exists.
  - Other `seriesId` references are data plumbing: `Session.swift:32,45,57`,
    `SessionDTO.swift:28,82,110`, frozen `SchemaV1.swift:120,127,135`,
    `DataArchive.swift:185`, `PreviewFixtures.swift:47` (`nil`), `SEV:180`, `:223`, and the
    `SR` lines in Q1/Q4. No checks in `SessionRunView`, Schedule, client detail,
    `SetTableView`, `SetDraft`, reminders or notifications.
- **SessionRunViewModel state** (`SRVM`): `onStatusChanged` (`:13`, init default `{}` `:57`),
  `errorMessage` (`:23`), `lastLoggedSetId` (`:28`), `plannedSetCount` (`:30-32`),
  `loggedSetCount` (`:34-40`), `progress` (`:42`); init takes
  `calendar: any CalendarSyncing = EventKitCalendarService()` (`:52`). No construction
  site passes a calendar (`ScheduleView.swift:44`, `ClientDetailView.swift:106`,
  `SessionRunView.swift:234` preview).
- **SessionRunView UI** (`Sources/Features/Session/SessionRunView.swift`):
  - Status buttons only while `.scheduled` (`:67-79`): "Mark Completed", "Cancelled",
    "No-show" — each sets `pendingStatus` (`:70`, `:73`, `:76`).
  - Series footnote when `!canEdit`: "Part of a repeating series — editing individual
    occurrences isn't available yet." (`:81-87`).
  - Progress bar while scheduled and `plannedSetCount > 0` (`:91-99`).
  - "More actions" menu (`:109-117`): "Edit session" only if `canEdit` (`:111`); "Delete
    session" always (`:113`).
  - Edit sheet (`:120-131`): `SessionEditView(sessionRepo:, clientRepo:, workoutRepo:,
    existing: viewModel.session, initialDate:)`; `onSaved` sets `calendarWarning` and
    runs `reloadAfterEdit()` (`:127-130`).
  - "Calendar" warning alert (`:132-139`).
  - Delete alert "Delete this session?" (`:140-153`); dismisses only if `delete()` returns
    true (`:143-144`); message: non-series "Logged sets for this session are deleted too.
    This cannot be undone.", series "Only this occurrence is deleted; the rest of the
    series stays." (`:150-152`).
  - Status alert (`:166-179`): titles/confirm labels from `statusAlertTitle` (`:194-200`)
    and `statusAlertConfirm` (`:202-208`); destructive role unless completed (`:170`);
    "Keep" cancels (`:174`); message completed → "You can still log or delete sets
    afterwards.", else "This can't be changed back from the app."
  - Set delete confirmationDialog (`:180-190`); `#Preview("Session")` (`:231-244`) uses
    `PreviewFixtures.scheduledSession`.
  - `SetTableView` / `SetDraft` carry no status/edit/delete-session logic.
- **Edit** (`SEV:249-288`); edit mode hides Workouts and Repeat (`SEV:80-124`):
  1. Copy existing with new client/start/end/notes (`:250-254`).
  2. `sessionRepo.update` (`:256`); throw → "Couldn't save the session…", false
     (`:258-259`), no log.
  3. Calendar (`:262-279`): toggle on + access → `update` if id else `push(recurrence:
     nil)`; toggle off + id → `remove`; via `capturing`.
  4. `resolveEventIdentifier` → `apply` with `setEventIdentifier(id:)` (`:280-286`);
     return true (`:287`). Toolbar Save then calls `onSaved` and dismisses (`:141-152`).
  - `SR.update` (`SR:190-198`) writes only client/start/end/notes/updatedAt.
- **Status change** (`SRVM.setStatus`, `:205-228`): clear error (`:206`) →
  `sessionRepo.setStatus` (`:208`; throw → `Log.ui.error`, "Couldn't update the session
  status.", return, `:210-212`) → if cancel & non-series & id: `calendar.remove` then
  `setEventIdentifier(id, nil)` (`:217-220`; throw only logged "cancel cleanup failed",
  id kept, `:221-224`) → `refreshSession()` (`:226`) → `onStatusChanged()` (`:227`).
  Completed and no-show never touch the calendar.
- **Delete** (`SRVM.delete`, `:99-118`): clear error (`:100`) → **calendar first** if
  non-series & id (`:101-103`; failure logged "remove on delete failed", `:106`) →
  `sessionRepo.delete` (`:110`; throw → `Log.ui.error`, "Couldn't delete the session…",
  false, `:112-114`) → `onStatusChanged()` (`:116`) → true.
- `reloadAfterEdit()` (`SRVM:90-93`): `refreshSession()` then `onStatusChanged()`.
  `refreshSession()` (`:233-242`) re-reads, failure logged at debug.
- `SR.delete(id:)` (`SR:225-238`) deletes `SetRecord`s by instance id, then the session.
- **Presenters**: Schedule row → `SessionRunView` with `onStatusChanged: {
  viewModel.load() }` (`ScheduleView.swift:42-58`, `:52`), add sheet (`:72-82`), warning
  alert (`:83-90`). Client detail `sessionLink` (`ClientDetailView.swift:104-119`) passes
  `onStatusChanged: { viewModel.reload() }` (`:114`) and no `workoutRepo`.
- **Session row**: `SessionRow` in `ScheduleView.swift:99-122` — client name in
  `Theme.Fonts.display()` (`:106-107`), time range `.caption` (`:108-111`), instance names
  `.caption2` (`:112-116`), `StatusChip(status:)` (`:119`); no series indicator. Used at
  `ScheduleView.swift:55` and `ClientDetailView.swift:117` (date as title).
  `StatusChip` (`Sources/Features/Components/StatusChip.swift:3-26`): nothing for
  scheduled; Label in a Capsule for completed/cancelled/no-show with theme colours.
  Previews: `ScheduleView.swift:124` "Schedule", `:135` "Session row";
  `ClientDetailView.swift:122`; `SEV:310` "New session" (no edit-mode preview).
- **Theme** (`Sources/Support/Theme.swift`): colours `accent` `:6` … `success` `:9`,
  `warning` `:10`, `danger` `:11`; `Fonts.display()` `:19`; spacing `xs` `:27`, `sm` `:28`;
  screens use `.themedRows()` / `.themedScreen()`.
- **PreviewFixtures** (`Sources/Support/PreviewFixtures.swift`): `client` `:13`,
  `scheduledSession` `:33` (`seriesId: nil` `:47`), `loggedSets` `:50`, `repositories()`
  `:77`, `container()` `:96`; no series fixture. Not used by Tests.
- **Order summary**: Edit = repo.update → calendar → setEventIdentifier → reload/refresh.
  Cancel = repo.setStatus → calendar.remove → setEventIdentifier(nil) → refreshSession →
  onStatusChanged. Completed/no-show = repo.setStatus → refreshSession → onStatusChanged.
  Delete = calendar.remove → repo.delete → onStatusChanged. Add = schedule(Series) →
  push → setEventIdentifier(ForSeries) → onSaved → ScheduleViewModel.load.

## Q4: `SessionRepository` methods by series, date, status; guarantees

### Findings
- Protocol `SR:4-43`; implementation `@ModelActor actor SwiftDataSessionRepository` (`SR:106`).
- **Series-keyed** (only two): `scheduleSeries` (`SR:13-19`, impl `:113-149`) and
  `setEventIdentifierForSeries(_ seriesId:, _ eventIdentifier:)` (`SR:29`, impl `:207-216`)
  — fetches all rows `seriesId == seriesId` with no status/date filter, sets id and
  `updatedAt`, saves. No method fetches, updates or deletes by series or "this and following".
- **Date/status reads**: `sessions(from:to:)` (`SR:155-162`, no status filter);
  `upcoming(after:limit:)` (`SR:164-172`, `statusRaw == "scheduled"`, `fetchLimit`);
  `forClient(_:)` (`SR:174-181`); `completedCount(since:)` (`SR:240-246`).
- **Single-row mutators**: `get(id:)` (`SR:151-153`), `setStatus(id:_:)` (`SR:183-188`),
  `update(_:)` (`SR:190-198`), `setEventIdentifier(id:_:)` (`SR:200-205`),
  `updateNotes(id:_:)` (`SR:218-223`), `delete(id:)` (`SR:225-238`); all silent no-op
  on a missing id.
- Sets: `recordSet` (`SR:250-253`), `deleteSet` (`SR:255-262`), `setsFor(instanceId:)`
  (`SR:264-271`), `lastSet(clientId:exerciseId:)` (`SR:273-286`). `SetRecord` links to
  instances by `workoutInstanceId`, not a relationship (`SR:227-228`).
- **Guarantees**: none. No method checks logged sets, non-scheduled status or series
  membership before mutating. `scheduleSeries` always creates `.scheduled` rows with fresh
  instances (`SR:135`).

## Q5: How `ReminderCoordinator` schedules/clears notifications and what triggers refresh

### Findings
- `refresh()` (`Sources/Services/ReminderCoordinator.swift:51-71`): `upcoming(after: .now,
  limit: 64)` (`:54`; error → logged, `[]`, `:56-57`, which then clears all pending
  alerts); names from `allIncludingArchived()` (`:61-66`, fallback "Client"); 
  `notifications.reschedule(upcoming:)` (`:67-69`); `refreshPermissionStatus()` (`:70`).
  Doc `:5-6`: call on foreground and after any session mutation.
- `LocalNotificationService.reschedule` (`Sources/Services/NotificationService.swift:84-117`)
  removes all pending `sess-` requests, returns early without authorization, else adds
  24 h / 1 h alerts from pure `selectAlerts` (`:15-49`). Identifiers
  `"sess-<session UUID>-24h"` / `"-1h"` (`:32`, `:41`) — session id, not `seriesId`.
- `upcoming` filters on `scheduled`, so cancelled / completed / no-show / deleted
  sessions drop out on the next `refresh()`.
- **Callers**: `RootView.swift:82` (foreground); `ScheduleViewModel.load()`
  (`ScheduleViewModel.swift:55`); `ClientDetailViewModel.reload()`
  (`ClientDetailViewModel.swift:57`). Add → `onSaved` → `load()` (`ScheduleView.swift:80`);
  edit → `reloadAfterEdit` → `onStatusChanged`; status/delete → `onStatusChanged`
  (`SRVM:227`, `:116`, delete only on success). `SessionRunViewModel` never calls the
  coordinator directly.

## Q6: Series/recurrence in schema, DTO and archive; migration implications

### Findings
- Live `Session` @Model (`Sources/Models/Session.swift:22-65`): `seriesId` (`:32`),
  `recurrenceData` (JSON of `AppRecurrence`, `:33`), `eventIdentifier` (`:34`); all
  optional, nil defaults (`:45-47`). The rule itself is stored, duplicated on every occurrence.
- **SchemaV1** (`Sources/Persistence/SchemaV1.swift`): version 1.0.0 (`:9`, `:15-18`);
  **frozen nested copies** of all 8 models (`Session` `:110-141`, same three fields
  `:120-122`); header `:4-7` says they are never edited (SwiftData needs distinct classes
  per version).
- **SchemaV2** (`Sources/Persistence/SchemaV2.swift`): version 2.0.0 (`:6`, `:12-15`);
  `models` are the **live** top-level types (`:7-10`); adds only `Client.isSelf`
  (`Sources/Models/Client.swift:15`). `Session` is identical in V1 and V2.
- **Migration plan** `TrainMeMigrationPlan` (`SchemaV1.swift:216-221`): `schemas =
  [SchemaV1, SchemaV2]`, one `.lightweight(V1 → V2)` stage.
- `PersistenceController` builds the container from `SchemaV2` through the plan
  (`Sources/Persistence/PersistenceController.swift:6`, `:17-22`).
- `StoreBackup` keys on `"lastRunSchemaVersion"` (`StoreBackup.swift:7`), backs up to
  `Backups/pre-schema-<version>/` on change (`:18-48`); `TrainMeApp.swift:19` passes
  `SchemaV2.versionString`.
- **How V2 was introduced** (pattern for any new stored property): defaulted property on
  the live class + DTO field with a decode default (`ClientDTO.swift:14`); new
  `SchemaVn` listing live types; previous schema keeps frozen copies; lightweight stage;
  `PersistenceController` / `TrainMeApp` point at the new version; `SchemaTests` and
  repository tests updated. `ArchiveV1` and the fixture were untouched.
- `SessionDTO` (`Sources/Models/DTO/SessionDTO.swift:20-33`): `seriesId` (`:28`),
  `recurrence` (`:29`), `eventIdentifier` (`:30`); model→DTO decodes with `try?` (`:83`),
  `toModel()` re-encodes (`:102-118`, `:111`). Session fields are also mapped one by one
  in `DataArchive.insertSessionGraph` (`:177-201`) and `SR:299-301`.
- **Archive v1** (`Sources/Services/Archive/ArchiveV1.swift`): `schemaVersion = 1` (`:9`),
  frozen (`:3-7`), `sessions: [SessionDTO]` (`:18`); import rejects newer
  (`DataArchive.swift:86-91`), upserts by id (`:159-165`).
- Fixture `Tests/Fixtures/export-v1.json`: one session (`:83-109`) with no `seriesId`,
  `recurrence` or `eventIdentifier` keys.
- **Tests pinning shape**: `SchemaTests.swift:5-12` (V1 and V2 each 8 models, "1.0.0" /
  "2.0.0", 2 schemas, 1 stage), `:14-17` (container opens, 8 entities);
  `ArchiveRoundTripTests.swift` `goldenV1FixtureImports` (`:148-174`), round-trip helper
  uses `seriesId: nil, recurrence: nil` (`:52-53`); `StoreBackupTests.swift` (5 tests, no
  schema references); `ClientRepositoryTests.swift:88-134` (`isSelf`).

## Q7: Test doubles and existing series coverage

### Findings
- **`FakeCalendar`** (actor, `Tests/SessionRunViewModelTests.swift:7-46`): records
  `removed` / `updated` (`:8-9`); stubs `pushResult` (default `.success("evt-new")`),
  `updateResult`, `removeError` (reset on every `configure`, `:24`), `status`
  (`:10-14`, `:16-26`); `push` ignores session and recurrence (`:32-34`). Also used by
  `CalendarServiceTests.swift:10`.
- **`FailingSessionRepo`** (actor, `SessionRunViewModelTests.swift:88-141`): wraps the
  real repo; `fail(delete:setStatus:recordSet:)` (`:97-101`); forwards every other
  `SessionRepository` method (`:116-140`). **Any new protocol method needs a forwarder here.**
- **`FakeNotifications`** (`Tests/ReminderCoordinatorTests.swift:6-19`): records
  `rescheduleCalls: [[UUID]]`. **`FlakyArchive`** (`Tests/SafeImporterTests.swift:7-26`).
- No fakes for client/exercise/workout repositories; tests use real `SwiftData*Repository`
  on `PersistenceController.makeContainer(inMemory: true)` per file (e.g.
  `SessionRunViewModelTests.swift:55`, `:158`, `:245`; `SessionRepositoryTests.swift:11`
  with `makeRepos()` `:10` and `sessionDTO(clientId:startAt:)` `:18-25`). Swift Testing
  (`@Test`, `#expect`, `#require`); VM tests `@MainActor`. Env structs `FailingEnv`
  (`:143-152`) and `SessionEnv` (`:233-239`, `makeSessionEnv` `:244`).
- **SessionRunViewModelTests** (7): `deleteRemovesCalendarEventAndSession` `:54`,
  `failedDeleteReturnsFalseAndSetsError` `:193`, `failedSetStatusKeepsEventIdentifier`
  `:205`, `failedRecordLeavesSetsUnchanged` `:218`, and under "Inline set table (Phase 3)"
  (`:231`): `previousSetsLoadedPerExercise` `:280`, `progressReflectsLoggedOverPlanned`
  `:297`, `recordDraftOmitsMetricsNotInExercise` `:316`.
- **Series coverage today**: `SchedulingTests.swift` (`expandRecurrence`) `:9`, `:25`,
  `:33`, `:41`, `:49`, `:58` (helper `date(y,m,d,h)` `:5`); `CalendarMappingTests.swift`
  `weeklyTueThuMapsToEKRule` `:6`, `occurrenceCountEndMaps` `:16`, `endDateMaps` `:24`,
  `invalidIntervalClampedToOne` `:34`; `SessionRepositoryTests.swift`
  `seriesSchedulingSharesSeriesIdAndCopiesPerSession` `:69`,
  `seriesHorizonCoversExactlyNWeeks` `:112`,
  `seriesStartingOffRuleWeekdayAnchorsOnFirstRealOccurrence` `:127`;
  `EventIdentifierResolutionTests.swift` (9 tests, `:6-55`).
- **Not covered**: `setEventIdentifierForSeries`; `canEdit == false`; the calendar skip at
  `SRVM:101` / `:217`; non-nil `recurrence` round-trip; `FakeCalendar.push` with a
  recurrence; `SessionEditView` logic.
- `grep -r "@Test" Tests | wc -l` → 115 lines across 24 files.

## Cross-Cutting Observations
- **Series identity is implicit**: rows sharing `seriesId`, each carrying a copy of the
  rule and the same `eventIdentifier`. The calendar event's end is pinned to the
  occurrence count (`SEV:215-216`), not an end date.
- **Calendar span semantics**: `remove` always `.futureEvents`, `update` always
  `.thisEvent`; on a recurring event `event(withIdentifier:)` resolves to the first
  occurrence. The `seriesId == nil` gates in `SRVM` keep series rows from calling these.
- **Write ordering is not uniform**: delete is calendar-then-DB; edit and cancel are
  DB-then-calendar. Calendar failures are non-blocking (logged or `calendarWarning`), DB
  failures block.
- **Reminders are derived state**, rebuilt from scheduled `upcoming` on every explicit
  `refresh()`, keyed by session id.
- **Schema versioning is active**: the live models are SchemaV2; a new stored property
  means a SchemaV3 with frozen V2 copies and a lightweight stage.
- **Logic location**: `SessionEditView` holds untested create/edit orchestration;
  `SessionRunViewModel` is the tested surface with injected `CalendarSyncing` and a
  presenter-supplied `onStatusChanged`.

## Open Areas
- EventKit behaviour for occurrence-level operations on a recurring event (detached
  occurrences, `occurrenceDate`, `.futureEvents` on a mid-series occurrence) is not
  exercised anywhere; `FakeCalendar` does not model recurrence.
- Whether data import (`SettingsView` `importArchive(url:mode: .merge)`) triggers
  `reminders.refresh()` was not traced.
