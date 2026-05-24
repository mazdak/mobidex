#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${MOBIDEX_BUNDLE_ID:-com.getresq.mobidex}"
APP_PATH="${MOBIDEX_APP_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/Mobidex.app"}"
DEVICE_ID="${MOBIDEX_SIMULATOR_ID:-}"
SCREENSHOT_PATH="${MOBIDEX_SCREENSHOT_PATH:-"/tmp/mobidex-live-host-smoke.png"}"
RESULT_FILENAME="mobidex-smoke-result.json"
WORK_DIR="$(mktemp -d)"
APP_STDOUT="$WORK_DIR/app.out"
APP_STDERR="$WORK_DIR/app.err"
TIMEOUT="${MOBIDEX_SMOKE_TIMEOUT:-180}"
RESULT_TIMEOUT=$((TIMEOUT + 60))

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

required() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required smoke value: $key" >&2
    exit 2
  fi
}

required MOBIDEX_SMOKE_HOST
required MOBIDEX_SMOKE_USER
required MOBIDEX_SMOKE_CWD
required MOBIDEX_SMOKE_AUTH

case "$MOBIDEX_SMOKE_AUTH" in
  private-key | privateKey)
    required MOBIDEX_SMOKE_PRIVATE_KEY_BASE64
    ;;
  password)
    required MOBIDEX_SMOKE_PASSWORD
    ;;
  *)
    echo "Unsupported MOBIDEX_SMOKE_AUTH: $MOBIDEX_SMOKE_AUTH" >&2
    exit 2
    ;;
esac

SDK=iphonesimulator CONFIGURATION=Debug "$ROOT_DIR/Scripts/verify-ios-build.sh" Mobidex

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

xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"
RESULT_PATH="$DATA_CONTAINER/Documents/$RESULT_FILENAME"
rm -f "$RESULT_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

launch_env=(
  "SIMCTL_CHILD_MOBIDEX_SMOKE=1"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_AUTH=$MOBIDEX_SMOKE_AUTH"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_MODE=${MOBIDEX_SMOKE_MODE:-connection}"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_HOST=$MOBIDEX_SMOKE_HOST"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_PORT=${MOBIDEX_SMOKE_PORT:-22}"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_USER=$MOBIDEX_SMOKE_USER"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_CODEX_PATH=${MOBIDEX_SMOKE_CODEX_PATH:-codex}"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_CWD=$MOBIDEX_SMOKE_CWD"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_DISPLAY_NAME=${MOBIDEX_SMOKE_DISPLAY_NAME:-Live Host Smoke}"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_EXECUTION_PATH=${MOBIDEX_SMOKE_EXECUTION_PATH:-}"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_TIMEOUT=$TIMEOUT"
)

for key in MOBIDEX_SMOKE_SERVER_ID MOBIDEX_SMOKE_NEW_SESSION_LOCATION MOBIDEX_SMOKE_PROMPT MOBIDEX_SMOKE_EXPECTED_TEXT MOBIDEX_SMOKE_STEER_TEXT MOBIDEX_SMOKE_PASSWORD MOBIDEX_SMOKE_PRIVATE_KEY_BASE64 MOBIDEX_SMOKE_PRIVATE_KEY_PASSPHRASE; do
  if [[ -n "${!key:-}" ]]; then
    launch_env+=("SIMCTL_CHILD_$key=${!key}")
  fi
done

env "${launch_env[@]}" \
xcrun simctl launch \
  --terminate-running-process \
  --stdout="$APP_STDOUT" \
  --stderr="$APP_STDERR" \
  "$DEVICE_ID" \
  "$BUNDLE_ID" >/dev/null

deadline=$((SECONDS + RESULT_TIMEOUT))
while (( SECONDS < deadline )); do
  if [[ -f "$RESULT_PATH" ]]; then
    status="$(python3 - "$RESULT_PATH" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle).get("status", ""))
PY
)"
    if [[ "$status" == "success" ]]; then
      xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null 2>&1 || true
      python3 - "$RESULT_PATH" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    result = json.load(handle)
print(json.dumps(result, indent=2, sort_keys=True))
PY
      echo "Live-host smoke succeeded. Screenshot: $SCREENSHOT_PATH"
      exit 0
    fi
    if [[ "$status" == "failure" ]]; then
      break
    fi
  fi
  sleep 1
done

echo "Live-host smoke failed or timed out." >&2
if [[ -f "$RESULT_PATH" ]]; then
  cat "$RESULT_PATH" >&2
fi
echo "app stdout:" >&2
sed -n '1,180p' "$APP_STDOUT" >&2 2>/dev/null || true
echo "app stderr:" >&2
sed -n '1,220p' "$APP_STDERR" >&2 2>/dev/null || true
xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null 2>&1 || true
echo "Screenshot: $SCREENSHOT_PATH" >&2
exit 1
