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
