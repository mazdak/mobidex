#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${MOBIDEX_BUNDLE_ID:-com.mazdak.mobidex}"
APP_PATH="${MOBIDEX_APP_PATH:-"$ROOT_DIR/build/Debug-iphonesimulator/Mobidex.app"}"
DEVICE_ID="${MOBIDEX_SIMULATOR_ID:-}"
SCREENSHOT_PATH="${MOBIDEX_SCREENSHOT_PATH:-"/tmp/mobidex-inapp-ssh-smoke.png"}"
RESULT_FILENAME="mobidex-smoke-result.json"
WORK_DIR="$(mktemp -d)"
KEEP_SIMULATOR="${MOBIDEX_KEEP_SIMULATOR:-0}"
KEEP_WORK_DIR="${MOBIDEX_KEEP_WORK_DIR:-0}"
STAY_ALIVE_ON_SUCCESS="${MOBIDEX_STAY_ALIVE_ON_SUCCESS:-0}"
SETUP_ONLY="${MOBIDEX_SMOKE_SETUP_ONLY:-0}"
SETUP_ENV_PATH="${MOBIDEX_SMOKE_ENV_PATH:-}"
AUTH_METHOD="${MOBIDEX_SMOKE_AUTH:-private-key}"
SMOKE_MODE="${MOBIDEX_SMOKE_MODE:-}"
PROMPT="${MOBIDEX_SMOKE_PROMPT:-Reply exactly: mobidex simulator smoke.}"
EXPECTED_TEXT="${MOBIDEX_SMOKE_EXPECTED_TEXT:-mobidex simulator smoke}"
STEER_TEXT="${MOBIDEX_SMOKE_STEER_TEXT:-Steer control smoke}"
TIMEOUT="${MOBIDEX_SMOKE_TIMEOUT:-180}"
APP_STDOUT="$WORK_DIR/app.out"
APP_STDERR="$WORK_DIR/app.err"
PASSWORD="${MOBIDEX_SMOKE_PASSWORD:-mobidex-password}"

case "$TIMEOUT" in
  "" | *[!0-9]*)
    echo "MOBIDEX_SMOKE_TIMEOUT must be a positive integer number of seconds." >&2
    exit 1
    ;;
esac
if (( TIMEOUT < 1 )); then
  echo "MOBIDEX_SMOKE_TIMEOUT must be at least 1 second." >&2
  exit 1
fi
RESULT_TIMEOUT=$((TIMEOUT + 60))

case "$SETUP_ONLY" in
  0 | 1)
    ;;
  *)
    echo "MOBIDEX_SMOKE_SETUP_ONLY must be 0 or 1." >&2
    exit 1
    ;;
esac

if [[ "$SETUP_ONLY" == "1" && -z "$SETUP_ENV_PATH" ]]; then
  echo "MOBIDEX_SMOKE_ENV_PATH is required when MOBIDEX_SMOKE_SETUP_ONLY=1." >&2
  exit 1
fi

case "$AUTH_METHOD" in
  password | private-key)
    ;;
  privateKey)
    AUTH_METHOD="private-key"
    ;;
  *)
    echo "Unsupported MOBIDEX_SMOKE_AUTH: $AUTH_METHOD. Use private-key or password." >&2
    exit 1
    ;;
esac

if [[ -z "$SMOKE_MODE" ]]; then
  if [[ "$AUTH_METHOD" == "password" ]]; then
    SMOKE_MODE="connection"
  else
    SMOKE_MODE="turn"
  fi
fi

case "$SMOKE_MODE" in
  turn | connection | control | approval | seed)
    ;;
  *)
    echo "Unsupported MOBIDEX_SMOKE_MODE: $SMOKE_MODE. Use turn, connection, control, approval, or seed." >&2
    exit 1
    ;;
esac

if [[ "$SMOKE_MODE" == "control" && -z "${MOBIDEX_SMOKE_EXPECTED_TEXT:-}" ]]; then
  EXPECTED_TEXT="control steer accepted"
fi

if [[ "$AUTH_METHOD" == "password" ]]; then
  SMOKE_USER="${MOBIDEX_SMOKE_USER:-mobidex}"
else
  SMOKE_USER="${MOBIDEX_SMOKE_USER:-$(whoami)}"
fi

