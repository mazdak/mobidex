# Review Notes

This file records the subagent review checkpoints used during the Mobidex build.

## Discovery Shell Wrapper

- Finding: Citadel `executeCommand(..., inShell: true)` appends `;exit\n`, so the discovery heredoc terminator must stay on its own line and Python failures must keep their exit status.
- Fix: `RemoteCodexDiscovery.shellCommand` now ends with `PY\nmobidex_status=$?;exit $mobidex_status`, which becomes `PY\nmobidex_status=$?;exit $mobidex_status;exit\n` after Citadel appends its suffix.
- Verification: `Scripts/verify-discovery.sh` simulates the suffix, asserts no `PY;exit` or bare `;exit` line appears, verifies nonzero Python exit-status propagation, and checks exact synthetic `.codex` discovery output.
- Follow-up fix: discovered session counts are persisted on `ProjectRecord` and rendered in the project list instead of being dropped after discovery.
- Follow-up review finding: previously discovered projects could keep stale positive counts when a later `.codex` scan omitted them, zero-session discoveries were hidden, and the new persisted field needed an intentional storage-shape decision.
- Follow-up fix: discovery refresh now clears stale discovery metadata for omitted projects, the project list renders a zero-session discovered state, and server metadata uses a new storage key rather than a compatibility decoder for the old project shape.
- Follow-up review: no remaining blocking findings or verification gaps for this scope after the stale-count and storage-key fixes.
- Follow-up finding: macOS zsh treats `status` as a read-only shell variable, so the original exit-status wrapper failed on localhost SSH even after Python emitted valid JSON.
- Follow-up fix: the wrapper now uses `mobidex_status`, `Scripts/verify-discovery.sh` checks zsh exit-status propagation when zsh is installed, and the localhost generated-key SSH verifier passes through discovery.

## In-App SSH Smoke

