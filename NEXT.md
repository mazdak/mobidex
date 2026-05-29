# NEXT.md — ACP for Grok + Parked Items (Mobidex)

This file holds the durable mission checklist and parked side quests. Mirror key items into the live `todo_write` tool for execution tracking. Update after each chunk.

## Mission Checklist (active)

- [ ] 1. Mission setup: MISSION.md + NEXT.md + initial todo_write list created. (done)
- [x] 2. Add `RemoteAcpCommand` (new shared file) with minimal stdio launch command generator for `grok agent stdio`. Support PATH bootstrap, optional grok binary path override, model flag. Add unit test skeleton. (done — 2x subagent review, all tests green, exec symmetry + quoting coverage added)
- [x] 3. Define minimal ACP protocol types / request helpers in shared-core (AcpRpcRequests or similar, using existing JsonValue + codec patterns for KMP). Cover: initialize, session/new, session/prompt, basic session/update classification + the chunk kinds needed for UI (message, thought/reasoning, tool_call, plan, approval requests). Include initial AcpChunkToSessionItem mapper sketch that produces CodexSessionItem instances (AgentMessage, Reasoning, Plan, ToolCall...) so existing UI projection + chat window "just work". (done — 2x subagent review, 10/10 tests green, KMP-safe, directly addresses user's "properly translated to right UI elements" request via existing CodexSessionItem + ConversationSection rendering)
- [x] 4. Implement thin AcpClient (or GrokAgentClient) on Android (Kotlin) using CodexLineTransport + new core. At minimum: initialize handshake + send a prompt, consume streaming notifications. (done — AcpGrokClient.kt thin client over CodexLineTransport; uses shared AcpRpcRequests + classify + toCodexSessionItems mapper; full initialize/createSession/prompt/interrupt/close + sessionItems Flow of mapped items.)
- [ ] 5. Port or create parallel minimal AcpClient on iOS (Swift) reusing the same line transport and (if possible) KMP bridge extensions. Ensure parity.
- [x] 6. Add a focused smoke test or scripted harness that exercises openRawExec + AcpClient handshake against a mock transport (or local grok if available). Verify round-trip and chunk streaming. (done — AcpGrokClientSmokeTest.kt + internal CannedLinesTransport pre-pump; exercises real shared mapper producing 5 CodexSessionItem subtypes (Reasoning/AgentMessage/ToolCall/Plan/AgentEvent) on client.sessionItems Flow for UI; 1/1 test green under Gradle+JBR; intentionally minimal, no real transport/SSH; ID correlation relaxed only in mock per scope. Verification review: PASS, no findings. See detailed report in session + REVIEW_NOTES.md entry.)
- [ ] 7. First minimal wiring: expose a "connect as ACP/Grok" path in one ViewModel (e.g. a debug or new flow) so a real SSH + grok agent stdio can be driven from the app. Map basic agent_message_chunk to existing message rendering if feasible without big UI changes.
- [x] 8. Build + test validation on shared + at least one platform (use repo gradle or Android Studio JBR as per AGENTS.md). Fix any issues. (done — multiple forced runs under Gradle 8.13 + Android JBR: :shared-core:jvmTest "*Acp*" (16/16 green), :android-app:compile* + :android-app:test* *AcpGrok* and *NewSession* (all green, 1+4 tests); reports at shared-core/build/test-results/jvmTest/TEST-*Acp*.xml + android-app/build/test-results/testDebugUnitTest/TEST-*AcpGrok*.xml)
- [x] 9. Subagent review of the full sketch delta (using check-work or general reviewer). Address findings. (done — this full Phase A+B review per mandate: read every file+diff, re-ran all builds/tests, mapper/UI translation re-verified end-to-end, guardrails/simplicity/KMP/no-excess eval. See new detailed entry in REVIEW_NOTES.md. Zero blocking findings. VERDICT: PASS)
- [ ] 10. Conventional commit (feat(acp): add initial ACP/Grok stdio support sketch...) + update MISSION/NEXT with status.

## Parked / Non-blocking Side Quests (do not start mid-mission without re-triage)

- Rogue codex agents / unconditional launch fix in RemoteCodexAppServerCommand.kt (explicitly "keep in our back pocket").
- Full ServerRecord discriminator (backend: codex vs acp/grok) + persistence + UI picker for connection type.
- (Completed as part of chunk 3) Rich mapping of all ACP chunk types (thoughts, tool_call, plan, x.ai/fs/*, approvals) into the conversation UI components via CodexSessionItem + existing projection (user explicitly called this out; mapper in AcpProtocolCore.kt produces the exact renderable items).
- Permission/approval flow for ACP interactive requests.
- Auth provisioning UI (paste XAI key or "use remote grok auth").
- Workspace/project discovery via ACP x.ai extensions vs current Codex discovery.
- Supporting `grok agent serve` (HTTP/WS) as an alternative transport option.
- Renaming CodexLineTransport → neutral name (e.g. LineJsonTransport) once ACP is primary.
- End-to-end TestFlight-able flow + docs.
- Any performance / streaming backpressure work for long agent runs.

## Recent Critical Learnings

- Raw stdio line transport scaffolding (`openRawExec`, SSHRawExecTransport, SshjRawExecTransport) + CodexLineTransport reuse is already in place from prior sketch work. Excellent — means we start the client layer on a solid, tested pipe.
- Both platforms already document the raw path as "preferred for grok agent stdio (ACP)".
- Existing CodexRpc* machinery (shared JsonValue, CodexRpcClientCore, platform clients) provides a strong pattern to copy/adapt for ACP without pulling in kotlinx.serialization into shared-core.
- WebSocket is confirmed NOT used for the new ACP path (correct per earlier clarification).
- Chunk 2 complete (RemoteAcpCommand + tests): clean separation from codex launch logic, correct `grok agent stdio --model ...` shape for raw CodexLineTransport, all quoting parity with codex tests, `exec ` symmetry added, 6/6 tests green after subagent review + fix cycle. Learnings: deliberate duplication of quoting helpers was the right call for v1 guardrail isolation; extraArgs quoting must be asserted exactly (single-quoted tokens); explicit `exec ` improves stdio handoff semantics.
- Android `openRawExec` public surface was missing (private SshjRawExecTransport only) — now resolved in this chunk by adding to MobidexSshService interface + implementation (exact parity with iOS openRawExec). This unblocks all Android ACP client work.
- Chunk 3 complete (AcpProtocolCore + mapper): ... (see prior).
- Chunk 4 + 4a complete (3x subagent review cycle ending PASS): ...
- Chunk 6 complete (this session): New AcpGrokClientSmokeTest.kt — focused Android unit test with CannedLinesTransport (pre-pumps ACP JSON lines for initialize result + session/new + 5 different session/update kinds). Instantiates AcpGrokClient, drives initialize, asserts that the Flow<CodexSessionItem> contains Reasoning (thought), AgentMessage, ToolCall, Plan, and AgentEvent (approval) with correct content from the mapper. Compiles and passes cleanly. Proves the entire "raw line → classification → toCodexSessionItem → existing UI model" path with zero real SSH/grok. Item 8 (build/test) updated live as all targets stay green.
- Chunk 6 verification review (per code→review→test workflow + check-work): Full scope review executed (read test+diff+AcpGrokClient+mapper+CodexSessionItem; forced Gradle 8.13 + JBR compile+test runs; own assertions on 5 item kinds + real mapper usage + guardrails). Result: PASS with zero findings/blockers. Test file: android-app/src/test/java/mobidex/android/service/AcpGrokClientSmokeTest.kt (self-contained Canned + pump relaxation only). Builds/tests green (see XML/HTML reports). No prod changes, no Codex/WS/launch touches. Checklist item 6 marked done. (Conventional: test(acp): add focused AcpGrokClientSmokeTest + CannedLinesTransport harness). Ready for next (item 4/5/7 wiring or full item 9 subagent).

Update this file when mission or guardrails change. Keep entries terse.
