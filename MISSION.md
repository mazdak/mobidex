# Mission: ACP Support for Grok in Mobidex

**Mission statement:** Enable Mobidex to connect to and drive Grok agents (via the Agent Client Protocol over `grok agent stdio`) from the phone using the existing rich conversation UI and SSH connections, with a clean raw stdio/JSON-RPC line transport.

**Done criteria:**
- Can generate a minimal, correct launch command for `grok agent stdio` (with PATH bootstrap, model selection, nohup-free).
- Raw line transport (`openRawExec` / `CodexLineTransport` impls) exists and is used for ACP (already partially scaffolded).
- Minimal ACP client (initialize + session/new + session/prompt + basic streaming consumption of session/update) exists and can perform a handshake + simple prompt against a real `grok agent stdio` (or mock).
- ACP session/update chunks (agent_message_chunk / thought / reasoning, tool_call, plan, approvals, etc.) are translated into the existing `CodexSessionItem` model (AgentMessage, Reasoning, Plan, ToolCall, etc.) so they render in the chat window using the current ConversationSection / projection machinery (no or minimal duplication of UI rendering code).
- At least one end-to-end smoke (test or manual via a ViewModel path) demonstrates connecting and receiving streaming chunks from an ACP agent that appear correctly in the rich chat UI.
- Codex app-server path and its launch logic remain 100% untouched.
- Work tracked in MISSION.md / NEXT.md / TODO.md; every chunk follows code → subagent review → fix → test → mark done.
- Conventional commit style for any commits.

**Guardrails / Constraints:**
- Do NOT edit the unconditional launch / proxy script logic inside RemoteCodexAppServerCommand.kt (rogue agents issue kept in back pocket).
- Prefer simple, obvious, hard-to-misuse interfaces. No hidden modes or excessive config for the first cut.
- KMP/shared-core for protocol request builders, JSON handling, and core client logic where it avoids duplication.
- Reuse `CodexLineTransport` (neutral line pipe) for ACP clients in the sketch phase; rename only if it becomes a clear wart later (hard break when justified).
- No WebSocket upgrade for the primary `grok agent stdio` SSH-exec path.
- Auth: support injecting env (e.g. XAI_API_KEY) or rely on remote user context for `~/.grok`; keep simple for v1.
- After each discrete chunk or todo item completion: launch subagent review, fix findings, run focused tests/build validation, then mark done.
- Park non-blocking side quests (e.g. full UI branching, ServerRecord discriminator, x.ai/* extensions, rich plan/tool rendering) in NEXT.md.

**Critical decisions logged (item 7 close + handoff):**
- xcodegen + explicit git add of new .swift files remains load-bearing for iOS ACP work (pbxproj snapshot drift is the recurring integration tax; always verify after adding platform client files).
- The isolated DEBUG preview + exact shared projection was the minimal way to satisfy the "properly translated to right UI elements in the chat window" first-class criterion without violating the "Codex untouched" and "backendType parked" guardrails.
- With item 7 green + commit, mission now advances to auth (required before any real Grok usage or discovery picker). "Keep going" continues.
- Decision: Reuse/extend existing raw exec transport scaffolding + CodexLineTransport abstraction rather than new parallel AcpTransport (simpler, less code, already documented for this use).
- Decision: New `RemoteAcpCommand.kt` (separate from codex command file) for ACP launch command generation — clean separation, obvious naming.
- (Future) Backend type on ServerRecord or dedicated "Grok Agents" section in server list for UX.

**Current phase:** acp-remote-auth-handling COMPLETE (check-work subagent 019e74f7-bbeb-7910-be44-64b904aec621 VERDICT: PASS after 172s / 38 tool calls; fresh Gradle 8.13+JBR runs 8/8 JVM + Android credential/VM tests; iOS Scripts/verify-ios-build.sh BUILD SUCCEEDED; all guardrails held with git/grep proofs; explicit key → clean envPrefix wins, conditional ~/.grok/auth.json fallback only on null; both clients symmetric/minimal/no new UI; mission re-anchor subagent 019e74f7-f2f0 also green). Conventional commit next. "Keep going" active.

**Next item (per mission check + live trackers):** Re-invoke mission skill post-commit; smallest discrete follow-on per current NEXT.md/TODO (no invention; likely broader sketch commit closure or first production wiring step now that auth is solid). Guardrails to re-check on every subsequent chunk: Codex paths 100% untouched + ServerRecord/backendType still fully parked (no main-flow changes without re-triage).

**Critical learnings from auth chunk (item close):**
- Mandated builds (exact Gradle 8.13 + JBR + iOS verify) immediately surfaced 2 test failures from the initial dirty drop (brittle exact-equals + over-strict substring assert on the fallback shell text). Fixed in one cycle (conditional fallback only when no explicit key + robust assertContains + $ escape); all green on re-run. Lesson: never skip the "build after edit" gate even for "small" auth wiring.
- Taste win: making the remote fallback block conditional (if xaiApiKey == null) produces cleaner generated commands when the mobile credential store supplies a key (no unnecessary cat/python noise in the SSH exec line). Still defensive for the no-key case (remote dev machines with ~/.grok/auth.json). Aligns with "simple, obvious, hard-to-misuse".
- Credential surface was already 90% there (parallel to OpenAI key); adding XAI was 2-3 lines per impl + protocol + fakes. Zero new UI or provisioning flows (as required). Both platforms identical pattern.
- Guardrail enforcement worked: the launched check-work verifier did exhaustive git/grep/MD5 on protected Codex files + ServerRecord (0 leakage). Subagent confirmed "100% guardrail compliance".
- Mission skill + subagent reviews after the fix chunk + fresh builds + this closeout kept the long "keep going" execution aligned; no scope creep into parked items (rogue Codex, full discriminator, auth UI, etc.).
- With auth solid, real device `grok agent stdio` usage is now unblocked for the debug path (key from settings or remote fallback). This directly satisfies a core done criterion prerequisite before any broader discovery or production connect wiring.

All process followed (code→fix→build→subagent review→green→trackers+commit). Ready for next discrete chunk under "Keep going until all items are finished in the mission".