- Finding: an ad hoc simulator helper app cannot use the normal Keychain entitlement reliably, so a smoke-only app launch path failed before reaching SSH.
- Fix: when `MOBIDEX_SMOKE=1`, `MobidexApp` uses in-memory repositories/credentials with the real `CitadelSSHService`, preserving the production Keychain path for normal launches.
- Follow-up finding: local macOS `sshd` runs non-login commands with a reduced PATH, so a `~/.bun/bin/codex` Node wrapper could authenticate successfully and then fail to start app-server.
- Follow-up fix: `Scripts/verify-inapp-ssh-smoke.sh` generates a temporary Codex wrapper that exports the current PATH before execing the configured Codex path; app stdout/stderr and `sshd` logs are printed on failure.
- Follow-up finding: the smoke originally accepted expected text from any conversation section, which allowed the user prompt to satisfy the check.
- Follow-up fix: `MobidexLaunchSmoke` now requires expected text in an assistant section and records `assistantSectionCount` in the result.
- Review follow-up fixes: the smoke now writes a `waiting-for-text` running stage, gives the outer script a 60-second result-file cushion beyond the app wait, checks expected text in assistant body only, and expands `~` / `~/` in `MOBIDEX_SMOKE_CODEX_PATH` before writing the temporary wrapper.
- Verification: `MOBIDEX_SMOKE_TIMEOUT=240 MOBIDEX_SMOKE_CODEX_PATH='~/.bun/bin/codex' Scripts/verify-inapp-ssh-smoke.sh` succeeds, reporting `assistantSectionCount: 1`, `conversationSectionCount: 2`, and `expectedTextFound: true`, and writing `/tmp/mobidex-inapp-ssh-smoke.png`.
- Follow-up fix: the smoke now supports `MOBIDEX_SMOKE_AUTH=password|private-key` and `MOBIDEX_SMOKE_MODE=turn|connection`, so password authentication can be validated through the in-app Citadel command path without requiring a local system account password.
- Verification: `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=connection MOBIDEX_SMOKE_TIMEOUT=120 Scripts/verify-inapp-ssh-smoke.sh` succeeds against a disposable AsyncSSH password server, reporting `authMethod: password`, `mode: connection`, and `status: success`.
- Review follow-up fixes: password smoke now defaults to `connection` and no longer requires a local `codex` executable for connection-only smoke.
- Follow-up finding: the first disposable AsyncSSH password server handled exec requests but not shell requests, while Citadel uses shell mode for `.codex` discovery. This made the full password turn smoke fail after app-server initialize and before discovery.
- Follow-up fix: the AsyncSSH password server now launches a real local shell for shell requests and keeps exec handling for app-server commands.
- Verification: `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_TIMEOUT=120 Scripts/verify-inapp-ssh-smoke.sh` succeeds without an explicit mode, reporting `authMethod: password`, `mode: connection`, and `status: success`.
- Verification: `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=turn MOBIDEX_SMOKE_TIMEOUT=120 MOBIDEX_SMOKE_CODEX_PATH='~/.bun/bin/codex' Scripts/verify-inapp-ssh-smoke.sh` succeeds through the full password-auth app-server turn path with assistant output detected.
- Verification: after the password-mode review fixes, `MOBIDEX_SMOKE_TIMEOUT=240 MOBIDEX_SMOKE_CODEX_PATH='~/.bun/bin/codex' Scripts/verify-inapp-ssh-smoke.sh` still succeeds through the private-key app-server turn path with assistant output detected.
- Follow-up fix: `MOBIDEX_SMOKE_MODE=control` starts a deterministic fake app-server over the same SSH transport, avoiding model/API spend while exercising app control actions.
- Verification: `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=control MOBIDEX_SMOKE_TIMEOUT=120 MOBIDEX_SCREENSHOT_PATH=/tmp/mobidex-control-ui-smoke.png Scripts/verify-inapp-ssh-smoke.sh` succeeds, reporting `approvalHandled: true`, `interruptHandled: true`, `assistantSectionCount: 1`, and `expectedTextFound: true`; the screenshot shows the compact conversation detail with the steered assistant response after interrupt.
- Review follow-up fix: the fake control app-server now asserts `thread/start` cwd, `thread/read` id, `turn/start` id, `turn/steer` thread id / expected turn id / input text, `turn/interrupt` thread id / turn id, and approval decision payloads before allowing the smoke to pass.
- Review follow-up fix: the fake control app-server now also requires that the approval response was observed before accepting `turn/steer` or `turn/interrupt`, so the smoke cannot pass by clearing only local pending-approval state.
- Follow-up fix: `MOBIDEX_SMOKE_MODE=approval` stops at the pending approval state, asserts pending approval / loaded thread / active interrupt state from the app result JSON, and captures a visible compact conversation-detail screenshot without spending model/API resources.
- Follow-up finding: compact `NavigationSplitView` did not promote to the conversation detail from launch-smoke state changes with `columnVisibility` alone.
- Follow-up fix: `RootView` now also binds `preferredCompactColumn`, and project/session taps plus smoke-driven selected-thread changes set it to `.detail`.
- Verification: `MOBIDEX_SMOKE_AUTH=password MOBIDEX_SMOKE_MODE=approval MOBIDEX_SMOKE_TIMEOUT=120 MOBIDEX_SCREENSHOT_PATH=/tmp/mobidex-approval-ui-smoke.png Scripts/verify-inapp-ssh-smoke.sh` succeeds and the screenshot shows the active conversation detail with a command approval card and user message.
- Follow-up fix: `Scripts/verify-visible-ui-smokes.sh` wraps the approval and control visible UI smokes and checks both screenshots are written.
- Verification: `MOBIDEX_VISIBLE_SCREENSHOT_DIR=/tmp/mobidex-visible-ui-smokes Scripts/verify-visible-ui-smokes.sh` succeeds and writes `approval.png` plus `control.png`.
- Review follow-up fixes: the visible UI wrapper now rejects `MOBIDEX_SMOKE_TIMEOUT=0` before launching child smokes and removes each target screenshot before capture so stale files cannot mask a missing screenshot.
- Verification: `bash -n Scripts/verify-visible-ui-smokes.sh`, the `MOBIDEX_SMOKE_TIMEOUT=0` rejection path, and the full visible UI wrapper all pass after the hardening.
- Follow-up fix: `MOBIDEX_SMOKE_MODE=seed` plus `MOBIDEX_STAY_ALIVE_ON_SUCCESS=1` seeds the launched app with a fake SSH/app-server target and keeps the disposable server alive for manual Simulator UI probing.
- Follow-up fix: `Scripts/verify-manual-ui-seed.sh` wraps seed mode with manual tap instructions and defaults suitable for handoff.
- Review follow-up fix: the README no longer lists `Scripts/verify-manual-ui-seed.sh` in the normal noninteractive helper block because the wrapper intentionally waits in manual handoff mode by default; it now documents the noninteractive validation overrides separately.
- Historical check: `simctl io`/`simctl ui` provide screenshot/video/display and UI appearance settings only, no local click/HID helper is installed, and `System Events` UI automation is disabled; raw manual tap injection was not available in this environment.
- Historical check: a no-package UI-test harness still could not get an iOS Simulator destination once a UI-test bundle was present, and CoreGraphics synthetic input was denied (`CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` returned `false`).
- Follow-up fix: `Scripts/verify-inapp-ssh-smoke.sh` now has `MOBIDEX_SMOKE_SETUP_ONLY=1` plus `MOBIDEX_SMOKE_ENV_PATH`, which starts the disposable fake SSH/app-server, writes app launch environment values, and stays alive until stopped.
- Follow-up fix: `MobidexUITests` and `Scripts/verify-tap-ui-smoke.sh` use the setup-only seed path plus a generated UI `.xctestrun` to run XCUITest outside the broken normal scheme destination resolver.
- Verification: `MOBIDEX_UI_SMOKE_TIMEOUT=120 Scripts/verify-tap-ui-smoke.sh` succeeds, executing 1 XCUITest with 0 failures. The log records synthesized taps on Connect, project row, composer, Send, Approve, Send, and Stop Turn, and stores a screenshot attachment before interrupt.
- Review findings fixed: compact launches that start on the server sidebar now tap `serverRow` before waiting for `connectButton`; the test waits for `approveButton` to disappear before sending steer text; the verifier writes absolute bundle paths into the generated UI `.xctestrun`; and the default UI `.xctestrun` lives under a temporary work directory so the smoke password is not left in `build/`.
- Verification: after those fixes, `MOBIDEX_UI_SMOKE_TIMEOUT=120 Scripts/verify-tap-ui-smoke.sh` succeeds again, and `build/MobidexUIGenerated.xctestrun` is absent after cleanup.

