#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DISCOVERY_SOURCE="$ROOT_DIR/Sources/Mobidex/Services/RemoteCodexDiscovery.swift"
HOST="${MOBIDEX_SSH_HOST:-}"
USER="${MOBIDEX_SSH_USER:-}"
PORT="${MOBIDEX_SSH_PORT:-22}"
IDENTITY_FILE="${MOBIDEX_SSH_IDENTITY_FILE:-}"
CODEX_HOME_VALUE="${MOBIDEX_CODEX_HOME:-}"
CODEX_PATH="${MOBIDEX_CODEX_PATH:-codex}"
LIVE_CREATE_THREAD="${MOBIDEX_LIVE_CREATE_THREAD:-0}"
LIVE_CREATE_TURN="${MOBIDEX_LIVE_CREATE_TURN:-0}"
LIVE_TURN_PROMPT="${MOBIDEX_LIVE_TURN_PROMPT:-Reply exactly: mobidex live verification.}"
LIVE_TURN_TIMEOUT="${MOBIDEX_LIVE_TURN_TIMEOUT:-180}"
LIVE_CWD="${MOBIDEX_LIVE_CWD:-}"
REMOTE_LIVE_CWD_CREATED=0

fail() {
  echo "Live host verification failed: $*" >&2
  exit 1
}

quote_remote_executable() {
  local value="$1"
  local rest
  if [[ "$value" == "~" ]]; then
    printf '"${HOME}"'
  elif [[ "$value" == "~/"* ]]; then
    rest="${value#\~/}"
    printf -v rest "%q" "$rest"
    printf '"${HOME}"/%s' "$rest"
  else
    printf "%q" "$value"
  fi
}

if [[ -z "$HOST" || -z "$USER" ]]; then
  fail "set MOBIDEX_SSH_HOST and MOBIDEX_SSH_USER. Optional: MOBIDEX_SSH_PORT, MOBIDEX_SSH_IDENTITY_FILE, MOBIDEX_CODEX_HOME, MOBIDEX_CODEX_PATH."
fi

