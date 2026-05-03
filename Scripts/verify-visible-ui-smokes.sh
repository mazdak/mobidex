#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_DIR="${MOBIDEX_VISIBLE_SCREENSHOT_DIR:-/tmp/mobidex-visible-ui-smokes}"
TIMEOUT="${MOBIDEX_SMOKE_TIMEOUT:-120}"

case "$TIMEOUT" in
  "" | *[!0-9]*)
    echo "MOBIDEX_SMOKE_TIMEOUT must be a positive integer number of seconds." >&2
    exit 1
    ;;
esac

if (( 10#$TIMEOUT < 1 )); then
  echo "MOBIDEX_SMOKE_TIMEOUT must be a positive integer number of seconds." >&2
  exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

run_smoke() {
  local mode="$1"
  local screenshot_path="$SCREENSHOT_DIR/$mode.png"

  rm -f "$screenshot_path"

  MOBIDEX_SMOKE_AUTH=password \
  MOBIDEX_SMOKE_MODE="$mode" \
  MOBIDEX_SMOKE_TIMEOUT="$TIMEOUT" \
  MOBIDEX_SCREENSHOT_PATH="$screenshot_path" \
    "$ROOT_DIR/Scripts/verify-inapp-ssh-smoke.sh"

  if [[ ! -s "$screenshot_path" ]]; then
    echo "Missing or empty screenshot: $screenshot_path" >&2
    exit 1
  fi
}

run_smoke approval
run_smoke control

echo "Visible UI smokes succeeded."
echo "Screenshots:"
echo "$SCREENSHOT_DIR/approval.png"
echo "$SCREENSHOT_DIR/control.png"
