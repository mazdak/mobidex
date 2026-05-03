#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_SOURCE="$ROOT_DIR/Sources/Mobidex/Services/RemoteCodexDiscovery.swift"
WORK_DIR="$(mktemp -d)"
CODEX_HOME_DIR="$WORK_DIR/codex-home"
APP_DIR="$WORK_DIR/projects/app"
WORKTREE_DIR="$WORK_DIR/worktrees/app-linked"
WORKTREE_ONLY_MAIN_DIR="$WORK_DIR/projects/worktree-only-main"
WORKTREE_ONLY_DIR="$WORK_DIR/worktrees/worktree-only-linked"
CONFIG_ONLY_DIR="$WORK_DIR/projects/config-only"
MISSING_CONFIG_DIR="$WORK_DIR/projects/missing-config"
MISSING_SESSION_DIR="$WORK_DIR/projects/missing-session"
PYTHON_SOURCE="$WORK_DIR/discovery.py"
SHELL_COMMAND="$WORK_DIR/discovery-command.sh"
SHELL_INPUT="$WORK_DIR/discovery-shell-input.sh"
EXIT_CHECK="$WORK_DIR/discovery-exit-check.sh"
OUTPUT_JSON="$WORK_DIR/projects.json"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ruby -0ne 'match = $_.match(/static let pythonSource = #"""\n(.*?)\n"""#/m); abort("Could not extract pythonSource") unless match; print match[1]' \
  "$SWIFT_SOURCE" >"$PYTHON_SOURCE"

EXPECTED_SWIFT_LINE=$'    static let shellCommand = "python3 - <<\'PY\'\\n\\(pythonSource)\\nPY\\nmobidex_status=$?;exit $mobidex_status"'
if ! grep -Fxq "$EXPECTED_SWIFT_LINE" "$SWIFT_SOURCE"; then
  echo "RemoteCodexDiscovery.shellCommand does not preserve the heredoc terminator before Citadel's ;exit suffix." >&2
  exit 1
fi

mkdir -p \
  "$CODEX_HOME_DIR/sessions/2026/05/02" \
  "$CODEX_HOME_DIR/archived_sessions/2026/05/01" \
  "$CODEX_HOME_DIR/sessions/ignored" \
  "$APP_DIR" \
  "$WORKTREE_ONLY_MAIN_DIR" \
  "$CONFIG_ONLY_DIR" \
  "$(dirname "$WORKTREE_DIR")"

git -C "$APP_DIR" init -q
git -C "$APP_DIR" config user.email "mobidex@example.com"
git -C "$APP_DIR" config user.name "Mobidex"
touch "$APP_DIR/README.md"
git -C "$APP_DIR" add README.md
git -C "$APP_DIR" commit -q -m init
git -C "$APP_DIR" worktree add -q "$WORKTREE_DIR"

git -C "$WORKTREE_ONLY_MAIN_DIR" init -q
git -C "$WORKTREE_ONLY_MAIN_DIR" config user.email "mobidex@example.com"
git -C "$WORKTREE_ONLY_MAIN_DIR" config user.name "Mobidex"
touch "$WORKTREE_ONLY_MAIN_DIR/README.md"
git -C "$WORKTREE_ONLY_MAIN_DIR" add README.md
git -C "$WORKTREE_ONLY_MAIN_DIR" commit -q -m init
git -C "$WORKTREE_ONLY_MAIN_DIR" worktree add -q "$WORKTREE_ONLY_DIR"

cat >"$CODEX_HOME_DIR/config.toml" <<EOF
[projects."$CONFIG_ONLY_DIR"]
trusted = true

[projects."$APP_DIR"]
trusted = true

[projects."$MISSING_CONFIG_DIR"]
trusted = true
EOF

cat >"$CODEX_HOME_DIR/sessions/2026/05/02/rollout-1.jsonl" <<EOF
{"type":"session_meta","payload":{"cwd":"$APP_DIR"}}
{"type":"turn","payload":{"message":"hello"}}
EOF

