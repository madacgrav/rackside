# App Store listing — TrainMe 1.0.0

Paste each field into App Store Connect. Each field is the fenced block under its heading; `scripts/check-metadata-lengths.sh` checks the limits.

## Name

```text
TrainMe
```

## Subtitle

```text
Personal trainer client log
```

## Promotional Text

```text
Schedule sessions, log every set, run rest timers from your Apple Watch and show clients their progress — all private, all on your iPhone.
```

## Description

```text
TrainMe is the client and session log for independent personal trainers. Keep everything about your clients in one place, run sessions set by set, and show clients how far they've come — without accounts, subscriptions or the cloud.

CLIENTS AND INTAKE
• Client profiles with goals, injuries, emergency contact and physician
• Guided intake: profile, health screening, liability waiver and assessment, one step at a time
• Health screening that flags when medical clearance is recommended, shown on every session
• NASM-style Overhead Squat and Single-Leg Squat assessments plus measurements, with changes since last time
• Send your liability waiver as a PDF and track when it comes back signed

WORKOUTS AND SCHEDULING
• Reusable workout templates built from a 34-exercise starter library or your own exercises
• Day and week views of your schedule
• Weekly repeating sessions, with "this session only" or "this and following" edits
• Add sessions to your iPhone calendar
• Reminders 24 hours and 1 hour before each session, plus pre-written text reminders to clients

RUN THE SESSION
• Log sets in seconds, with last session's numbers alongside
• Rest timer starts automatically when you log a set
• Countdown for timed sets like planks that fills in the duration for you
• Client injuries and clearance warnings right on the session screen

APPLE WATCH
• See and control the rest timer on your wrist
• Start a rest or the next timed set from the watch
• Feel a tap when time is up

PROGRESS REPORTS
• Consistency, weekly volume and top exercises for each client
• Exercise history with personal bests and estimated 1RM
• Share reports with clients as PDF or image

PRIVATE BY DESIGN
• Your data stays on your iPhone — no account, no server, no tracking, no ads
• Face ID lock
• Export everything to a file for backup, and import it on a new phone

TrainMe is a record-keeping tool for fitness professionals. It does not provide medical advice, and its health screening is not a diagnosis.
```

## Keywords

```text
personal trainer,PT,client,workout log,fitness coach,session,NASM,assessment,rest timer,progress
```

## What's New in This Version

See `whats-new/1.0.0.md`.

## URLs

- **Support URL:** https://madacgrav.github.io/rackside/support/
- **Marketing URL:** https://madacgrav.github.io/rackside/
- **Privacy Policy URL:** https://madacgrav.github.io/rackside/privacy/

## Copyright

```text
2026 Adam (madacgrav)
```

> **Owner:** replace with your legal name (or business name) before submitting.

## Category

- **Primary:** Health & Fitness
- **Secondary:** Business

## Pricing

- **Price:** USD 0.99, all territories
- **In-app purchases:** none

## Age Rating

Answer **None / No** to every content question, including *Medical or Treatment Information* (TrainMe stores the trainer's own records and gives no medical advice) and *Unrestricted Web Access*. Expected rating: **4+**.

## App Privacy

**Data Not Collected.** TrainMe has no server, analytics, advertising or tracking; all data stays on the device, and anything that leaves it (calendar events, shared PDFs, text messages, export files) is sent by the user through iOS. This matches `Sources/PrivacyInfo.xcprivacy` (no collected data types, no tracking).

## Export Compliance

Uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption` = NO in both apps).

## Review Notes

```text
TrainMe has no login or account; all data is stored locally on the device.

To see the app with realistic data:
1. Download the attached file "TrainMe Review Sample.json" (also available at https://github.com/madacgrav/rackside/tree/main/docs/app-store) and save it to Files.
2. In TrainMe, open Settings > Import from file…, choose the file, then choose "Replace ALL data".
3. Open the Clients tab > Jordan Lee to see a client with intake, assessments and progress reports (View progress).

Face ID: TrainMe locks behind Face ID when it is set up; if Face ID is unavailable, the device passcode is used.

Apple Watch: open any session marked Scheduled on the iPhone (Schedule tab, or a client's Upcoming Sessions) and tap the ✓ on a set row to log it. A rest timer starts on the iPhone and appears in the TrainMe watch app, where it can be extended or skipped.

Permissions are optional: Notifications (session reminders) and Calendar (only when the trainer turns on "Add to iPhone calendar" for a session).
```

## Screenshots

Upload from `screenshots/`.

**iPhone 6.9" (1320 × 2868)**, in order:

| File | Caption |
|---|---|
| `01-schedule-week.png` | Your week at a glance |
| `02-session-timer.png` | Log sets fast, with a rest timer built in |
| `03-client-detail.png` | Everything about each client in one place |
| `04-progress-report.png` | Show clients their progress |
| `05-assessment.png` | Movement assessments that track change |
| `06-workout-builder.png` | Build workouts once, reuse them forever |

**Apple Watch (422 × 514):**

| File | Caption |
|---|---|
| `w1-timer-running.png` | Rest timer on your wrist |
| `w2-quick-start.png` | Start the next set from your watch |

Regenerate with `scripts/screenshots.sh` (run it in the morning for the most natural session times).