cleanup() {
  if [[ -n "${SSHD_PID:-}" ]]; then
    kill "$SSHD_PID" >/dev/null 2>&1 || true
  fi
  if [[ "${BOOTED_BY_SCRIPT:-0}" == "1" && "$KEEP_SIMULATOR" != "1" ]]; then
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_WORK_DIR" == "1" ]]; then
    echo "Keeping work directory: $WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

print_runtime_logs() {
  echo "app stdout:" >&2
  sed -n '1,160p' "$APP_STDOUT" >&2 2>/dev/null || true
  echo "app stderr:" >&2
  sed -n '1,160p' "$APP_STDERR" >&2 2>/dev/null || true
  echo "sshd log:" >&2
  sed -n '1,160p' "$WORK_DIR/sshd.log" >&2
}

SDK=iphonesimulator CONFIGURATION=Debug "$ROOT_DIR/Scripts/verify-ios-build.sh" Mobidex

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(
    xcrun simctl list devices available |
      awk '
        /^-- iOS / { in_ios = 1; next }
        /^-- / { in_ios = 0 }
        in_ios && match($0, /\([0-9A-F-][0-9A-F-]*\)/) {
          device_id = substr($0, RSTART + 1, RLENGTH - 2)
          if (length(device_id) == 36) {
            print device_id
            exit
          }
        }
      '
  )"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No available iOS simulator device found." >&2
  exit 1
fi

INITIAL_STATE="$(
  xcrun simctl list devices |
    awk -v id="$DEVICE_ID" '
      index($0, id) {
        if ($0 ~ /\(Booted\)/) print "Booted"
        else if ($0 ~ /\(Shutdown\)/) print "Shutdown"
        else print "Other"
        exit
      }
    '
)"
BOOTED_BY_SCRIPT=0
if [[ "$INITIAL_STATE" == "Shutdown" ]]; then
  xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
  BOOTED_BY_SCRIPT=1
fi
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null

PORT="$(
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
HOST_KEY="$WORK_DIR/host_ed25519"
CLIENT_KEY="$WORK_DIR/client_ed25519"
AUTHORIZED_KEYS="$WORK_DIR/authorized_keys"
SSHD_CONFIG="$WORK_DIR/sshd_config"
PASSWORD_SERVER="$WORK_DIR/password_ssh_server.py"
FAKE_CODEX_SERVER="$WORK_DIR/fake_codex_app_server.py"
SMOKE_CWD="$WORK_DIR/project"
CODEX_PATH="$WORK_DIR/codex-smoke"

mkdir -p "$SMOKE_CWD"
if [[ "$SMOKE_MODE" == "control" || "$SMOKE_MODE" == "approval" || "$SMOKE_MODE" == "seed" ]]; then
  cat >"$FAKE_CODEX_SERVER" <<'PY'
import json
import sys
import time


CWD = sys.argv[1]
STEER_TEXT = sys.argv[2]
THREAD_ID = "thread-control"
TURN_ID = "turn-control"
APPROVAL_ID = "approval-control"

thread_started = False
turn_started = False
turn_completed = False
user_text = ""
assistant_text = ""
approval_sent = False
approval_resolved = False
steer_seen = False


