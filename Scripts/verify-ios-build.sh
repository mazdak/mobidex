#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Mobidex.xcodeproj"
TARGET="${1:-Mobidex}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SDK="${SDK:-iphonesimulator}"
DEFAULT_SOURCE_PACKAGES_DIR="${TMPDIR:-/tmp}/mobidex-source-packages"
SOURCE_PACKAGES_DIR="${MOBIDEX_SOURCE_PACKAGES_DIR:-$DEFAULT_SOURCE_PACKAGES_DIR}"

case "$SDK" in
  iphonesimulator | iphoneos)
    ;;
  *)
    echo "This verification helper supports SDK=iphonesimulator or SDK=iphoneos." >&2
    exit 2
    ;;
esac

PLATFORM_BUILD_DIR="$CONFIGURATION-$SDK"
if [[ -z "${LOG_PATH:-}" ]]; then
  if [[ "$SDK" == "iphonesimulator" ]]; then
    LOG_PATH="/tmp/mobidex-${TARGET}-verify.log"
  else
    LOG_PATH="/tmp/mobidex-${TARGET}-${SDK}-verify.log"
  fi
fi

xcodebuild \
  -resolvePackageDependencies \
  -project "$PROJECT_PATH" \
  -scheme Mobidex \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  >/dev/null

CHECKOUTS_DIR="$SOURCE_PACKAGES_DIR/checkouts"
if [[ ! -d "$CHECKOUTS_DIR" ]]; then
  echo "Could not find package checkouts at $CHECKOUTS_DIR." >&2
  exit 2
fi

PACKAGE_NAMES=(
  swift-asn1
  swift-collections
  swift-atomics
  swift-nio
  swift-nio-ssh
  swift-crypto
  swift-log
  BigInt
  swift-system
  Citadel
  gitdiff
)

include_paths=()
for package_name in "${PACKAGE_NAMES[@]}"; do
  include_paths+=("$CHECKOUTS_DIR/$package_name/build/$PLATFORM_BUILD_DIR")
done
include_setting="\$(inherited) ${include_paths[*]}"

prepare_package_outputs() {
  local generated_module_maps="GeneratedModuleMaps-$SDK"
  local nio_module_maps="$CHECKOUTS_DIR/swift-nio/build/$generated_module_maps"
  local destination

  if [[ -d "$nio_module_maps" ]]; then
    for destination in \
      "$ROOT_DIR/build/$generated_module_maps" \
      "$CHECKOUTS_DIR/swift-nio-ssh/build/$generated_module_maps" \
      "$CHECKOUTS_DIR/Citadel/build/$generated_module_maps"; do
      mkdir -p "$destination"
      find "$nio_module_maps" -maxdepth 1 -name 'CNIO*.modulemap' -print0 |
        while IFS= read -r -d '' modulemap; do
          ln -sfn "$modulemap" "$destination/$(basename "$modulemap")"
        done
    done
  fi

  mkdir -p "$ROOT_DIR/build/$PLATFORM_BUILD_DIR"
  find "$CHECKOUTS_DIR" -path "*/build/$PLATFORM_BUILD_DIR/*.bundle" -maxdepth 6 -print0 |
    while IFS= read -r -d '' bundle; do
      ln -sfn "$bundle" "$ROOT_DIR/build/$PLATFORM_BUILD_DIR/$(basename "$bundle")"
    done
}

run_build() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -target "$TARGET" \
    -sdk "$SDK" \
    -configuration "$CONFIGURATION" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CLANG_ENABLE_EXPLICIT_MODULES=NO \
    SWIFT_ENABLE_EXPLICIT_MODULES=NO \
    "SWIFT_INCLUDE_PATHS=$include_setting" \
    -jobs 1 \
    >"$LOG_PATH" 2>&1
}

prepare_package_outputs
if ! run_build; then
  prepare_package_outputs
  run_build
fi

echo "Build succeeded for target $TARGET. Log: $LOG_PATH"
