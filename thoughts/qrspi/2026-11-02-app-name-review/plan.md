# Implementation Plan

## Overview
Rename the app from TrainMe to **Rackside** everywhere a user, reviewer or site visitor sees it, and
rename the Xcode project, targets, schemes, test module, repo and docs site path to match. Bundle IDs
(`com.madacgrav.trainme`, `com.madacgrav.trainme.watchkitapp`), the logger subsystem in
`Sources/Support/Log.swift:5`, and `TrainMeMigrationPlan` stay unchanged.

**Rules for every phase**
- Targeted edits per file. Never run a tree-wide `sed s/TrainMe/Rackside/`.
- Never touch: bundle ID strings, `Log.swift`, `TrainMeMigrationPlan` (any file), `Sources/Persistence/SchemaV*.swift`,
  `Sources/Services/Archive/ArchiveV*.swift`, `Tests/Fixtures/*`, anything under `thoughts/` or `build/`.
- Historical GitHub links (`github.com/madacgrav/trainme/pull/…`, `/issues/…`, `/compare/…`,
  `/releases/…`) are left as-is everywhere; GitHub redirects them after the repo rename.
- `*.xcodeproj` is gitignored (`.gitignore:11`). Regenerate with `xcodegen generate`; never commit it.
- One commit per phase, message `Phase N: <name>`, ending with the attribution line from the session.

**Test command** (from `README.md` and `.github/workflows/ci.yml`; scheme name changes in Phase 2):
```bash
xcodegen generate
xcodebuild -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -scheme <Scheme>Watch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
If `xcodebuild` says it "requires Xcode", prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
If `xcodegen` is unavailable, `brew install xcodegen`; there is no manual fallback for the project file.

---

## Phase 1: App shows "Rackside"

### Changes

#### 1. Home-screen names
**File**: `Sources/Info.plist` — modify
- Line 22: `<string>TrainMe</string>` under `CFBundleDisplayName` → `<string>Rackside</string>`
- Line 28: `TrainMe adds your training sessions…` → `Rackside adds your training sessions to your calendar and removes them when cancelled.`
- Line 30: `TrainMe locks your client data behind Face ID.` → `Rackside locks your client data behind Face ID.`

**File**: `project.yml` — modify line 47 only
```yaml
        INFOPLIST_KEY_CFBundleDisplayName: Rackside
```

#### 2. In-app strings
| File | Line | New text |
|------|------|----------|
| `Sources/Services/AppLock.swift` | 42 | `localizedReason: "Unlock Rackside"` |
| `Sources/Features/Lock/LockGateView.swift` | 48 | `title: "Rackside is locked",` |
| `Sources/TrainMeApp.swift` | 118 | `title: "Rackside couldn't open its data store",` (string only; struct name stays this phase) |
| `Sources/Features/Settings/SettingsView.swift` | 216 | `"This file was exported by a newer version of Rackside. Update the app first."` |
| `Sources/Features/Settings/SettingsView.swift` | 220 | `"Import failed: the file isn't a valid Rackside export."` |
| `Sources/Services/ReportExporter.swift` | 77, 115 | `Text("Rackside Progress Report")` |
| `Sources/Services/TimerNotificationService.swift` | 16 | `case .timedSet: ("Timed set done", "Log the set in Rackside.")` |
| `Watch/WatchNotifier.swift` | 24 | `… : "Log the set in Rackside."` |
| `Sources/Services/Archive/DataArchive.swift` | 36 | `appending(path: "Rackside Export \(day).json")` |

### Verification
#### Automated
- [x] `xcodegen generate && xcodebuild -scheme TrainMe -destination 'platform=iOS Simulator,name=iPhone 17' test` passes
- [x] `xcodebuild -scheme TrainMeWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeds
- [x] `grep -rn '"[^"]*TrainMe' Sources Watch` returns no string literals
- [x] `grep -n TrainMe Sources/Info.plist project.yml | grep -v -e 'TrainMe:' -e TrainMeWatch -e TrainMeTests -e 'name: TrainMe' -e entitlements` returns nothing

#### Manual
- [ ] iPhone simulator home screen shows "Rackside"; watch simulator shows "Rackside"
- [ ] Settings › Export offers `Rackside Export <yyyy-MM-dd>.json`
- [ ] Importing an older `TrainMe Export …json` still succeeds (filename is never checked)
- [ ] A shared progress report PDF shows "Rackside Progress Report"

---

## Phase 2: Project builds as Rackside

### Changes

#### 1. File renames (use `git mv`)
```bash
git mv Sources/TrainMe.entitlements Sources/Rackside.entitlements
git mv Sources/TrainMeApp.swift Sources/RacksideApp.swift
git mv Watch/TrainMeWatchApp.swift Watch/RacksideWatchApp.swift
```

#### 2. Entry types
- `Sources/RacksideApp.swift:74`: `struct TrainMeApp: App` → `struct RacksideApp: App`
- `Watch/RacksideWatchApp.swift:4`: `struct TrainMeWatchApp: App` → `struct RacksideWatchApp: App`
- `grep -rn 'TrainMeApp\b\|TrainMeWatchApp' Sources Watch Tests` afterwards must return nothing (fix any preview/test reference found).

