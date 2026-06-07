# Mission: Ship Terminal Feedback Fix To TestFlight

**Mission statement:** Upload the current `master` terminal feedback fix to internal and external TestFlight.

**Done criteria:**
- `master` is clean, pushed, and pulled from `origin/master` before the build.
- Distribution preflight passes.
- Internal TestFlight workflow uploads the next build and adds it to `Internal Testers`.
- External TestFlight workflow submits the same build to `External Testers`.
- Release records capture the build number, build ID, run records, and status.

**Guardrails / Constraints:**
- Build only from up-to-date `master`.
- Use the existing `.asc` workflows.
- Restore normal keychain state after temporary signing setup.

**Critical learnings:**
- Release commit is `0a305a1` (`fix(terminal): show connection state before shell output`).
- `origin/master` was pulled with `--ff-only --autostash`; remote was already up to date.
- Distribution preflight passed before the archive.
- Internal TestFlight build `1.0 (41)` uploaded successfully with BUILD_ID `116d13c1-978a-409a-b72e-df595ee79109`.
- External TestFlight submission to `External Testers` completed for the same build.
- Temporary signing keychain setup was required for non-interactive archive signing and was removed after the workflows completed.
- Build `1.0 (41)` is insufficient: it adds visible status but does not change terminal input delivery.
- `MOBIDEX_SMOKE_MODE=terminal` now uses an isolated server id per run so repeated disposable SSH servers do not trip real host-key pinning.
- `MOBIDEX_SMOKE_MODE=terminal` passed against the disposable SSH server after the direct-write fix, proving the app-level PTY open/write/read service path works.
- The concrete iOS black-screen root cause is the terminal WebView asset lookup: `TerminalView` looked for `TerminalWeb/index-ios.html`, but Xcode copies the terminal resources flat into `Mobidex.app/index-ios.html`; the built app has no `TerminalWeb/` directory, so the WebView never booted.
- Native buttons/text field also routed native -> JavaScript -> native before writing to the PTY; build `1.0 (41)` never changed that path. Direct PTY writes remove that fragile loop.
- After the asset-loader correction, `MOBIDEX_SMOKE_MODE=terminal`, Android `:android-app:compileDebugKotlin`, and whitespace checks passed.

---

# Mission: Restore Terminal Screen Feedback

**Mission statement:** Fix the terminal screen so opening it visibly shows connection/progress state and an interactive prompt/cursor instead of a silent black screen.

**Done criteria:**
- Terminal open path exposes clear connection status before the PTY produces output.
- A connected terminal visibly shows that it is connected and ready even if the remote shell has not printed a prompt yet.
- Failed or stalled terminal opens surface a user-visible error instead of leaving a blank black view.
- iOS and Android terminal paths are checked for the same failure mode.
- Focused review and validation run before landing.

**Guardrails / Constraints:**
- Work from up-to-date `master`.
- Keep terminal UX simple and explicit; do not fake command output as a shell prompt.
- Do not touch unrelated chat/session behavior.

**Critical learnings:**
- `origin/master` was pulled with `--ff-only`; remote was already up to date.
- Both iOS and Android cleared the only visible "Opening terminal" feedback as soon as the PTY session object opened, before any shell bytes arrived.
- Fix keeps terminal status in native UI: opening, connected/waiting for shell output, and error; connected status clears on the first real output chunk.
- The fix does not write fake shell prompts or connection text into the remote terminal stream.

---

# Mission: Ship Retained Chat Display Fix To TestFlight

**Mission statement:** Upload the current `master` retained chat display fix to internal and external TestFlight.

**Done criteria:**
- `master` is clean, pushed, and pulled from `origin/master` before the build.
- Distribution preflight passes.
- Internal TestFlight workflow uploads the next build and adds it to `Internal Testers`.
- External TestFlight workflow submits the same build to `External Testers`.
- Release records capture the build number, build ID, run records, and status.

**Guardrails / Constraints:**
- Build only from up-to-date `master`.
- Use the existing `.asc` workflows.
- Restore normal keychain state after temporary signing setup.

**Critical learnings:**
- Release commit is `1a6beb7` (`fix(chat): retain display during refresh`).
- `origin/master` was pulled with `--ff-only --autostash`; remote was already up to date.
- Distribution preflight passed before the archive.
- Internal TestFlight build `1.0 (40)` uploaded successfully with BUILD_ID `17a08b68-1ebe-4590-b124-de2568db7173`.
- External TestFlight submission to `External Testers` completed for the same build.
- Temporary signing keychain setup was required for non-interactive archive signing and was removed after the workflows completed.