cat >"$CODEX_HOME_DIR/sessions/2026/05/02/rollout-2.jsonl" <<EOF
{"type":"noise"}
{"type":"session_meta","payload":{"cwd":
{"type":"session_meta","payload":{"nested":{"cwd":"$APP_DIR"}}}
EOF

cat >"$CODEX_HOME_DIR/sessions/2026/05/02/rollout-worktree.jsonl" <<EOF
{"type":"session_meta","payload":{"cwd":"$WORKTREE_DIR"}}
EOF

cat >"$CODEX_HOME_DIR/sessions/2026/05/02/rollout-worktree-only.jsonl" <<EOF
{"type":"session_meta","payload":{"cwd":"$WORKTREE_ONLY_DIR"}}
EOF

cat >"$CODEX_HOME_DIR/archived_sessions/2026/05/01/rollout-3.jsonl" <<EOF
{"type":"session_meta","payload":{"current_dir":"$APP_DIR"}}
EOF

cat >"$CODEX_HOME_DIR/sessions/ignored/rollout-ignored.jsonl" <<'EOF'
{"type":"session_meta","payload":{"message":"missing cwd"}}
EOF

cat >"$CODEX_HOME_DIR/sessions/ignored/rollout-missing.jsonl" <<EOF
{"type":"session_meta","payload":{"cwd":"$MISSING_SESSION_DIR"}}
EOF

touch -t 202605020101 "$CODEX_HOME_DIR/config.toml"
touch -t 202605020202 "$CODEX_HOME_DIR/sessions/2026/05/02/rollout-1.jsonl"
touch -t 202605020303 "$CODEX_HOME_DIR/sessions/2026/05/02/rollout-2.jsonl"
touch -t 202605020404 "$CODEX_HOME_DIR/sessions/2026/05/02/rollout-worktree-only.jsonl"
touch -t 202605020505 "$CODEX_HOME_DIR/sessions/2026/05/02/rollout-worktree.jsonl"
touch -t 202605010404 "$CODEX_HOME_DIR/archived_sessions/2026/05/01/rollout-3.jsonl"

{
  printf "python3 - <<'PY'\n"
  cat "$PYTHON_SOURCE"
  printf '\nPY\nmobidex_status=$?;exit $mobidex_status'
} >"$SHELL_COMMAND"

{
  cat "$SHELL_COMMAND"
  printf ";exit\n"
} >"$SHELL_INPUT"

python3 - "$SHELL_INPUT" <<'PY'
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    contents = handle.read()

assert "\nPY\nmobidex_status=$?;exit $mobidex_status;exit\n" in contents, contents[-120:]
assert "\nPY;exit\n" not in contents, contents[-120:]
assert "\n;exit\n" not in contents, contents[-120:]
PY

{
  printf "python3 - <<'PY'\n"
  printf 'import sys\nsys.exit(17)\n'
  printf 'PY\nmobidex_status=$?;exit $mobidex_status;exit\n'
} >"$EXIT_CHECK"

set +e
bash "$EXIT_CHECK" >/dev/null 2>&1
exit_status=$?
set -e

if [[ "$exit_status" != "17" ]]; then
  echo "Discovery shell wrapper did not preserve Python exit status; got $exit_status." >&2
  exit 1
fi

if command -v zsh >/dev/null 2>&1; then
  set +e
  zsh "$EXIT_CHECK" >/dev/null 2>&1
  exit_status=$?
  set -e

  if [[ "$exit_status" != "17" ]]; then
    echo "Discovery shell wrapper did not preserve Python exit status under zsh; got $exit_status." >&2
    exit 1
  fi
fi

CODEX_HOME="$CODEX_HOME_DIR" bash "$SHELL_INPUT" >"$OUTPUT_JSON"

python3 - "$OUTPUT_JSON" "$APP_DIR" "$WORKTREE_DIR" "$WORKTREE_ONLY_MAIN_DIR" "$WORKTREE_ONLY_DIR" "$CONFIG_ONLY_DIR" "$MISSING_CONFIG_DIR" "$MISSING_SESSION_DIR" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    projects = json.load(handle)

app_dir, worktree_dir, worktree_only_main_dir, worktree_only_dir, config_only_dir, missing_config_dir, missing_session_dir = [
    os.path.realpath(path) for path in sys.argv[2:]
]
by_path = {project["path"]: project for project in projects}

assert [project["path"] for project in projects] == [
    app_dir,
    worktree_only_main_dir,
    config_only_dir,
], projects
assert by_path[app_dir]["threadCount"] == 3, projects
assert by_path[app_dir]["sessionPaths"] == [app_dir, worktree_dir], projects
assert by_path[app_dir]["lastSeenAt"] is not None, projects
assert by_path[worktree_only_main_dir]["threadCount"] == 1, projects
assert by_path[worktree_only_main_dir]["sessionPaths"] == [worktree_only_main_dir, worktree_only_dir], projects
assert by_path[config_only_dir]["threadCount"] == 0, projects
assert by_path[config_only_dir]["sessionPaths"] == [config_only_dir], projects
assert by_path[config_only_dir]["lastSeenAt"] is not None, projects
assert missing_config_dir not in by_path, projects
assert missing_session_dir not in by_path, projects
PY

echo "Discovery verification succeeded."