#### 3. `project.yml`
Change names only; leave bundle IDs and `WKCompanionAppBundleIdentifier` exactly as they are.
```yaml
name: Rackside
...
targets:
  Rackside:
    ...
        CODE_SIGN_ENTITLEMENTS: Sources/Rackside.entitlements
    dependencies:
      - target: RacksideWatch
  RacksideWatch:
    ...
  RacksideTests:
    ...
    dependencies:
      - target: Rackside
schemes:
  Rackside:
    build:
      targets:
        Rackside: all
    test:
      targets: [RacksideTests]
  RacksideWatch:
    build:
      targets:
        RacksideWatch: all
```
Do not add `PRODUCT_NAME`; it defaults to the target name, which `screenshots.sh` relies on.

#### 4. Test module
```bash
grep -rl '^@testable import TrainMe$' Tests | xargs sed -i '' 's/^@testable import TrainMe$/@testable import Rackside/'
```
- `Tests/ReportingTests.swift:61`: `unit: TrainMe.Unit` → `unit: Rackside.Unit`
- Leave `TrainMeMigrationPlan` references in `Tests/SchemaTests.swift:12-13` and `Tests/MigrationTests.swift:19`.

#### 5. CI
**File**: `.github/workflows/ci.yml` — line 24 `-scheme Rackside`, line 30 `-scheme RacksideWatch`.

#### 6. Screenshot script
**File**: `scripts/screenshots.sh`
- Line 42: `xcodebuild -scheme Rackside …`
- Line 44: `APP="$DERIVED/Build/Products/Debug-iphonesimulator/Rackside.app"`
- Line 45: `WAPP="$APP/Watch/RacksideWatch.app"`
- Lines 96, 110: bundle IDs unchanged.

#### 7. README build section
**File**: `README.md` — line 23 `Rackside.xcodeproj`, lines 30/33 `open Rackside.xcodeproj` and **Rackside** scheme, line 39 `-scheme Rackside`.

#### 8. Regenerate locally
```bash
rm -rf TrainMe.xcodeproj
xcodegen generate   # creates Rackside.xcodeproj (gitignored)
```

### Verification
#### Automated
- [x] `ls Rackside.xcodeproj` exists; `ls TrainMe.xcodeproj` fails
- [x] `xcodebuild -scheme Rackside -destination 'platform=iOS Simulator,name=iPhone 17' test` passes
- [x] `xcodebuild -scheme RacksideWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeds
- [x] `grep -n 'com.madacgrav.trainme' project.yml` still shows lines 22, 45, 48
- [x] `grep -rn 'TrainMe' Sources Watch Tests .github scripts project.yml` returns only `TrainMeMigrationPlan` refs and the `Log.swift` subsystem

#### Manual (owner's iPhone "madphone", UDID `00008140-001E31AE21DB001C`)
- [x] Build and install over the existing app:
  ```bash
  xcodebuild -project Rackside.xcodeproj -scheme Rackside -configuration Debug -destination 'id=00008140-001E31AE21DB001C' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
  ```
  ```bash
  xcrun devicectl device install app --device 00008140-001E31AE21DB001C build/DerivedData/Build/Products/Debug-iphoneos/Rackside.app
  ```
- [x] Home screen shows one "Rackside" icon (it replaces TrainMe, not a second app)
- [x] Existing clients and sessions are present; no Face ID or calendar re-prompt
- [ ] Watch app installs and mirrors a rest timer started on the phone

---

## Phase 3: Links point at rackside

### Changes

#### 1. In-app URLs
**File**: `Sources/Support/AppInfo.swift`
```swift
    private static let base = URL(string: "https://madacgrav.github.io/rackside/")!
    ...
    static let license = URL(string: "https://github.com/madacgrav/rackside/blob/main/LICENSE")!
```
**File**: `Tests/AppInfoTests.swift:22`
```swift
    #expect(AppLinks.privacy.absoluteString == "https://madacgrav.github.io/rackside/privacy/")