def send(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def fail(message, request_id=None):
    print(f"FAKE PROTOCOL ERROR: {message}", file=sys.stderr, flush=True)
    if request_id is not None:
        send({"id": request_id, "error": {"code": -32000, "message": message}})
    sys.exit(70)


def require(condition, message, request_id=None):
    if not condition:
        fail(message, request_id)


def now():
    return int(time.time())


def status():
    return {"type": "idle"} if turn_completed or not turn_started else {"type": "active", "activeFlags": []}


def turn():
    items = []
    if user_text:
        items.append({
            "type": "userMessage",
            "id": "item-user",
            "content": [{"type": "text", "text": user_text}],
        })
    if assistant_text:
        items.append({"type": "agentMessage", "id": "item-agent", "text": assistant_text})
    return {
        "id": TURN_ID,
        "status": "completed" if turn_completed else "inProgress",
        "items": items,
    }


def thread(include_turns=True):
    data = {
        "id": THREAD_ID,
        "preview": user_text or "Control smoke",
        "cwd": CWD,
        "status": status(),
        "updatedAt": now(),
        "createdAt": now() - 1,
    }
    if include_turns:
        data["turns"] = [turn()] if turn_started else []
    return data


def input_text(params):
    values = params.get("input") or []
    if values and isinstance(values[0], dict):
        return values[0].get("text") or ""
    return ""


def handle_request(message):
    global thread_started, turn_started, turn_completed, user_text
    global assistant_text, approval_sent, approval_resolved, steer_seen

    request_id = message.get("id")
    method = message.get("method")
    params = message.get("params") or {}

    if method == "initialize":
        send({
            "id": request_id,
            "result": {
                "userAgent": "mobidex-control-smoke",
                "codexHome": CWD,
                "platformFamily": "unix",
                "platformOs": "macos",
            },
        })
    elif method == "thread/list":
        cwd = params.get("cwd")
        require(cwd in (None, CWD), f"unexpected thread/list cwd: {cwd!r}", request_id)
        send({"id": request_id, "result": {"data": [thread(False)] if thread_started else [], "nextCursor": None}})
    elif method == "thread/start":
        require(params.get("cwd") == CWD, f"unexpected thread/start cwd: {params.get('cwd')!r}", request_id)
        thread_started = True
        send({"id": request_id, "result": {"thread": thread(True)}})
    elif method == "thread/read":
        require(params.get("threadId") == THREAD_ID, f"unexpected thread/read threadId: {params.get('threadId')!r}", request_id)
        send({"id": request_id, "result": {"thread": thread(True)}})
    elif method == "turn/start":
        require(params.get("threadId") == THREAD_ID, f"unexpected turn/start threadId: {params.get('threadId')!r}", request_id)
        thread_started = True
        turn_started = True
        turn_completed = False
        user_text = input_text(params)
        send({"id": request_id, "result": {"turn": turn()}})
        if not approval_sent:
            approval_sent = True
            send({
                "jsonrpc": "2.0",
                "id": APPROVAL_ID,
                "method": "item/commandExecution/requestApproval",
                "params": {
                    "threadId": THREAD_ID,
                    "turnId": TURN_ID,
                    "itemId": "item-command",
                    "command": "printf control",
                    "cwd": CWD,
                },
            })
    elif method == "turn/steer":
        require(params.get("threadId") == THREAD_ID, f"unexpected turn/steer threadId: {params.get('threadId')!r}", request_id)
        require(params.get("expectedTurnId") == TURN_ID, f"unexpected turn/steer expectedTurnId: {params.get('expectedTurnId')!r}", request_id)
        require(input_text(params) == STEER_TEXT, f"unexpected turn/steer input: {input_text(params)!r}", request_id)
        require(approval_resolved, "turn/steer arrived before approval response was observed", request_id)
        steer_seen = True
        assistant_text += "control steer accepted"
        send({"id": request_id, "result": {}})
        send({
            "method": "item/agentMessage/delta",
            "params": {
                "threadId": THREAD_ID,
                "turnId": TURN_ID,
                "itemId": "item-agent",
                "delta": "control steer accepted",
            },
        })
    elif method == "turn/interrupt":
        require(params.get("threadId") == THREAD_ID, f"unexpected turn/interrupt threadId: {params.get('threadId')!r}", request_id)
        require(params.get("turnId") == TURN_ID, f"unexpected turn/interrupt turnId: {params.get('turnId')!r}", request_id)
        require(approval_resolved, "turn/interrupt arrived before approval response was observed", request_id)
        turn_completed = True
        send({"id": request_id, "result": {}})
        send({"method": "turn/completed", "params": {"threadId": THREAD_ID, "turn": turn()}})
    else:
        send({"id": request_id, "result": {}})


for raw_line in sys.stdin:
    line = raw_line.strip()
    if not line:
        continue
    message = json.loads(line)
    if "method" in message:
        if "id" in message:
            handle_request(message)
        elif message.get("method") == "initialized":
            send({"method": "remoteControl/status/changed", "params": {"status": "disabled", "environmentId": None}})
    elif message.get("id") == APPROVAL_ID and "result" in message:
        result = message.get("result") or {}
        require(result.get("decision") == "accept", f"unexpected approval decision: {result!r}")
        approval_resolved = True
        send({"method": "serverRequest/resolved", "params": {"threadId": THREAD_ID, "requestId": APPROVAL_ID}})
PY
  quoted_fake_codex_server="$(printf "%q" "$FAKE_CODEX_SERVER")"
  quoted_smoke_cwd="$(printf "%q" "$SMOKE_CWD")"
  quoted_steer_text="$(printf "%q" "$STEER_TEXT")"
  cat >"$CODEX_PATH" <<EOF
#!/bin/bash
if [[ "\$1" == "app-server" && "\$2" == "--listen" && "\$3" == "stdio://" ]]; then
  exec python3 $quoted_fake_codex_server $quoted_smoke_cwd $quoted_steer_text
fi
echo "unsupported fake codex invocation: \$*" >&2
exit 64
EOF
  chmod 700 "$CODEX_PATH"
elif [[ "$SMOKE_MODE" == "turn" ]]; then
  SOURCE_CODEX_PATH="${MOBIDEX_SMOKE_CODEX_PATH:-$(command -v codex || true)}"
  if [[ -z "$SOURCE_CODEX_PATH" ]]; then
    echo "Could not find codex on PATH. Set MOBIDEX_SMOKE_CODEX_PATH, or use MOBIDEX_SMOKE_MODE=connection for connection-only smoke." >&2
    exit 1
  fi
  case "$SOURCE_CODEX_PATH" in
    "~")
      SOURCE_CODEX_PATH="$HOME"
      ;;
    "~/"*)
      SOURCE_CODEX_PATH="$HOME/${SOURCE_CODEX_PATH#\~/}"
      ;;
  esac
  quoted_source_codex_path="$(printf "%q" "$SOURCE_CODEX_PATH")"
  quoted_launch_path="$(printf "%q" "$PATH")"
  cat >"$CODEX_PATH" <<EOF
