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
- [x] 10. Conventional commit of ACP sketch delta (feat(acp): add initial ACP/Grok stdio support sketch — RemoteAcpCommand + AcpProtocolCore mapper + Android AcpGrokClient + openRawExec parity on both platforms + smoke + trackers) landed as 86d76f3 (per git log). Trackers updated post-commit. (done)

## Current Status Snapshot (post auth close at 2dfc3fb + full "Keep going" execution)
- Git: detached (post auth simplification). Key prior: 2dfc3fb (added then removed XAI injection per user: "if the ssh server is already authenticated, why does the mobile app need to handle auth? this is what we do with codex"). The removal commit enforces Codex parity (SSH credential only; remote process uses its own ~/.grok/* or env). Earlier: 5fbd0c3 (item 7), 86d76f3 (sketch).
- All core sketch items 1-10 + auth handling COMPLETE (multiple check-work PASS verdicts, all mandated Gradle 8.13+JBR + iOS verify builds green, guardrails 100% held across chunks).
- UI translation first-class criterion satisfied (mapper produces real CodexSessionItem kinds rendered by existing ConversationSection; proven in debug preview on both platforms; zero UI or Codex path changes).
- Auth simplification landed (fix): mobile XAI key injection + remote auth.json fallback removed on both clients. Now matches Codex exactly — SSH auth to the server is the trust boundary; the remote `grok` (or `codex`) binary uses the logged-in user's environment. Subagent PASS + exact Gradle 8.13+JBR + iOS verify all green on isolated delta. Conventional commit ready.
- Guardrails still held: Codex launch/WS/RemoteCodex* 100% untouched (exhaustive proofs in every review); ServerRecord discriminator/backendType + main production flows + picker still parked (no changes in any chunk); raw stdio only; simple interfaces; "fix both clients".
- Next: per mission re-anchor + live checklist, reconcile any remaining stale text, re-invoke mission skill, then advance the smallest unparked item that progresses end-to-end ACP/Grok support (e.g. production wiring investigation or next smoke/end-to-end under the parked rules).
- Builds: always use exact `build/gradle-8.13/bin/gradle` + JBR / Scripts/verify-ios-build.sh.
- Process: After every sub-chunk: todo_write + spawn_subagent (check-work with full mission + both-clients + Codex-untouched + UI gates) → fix → exact builds → re-review → mark → conventional commit. "Keep going until all items are finished in the mission."

## Active Chunk
- acp-production-wiring (post user "Yes" + mission re-anchor): IN PROGRESS.
  - [x] Discriminator polish (BackendType + field + iOS decodeIfPresent/default init + editor/smoke sites + Android import; 100+ tests untouched via defaults; legacy JSON compat; iOS verify + Gradle 8.13+JBR green; dedicated check-work 019e7517-fae2 VERDICT: PASS). Learnings logged in MISSION.md.
  - [ ] Android real connect/send/approval/close branching (promote AcpGrokClient + collector to main UI state when .acpGrok; reuse mapper/auth/raw-exec; zero Codex changes).
  - [ ] iOS symmetric VM branching.
  - [ ] Full wiring subagent reviews (2+ with UI gate + Codex proofs) + builds.
  - [ ] Trackers + conventional commit at chunk close.
  "Keep going" — full process on every sub-chunk.

## Parked (do not start)
All from NEXT.md: rogue Codex agents, full ServerRecord discriminator + picker, auth UI, x.ai extensions, rich approval/plan rendering, etc. Re-triage only after core items 5+7+10 closed.

## Process Reminders
- After every edit or sub-chunk: todo_write update + spawn review subagent.
- Before final response on any item: mission check (what criteria met, what remains, side quests).
- Use exact Gradle: `build/gradle-8.13/bin/gradle` with JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home for JVM/Android validation.
- iOS: prefer Scripts/verify-ios-build.sh or xcodebuild per project.yml/Mobidex.xcodeproj.

Update this file live after every discrete step. Mirror durable items to NEXT.md.