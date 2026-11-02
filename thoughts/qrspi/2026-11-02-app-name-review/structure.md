# Structure Outline

## Approach
Rename TrainMe → Rackside in four slices, from what the user sees outward: the running app first,
then the build identity, then URLs, then prose. Bundle IDs, the logger subsystem and
`TrainMeMigrationPlan` never change. Targeted per-file edits, no tree-wide `sed`.

Correction to design: `*.xcodeproj` is gitignored (`.gitignore:11`), so the regenerated
`Rackside.xcodeproj` is not committed and there is no old project to delete from git. Delete the local
`TrainMe.xcodeproj` after regenerating.

## Phase 1: App shows "Rackside"
Every string a user sees on the phone, watch, exported report and export file says Rackside.
Project, scheme and module names are untouched, so the build commands are unchanged.

**Files**: `Sources/Info.plist`, `project.yml` (line 47 only), `Sources/Services/AppLock.swift`,
`Sources/Features/Lock/LockGateView.swift`, `Sources/TrainMeApp.swift` (line 118 string only),
`Sources/Features/Settings/SettingsView.swift`, `Sources/Services/ReportExporter.swift`,
`Sources/Services/TimerNotificationService.swift`, `Watch/WatchNotifier.swift`,
`Sources/Services/Archive/DataArchive.swift`

**Key changes**:
- `CFBundleDisplayName` = `Rackside` (`Info.plist:22`); `INFOPLIST_KEY_CFBundleDisplayName: Rackside` (`project.yml:47`)
- Calendar and Face ID usage descriptions (`Info.plist:28, 30`)
- `localizedReason: "Unlock Rackside"`; lock title `"Rackside is locked"`; store alert title
- Import error strings (`SettingsView.swift:216, 220`)
- `Text("Rackside Progress Report")` ×2
- Notification body `"Log the set in Rackside."` ×2
- Export file name `"Rackside Export \(day).json"`

**Verify**: `xcodegen generate && xcodebuild -scheme TrainMe test` passes (no test pins these strings);
`grep -rn "TrainMe" Sources Watch` returns only type names, `TrainMeMigrationPlan`, and `@testable`-free
internal hits. Manual: simulator home screen and watch show "Rackside"; Settings › Export writes
`Rackside Export <date>.json`; an old `TrainMe Export` file still imports.

---

## Phase 2: Project builds as Rackside
The Xcode project, targets, schemes, app entry types, test module, CI and screenshot script use the
new name. Bundle IDs unchanged.

**Files**: `project.yml`, `Sources/TrainMe.entitlements` → `Sources/Rackside.entitlements`,
`Sources/TrainMeApp.swift` → `Sources/RacksideApp.swift`, `Watch/TrainMeWatchApp.swift` →
`Watch/RacksideWatchApp.swift`, all 43 `Tests/*.swift` imports, `Tests/ReportingTests.swift:61`,
`.github/workflows/ci.yml`, `scripts/screenshots.sh`, `README.md` build section (lines 30, 33, 39)

**Key changes**:
- `project.yml`: `name: Rackside`; targets `Rackside`, `RacksideWatch`, `RacksideTests`; schemes and
  target refs to match; `CODE_SIGN_ENTITLEMENTS: Sources/Rackside.entitlements`; bundle IDs and
  `WKCompanionAppBundleIdentifier` **unchanged**; no `PRODUCT_NAME` override
- `struct RacksideApp: App`, `struct RacksideWatchApp: App`
- `@testable import Rackside`; `Rackside.Unit`
- CI `-scheme Rackside` / `-scheme RacksideWatch`
- `screenshots.sh`: scheme `Rackside`, `Rackside.app`, `Watch/RacksideWatch.app`; bundle IDs unchanged
- `TrainMeMigrationPlan` and `Log.swift` subsystem **unchanged**
- Use `git mv` for the three renamed files

