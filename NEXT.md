# NEXT.md — ACP for Grok + Parked Items (Mobidex)

This file holds the durable mission checklist and parked side quests. Mirror key items into the live `todo_write` tool for execution tracking. Update after each chunk.

## Mission Checklist (active)

- [ ] 1. Mission setup: MISSION.md + NEXT.md + initial todo_write list created. (done)
- [x] 2. Add `RemoteAcpCommand` (new shared file) with minimal stdio launch command generator for `grok agent stdio`. Support PATH bootstrap, optional grok binary path override, model flag. Add unit test skeleton. (done — 2x subagent review, all tests green, exec symmetry + quoting coverage added)
- [ ] 3. Define minimal ACP protocol types / request helpers in shared-core (AcpRpcRequests or similar, using existing JsonValue + codec patterns for KMP). Cover: initialize, session/new, session/prompt, basic session/update classification.
- [ ] 4. Implement thin AcpClient (or GrokAgentClient) on Android (Kotlin) using CodexLineTransport + new core. At minimum: initialize handshake + send a prompt, consume streaming notifications.
- [ ] 5. Port or create parallel minimal AcpClient on iOS (Swift) reusing the same line transport and (if possible) KMP bridge extensions. Ensure parity.
- [ ] 6. Add a focused smoke test or scripted harness that exercises openRawExec + AcpClient handshake against a mock transport (or local grok if available). Verify round-trip and chunk streaming.
- [ ] 7. First minimal wiring: expose a "connect as ACP/Grok" path in one ViewModel (e.g. a debug or new flow) so a real SSH + grok agent stdio can be driven from the app. Map basic agent_message_chunk to existing message rendering if feasible without big UI changes.
- [ ] 8. Build + test validation on shared + at least one platform (use repo gradle or Android Studio JBR as per AGENTS.md). Fix any issues.
- [ ] 9. Subagent review of the full sketch delta (using check-work or general reviewer). Address findings.
- [ ] 10. Conventional commit (feat(acp): add initial ACP/Grok stdio support sketch...) + update MISSION/NEXT with status.

## Parked / Non-blocking Side Quests (do not start mid-mission without re-triage)

- Rogue codex agents / unconditional launch fix in RemoteCodexAppServerCommand.kt (explicitly "keep in our back pocket").
- Full ServerRecord discriminator (backend: codex vs acp/grok) + persistence + UI picker for connection type.
- Rich mapping of all ACP chunk types (thoughts, tool_call, plan, x.ai/fs/*, approvals) into the conversation UI components.
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
- Android `openRawExec` public surface still missing (private SshjRawExecTransport only) — surfaced as integration blocker for AcpClient wiring (iOS already has the full API).

Update this file when mission or guardrails change. Keep entries terse.
