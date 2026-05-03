#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${MOBIDEX_APP_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/Mobidex.app"}"
RUNNER_PATH="${MOBIDEX_UI_TEST_RUNNER_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/MobidexUITests-Runner.app"}"
TEST_BUNDLE_PATH="${MOBIDEX_UI_TEST_BUNDLE_PATH:-"$RUNNER_PATH/PlugIns/MobidexUITests.xctest"}"
LOG_PATH="${LOG_PATH:-/tmp/mobidex-tap-ui-smoke.log}"
SCREENSHOT_PATH="${MOBIDEX_UI_SMOKE_SCREENSHOT_PATH:-/tmp/mobidex-tap-ui-smoke.png}"
DESTINATION="${MOBIDEX_DESTINATION:-}"
DEVICE_ID="${MOBIDEX_SIMULATOR_ID:-}"
KEEP_SIMULATOR="${MOBIDEX_KEEP_SIMULATOR:-0}"
TIMEOUT_SECONDS="${MOBIDEX_UI_SMOKE_TIMEOUT:-120}"
TEST_TIMEOUT_SECONDS="${MOBIDEX_UI_TEST_TIMEOUT_SECONDS:-$((TIMEOUT_SECONDS + 120))}"
WORK_DIR="$(mktemp -d)"
XCTESTRUN_PATH="${MOBIDEX_UI_XCTESTRUN_PATH:-"$WORK_DIR/MobidexUIGenerated.xctestrun"}"
SETUP_ENV_PATH="$WORK_DIR/app-env.sh"
SETUP_STDOUT="$WORK_DIR/setup.out"
SETUP_STDERR="$WORK_DIR/setup.err"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "MOBIDEX_UI_SMOKE_TIMEOUT must be a positive integer." >&2
  exit 2
fi

