# Mobidex

Mobidex is an iOS-only SwiftUI app for viewing and steering Codex sessions that are running on remote servers over SSH.

## Stack Decision

This is a native SwiftUI app, not Expo React Native. The hard part is native SSH, process transport, credential storage, and app-server streaming; Expo would still need a custom native module and a prebuilt dev client for that path.

## Current Feature Set

- Manage SSH servers manually.
- Store passwords and private keys in Keychain, not in `UserDefaults`.
- Connect with password or RSA/Ed25519 OpenSSH private key authentication.
- Configure the remote Codex executable path per server; it defaults to `codex`.
- Discover projects and session counts from remote Codex data under `CODEX_HOME` or `~/.codex`.
- Add a project manually by remote folder path.
- Start the configured Codex executable with `app-server --listen stdio://` over SSH.
- List and read Codex threads through app-server JSON-RPC.
- Include all app-server thread source kinds when listing sessions so CLI, VS Code, exec, app-server, and subagent sessions can appear.
- Render user/assistant messages, reasoning, plans, commands, file changes, tools, agent events, web searches, media placeholders, reviews, compaction, and unknown item types.
- Stream live assistant, reasoning, plan, turn-plan, command-output, terminal-input, file-change, turn-diff, MCP-progress, and turn events into the conversation view.
- Start, steer, and interrupt turns.
- Start a first thread from a selected project even when the project has no listed sessions yet; project/session taps promote the conversation detail on compact layouts and reset to automatic column visibility on regular-width screens.
- Respond to supported approval requests, including current command/file-change approvals and legacy `execCommandApproval` / `applyPatchApproval` requests.

## Remote Host Requirements

- SSH reachable from the iOS device or simulator.
- `codex` available on the remote `PATH`, or a server-specific Codex path such as `/home/ubuntu/.bun/bin/codex` or `~/.bun/bin/codex`.
- If that Codex path is a Node/Bun wrapper and the SSH server's non-login PATH cannot find the runtime, point Mobidex at a small remote wrapper script that exports the needed PATH before execing `codex`.
- `python3` available for project discovery.
- Codex data in `CODEX_HOME` or `~/.codex`.

Project discovery infers projects and session counts from:

- `config.toml` project entries.
- `sessions/**/rollout-*.jsonl`.
- `archived_sessions/**/rollout-*.jsonl`.

Manual project paths are still supported when discovery cannot infer a project.
Session listing and hydration come from `thread/list` and `thread/read` after the app-server connection is established.

## Local Storage Note

Server metadata is stored under `mobidex.servers.v3`. This intentionally ignores older `mobidex.servers.v1` and `mobidex.servers.v2` metadata written before the current project/session-count and Codex-path shape; re-add servers on installs that still have older local metadata.

## Build Setup

Generate the Xcode project:

```sh
xcodegen generate
```

The normal Xcode scheme is the intended build/test path. After the Mobidex rename and project regeneration, `Scripts/verify-official-scheme.sh` succeeds on this machine and writes `/tmp/mobidex-official-scheme.log`.

The helper-built `MobidexTests` target produces a hosted simulator `.xctest` bundle under `Mobidex.app/PlugIns`. `Scripts/verify-simulator-tests.sh` runs that hosted bundle with `xcodebuild test-without-building` and a generated `.xctestrun` file, which gives a deterministic simulator XCTest execution gate.

The helper-built `MobidexUITests` target produces `MobidexUITests-Runner.app`. `Scripts/verify-tap-ui-smoke.sh` starts the deterministic fake SSH/app-server used by seed mode, writes a generated UI `.xctestrun`, and uses XCUITest to tap through Connect, project selection, composer send, approval, steer, and stop-turn controls.

Useful verification helpers:

```sh
Scripts/verify-discovery.sh
Scripts/verify-app-server-schema.sh
Scripts/verify-ios-build.sh Mobidex
Scripts/verify-ios-build.sh MobidexTests
Scripts/verify-ios-build.sh MobidexUITests
SDK=iphoneos Scripts/verify-ios-build.sh Mobidex
SDK=iphoneos Scripts/verify-ios-build.sh MobidexTests
Scripts/verify-simulator-tests.sh
Scripts/verify-simulator-launch.sh
Scripts/verify-inapp-ssh-smoke.sh
Scripts/verify-tap-ui-smoke.sh
```

