#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISCOVERY_SOURCE="$ROOT_DIR/shared-core/src/commonMain/kotlin/mobidex/shared/RemoteCodexDiscovery.kt"
WORK_DIR="$(mktemp -d)"
PYTHON_SOURCE="$WORK_DIR/discovery.py"
SHELL_COMMAND="$WORK_DIR/discovery-command.sh"
SHELL_INPUT="$WORK_DIR/discovery-shell-input.sh"
EXIT_CHECK="$WORK_DIR/discovery-exit-check.sh"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ruby -0ne 'match = $_.match(/val pythonSource: String = """\n(.*?)\n"""\.trimIndent\(\)/m); abort("Could not extract pythonSource") unless match; print match[1]' \
  "$DISCOVERY_SOURCE" >"$PYTHON_SOURCE"

EXPECTED_KOTLIN_LINE='            "python3 - <<'\''PY'\''\n$pythonSource\nPY\nmobidex_status=\$?;exit \$mobidex_status",'
if ! grep -Fxq "$EXPECTED_KOTLIN_LINE" "$DISCOVERY_SOURCE"; then
  echo "RemoteCodexDiscovery.shellCommand does not preserve the heredoc terminator before Citadel's ;exit suffix." >&2
  exit 1
fi

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

make_git_worktree() {
  local main_dir="$1"
  local worktree_dir="$2"
  mkdir -p "$main_dir" "$(dirname "$worktree_dir")"
  git -C "$main_dir" init -q
  git -C "$main_dir" config user.email "mobidex@example.com"
  git -C "$main_dir" config user.name "Mobidex"
  touch "$main_dir/README.md"
  git -C "$main_dir" add README.md
  git -C "$main_dir" commit -q -m init
  local branch_name
  branch_name="mobidex-${worktree_dir##*/}-$(basename "$(dirname "$worktree_dir")")"
  git -C "$main_dir" worktree add -q -b "$branch_name" "$worktree_dir"
}

CODEX_HOME_DIR="$WORK_DIR/codex-home"
APP_DIR="$WORK_DIR/projects/app"
WORKTREE_DIR="$WORK_DIR/.codex/worktrees/a1b2/app"
WORKTREE_ONLY_MAIN_DIR="$WORK_DIR/projects/worktree-only-main"
WORKTREE_ONLY_DIR="$WORK_DIR/.codex/worktrees/c3d4/worktree-only-main"
REMOTE_PROJECT_DIR="$WORK_DIR/projects/remote-project"
ZERO_SESSION_DIR="$WORK_DIR/projects/zero-session"
NOISY_CONFIG_DIR="$WORK_DIR/projects/noisy-config"
MISSING_DIR="$WORK_DIR/projects/missing"
HIDDEN_VERIFY_DIR="$WORK_DIR/.mobdex-live-verify"
OUTPUT_JSON="$WORK_DIR/projects.json"

make_git_worktree "$APP_DIR" "$WORKTREE_DIR"
make_git_worktree "$WORKTREE_ONLY_MAIN_DIR" "$WORKTREE_ONLY_DIR"
mkdir -p "$CODEX_HOME_DIR" "$REMOTE_PROJECT_DIR" "$ZERO_SESSION_DIR" "$NOISY_CONFIG_DIR" "$HIDDEN_VERIFY_DIR"

cat >"$CODEX_HOME_DIR/config.toml" <<EOF
[projects."$NOISY_CONFIG_DIR"]
trusted = true
EOF

python3 - "$CODEX_HOME_DIR" "$APP_DIR" "$WORKTREE_DIR" "$WORKTREE_ONLY_MAIN_DIR" "$WORKTREE_ONLY_DIR" "$REMOTE_PROJECT_DIR" "$ZERO_SESSION_DIR" "$MISSING_DIR" "$HIDDEN_VERIFY_DIR" <<'PY'
import json
import os
import sqlite3
import sys

codex_home, app_dir, worktree_dir, worktree_main, worktree_dir_only, remote_dir, zero_dir, missing_dir, hidden_dir = sys.argv[1:]
state = {
    "project-order": [app_dir, "437fb22f-f9ce-4f74-964e-907cb8084df8", zero_dir, missing_dir],
    "electron-saved-workspace-roots": [app_dir, zero_dir],
    "active-workspace-roots": [app_dir],
    "remote-projects": [
        {
            "id": "437fb22f-f9ce-4f74-964e-907cb8084df8",
            "remotePath": remote_dir,
            "label": "remote-project",
        }
    ],
    "thread-workspace-root-hints": {
        "thread-app-main": missing_dir,
        "thread-worktree-only": worktree_main,
    },
}
with open(os.path.join(codex_home, ".codex-global-state.json"), "w", encoding="utf-8") as handle:
    json.dump(state, handle)

connection = sqlite3.connect(os.path.join(codex_home, "state_5.sqlite"))
connection.execute(
    "create table threads (id text, cwd text, title text, updated_at integer, source text, archived integer)"
)
rows = [
    ("thread-app-main", app_dir, "main", 1770000300, "cli", 0),
    ("thread-app-worktree", worktree_dir, "worktree", 1770000400, "vscode", 0),
    ("thread-remote", remote_dir, "remote project", 1770000350, "cli", 0),
    ("thread-app-archived", app_dir, "archived", 1770000500, "cli", 1),
    ("thread-app-review", app_dir, "review", 1770000600, '{"subagent":"review"}', 0),
    ("thread-worktree-only", worktree_dir_only, "worktree only", 1770000200, "vscode", 0),
    ("thread-hidden", hidden_dir, "hidden smoke", 1770000700, "cli", 0),
]
connection.executemany("insert into threads values (?, ?, ?, ?, ?, ?)", rows)
connection.commit()
PY

