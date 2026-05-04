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
LIVE_EXERCISE_LIFECYCLE="${MOBIDEX_LIVE_EXERCISE_LIFECYCLE:-0}"
LIVE_IMAGE_LOCAL_PATH="${MOBIDEX_LIVE_IMAGE_LOCAL_PATH:-$HOME/Downloads/download-latest-macos-app-badge-2x.png}"
LIVE_IMAGE_REMOTE_PATH=""
REMOTE_LIVE_CWD_CREATED=0
REMOTE_PATH_BOOTSTRAP='export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; '

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
ssh "${ssh_args[@]}" "$remote" "${REMOTE_PATH_BOOTSTRAP}python3 --version >/dev/null && $quoted_codex_path --version >/dev/null"

if [[ -z "$LIVE_CWD" && ( "$LIVE_CREATE_THREAD" == "1" || "$LIVE_CREATE_TURN" == "1" || "$LIVE_EXERCISE_LIFECYCLE" == "1" ) ]]; then
  LIVE_CWD="$(
    ssh "${ssh_args[@]}" "$remote" 'mktemp -d "$HOME/.mobidex-live-verify.XXXXXX"'
  )"
  REMOTE_LIVE_CWD_CREATED=1
fi

if [[ "$LIVE_EXERCISE_LIFECYCLE" == "1" ]]; then
  [[ -n "$LIVE_CWD" ]] || fail "MOBIDEX_LIVE_EXERCISE_LIFECYCLE=1 requires MOBIDEX_LIVE_CWD or a resolvable remote HOME."
  [[ -f "$LIVE_IMAGE_LOCAL_PATH" ]] || fail "image fixture not found at $LIVE_IMAGE_LOCAL_PATH. Set MOBIDEX_LIVE_IMAGE_LOCAL_PATH to an existing local image."

  quoted_live_cwd="$(quote_remote_executable "$LIVE_CWD")"
  ssh "${ssh_args[@]}" "$remote" "LIVE_CWD=$quoted_live_cwd python3 - <<'PY'
import os
import subprocess
from pathlib import Path

cwd = Path(os.environ['LIVE_CWD'])
cwd.mkdir(parents=True, exist_ok=True)
(cwd / 'README.md').write_text('Mobidex disposable live verification repo.\n', encoding='utf-8')
(cwd / 'mobidex-live-action.txt').write_text('pending\n', encoding='utf-8')
subprocess.run(['git', '-C', str(cwd), 'init', '-q'], check=True)
subprocess.run(['git', '-C', str(cwd), 'add', 'README.md', 'mobidex-live-action.txt'], check=True)
subprocess.run([
    'git',
    '-C',
    str(cwd),
    '-c',
    'user.name=Mobidex Live Verify',
    '-c',
    'user.email=mobidex@example.invalid',
    'commit',
    '-q',
    '-m',
    'seed live verification repo',
], check=True)
origin = cwd / '.git' / 'mobidex-origin.git'
subprocess.run(['git', 'init', '--bare', '-q', str(origin)], check=True)
subprocess.run(['git', '-C', str(cwd), 'remote', 'add', 'origin', str(origin)], check=True)
branch = subprocess.check_output(['git', '-C', str(cwd), 'branch', '--show-current'], text=True).strip() or 'master'
subprocess.run(['git', '-C', str(cwd), 'push', '-q', '-u', 'origin', branch], check=True)
PY"

  LIVE_IMAGE_REMOTE_PATH="$LIVE_CWD/mobidex-live-image.png"
  quoted_image_path="$(quote_remote_executable "$LIVE_IMAGE_REMOTE_PATH")"
  ssh "${ssh_args[@]}" "$remote" "cat > $quoted_image_path" <"$LIVE_IMAGE_LOCAL_PATH"
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

echo "Checking Codex app-server stdio thread list and optional lifecycle probes..."
python3 - "$HOST" "$USER" "$PORT" "$IDENTITY_FILE" "$CODEX_PATH" "$CODEX_HOME_VALUE" "$discovery_json" "$LIVE_CREATE_THREAD" "$LIVE_CREATE_TURN" "$LIVE_TURN_PROMPT" "$LIVE_TURN_TIMEOUT" "$LIVE_CWD" "$LIVE_EXERCISE_LIFECYCLE" "$LIVE_IMAGE_REMOTE_PATH" <<'PY'
import json
import os
import selectors
import shlex
import subprocess
import sys
import time