if [[ ! "$TEST_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "MOBIDEX_UI_TEST_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

if [[ -n "$DESTINATION" ]]; then
  if [[ -z "$DEVICE_ID" && "$DESTINATION" =~ id=([0-9A-Fa-f-]{36}) ]]; then
    DEVICE_ID="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    echo "MOBIDEX_DESTINATION must include an id= simulator UDID unless MOBIDEX_SIMULATOR_ID is also set." >&2
    exit 2
  fi
else
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

  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
fi

cleanup() {
  if [[ -n "${SETUP_PID:-}" ]]; then
    kill "$SETUP_PID" >/dev/null 2>&1 || true
    wait "$SETUP_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_SIMULATOR" != "1" ]]; then
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

absolute_path() {
  case "$1" in
    /*)
      printf '%s\n' "$1"
      ;;
    *)
      printf '%s/%s\n' "$PWD" "$1"
      ;;
  esac
}

if [[ "${MOBIDEX_SKIP_BUILD:-0}" != "1" ]]; then
  SDK=iphonesimulator CONFIGURATION=Debug "$ROOT_DIR/Scripts/verify-ios-build.sh" MobidexUITests
fi

APP_PATH="$(absolute_path "$APP_PATH")"
RUNNER_PATH="$(absolute_path "$RUNNER_PATH")"
TEST_BUNDLE_PATH="$(absolute_path "$TEST_BUNDLE_PATH")"
XCTESTRUN_PATH="$(absolute_path "$XCTESTRUN_PATH")"
SCREENSHOT_PATH="$(absolute_path "$SCREENSHOT_PATH")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -d "$RUNNER_PATH" ]]; then
  echo "UI test runner not found: $RUNNER_PATH" >&2
  exit 1
fi

if [[ ! -d "$TEST_BUNDLE_PATH" ]]; then
  echo "UI test bundle not found: $TEST_BUNDLE_PATH" >&2
  exit 1
fi

if [[ ! -f "$TEST_BUNDLE_PATH/Info.plist" ]]; then
  echo "UI test bundle is missing Info.plist: $TEST_BUNDLE_PATH" >&2
  exit 1
fi

rm -f "$SCREENSHOT_PATH"
MOBIDEX_SIMULATOR_ID="$DEVICE_ID" \
MOBIDEX_SMOKE_AUTH=password \
MOBIDEX_SMOKE_MODE=seed \
MOBIDEX_SMOKE_SETUP_ONLY=1 \
MOBIDEX_SMOKE_ENV_PATH="$SETUP_ENV_PATH" \
MOBIDEX_SMOKE_PROMPT="${MOBIDEX_UI_SMOKE_PROMPT:-Start control smoke}" \
MOBIDEX_SMOKE_STEER_TEXT="${MOBIDEX_UI_SMOKE_STEER_TEXT:-Steer control smoke}" \
MOBIDEX_SMOKE_EXPECTED_TEXT="${MOBIDEX_UI_SMOKE_EXPECTED_TEXT:-control steer accepted}" \
MOBIDEX_SMOKE_TIMEOUT="$TIMEOUT_SECONDS" \
"$ROOT_DIR/Scripts/verify-inapp-ssh-smoke.sh" >"$SETUP_STDOUT" 2>"$SETUP_STDERR" &
SETUP_PID=$!

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  if [[ -s "$SETUP_ENV_PATH" ]]; then
    break
  fi
  if ! kill -0 "$SETUP_PID" >/dev/null 2>&1; then
    echo "Smoke setup exited before writing $SETUP_ENV_PATH." >&2
    sed -n '1,160p' "$SETUP_STDOUT" >&2 || true
    sed -n '1,220p' "$SETUP_STDERR" >&2 || true
    exit 1
  fi
  sleep 1
done

if [[ ! -s "$SETUP_ENV_PATH" ]]; then
  echo "Timed out waiting for smoke setup environment at $SETUP_ENV_PATH." >&2
  sed -n '1,160p' "$SETUP_STDOUT" >&2 || true
  sed -n '1,220p' "$SETUP_STDERR" >&2 || true
  exit 1
fi

# shellcheck disable=SC1090
source "$SETUP_ENV_PATH"
export MOBIDEX_UI_SMOKE_PROMPT="${MOBIDEX_UI_SMOKE_PROMPT:-${MOBIDEX_SMOKE_PROMPT:-Start control smoke}}"
export MOBIDEX_UI_SMOKE_STEER_TEXT="${MOBIDEX_UI_SMOKE_STEER_TEXT:-${MOBIDEX_SMOKE_STEER_TEXT:-Steer control smoke}}"
export MOBIDEX_UI_SMOKE_EXPECTED_TEXT="${MOBIDEX_UI_SMOKE_EXPECTED_TEXT:-${MOBIDEX_SMOKE_EXPECTED_TEXT:-control steer accepted}}"
export MOBIDEX_UI_SMOKE_TIMEOUT="$TIMEOUT_SECONDS"

runner_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$RUNNER_PATH/Info.plist")"
PRODUCT_DIR="$(cd "$(dirname "$APP_PATH")" && pwd -P)"

mkdir -p "$(dirname "$XCTESTRUN_PATH")" "$(dirname "$LOG_PATH")" "$(dirname "$SCREENSHOT_PATH")"
rm -f "$XCTESTRUN_PATH"

plist="/usr/libexec/PlistBuddy"
/usr/bin/plutil -create xml1 "$XCTESTRUN_PATH"
"$plist" -c "Add :__xctestrun_metadata__ dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :__xctestrun_metadata__:FormatVersion integer 2" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan:IsDefault bool true" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan:Name string MobidexUIGenerated" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0 dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:IsEnabled bool true" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:Name string Default" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0 dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:BlueprintName string MobidexUITests" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths:0 string $APP_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths:1 string $RUNNER_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths:2 string $TEST_BUNDLE_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:IsUITestBundle bool true" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:ProductModuleName string MobidexUITests" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:SystemAttachmentLifetime string deleteOnSuccess" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestBundlePath string $TEST_BUNDLE_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestHostBundleIdentifier string $runner_bundle_id" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestHostPath string $RUNNER_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UITargetAppBundleIdentifier string com.mazdak.mobidex" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UITargetAppPath string $APP_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UserAttachmentLifetime string deleteOnSuccess" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XCODE_BUILT_PRODUCTS_DIR_PATHS string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XPC_DYLD_FRAMEWORK_PATH string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XPC_DYLD_LIBRARY_PATH string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_FRAMEWORK_PATH string $PRODUCT_DIR:__SHAREDFRAMEWORKS__:__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_LIBRARY_PATH string $PRODUCT_DIR:__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:XCODE_SCHEME_NAME string Mobidex" "$XCTESTRUN_PATH"

add_test_environment() {
  local key="$1"
  local value="${!key:-}"
  if [[ -n "$value" ]]; then
    "$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:$key string $value" "$XCTESTRUN_PATH"
  fi
}

for key in \
  MOBIDEX_SMOKE_AUTH \
  MOBIDEX_SMOKE_CODEX_PATH \
  MOBIDEX_SMOKE_CWD \
  MOBIDEX_SMOKE_EXPECTED_TEXT \
  MOBIDEX_SMOKE_HOST \
  MOBIDEX_SMOKE_MODE \
  MOBIDEX_SMOKE_PASSWORD \
  MOBIDEX_SMOKE_PORT \
  MOBIDEX_SMOKE_PROMPT \
  MOBIDEX_SMOKE_STEER_TEXT \
  MOBIDEX_SMOKE_TIMEOUT \
  MOBIDEX_SMOKE_USER \
  MOBIDEX_UI_SMOKE_EXPECTED_TEXT \
  MOBIDEX_UI_SMOKE_PROMPT \
  MOBIDEX_UI_SMOKE_STEER_TEXT \
  MOBIDEX_UI_SMOKE_TIMEOUT; do
  add_test_environment "$key"
done

xcrun simctl terminate "$DEVICE_ID" com.mazdak.mobidex >/dev/null 2>&1 || true
xcrun simctl terminate "$DEVICE_ID" "$runner_bundle_id" >/dev/null 2>&1 || true

set +e
perl -e 'alarm shift; exec @ARGV' "$TEST_TIMEOUT_SECONDS" \
  xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN_PATH" \
  -destination "$DESTINATION" \
  >"$LOG_PATH" 2>&1
status=$?
set -e

xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null 2>&1 || true

if [[ "$status" == "0" ]]; then
  echo "Tap-level UI smoke succeeded. Log: $LOG_PATH"
  echo "Destination: $DESTINATION"
  if [[ -n "${MOBIDEX_UI_XCTESTRUN_PATH:-}" ]]; then
    echo "xctestrun: $XCTESTRUN_PATH"
  else
    echo "xctestrun: generated in a temporary work directory and removed on exit"
  fi
  echo "Screenshot: $SCREENSHOT_PATH"
  exit 0
fi

echo "Tap-level UI smoke failed. Log: $LOG_PATH" >&2
echo "Setup stdout:" >&2
sed -n '1,120p' "$SETUP_STDOUT" >&2 || true
echo "Setup stderr:" >&2
sed -n '1,220p' "$SETUP_STDERR" >&2 || true
echo "xcodebuild tail:" >&2
tail -n 160 "$LOG_PATH" >&2 || true
if [[ -f "$SCREENSHOT_PATH" ]]; then
  echo "Screenshot: $SCREENSHOT_PATH" >&2
fi
exit "$status"
