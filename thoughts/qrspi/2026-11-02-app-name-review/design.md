# Design Discussion

## Current State

The app ships under the name **TrainMe** on iPhone and Apple Watch. The 1.0.0 App Store
submission kit is merged but no App Store Connect record exists yet (`docs/app-store/checklist.md:20`).

**The name is in use by others** (research Q7, web sources only):

- A French coach-booking marketplace, TrainMe (trainme.co, Decathlon-linked), with two active
  App Store apps (ids 1165978033, 1542215145), Health & Fitness / Sports.
- "TrainMe: Home & Gym Workout" (Appstack Technologies, id 6467795772), USD-priced, Health & Fitness.
- A pending USPTO Class 9 application **TRAINME**, Train-Me LLC, filed 2026-07-23, for an app that
  schedules sports training sessions.

**Where the name lives in the repo** (research Q1–Q5):

- 14 user-visible strings, all literal, no shared constant and no localisation table:
  `Sources/Info.plist:22, 28, 30`; `project.yml:47`; `AppLock.swift:42`; `LockGateView.swift:48`;
  `TrainMeApp.swift:118`; `SettingsView.swift:216, 220`; `ReportExporter.swift:77, 115`;
  `TimerNotificationService.swift:16`; `Watch/WatchNotifier.swift:24`; `DataArchive.swift:36`.
- Project identity: `project.yml:1, 14, 27, 30, 31, 51, 56, 61-70` (project, targets, schemes,
  entitlements path); `Sources/TrainMe.entitlements` (empty dict); `Sources/TrainMeApp.swift:74`;
  `Watch/TrainMeWatchApp.swift:4`; CI `.github/workflows/ci.yml:24, 30`; `scripts/screenshots.sh:42-45`.
- Test module: 43 `@testable import TrainMe` lines plus `TrainMe.Unit` (`Tests/ReportingTests.swift:61`).
- Persistence/logging internals: `TrainMeMigrationPlan` (`SchemaV1.swift:216`, `PersistenceController.swift:20`,
  two tests); logger subsystem `"com.madacgrav.trainme"` (`Log.swift:5`).
- Bundle IDs `com.madacgrav.trainme` / `.watchkitapp` (`project.yml:22, 45, 48`; `scripts/screenshots.sh:96, 110`;
  `checklist.md:20`). The sandbox, UserDefaults, permissions and watch pairing all hang off these implicitly
  (research Q2); nothing in Swift reads the bundle ID.
- External identity: GitHub repo `madacgrav/trainme`; Pages `baseurl: /trainme` (`docs/_config.yml:4`);
  `AppInfo.swift:15, 20`; `Tests/AppInfoTests.swift:22`; `scripts/check-docs-links.sh:16`;
  CHANGELOG compare/PR links; `metadata.md:78-80, 118`; `README.md:3, 11-12`; `docs/support.md:11`.
- Docs prose: ~150 matching lines across `docs/`, `README.md`, `CHANGELOG.md`, `PRD.md`, `BACKLOG.md`
  (research Q4 table). `metadata.md` Name field and description; `TrainMe Review Sample.json` filename.
- Icon, asset catalogs and screenshots carry no wordmark (research Q5). The exported progress report
  header does (`ReportExporter.swift:77, 115`).
- Archive format is name-agnostic: body, UTType and validation never reference the name
  (research Q3). Only the default export filename and two Settings error strings do.

## Desired End State

The app is called **Rackside** everywhere a user, reviewer or visitor can see it, and the project,
repo and docs site carry the same name. Bundle identifiers stay `com.madacgrav.trainme` and
`com.madacgrav.trainme.watchkitapp`, so the owner's phone keeps its data, permissions and watch pairing.

Verification:

1. `grep -rIi trainme` over `Sources/ Watch/ Shared/ docs/ scripts/ .github/ README.md CHANGELOG.md project.yml`
   returns only: the two bundle IDs and `WKCompanionAppBundleIdentifier` in `project.yml`, the bundle IDs
   in `scripts/screenshots.sh` and `docs/app-store/checklist.md`, the logger subsystem in `Log.swift`,
   `TrainMeMigrationPlan` references, and historical PR/compare links in `CHANGELOG.md`.
