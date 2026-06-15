# Mission

Mission: Align Mobidex's Codex app-server requests with the current Codex CLI/TUI protocol behavior discovered in `/Users/mazdak/Code/codex`.

Done criteria:
- [x] Confirm the Mobidex worktree is current with the repo default branch.
- [x] Identify where Mobidex discovers, stores, names, and lists Codex projects/threads.
- [x] Compare those assumptions with available Codex CLI/TUI source or local Codex state.
- [x] Send `runtimeWorkspaceRoots` when starting Codex threads with a cwd.
- [x] Send `runtimeWorkspaceRoots` when starting Codex turns with a known cwd.
- [x] Use app-server's multi-cwd `thread/list` filter for project session paths.
- [x] Remove brittle exact client-side cwd filtering after server-filtered list calls.
- [x] Update focused protocol/client tests and run validation.
- [x] Commit and merge the fix into `master`.

Guardrails:
- Do not touch unrelated release metadata or previous TestFlight artifacts.
- Preserve existing user changes if the worktree becomes dirty.
- Prefer hard breaks over compatibility shims unless the user asks otherwise.

Critical learnings:
- The worktree started detached and `git pull origin master` reported it was already up to date.
- Mobidex starts project sessions in `$HOME/.codex/worktrees/<id>/<repo>` and stores those worktree cwds in the selected project's `sessionPaths`.
- Mobidex discovery already reads Codex's `.codex-global-state.json`, including workspace-root hints, but the Mobidex session creation path does not register new worktree sessions there.
- The current Codex app-server still stores thread state under `CODEX_HOME` (`~/.codex` by default); CLI/TUI source does not show a hard-coded `~/Code/codex` project model.
- Clarification: `/Users/mazdak/Code/codex` is the local Codex source checkout used for comparison. The open source checkout contains CLI/TUI/app-server/protocol code, but the Desktop-specific project registry keys (`electron-saved-workspace-roots`, `active-workspace-roots`, `project-order`, `thread-workspace-root-hints`) do not appear in that source tree.
- Current Codex app-server `thread/list` supports one or many cwd filters and normalizes path comparisons server-side. Mobidex previously looped over single cwd filters and applied exact local `cwd == cwd` filtering in Swift/Android clients.
- Current Codex app-server supports `runtimeWorkspaceRoots` on `thread/start` and `turn/start`; Mobidex previously sent only `cwd`.
- The likely Desktop mismatch is workspace-root identity: Desktop appears to group by saved/active workspace roots and thread workspace-root hints, while Mobidex-created sessions only have their worktree cwd plus Mobidex-local `sessionPaths`.
- Decision: implement the public app-server alignment only; do not write Desktop-private `.codex-global-state.json` keys.
- Validation: subagent review found missing Android multi-cwd list coverage and noted `turn/start` runtime-root support; both items were addressed.
- Validation passed: `:shared-core:jvmTest`, `:android-app:testDebugUnitTest`, and focused iOS simulator tests for `CodexProtocolTests`, `testConnectLoadsProjectThreadsAcrossWorktreeSessionPaths`, and `testStartNewSessionCreatesAndSelectsThreadWhenConnected`.

Prior master mission retained:
- Fixed the iOS new-worktree session launch hang/error where `thread/list` could time out after starting a session.
- iOS had allowed New Session while `refreshingSessions` was active; Android already blocked this through its `isBusy` predicate.
- Notification-driven iOS thread-list refresh errors were foregrounded through `statusMessage`, so a background `thread/list` timeout could appear in the new-session empty state.