## Build Verification Helper

- Historical finding: the normal Xcode scheme previously could not resolve an eligible iOS Simulator destination.
- Fix: `Scripts/verify-ios-build.sh` provides a target-level verification path that prepares local SwiftPM module-map/include/resource-bundle workarounds for Citadel, Swift Crypto, SwiftNIO, and Wellz26 swift-nio-ssh.
- Follow-up fix: the helper now passes one deterministic Swift package clone root to both package resolution and target builds, avoiding mixed package products from stale `~/Library/Developer/Xcode/DerivedData` entries.
- Verification: `Scripts/verify-ios-build.sh Mobidex`, `Scripts/verify-ios-build.sh MobidexTests`, `SDK=iphoneos Scripts/verify-ios-build.sh Mobidex`, and `SDK=iphoneos Scripts/verify-ios-build.sh MobidexTests` all end with `BUILD SUCCEEDED`.
- Follow-up fix: `project.yml` now generates all four iOS interface orientations, removing the device-SDK validation warning about partial orientation support.
- Historical check: `simctl` originally listed only iOS 26.1/26.2 simulators, and scheme build-for-testing still failed destination matching during that investigation.
- Historical check: installing iOS 26.4 Simulator 23E244 and booting an iOS 26.4 simulator did not immediately make `xcodebuild` list an iOS Simulator destination for the scheme.
- Follow-up check: rebuilding `MobidexTests` creates `build/Debug-iphonesimulator/Mobidex.app/PlugIns/MobidexTests.xctest`, but direct simulator `xctest` execution fails because the hosted test bundle expects symbols from `Mobidex.app/Mobidex`; the helper `.xctestrun` path is the supported direct simulator-test gate.
- Follow-up finding: the helper-built test bundle initially lacked its own `Info.plist`, so it could compile/link but was not a valid runtime XCTest bundle.
- Follow-up fix: `project.yml` now generates `Tests/MobidexTests/Info.plist`, and `Scripts/verify-simulator-tests.sh` builds the hosted test bundle, writes a generated app-hosted `.xctestrun` with the XCTest injector environment, and runs `xcodebuild test-without-building` on a concrete simulator destination.
- Follow-up finding: actual simulator XCTest execution exposed that `ScriptedSSHService.openAppServer` did not match production because it returned an uninitialized app-server client.
- Follow-up fix: the scripted SSH service now initializes the client before returning it, matching `CitadelSSHService.openAppServer`.
- Verification: `Scripts/verify-simulator-tests.sh` succeeds, executing 29 app-hosted simulator tests with 0 failures.
- Follow-up fix: `Scripts/verify-official-scheme.sh` captures the official scheme gate plus Xcode version, first-launch status, SDKs, installed runtimes, scheme destinations, a destination diagnosis, and the command output into one log for rechecking after environment or dependency changes.
- Review follow-up fixes: stale `NEXT.md` runtime-only evidence is now marked historical/superseded, and `MOBIDEX_SCHEME_ACTION=test` now requires a concrete, non-generic `MOBIDEX_DESTINATION` instead of using the generic build destination.
- Verification: `bash -n Scripts/verify-official-scheme.sh`, the missing/generic-destination `MOBIDEX_SCHEME_ACTION=test` guards, and the default official scheme diagnostic path all behave as expected.
- Historical check: `xcodebuild -runFirstLaunch -checkForNewerComponents` reported no new updates for Xcode 17E202 during the earlier destination investigation.
- Historical check: after restarting CoreSimulator, a fresh no-package generated iOS app reproduced the same missing simulator destination behavior, suggesting the earlier issue was local Xcode destination resolution rather than Mobidex-specific code.
- Follow-up fix: `Scripts/verify-official-scheme.sh` now logs available simulator devices as well as runtimes, making the runtime/device-versus-`xcodebuild` destination mismatch explicit.
- Historical check: explicit iOS 26.4 device-support preparation for the paired iPhone 16 Pro started copying but did not complete within a 20-minute bound.
- Follow-up cleanup: the partial locked device-support directory was moved aside to `.mobidex-partial-iPhone17,1-26.4.2-23E261-20260503-0634`.
- Follow-up check: `xcodebuild -downloadPlatform iOS -buildVersion 26.4 -architectureVariant universal` downloaded the 10.6 GB universal iOS 26.4 simulator payload but failed installation as a duplicate of the ready iOS 26.4 arm64 runtime. The unusable duplicate runtime image was removed with `xcrun simctl runtime delete`; runtime listing now shows only ready iOS disk images.
- Follow-up fix: `Scripts/verify-official-scheme.sh` now logs `xcrun simctl runtime list` and an unusable-runtime count, so future scheme-gate rechecks capture duplicate/unusable runtime state.
- Follow-up review: no blocking findings for the helper itself; the official scheme gate now passes after the Mobidex rename/regeneration pass.