---

# Mission: Decouple Chat Display From Refresh Jitter

**Mission statement:** Stop incoming messages and selected-thread refreshes from clearing or jittering the visible chat while the user is reading, by separating retained display content from transient load state.

**Done criteria:**
- Incoming thread updates do not flash the timeline empty or bounce scroll while data is rehydrating.
- Existing visible sections remain on screen during refresh/reload unless the user changes selected server/project/thread.
- Loading indicators are overlays/inline status, not replacements for retained chat content.
- iOS and Android refresh/display behavior are checked for the same backing-store problem.
- Focused review and validation run before landing.

**Guardrails / Constraints:**
- Work from up-to-date `master`.
- Do not hide true empty states for genuinely empty/new sessions.
- Do not clear user-visible chat content just to signal a background load.

**Critical learnings:**
- `master` is up to date at `cc63239` after build 39 release records.
- Both clients still have direct display-clearing paths (`publishConversationSections([])` / `conversationSections = emptyList()`) mixed into refresh/load flows.
- Partial session-list refreshes must preserve the selected thread snapshot; only the complete follow-up list is allowed to prove that a selected thread disappeared and clear/fallback.
- iOS selected-thread loading status must not be inserted into an already populated timeline because even a harmless status row changes content height and scroll anchoring.
- Android `thread/started` events should hydrate the conversation only when there is no selected thread or the event is for the selected thread; project-scope membership alone is not enough.

---

# Mission: Ship Scroll Anchoring Fix To TestFlight

**Mission statement:** Upload the current `master` scroll anchoring/New Session regression fix to internal and external TestFlight.

**Done criteria:**
- `master` is clean, pushed, and pulled from `origin/master` before the build.
- Distribution preflight passes.
- Internal TestFlight workflow uploads the next build and adds it to `Internal Testers`.
- External TestFlight workflow submits the same build to `External Testers`.
- `NEXT.md` and `ASC.md` record the final build number, build ID, run records, and status.

**Guardrails / Constraints:**
- Build only from up-to-date `master`.
- Use the existing `.asc` workflows.
- Preserve the normal login keychain after temporary signing setup is no longer needed.

**Critical learnings:**
- Release commit is `1426ae4` (`fix(chat): preserve manual scroll position`).
- `origin/master` was pulled with `--ff-only --autostash` after the mission tracker edit; remote was already up to date.
- Distribution preflight passed, internal TestFlight build `1.0 (39)` uploaded successfully with BUILD_ID `17216b9a-e6fc-44b3-b262-0b3f10e6aefd`, and external TestFlight submission to `External Testers` completed.
- Temporary signing keychain setup was required again for non-interactive archive signing and was removed after the workflows completed.

---

# Mission: Fix Chat Scroll Anchoring And Worktree Session Regression

**Mission statement:** Stop incoming chat updates from stealing scroll position when the user is reading earlier messages, and restore reliable New Session in new worktree behavior.

**Done criteria:**
- Incoming messages only auto-scroll when the user is already at or near the bottom.
- The down-arrow remains the explicit way to jump to the newest loaded message.
- New Session in a new worktree works again or fails quickly with a clear error.
- Check other local worktrees for unmerged relevant fixes before coding.
- Run focused review and verification for the changed paths.

**Guardrails / Constraints:**
- Work from up-to-date `master`.
- Do not discard changes in sibling worktrees.
- Fix iOS and Android together when the same behavior exists on both clients.

**Critical learnings:**
- `master` is up to date at `1b7a4e5`; the earlier worktree-start fix is present as `5f97a21`.
- The `codex/fix-steer-now-worktree` worktree has an older duplicate fix commit and is behind `master`; it is not carrying a newer unmerged fix.
- The Grok worktree has uncommitted docs/todo files, but no unique code commits ahead of `master`.
- iOS only disabled chat auto-follow when the user dragged during an active stream; scrolling up while idle left auto-follow armed, so the next incoming active update could pull the viewport back down.
- Android treated being within two list items of the tail as "near bottom", so reading one or two messages above the latest still allowed incoming messages to auto-scroll.
- iOS compact chat only exposed the New Session toolbar button when a thread was selected; project-empty detail screens had no direct way to start the worktree session path.
- Android's primary New Session plus opened a choice dialog instead of performing the default new-worktree action; the dropdown still exposes both locations.

---

# Mission: Ship Chat Audit Fix To TestFlight

