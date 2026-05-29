# TODO — Live ACP/Grok Mission Execution Tracker (Mirrors NEXT.md Active Checklist)

**Mission:** Enable Mobidex to connect to and drive Grok agents (via ACP over `grok agent stdio`) using existing rich conversation UI + SSH, with raw line JSON-RPC transport. Codex path 100% untouched.

**Process (strict):** code (smallest chunk) → spawn_subagent (check-work or general review) → fix findings → build/test (Gradle 8.13 + JBR for JVM/Android; Scripts/verify-* for iOS) → re-review → update trackers (this file + MISSION.md/NEXT.md) → conventional commit → mark done. Use todo_write after every sub-chunk/review. Weave mission skill at transitions.

## Active Items (from NEXT.md + current FS state at ab0fda9 + dirty delta)

- [x] 1. Mission setup: MISSION.md + NEXT.md + initial todo_write. (done)
- [x] 2. RemoteAcpCommand + stdio generator + tests (KMP). (done — 2x review, 6/6 green)
- [x] 3. AcpProtocolCore (requests, classify, AcpContentChunk sealed + full toCodexSessionItem mapper to AgentMessage/Reasoning/ToolCall/Plan/AgentEvent etc.). 10/10 tests. Directly satisfies "Grok/ACP responses properly translated to right UI elements" via existing CodexSessionItem + ConversationSection (no UI changes). (done — 2x review, green)
- [x] 4. Android thin AcpGrokClient (over CodexLineTransport from openRawExec + RemoteAcpCommand; uses shared core + mapper for sessionItems: Flow<CodexSessionItem>). (done — smoke test also)
- [x] 5. iOS AcpClient parity (Swift; reuse existing openRawExec/SSHRawExecTransport + CodexLineTransport protocol; add minimal SharedKMPBridge surface for Acp* types/mapper/requests; thin client actor + focused smoke). **Next after item 10.** (iOS transport/docs already complete per inspection; main effort = bridge mirroring Codex pattern + client.) (done — AcpGrokClient.swift + bridge additions; full review: diffs+files read, Scripts/verify-ios-build.sh re-run → BUILD SUCCEEDED no ACP warnings, 5-chunk mapper verified vs KMP+CodexThreadItem+UI, guardrails (CodexAppServerProtocol.swift untouched exhaustive Codex classify, zero leakage/grep, transport files git-zero-diff), taste PASS (line-for-line pattern reuse, minimal, no excess/hidden modes). VERDICT: PASS. Ready for 7 wiring + conventional commit per mission.)
- [x] 6. Focused smoke (AcpGrokClientSmokeTest with Canned + real mapper producing 5 CodexSessionItem kinds). (done — 1/1 green)
- [x] 7. First minimal wiring + rich chat preview closure (both platforms). Debug ACP path + collectors + iOS DEBUG section in diagnostics + exact SharedKMPBridge projection to ConversationSection + isolated preview sheet. Subagent VERDICT PASS (zero findings; UI translation first-class + Codex untouched gates satisfied with proofs; builds green). Marked done. (2026-05-29)
- [x] 8. Build + test validation (shared jvmTest *Acp*, android *AcpGrok* + compile; use documented Gradle wrapper + Android Studio JBR). (done — multiple forced green runs)
- [x] 9. Full-sketch subagent review (check-work style: every file+delta, all builds/tests re-run, mapper/UI/guardrails/simplicity eval). (done — PASS, zero findings requiring fixes per prior)
- [ ] 10. Conventional commit of ACP sketch delta (feat(acp): add initial ACP/Grok stdio support sketch — RemoteAcpCommand + AcpProtocolCore mapper + Android AcpGrokClient + openRawExec parity on both platforms + smoke + trackers) + update MISSION/NEXT with status. **Current prep chunk.**

## Current Status Snapshot (post mission skill invocation + FS inspection)
- Git: detached ab0fda9 (last: feat(acp) AcpProtocolCore mapper commit); dirty with exactly the post-protocol client+transport delta (new AcpGrokClient.kt + SmokeTest.kt, SshService.kt extensions both platforms, test tweaks, tracker edits).
- All early done criteria met for sketch phase. UI translation via mapper exercised and proven in Android client/smoke (Grok thoughts → Reasoning collapsed, etc.).
- iOS: Full raw exec transport parity + docs already present (SSHRawExecTransport implements CodexLineTransport; openRawExec on SSHService). No ACP client or bridge yet. AppViewModel.swift 100% Codex-wired at connectSelectedServer ~1023.
- Android symmetric (AppViewModel.kt hard-wired; SshService has openRawExec implemented).
- No ServerRecord changes (backendType parked). No edits to any Codex launch/WS/proxy code.
- Builds: shared-core jvmTest Acp* 16/16 green historically; Android smoke green. iOS verify scripts available (Scripts/verify-ios-build.sh etc.).
- Guardrails: 100% (Codex untouched, no WS primary for ACP, simple, KMP for protocol/mapper, subagent after chunks, trackers updated).

## Next Immediate Chunk (per mission subagent rec + "keep going until finished")
- acp-remote-auth-handling (next after item 7): Extend acpStdioCommand + platform raw-exec launch sites to inject XAI_API_KEY env var when ServerRecord has auth configured (or credential store), with fallback SSH exec of `cat ~/.grok/auth.json` or equivalent lookup on the remote. Add minimal surface in both clients (no new UI yet). Follow full cycle: smallest code chunk → subagent → fix → exact Gradle/xcode builds → trackers → conventional commit. "Fix both clients". Keep Codex paths untouched. Park full picker/discovery until auth solid.
Prep + execute item 10: Small tracker polish (append this snapshot + iOS assessment learnings to NEXT/REVIEW_NOTES), launch check-work verifier subagent (focus: ACP sketch delta readiness for commit; re-run all *Acp* JVM tests under Gradle 8.13+JBR, Android smoke, iOS build via verify script, full diff review, mapper/UI fidelity, guardrails). If PASS: git commit (conventional message), mark 10 done, update trackers, then immediately pick item 5 (iOS client) as next smallest chunk.

## Parked (do not start)
All from NEXT.md: rogue Codex agents, full ServerRecord discriminator + picker, auth UI, x.ai extensions, rich approval/plan rendering, etc. Re-triage only after core items 5+7+10 closed.

## Process Reminders
- After every edit or sub-chunk: todo_write update + spawn review subagent.
- Before final response on any item: mission check (what criteria met, what remains, side quests).
- Use exact Gradle: `build/gradle-8.13/bin/gradle` with JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home for JVM/Android validation.
- iOS: prefer Scripts/verify-ios-build.sh or xcodebuild per project.yml/Mobidex.xcodeproj.

Update this file live after every discrete step. Mirror durable items to NEXT.md.