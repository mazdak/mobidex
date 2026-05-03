#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${MOBIDEX_APP_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/Mobidex.app"}"
BUNDLE_ID="${MOBIDEX_BUNDLE_ID:-com.mazdak.mobidex}"
SCREENSHOT_PATH="${MOBIDEX_SCREENSHOT_PATH:-"/tmp/mobidex-simulator-launch.png"}"
DEVICE_ID="${MOBIDEX_SIMULATOR_ID:-}"
KEEP_SIMULATOR="${MOBIDEX_KEEP_SIMULATOR:-0}"
SETTLE_SECONDS="${MOBIDEX_LAUNCH_SETTLE_SECONDS:-2}"

if [[ "${MOBIDEX_SKIP_BUILD:-0}" != "1" ]]; then
  SDK=iphonesimulator CONFIGURATION=Debug "$ROOT_DIR/Scripts/verify-ios-build.sh" Mobidex
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(
    xcrun simctl list devices available |
      awk '
        /^-- iOS / { in_ios = 1; next }
        /^-- / { in_ios = 0 }
        in_ios && match($0, /\([0-9A-F-][0-9A-F-]*\)/) {
          device_id = substr($0, RSTART + 1, RLENGTH - 2)
          if (length(device_id) == 36) {
            print device_id
            exit
          }
        }
      '
  )"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No available iOS simulator device found." >&2
  exit 1
fi

INITIAL_STATE="$(
  xcrun simctl list devices |
    awk -v id="$DEVICE_ID" '
      index($0, id) {
        if ($0 ~ /\(Booted\)/) print "Booted"
        else if ($0 ~ /\(Shutdown\)/) print "Shutdown"
        else print "Other"
        exit
      }
    '
)"
BOOTED_BY_SCRIPT=0

cleanup() {
  if [[ "$BOOTED_BY_SCRIPT" == "1" && "$KEEP_SIMULATOR" != "1" ]]; then
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$INITIAL_STATE" == "Shutdown" ]]; then
  xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
  BOOTED_BY_SCRIPT=1
fi

xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
LAUNCH_OUTPUT="$(xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_ID")"
APP_PID="${LAUNCH_OUTPUT##*: }"
if [[ ! "$APP_PID" =~ ^[0-9]+$ ]]; then
  echo "Could not parse launched app pid from: $LAUNCH_OUTPUT" >&2
  exit 1
fi
sleep "$SETTLE_SECONDS"
if ! xcrun simctl spawn "$DEVICE_ID" launchctl print "pid/$APP_PID" >/dev/null 2>&1; then
  echo "App process $APP_PID is not running after launch." >&2
  exit 1
fi
mkdir -p "$(dirname "$SCREENSHOT_PATH")"
xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null

echo "Simulator launch succeeded."
echo "Device: $DEVICE_ID"
echo "Launch: $LAUNCH_OUTPUT"
echo "Screenshot: $SCREENSHOT_PATH"