#!/bin/bash
export PATH=$quoted_launch_path:\$PATH
exec $quoted_source_codex_path "\$@"
EOF
  chmod 700 "$CODEX_PATH"
else
  CODEX_PATH="${MOBIDEX_SMOKE_CODEX_PATH:-codex}"
fi

if [[ "$AUTH_METHOD" == "password" ]]; then
  cat >"$PASSWORD_SERVER" <<'PY'
import asyncio
import os
import signal
import sys

import asyncssh


USERNAME = os.environ["MOBIDEX_PASSWORD_SMOKE_USER"]
PASSWORD = os.environ["MOBIDEX_PASSWORD_SMOKE_PASSWORD"]
PORT = int(os.environ["MOBIDEX_PASSWORD_SMOKE_PORT"])


class PasswordServer(asyncssh.SSHServer):
    def connection_made(self, conn):
        print("CONNECTION MADE", file=sys.stderr, flush=True)

    def connection_lost(self, exc):
        print(f"CONNECTION LOST {exc!r}", file=sys.stderr, flush=True)

    def begin_auth(self, username):
        print(f"BEGIN AUTH {username!r}", file=sys.stderr, flush=True)
        return True

    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        valid = username == USERNAME and password == PASSWORD
        print(f"VALIDATE PASSWORD {username!r} {valid!r}", file=sys.stderr, flush=True)
        return valid