`Scripts/verify-official-scheme.sh` is the canonical recheck for the normal Xcode scheme gate. It records Xcode SDKs, available runtimes, runtime disk images, simulator devices, scheme destinations, whether the matching simulator runtime is present, and whether any simulator runtime images are unusable. It currently succeeds on this machine and writes `/tmp/mobidex-official-scheme.log`.

By default the official-scheme helper runs `build-for-testing` against `generic/platform=iOS Simulator`. If you set `MOBIDEX_SCHEME_ACTION=test`, also set a concrete `MOBIDEX_DESTINATION` such as `platform=iOS Simulator,id=<simulator-udid>`.

`verify-discovery.sh` extracts the same discovery Python that the app sends over SSH, wraps it with the app's heredoc command shape, simulates Citadel's appended `;exit`, checks zsh-safe exit-status propagation, and runs it against a synthetic `.codex` tree.

`verify-app-server-schema.sh` checks the Mobidex protocol surface against the generated app-server schema in `~/Code/codex`; set `CODEX_SOURCE_DIR` if the Codex checkout lives elsewhere. ChatGPT auth-token refresh requests are detected but not answered by this MVP.

The helper reproduces the local SwiftPM include/module-map/resource-bundle workarounds needed for Citadel, Swift Crypto, SwiftNIO, and Wellz26 swift-nio-ssh under Xcode 26.4.1. It uses a deterministic Swift package clone root at `${TMPDIR:-/tmp}/mobidex-source-packages` so package checkouts and build products stay aligned. It defaults to `SDK=iphonesimulator`; pass `SDK=iphoneos` for a device-SDK compile check. Simulator logs are written to `/tmp/mobidex-<target>-verify.log`; device-SDK logs are written to `/tmp/mobidex-<target>-iphoneos-verify.log`.

Run the `verify-ios-build.sh` invocations one at a time because they share generated module-map and build output directories.

`verify-simulator-tests.sh` builds `MobidexTests`, verifies the hosted `.xctest` bundle has a processed `Info.plist`, writes `build/MobidexGenerated.xctestrun` with the app-hosted XCTest injector environment, selects an available iOS simulator unless `MOBIDEX_SIMULATOR_ID` or `MOBIDEX_DESTINATION` is provided, and runs `xcodebuild test-without-building`. Custom `MOBIDEX_APP_PATH` and `MOBIDEX_TEST_BUNDLE_PATH` values are written into the generated `.xctestrun` as absolute paths. The default log is `/tmp/mobidex-simulator-tests.log`; set `MOBIDEX_TEST_TIMEOUT_SECONDS` to change the hard timeout.

`verify-tap-ui-smoke.sh` builds `MobidexUITests`, starts `verify-inapp-ssh-smoke.sh` in setup-only seed mode, writes a temporary generated UI `.xctestrun`, and runs `xcodebuild test-without-building` against a concrete simulator destination. The UI test launches the app with smoke environment values, then taps the visible controls for Connect, project row, composer, Send, Approve, Send, and Stop Turn. The default log is `/tmp/mobidex-tap-ui-smoke.log`; set `MOBIDEX_UI_SMOKE_TIMEOUT` or `MOBIDEX_UI_TEST_TIMEOUT_SECONDS` to tune timeouts. Set `MOBIDEX_UI_XCTESTRUN_PATH` only when you intentionally want to keep the generated run file for debugging, because it contains smoke environment values.

`verify-simulator-launch.sh` uses the helper to force a Debug `iphonesimulator` app build, selects an available iOS simulator unless `MOBIDEX_SIMULATOR_ID` is provided, installs and launches `com.mazdak.mobidex`, verifies the launched process is still running after a short settle delay, and writes a screenshot to `/tmp/mobidex-simulator-launch.png` unless `MOBIDEX_SCREENSHOT_PATH` is set. `MOBIDEX_SKIP_BUILD=1` and `MOBIDEX_APP_PATH` are local debugging escape hatches; the default path is the build-install-launch smoke.