**Mission statement:** Commit the chat-screen performance/scroll fixes, build from up-to-date `master`, upload the next TestFlight build, and distribute it to internal and external testers.

**Done criteria:**
- Chat audit fixes are committed on `master` with a conventional commit.
- `master` is pulled from `origin/master` before the TestFlight build.
- `.asc` internal TestFlight workflow completes and records the new build number/build ID.
- External TestFlight workflow submits the same build to `External Testers`.
- `NEXT.md` records the uploaded build, run records, and final status.

**Guardrails / Constraints:**
- Build TestFlight only from up-to-date `master`.
- Do not discard the current chat-screen changes.
- Use the existing `.asc` workflow and App Store Connect configuration.

**Critical learnings:**
- `HEAD`, `master`, and `origin/master` started aligned at `d73adde`; the chat audit changes were uncommitted in a detached worktree.
- Release commit `31043c2` is pushed to `origin/master`; TestFlight build `1.0 (38)` uploaded successfully with BUILD_ID `8a078787-1bc2-4b25-9944-dfdc84373b1f`.
- The first archive attempts failed because non-interactive `codesign` could not access private keys in `login.keychain-db` (`errSecInternalComponent`). Importing `.asc/signing/generated` certificate/key material into a temporary unlocked keychain and making it the default keychain allowed archive/export to complete.
- Internal TestFlight completed and external TestFlight submission to `External Testers` completed on 2026-06-06.

---

# Mission: Audit Chat Screen Performance And Bottom Scroll

**Mission statement:** Audit and fix the chat screen paths that get slow as conversations grow, make the down-arrow bottom-scroll control reliable, and improve the UX when older data has not loaded yet.

**Done criteria:**
- Identify the chat screen rendering/loading causes behind slow long chats.
- Fix the down-arrow control so it scrolls to the newest loaded message predictably.
- Improve loading/scroll UX where unloaded data affects the user experience.
- Run focused review and verification for the changed chat paths.

**Guardrails / Constraints:**
- Keep iOS and Android symmetry in mind, but avoid unrelated client rewrites.
- Prefer simple, obvious scroll/loading state over legacy compatibility modes.
- Do not discard unrelated worktree changes.

**Critical learnings:**
- iOS chat slowdown came from repeated full-section publication on unchanged thread refreshes plus markdown parsing during SwiftUI view construction for visible assistant/reasoning/plan rows.
- The iOS down-arrow targeted only a bottom spacer inside a lazy stack; targeting the latest real section first makes the scroll command reliable when lazy layout is still catching up.
- The selected-thread detail load state existed in the model but was not surfaced in the chat timeline.

---

# Mission: Fix Steer Now and New Worktree Regressions

**Mission statement:** Restore queued "Steer now" and "Start in New Worktree" behavior after the queue/navigation release.

**Done criteria:**
- "Steer now" resolves the current active turn before sending and does not boomerang the item back into the queue on stale local state.
- The steered queued input appears immediately in the transcript and reconciles without duplicates.
- "Start in New Worktree" either creates the worktree/session or fails quickly with a visible error instead of hanging.
- iOS and Android stay symmetric where they share these paths.

**Critical learnings:**
- The queued steer path trusted the locally cached active turn ID; a stale selected thread could make the RPC fail after the item was already removed.
- Android had no new-session timeout around worktree creation or `thread/start`.
- Remote `git worktree add` needs its own shell watchdog because client-side cancellation is not always enough when SSH execs stall.

---

# Mission: Fix Queued Turn Reliability

**Mission statement:** Make queued follow-ups leave the queue when picked up, survive reconnect/background churn, and show steer submissions immediately in the transcript without duplicates.

**Done criteria:**
- A queued item is removed as soon as it is picked up for sending and is requeued only if pickup fails.
- Queued inputs are not cleared by disconnect/reconnect paths that can happen while the app is inactive.
- Steered input gets a local transcript echo quickly and reconciles with the server item without duplicate user messages.
- iOS and Android queue behavior stay symmetric where both clients implement the feature.

**Critical learnings:**
- Queue state was being treated like connection state and cleared during disconnect/reconnect.
- Android dequeued only after `turn/start` returned, leaving a race where completion/refresh paths could pick the same item twice.
- Existing local echo preservation needed to preserve unmatched local echoes and drop matching ones by user text once real server items arrive.

---

# Mission: Fix Predictable Project/Session Navigation

**Mission statement:** Fix project-to-session navigation so users move predictably through server > project > session > conversation, stabilize visible session lists, and reduce agent bubble horizontal waste.