## Simulator Launch Verification

- Historical finding: while official scheme destination selection was blocked, the helper-built simulator app could still be installed and launched directly with `simctl` on the available simulator runtimes.
- Fix: `Scripts/verify-simulator-launch.sh` forces a Debug simulator helper build, installs the app on an available iOS simulator, terminates any existing app process, launches `com.mazdak.mobidex`, verifies the launched PID is still running after a settle delay, and captures a screenshot.
- Verification: `MOBIDEX_SCREENSHOT_PATH=/tmp/mobidex-runtime/verify-launch-default-full.png Scripts/verify-simulator-launch.sh` succeeds and the screenshot shows the rendered initial `Servers` / `No Servers` UI.
- Follow-up review findings: the verifier originally could inherit `SDK=iphoneos` / `CONFIGURATION=Release`, could interact with a running app, and auto-device parsing initially selected the status token instead of the simulator UDID.
- Follow-up fixes: the verifier now command-scopes `SDK=iphonesimulator CONFIGURATION=Debug`, terminates before launch and uses `--terminate-running-process`, extracts UUID-shaped device IDs, only shuts down simulators it observed as `Shutdown`, waits before screenshot capture, and checks the launched PID with `launchctl`.
- Follow-up review: no blocking findings for the final verifier; documented `MOBIDEX_SKIP_BUILD` and `MOBIDEX_APP_PATH` remain debugging escape hatches, while the default command validates a fresh Debug simulator build/install/launch path.

