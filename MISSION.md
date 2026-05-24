Mission: Restore reliable New Session creation and SSH app-server startup, and prove the app navigation no longer exposes the phantom detail page.

Done criteria:
- List every visible app page/surface and identify which one caused the phantom page.
- Make New Session create/select the new thread before compact navigation promotes the conversation detail.
- Keep the valid empty project-session state without letting it masquerade as an intermediate new-session page.
- Fix the Mac SSH app-server startup regression without breaking Linux or configured launch paths.
- Check the same SSH launch-command behavior in the shared Android model where applicable.
- Run subagent review after each coherent chunk, then focused unit tests, xcodebuild simulator tests, simulator launch/screenshot checks, and relevant Android/shared checks.

Guardrails:
- Prefer a hard, simple fix over backwards-compatible dead paths.
- Do not remove real empty states for servers/projects that truly have no sessions.
- Do not hide SSH bootstrap errors that matter; only prevent ordinary interactive shell rc noise from killing app-server startup.

Critical learnings:
- Page inventory: root split view has Servers sidebar, project/session list, conversation detail, settings/add/edit server sheets, add project/remote folder browser sheets, terminal sheet, diagnostics sheet, session changes tab, queue sheet, and photo/file pickers.
- The phantom page was the `ConversationView` project-detail empty state, not an independent route. It could appear because compact navigation promoted to detail before `thread/start` created a selected thread.
- New Session now returns the created thread id; compact navigation promotes only when that id is selected, and stale success/failure responses return nil.
- The project-detail empty state no longer has its own New Session button. Starting sessions belongs to the project session toolbar.
- SSH app-server launch must source configured rc files; the Mac failure reproduced because Mobidex sourced `.zshrc` before prepending Homebrew paths, so `starship`, `zoxide`, and `fzf` were missing under an SSH-style sparse PATH.
- SSH app-server launch now exports Mobidex's tool PATH first, then sources the configured rc file, then starts/discovers Codex. Rc stdout is redirected to stderr and rc source failures are non-fatal.
- The default shell startup file is now `$HOME/.zprofile`, and existing `.zshrc` paths are migrated to the matching `.zprofile` path; Linux `.bashrc` paths are preserved.
- Android loaded-state migration preserves configured shell startup files while migrating `.zshrc` to `.zprofile` and clearing stale app-server project session counts.
- Validation: subagent reviews passed after fixes; shared core, Android unit tests, XcodeBuildMCP simulator tests, app-hosted simulator XCTest helper, simulator launch/screenshot, tap UI smoke, and in-app SSH control smoke passed with `/Users/mazdak/.zshrc` configured and migrated to `.zprofile`.
- Residual risk: an old host-key pin can still block a localhost smoke with a reused test server id; rerunning with a fresh smoke server id verified app-server startup successfully.
