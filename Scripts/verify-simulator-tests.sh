#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${MOBIDEX_APP_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/Mobidex.app"}"
TEST_BUNDLE_PATH="${MOBIDEX_TEST_BUNDLE_PATH:-"$APP_PATH/PlugIns/MobidexTests.xctest"}"
XCTESTRUN_PATH="${MOBIDEX_XCTESTRUN_PATH:-"$ROOT_DIR/build/MobidexGenerated.xctestrun"}"
LOG_PATH="${LOG_PATH:-/tmp/mobidex-simulator-tests.log}"
DESTINATION="${MOBIDEX_DESTINATION:-}"
DEVICE_ID="${MOBIDEX_SIMULATOR_ID:-}"
KEEP_SIMULATOR="${MOBIDEX_KEEP_SIMULATOR:-0}"
TIMEOUT_SECONDS="${MOBIDEX_TEST_TIMEOUT_SECONDS:-180}"

if [[ ! "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "MOBIDEX_TEST_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

if [[ "${MOBIDEX_SKIP_BUILD:-0}" != "1" ]]; then
  SDK=iphonesimulator CONFIGURATION=Debug "$ROOT_DIR/Scripts/verify-ios-build.sh" MobidexTests
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -d "$TEST_BUNDLE_PATH" ]]; then
  echo "Test bundle not found: $TEST_BUNDLE_PATH" >&2
  exit 1
fi

if [[ ! -f "$TEST_BUNDLE_PATH/Info.plist" ]]; then
  echo "Test bundle is missing Info.plist: $TEST_BUNDLE_PATH" >&2
  exit 1
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd -P)/$(basename "$APP_PATH")"
TEST_BUNDLE_PATH="$(cd "$(dirname "$TEST_BUNDLE_PATH")" && pwd -P)/$(basename "$TEST_BUNDLE_PATH")"
PRODUCT_DIR="$(cd "$(dirname "$APP_PATH")" && pwd -P)"

if [[ -z "$DESTINATION" ]]; then
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

INITIAL_STATE=""
BOOTED_BY_SCRIPT=0
if [[ -n "$DEVICE_ID" ]]; then
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
fi

cleanup() {
  if [[ "$BOOTED_BY_SCRIPT" == "1" && "$KEEP_SIMULATOR" != "1" ]]; then
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$INITIAL_STATE" == "Shutdown" ]]; then
  xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
  BOOTED_BY_SCRIPT=1
  xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
fi

mkdir -p "$(dirname "$XCTESTRUN_PATH")" "$(dirname "$LOG_PATH")"
rm -f "$XCTESTRUN_PATH"

plist="/usr/libexec/PlistBuddy"
/usr/bin/plutil -create xml1 "$XCTESTRUN_PATH"
"$plist" -c "Add :__xctestrun_metadata__ dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :__xctestrun_metadata__:FormatVersion integer 2" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan:IsDefault bool true" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestPlan:Name string MobidexGenerated" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0 dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:IsEnabled bool true" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:Name string Default" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0 dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:BlueprintName string MobidexTests" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths array" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths:0 string $APP_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:DependentProductPaths:1 string $TEST_BUNDLE_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:ProductModuleName string MobidexTests" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:SystemAttachmentLifetime string deleteOnSuccess" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestBundlePath string $TEST_BUNDLE_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestHostBundleIdentifier string com.mazdak.mobidex" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestHostPath string $APP_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UITargetAppPath string $APP_PATH" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:UserAttachmentLifetime string deleteOnSuccess" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables dict" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XCODE_BUILT_PRODUCTS_DIR_PATHS string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XPC_DYLD_FRAMEWORK_PATH string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:__XPC_DYLD_LIBRARY_PATH string $PRODUCT_DIR" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_FRAMEWORK_PATH string $PRODUCT_DIR:__SHAREDFRAMEWORKS__:__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_INSERT_LIBRARIES string __TESTHOST__/Frameworks/libXCTestBundleInject.dylib" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:DYLD_LIBRARY_PATH string $PRODUCT_DIR:__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:XCInjectBundleInto string unused" "$XCTESTRUN_PATH"
"$plist" -c "Add :TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables:XCODE_SCHEME_NAME string Mobidex" "$XCTESTRUN_PATH"

xcrun simctl terminate "$DEVICE_ID" com.mazdak.mobidex >/dev/null 2>&1 || true

set +e
perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" \
  xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN_PATH" \
  -destination "$DESTINATION" \
  >"$LOG_PATH" 2>&1
status=$?
set -e

if [[ "$status" == "0" ]]; then
  echo "Simulator XCTest gate succeeded. Log: $LOG_PATH"
  echo "Destination: $DESTINATION"
  echo "xctestrun: $XCTESTRUN_PATH"
  exit 0
fi

echo "Simulator XCTest gate failed. Log: $LOG_PATH" >&2
tail -n 120 "$LOG_PATH" >&2
exit "$status"
