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
- Auth: SSH authentication (the per-ServerRecord credential) is the *only* mobile-side concern. Once logged in as the target unix user, the launched agent (`grok agent stdio` or `codex app-server`) inherits the remote environment/home exactly as Codex has always done. No XAI_API_KEY injection or remote auth.json parsing from the phone. (Inconsistent mobile auth handling added during sketch was removed after explicit user feedback; hard break, both clients fixed.)
- After each discrete chunk or todo item completion: launch subagent review, fix findings, run focused tests/build validation, then mark done.
- Park non-blocking side quests (e.g. full UI branching, ServerRecord discriminator, x.ai/* extensions, rich plan/tool rendering) in NEXT.md.

**Critical decisions logged (item 7 close + handoff):**
- xcodegen + explicit git add of new .swift files remains load-bearing for iOS ACP work (pbxproj snapshot drift is the recurring integration tax; always verify after adding platform client files).
- The isolated DEBUG preview + exact shared projection was the minimal way to satisfy the "properly translated to right UI elements in the chat window" first-class criterion without violating the "Codex untouched" and "backendType parked" guardrails.
- With item 7 green + commit, mission now advances to auth (required before any real Grok usage or discovery picker). "Keep going" continues.
- Decision: Reuse/extend existing raw exec transport scaffolding + CodexLineTransport abstraction rather than new parallel AcpTransport (simpler, less code, already documented for this use).
- Decision: New `RemoteAcpCommand.kt` (separate from codex command file) for ACP launch command generation — clean separation, obvious naming.
- (Future) Backend type on ServerRecord or dedicated "Grok Agents" section in server list for UX.

**Current phase:** acp-production-wiring — Android real connect/send/approval branching sub-chunk IN PROGRESS (user request: "The real connectSelectedServer / send / approval paths don't yet look at backendType... The last step (making a server record with backendType = acpGrok just work in the normal conversation UI) is in progress right now."). Holders + comments + iOS prod helper pre-added in prior discriminator polish. Current sub-chunk: add Android startAcpProductionSessionForCurrentProject + acpItems/sessionId holders + collector that calls CodexSessionProjection.sections into main conversationSections state; insert *minimal* early if (backendType == AcpGrok) { start...; return } guards in connect/send/respond/disconnect (Codex blocks byte-for-byte untouched, no indentation of existing logic); basic ACP send uses client.sendPrompt + local user item append for echo in chat. Then build + check-work (exact UI-gate + "Codex untouched" git proofs) + iOS symmetric call-site wiring. Guardrails: UI translation via proven mapper (no new views), SSH-only auth (no injection), fix both clients, no parked items.

**Mission re-anchor (post-auth at 2dfc3fb):** One-sentence mission unchanged. Completion for this phase: (a) BackendType discriminator safe for persistence + all constructions; (b) real (non-debug) branching in connectSelectedServer / sendInputItems / approval / close paths on Android + iOS so a ServerRecord with .acpGrok drives the primary conversation state via existing mapper → ConversationSection (identical rich elements: Reasoning, AgentMessage, ToolCall, Plan, interactive AgentEvent); (c) no changes whatsoever to any Codex/WS/RemoteCodex*/appServer/event paths (byte-for-byte + git proofs in every review); (d) all mandated builds (Gradle 8.13+JBR JVM/Android tests; iOS verify) + 2+ check-work subagents (full gates) green; (e) trackers + conventional commit. Guardrails: hard break on parked items (rogue Codex, full picker, auth UI); simple obvious interfaces; KMP where it avoids dupe.

**Critical learnings from auth chunk (item close):**
- Mandated builds (exact Gradle 8.13 + JBR + iOS verify) immediately surfaced 2 test failures from the initial dirty drop (brittle exact-equals + over-strict substring assert on the fallback shell text). Fixed in one cycle (conditional fallback only when no explicit key + robust assertContains + $ escape); all green on re-run. Lesson: never skip the "build after edit" gate even for "small" auth wiring.
- Taste win: making the remote fallback block conditional (if xaiApiKey == null) produces cleaner generated commands when the mobile credential store supplies a key (no unnecessary cat/python noise in the SSH exec line). Still defensive for the no-key case (remote dev machines with ~/.grok/auth.json). Aligns with "simple, obvious, hard-to-misuse".
- Credential surface was already 90% there (parallel to OpenAI key); adding XAI was 2-3 lines per impl + protocol + fakes. Zero new UI or provisioning flows (as required). Both platforms identical pattern.
- Guardrail enforcement worked: the launched check-work verifier did exhaustive git/grep/MD5 on protected Codex files + ServerRecord (0 leakage). Subagent confirmed "100% guardrail compliance".
- Mission skill + subagent reviews after the fix chunk + fresh builds + this closeout kept the long "keep going" execution aligned; no scope creep into parked items (rogue Codex, full discriminator, auth UI, etc.).
- With auth solid, real device `grok agent stdio` usage is now unblocked for the debug path (key from settings or remote fallback). This directly satisfies a core done criterion prerequisite before any broader discovery or production connect wiring.

**Critical learnings from production-wiring chunk start (discriminator polish sub-chunk, check-work 019e7517-fae2-7700-a047-0a5fb751f7da VERDICT: PASS):**
- decodeIfPresent + trailing default in designated init is the minimal, robust pattern for adding a new Codable field to persisted ServerRecord (exactly mirrors prior executionPath/authMethod handling; old JSON from UserDefaults/JSON repo + Android prefs now roundtrips without crash or migration code).
- 100+ test sites + existing legacy test payloads exercised the compat automatically — no edits needed thanks to default param (taste win; labeled-arg call sites in editors/smoke were the only required updates).
- Fresh mandated builds (iOS verify script + Gradle 8.13+JBR) + subagent caught the one Android import miss immediately (fixed in <1m); re-ran green. Lesson reinforced: never declare a chunk done without the exact build + check-work gate.
- Guardrails held perfectly in first wiring sub-chunk (exhaustive grep in verifier: 0 Codex leakage; field only in models + editors + docs/comments; default always Codex preserves 100% prior behavior until explicit .acpGrok records are created/selected).
- Explicit user approval + MISSION re-anchor + todo_write + mission skill weave at transition kept execution on the narrow approved path (no picker, no UI for type, no rogue Codex, no over-engineering).
- Sub-chunk complete with full process; ready for the core value: real VM branching that makes ACP drive the *main* rich chat (mapper already proven in debug preview).

All process followed (code→fix→build→subagent review→green→trackers+commit). Ready for next discrete chunk (Android prod wiring) under "Keep going until all items are finished in the mission".

**Critical learnings from production-wiring final chunk (both-clients backendType branching, check-work 019e754c... + 019e7551... VERDICT: PASS on Android then full):**
- Early `if (backendType == .AcpGrok) { ...; return }` (or equivalent) is the minimal, tasteful way to wire the discriminator into main paths while guaranteeing Codex blocks remain byte-for-byte identical (git diff + grep/MD5 proofs in both verifiers).
- Collector + projection (CodexSessionProjection.sections on Android; SharedKMPBridge + publish on iOS) into the *main* conversationSections state is exactly what makes "acpGrok ServerRecord just work in normal chat UI" with zero UI or mapper changes — directly satisfies the repeated "properly translated to right UI elements in the chat window" gate via the existing AcpProtocolCore mapper (5 kinds: Reasoning/AgentMessage/ToolCall/Plan/AgentEvent).
- Both clients now fully symmetric for prod wiring (holders + acpSessionId + start helper + 4 guarded paths + cleanups + SSH-parity comments); "fix both clients" + AGENTS.md rule enforced. iOS verify + Gradle 8.13+JBR green on final delta.
- Minor observation (fixed pre-final review): explicit Connected transition for ACP connect path (parity with Codex); non-blocking for UI/translation but caught by subagent.
- Guardrails held 100% (0 Codex leakage in any hunk across platforms; auth model clean post-prior removal; no parked items started; simple interfaces).
- Mission skill + todo_write + 2x full check-work (UI-gate sentence + untouched proofs) + exact builds after every sub-chunk kept the "keep going" execution aligned to the user's explicit final request.
- With this, the last step is complete: a ServerRecord with backendType=acpGrok drives Grok agents in the normal conversation UI (debug methods no longer the only path). All done criteria for the phase satisfied. Ready for conventional commit + (if desired) on-device validation.