host, user, port, identity_file, codex_path, codex_home, discovery_json, live_create_thread, live_create_turn, live_turn_prompt, live_turn_timeout, live_cwd, live_exercise_lifecycle, live_image_remote_path = sys.argv[1:15]
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

def remote_path_bootstrap():
    return 'export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; '

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
    f"{quote_remote_env_assignment('CODEX_HOME', codex_home)}{remote_path_bootstrap()}{quote_remote_executable(codex_path)} app-server --listen stdio://",
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
server_requests = []
created_thread_id = None
created_thread_ids = []
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
            server_requests.append(response)
            continue
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
            server_requests.append(message)
            continue
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

def wait_server_request(timeout=60, required=True):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if server_requests:
            return server_requests.pop(0)
        message = read_message(max(0.1, deadline - time.monotonic()))
        if message is None:
            continue
        if message.get("method") and message.get("id") is not None:
            return message
        if message.get("method"):
            notifications.append(message)
    if required:
        raise SystemExit("timed out waiting for app-server approval request")
    return None

def approve_server_request(message):
    assert process.stdin is not None
    method = message.get("method")
    if method in ("item/commandExecution/requestApproval", "item/fileChange/requestApproval"):
        result = {"decision": "accept"}
    elif method in ("execCommandApproval", "applyPatchApproval"):
        result = {"decision": "approved"}
    else:
        raise SystemExit(f"cannot approve unexpected app-server request {method!r}")
    process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}) + "\n")
    process.stdin.flush()

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
            server_requests.append(message)
            continue
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

def start_thread(cwd, service_name, sandbox="read-only", approval_policy="never", ephemeral=False):
    result = request(
        "thread/start",
        {
            "cwd": cwd,
            "serviceName": service_name,
            "ephemeral": ephemeral,
            "sandbox": sandbox,
            "approvalPolicy": approval_policy,
        },
        timeout=45,
    )
    thread = result.get("thread")
    if not isinstance(thread, dict):
        raise SystemExit(f"thread/start returned invalid thread for {service_name}: {result!r}")
    thread_id = thread.get("id")
    if not isinstance(thread_id, str) or not thread_id:
        raise SystemExit(f"thread/start returned invalid thread id for {service_name}: {thread!r}")
    if not ephemeral:
        created_thread_ids.append(thread_id)
    return thread

def start_turn(thread_id, input_items, timeout=45):
    result = request(
        "turn/start",
        {
            "threadId": thread_id,
            "input": input_items,
            "effort": "low",
        },
        timeout=timeout,
    )
    turn = result.get("turn")
    if not isinstance(turn, dict) or not isinstance(turn.get("id"), str):
        raise SystemExit(f"turn/start returned invalid turn: {result!r}")
    return turn

def text_input(text):
    return {"type": "text", "text": text, "text_elements": []}

def ensure_completed_turn(thread_id, turn, label):
    completed_turn = wait_completed_turn(thread_id, turn, timeout=live_turn_timeout)
    completed_status = completed_turn.get("status")
    if completed_status != "completed":
        error_detail = completed_turn.get("error")
        raise SystemExit(
            f"{label} reported non-completed status "
            f"{completed_status!r} for {thread_id}: {json.dumps(error_detail, sort_keys=True)}"
        )
    return completed_turn