async def handle_process(process):
    command = process.command
    if command:
        print(f"COMMAND {command!r}", file=sys.stderr, flush=True)
        child = await asyncio.create_subprocess_shell(
            command,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    else:
        shell = os.environ.get("SHELL") or "/bin/bash"
        print(f"SHELL {shell!r}", file=sys.stderr, flush=True)
        child = await asyncio.create_subprocess_exec(
            shell,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

    async def pump_stdin():
        try:
            while True:
                data = await process.stdin.read(8192)
                if not data:
                    print("STDIN EOF", file=sys.stderr, flush=True)
                    break
                print(f"STDIN {len(data)} bytes", file=sys.stderr, flush=True)
                child.stdin.write(data if isinstance(data, bytes) else data.encode())
                await child.stdin.drain()
        except asyncio.CancelledError:
            print("STDIN CANCELLED", file=sys.stderr, flush=True)
        except (BrokenPipeError, ConnectionError) as exc:
            print(f"STDIN CLOSED {exc!r}", file=sys.stderr, flush=True)
        except Exception as exc:
            print(f"STDIN ERROR {exc!r}", file=sys.stderr, flush=True)
        finally:
            if child.stdin and not child.stdin.is_closing():
                child.stdin.close()

    async def pump_output(source, target, mirror_to_log=False):
        try:
            while True:
                data = await source.read(8192)
                if not data:
                    break
                if mirror_to_log:
                    sys.stderr.buffer.write(data if isinstance(data, bytes) else data.encode())
                    sys.stderr.buffer.flush()
                target.write(data)
                await target.drain()
        except asyncio.CancelledError:
            print("OUTPUT CANCELLED", file=sys.stderr, flush=True)
        except (BrokenPipeError, ConnectionError) as exc:
            print(f"OUTPUT CLOSED {exc!r}", file=sys.stderr, flush=True)
        except Exception as exc:
            print(f"OUTPUT ERROR {exc!r}", file=sys.stderr, flush=True)

    stdin_task = asyncio.create_task(pump_stdin())
    output_tasks = [
        asyncio.create_task(pump_output(child.stdout, process.stdout, mirror_to_log=True)),
        asyncio.create_task(pump_output(child.stderr, process.stderr, mirror_to_log=True)),
    ]
    status = await child.wait()
    print(f"CHILD EXIT {status!r}", file=sys.stderr, flush=True)
    stdin_task.cancel()
    await asyncio.gather(stdin_task, *output_tasks, return_exceptions=True)
    process.exit(status if status is not None else 255)


async def main():
    host_key = asyncssh.generate_private_key("ssh-ed25519")
    server = await asyncssh.create_server(
        PasswordServer,
        "127.0.0.1",
        PORT,
        server_host_keys=[host_key],
        process_factory=handle_process,
        encoding=None,
    )

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    await stop.wait()
    server.close()
    await server.wait_closed()


asyncio.run(main())
PY

  MOBIDEX_PASSWORD_SMOKE_USER="$SMOKE_USER" \
  MOBIDEX_PASSWORD_SMOKE_PASSWORD="$PASSWORD" \
  MOBIDEX_PASSWORD_SMOKE_PORT="$PORT" \
  uv run --with asyncssh --with cryptography python "$PASSWORD_SERVER" >"$WORK_DIR/sshd.log" 2>&1 &
  SSHD_PID=$!
else
  ssh-keygen -q -t ed25519 -N "" -f "$HOST_KEY"
  ssh-keygen -q -t ed25519 -N "" -f "$CLIENT_KEY"
  cp "$CLIENT_KEY.pub" "$AUTHORIZED_KEYS"

  cat >"$SSHD_CONFIG" <<EOF
Port $PORT
ListenAddress 127.0.0.1
HostKey $HOST_KEY
PidFile $WORK_DIR/sshd.pid
AuthorizedKeysFile $AUTHORIZED_KEYS
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
StrictModes no
LogLevel VERBOSE
Subsystem sftp internal-sftp
EOF

  /usr/sbin/sshd -D -e -f "$SSHD_CONFIG" >"$WORK_DIR/sshd.log" 2>&1 &
  SSHD_PID=$!
fi

for _ in {1..50}; do
  if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if [[ "$AUTH_METHOD" == "password" ]]; then
  MOBIDEX_PASSWORD_SMOKE_USER="$SMOKE_USER" \
  MOBIDEX_PASSWORD_SMOKE_PASSWORD="$PASSWORD" \
  MOBIDEX_PASSWORD_SMOKE_PORT="$PORT" \
  uv run --with asyncssh python - <<'PY'
import asyncio
import os

import asyncssh


async def main():
    async with asyncssh.connect(
        "127.0.0.1",
        port=int(os.environ["MOBIDEX_PASSWORD_SMOKE_PORT"]),
        username=os.environ["MOBIDEX_PASSWORD_SMOKE_USER"],
        password=os.environ["MOBIDEX_PASSWORD_SMOKE_PASSWORD"],
        known_hosts=None,
    ) as connection:
        result = await connection.run("printf ok", check=True)
        output = result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout
        if output != "ok":
            raise SystemExit(f"unexpected password preflight output: {output!r}")


asyncio.run(main())
PY
else
  ssh -p "$PORT" \
    -i "$CLIENT_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    "$SMOKE_USER@127.0.0.1" 'printf ok' >/dev/null

  CLIENT_KEY_B64="$(base64 <"$CLIENT_KEY" | tr -d '\n')"
fi

xcrun simctl install "$DEVICE_ID" "$APP_PATH"
DATA_CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"
RESULT_PATH="$DATA_CONTAINER/Documents/$RESULT_FILENAME"
rm -f "$RESULT_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

launch_env=(
  "SIMCTL_CHILD_MOBIDEX_SMOKE=1"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_AUTH=$AUTH_METHOD"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_MODE=$SMOKE_MODE"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_HOST=127.0.0.1"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_PORT=$PORT"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_USER=$SMOKE_USER"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_CODEX_PATH=$CODEX_PATH"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_CWD=$SMOKE_CWD"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_PROMPT=$PROMPT"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_STEER_TEXT=$STEER_TEXT"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_EXPECTED_TEXT=$EXPECTED_TEXT"
  "SIMCTL_CHILD_MOBIDEX_SMOKE_TIMEOUT=$TIMEOUT"
)
if [[ "$SMOKE_MODE" == "approval" || "$SMOKE_MODE" == "control" ]]; then
  launch_env+=("SIMCTL_CHILD_MOBIDEX_SMOKE_PROMOTE_DETAIL=1")
fi
if [[ "$AUTH_METHOD" == "password" ]]; then
  launch_env+=("SIMCTL_CHILD_MOBIDEX_SMOKE_PASSWORD=$PASSWORD")
else
  launch_env+=("SIMCTL_CHILD_MOBIDEX_SMOKE_PRIVATE_KEY_BASE64=$CLIENT_KEY_B64")
fi

write_setup_environment() {
  local output_path="$1"
  local entry
  local key
  local value
  mkdir -p "$(dirname "$output_path")"
  : >"$output_path"
  for entry in "${launch_env[@]}"; do
    key="${entry%%=*}"
    value="${entry#*=}"
    key="${key#SIMCTL_CHILD_}"
    printf 'export %s=%q\n' "$key" "$value" >>"$output_path"
  done
  printf 'export MOBIDEX_SIMULATOR_ID=%q\n' "$DEVICE_ID" >>"$output_path"
  printf 'export MOBIDEX_APP_PATH=%q\n' "$APP_PATH" >>"$output_path"
}

if [[ "$SETUP_ONLY" == "1" ]]; then
  write_setup_environment "$SETUP_ENV_PATH"
  echo "In-app SSH smoke setup is ready."
  echo "Device: $DEVICE_ID"
  echo "Port: $PORT"
  echo "Environment: $SETUP_ENV_PATH"
  while true; do
    sleep 3600
  done
fi

env "${launch_env[@]}" \
xcrun simctl launch \
  --terminate-running-process \
  --stdout="$APP_STDOUT" \
  --stderr="$APP_STDERR" \
  "$DEVICE_ID" \
  "$BUNDLE_ID" >/dev/null

deadline=$((SECONDS + RESULT_TIMEOUT))
while (( SECONDS < deadline )); do
  if [[ -f "$RESULT_PATH" ]]; then
    status="$(python3 - "$RESULT_PATH" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle).get("status", ""))
PY
)"
    if [[ "$status" == "success" ]]; then
      if [[ "$SMOKE_MODE" == "approval" ]]; then
        python3 - "$RESULT_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    result = json.load(handle)

checks = {
    "pendingApprovalCount": result.get("pendingApprovalCount", 0) >= 1,
    "selectedThreadLoaded": result.get("selectedThreadLoaded") is True,
    "canInterruptActiveTurn": result.get("canInterruptActiveTurn") is True,
    "conversationSectionCount": result.get("conversationSectionCount", 0) >= 1,
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit(f"approval UI smoke missing expected state: {failed}; result={result!r}")
PY
        sleep "${MOBIDEX_SCREENSHOT_SETTLE_SECONDS:-1}"
      elif [[ "$SMOKE_MODE" == "control" ]]; then
        python3 - "$RESULT_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    result = json.load(handle)

checks = {
    "approvalHandled": result.get("approvalHandled") is True,
    "interruptHandled": result.get("interruptHandled") is True,
    "expectedTextFound": result.get("expectedTextFound") is True,
    "assistantSectionCount": result.get("assistantSectionCount", 0) >= 1,
    "conversationSectionCount": result.get("conversationSectionCount", 0) >= 2,
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit(f"control UI smoke missing expected state: {failed}; result={result!r}")
PY
        sleep "${MOBIDEX_SCREENSHOT_SETTLE_SECONDS:-1}"
      fi
      mkdir -p "$(dirname "$SCREENSHOT_PATH")"
      xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null
      echo "In-app SSH smoke succeeded."
      echo "Device: $DEVICE_ID"
      echo "Port: $PORT"
      echo "Result: $RESULT_PATH"
      echo "Screenshot: $SCREENSHOT_PATH"
      cat "$RESULT_PATH"
      if [[ "$STAY_ALIVE_ON_SUCCESS" == "1" ]]; then
        echo "Keeping SSH server alive. Stop this script to clean up."
        while true; do
          sleep 3600
        done
      fi
      exit 0
    fi
    if [[ "$status" == "failure" ]]; then
      cat "$RESULT_PATH" >&2
      print_runtime_logs
      exit 1
    fi
  fi
  sleep 1
done

echo "Timed out waiting for in-app SSH smoke result at $RESULT_PATH." >&2
if [[ -f "$RESULT_PATH" ]]; then
  cat "$RESULT_PATH" >&2
fi
print_runtime_logs
exit 1
