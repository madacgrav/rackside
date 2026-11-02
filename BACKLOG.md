# TrainMe Backlog

Everything the 2026-10-26 review found that is **not** fixed in the same change.
Priorities follow the PRD (P1 strongly desired, P2 nice-to-have). Each row links the
PRD section, the evidence from the review, and its GitHub issue.

Source: `thoughts/qrspi/2026-10-26-review-gaps-and-app-icon/research.md`. P0 items from
that review (export reminder, injuries at session time, units, session edit/delete,
confirmations, failed-save surfacing, notification correctness) shipped in the same PR.

Tech debt and test gaps from that review (rows 20–27) were addressed in
[#32](https://github.com/madacgrav/trainme/pull/32); see the [Done](#done) table and
`thoughts/qrspi/2026-10-26-tech-debt/` for the design and plan.

P1 reporting features (rows 1–4, 9, 10) were addressed in
[#34](https://github.com/madacgrav/trainme/pull/34); see the [Done](#done) table and
`thoughts/qrspi/2026-10-26-p1-reporting/` for the design and plan.

Series edit/cancel (row 5) was addressed in
[#39](https://github.com/madacgrav/trainme/pull/39);
see the [Done](#done) table and `thoughts/qrspi/GH-7-series-edit-cancel-calendar/` for the
design and plan.

Week view on Schedule (row 6) was addressed in [#40](https://github.com/madacgrav/trainme/pull/40);
see the [Done](#done) table and `thoughts/qrspi/GH-8-schedule-week-view/` for the design and
plan.

Client intake (row 35: profile, health screening, NASM assessments, liability waiver, guided flow)
is on branch `2026-11-01-nasm-movement-assessment`; see the [Done](#done) table and
`thoughts/qrspi/2026-11-01-nasm-movement-assessment/` for the design and plan.

## P1 — features

| # | Item | Why / PRD ref | Evidence | Issue |
|---|------|---------------|----------|-------|
| 7 | Inline "create exercise" from the workout picker | PRD §4.3 | `ExercisePickerView` has no create action | [#9](https://github.com/madacgrav/trainme/issues/9) |
| 8 | Browse and unarchive archived clients | PRD §5.1 | No list uses `allIncludingArchived`; unarchive only from an open detail screen | [#10](https://github.com/madacgrav/trainme/issues/10) |

## P2 — features

| # | Item | Why / PRD ref | Evidence | Issue |
|---|------|---------------|----------|-------|
| 11 | CSV export of session history | PRD §9 | No CSV code | [#13](https://github.com/madacgrav/trainme/issues/13) |
| 12 | Daily / every-N-weeks recurrence in the UI | PRD §5.4 | `AppRecurrence` supports it; `SessionEditView` is weekly, interval 1 | [#14](https://github.com/madacgrav/trainme/issues/14) |
| 13 | RPE input when logging a set | PRD §4.1 | `SetRecord.rpe` is always nil | [#15](https://github.com/madacgrav/trainme/issues/15) |
| 14 | Delete client / delete exercise | PRD §5.1 / §5.2 | Repository methods exist with no UI caller | [#16](https://github.com/madacgrav/trainme/issues/16) |
| 15 | Settings toggles: app lock on/off, calendar default, notification lead times | PRD §5.7 / §5.11 | Settings has Units and Backup only | [#17](https://github.com/madacgrav/trainme/issues/17) |
| 16 | Reorder workout entries via edit mode | PRD §5.3 P1 | `.onMove` is wired but no `EditButton` exists | [#18](https://github.com/madacgrav/trainme/issues/18) |
| 17 | Session notes on Schedule and client-detail rows | PRD §5.5 | Notes visible only inside the run screen | [#19](https://github.com/madacgrav/trainme/issues/19) |
| 33 | Snapshot tests for themed screens (swift-snapshot-testing, CI baseline) | UI refresh verification | Previews + manual screenshots only; see `thoughts/qrspi/2026-10-26-ui-refresh-and-icon/screenshots/` | — |
| 34 | Quick timers for exercises: rest countdown between sets, countdown for timed sets that prefills duration | PRD §4.1 / §5.5 (requested 2026-10-29) | `SetTableView` has only a numeric duration stepper (15 s steps); no timer code | [#38](https://github.com/madacgrav/trainme/issues/38) |
| 36 | NASM assessment form page 2 | Intake follow-up | Only page 1 of the form (`nasm-assessment-form-p1.jpeg`) was provided; blocked on the page | — |
| 37 | Charts of assessment measurements over time | Intake follow-up | Assessments only diff against the previous one | — |
| 38 | In-app e-signature for the waiver | Intake follow-up | Waiver is send-and-mark; the signed copy lives outside the app | — |
| 39 | Compensation → overactive/underactive muscle suggestions | Intake follow-up | Sources were secondary and incomplete (research.md Q10) | — |

## Deferred by owner decision

| # | Item | Decision | Issue |
|---|------|----------|-------|
| 18 | Double-booking detection / warning | decisions.md #3: out of scope | [#20](https://github.com/madacgrav/trainme/issues/20) |
| 19 | Direct Google Calendar API integration | decisions.md #4: default calendar + share sheet only | [#21](https://github.com/madacgrav/trainme/issues/21) |

## Done

Addressed in [#32](https://github.com/madacgrav/trainme/pull/32) (one commit per phase).

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 20 | `VersionedSchema` + `SchemaMigrationPlan` | `SchemaV1` + `TrainMeMigrationPlan`; `StoreBackup` keyed on schema version with a one-time legacy backup | [#22](https://github.com/madacgrav/trainme/issues/22) |
| 21 | Pre-import automatic backup and import rollback on partial failure | `SafeImporter` snapshots before replace-import, `importData` rolls back on throw, snapshot restored on failure; distinct Settings messages | [#23](https://github.com/madacgrav/trainme/issues/23) |
| 22 | Surface remaining background `try?` paths | `os.Logger` per subsystem; seed-import alert; `SessionRunViewModel` error state; calendar warnings after save; export/import picker failures reported | [#24](https://github.com/madacgrav/trainme/issues/24) |
| 23 | Check notification authorization before `add`; re-prompt path when denied | `reschedule` gates on `canScheduleAlerts`; Settings → Permissions shows status with Open Settings link | [#25](https://github.com/madacgrav/trainme/issues/25) |
| 24 | Handle `defaultCalendarForNewEvents == nil` | Falls back to first writable calendar, else `CalendarError.noWritableCalendar` surfaced as a warning | [#26](https://github.com/madacgrav/trainme/issues/26) |
| 25 | Privacy manifest, entitlements file, CI workflow | `Sources/PrivacyInfo.xcprivacy`, `Sources/TrainMe.entitlements`, `.github/workflows/ci.yml` | [#27](https://github.com/madacgrav/trainme/issues/27) |
| 26 | AppLock, EventKit write path, notification delivery, ReportExporter, view models, UI tests | Partial: `SessionRunViewModel` failure paths, notification gate, calendar outcome resolution, coordinator status tested via fakes. Still open: AppLock, ReportExporter, real EventKit/UNUserNotificationCenter, UI tests | [#28](https://github.com/madacgrav/trainme/issues/28) |
| 27 | Replace-import into a non-empty store; `importArchive(url:)` failure paths | `Tests/SafeImporterTests.swift` covers both plus mid-import failure restore and malformed body | [#29](https://github.com/madacgrav/trainme/issues/29) |

Still worth a look (found while doing the above, not fixed): a failed `upcoming` fetch in
`ReminderCoordinator.refresh` clears all pending alerts instead of leaving them.

Addressed in [#34](https://github.com/madacgrav/trainme/pull/34) (one commit per phase).

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 1 | Session volume per session / week | `sessionVolumes` / `weeklyVolumes` on `ReportingQueries`; per-unit totals, never converted; overview bar chart + session rows | [#3](https://github.com/madacgrav/trainme/issues/3) |
| 2 | Training consistency | `consistency(clientId:from:to:)`; completed ÷ resolved, unresolved past sessions reported separately; window picker 4w / 12w / all | [#4](https://github.com/madacgrav/trainme/issues/4) |
| 3 | Client-level summary of top exercises | `topExercises` ranked by session count then recency; overview rows link to the exercise screen | [#5](https://github.com/madacgrav/trainme/issues/5) |
| 4 | Per-exercise history list | `historyBySession`; `ExerciseReportView` "History" section | [#6](https://github.com/madacgrav/trainme/issues/6) |
| 9 | Report as PNG image | `ReportExporter.render` writes PDF and PNG at 3×; Share menu on both screens | [#11](https://github.com/madacgrav/trainme/issues/11) |
| 10 | Total-reps progression chart | `ProgressPoint.totalReps`; third chart on the exercise screen and page | [#12](https://github.com/madacgrav/trainme/issues/12) |

Addressed in [#36](https://github.com/madacgrav/trainme/pull/36) (one commit per phase).

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 28 | Theme tokens and shared components | `Sources/Support/Theme.swift`, `Sources/Features/Components/`; dark-first colorsets with light values | [#36](https://github.com/madacgrav/trainme/pull/36) |
| 29 | Inline set table | `SetTableView`, `MetricStepper`, `SetDraft`; one-tap logging with haptic and progress bar | [#36](https://github.com/madacgrav/trainme/pull/36) |
| 30 | Self-use client | `Client.isSelf`, `SchemaV2` lightweight migration (SchemaV1 keeps a frozen model snapshot), "About You" sheet | [#36](https://github.com/madacgrav/trainme/pull/36) |
| 31 | Icon appearance variants | Bolder layers, explicit dark and tinted specializations in `icon.json` | [#36](https://github.com/madacgrav/trainme/pull/36) |
| 32 | Previews for every screen | `PreviewFixtures` (seeded in-memory container) and a `#Preview` per feature screen | [#36](https://github.com/madacgrav/trainme/pull/36) |

Addressed in [#39](https://github.com/madacgrav/trainme/pull/39) (one commit per phase).

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 5 | Series edit/cancel and shared calendar event update/removal | "This session only" / "This and following" for edit, cancel and delete (`SeriesActions`); one-session edits detach from the series with their own event; "following" ends the recurring event before the date and edits start a new series segment; occurrences with logged sets keep their own event; no schema change | [#7](https://github.com/madacgrav/trainme/issues/7) |

Addressed in [#40](https://github.com/madacgrav/trainme/pull/40) (one commit per phase).

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 6 | Week view on Schedule | Day/Week segmented toggle; week of `selectedDate` (locale first weekday) as 7 day sections with `SessionRow`; chevrons + Today; mode persisted; `ScheduleViewModel` takes an injected `Calendar`; `ScheduleViewModelTests` | [#8](https://github.com/madacgrav/trainme/issues/8) |

Client intake, on branch `2026-11-01-nasm-movement-assessment` (one commit per phase).

| # | Item | Resolution | Issue |
|---|------|------------|-------|
| 35 | Client intake from the NASM assessment form | `SchemaV3` (V2 frozen as nested copies, real on-disk V2→V3 migration test) and archive v2 (V1 decode + `migrate`, golden `export-v2.json`). Client profile fields; dated `HealthScreening` with clearance flag shown on detail and in sessions; dated `Assessment` (measurements, Overhead/Single Leg Squat option sets, diff vs previous); versioned `WaiverTemplate` + `WaiverRecord` snapshots, paginated PDF shared via a completion-reporting share sheet; guided `IntakeFlowView` | — |
