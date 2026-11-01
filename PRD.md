# TrainMe — Product Requirements Document

**Version:** 0.1 (draft for review)
**Date:** 2026-07-08
**Owner:** Adam
**Status:** Draft

---

## 1. Summary

TrainMe is a mobile app that helps an independent personal trainer manage clients, build and reuse workouts, schedule and record training sessions, and track each client's progress over time. Version 1 targets **iOS only**, stores **all data locally on the device**, and is built for a **single trainer** (the app's owner) with the architecture kept clean enough to add cloud sync and multi-trainer accounts later.

The core loop the app optimizes: *build a workout → schedule a session for a client → run the session and record what actually happened → see the client improve over weeks.*

---

## 2. Goals and non-goals

### 2.1 Goals (v1)

The app should let a single trainer manage a roster of clients, author reusable workouts, schedule sessions on a calendar, record what actually happened in each session, and review each client's progression. It should keep working with no internet connection and never lose data silently. It should let the trainer get client data out of the app (export) and back in (import) using a stable, documented file format.

### 2.2 Explicit non-goals (v1)

Billing, invoicing, and package/sessions-remaining tracking are out of scope for v1 (revisit in v2). There is no client-facing app or client login — clients never install anything. There is no multi-trainer / team functionality, no cloud account, and no server-side component. Nutrition, body-measurement/photo tracking, and in-app payments are out of scope. Android is deferred to a later release.

### 2.3 Why these constraints matter downstream

Two v1 decisions have large consequences that the rest of this document is built around:

- **Local-only storage on iOS** means the app *cannot* send automated text messages. iOS does not permit an app to send SMS silently or on a schedule. See §6 (Reminders) and §7 (Sharing reports) for how this reshapes those features into trainer-initiated actions rather than automation.
- **"Personal now, sellable later"** means we accept the local-only limitation for v1 but keep the data layer, export schema, and domain model clean enough that a sync backend can be added in v2 without a rewrite. See §11 (Future/commercialization path).

---

## 3. Target user and context

The primary (and only) v1 user is an independent personal trainer running their own book of business, comfortable with a phone but not technical. They train clients in person at a gym or in homes, often with spotty connectivity, and need something faster and more structured than a notes app or spreadsheet. They typically run back-to-back sessions and need to record sets quickly, sometimes one-handed, mid-exercise.

Clients are *records inside the app*, not users. They receive value indirectly: reminders and progress reports that the trainer chooses to send them.

---

## 4. Core concepts and data model

This section defines the domain, because two of the requested behaviors ("edit for one session vs. permanently for the future" and "lifting-weight progression reporting") are only possible with the right model.

### 4.1 Entities

**Client** — a person the trainer trains. Fields: name (required), mobile phone number (required, E.164-normalized), plus optional goal/notes and injuries/limitations (see §4.4 — recommended additions). One trainer has many clients.

**Exercise (library item)** — a *canonical, reusable* definition of a movement, e.g. "Barbell Bench Press." Fields: name, category (`strength` / `cardio` / `bodyweight` / `mobility`), the metrics it tracks (any of: weight, reps, sets, duration, distance), and default unit. This is the single most important modeling decision in the app — see §4.3.

**Workout (template)** — a named, reusable ordered list of exercise entries with target parameters (e.g. "Leg Day A" = Back Squat 3×5 @ 185 lb, Leg Press 3×12, …). Workouts are *templates*; they are not tied to a date or a client.

**Session** — a dated, scheduled event for one client that contains one or more **workout instances**. A session has: client, date/time, status (`scheduled` / `completed` / `cancelled` / `no-show`), and notes.

**Workout instance** — a *copy* of a workout template captured into a session. This is what makes "edit for this session only vs. permanently" work (see §4.2). It holds the *planned* parameters and, after the session, the *actual* recorded sets.

**Set record** — the actual performed data for one set: weight, reps, duration, distance, RPE (optional), as applicable to the exercise's metrics. This is the atomic unit that reporting aggregates.

### 4.2 Template vs. instance (the "edit one session vs. all future" mechanic)

When a trainer schedules a workout into a session, the app **copies** the template into a workout instance. From there:

- **"Edit just this session"** → modify the workout instance only. The template and all other sessions are untouched.
- **"Update permanently for the future"** → modify the **template**. Future sessions that copy it get the new version.

**Open design question to resolve:** when a template is edited, what happens to *already-scheduled future sessions* that were created from the old version? Options: (a) leave them frozen at the version they were created with (predictable, but they drift from the template), or (b) offer "apply this change to N upcoming sessions" at edit time. Recommendation: (a) by default with an optional (b) prompt. This needs your decision before build.

### 4.3 Exercise identity — why free-text alone breaks reporting

The original notes had "exercise" as a free-text field. That quietly makes progression reporting impossible: if "Bench Press" is entered as "bench," "Bench Press," and "BB bench" across sessions, the app sees three unrelated exercises and can't chart a trend.

**Requirement:** exercises resolve to a canonical library item via autocomplete. The trainer types, the app suggests existing exercises, and picks one. Free-text is allowed only to *create a new library item* (which is then reused). Every set record references an exercise ID, not a string. This is what makes §8 (reporting) possible.

