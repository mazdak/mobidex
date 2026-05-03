#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export MOBIDEX_SMOKE_AUTH="${MOBIDEX_SMOKE_AUTH:-password}"
export MOBIDEX_SMOKE_MODE="seed"
export MOBIDEX_STAY_ALIVE_ON_SUCCESS="${MOBIDEX_STAY_ALIVE_ON_SUCCESS:-1}"
export MOBIDEX_KEEP_SIMULATOR="${MOBIDEX_KEEP_SIMULATOR:-1}"
export MOBIDEX_SCREENSHOT_PATH="${MOBIDEX_SCREENSHOT_PATH:-/tmp/mobidex-manual-ui-seed.png}"

cat <<'EOF'
Manual UI seed mode

This starts Mobidex in the Simulator with a disposable password-auth SSH
server and fake Codex app-server target already saved in the app.

After the script reports success and says it is keeping the SSH server alive:

1. Open the Simulator window.
2. Select the saved "Smoke SSH" server if it is not already selected.
3. Tap Connect.
4. Open the seeded project and use the composer to start a turn.
5. Approve the command request when it appears.
6. Send a steer message while the turn is active.
7. Tap Stop to interrupt the active turn.

Stop this script to clean up the disposable SSH server and work directory.
EOF

exec "$ROOT_DIR/Scripts/verify-inapp-ssh-smoke.sh"