```

#### 2. Docs site config and link check
- `docs/_config.yml`: line 1 `title: Rackside`, line 4 `baseurl: /rackside`
- `scripts/check-docs-links.sh:16`:
  ```bash
  if [[ "$link" == /rackside/* ]]; then target="docs/${link#/rackside/}"; else target="$dir/$link"; fi
  ```

#### 3. Current (non-historical) links
| File | Line(s) | Change |
|------|---------|--------|
| `README.md` | 3 | CI badge → `github.com/madacgrav/rackside/actions/...` |
| `README.md` | 11-12 | guide, privacy, support → `madacgrav.github.io/rackside/...` |
| `docs/support.md` | 11 | issues link → `github.com/madacgrav/rackside/issues` |
| `docs/app-store/metadata.md` | 78-80 | support / marketing / privacy URLs → `madacgrav.github.io/rackside/...` |
| `docs/app-store/metadata.md` | 118 | sample-file URL → `github.com/madacgrav/rackside/tree/main/docs/app-store` |
| `docs/app-store/checklist.md` | 14 | `https://madacgrav.github.io/rackside/` |
| `CHANGELOG.md` | 11 | `[madacgrav.github.io/rackside](https://madacgrav.github.io/rackside/)` |

Leave PR, issue, compare and release links in `CHANGELOG.md` and `BACKLOG.md` unchanged.

#### 4. Repo rename (owner action, between commit and merge)
Add to `docs/app-store/checklist.md` under "Publish the website", before the Pages step:
```markdown
- [ ] GitHub › repo **Settings › General** › rename `trainme` to `rackside`, then locally: `git remote set-url origin https://github.com/madacgrav/rackside.git`.
```

### Verification
#### Automated
- [x] `xcodebuild -scheme Rackside -destination 'platform=iOS Simulator,name=iPhone 17' test` passes (AppInfoTests)
- [x] `scripts/check-docs-links.sh` passes
- [x] `grep -rn 'github.io/trainme\|madacgrav/trainme/\(actions\|blob\|tree\)\|madacgrav/trainme/issues"\?)\?$' Sources Tests docs README.md CHANGELOG.md scripts` returns nothing outside historical PR/issue/compare links

#### Manual
- [ ] Settings › About links open `madacgrav.github.io/rackside/...` (404 until Pages is enabled on the renamed repo is expected)
- [ ] After the owner renames the repo: CI runs green; Pages serves `/rackside/`, `/guide/`, `/privacy/`, `/support/`, `/changelog/`

---

## Phase 4: Docs and App Store kit read Rackside

### Changes

Replace the product name "TrainMe" with "Rackside" in prose. Keep: historical GitHub links,
`TrainMeMigrationPlan`, bundle IDs. Per-file guidance:

#### 1. Docs site
- `docs/index.md`: lines 2, 6 (`alt="Rackside app icon"`), 8, 10
- `docs/privacy.md`, `docs/support.md`: every prose "TrainMe"
- `docs/guide/*.md` (10 files with matches; `workouts-and-exercises.md` has none): every prose "TrainMe".
  `troubleshooting.md:14` has "TrainMe" outside the backticks; only that word changes, the backticked labels stay.

#### 2. App Store kit
- `docs/app-store/metadata.md`: title (1), Name field (7-9) → `Rackside`, description (26, 63), review notes (114-127) including the sample filename
- `git mv "docs/app-store/TrainMe Review Sample.json" "docs/app-store/Rackside Review Sample.json"`
- `docs/app-store/checklist.md`: title (1), licence line (7), line 20 → `name *Rackside*`, SKU `rackside-ios`, bundle ID **unchanged**; line 28 `Rackside.xcodeproj`; line 37 `Rackside Review Sample.json`
- `docs/app-store/whats-new/1.0.0.md:4` → "Rackside's first release on the App Store."

#### 3. Product docs
- `README.md`: heading (1), line 5 and any remaining prose
- `PRD.md`: lines 1, 12
- `BACKLOG.md`: line 1 title only (rows are historical records; leave `TrainMeMigrationPlan`, `Sources/TrainMe.entitlements` and issue/PR links)

#### 4. Changelog
**File**: `CHANGELOG.md`
- Line 3: "All notable changes to Rackside are documented in this file."
- `[Unreleased] — 1.0.0` › `### Changed`: replace "TrainMe is now an iPhone-only app…" with "Rackside is now…" and add
  ```markdown
  - Renamed the app from TrainMe to Rackside, because other fitness apps and a pending US trademark already use the TrainMe name.
  ```
- Leave released version sections and all links untouched.
- Then: `scripts/sync-changelog.sh` (regenerates `docs/changelog.md`; never edit it by hand).

### Verification
#### Automated
- [ ] `scripts/check-metadata-lengths.sh` passes
- [ ] `scripts/check-docs-links.sh` passes
- [ ] `scripts/check-guide-labels.sh` passes
- [ ] Re-running `scripts/sync-changelog.sh` after the commit leaves `git status` clean for `docs/changelog.md`
- [ ] Final sweep returns only the allowed exceptions:
  ```bash
  grep -rnIi trainme --exclude-dir={build,thoughts,.git,Rackside.xcodeproj} . | grep -v -e 'com\.madacgrav\.trainme' -e TrainMeMigrationPlan -e 'github\.com/madacgrav/trainme/\(pull\|issues\|compare\|releases\)'
  ```
  Expected leftovers: `BACKLOG.md` historical row mentioning `Sources/TrainMe.entitlements`, `CHANGELOG.md`/`docs/changelog.md` released-version prose, and the new changelog line that names the old name. Anything else is a miss.
- [ ] `xcodebuild -scheme Rackside -destination 'platform=iOS Simulator,name=iPhone 17' test` still passes

#### Manual
- [ ] Skim `docs/index.md`, `docs/guide/index.md` and `metadata.md` description: reads naturally with "Rackside"
- [ ] `ls docs/app-store/` shows `Rackside Review Sample.json`, no TrainMe file