ssh_args=(
  -p "$PORT"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

if [[ -n "$IDENTITY_FILE" ]]; then
  ssh_args+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
fi

remote="${USER}@${HOST}"
work_dir="$(mktemp -d)"
discovery_py="$work_dir/discovery.py"
discovery_command="$work_dir/discovery-command.sh"
discovery_json="$work_dir/projects.json"

cleanup() {
  rm -rf "$work_dir"
  if [[ "$REMOTE_LIVE_CWD_CREATED" == "1" && -n "$LIVE_CWD" ]]; then
    local quoted_live_cwd
    local quoted_codex_home
    local codex_home_assignment
    quoted_live_cwd="$(quote_remote_executable "$LIVE_CWD")"
    codex_home_assignment=""
    if [[ -n "$CODEX_HOME_VALUE" ]]; then
      quoted_codex_home="$(quote_remote_executable "$CODEX_HOME_VALUE")"
      codex_home_assignment="CODEX_HOME=$quoted_codex_home "
    fi
    ssh "${ssh_args[@]}" "$remote" "LIVE_CWD=$quoted_live_cwd ${codex_home_assignment}python3 - <<'PY'
import json
import os
from pathlib import Path

live_cwd = os.environ['LIVE_CWD']
codex_home = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex').expanduser()
config_path = codex_home / 'config.toml'
if config_path.exists():
    target = '[projects.' + json.dumps(live_cwd) + ']'
    lines = config_path.read_text(encoding='utf-8').splitlines(keepends=True)
    output = []
    skipping = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            if stripped == target:
                skipping = True
                continue
            if skipping:
                skipping = False
        if not skipping:
            output.append(line)
    if output != lines:
        config_path.write_text(''.join(output), encoding='utf-8')
PY
rm -rf -- $quoted_live_cwd" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ruby -0ne 'match = $_.match(/static let pythonSource = #"""\n(.*?)\n"""#/m); abort("Could not extract pythonSource") unless match; print match[1]' \
  "$SWIFT_DISCOVERY_SOURCE" >"$discovery_py"

{
  if [[ -n "$CODEX_HOME_VALUE" ]]; then
    printf -v quoted_codex_home "%q" "$CODEX_HOME_VALUE"
    printf "export CODEX_HOME=%s\n" "$quoted_codex_home"
  fi
  printf "python3 - <<'PY'\n"
  cat "$discovery_py"
  printf '\nPY\nmobidex_status=$?;exit $mobidex_status'
} >"$discovery_command"

echo "Checking SSH command execution..."
ssh "${ssh_args[@]}" "$remote" 'printf mobidex-ready' | grep -Fxq mobidex-ready

echo "Checking remote requirements..."
quoted_codex_path="$(quote_remote_executable "$CODEX_PATH")"
ssh "${ssh_args[@]}" "$remote" "python3 --version >/dev/null && $quoted_codex_path --version >/dev/null"

if [[ -z "$LIVE_CWD" && ( "$LIVE_CREATE_THREAD" == "1" || "$LIVE_CREATE_TURN" == "1" ) ]]; then
  LIVE_CWD="$(
    ssh "${ssh_args[@]}" "$remote" 'mktemp -d "$HOME/.mobidex-live-verify.XXXXXX"'
  )"
  REMOTE_LIVE_CWD_CREATED=1
fi

echo "Running remote Codex project discovery..."
set +e
ssh "${ssh_args[@]}" "$remote" "$(cat "$discovery_command")" >"$discovery_json" 2>&1
discovery_status=$?
set -e

if [[ "$discovery_status" != "0" ]]; then
  fail "remote discovery command exited with $discovery_status: $(cat "$discovery_json")"
fi

python3 - "$discovery_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    projects = json.load(handle)

if not isinstance(projects, list):
    raise SystemExit("discovery did not return a JSON array")
for project in projects:
    if not isinstance(project, dict) or not isinstance(project.get("path"), str):
        raise SystemExit(f"invalid discovered project entry: {project!r}")
print(f"Discovery returned {len(projects)} project(s).")
PY

echo "Checking Codex app-server stdio thread list and optional read..."
python3 - "$HOST" "$USER" "$PORT" "$IDENTITY_FILE" "$CODEX_PATH" "$CODEX_HOME_VALUE" "$discovery_json" "$LIVE_CREATE_THREAD" "$LIVE_CREATE_TURN" "$LIVE_TURN_PROMPT" "$LIVE_TURN_TIMEOUT" "$LIVE_CWD" <<'PY'
import json
import os
import selectors
import shlex
import subprocess
import sys
import time

host, user, port, identity_file, codex_path, codex_home, discovery_json, live_create_thread, live_create_turn, live_turn_prompt, live_turn_timeout, live_cwd = sys.argv[1:13]
live_turn_timeout = int(live_turn_timeout)

def quote_remote_executable(value):
    if value == "~":
        return '"${HOME}"'
    if value.startswith("~/"):
        return '"${HOME}"/' + shlex.quote(value[2:])
    return shlex.quote(value)

def quote_remote_env_assignment(name, value):
    if not value:
        return ""
    return f"{name}={quote_remote_executable(value)} "

cmd = [
    "ssh",
    "-p",
    port,
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "StrictHostKeyChecking=accept-new",
]
if identity_file:
    cmd.extend(["-i", identity_file, "-o", "IdentitiesOnly=yes"])
cmd.extend([
    f"{user}@{host}",
    f"{quote_remote_env_assignment('CODEX_HOME', codex_home)}{quote_remote_executable(codex_path)} app-server --listen stdio://",
])

process = subprocess.Popen(
    cmd,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    bufsize=1,
)

next_id = 1
notifications = []
created_thread_id = None
active_turn_id = None
active_turn_thread_id = None

def read_message(timeout):
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            events = selector.select(deadline - time.monotonic())
            if not events:
                continue
            candidate = process.stdout.readline()
            if not candidate:
                continue
            return json.loads(candidate)
        return None
    finally:
        selector.close()

def request(method, params=None, timeout=30):
    global next_id
    assert process.stdin is not None
    request_id = next_id
    next_id += 1
    payload = {"jsonrpc": "2.0", "id": request_id, "method": method}
    if params is not None:
        payload["params"] = params
    process.stdin.write(json.dumps(payload) + "\n")
    process.stdin.flush()

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        response = read_message(max(0.1, deadline - time.monotonic()))
        if response is None:
            break
        if response.get("method") and response.get("id") is not None:
            raise SystemExit(
                "app-server requested "
                f"{response.get('method')!r} during live verification; this verifier cannot answer server requests"
            )
        if response.get("method"):
            notifications.append(response)
            continue
        if response.get("id") != request_id:
            continue
        if "error" in response:
            raise SystemExit(f"{method} failed: {response['error']!r}")
        if "result" not in response:
            raise SystemExit(f"{method} response did not include result: {response!r}")
        return response["result"]
    raise SystemExit(f"timed out waiting for {method} response")

def wait_notification(method, thread_id=None, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        notification = pop_notification(method, thread_id=thread_id)
        if notification is not None:
            return notification
        message = read_message(max(0.1, deadline - time.monotonic()))
        if message is None:
            continue
        if message.get("method") and message.get("id") is not None:
            raise SystemExit(
                "app-server requested "
                f"{message.get('method')!r} during live verification; this verifier cannot answer server requests"
            )
        if message.get("method"):
            notifications.append(message)
    raise SystemExit(f"timed out waiting for {method} notification")

def pop_notification(method, thread_id=None):
    for index, message in enumerate(notifications):
        if message.get("method") != method:
            continue
        params = message.get("params") or {}
        if thread_id is not None and params.get("threadId") != thread_id:
            continue
        return notifications.pop(index)
    return None

def wait_completed_turn(thread_id, started_turn, timeout=60):
    if started_turn.get("status") == "completed":
        return started_turn

    turn_id = started_turn.get("id")
    deadline = time.monotonic() + timeout
    next_read_at = time.monotonic()
    last_read_error = None
    while time.monotonic() < deadline:
        notification = pop_notification("turn/completed", thread_id=thread_id)
        if notification is not None:
            completed_params = notification.get("params") or {}
            completed_turn = completed_params.get("turn")
            if not isinstance(completed_turn, dict):
                raise SystemExit(f"turn/completed did not include a turn: {notification!r}")
            return completed_turn

        now = time.monotonic()
        if now >= next_read_at:
            try:
                read_result = request(
                    "thread/read",
                    {"threadId": thread_id, "includeTurns": True},
                    timeout=min(10, max(1, int(deadline - now))),
                )
                thread = read_result.get("thread")
                turns = thread.get("turns") if isinstance(thread, dict) else None
                if isinstance(turns, list):
                    matching_turn = next(
                        (candidate for candidate in turns if isinstance(candidate, dict) and candidate.get("id") == turn_id),
                        None,
                    )
                    if isinstance(matching_turn, dict) and matching_turn.get("status") != "inProgress":
                        return matching_turn
            except SystemExit as error:
                last_read_error = str(error)
            next_read_at = time.monotonic() + 5

        message = read_message(min(1, max(0.1, deadline - time.monotonic())))
        if message is None:
            continue
        if message.get("method") and message.get("id") is not None:
            raise SystemExit(
                "app-server requested "
                f"{message.get('method')!r} during live verification; this verifier cannot answer server requests"
            )
        if message.get("method"):
            notifications.append(message)

    detail = f"; last thread/read error: {last_read_error}" if last_read_error else ""
    raise SystemExit(f"timed out waiting for completed turn {turn_id} on {thread_id}{detail}")

def list_threads(cwd):
    params = {
        "limit": 10,
        "sortKey": "updated_at",
        "sortDirection": "desc",
        "archived": False,
        "sourceKinds": [
            "cli",
            "vscode",
            "exec",
            "appServer",
            "subAgent",
            "subAgentReview",
            "subAgentCompact",
            "subAgentThreadSpawn",
            "subAgentOther",
            "unknown",
        ],
    }
    if cwd:
        params["cwd"] = cwd
    result = request("thread/list", params, timeout=45)
    threads = result.get("data")
    if not isinstance(threads, list):
        raise SystemExit(f"thread/list returned invalid data: {result!r}")
    if cwd:
        mismatched = [thread for thread in threads if thread.get("cwd") != cwd]
        if mismatched:
            raise SystemExit(f"thread/list returned thread outside cwd {cwd!r}: {mismatched[0]!r}")
    return threads

try:
    initialize_result = request(
        "initialize",
        {
            "clientInfo": {"name": "mobidex-live-verify", "title": "Mobidex Live Verify", "version": "0.1.0"},
            "capabilities": {"experimentalApi": True},
        },
        timeout=10,
    )
    if not isinstance(initialize_result, dict):
        raise SystemExit(f"unexpected initialize result: {initialize_result!r}")

    process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "initialized"}) + "\n")
    process.stdin.flush()

    with open(discovery_json, "r", encoding="utf-8") as handle:
        projects = json.load(handle)

    candidates = []
    seen = set()
    for project in sorted(projects, key=lambda item: item.get("threadCount") or 0, reverse=True):
        path = project.get("path")
        if isinstance(path, str) and path and path not in seen:
            candidates.append(path)
            seen.add(path)

    selected_cwd = None
    threads = []
    for cwd in candidates[:5]:
        selected_cwd = cwd
        threads = list_threads(cwd)
        print(f"thread/list returned {len(threads)} thread(s) for {cwd}.")
        if threads:
            break

    if not candidates:
        threads = list_threads(None)
        print(f"thread/list returned {len(threads)} unfiltered thread(s).")
    elif not threads:
        selected_cwd = None
        threads = list_threads(None)
        print(f"thread/list returned {len(threads)} unfiltered thread(s) after discovered project probes were empty.")

    if live_create_thread == "1":
        if not live_cwd:
            raise SystemExit("MOBIDEX_LIVE_CREATE_THREAD=1 requires MOBIDEX_LIVE_CWD or a resolvable remote HOME")
        start_result = request(
            "thread/start",
            {
                "cwd": live_cwd,
                "serviceName": "mobidex-live-verify",
                "ephemeral": True,
                "sandbox": "read-only",
                "approvalPolicy": "never",
            },
            timeout=45,
        )
        created_thread = start_result.get("thread")
        if not isinstance(created_thread, dict):
            raise SystemExit(f"thread/start returned invalid thread: {start_result!r}")
        created_thread_id = created_thread.get("id")
        if not isinstance(created_thread_id, str) or not created_thread_id:
            raise SystemExit(f"thread/start returned invalid thread id: {created_thread!r}")
        read_result = request("thread/read", {"threadId": created_thread_id, "includeTurns": False}, timeout=45)
        thread = read_result.get("thread")
        if not isinstance(thread, dict) or thread.get("id") != created_thread_id:
            raise SystemExit(f"thread/read returned unexpected created thread: {read_result!r}")
        if thread.get("ephemeral") is not True:
            raise SystemExit(f"thread/read did not return an ephemeral temporary thread: {thread!r}")
        print(
            "thread/start created and thread/read loaded temporary ephemeral no-turn thread "
            f"metadata {created_thread_id} in {live_cwd}."
        )
        created_thread_id = None

    if live_create_turn == "1":
        if not live_cwd:
            raise SystemExit("MOBIDEX_LIVE_CREATE_TURN=1 requires MOBIDEX_LIVE_CWD or a resolvable remote HOME")
        start_result = request(
            "thread/start",
            {
                "cwd": live_cwd,
                "serviceName": "mobidex-live-verify-turn",
                "ephemeral": False,
                "sandbox": "read-only",
                "approvalPolicy": "never",
            },
            timeout=45,
        )
        created_thread = start_result.get("thread")
        if not isinstance(created_thread, dict):
            raise SystemExit(f"thread/start returned invalid materialized thread: {start_result!r}")
        created_thread_id = created_thread.get("id")
        if not isinstance(created_thread_id, str) or not created_thread_id:
            raise SystemExit(f"thread/start returned invalid materialized thread id: {created_thread!r}")
        turn_result = request(
            "turn/start",
            {
                "threadId": created_thread_id,
                "input": [
                    {
                        "type": "text",
                        "text": live_turn_prompt,
                        "text_elements": [],
                    }
                ],
            },
            timeout=45,
        )
        turn = turn_result.get("turn")
        if not isinstance(turn, dict) or not isinstance(turn.get("id"), str):
            raise SystemExit(f"turn/start returned invalid turn: {turn_result!r}")
        active_turn_id = turn["id"]
        active_turn_thread_id = created_thread_id
        completed_turn = wait_completed_turn(created_thread_id, turn, timeout=live_turn_timeout)
        completed_status = completed_turn.get("status")
        if completed_status != "completed":
            error_detail = completed_turn.get("error")
            raise SystemExit(
                "materialized turn reported non-completed status "
                f"{completed_status!r} for {created_thread_id}: {json.dumps(error_detail, sort_keys=True)}"
            )
        active_turn_id = None
        active_turn_thread_id = None
        read_result = request("thread/read", {"threadId": created_thread_id, "includeTurns": True}, timeout=45)
        thread = read_result.get("thread")
        if not isinstance(thread, dict) or thread.get("id") != created_thread_id:
            raise SystemExit(f"thread/read returned unexpected materialized thread: {read_result!r}")
        turns = thread.get("turns")
        if not isinstance(turns, list) or not turns:
            raise SystemExit(f"thread/read did not include materialized turns: {thread!r}")
        print(
            "turn/start completed and thread/read hydrated temporary materialized thread "
            f"{created_thread_id} in {live_cwd} with {len(turns)} turn(s)."
        )
        request("thread/archive", {"threadId": created_thread_id}, timeout=45)
        print(f"Archived temporary materialized thread {created_thread_id}.")
        created_thread_id = None

    if threads:
        thread_id = threads[0].get("id")
        if not isinstance(thread_id, str) or not thread_id:
            raise SystemExit(f"thread/list returned invalid thread id: {threads[0]!r}")
        read_result = request("thread/read", {"threadId": thread_id, "includeTurns": True}, timeout=45)
        thread = read_result.get("thread")
        if not isinstance(thread, dict) or thread.get("id") != thread_id:
            raise SystemExit(f"thread/read returned unexpected thread: {read_result!r}")
        if not isinstance(thread.get("turns"), list):
            raise SystemExit(f"thread/read did not include turns: {thread!r}")
        cwd_detail = f" in {selected_cwd}" if selected_cwd else ""
        print(f"thread/read hydrated thread {thread_id}{cwd_detail} with {len(thread['turns'])} turn(s).")
    else:
        print("No threads returned; thread/read skipped.")
finally:
    if active_turn_id and active_turn_thread_id:
        try:
            request(
                "turn/interrupt",
                {"threadId": active_turn_thread_id, "turnId": active_turn_id},
                timeout=10,
            )
        except BaseException:
            pass
    if created_thread_id:
        try:
            request("thread/archive", {"threadId": created_thread_id}, timeout=10)
        except BaseException:
            pass
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()

print("App-server thread list probe succeeded.")
PY

echo "Live host verification succeeded."
