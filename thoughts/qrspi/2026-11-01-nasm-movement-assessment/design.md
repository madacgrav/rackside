# Design Discussion

## Current State
- **Client** (`Sources/Models/Client.swift:4-17`) holds name, phone and three free-text health fields
  (`goal`, `injuries`, `notes`). It has no structured intake, no screening and no assessment data. PRD
  §4.4 marks PAR-Q intake as deferred (`PRD.md:80`).
- **Related records** link to a client by plain `clientId` UUID, not by relationship (`Session.swift:25`).
  Deleting a client does not cascade (`ClientRepository.swift:58-62`). Owned children use
  `.cascade` + `inverse` (`Session.swift:30-31`).
- **Persistence:** `SchemaV2` is current, and V1 is a frozen copy behind a lightweight migration
  (`SchemaV1.swift:216-221`, `SchemaV2.swift:5-16`). `StoreBackup` keys on `versionString`
  (`StoreBackup.swift:18-48`).
- **Archive:** `ArchiveV1` is frozen (`ArchiveV1.swift:3-30`). Import rejects newer versions and has no
  migrate chain yet (`DataArchive.swift:82-100`). A golden fixture must keep importing
  (`Tests/ArchiveRoundTripTests.swift:145-174`).
- **Outbound:** the only way to message a client is SMS with a body only
  (`MessagingService.swift:23-39`). Files leave the app via `ShareLink` (`ShareReportMenu.swift:10-11`).
  PDF output is single-page and generated from charts only (`ReportExporter.swift:11-49`). There is no
  signature capture and no stored files.
- **Session screen:** the only health info it surfaces is an injuries warning
  (`SessionRunView.swift:47-55`).

## Desired End State
After creating a client, the trainer can run a guided **intake** that covers five areas:
1. **Profile:** date of birth, emergency contact (name, relationship, phone), physician (name, phone),
   occupation, training history, availability and goals.
2. **Health screening:** the app's own plain-language yes/no questions, covering the same topics as
   PAR-Q+ but in our own wording:
   - heart condition or high blood pressure
   - chest pain
   - dizziness or fainting
   - other chronic condition
   - medication for a chronic condition
   - bone, joint or soft-tissue problem
   - told by a doctor to exercise only under supervision

   A YES on any of them sets a **"Medical clearance recommended"** flag, which the trainer can resolve
   by recording that clearance was received and when. The screening also captures structured history:
   - conditions, surgeries, medications and supplements
   - family heart history
   - symptoms
   - lifestyle: sleep, stress, tobacco, alcohol, activity

   The screening is dated, and the app prompts for a review after 12 months.
3. **Waiver:** the app produces an **unsigned waiver PDF** from a trainer-editable template and shares
   it through the share sheet (email, text, AirDrop). The trainer later marks it **"Signed — returned
   on <date>"**. The app records the template version that was sent.
4. **Measurements:** resting HR, blood pressure, height, weight, waist, hip, body-fat %, push-up count
   and plank time. All are optional.
5. **Movement assessment:** the NASM page-1 tests.
   - **Overhead Squat:**
     - anterior foot/knee items, each scored R/L
     - lateral items, each scored yes/no
     - posterior items, each scored R/L
     - the "modified" heels-elevated and arms-down result for feet, knees, LPHC and upper body
     - notes
   - **Single Leg Squat:** each item scored R/L, plus notes.

Measurements and movement belong to a dated **Assessment**. Re-assessments create new dated entries,
and the assessment detail screen shows what changed since the previous one. When starting intake, the
trainer toggles which sections apply to this client. Every section can also be reopened later from new
**client detail** sections:
- Profile
- Health & Clearance
- Waiver
- Assessments

The session screen shows a clearance warning next to the injuries warning.

**Verification:**
- Unit tests for each repository and for the clearance logic.
- Archive v2 round-trip, and the v1 golden fixture still imports.
- A V2 to V3 schema migration test, opening a real V2 store.
- Waiver PDF render tests: multi-page output, and the version is stamped.
- Previews for every new screen.
- A device pass on "madphone".