### 4.4 Recommended additions to the Client record (your call)

The original spec had name + phone only. For a tool a trainer relies on, consider adding: primary goal, injuries/limitations (surfaces at session time so the trainer trains safely), and free-form notes. These are cheap to add now and awkward to retrofit.

**Client intake (shipped 2026-11).** Built from the trainer's NASM assessment form, configured per client:
- **Profile:** date of birth, emergency contact, physician, occupation, training history and availability.
- **Health screening:** dated, using the app's own plain-language yes/no questions. These are not PAR-Q+ text and are not a diagnosis. It also records medical history and lifestyle. Any YES flags "medical clearance recommended" on the client and in sessions until a clearance date is recorded, and screenings are prompted for review every 12 months.
- **Assessments:** dated, with toggled sections:
  - measurements
  - NASM page-1 Overhead Squat, including the heels-elevated and arms-down retests
  - Single Leg Squat

  Each assessment shows the changes since the previous one.
- **Liability waiver:** a versioned template that the trainer edits in Settings, with a not-legal-advice notice. It is sent as an unsigned PDF through the share sheet and marked when it is signed and returned. Each send keeps a snapshot of the text that was sent.
- **Guided intake:** offered after a client is created, and also from the client's page.

Billing remains deferred.

### 4.5 Units and metrics

Support pounds and kilograms at minimum (per-client or global default). Support these metric combinations per exercise: weight + reps + sets (strength), reps + sets (bodyweight), duration (timed holds, cardio), and distance + duration (running/rowing). The exercise's `metrics` field drives which inputs the recording UI shows, so a treadmill session doesn't ask for "weight."

---

## 5. Feature requirements

Priority: **P0** = required for v1, **P1** = strongly desired, **P2** = nice-to-have / v1.x.

### 5.1 Client management (P0)
Create, view, edit, and archive clients. List/search the roster. Each client's detail screen shows upcoming sessions, recent session history, and a link to their progress reports.

### 5.2 Exercise library (P0)
A searchable library of exercises with category and tracked metrics. Autocomplete when adding an exercise to a workout. Ship with a seed library of common exercises so the trainer isn't starting empty; allow adding custom ones.

### 5.3 Workout builder (P0)
Create, edit, duplicate, and delete workout templates. A workout is an ordered list of exercises with target sets/reps/weight/duration as appropriate. This is the "screen to maintain workouts" from the notes. Reordering exercises is P1.

### 5.4 Scheduling & calendar (P0)
Schedule a session for a client on a date/time and attach one or more workouts. A calendar view shows the trainer's day/week. Recurring sessions (e.g. "every Tue/Thu at 7am") is **P1**. Double-booking detection/warning is **P1**. Optional one-way push of sessions to the iOS system calendar (EventKit) is **P2**.

### 5.5 Run / record a session (P0)
Open a scheduled session and record actual performed sets against the planned workout instance. Fast entry is a first-class concern (large tap targets, "repeat last set," quick +/- steppers). Mark session completed / cancelled / no-show. Session and notes are saved to history.

### 5.6 Session & workout history (P0)
Per-client history of past sessions and what was performed. Per-exercise history (every time this client did Back Squat, with weights/reps). This is the data source for reporting.

### 5.7 Reminders (P0, redesigned — see §6)
Local notifications remind the *trainer* of upcoming sessions. Texting a client a reminder is a trainer-initiated action that opens a pre-filled Messages sheet (iOS cannot automate this).

### 5.8 Progress reporting (P0/P1 — see §8)
Per-client, per-exercise charts of weight and rep progression over time (P0). Session-volume and consistency summaries (P1).

### 5.9 Share a report with a client (P1 — see §7)
Generate a shareable report (PDF/image) and hand it to the trainer's iOS share sheet to send via Messages/email/AirDrop. Not automated.

### 5.10 Export & import (P0 — see §9)
Export all data (clients, exercises, workouts, sessions, history) to a documented file on the device / Files app. Import from a file in that same format.

### 5.11 Security / app lock (P0 — see §10)
Biometric (Face ID / Touch ID) lock on app open, since the app holds client PII and phone numbers.

---

## 6. Reminders — honest iOS design

**Constraint:** an iOS app that stores data locally and has no backend **cannot send SMS automatically or on a schedule.** There is no API for silent/background texting. This is a platform rule, not a design choice.

**What v1 will do instead:**

1. **Trainer-facing local notifications (fully automatic).** The app schedules `UNUserNotificationCenter` local notifications ahead of each session (e.g. 24h and 1h before). These fire on the trainer's own phone with no internet and no backend. This is reliable and free.

2. **Client reminder texts (one tap, trainer-initiated).** From a session, the trainer taps "Text reminder." The app opens `MFMessageComposeViewController` with the client's number and a pre-filled message ("Hi Sam, reminder: our session tomorrow at 7am — see you then!"). The trainer taps send inside Messages. The app cannot confirm or automate the send.

