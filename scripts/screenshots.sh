#!/usr/bin/env bash
# Regenerates App Store and user-guide screenshots from DEBUG demo data.
#
#   scripts/screenshots.sh [--dark] [--only <name>]
#
# Today's demo sessions start just after the current time, so a morning run gives the
# most natural-looking schedule. The watch clock can't be overridden and shows real time.
# Env overrides: PHONE (default "iPhone 18 Pro Max"), WATCH (default "Apple Watch Ultra 4 (49mm)").
# Output: docs/app-store/screenshots/*.png (App Store set) and docs/guide/images/*.png (guide).
set -euo pipefail
cd "$(dirname "$0")/.."

PHONE="${PHONE:-iPhone 18 Pro Max}"
WATCH="${WATCH:-Apple Watch Ultra 4 (49mm)}"
APPEARANCE=light
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dark) APPEARANCE=dark; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    *) echo "usage: $0 [--dark] [--only <name>]" >&2; exit 2 ;;
  esac
done
SUFFIX=""; [[ "$APPEARANCE" == dark ]] && SUFFIX="-dark"

STORE=docs/app-store/screenshots
GUIDE=docs/guide/images
mkdir -p "$STORE" "$GUIDE"

# Simulators can take ~20 s to draw the first frame after a relaunch; earlier
# captures come back blank (a white frame is ~84 KB vs 240 KB+ for real content).
FIRST_FRAME_WAIT=25
MIN_PHONE_BYTES=150000

udid() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; }
P=$(udid "$PHONE") || { echo "No simulator named '$PHONE'" >&2; exit 1; }
W=$(udid "$WATCH") || { echo "No simulator named '$WATCH'" >&2; exit 1; }

echo "==> Building Debug app"
DERIVED=build/ScreenshotsDerivedData
xcodegen generate >/dev/null
xcodebuild -scheme Rackside -configuration Debug -destination "id=$P" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build -quiet
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Rackside.app"
WAPP="$APP/Watch/RacksideWatch.app"

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

bytes() { stat -f %z "$1"; }

# shot <device> <bundle-id> <file> <min-bytes> <args...>
shot() {
  local dev=$1 bundle=$2 file=$3 min=$4; shift 4
  local attempt
  for attempt in 1 2 3; do
    xcrun simctl launch --terminate-running-process "$dev" "$bundle" "$@" >/dev/null
    sleep "$FIRST_FRAME_WAIT"
    xcrun simctl io "$dev" screenshot "$file" >/dev/null 2>&1
    if (( $(bytes "$file") >= min )); then return 0; fi
    echo "    blank frame, retrying ($attempt)"
  done
  echo "FAILED: $file stayed blank" >&2
  return 1
}

# Last export one hour ago: no backup banner/badge, and Settings shows a believable date.
PHONE_ARGS=(-demoData -hasSeenBackupNotice YES -lastExportAt $(( $(date +%s) - 3600 )))

# name | demo screen | schedule mode | also App Store
PHONE_SHOTS="01-schedule-week|schedule|week|yes
02-session-timer|session|week|yes
03-client-detail|client|week|yes
04-progress-report|report|week|yes
05-assessment|assessment|week|yes
06-workout-builder|builder|week|yes
schedule-day|schedule|day|no
clients|clients|week|no
workouts|workouts|week|no
exercises|exercises|week|no
settings|settings|week|no"

echo "==> iPhone: $PHONE ($APPEARANCE)"
boot "$P"
xcrun simctl ui "$P" appearance "$APPEARANCE"
xcrun simctl status_bar "$P" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$P" "$APP"

while IFS='|' read -r name screen mode store; do
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue
  echo "--> $name"
  out="$GUIDE/$name$SUFFIX.png"
  shot "$P" com.madacgrav.trainme "$out" "$MIN_PHONE_BYTES" \
    "${PHONE_ARGS[@]}" -demoScreen "$screen" -scheduleMode "$mode"
  [[ "$store" == yes ]] && cp "$out" "$STORE/$name$SUFFIX.png"
done <<< "$PHONE_SHOTS"
xcrun simctl status_bar "$P" clear

echo "==> Watch: $WATCH"
boot "$W"
xcrun simctl install "$W" "$WAPP"
for pair in "w1-timer-running|running" "w2-quick-start|idle"; do
  name=${pair%%|*}; state=${pair##*|}
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue
  echo "--> $name"
  # Watch frames are small (~28 KB), so no blank-size check; the wait is enough.
  shot "$W" com.madacgrav.trainme.watchkitapp "$STORE/$name.png" 0 -demoData -demoWatch "$state"
  cp "$STORE/$name.png" "$GUIDE/$name.png"
done

echo "==> Checking sizes"
size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/{print $2}' | paste -sd x -; }
bad=0
for f in "$STORE"/0*.png; do
  [[ -e "$f" ]] || continue
  s=$(size "$f")
  [[ "$s" =~ ^(1320x2868|1290x2796)$ ]] || { echo "BAD SIZE $f $s (need 6.9\" iPhone)"; bad=1; }
done
for f in "$STORE"/w*.png; do
  [[ -e "$f" ]] || continue
  s=$(size "$f")
  [[ "$s" =~ ^(422x514|410x502|416x496|396x484|368x448)$ ]] || { echo "BAD SIZE $f $s (need Apple Watch)"; bad=1; }
done
[[ $bad -eq 0 ]] && echo "All screenshots OK."
exit $bad
