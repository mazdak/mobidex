#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_STUDIO_JBR="${ANDROID_STUDIO_JBR:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
GRADLE_VERSION="${GRADLE_VERSION:-8.13}"
GRADLE_HOME="${ROOT_DIR}/build/gradle-${GRADLE_VERSION}"
GRADLE_ZIP="${ROOT_DIR}/build/gradle-${GRADLE_VERSION}-bin.zip"
GRADLE_URL="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
CONFIGURATION_NAME="${CONFIGURATION:-Debug}"
CONFIGURATION_LOWER="$(printf '%s' "$CONFIGURATION_NAME" | tr '[:upper:]' '[:lower:]')"
XCFRAMEWORK_NAME="MobidexShared.xcframework"
SOURCE_XCFRAMEWORK="${ROOT_DIR}/shared-core/build/XCFrameworks/${CONFIGURATION_LOWER}/${XCFRAMEWORK_NAME}"
TARGET_DIR="${ROOT_DIR}/build/shared-core"
TARGET_XCFRAMEWORK="${TARGET_DIR}/${XCFRAMEWORK_NAME}"

export JAVA_HOME="${JAVA_HOME:-$ANDROID_STUDIO_JBR}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$JAVA_HOME/bin:$PATH"

if [ ! -x "$JAVA_HOME/bin/java" ]; then
  echo "Java runtime not found at $JAVA_HOME" >&2
  exit 1
fi

if [ ! -x "$GRADLE_HOME/bin/gradle" ]; then
  mkdir -p "${ROOT_DIR}/build"
  curl --fail --location --output "$GRADLE_ZIP" "$GRADLE_URL"
  unzip -q -o "$GRADLE_ZIP" -d "${ROOT_DIR}/build"
fi

"$GRADLE_HOME/bin/gradle" \
  --no-daemon \
  --console=plain \
  -p "$ROOT_DIR" \
  ":shared-core:assembleMobidexShared${CONFIGURATION_NAME}XCFramework"

rm -rf "$TARGET_XCFRAMEWORK"
mkdir -p "$TARGET_DIR"
cp -R "$SOURCE_XCFRAMEWORK" "$TARGET_XCFRAMEWORK"
