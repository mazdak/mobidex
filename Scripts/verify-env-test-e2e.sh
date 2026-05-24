#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_ENV_FILE="${MOBIDEX_SHARED_TEST_ENV:-"$HOME/.codex/mobidex/.env.test"}"
if [[ -n "${MOBIDEX_TEST_ENV:-}" ]]; then
  ENV_FILE="$MOBIDEX_TEST_ENV"
elif [[ -f "$ROOT_DIR/.env.test" ]]; then
  ENV_FILE="$ROOT_DIR/.env.test"
else
  ENV_FILE="$SHARED_ENV_FILE"
fi

usage() {
  cat >&2 <<'EOF'
Usage: Scripts/verify-env-test-e2e.sh [connection|new-session|join|visible-new-session]

Reads repo .env.test first, then ~/.codex/mobidex/.env.test.
Set MOBIDEX_TEST_ENV=/path/to/file to use another file.
See .env.test.example for supported variables.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing test environment file: $ENV_FILE" >&2
  echo "Create ~/.codex/mobidex/.env.test from .env.test.example, or set MOBIDEX_TEST_ENV." >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

MODE="${1:-${MOBIDEX_E2E_MODE:-new-session}}"

required() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required value in $ENV_FILE: $key" >&2
    exit 2
  fi
}

optional_export() {
  local target="$1"
  local source="$2"
  if [[ -n "${!source:-}" ]]; then
    export "$target=${!source}"
  fi
}

case "$MODE" in
  connection | new-session | join | visible-new-session)
    ;;
  *)
    echo "Unsupported E2E mode: $MODE" >&2
    usage
    exit 2
    ;;
esac

required MOBIDEX_E2E_HOST
required MOBIDEX_E2E_USER
required MOBIDEX_E2E_CWD

AUTH="${MOBIDEX_E2E_AUTH:-private-key}"
case "$AUTH" in
  private-key | privateKey)
    AUTH="private-key"
    if [[ -n "${MOBIDEX_E2E_PRIVATE_KEY_BASE64:-}" ]]; then
      export MOBIDEX_SMOKE_PRIVATE_KEY_BASE64="$MOBIDEX_E2E_PRIVATE_KEY_BASE64"
    else
      required MOBIDEX_E2E_PRIVATE_KEY_PATH
      if [[ ! -f "$MOBIDEX_E2E_PRIVATE_KEY_PATH" ]]; then
        echo "Private key file does not exist: $MOBIDEX_E2E_PRIVATE_KEY_PATH" >&2
        exit 2
      fi
      export MOBIDEX_SMOKE_PRIVATE_KEY_BASE64="$(base64 <"$MOBIDEX_E2E_PRIVATE_KEY_PATH" | tr -d '\n')"
    fi
    optional_export MOBIDEX_SMOKE_PRIVATE_KEY_PASSPHRASE MOBIDEX_E2E_PRIVATE_KEY_PASSPHRASE
    ;;
  password)
    required MOBIDEX_E2E_PASSWORD
    export MOBIDEX_SMOKE_PASSWORD="$MOBIDEX_E2E_PASSWORD"
    ;;
  *)
    echo "Unsupported MOBIDEX_E2E_AUTH: $AUTH. Use private-key or password." >&2
    exit 2
    ;;
esac

export MOBIDEX_SMOKE_AUTH="$AUTH"
export MOBIDEX_SMOKE_HOST="$MOBIDEX_E2E_HOST"
export MOBIDEX_SMOKE_USER="$MOBIDEX_E2E_USER"
export MOBIDEX_SMOKE_CWD="$MOBIDEX_E2E_CWD"
export MOBIDEX_SMOKE_PORT="${MOBIDEX_E2E_PORT:-22}"
export MOBIDEX_SMOKE_DISPLAY_NAME="${MOBIDEX_E2E_DISPLAY_NAME:-E2E SSH}"
export MOBIDEX_SMOKE_CODEX_PATH="${MOBIDEX_E2E_CODEX_PATH:-codex}"
export MOBIDEX_SMOKE_EXECUTION_PATH="${MOBIDEX_E2E_EXECUTION_PATH:-}"
export MOBIDEX_SMOKE_TIMEOUT="${MOBIDEX_E2E_TIMEOUT:-180}"
export MOBIDEX_SMOKE_SERVER_ID="${MOBIDEX_E2E_SERVER_ID:-$(uuidgen)}"
optional_export MOBIDEX_SMOKE_PROMPT MOBIDEX_E2E_PROMPT
optional_export MOBIDEX_SMOKE_EXPECTED_TEXT MOBIDEX_E2E_EXPECTED_TEXT
optional_export MOBIDEX_UI_SMOKE_PROMPT MOBIDEX_E2E_PROMPT
optional_export MOBIDEX_UI_SMOKE_EXPECTED_TEXT MOBIDEX_E2E_EXPECTED_TEXT

case "$MODE" in
  connection)
    export MOBIDEX_SMOKE_MODE=connection
    exec "$ROOT_DIR/Scripts/verify-live-host-smoke.sh"
    ;;
  new-session)
    export MOBIDEX_SMOKE_MODE=new-session
    export MOBIDEX_SMOKE_NEW_SESSION_LOCATION="${MOBIDEX_E2E_NEW_SESSION_LOCATION:-project-directory}"
    exec "$ROOT_DIR/Scripts/verify-live-host-smoke.sh"
    ;;
  join)
    export MOBIDEX_SMOKE_MODE=join
    exec "$ROOT_DIR/Scripts/verify-live-host-smoke.sh"
    ;;
  visible-new-session)
    export MOBIDEX_SMOKE_MODE=seed
    export MOBIDEX_UI_REAL_HOST_SMOKE=1
    export MOBIDEX_UI_NEW_SESSION_LOCATION="${MOBIDEX_E2E_NEW_SESSION_LOCATION:-project-directory}"
    export MOBIDEX_UI_SMOKE_TIMEOUT="${MOBIDEX_E2E_TIMEOUT:-180}"
    exec "$ROOT_DIR/Scripts/verify-live-host-ui-smoke.sh"
    ;;
esac