2. `xcodegen generate` produces `Rackside.xcodeproj`; both schemes build; the test target passes
   (`xcodebuild -scheme Rackside test`).
3. Installing the new build over the existing TrainMe install on the owner's iPhone opens the existing
   store (same bundle ID, SchemaV3) and the watch app still pairs.
4. Home screen shows "Rackside" on iPhone and watch; permission prompts, lock screen, alerts, timer
   notifications and the progress report header say Rackside; export file is `Rackside Export <date>.json`.
5. `scripts/check-metadata-lengths.sh`, `check-docs-links.sh`, `check-guide-labels.sh` all pass.
   Docs site renders at `https://madacgrav.github.io/rackside/` once Pages is enabled.
6. Fresh screenshots are not required (no wordmark in captures), but `screenshots.sh` runs end-to-end
   with the new scheme and bundle IDs.

## Patterns to Follow

- **XcodeGen is the source of truth.** All target, scheme and plist-key changes go in `project.yml`
  (`project.yml:1-70`); never hand-edit `TrainMe.xcodeproj`. Regenerate and commit the new `.xcodeproj`
  the same way earlier phases did.
- **Hand-written iPhone plist, generated watch plist.** iPhone display name is the literal at
  `Sources/Info.plist:22`; watch display name is `INFOPLIST_KEY_CFBundleDisplayName` at `project.yml:47`.
  Change both; do not introduce `PRODUCT_NAME` overrides.
- **Frozen schema and archive files stay frozen.** `SchemaV1`/`V2`/`V3` and `ArchiveV1`/`V2` are marked
  FROZEN. The rename must not touch their bodies. `TrainMeMigrationPlan` (`SchemaV1.swift:216`) is
  internal and is deliberately left as-is (decision 4).
- **Strings are literal, one per call site.** There is no `AppInfo.name`; follow the existing style and
  replace each literal in place rather than introducing an indirection the rest of the app doesn't use.
  (Introducing a constant is cheap but out of scope; see "Not Doing".)
- **Docs link check maps absolute paths.** `scripts/check-docs-links.sh:16` hard-codes `/trainme/`;
  update to `/rackside/` alongside `docs/_config.yml:4`.
- **Changelog sync.** Edit `CHANGELOG.md`, then run `scripts/sync-changelog.sh` to regenerate
  `docs/changelog.md`; never edit the generated copy directly.
- **Guide label check.** `check-guide-labels.sh` requires backticked UI labels in `docs/guide/*.md` to
  exist as `"label` literals in code. None of the 14 renamed strings are backticked labels, but run the
  script after the docs pass.
- **Anti-pattern to avoid:** blind `sed s/TrainMe/Rackside/g` across the tree. It would rewrite the
  bundle IDs, the logger subsystem, `TrainMeMigrationPlan`, historical PR links and the frozen
  fixtures' comments. Do targeted edits per file class.

## Design Decisions

1. **New name: Rackside.** Chosen over Trainbook, Liftledger and PT Ledger. Web search found no app,
   company or trademark using it; nearest names (Rackd Life, RackCoach) are not matches. Short, gym-flavoured,
   fits the 30-char App Store name limit with room for a suffix later. Trademark registries were not
   queried directly; see Open Risks.
2. **Bundle identifiers unchanged.** `com.madacgrav.trainme` and `.watchkitapp` stay. They are never
   user-visible, no App Store record exists yet so there is nothing to reconcile, and changing them would
   give the owner's phone a fresh empty sandbox (research Q2, platform note). The checklist line that
   quotes the bundle ID (`checklist.md:20`) stays correct.
