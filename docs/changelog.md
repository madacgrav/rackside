---
title: Changelog
permalink: /changelog/
---

# Changelog

All notable changes to TrainMe are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions before 1.0.0 were development builds and were not released on the App Store.

## [Unreleased] — 1.0.0

### Added
- Settings › About: version, user guide, what's new, privacy policy, support and license.

### Changed
- TrainMe is now an iPhone-only app (with its Apple Watch companion).
- The iPhone and Apple Watch apps now share one version number.

### Fixed
- The Apple Watch now shows the running rest or timed-set countdown instead of the quick-start buttons.

## [0.6.0] — 2026-11-02

### Added
- Rest timer: logging a set starts a rest countdown at the bottom of the session screen. Add time, skip, or pick a different length.
- Countdown for timed sets (like planks) that fills in the duration when it finishes.
- Timers keep running when you lock your phone, switch apps or relaunch TrainMe, and alert you when time is up.
- **Apple Watch app**: see the running timer on your wrist, add time or skip, start a rest or the next timed set from the watch, and feel a tap when the timer reaches zero. ([#42](https://github.com/madacgrav/trainme/pull/42))

## [0.5.0] — 2026-11-01

### Added
- Client intake ([#41](https://github.com/madacgrav/trainme/pull/41)):
  - Extended client profile: date of birth, emergency contact, physician, occupation, training history and availability.
  - Health screening with a medical-clearance flag shown on the client and in sessions.
  - NASM Overhead Squat and Single-Leg Squat movement assessments, plus measurements (vitals, body, fitness tests), with changes since the previous assessment.
  - Liability waiver: send it to a client as a PDF, mark it signed and returned, and edit the waiver template in Settings.
  - A guided intake flow, offered after you add a client and from the client's menu.

### Fixed
- The waiver screen could hang on some devices.

## [0.4.0] — 2026-11-01

### Added
- Week view on the Schedule tab, with previous/next week and Today buttons. TrainMe remembers whether you prefer day or week view. ([#40](https://github.com/madacgrav/trainme/pull/40))
- Repeating sessions can be edited, cancelled or deleted for "this session only" or "this and following sessions", and your calendar stays in sync. ([#39](https://github.com/madacgrav/trainme/pull/39))

## [0.3.0] — 2026-10-27

### Added
- Progress reports: total reps per exercise, an exercise detail screen with history and estimated 1RM, consistency over a chosen window, weekly volume, top exercises, and a PNG export alongside the PDF. ([#34](https://github.com/madacgrav/trainme/pull/34))
- "About you": add yourself as a client to track your own training. ([#36](https://github.com/madacgrav/trainme/pull/36))

### Changed
- Refreshed look across the app, with an inline set table in the session screen. ([#36](https://github.com/madacgrav/trainme/pull/36))
- Dark, tinted and clear app icon variants.
- Better support for larger text sizes and VoiceOver labels in reports.

## [0.2.0] — 2026-10-26

### Added
- App icon and accent colour. ([#31](https://github.com/madacgrav/trainme/pull/31))
- Edit and delete an existing session.
- A reminder to back up when your last export is more than 14 days or 5 sessions old.
- The session screen shows the client's injuries, and session notes can be edited there.
- Each exercise keeps its own weight unit (lb or kg) everywhere it appears.
- Permissions rows in Settings for notifications and calendar. ([#32](https://github.com/madacgrav/trainme/pull/32))
- TrainMe backs up your data automatically before an app update changes how it is stored.

### Changed
- Destructive actions now ask for confirmation, and failed saves are shown instead of silently ignored.
- Replacing all data from an import file can now be undone automatically if the import fails.
- Adding a session to your calendar falls back to any writable calendar when there is no default.

### Fixed
- A repeating series now creates the number of weeks you chose, without an extra calendar event. ([#2](https://github.com/madacgrav/trainme/pull/2))
- Deleting a session also deletes its recorded sets.
- The Face ID prompt no longer appears twice.
- Cancelled sessions no longer send reminders.
- Restoring a backup works reliably.

## [0.1.0] — 2026-07-09

### Added
- The first version of TrainMe ([#1](https://github.com/madacgrav/trainme/pull/1)):
  - Clients with contact details, goals, injuries and notes.
  - An exercise library with 34 starter exercises, plus your own.
  - Reusable workout templates.
  - Scheduling, with weekly repeats and an option to add sessions to your iPhone calendar.
  - Recording sessions set by set.
  - History and progress charts per client and exercise.
  - Session reminders, and pre-filled text reminders to clients.
  - Sharing progress reports as PDF.
  - Export and import of all data as a file.
  - Face ID lock, and a recovery screen if the data store can't be opened.

[Unreleased]: https://github.com/madacgrav/trainme/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/madacgrav/trainme/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/madacgrav/trainme/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/madacgrav/trainme/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/madacgrav/trainme/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/madacgrav/trainme/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/madacgrav/trainme/releases/tag/v0.1.0
