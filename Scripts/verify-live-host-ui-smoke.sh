#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${MOBIDEX_BUNDLE_ID:-com.getresq.mobidex}"
APP_PATH="${MOBIDEX_APP_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/Mobidex.app"}"
RUNNER_PATH="${MOBIDEX_UI_TEST_RUNNER_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/MobidexUITests-Runner.app"}"
TEST_BUNDLE_PATH="${MOBIDEX_UI_TEST_BUNDLE_PATH:-"$RUNNER_PATH/PlugIns/MobidexUITests.xctest"}"
DEVICE_ID="${MOBIDEX_SIMULATOR_ID:-}"
DESTINATION="${MOBIDEX_DESTINATION:-}"
LOG_PATH="${LOG_PATH:-/tmp/mobidex-live-host-ui-smoke.log}"
SCREENSHOT_PATH="${MOBIDEX_UI_SMOKE_SCREENSHOT_PATH:-/tmp/mobidex-live-host-ui-smoke.png}"
TIMEOUT_SECONDS="${MOBIDEX_UI_SMOKE_TIMEOUT:-180}"
TEST_TIMEOUT_SECONDS="${MOBIDEX_UI_TEST_TIMEOUT_SECONDS:-$((TIMEOUT_SECONDS + 120))}"
WORK_DIR="$(mktemp -d)"
XCTESTRUN_PATH="${MOBIDEX_UI_XCTESTRUN_PATH:-"$WORK_DIR/MobidexLiveHostUI.xctestrun"}"

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
if [[ -z "$DESTINATION" ]]; then
  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
fi

SDK=iphonesimulator CONFIGURATION=Debug "$ROOT_DIR/Scripts/verify-ios-build.sh" MobidexUITests

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

APP_PATH="$(absolute_path "$APP_PATH")"
RUNNER_PATH="$(absolute_path "$RUNNER_PATH")"
TEST_BUNDLE_PATH="$(absolute_path "$TEST_BUNDLE_PATH")"
XCTESTRUN_PATH="$(absolute_path "$XCTESTRUN_PATH")"
SCREENSHOT_PATH="$(absolute_path "$SCREENSHOT_PATH")"

for path in "$APP_PATH" "$RUNNER_PATH" "$TEST_BUNDLE_PATH"; do
  if [[ ! -d "$path" ]]; then
    echo "Required UI smoke bundle not found: $path" >&2
    exit 1
  fi
done

runner_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$RUNNER_PATH/Info.plist")"
PRODUCT_DIR="$(cd "$(dirname "$APP_PATH")" && pwd -P)"

mkdir -p "$(dirname "$LOG_PATH")" "$(dirname "$SCREENSHOT_PATH")" "$(dirname "$XCTESTRUN_PATH")"
rm -f "$XCTESTRUN_PATH"

plist="/usr/libexec/PlistBuddy"
/usr/bin/plutil -create xml1 "$XCTESTRUN_PATH"
"$plist" -c "Add :__xctestrun_metadata__ dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :__xctestrun_metadata__:FormatVersion integer 2" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan:IsDefault bool true" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan:Name string MobidexLiveHostUI" "$XCTESTRUN_PATH"
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
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UITargetAppBundleIdentifier string $BUNDLE_ID" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UITargetAppPath string $APP_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UserAttachmentLifetime string deleteOnSuccess" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:SkipTestIdentifiers array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:OnlyTestIdentifiers array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:OnlyTestIdentifiers:0 string MobidexUITests/testRealHostNewSessionFromVisibleUI" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XCODE_BUILT_PRODUCTS_DIR_PATHS string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XPC_DYLD_FRAMEWORK_PATH string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XPC_DYLD_LIBRARY_PATH string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_FRAMEWORK_PATH string $PRODUCT_DIR:__SHAREDFRAMEWORKS__:__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_LIBRARY_PATH string $PRODUCT_DIR:__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib" "$XCTESTRUN_PATH"

add_test_environment() {
  local key="$1"
  local value="${!key:-}"
  if [[ -n "$value" ]]; then
    "$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:$key string $value" "$XCTESTRUN_PATH"
  fi
}

export MOBIDEX_UI_REAL_HOST_SMOKE=1
for key in \
  MOBIDEX_SMOKE_AUTH \
  MOBIDEX_SMOKE_CODEX_PATH \
  MOBIDEX_SMOKE_CWD \
  MOBIDEX_SMOKE_DISPLAY_NAME \
  MOBIDEX_SMOKE_EXPECTED_TEXT \
  MOBIDEX_SMOKE_HOST \
  MOBIDEX_SMOKE_MODE \
  MOBIDEX_SMOKE_NEW_SESSION_LOCATION \
  MOBIDEX_SMOKE_PASSWORD \
  MOBIDEX_SMOKE_PORT \
  MOBIDEX_SMOKE_PRIVATE_KEY_BASE64 \
  MOBIDEX_SMOKE_PRIVATE_KEY_PASSPHRASE \
  MOBIDEX_SMOKE_PROMPT \
  MOBIDEX_SMOKE_SERVER_ID \
  MOBIDEX_SMOKE_STEER_TEXT \
  MOBIDEX_SMOKE_EXECUTION_PATH \
  MOBIDEX_SMOKE_TIMEOUT \
  MOBIDEX_SMOKE_USER \
  MOBIDEX_UI_NEW_SESSION_LOCATION \
  MOBIDEX_UI_REAL_HOST_SMOKE \
  MOBIDEX_UI_SMOKE_EXPECTED_TEXT \
  MOBIDEX_UI_SMOKE_PROMPT \
  MOBIDEX_UI_SMOKE_STEER_TEXT \
  MOBIDEX_UI_SMOKE_TIMEOUT; do
  add_test_environment "$key"
done

xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

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
  echo "Live-host UI smoke succeeded. Log: $LOG_PATH"
  echo "Screenshot: $SCREENSHOT_PATH"
  exit 0
fi

echo "Live-host UI smoke failed. Log: $LOG_PATH" >&2
tail -n 180 "$LOG_PATH" >&2 || true
echo "Screenshot: $SCREENSHOT_PATH" >&2
exit "$status"