3. **Rename GitHub repo and Pages path.** Repo becomes `madacgrav/rackside`; GitHub redirects the old
   URL. `docs/_config.yml` baseurl → `/rackside`; `AppInfo.swift:15, 20`, `AppInfoTests.swift:22`,
   `check-docs-links.sh:16`, `metadata.md:78-80, 118`, `README.md:3, 11-12`, `docs/support.md:11` and
   the CHANGELOG site link (`CHANGELOG.md:11`) follow. Historical `github.com/madacgrav/trainme/pull/N`
   and compare links in CHANGELOG are left alone: they redirect and are part of the record.
4. **Rename scope: user-facing strings + project identity, not persistence internals.** Rename the 14
   user-visible strings, project/target/scheme names, entitlements filename, `TrainMeApp` →
   `RacksideApp`, `TrainMeWatchApp` → `RacksideWatchApp`, CI schemes, `screenshots.sh` scheme and
   `.app` names, and the test module (`@testable import Rackside`, `Rackside.Unit`). Leave
   `TrainMeMigrationPlan` and the `Log.swift` subsystem string untouched: both are internal, the
   subsystem matches the unchanged bundle ID, and renaming the migration plan touches a file marked FROZEN.
5. **Docs and App Store kit get a full prose pass.** Every "TrainMe" in `docs/`, `README.md`, `PRD.md`,
   `BACKLOG.md`, `metadata.md`, `checklist.md`, `whats-new/1.0.0.md` becomes "Rackside";
   `TrainMe Review Sample.json` is renamed `Rackside Review Sample.json` and its reference in
   `metadata.md:118` updated. `CHANGELOG.md` gets an entry under `[Unreleased] — 1.0.0` recording the rename.
6. **No new screenshots.** Captures contain no wordmark (research Q5); the home-screen name is not in any
   capture. `screenshots.sh` is updated so it still runs, but re-running it is optional.
7. **Export filename changes with the name.** `DataArchive.swift:36` → `"Rackside Export <date>.json"`.
   Import is filename-agnostic (research Q3), so old `TrainMe Export` files still import.

## What We're NOT Doing

- Not changing bundle identifiers, the logger subsystem, or `TrainMeMigrationPlan`.
- Not changing the data store, archive schema, archive fixtures, or any FROZEN file.
- Not introducing an `AppInfo.name` constant or a localisation table.
- Not redesigning the icon or adding a wordmark.
- Not re-shooting App Store screenshots (optional, not required).
- Not rewriting historical CHANGELOG PR/compare links or old `thoughts/qrspi/*` artifacts.
- Not filing a trademark, registering domains, or doing a formal clearance search.
- Not changing the licence or copyright name (separate checklist items).
- Not touching App Store Connect (no record exists; the checklist already covers creating it with the
  app name, which will now read Rackside).

## Open Risks

- **Trademark clearance is web-search only.** USPTO TSDR, EUIPO, UK IPO and WIPO were not queried
  directly for RACKSIDE. A formal search or a lawyer's clearance is the owner's call before submission.
- **App Store name uniqueness.** Apple enforces unique app names per storefront at record creation.
  Web search found no "Rackside" app, but the in-store check happens only when the record is created
  (`checklist.md:20`). If it fails, fallback candidates that also came up clear: Trainbook, Liftledger,
  PT Ledger.
- **Repo rename side effects.** Local clones keep working via redirect, but `git remote set-url` is
  needed to avoid relying on it. Any CI badge or Pages setting referencing the old path must be
  re-checked after the GitHub rename. Pages must be (re)enabled on the renamed repo.
- **`xcodegen generate` output.** Renaming the project name produces `Rackside.xcodeproj`; the old
  `TrainMe.xcodeproj` must be deleted from git, and `build/` DerivedData from the old scheme is stale.
- **Watch display name length.** "Rackside" is 8 chars; fine for the watch home screen, but verify in
  the simulator that it isn't truncated under the icon.
- **Screenshot script byte/size checks** are unaffected by the rename, but the script's hard-coded
  `.app` paths (`screenshots.sh:44-45`) will break if the product name and target name diverge.
  Keep `PRODUCT_NAME` defaulting to the target name.