`verify-inapp-ssh-smoke.sh` builds the app, starts a disposable localhost SSH server, installs the app on a simulator, seeds a smoke server through launch environment, and connects through the real Citadel app path. By default, `MOBIDEX_SMOKE_AUTH=private-key` uses local `sshd` with a generated Ed25519 key, starts Codex app-server, sends a short prompt, waits for assistant output, and writes `/tmp/mobidex-inapp-ssh-smoke.png`. It creates a temporary Codex wrapper with the current PATH baked in so local `~/.bun/bin/codex` wrappers can find Node under macOS `sshd`. This default smoke can spend model/API resources; override `MOBIDEX_SMOKE_PROMPT`, `MOBIDEX_SMOKE_EXPECTED_TEXT`, `MOBIDEX_SMOKE_TIMEOUT`, or `MOBIDEX_SMOKE_CODEX_PATH` when needed. `MOBIDEX_SMOKE_AUTH=password` defaults to connection mode and uses a disposable AsyncSSH password server to validate the in-app password-auth command path without requiring a system account password or PAM. Add `MOBIDEX_SMOKE_MODE=turn` to run the full password-auth app-server turn smoke; this can spend model/API resources.

`MOBIDEX_SMOKE_MODE=control` uses a deterministic fake app-server over the same in-app SSH transport to exercise start, approval response, steer, live assistant delta, and interrupt without spending model/API resources. It also promotes the compact UI to the conversation detail before screenshot capture.

`MOBIDEX_SMOKE_MODE=approval` uses the same fake app-server but stops at the pending approval state, promotes the compact UI to the conversation detail, asserts the thread/approval/active-turn state, and captures a screenshot that should show the active conversation and approval card. This is a non-tap visible UI checkpoint; use `verify-tap-ui-smoke.sh` for interaction validation.

`verify-visible-ui-smokes.sh` runs the non-tap approval and control visible UI smokes back to back and writes screenshots to `/tmp/mobidex-visible-ui-smokes` unless `MOBIDEX_VISIBLE_SCREENSHOT_DIR` is set.

`verify-inapp-ssh-smoke.sh` also supports `MOBIDEX_SMOKE_SETUP_ONLY=1` with `MOBIDEX_SMOKE_ENV_PATH=/path/to/env.sh`; this starts the disposable server, writes app launch environment values, and stays alive until stopped. `verify-tap-ui-smoke.sh` uses that setup path internally.

`MOBIDEX_SMOKE_MODE=seed MOBIDEX_STAY_ALIVE_ON_SUCCESS=1` seeds a fake SSH server into the launched app and keeps the disposable server alive for manual Simulator UI probing. Stop the script to clean it up.

`verify-manual-ui-seed.sh` is a convenience wrapper around seed mode. It defaults to password auth, keeps the Simulator and disposable SSH server alive, captures `/tmp/mobidex-manual-ui-seed.png`, and prints the manual tap checklist. For noninteractive validation of the wrapper without leaving the server running, use:

```sh
MOBIDEX_STAY_ALIVE_ON_SUCCESS=0 MOBIDEX_KEEP_SIMULATOR=0 Scripts/verify-manual-ui-seed.sh
```

To use a custom package clone root, pass:

```sh
MOBIDEX_SOURCE_PACKAGES_DIR=/path/to/source-packages Scripts/verify-ios-build.sh Mobidex
```

## Live Host Validation

When a reachable SSH host is available, this script checks the remote prerequisites, runs the app's heredoc-shaped project discovery command with merged stderr/stdout, verifies the configured Codex executable responds to app-server `initialize`, calls `thread/list` for up to five discovered project paths plus an unfiltered fallback when needed, and calls `thread/read` when the live host returns a thread:

```sh
MOBIDEX_SSH_HOST=host.example.com \
MOBIDEX_SSH_USER=mazdak \
MOBIDEX_SSH_IDENTITY_FILE=~/.ssh/id_ed25519 \
MOBIDEX_CODEX_PATH='~/.bun/bin/codex' \
Scripts/verify-live-host.sh
```

Optional variables:

- `MOBIDEX_SSH_PORT` defaults to `22`.
- `MOBIDEX_CODEX_HOME` overrides remote `CODEX_HOME` for both discovery and app-server.
- `MOBIDEX_CODEX_PATH` defaults to `codex`.
- `MOBIDEX_LIVE_CREATE_THREAD=1` creates a temporary ephemeral read-only no-turn thread, reads its metadata with `thread/read` and `includeTurns=false`, then lets the app-server drop it when the verifier process exits. This does not validate hydrated turns, archival, streaming, or steering.
- `MOBIDEX_LIVE_CREATE_TURN=1` is a stronger opt-in smoke that starts a real temporary turn. It creates a non-ephemeral temporary thread in the live cwd, sends one prompt, accepts either a completed `turn/start` response, `turn/completed`, or a completed turn found by `thread/read`, then archives the temporary thread. This can spend model/API resources and should only be used on a host intended for live validation.
- `MOBIDEX_LIVE_TURN_PROMPT` overrides the prompt for that opt-in turn; it defaults to `Reply exactly: mobidex live verification.`.
- `MOBIDEX_LIVE_TURN_TIMEOUT` overrides the materialized-turn completion wait, in seconds; it defaults to `180`.
- `MOBIDEX_LIVE_CWD` sets the remote cwd for that temporary thread; otherwise the script creates and removes a unique `~/.mobidex-live-verify.*` directory and its generated Codex project-trust stanza.

The script uses non-interactive `ssh` with `BatchMode=yes`, so it is best for SSH config, agent, or identity-file validation. Password authentication can be smoke-tested in app with `MOBIDEX_SMOKE_AUTH=password Scripts/verify-inapp-ssh-smoke.sh`, or through a full app-server turn with `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=turn MOBIDEX_SMOKE_CODEX_PATH='~/.bun/bin/codex' Scripts/verify-inapp-ssh-smoke.sh`.

## Validation Status

Verified locally:

