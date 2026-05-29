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

## Current Status Snapshot (post "Keep going" + item 7 close at 5fbd0c3 + mission re-align)
- Git: detached at 5fbd0c3 (feat(acp): close item 7 minimal debug wiring with rich chat preview on both platforms (UI translation first-class + Codex untouched)); dirty exactly with start of acp-remote-auth-handling (RemoteAcpCommand + test now accept/pass xaiApiKey for XAI_API_KEY= prefix injection; see diff).
- Item 7 (minimal debug wiring + rich chat preview closure on both + mapper exercised for "properly translated to right UI elements") COMPLETE + subagent PASS + conventional commit landed. UI translation first-class criterion satisfied (Grok chunks → existing ConversationSection via shared mapper, zero UI or Codex path changes).
- All guardrails held: Codex launch/WS/RemoteCodexAppServerCommand 100% untouched (MD5/grep proofs in prior reviews); no ServerRecord discriminator/backendType (parked); raw stdio only; simple interfaces.
- Next discrete item per MISSION.md handoff + TODO: **acp-remote-auth-handling** (complete the XAI key injection: credential store surface on both + wiring of loadXAI... into the two startAcpDebug* call sites + minimal remote ~/.grok/auth.json fallback via SSH exec when no local key; "fix both clients"; no new UI; then trackers + conventional commit).
- Builds remain green from item 7 close (shared jvmTest *Acp*, android *AcpGrok*, iOS verify). Use exact Gradle 8.13 + JBR / Scripts/verify-ios-build.sh going forward.
- Process: After every sub-chunk: todo_write + spawn_subagent (check-work with mission context + both-clients + Codex-untouched + UI-translation gates) → fix → exact builds → re-review → mark → conventional commit.

## Active Chunk
- acp-remote-auth-handling: COMPLETE (check-work VERDICT: PASS 019e74f7-bbeb-7910-be44-64b904aec621; JVM 8/8 + Android tests + iOS verify BUILD SUCCEEDED after conditional fallback fix + test robustness; guardrails 100% (git/grep proofs, 0 Codex/ServerRecord touches); mission re-anchor also PASS. Ready for conventional commit + next item selection per mission check).

## Parked (do not start)
All from NEXT.md: rogue Codex agents, full ServerRecord discriminator + picker, auth UI, x.ai extensions, rich approval/plan rendering, etc. Re-triage only after core items 5+7+10 closed.

## Process Reminders
- After every edit or sub-chunk: todo_write update + spawn review subagent.
- Before final response on any item: mission check (what criteria met, what remains, side quests).
- Use exact Gradle: `build/gradle-8.13/bin/gradle` with JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home for JVM/Android validation.
- iOS: prefer Scripts/verify-ios-build.sh or xcodebuild per project.yml/Mobidex.xcodeproj.

Update this file live after every discrete step. Mirror durable items to NEXT.md.