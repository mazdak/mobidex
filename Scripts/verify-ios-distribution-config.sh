#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

plutil -lint \
  .asc/export-options-adhoc.plist \
  .asc/export-options-testflight.plist \
  >/dev/null

asc workflow validate --file .asc/workflow.json >/dev/null

build_settings="$(xcodebuild \
  -showBuildSettings \
  -project Mobidex.xcodeproj \
  -scheme Mobidex \
  -configuration Release \
  -destination generic/platform=iOS)"

printf '%s\n' "$build_settings" | rg -q "^[[:space:]]+PRODUCT_BUNDLE_IDENTIFIER = com\\.getresq\\.mobidex$"
printf '%s\n' "$build_settings" | rg -q "^[[:space:]]+DEVELOPMENT_TEAM = JX3932QCN8$"

echo "iOS distribution config is valid."