## Patterns to Follow
- **Layering:** `@Model` → DTO (`Codable, Sendable, Identifiable, Equatable`, with `init(_:)` and
  `toModel()`) → `@ModelActor` repository returning DTOs → `@Observable @MainActor` view model → view
  (`ClientRepository.swift:4-74`, `ClientDTO.swift:22-61`, `ClientEditViewModel.swift:6-62`).
- **Cross-entity links by UUID**, with explicit deletes when the parent goes. Follow the SetRecord
  pattern in `SessionRepository.swift:315-323`: deleting a client deletes its screenings, assessments
  and waiver records.
- **Flags as option sets packed into an Int**, like `MetricSet` (`ExerciseEditView.swift:36-44`; the
  model's `metricsRaw`; JSON `"metrics": 7`). Use this for compensation checklists, one set per
  view and side, and for screening answers.
- **Edit form shape:**
  - a sheet with `NavigationStack { Form }`
  - Save disabled by `canSave`
  - `ErrorBanner` as the last section
  - Save calls `save() async -> Bool`, then `onSaved()` and `dismiss()`
  - References: `ClientEditView.swift:14-55`, `ErrorBanner.swift:4-17`
- **Inputs:**
  - `MetricStepper` / `OptionalStepper` for numbers (`MetricStepper.swift:4-35`,
    `WorkoutBuilderView.swift:179-227`)
  - tinted toggle buttons for R/L checkboxes (`SessionEditView.swift:126-139`)
  - `AdaptiveLabeledRow` for accessibility text sizes
- **Detail screens:** pushed with `NavigationLink`, using `themedScreen()`/`themedRows()`
  (`Theme.swift:38-49`, `ClientDetailView.swift:9-63`).
- **Schema changes:**
  - freeze the current models as `SchemaV2` nested copies, the way `SchemaV1` does (`SchemaV1.swift:4-18`)
  - add `SchemaV3` with the live models and a lightweight V2→V3 stage
  - bump `StoreBackup`'s version key
  - give every new stored property a default (`Client.swift:8`)
- **Archive:** follow the header in `ArchiveV1.swift:3-7`. Add `ArchiveV2.Envelope` and a pure
  `migrate(v1) -> v2`, and keep V1 frozen.
- **Files with PII:** `.completeFileProtection`, kept in a tmp folder that is swept on disappear
  (`ReportExporter.swift:46-57`, `ClientReportView.swift:76-80`).
- **Previews:** extend `PreviewFixtures` and build repositories outside `#Preview`
  (`PreviewFixtures.swift:111-156`).
- **Do not follow these:**
  - Cancel discards without confirmation (`ClientEditView.swift`, research Q5). Intake is long, so
    multi-step intake needs a discard confirmation when edits exist.
  - Nested editors that write straight into the parent's draft with no cancel
    (`WorkoutBuilderView.swift:71-80`).
  - Single-page `ImageRenderer` PDF (`ReportExporter.swift:30-40`). A waiver needs real text
    pagination.

## Design Decisions
1. **Configurability: fixed sections plus per-client toggles.** This keeps one typed data shape, so
   storage, archive and comparisons stay simple. Each assessment stores which sections were included.
   Editable templates are out of scope.
2. **Stable profile data lives on `Client`:** new optional fields in V3 for date of birth, emergency
   contact, physician, occupation, training history and availability. These rarely change and are not
   tracked over time. Existing `goal`/`injuries`/`notes` stay as they are.
3. **Screening is a dated `HealthScreening` model** linked by `clientId`. It holds the answers
   option set, history fields, lifestyle fields, `clearanceReceivedOn: Date?`, `completedOn` and notes.
   The clearance rule is a pure function: any YES with no clearance date means clearance is needed. The
   latest screening drives the flags and the review-due prompt (12 months).
4. **Movement and measurements live in a dated `Assessment` model** linked by `clientId`.
   - `includedSections` is an option set. Measurements are optional Doubles.
   - The overhead squat and single-leg squat compensation sets are Int option sets, split by view and
     side. Modified-test results are four option sets, plus notes per test.
   - Comparing against the previous assessment is a pure diff function.
   - Page 2 tests can be added later as new sections without migrating old data.
5. **The waiver is send-and-mark.** A `WaiverRecord` linked by `clientId` stores `sentOn`,
   `templateVersion`, `templateTextSnapshot` and `returnedSignedOn: Date?`. The snapshot keeps what was
   sent even after the template is edited.
6. **Waiver template:**
   - The trainer edits it in Settings. It starts from a built-in starter text with labelled sections:
     assumption of risk, release of ordinary negligence, medical acknowledgement, emergency consent,
     and signature/date/initials lines.
   - Every save bumps the version.
   - It is stored as one SwiftData `WaiverTemplate` row, so it is included in the archive.
   - Settings shows a fixed notice: "This template is not legal advice. Have it reviewed by your
     attorney or insurer."
   - The PDF includes the client name, the trainer name (from the self profile) and the template
     version.
7. **Sharing:** the waiver PDF is shared with `ShareLink`, like `ShareReportMenu`. It is not sent as an
   SMS compose attachment, because the share sheet already covers email, text and AirDrop. Marking it
   "sent" happens when the trainer taps Share. The share sheet doesn't confirm that the file was
   actually delivered.
8. **PDF pagination:** a new `WaiverPDFRenderer` built on `UIGraphicsPDFRenderer` with `NSAttributedString`
   text layout across multiple pages. `ReportExporter` is left untouched.
9. **Intake flow:**
   - "Start intake" is offered after a new client is saved, and from client detail.
   - It is a sheet that steps through the sections: section toggles → Profile → Health → Waiver →
     Measurements → Movement → Review.
   - Each step saves on Next, so partial intakes persist.
   - Cancel asks for confirmation if there are unsaved edits.
10. **Archive v2:** `ArchiveV2.Envelope` adds `healthScreenings`, `assessments`, `waivers` and
    `waiverTemplate`. The new Client fields go on the shared `ClientDTO` as optionals.
    - v1 files decode through the frozen V1 envelope and then `migrate` into V2.
    - Add a new golden `export-v2.json` fixture.
    - `deleteAll` and `upsertAll` cover the new types.
11. **Session screen** shows "Medical clearance recommended" in the injuries section when the flag is
    active. Detail sections reach the data through the client's repositories, with no new tab.

## What We're NOT Doing
- Importing, scanning, OCR or photo attachment of the paper form (per the user).
- E-signature or in-app signature capture, and storing the returned signed file. The signed copy lives
  outside the app.
- Editable question or assessment templates, and custom fields.
- Reproducing PAR-Q+ wording, or any claim that the screening is diagnostic.
- NASM compensation → overactive/underactive muscle suggestions or corrective programming. The sources
  were secondary and incomplete.
- Page 2 tests until the user provides the page.
- Email compose integration, any network or cloud sync, and HIPAA-style controls beyond the existing
  app lock and file protection.
- Minor/guardian waivers and per-state waiver variants.
- Charts of assessment measurements over time (possible follow-up). We only diff against the previous
  assessment.

## Open Risks
- **The V2→V3 migration is the first one with real data on users' devices.** There is no existing
  test that migrates an on-disk store (research, Open Areas). We need to add one, and rely on
  `StoreBackup` as the fallback.
- **The archive v2 migrate chain is new code** on the import path. Merge or replace for a v1 file into
  a v3 store must keep `goldenV1FixtureImports` green.
- **`ShareLink` gives no delivery confirmation**, so "sent on" means "shared on". The trainer can edit
  the date.
- **Health data size:** the store has no explicit file-protection class (research Q7). We'll check
  whether one should be set now that health data is stored. This is a possible small change in
  `PersistenceController`.
- **Page 2 of the form is unknown** and may add tests that don't fit the section model.
- **The waiver starter text is boilerplate** drawn from secondary sources. Enforceability varies by
  state, which the notice covers, but the wording still needs the user's review.
- **Scope is large.** Structure should slice it into vertical slices:
  1. profile and schema/archive groundwork
  2. health screening and clearance
  3. assessment
  4. waiver
  5. guided intake flow