## Live Host Verification

- Finding: live SSH/app-server validation remains external because no reachable host credentials were provided.
- Fix: `Scripts/verify-live-host.sh` now provides a repeatable key/agent-based smoke test for SSH command execution, remote `python3`/Codex availability, Mobidex's heredoc-shaped discovery command with merged stderr/stdout, and app-server initialize over SSH.
- Follow-up finding: a probed SSH devbox had Codex installed at a user-local path but not on the non-interactive SSH PATH, which would prevent app-server startup.
- Follow-up fix: server settings now include a configurable Codex path, and `Scripts/verify-live-host.sh` accepts `MOBIDEX_CODEX_PATH`.
- Follow-up review finding: home-relative Codex paths needed quoted remote `$HOME` expansion to avoid shell splitting if the remote home directory contains spaces.
- Follow-up fix: app command generation and the live verifier now emit `"${HOME}"/...` for `~/...` paths; the tilde-path live smoke succeeds against the devbox.
- Follow-up review: no remaining blocking findings for the Codex path or live-host verifier changes.
- Follow-up finding: app-server `thread/archive` requires a materialized rollout, and `thread/read includeTurns=true` fails before the first user message.
- Follow-up fix: the opt-in no-turn path now always creates an ephemeral thread and validates metadata `thread/read` with `includeTurns=false` instead of creating a persistent no-turn thread that cannot be archived.
- Follow-up review findings: the opt-in path originally only ran on empty hosts, `MOBIDEX_CODEX_HOME` only applied to discovery, and the default opt-in cwd left a fixed remote helper directory behind.
- Follow-up fixes: `MOBIDEX_LIVE_CREATE_THREAD=1` now runs the ephemeral read-only metadata-read branch whenever requested, app-server is launched with `CODEX_HOME` when configured, and the default cwd is a unique remote temp directory whose directory and generated project-trust stanza are removed by the script trap.
- Verification: script syntax passes, the missing-configuration path fails fast with the required environment variables, and key/agent devbox smokes with `MOBIDEX_CODEX_PATH='~/.bun/bin/codex'` and explicit `MOBIDEX_CODEX_HOME='~/.codex'` validate SSH command execution, remote `python3`, the configured Codex executable, `.codex` discovery, app-server stdio initialize, and live `thread/list`. The opt-in `MOBIDEX_LIVE_CREATE_THREAD=1` path validates ephemeral no-turn `thread/start` and metadata `thread/read`, and a post-run remote check found no `mobidex-live-verify` directories or Codex metadata references left behind. In-app private-key, password command, and password app-server turn smokes now run on simulator.
- Follow-up review: no blocking findings for the opt-in ephemeral branch, `MOBIDEX_CODEX_HOME` app-server propagation, cleanup behavior, or documentation boundaries.
- Follow-up fix: `MOBIDEX_LIVE_CREATE_TURN=1` adds a separate explicit opt-in for live materialized turn validation. It creates a non-ephemeral temporary thread, starts a real turn, accepts completion from `turn/start`, `turn/completed`, or hydrated `thread/read`, requires final status `completed`, reads with `includeTurns=true`, archives the temporary thread, interrupts if a turn remains active on failure, and fails clearly on server requests it cannot answer.
- Follow-up review findings: the first draft used an ephemeral thread for hydrated turn reads, lacked protocol-level interrupt cleanup, buffered server requests as if they were notifications, and left app-server stderr as an undrained pipe.
- Follow-up fixes: the turn smoke now uses a non-ephemeral thread, archives after hydrated read, interrupts/archives in error cleanup, sends app-server stderr to `DEVNULL`, fails fast on request-shaped inbound messages, and checks terminal turn status before treating the smoke as passed.
- Verification: `bash -n Scripts/verify-live-host.sh` passes, the missing-configuration path fails fast, targeted embedded Python syntax checks pass, and focused subagent review found no blocking findings for the materialized-turn verifier. The `MOBIDEX_LIVE_CREATE_TURN=1` path now passes against the key/agent devbox.
- Refresh validation: on 2026-05-03 02:38 EDT, script syntax, targeted embedded live-verifier Python syntax, discovery/schema verifiers, `Scripts/verify-ios-build.sh MobidexTests`, and `MOBIDEX_SCREENSHOT_PATH=/tmp/mobidex-runtime/verify-launch-proceed.png Scripts/verify-simulator-launch.sh` all passed. The launch screenshot rendered the expected empty `Servers` screen; at that time official scheme destinations remained ineligible due the missing iOS 26.4 platform.
- Follow-up fix: live materialized turns can complete in the rollout without a separate `turn/completed` notification reaching the stdio verifier, so `Scripts/verify-live-host.sh` now falls back to polling `thread/read includeTurns=true` for the started turn's terminal status. Mobidex also handles terminal `turn/start` responses by hydrating the thread instead of leaving the UI in an active state.
- Verification: `MOBIDEX_LIVE_CREATE_TURN=1 Scripts/verify-live-host.sh` succeeded against the key/agent devbox with `MOBIDEX_CODEX_PATH='~/.bun/bin/codex'`, creating a temporary materialized turn, hydrating one completed turn, archiving it, and leaving no temporary cwd/config references. `Scripts/verify-discovery.sh`, `Scripts/verify-app-server-schema.sh`, live verifier syntax/embedded Python syntax, and `Scripts/verify-ios-build.sh MobidexTests` pass.
- Follow-up fix: `.codex` discovery now filters config and rollout cwd paths to existing absolute directories, preventing archived temporary or stale cross-machine cwd paths from appearing as projects. The discovery verifier now covers missing config paths and missing session cwd paths.