**Verify**: `rm -rf TrainMe.xcodeproj && xcodegen generate` creates `Rackside.xcodeproj`;
`xcodebuild -scheme Rackside test` and `xcodebuild -scheme RacksideWatch build` pass.
Manual: install on the owner's iPhone (madphone) over the existing TrainMe install; existing clients
and sessions appear (same bundle ID, SchemaV3 store); watch app installs and mirrors a rest timer.

---

## Phase 3: Links point at rackside
All in-app, docs and metadata URLs use `madacgrav/rackside` and `madacgrav.github.io/rackside/`.
The GitHub repo rename itself is an owner action, done between this phase's commit and merge.

**Files**: `Sources/Support/AppInfo.swift`, `Tests/AppInfoTests.swift`, `docs/_config.yml`,
`scripts/check-docs-links.sh`, `README.md` (lines 3, 11-12), `docs/support.md:11`,
`docs/app-store/metadata.md` (78-80, 118), `docs/app-store/checklist.md:14`, `CHANGELOG.md:11`

**Key changes**:
- `AppInfo` base `https://madacgrav.github.io/rackside/`; licence `https://github.com/madacgrav/rackside/blob/main/LICENSE`
- `AppInfoTests` expects `.../rackside/privacy/`
- `baseurl: /rackside`; `title: Rackside`
- `check-docs-links.sh:16` maps `/rackside/*` → `docs/`
- CHANGELOG historical `/pull/N` and compare links **left as-is** (GitHub redirects)

**Verify**: `xcodebuild -scheme Rackside test` passes (AppInfoTests); `scripts/check-docs-links.sh`
passes. After the owner renames the repo: `git remote set-url origin https://github.com/madacgrav/rackside.git`,
CI runs green on the renamed repo, Pages (once enabled) serves `/rackside/`, `/guide/`, `/privacy/`, `/support/`.

---

## Phase 4: Docs and App Store kit read Rackside
Every remaining prose "TrainMe" in docs, App Store kit and product docs becomes Rackside, and the
rename is recorded in the changelog.

**Files**: `docs/index.md`, `docs/privacy.md`, `docs/support.md`, `docs/guide/*.md` (10 files),
`docs/app-store/metadata.md`, `docs/app-store/checklist.md`, `docs/app-store/whats-new/1.0.0.md`,
`docs/app-store/TrainMe Review Sample.json` → `Rackside Review Sample.json`, `README.md`, `PRD.md`,
`BACKLOG.md`, `CHANGELOG.md` → `scripts/sync-changelog.sh` → `docs/changelog.md`

**Key changes**:
- `metadata.md` Name field `Rackside`; description, review notes and sample filename updated
- `checklist.md`: app name *Rackside*, SKU `rackside-ios`, `Rackside.xcodeproj`; bundle ID line unchanged
- CHANGELOG `[Unreleased] — 1.0.0`: "Renamed the app to Rackside" entry
- `thoughts/qrspi/*` historical artifacts **not** edited

**Verify**: `scripts/check-metadata-lengths.sh`, `check-docs-links.sh`, `check-guide-labels.sh` pass.
`grep -rIi trainme --exclude-dir={build,thoughts,.git} .` returns only: bundle IDs (`project.yml`,
`screenshots.sh`, `checklist.md`), `Log.swift` subsystem, `TrainMeMigrationPlan` refs, and CHANGELOG
historical PR/compare links.

## Testing Checkpoints

| After | True |
|-------|------|
| Phase 1 | App and watch display "Rackside"; all 14 user-visible strings renamed; tests pass with old scheme `TrainMe`. |
| Phase 2 | `Rackside.xcodeproj` generated; schemes `Rackside` / `RacksideWatch` build and test; CI and screenshot script use new names; owner's phone keeps its data after install. |
| Phase 3 | All URLs say `rackside`; AppInfoTests and docs link check pass; repo rename and remote update pending owner action. |
| Phase 4 | No "TrainMe" left except the documented internal exceptions; all three docs checks pass; changelog records the rename. |

Each phase leaves the app buildable and shippable on its own: stopping after Phase 1 already gives a
correctly named app on the device.
