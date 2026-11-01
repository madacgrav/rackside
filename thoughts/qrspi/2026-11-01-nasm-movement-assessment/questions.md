# Research Questions

## Context
Focus on the SwiftUI + SwiftData app under `Sources/`: the `Client` model and Clients feature screens,
the versioned schemas in `Sources/Persistence/`, the JSON archive under `Sources/Services/Archive/`,
reporting/export, and the tests in `Tests/`.

## Questions
1. How is the `Client` model defined, and how do `ClientEditView`/`ClientEditViewModel` and
   `ClientDetailView`/`ClientDetailViewModel` load, edit, validate and save its fields? Which sections
   does the client detail screen show, and how does it reach related records such as sessions?
2. How are one-to-many relationships between models declared (e.g. Client → Session, Session →
   SetRecord)? Cover delete rules, inverses, ordering, and how repositories query child records.
3. How are `SchemaV1` and `SchemaV2` and the migration plan structured? What changed between versions,
   and how is `SchemaTests` set up to check them?
4. How does the JSON export/import archive (`ArchiveV1`, `DataArchive`, `SafeImporter`, the DTOs) map
   models to DTOs and back? How is versioning handled, and how do `ArchiveRoundTripTests` and the
   `export-v1.json` fixture check it?
5. How do existing forms present structured, repeated inputs (toggles, steppers, pickers, set tables
   such as `SetTableView`/`SetDraft`, `MetricStepper`)? How do they model draft state before saving?
6. How do `ReportingQueries`, `ClientReportView` and `ReportExporter` build and share per-client
   output? Are there patterns for comparing a client's records across dates?
7. How are client health-related fields (`goal`, `injuries`, `notes`) shown during a session
   (`SessionRunView`), and how does the app protect sensitive data (app lock, local-only storage)?

## Follow-up Questions (added 2026-11-01)
8. How does `MessagingService` (and any compose-sheet wrappers) present SMS/email to a client? What
   content can it carry (body, attachments), how is it triggered from screens, and how is it tested?
   Which other outbound paths exist (`ShareLink`, `ReportExporter` files, calendar)?
9. Does the app have any capability to capture handwriting or signatures (PencilKit, Canvas, drawing
   gestures), render user-entered content to PDF, or store binary blobs (images, PDFs) in SwiftData or
   on disk? How does `ReportExporter` lay out multi-section printable pages?
10. (External) Which data points do personal-training industry sources (NASM, ACE, ACSM, PAR-Q+)
    recommend collecting at client intake, beyond movement assessments? Cover health screening,
    medical history, lifestyle, goals and emergency contacts. Which elements do fitness liability
    waivers / informed-consent forms typically contain, and what is generally said about e-signatures
    and record retention for them?
