#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Mobidex.xcodeproj"
SCHEME="${MOBIDEX_SCHEME:-Mobidex}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${MOBIDEX_DESTINATION:-generic/platform=iOS Simulator}"
ACTION="${MOBIDEX_SCHEME_ACTION:-build-for-testing}"
LOG_PATH="${LOG_PATH:-/tmp/mobidex-official-scheme.log}"

case "$ACTION" in
  build | build-for-testing | test)
    ;;
  *)
    echo "Unsupported MOBIDEX_SCHEME_ACTION: $ACTION" >&2
    echo "Use build, build-for-testing, or test." >&2
    exit 2
    ;;
esac

if [[ "$ACTION" == "test" && ( -z "${MOBIDEX_DESTINATION:-}" || "$DESTINATION" == generic/* ) ]]; then
  cat >&2 <<'MSG'
MOBIDEX_SCHEME_ACTION=test requires a concrete MOBIDEX_DESTINATION, for example:
  MOBIDEX_SCHEME_ACTION=test MOBIDEX_DESTINATION='platform=iOS Simulator,id=<simulator-udid>' Scripts/verify-official-scheme.sh
The default generic simulator destination is intended for build/build-for-testing only.
MSG
  exit 2
fi

mkdir -p "$(dirname "$LOG_PATH")"

sdk_output="$(xcodebuild -showsdks 2>&1)"
runtimes_output="$(xcrun simctl list runtimes available 2>&1)"
runtime_images_output="$(xcrun simctl runtime list 2>&1 || true)"
devices_output="$(xcrun simctl list devices available 2>&1)"
destinations_output="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showdestinations 2>&1 || true)"
simulator_sdk_version="$(
  printf '%s\n' "$sdk_output" |
    awk '/iOS Simulator SDKs:/{in_ios_sim=1; next} in_ios_sim && /-sdk iphonesimulator/{print; exit}' |
    sed -E 's/.*iOS ([0-9.]+)[[:space:]]+-sdk iphonesimulator.*/\1/'
)"

matching_runtime_present="unknown"
if [[ -n "$simulator_sdk_version" ]]; then
  if printf '%s\n' "$runtimes_output" | grep -Fq "iOS $simulator_sdk_version ("; then
    matching_runtime_present="yes"
  else
    matching_runtime_present="no"
  fi
fi

scheme_lists_simulator_destination="no"
if printf '%s\n' "$destinations_output" | grep -Fq "platform:iOS Simulator"; then
  scheme_lists_simulator_destination="yes"
fi

unusable_runtime_image_count="$(
  printf '%s\n' "$runtime_images_output" |
    grep -c 'Unusable' || true
)"

{
  echo "== Xcode =="
  xcodebuild -version
  echo
  echo "== First Launch =="
  if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    echo "complete"
  else
    echo "incomplete"
  fi
  echo
  echo "== SDKs =="
  printf '%s\n' "$sdk_output"
  echo
  echo "== Available Runtimes =="
  printf '%s\n' "$runtimes_output"
  echo
  echo "== Runtime Disk Images =="
  printf '%s\n' "$runtime_images_output"
  echo
  echo "== Available Simulator Devices =="
  printf '%s\n' "$devices_output"
  echo
  echo "== Scheme Destinations =="
  printf '%s\n' "$destinations_output"
  echo
  echo "== Destination Diagnosis =="
  echo "iOS simulator SDK version: ${simulator_sdk_version:-unknown}"
  echo "Matching simulator runtime present: $matching_runtime_present"
  echo "Unusable simulator runtime images: $unusable_runtime_image_count"
  echo "Scheme lists iOS Simulator destination: $scheme_lists_simulator_destination"
  echo
  echo "== Command =="
  printf 'xcodebuild -project %q -scheme %q -destination %q -configuration %q %q CODE_SIGNING_ALLOWED=NO\n' \
    "$PROJECT_PATH" "$SCHEME" "$DESTINATION" "$CONFIGURATION" "$ACTION"
  echo
} >"$LOG_PATH" 2>&1

set +e
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration "$CONFIGURATION" \
  "$ACTION" \
  CODE_SIGNING_ALLOWED=NO \
  >>"$LOG_PATH" 2>&1
status=$?
set -e

if [[ "$status" == "0" ]]; then
  echo "Official scheme gate succeeded. Log: $LOG_PATH"
  exit 0
fi

echo "Official scheme gate failed. Log: $LOG_PATH" >&2
tail -n 80 "$LOG_PATH" >&2

if grep -Eq 'iOS [0-9.]+ is not installed|Unable to find a destination|Found no destinations' "$LOG_PATH"; then
  if [[ "$matching_runtime_present" == "no" ]]; then
    cat >&2 <<MSG

Destination selection is blocked. Install/select a simulator runtime that matches this Xcode
installation, then rerun this script. The helper build scripts can compile the targets, but they
do not replace this official scheme gate.
MSG
  elif [[ "$matching_runtime_present" == "yes" && "$scheme_lists_simulator_destination" == "no" ]]; then
    cat >&2 <<'MSG'

Destination selection is blocked even though the matching simulator runtime is installed. Xcode
is not listing an iOS Simulator destination for this scheme; inspect the Xcode destination resolver
state in the log. The helper build scripts can compile and launch the app, but they do not replace
this official scheme gate.
MSG
  else
    cat >&2 <<'MSG'

Destination selection is blocked. Inspect the destination diagnosis in the log, then install or
select a compatible simulator/device destination and rerun this script. The helper build scripts
can compile the targets, but they do not replace this official scheme gate.
MSG
  fi
fi

exit "$status"