CODEX_HOME="$CODEX_HOME_DIR" bash "$SHELL_INPUT" >"$OUTPUT_JSON"

python3 - "$OUTPUT_JSON" "$APP_DIR" "$WORKTREE_DIR" "$WORKTREE_ONLY_MAIN_DIR" "$WORKTREE_ONLY_DIR" "$REMOTE_PROJECT_DIR" "$ZERO_SESSION_DIR" "$NOISY_CONFIG_DIR" "$MISSING_DIR" "$HIDDEN_VERIFY_DIR" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    projects = json.load(handle)

app_dir, worktree_dir, worktree_main, worktree_dir_only, remote_dir, zero_dir, noisy_config_dir, missing_dir, hidden_dir = [
    os.path.realpath(path) for path in sys.argv[2:]
]
by_path = {project["path"]: project for project in projects}

assert [project["path"] for project in projects] == [app_dir, remote_dir, zero_dir], projects
assert by_path[app_dir]["discoveredSessionCount"] == 2, projects
assert by_path[app_dir]["archivedSessionCount"] == 1, projects
assert set(by_path[app_dir]["sessionPaths"]) == {app_dir, worktree_dir}, projects
assert by_path[app_dir]["lastDiscoveredAt"] == 1770000500, projects
assert by_path[remote_dir]["discoveredSessionCount"] == 1, projects
assert by_path[remote_dir]["archivedSessionCount"] == 0, projects
assert by_path[remote_dir]["sessionPaths"] == [remote_dir], projects
assert by_path[remote_dir]["lastDiscoveredAt"] == 1770000350, projects
assert by_path[zero_dir]["discoveredSessionCount"] == 0, projects
assert by_path[zero_dir]["archivedSessionCount"] == 0, projects
assert by_path[zero_dir]["sessionPaths"] == [zero_dir], projects
assert by_path[zero_dir]["lastDiscoveredAt"] is None, projects
assert worktree_main not in by_path, projects
assert noisy_config_dir not in by_path, projects
assert missing_dir not in by_path, projects
assert hidden_dir not in by_path, projects
PY

FALLBACK_HOME="$WORK_DIR/fallback-codex-home"
FALLBACK_MAIN="$WORK_DIR/fallback/main"
FALLBACK_WORKTREE="$WORK_DIR/fallback/.codex/worktrees/f5g6/fallback-main"
FALLBACK_HIDDEN="$WORK_DIR/fallback/.hidden"
FALLBACK_OUTPUT="$WORK_DIR/fallback-projects.json"

make_git_worktree "$FALLBACK_MAIN" "$FALLBACK_WORKTREE"
mkdir -p "$FALLBACK_HOME" "$FALLBACK_HIDDEN"

python3 - "$FALLBACK_HOME" "$FALLBACK_WORKTREE" "$FALLBACK_HIDDEN" <<'PY'
import os
import sqlite3
import sys

codex_home, worktree_dir, hidden_dir = sys.argv[1:]
connection = sqlite3.connect(os.path.join(codex_home, "state_5.sqlite"))
connection.execute(
    "create table threads (id text, cwd text, title text, updated_at integer, source text, archived integer)"
)
connection.executemany(
    "insert into threads values (?, ?, ?, ?, ?, ?)",
    [
        ("thread-fallback", worktree_dir, "fallback", 1770000100, "vscode", 0),
        ("thread-hidden", hidden_dir, "hidden", 1770000200, "cli", 0),
    ],
)
connection.commit()
PY

CODEX_HOME="$FALLBACK_HOME" bash "$SHELL_INPUT" >"$FALLBACK_OUTPUT"

python3 - "$FALLBACK_OUTPUT" "$FALLBACK_MAIN" "$FALLBACK_WORKTREE" "$FALLBACK_HIDDEN" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    projects = json.load(handle)

main_dir, worktree_dir, hidden_dir = [os.path.realpath(path) for path in sys.argv[2:]]
assert [project["path"] for project in projects] == [main_dir], projects
assert projects[0]["discoveredSessionCount"] == 1, projects
assert set(projects[0]["sessionPaths"]) == {main_dir, worktree_dir}, projects
assert hidden_dir not in projects[0]["sessionPaths"], projects
PY

CONFIG_ONLY_HOME="$WORK_DIR/config-only-codex-home"
CONFIG_ONLY_DIR="$WORK_DIR/config-only/project"
CONFIG_ONLY_OUTPUT="$WORK_DIR/config-only-projects.json"
mkdir -p "$CONFIG_ONLY_HOME" "$CONFIG_ONLY_DIR"
cat >"$CONFIG_ONLY_HOME/config.toml" <<EOF
[projects."$CONFIG_ONLY_DIR"]
trusted = true
EOF

CODEX_HOME="$CONFIG_ONLY_HOME" bash "$SHELL_INPUT" >"$CONFIG_ONLY_OUTPUT"

python3 - "$CONFIG_ONLY_OUTPUT" "$CONFIG_ONLY_DIR" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    projects = json.load(handle)

config_dir = os.path.realpath(sys.argv[2])
assert projects == [
    {
        "path": config_dir,
        "sessionPaths": [config_dir],
        "discoveredSessionCount": 0,
        "archivedSessionCount": 0,
        "lastDiscoveredAt": projects[0]["lastDiscoveredAt"],
    }
], projects
assert projects[0]["lastDiscoveredAt"] is not None, projects
PY

echo "Discovery verification succeeded."