def archive_thread(thread_id):
    try:
        request("thread/archive", {"threadId": thread_id}, timeout=15)
    except SystemExit as error:
        print(f"Warning: could not archive temporary thread {thread_id}: {error}", flush=True)
        return False
    if thread_id in created_thread_ids:
        created_thread_ids.remove(thread_id)
    return True

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
    for project in sorted(projects, key=lambda item: item.get("discoveredSessionCount") or 0, reverse=True):
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
                "effort": "low",
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

    if live_exercise_lifecycle == "1":
        if not live_cwd:
            raise SystemExit("MOBIDEX_LIVE_EXERCISE_LIFECYCLE=1 requires MOBIDEX_LIVE_CWD or a resolvable remote HOME")

        summary_thread = start_thread(live_cwd, "mobidex-live-summary", sandbox="read-only")
        summary_thread_id = summary_thread["id"]
        summary_turn = start_turn(
            summary_thread_id,
            [text_input("Summarize this disposable codebase in one short sentence.")],
        )
        ensure_completed_turn(summary_thread_id, summary_turn, "summary lifecycle turn")
        archive_thread(summary_thread_id)
        print("Lifecycle probe completed a summary turn.")

        if live_image_remote_path:
            image_thread = start_thread(live_cwd, "mobidex-live-image", sandbox="read-only")
            image_thread_id = image_thread["id"]
            image_turn = start_turn(
                image_thread_id,
                [
                    text_input("Describe this image in one short sentence."),
                    {"type": "localImage", "path": live_image_remote_path},
                ],
            )
            ensure_completed_turn(image_thread_id, image_turn, "image lifecycle turn")
            archive_thread(image_thread_id)
            print(f"Lifecycle probe completed an image turn using {live_image_remote_path}.")

        action_thread = start_thread(live_cwd, "mobidex-live-action", sandbox="workspace-write")
        action_thread_id = action_thread["id"]
        action_turn = start_turn(
            action_thread_id,
            [
                text_input(
                    "Modify only mobidex-live-action.txt. Replace its entire contents with exactly "
                    "`mobidex live action completed\\n`. Do not change any other file."
                )
            ],
        )
        ensure_completed_turn(action_thread_id, action_turn, "action lifecycle turn")
        diff_result = request("gitDiffToRemote", {"cwd": live_cwd}, timeout=45)
        diff = diff_result.get("diff")
        if not isinstance(diff, str):
            raise SystemExit(f"gitDiffToRemote returned invalid diff: {diff_result!r}")
        if "mobidex-live-action.txt" not in diff:
            raise SystemExit(f"gitDiffToRemote did not include the action file: {diff!r}")
        archive_thread(action_thread_id)
        print("Lifecycle probe completed an action turn and gitDiffToRemote reported changed files.")

        steer_thread = start_thread(
            live_cwd,
            "mobidex-live-steer",
            sandbox="workspace-write",
            approval_policy="on-request",
        )
        steer_thread_id = steer_thread["id"]
        steer_turn = start_turn(
            steer_thread_id,
            [
                text_input(
                    "Run the shell command `sleep 120`, then report that the steering probe finished."
                )
            ],
        )
        if steer_turn.get("status") != "inProgress":
            raise SystemExit(f"steer lifecycle turn completed before steering could be tested: {steer_turn!r}")
        active_turn_id = steer_turn["id"]
        active_turn_thread_id = steer_thread_id
        approval = wait_server_request(timeout=5, required=False)
        request(
            "turn/steer",
            {
                "threadId": steer_thread_id,
                "expectedTurnId": steer_turn["id"],
                "input": [text_input("Steering check: include the exact phrase mobidex steer acknowledged.")],
            },
            timeout=45,
        )
        if approval is None and server_requests:
            approval = server_requests.pop(0)
        if approval is not None:
            approve_server_request(approval)
        time.sleep(1)
        request(
            "turn/interrupt",
            {"threadId": steer_thread_id, "turnId": steer_turn["id"]},
            timeout=45,
        )
        active_turn_id = None
        active_turn_thread_id = None
        request("thread/read", {"threadId": steer_thread_id, "includeTurns": True}, timeout=45)
        archive_thread(steer_thread_id)
        print("Lifecycle probe accepted turn/steer while a turn was active and interrupted it.")

        interrupt_thread = start_thread(live_cwd, "mobidex-live-interrupt", sandbox="workspace-write")
        interrupt_thread_id = interrupt_thread["id"]
        interrupt_turn = start_turn(
            interrupt_thread_id,
            [text_input("Run the shell command `sleep 120`, then report that it finished.")],
        )
        if interrupt_turn.get("status") != "inProgress":
            raise SystemExit(f"interrupt lifecycle turn completed before interrupt could be tested: {interrupt_turn!r}")
        active_turn_id = interrupt_turn["id"]
        active_turn_thread_id = interrupt_thread_id
        time.sleep(2)
        request(
            "turn/interrupt",
            {"threadId": interrupt_thread_id, "turnId": interrupt_turn["id"]},
            timeout=45,
        )
        active_turn_id = None
        active_turn_thread_id = None
        request("thread/read", {"threadId": interrupt_thread_id, "includeTurns": True}, timeout=45)
        archive_thread(interrupt_thread_id)
        print("Lifecycle probe interrupted an active turn.")

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
    for thread_id in list(reversed(created_thread_ids)):
        try:
            request("thread/archive", {"threadId": thread_id}, timeout=10)
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