**Done criteria:**
- Tapping a project opens that project's session list without auto-opening an active/empty session.
- Empty projects show an empty session list with the existing new-session action.
- Visible session lists do not reorder from ambient active-session updates, but do refresh after load and explicit user mutations.
- Agent/Codex bubbles use symmetric horizontal margins.
- Focused iOS/Android checks or blockers are recorded.

**Critical learnings:**
- Project taps must suppress thread restoration even when the project was already selected by default.
- Freezing the visible session list needs explicit refreshes after archive/unarchive/new-session so user mutations still appear.
- The Android compact UI needed explicit back handling for chat > sessions and sessions > projects.

---

# Mission: Ship Mobidex To TestFlight

**Mission statement:** Merge the verified release changes to up-to-date `master`, upload a new Mobidex TestFlight build, and distribute it to internal and external testers.

**Done criteria:**
- Release changes are committed and merged to `master`.
- `master` is checked against `origin/master` before the TestFlight build.
- Distribution build is archived, exported, uploaded, and added to the internal TestFlight group.
- The uploaded build is submitted/distributed to the external TestFlight group.
- Build number, version, and any App Store Connect IDs are captured in `NEXT.md`.

**Guardrails / Constraints:**
- Follow the repo rule: build TestFlight from up-to-date `master`, not a side branch.
- Do not discard uncommitted user work; commit the verified release delta intentionally.
- Use the existing `.asc/workflow.json` release automation where possible.

**Critical learnings:**
- App Store Connect credentials are available via `asc` keychain profile `mobidex`.
- `origin/master` is currently behind local `master`; local `master` already contains prior ACP commits.

---

# Prior Mission: Add Generic ACP Agent Launch UI To Mobidex

**Mission statement:** Add a real server-editing UI for ACP-compatible agents so Grok is treated as the default ACP command rather than the product identity.

**Done criteria:**
- Server settings on iOS and Android let the user choose Codex or ACP Agent.
- ACP servers store a launch command, defaulting to the existing Grok stdio command.
- Production ACP launch paths use the configured command while preserving existing Codex behavior.
- Shared command generation has focused regression coverage.
- Focused shared/Android/iOS builds or tests run green.
- Work tracked in `MISSION.md` and `NEXT.md`, with subagent review after the chunk.

**Guardrails / Constraints:**
- Keep the protocol abstraction ACP-first; Grok should be a default command/preset, not the UI concept.
- Avoid legacy compatibility scaffolding except for existing persisted enum values that must still decode.
- Do not disturb Codex app-server launch or chat flows while adding the ACP branch.

**Critical learnings:**
- Existing ACP production wiring was present locally, but it had no user-facing server picker or command field.
- The clean shape is one generic launch command per server. A richer provider/preset layer can come later if it earns its keep.
- Subagent review caught that iOS ACP connection failure could be overwritten as connected; the helper now returns success and the ACP branch uses the existing re-entry guard.

---

# Prior Mission: Fix Mobidex Conversation Markdown And Project Session Coverage

**Mission statement:** Make agent replies render basic markdown emphasis correctly and make project selection show every session that belongs to that project, including Codex worktree sessions like the "cheetah" project case.

**Done criteria:**
- Agent/assistant markdown is rendered through real markdown parsers on iOS and Android, including emphasis and lists, instead of showing literal markers like `**bold**`.
- Project-scoped session loading includes sessions from the project directory and matching Codex worktrees even when exact directory sessions already exist.
- Shared grouping logic is covered by regression tests for the "exact match plus untracked worktree" case.
- Focused iOS/Android/shared tests or builds run green.
- Work tracked in `MISSION.md` and `NEXT.md`, with subagent review after each completed chunk.

**Guardrails / Constraints:**
- Keep changes scoped to presentation parsing and session list matching.
- Preserve existing project/session cache and Codex app-server request shapes.
- Prefer a hard, clear fix over compatibility clutter or new hidden settings.

**Critical learnings:**
- Initial inspection showed both clients already route assistant/reasoning/plan text through lightweight markdown renderers, but that homegrown parser is the wrong abstraction for agent output. The fix should use parser-backed rendering.
- Project session loading queried exact `cwd` paths first and skipped the unscoped scan whenever exact matches existed, so matching Codex worktree sessions were missed for projects with at least one direct session.
- Subagent review caught delimiter loss in the first KMP AST mapping. Structural delimiters are now filtered only inside structural nodes; literal punctuation and streaming/incomplete markdown are preserved.
