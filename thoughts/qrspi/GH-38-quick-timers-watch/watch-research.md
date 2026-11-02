# Watch Platform Research (external, supplements research.md)

Source: web research agent, 2026-11-01. Only three searches were run; most facts come from API knowledge.
**[verified]** = confirmed in a search result. **[unverified]** = from memory; confirm against Apple docs or on a device before relying on it.
Codebase tie-ins reference `research.md` sections.

## 1. Live Activities mirrored to Apple Watch
- iPhone Live Activities appear in the watch Smart Stack automatically from iOS 18 / watchOS 11, with no watch code **[verified]** — WWDC24 10068 https://developer.apple.com/wwdc24/10068
- A custom watch layout uses `.supplementalActivityFamilies([.small])` + `@Environment(\.activityFamily)` **[verified]**; without it the watch derives a layout from the compact presentations **[unverified]**.
- watchOS 26 adds Smart Stack UX changes, including an "Auto-Launch" setting for Live Activities **[partly verified]** (https://www.macrumors.com/how-to/apple-watch-live-activities-fix/). No Apple page found listing watchOS 26 ActivityKit API changes.
- `Text(timerInterval:countsDown:)` / `ProgressView(timerInterval:)` count down with no per-second updates. They stick at 0:00 until the activity is ended or updated.
- Alert/haptic at zero: `activity.update(_, alertConfiguration:)` alerts on both phone and watch, but a local update needs the app process running. A backgrounded app is suspended, so nothing fires at zero without APNs push. `staleDate` does not alert.
- Requires a **Widget Extension target** + `NSSupportsLiveActivities = YES` in the app's Info.plist. No App Group is needed if attributes/state carry everything.
- `Activity.request` must be called **in the foreground** (push-to-start needs APNs) **[unverified details]**.
- Limits: about 8 h active + 4 h on the Lock Screen **[unverified]**; well above a 30–180 s countdown.
- Interactive `Button(intent:)` with `LiveActivityIntent` on the watch probably runs on the iPhone **[unverified — test on a device pair]**.

## 2. Watch app target
- Since Xcode 14 a watch app is a single target with no WatchKit extension. Its bundle ID is prefixed by the iOS app's (`com.madacgrav.trainme.watchkitapp`). It sets `WKCompanionAppBundleIdentifier`, or `WKRunsIndependentlyOfCompanionApp` for standalone **[unverified]**. https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps
- XcodeGen: `type: application`, `platform: watchOS`, `deploymentTarget: "26.0"`; iOS target lists `- target: TrainMeWatch, embed: true`. Avoid `supportedDestinations` for the watch target (no "Embed Watch Content" phase — https://github.com/yonaskolb/XcodeGen/pull/1470) **[partly verified]**. The exact product type (`application` vs `application.watchapp2`) must be checked in the generated project.
- CI: building the iOS scheme with an embedded watch target also compiles for the watchOS simulator SDK. The `macos-26` runner's watchOS runtime availability is unconfirmed. `CODE_SIGNING_ALLOWED=NO` covers all targets **[unverified]**.
- research.md Q5/Q6: today the project has one iOS target, empty entitlements and no app group. A watch app can't read the SwiftData store unless data is sent to it.

## 3. Keeping a timer alive on the watch
- `Timer` / `Task.sleep` stop when the app is suspended (seconds after wrist-down). The robust approach is to store `endDate` and derive the remaining time.
- `WKExtendedRuntimeSession` types: mindfulness, physical therapy, self care, smart alarm (+ possibly a newer alarm type). Each needs a `WKBackgroundModes` entry, and App Review expects the type to match the use. Smart alarm's `notifyUser(hapticType:)` plays a haptic with the wrist down **[unverified]**. https://developer.apple.com/documentation/watchkit/wkextendedruntimesession
- `HKWorkoutSession`: keeps the app running indefinitely, but needs the HealthKit capability, usage strings and a user prompt **[unverified]**.
- `WKInterfaceDevice.current().play(_:)` only works while the app is executing.
- A local notification (`UNTimeIntervalNotificationTrigger`) scheduled by the watch app fires with a haptic even while the app is suspended. It is the most reliable haptic without a session.

## 4. Phone ↔ watch communication (WatchConnectivity)
- `sendMessage` requires `isReachable`. Watch→phone can wake the phone app in the background; phone→watch needs the watch app foreground. Latency is about ≤1 s.
- `updateApplicationContext` keeps only the latest value, which suits "current timer end date". `transferUserInfo` is queued and guaranteed but slow.
- To sync, send `endDate` + timer id + state, not per-second ticks.
- Swift 6: delegate callbacks arrive off the main actor, so callbacks need to be `nonisolated`. `[String: Any]` and `WCSession` are not `Sendable`; extract values before hopping to `@MainActor` **[unverified]**.

## 5. Complications and Controls
- Watch complications need a watch widget extension. They can display `Text(timerInterval:)` but cannot keep a timer alive.
- `ControlWidget` (iOS 18) is reported to come to watchOS 26 (Control Center, Smart Stack, Action button) **[unverified]**. Whether a watch control can start an iPhone Live Activity is uncertain (foreground requirement) — do not assume it.

## 6. iPhone-side alternatives
- **AlarmKit** (iOS 26): `.timer(duration:)` countdown alarms that ring through Silent/Focus and appear on a paired Apple Watch **[verified — WWDC25 230]** https://developer.apple.com/videos/play/wwdc2025/230/. It needs `NSAlarmKitUsageDescription` + `AlarmManager.requestAuthorization()`. It probably needs a widget extension for custom countdown UI **[unverified]**. It is an alarm-style takeover, which may be heavy for 60 s rests. It is the only option that alerts at zero with the app suspended and no watch app.
- **Local notification** (`UNTimeIntervalNotificationTrigger`, ≥1 s): mirrors to the watch with a haptic when the iPhone is locked/asleep and the watch is worn. It does **not** mirror while the iPhone screen is on. `.timeSensitive` breaks through Focus but needs the Time Sensitive capability.
- research.md Q4: notification permission is already requested (`RootView.swift:108`). `reschedule` removes only `sess-`-prefixed pending requests (`NotificationService.swift:87-88`), so differently-prefixed requests would not be cleared by it.

## Comparison
| Approach | Effort | New targets / entitlements | Phone in pocket | No watch app needed | Haptic at zero |
|---|---|---|---|---|---|
| Local notification only | Low | none | Yes (mirrors when locked) | Yes | Yes (watch) |
| Live Activity | Medium | Widget ext, `NSSupportsLiveActivities` | Yes | Yes (Smart Stack) | Only with push or running app |
| Live Activity + local notification | Medium | as above | Yes | Yes | Yes |
| AlarmKit timer | Medium | usage string, likely widget ext | Yes | Yes (mirrors) | Yes (alarm) |
| Watch app + local notification | High | watch target, signing, CI | Yes | No | Yes |
| Watch app + extended runtime session | High | watch target, background mode | Yes | No | Yes |
| Watch app + HKWorkoutSession | Highest | watch target, HealthKit | Yes | No | Yes |
| Watch Control / complication | High | watch widget ext | n/a | No | needs watch-app timer behind it |

## Codebase constraints relevant to any option (from research.md)
- `LockGateView` removes the whole content tree on `.background` (research.md Q3). In-view timer state would be lost on every phone background, independent of the watch approach.
- No timer primitives, background modes, extensions or app group exist (Q4–Q6). Every watch-facing option adds at least one target or capability, except local notifications.
- XcodeGen + CI build one iOS target on an iPhone simulator with signing off (Q5).

## Gaps to verify before committing to a design
- Live Activity intent buttons and control widgets behaving from the watch.
- `WKExtendedRuntimeSession` type list, durations and App Review fit for rest timers.
- XcodeGen watch product type with the installed version; watchOS simulator runtime on the `macos-26` runner.
- AlarmKit entitlement requirements and its watch presentation.
- Apple doc URLs above were not all fetched; check they resolve before citing.