**If truly automated client reminders are a hard requirement, that forces a backend + SMS provider (Twilio) and cloud-stored phone numbers — i.e. it breaks "local-only."** Documented here as the single biggest tension between the feature list and the storage decision. Recommendation: ship the tap-to-send flow in v1; revisit automation in v2 alongside cloud sync (§11).

---

## 7. Sharing reports with clients — honest iOS design

Same constraint as §6: no automated/MMS sending from a local-only app. A progression "report" is a chart-bearing image or PDF, which SMS can't carry inline anyway.

**v1 approach:** the app renders a report to a PDF or PNG and presents the standard iOS **share sheet**. The trainer chooses how to send it — Messages (as an attachment), email, AirDrop, save to Files. This is one tap plus the trainer confirming the send. No backend, no per-message cost, no consent/TCPA exposure for the app itself (the trainer is sending from their own Messages/email, as they would manually).

---

## 8. Reporting requirements

Reporting is per-client and driven by set records (§4.1), which is why the canonical exercise model (§4.3) is mandatory.

**P0 charts:** for a selected client and exercise, a line chart of top-set weight over time; a chart of estimated 1RM or total reps over time. A simple "personal best" callout per exercise.

**P1:** session volume (total weight moved) per session/week; training consistency (sessions completed vs. scheduled); a client-level summary combining their top exercises.

**Data honesty:** charts only reflect what was *recorded* in completed sessions. Cancelled/no-show sessions are excluded from progression but counted in consistency. Exercises with too few data points show "not enough data yet" rather than a misleading two-point line.

---

## 9. Export / import format

The trainer owns this format, so define it deliberately and version it from day one.

**Format:** a single JSON file (human-inspectable, easy to validate) with a top-level `schemaVersion` integer, an `exportedAt` timestamp, and arrays for `clients`, `exercises`, `workouts`, `sessions`, and `setRecords`, cross-referenced by stable UUIDs. A CSV export of session history may be offered additionally for spreadsheet use, but JSON is the canonical round-trip format.

**Requirements:** export writes to the iOS Files app / share sheet so the trainer controls where it lands (iCloud Drive, etc.). Import validates `schemaVersion` and rejects/upgrades unknown versions gracefully rather than corrupting data. Import offers **merge** vs **replace** and never silently overwrites without confirmation. Because there is no cloud backup in v1, the app should *prompt the trainer to export periodically* — export is the only backup mechanism, and a lost/broken phone otherwise means total data loss. This risk should be stated plainly in onboarding.

---

## 10. Security & privacy

The app stores client PII (names, phone numbers) and, if §4.4 is adopted, health/injury notes. Requirements: biometric app lock (Face ID / Touch ID) with passcode fallback on launch; rely on iOS Data Protection so on-device storage is encrypted at rest; no analytics/PII leaves the device (consistent with local-only); phone numbers stored normalized and used only for the compose sheets in §6/§7. Intake health data is stored in the on-device SwiftData store under iOS default Data Protection (complete until first unlock), behind the Face ID app lock. Waiver PDFs are temporary files with complete protection, deleted after sharing. If the app is later commercialized, a privacy policy and explicit client-consent capture for messaging will be required — noted for v2.

---

## 11. Architecture & commercialization path

**v1 stack (recommendation):** native iOS in Swift/SwiftUI, on-device persistence via SwiftData (or Core Data). No backend.

**Keep-it-sellable discipline (so v2 doesn't require a rewrite):** put all data access behind a repository/persistence protocol rather than calling the store directly from the UI, so a syncing implementation can be swapped in later. Give every entity a stable UUID and `createdAt`/`updatedAt` timestamps now (cheap insurance for future conflict resolution / sync). Keep the export schema (§9) stable and versioned — it doubles as the future sync payload shape. Isolate the messaging/compose logic behind a small service so a Twilio-backed automated path can be added without touching the UI.

**Likely v2 additions when commercializing:** cloud account + sync backend (enables real backup, multi-device, and *automated* reminders/reports via a server + Twilio), multi-trainer tenancy, billing/package tracking (deferred from §2.2), and Android via either a second native app or a future cross-platform decision.

---

## 12. Key risks & open decisions

**Total data loss (high).** Local-only + no cloud backup means a lost phone loses everything. Mitigation: aggressive export prompts and clear onboarding language. Accepted for v1.

**Feature/constraint tension (medium).** "Automated reminders and report-sending" cannot coexist with "local-only" on iOS. v1 ships trainer-initiated versions; automation is a v2 + backend decision. Confirmed above.

**Open decisions needing your input before build:**
The template-versioning behavior for already-scheduled future sessions (§4.2). Whether to adopt the expanded client fields — goal, injuries, notes (§4.4). Whether recurring sessions and double-booking warnings are v1 (currently P1) (§5.4). Whether iOS system-calendar sync is wanted at all (§5.4, currently P2).

---

## 13. Rough milestone sketch (non-binding)

A sensible build order: (1) data model + persistence + client CRUD; (2) exercise library + workout builder; (3) scheduling/calendar + session recording; (4) history + progression reporting; (5) reminders (local notifications + compose sheets) + report sharing; (6) export/import + biometric lock. Each slice is independently testable and demoable.