## App State and Protocol Handling

- Findings addressed during implementation: app-server EOF and send failures left stale state, async project/thread work could apply after selection changes, and credential deletion needed rollback on partial failure.
- Fixes: app-server client now closes on EOF/send failure, fails pending calls, finishes event streams, and rejects later requests; view-model async paths snapshot server/project/thread scope before applying results; credential deletion restores metadata/secret state on confirmed rollback paths.
- Verification: focused tests cover credential separation and rollback, JSON-RPC request shapes, EOF handling, session projection, remote discovery command shape/decode, stale composer results after project changes, and simulator-independent AppViewModel composer start/steer/interrupt control flow.
- Follow-up review: no blocking findings for the AppViewModel composer control-flow regression test.
- Follow-up review finding: `loadThreads()` prioritized active sessions, but notification-driven refreshes after `thread/*` and `turn/completed` events assigned the raw app-server list, so a live update could move recent idle sessions back above older active sessions.
- Follow-up fix: both selected-thread and list-only event refreshes now use the same active-first ordering as initial load.
- Verification: `AppViewModelTests.testLoadThreadsPrioritizesActiveSessions` now covers initial load, a `thread/updated` refresh, and stable app-server ordering within the active and inactive buckets.
- Follow-up review: no blocking findings for the active-session ordering fix, regression coverage, or tracker wording.
- Follow-up finding: `sendComposerText` always called the full `loadThreads()` after `turn/start`/`turn/steer`; for an in-progress turn that path can block on selected-thread `thread/read`, leaving the composer busy until the turn hydrates.
- Follow-up fix: active `turn/start` and `turn/steer` now refresh only the session list. Completed turn responses still hydrate immediately, while live notifications and active-turn polling hydrate active conversations.
- Review follow-up findings: active-turn polling could replace newer streamed deltas with an older active `thread/read` snapshot, and a delayed `thread/started` notification could clear an already-active composer-started thread.
- Review follow-up fixes: active polling now only hydrates terminal/non-active snapshots, and `thread/started` only hydrates when no selected thread has been loaded yet.
- Verification: `Scripts/verify-ios-build.sh MobidexTests` passes after regression coverage for both races, and the in-app SSH smoke reaches assistant output instead of timing out at the send stage.