- `xcodegen generate`.
- `Scripts/verify-discovery.sh`.
- `Scripts/verify-app-server-schema.sh`.
- `Scripts/verify-ios-build.sh Mobidex`.
- `Scripts/verify-ios-build.sh MobidexTests`.
- `Scripts/verify-ios-build.sh MobidexUITests`.
- `SDK=iphoneos Scripts/verify-ios-build.sh Mobidex`.
- `SDK=iphoneos Scripts/verify-ios-build.sh MobidexTests`.
- `Scripts/verify-simulator-tests.sh`; this validated app-hosted `MobidexTests` on an iOS simulator with `xcodebuild test-without-building`, executing 29 tests with 0 failures.
- `MOBIDEX_UI_SMOKE_TIMEOUT=120 Scripts/verify-tap-ui-smoke.sh`; this validated tap-level UI control on an iOS simulator through a generated UI `.xctestrun`, executing 1 XCUITest with 0 failures. The log shows synthesized taps for Connect, project row, composer, Send, Approve, Send, and Stop Turn against the deterministic fake SSH/app-server.
- `Scripts/verify-simulator-launch.sh`; this validated installing and launching the helper-built simulator app on an available iOS simulator, process survival after launch, and screenshot capture of the rendered initial `Servers` / `No Servers` UI.
- `Scripts/verify-inapp-ssh-smoke.sh`; this validated in-app private-key authentication through Citadel to a disposable localhost SSH server, app-server startup through the configured Codex path, a `turn/start` from the app path, active-turn hydration, assistant output detection, and screenshot capture. The latest passing run used `MOBIDEX_SMOKE_CODEX_PATH='~/.bun/bin/codex'` and reported `assistantSectionCount: 1`, `conversationSectionCount: 2`, and `expectedTextFound: true`.
- `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=connection MOBIDEX_SMOKE_TIMEOUT=120 Scripts/verify-inapp-ssh-smoke.sh`; this validated in-app password authentication through Citadel against a disposable AsyncSSH password server and a remote command executed from the app path.
- `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=turn MOBIDEX_SMOKE_TIMEOUT=120 MOBIDEX_SMOKE_CODEX_PATH='~/.bun/bin/codex' Scripts/verify-inapp-ssh-smoke.sh`; this validated in-app password authentication through Citadel, app-server startup, `.codex` discovery through a shell session, `turn/start`, active-turn hydration, assistant output detection, and screenshot capture against a disposable AsyncSSH password server.
- `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=control MOBIDEX_SMOKE_TIMEOUT=120 MOBIDEX_SCREENSHOT_PATH=/tmp/mobidex-control-ui-smoke.png Scripts/verify-inapp-ssh-smoke.sh`; this validated the launched app's control path over SSH against a deterministic fake app-server, including `thread/start`, `turn/start`, approval response, `turn/steer`, live assistant delta rendering, `turn/interrupt`, and a compact conversation-detail screenshot with the steered assistant response.
- `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=approval MOBIDEX_SMOKE_TIMEOUT=120 MOBIDEX_SCREENSHOT_PATH=/tmp/mobidex-approval-ui-smoke.png Scripts/verify-inapp-ssh-smoke.sh`; this validated the launched app reaches a visible compact conversation detail with an active turn, stop button, command approval card, and user message.
- `MOBIDEX_VISIBLE_SCREENSHOT_DIR=/tmp/mobidex-visible-ui-smokes Scripts/verify-visible-ui-smokes.sh`; this reruns both visible UI smokes and writes `approval.png` and `control.png`.
- `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=seed MOBIDEX_STAY_ALIVE_ON_SUCCESS=1 Scripts/verify-inapp-ssh-smoke.sh`; this seeds the launched app with a fake SSH server for manual Simulator UI probing and keeps the disposable server alive until the script is stopped.
- `MOBIDEX_STAY_ALIVE_ON_SUCCESS=0 MOBIDEX_KEEP_SIMULATOR=0 Scripts/verify-manual-ui-seed.sh`; this validates the manual UI seed wrapper without leaving the disposable server running. Running `Scripts/verify-manual-ui-seed.sh` without those overrides is the interactive handoff path and waits for the user to stop it.
- `Scripts/verify-live-host.sh` syntax and missing-configuration failure path.
- `Scripts/verify-live-host.sh` against a reachable key/agent SSH devbox with `MOBIDEX_CODEX_PATH='~/.bun/bin/codex'`; this validated SSH command execution, remote `python3`, the configured Codex executable, heredoc-shaped `.codex` discovery filtered to existing remote directories, app-server stdio `initialize`, and live `thread/list`.
- `MOBIDEX_LIVE_CREATE_THREAD=1 Scripts/verify-live-host.sh` against the same devbox; this validated ephemeral no-turn `thread/start` and metadata `thread/read` with `includeTurns=false`.
- `MOBIDEX_LIVE_CREATE_TURN=1 Scripts/verify-live-host.sh` against the same devbox; this validated a temporary materialized turn, `thread/read includeTurns=true`, archive cleanup, and fallback completion detection when the server records a completed turn without emitting `turn/completed` to this stdio verifier.
- A localhost `sshd` live-verifier smoke with a generated identity file; this validated `IdentitiesOnly=yes`, zsh-safe discovery exit handling, a temporary Codex wrapper for non-login PATH, app-server initialize, `thread/list`, `thread/read`, and ephemeral no-turn `thread/start`.
- Focused tests compile into `MobidexTests` and execute through `Scripts/verify-simulator-tests.sh`.
- App-view-model tests cover discovered `.codex` session counts, stale discovered-count clearing, completed `turn/start` responses without completion notifications, live plan deltas, turn-plan updates, file-change patch updates, legacy file-change output deltas, turn-diff updates, terminal interaction output, MCP progress, current/legacy command approval responses, legacy patch approval responses, and server-request resolution cleanup.
- App-view-model tests cover the no-selected-thread composer path that creates a thread before starting a turn, including a `thread/started` notification arriving before the `thread/start` response.
- `REVIEW_NOTES.md` records the subagent review checkpoints for async state handling, app-server EOF behavior, discovery shell wrapping, project generation, and verification helpers.

Still needs environment/input:

- Optional live-host UI validation against a real Codex session on a suitable host. The deterministic fake-server UI path is covered by `Scripts/verify-tap-ui-smoke.sh`; live model/API validation remains intentionally opt-in.

Local raw input channels are still unavailable (`simctl` has no tap/type operation and CoreGraphics event posting is denied), but the generated UI `.xctestrun` path gives a working XCUITest automation channel.

## Security Note

The first MVP accepts any SSH host key. Before treating this as production-ready, replace `.acceptAnything()` with host-key pinning or known-host verification.