## Codex App-Server Schema Alignment

- Finding: the original objective explicitly points to `~/Code/codex` as the app-server source of truth, so Mobidex should have a repeatable local check against that schema.
- Fix: `Scripts/verify-app-server-schema.sh` checks the Mobidex protocol surface against the generated TypeScript schema in `codex-rs/app-server-protocol/schema/typescript`.
- Follow-up finding: schema audit found missing Mobidex coverage for turn-level plan/diff updates, terminal interaction output, MCP progress, and legacy `execCommandApproval` / `applyPatchApproval` requests.
- Follow-up fix: `AppViewModel` now handles those conversation events, current command approval detail formatting, server-request resolution cleanup, and legacy approval responses; `Scripts/verify-app-server-schema.sh` checks the schema names plus selected Mobidex handler cases.
- Follow-up review: current string command approvals, legacy argv-array approvals, legacy patch approvals, and server-request resolution cleanup are rendered/handled and tested correctly.
- Verification: the script checks required thread/turn methods, the `initialized` client notification, live server notification names, selected handler cases, parsed thread item types, `text_elements` user input shape, and supported server-request response fields/types/literals. ChatGPT auth-token refresh is recognized as unsupported in this MVP.
- Follow-up finding: app-server `thread/list` defaults to interactive sources when `sourceKinds` is omitted, which can hide exec/app-server/subagent sessions on servers Mobidex is meant to monitor.
- Follow-up fix: Mobidex and `Scripts/verify-live-host.sh` now send all known `ThreadSourceKind` values, and the schema verifier checks those literals exist.
- Follow-up review: no blocking findings for the all-source-kind `thread/list` request shape, live verifier behavior, or documentation; future upstream additions to `ThreadSourceKind` should be caught by periodic schema audits.

## Litter Conversation Reference

- Finding: Litter's iOS conversation layer treats plan text and file-change patches as live timeline content, not only final hydrated history.
- Fix: Mobidex handles `item/plan/delta`, `turn/plan/updated`, `item/fileChange/patchUpdated`, `turn/diff/updated`, legacy `item/fileChange/outputDelta`, terminal-interaction output, and MCP progress in `AppViewModel` while keeping the app iOS-only and avoiding Litter's shared Rust store, local-network/Tailscale discovery, voice, watch, wallpaper, widget, and Android surfaces.
- Verification: `AppViewModelTests.testPlanAndFileChangeEventsUpdateLiveConversation` covers plan delta, turn-plan update, file patch update, legacy file-change output, turn-diff update, terminal interaction, and MCP progress behavior; focused review found no remaining blocking issues.

## Completion Audit Follow-Ups

- Finding: `AppViewModel.sendComposerText` could create a thread when no thread was selected, but `ConversationView` only exposed the composer when `selectedThread` existed.
- Fix: a selected project with no listed sessions now shows a project header, empty-session state, and composer, making the no-selected-thread `thread/start` path reachable from the UI.
- Follow-up review finding: if a `thread/started` notification auto-selected the same new thread before the `thread/start` response resumed, the first prompt could be dropped.
- Follow-up fix: no-thread composer sends now accept either the original selection state or the same newly started thread selected by a matching notification, while still rejecting project/thread changes.
- Follow-up review finding: compact split-view layouts could leave the new-thread detail composer unreachable after a project/session tap because rows only mutated model state.
- Follow-up fix: `RootView` now owns `NavigationSplitView` column visibility, project/session taps promote the detail column only in compact horizontal size classes, and regular-width size changes reset visibility to automatic.
- Verification: `Scripts/verify-ios-build.sh MobidexTests` and `Scripts/verify-ios-build.sh Mobidex` pass after the UI and race fixes; `AppViewModelTests.testComposerStartsSteersAndInterruptsThroughViewModel` covers the no-selected-thread `thread/start` and `turn/start` happy path, and `AppViewModelTests.testComposerStartContinuesWhenThreadStartedEventSelectsNewThreadFirst` covers the notification-before-response race.
- Follow-up review: no blocking findings for the first-prompt race fix, empty-project composer reachability, compact-only detail promotion, or regular-width visibility reset.
