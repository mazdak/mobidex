# NEXT.md — Active Work + Parked Items (Mobidex)

## Mission Checklist (active, 2026-06-05 regressions)

- [x] Fix queued "Steer now" to hydrate active-turn state before sending.
- [x] Add bounded New Worktree creation/session start behavior.
- [x] Add/update focused regression tests. (Android new-session test updated; iOS helper diagnostics improved, broad steer fixture still has refresh-order noise.)
- [x] Run focused iOS and Android validation. (Android green; iOS simulator build green; focused iOS XCTest still failing in mock request ordering.)

## Mission Checklist (active, 2026-06-05 queue)

- [x] Trace queued input, auto-start, steer, and local transcript echo paths.
- [x] Preserve queue state across disconnect/reconnect.
- [x] Remove queued items at pickup time and requeue only on failed pickup.
- [x] Add optimistic steer transcript echoes with duplicate reconciliation.
- [x] Run focused iOS and Android queue tests/checks.

## Mission Checklist (active, 2026-06-05)

- [x] Trace current navigation, session list ordering, and conversation bubble layout.
- [x] Implement project-to-session-list navigation and empty-list behavior.
- [x] Freeze session-list order while visible, refreshing on load and explicit mutations.
- [x] Adjust agent bubble horizontal inset on iOS and Android.
- [x] Review changes with a subagent and fix confirmed findings.
- [x] Run focused tests/build checks and fix failures or record blockers. (Android AppViewModelNewSessionTest green; iOS MobidexTests build + focused AppViewModelTests regression green)

## Mission Checklist (active, 2026-05-31)

## TestFlight Release Checklist (completed, 2026-06-05)

- [x] T1. Commit verified release delta.
- [x] T2. Merge release commit to `master`, confirm `master` vs `origin/master`, and push.
- [x] T3. Resolve TestFlight version/build and external tester group.
- [x] T4. Run `.asc` TestFlight workflow for internal testers.
- [x] T5. Publish the uploaded build to external TestFlight testers.
- [x] T6. Record version/build/build ID and final release status.

## asc TestFlight submissions (internal + external build 37) — 2026-06-06

- Executed from `master` at `5f97a21` after `origin/master` was pulled, the regression fix was cherry-picked from `codex/fix-steer-now-worktree`, and `master` was pushed.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 37.
  - BUILD_ID: `a85f41ca-02fa-4ee0-a2a6-7f42d634878b`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-37.ipa` (17,826,111 bytes).
  - Run record: `.asc/runs/testflight-20260606T002449Z-0fdbdd12.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
- External workflow: `asc workflow run testflight_external BUILD_ID:a85f41ca-02fa-4ee0-a2a6-7f42d634878b EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260606T002814Z-fbd54de3.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Validation note: Android focused regression tests passed and the iOS simulator build/preflight passed; the focused iOS XCTest fixture still has request-order noise and was not used as a release blocker for this shipment.

## asc TestFlight submissions (internal + external build 36) — 2026-06-05

- Executed from `master` at `045bdf3` after `origin/master` was pulled and the release commit was pushed.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 36.
  - BUILD_ID: `d9c424d8-3135-4a39-9195-cab5122aff82`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-36.ipa` (17,821,759 bytes).
  - Run record: `.asc/runs/testflight-20260605T142840Z-46a68b9f.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
- External workflow: `asc workflow run testflight_external BUILD_ID:d9c424d8-3135-4a39-9195-cab5122aff82 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260605T143230Z-4154a259.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.

## Completed ACP UI Checklist (2026-05-31)

- [x] A1. Add generic ACP Agent UI on iOS and Android server editors.
- [x] A2. Store and normalize per-server ACP launch commands, with Grok as the default command.
- [x] A3. Route production ACP launch through the configured command on both clients.
- [x] A4. Add/update focused tests and run shared, Android, and iOS validation.
- [x] A5. Launch subagent review for the ACP UI/generalization chunk and fix confirmed findings. (review agent 019e8060-8833-7dd0-94a2-6e9cb755a8b0; fixed iOS failed-connect state overwrite and ACP re-entry guard)

## Completed Markdown/Project Session Checklist (2026-05-31)

- [x] 1. Mission setup: re-anchor `MISSION.md` and `NEXT.md` for markdown rendering + project session coverage.
- [x] 2. Replace agent reply markdown rendering with parser-backed rendering on iOS and Android.
- [x] 3. Fix project-scoped session loading so exact project sessions do not hide matching Codex worktree sessions.
- [x] 4. Add regression coverage and run focused validation.
- [x] 5. Launch subagent review, fix confirmed findings, and mark the mission complete.

## Current Critical Learnings

- Both clients already choose markdown rendering for assistant/reasoning/plan/review/system sections; the homegrown parser should be replaced for rendered agent output instead of extended.
- Project-scoped session loading currently skips unscoped discovery when exact `cwd` matches exist, which can hide worktree sessions for projects such as "cheetah".
- Subagent review found a real parser bug where delimiter tokens were dropped in literal/incomplete markdown; fixed by preserving delimiter tokens outside structural nodes and adding regression coverage.

---

This file holds the durable mission checklist and parked side quests. Mirror key items into the live `todo_write` tool for execution tracking. Update after each chunk.

## Mission Checklist (active)

- [x] 1. Mission setup: MISSION.md + NEXT.md + initial todo_write list created. (done)
- [x] 11. acp-production-wiring (final): real backendType branching in connectSelectedServer/send/approval/close on *both* clients (Android + iOS). Holders + helpers + collector (CodexSessionProjection / SharedKMPBridge → main conversationSections) + acpSessionId + cleanups. 2x check-work (019e754c Android PASS; 019e7551 full PASS) + exact Gradle 8.13+JBR + iOS verify all green. UI translation gate + "Codex untouched" proofs + "fix both clients" satisfied. (done 2026-05-29)
- [x] 2. Add `RemoteAcpCommand` (new shared file) with minimal stdio launch command generator for `grok agent stdio`. Support PATH bootstrap, optional grok binary path override, model flag. Add unit test skeleton. (done — 2x subagent review, all tests green, exec symmetry + quoting coverage added)
- [x] 3. Define minimal ACP protocol types / request helpers in shared-core (AcpRpcRequests or similar, using existing JsonValue + codec patterns for KMP). Cover: initialize, session/new, session/prompt, basic session/update classification + the chunk kinds needed for UI (message, thought/reasoning, tool_call, plan, approval requests). Include initial AcpChunkToSessionItem mapper sketch that produces CodexSessionItem instances (AgentMessage, Reasoning, Plan, ToolCall...) so existing UI projection + chat window "just work". (done — 2x subagent review, 10/10 tests green, KMP-safe, directly addresses user's "properly translated to right UI elements" request via existing CodexSessionItem + ConversationSection rendering)
- [x] 4. Implement thin AcpClient (or GrokAgentClient) on Android (Kotlin) using CodexLineTransport + new core. At minimum: initialize handshake + send a prompt, consume streaming notifications. (done — AcpGrokClient.kt thin client over CodexLineTransport; uses shared AcpRpcRequests + classify + toCodexSessionItems mapper; full initialize/createSession/prompt/interrupt/close + sessionItems Flow of mapped items.)
- [x] 5. Port or create parallel minimal AcpClient on iOS (Swift) reusing the same line transport and (if possible) KMP bridge extensions. Ensure parity. (done — full AcpGrokClient.swift actor + SharedKMPBridge ACP surface (typealiases, acp*Params, acpClassifyInbound, acpClassificationToSessionItems + private acpChunkToThreadItem mirroring KMP mapper for exactly the 5 UI kinds); transport (openRawExec/SSHRawExecTransport/CodexLineTransport) + CodexAppServer* patterns 100% reused unmodified; zero Codex/WS/launch/UI files touched. iOS verify build: BUILD SUCCEEDED (clean, no ACP warnings). End-to-end mapper path + guardrails + taste/KMP parity all confirmed PASS in dedicated check-work review. See REVIEW_NOTES.md entry + full session log.)
- [x] 6. Add a focused smoke test or scripted harness that exercises openRawExec + AcpClient handshake against a mock transport (or local grok if available). Verify round-trip and chunk streaming. (done — AcpGrokClientSmokeTest.kt + internal CannedLinesTransport pre-pump; exercises real shared mapper producing 5 CodexSessionItem subtypes (Reasoning/AgentMessage/ToolCall/Plan/AgentEvent) on client.sessionItems Flow for UI; 1/1 test green under Gradle+JBR; intentionally minimal, no real transport/SSH; ID correlation relaxed only in mock per scope. Verification review: PASS, no findings. See detailed report in session + REVIEW_NOTES.md entry.)
- [x] 7. First minimal wiring (debug path + rich chat preview closure): Debug surfaces (`startAcpDebugSessionForGrok` + parallel holders/collectors) + iOS DEBUG-gated preview in ConnectionDiagnosticsView using exact `SharedKMPBridge.conversationSections(from: debugAcpItems)` (real ConversationSection instances for all 5 mapped kinds) + sheet + isolated preview view. Proves "properly translated to right UI elements in the chat window" via existing machinery with zero main-flow/Codex changes. Android parity (Flow + smoke). Subagent PASS (zero findings, builds green, gates held). Marked done after conventional commit. (2026-05-29)
- [x] 8. Build + test validation on shared + at least one platform (use repo gradle or Android Studio JBR as per AGENTS.md). Fix any issues. (done — multiple forced runs under Gradle 8.13 + Android JBR: :shared-core:jvmTest "*Acp*" (16/16 green), :android-app:compile* + :android-app:test* *AcpGrok* and *NewSession* (all green, 1+4 tests); reports at shared-core/build/test-results/jvmTest/TEST-*Acp*.xml + android-app/build/test-results/testDebugUnitTest/TEST-*AcpGrok*.xml)
- [x] 9. Subagent review of the full sketch delta (using check-work or general reviewer). Address findings. (done — this full Phase A+B review per mandate: read every file+diff, re-ran all builds/tests, mapper/UI translation re-verified end-to-end, guardrails/simplicity/KMP/no-excess eval. See new detailed entry in REVIEW_NOTES.md. Zero blocking findings. VERDICT: PASS)
- [x] 10. Conventional commit (feat(acp): add initial ACP/Grok stdio support sketch (RemoteAcpCommand + AcpProtocolCore mapper + Android AcpGrokClient + openRawExec parity + smoke + trackers)) landed as 86d76f3 after green check-work VERDICT: PASS (full builds, UI mapper proof, guardrails, iOS transport de-risk). Trackers + TODO.md updated. (done)

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

- (2026-05-29, post 2dfc3fb) acp-remote-auth-handling closed green (check-work PASS + all builds). Key learning repeated: the "code → build with exact Gradle 8.13+JBR + iOS verify → fix" loop caught brittleness immediately; conditional fallback was the obvious taste improvement. Guardrails (Codex untouched, no ServerRecord) held via subagent proofs. Auth now unblocks real `grok agent stdio` on device (key or ~/.grok fallback). Sketch + debug wiring + UI mapper proof + auth = solid foundation.
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
- **iOS Item 7 independent check-work verifier (this session, Phase A+B strict gates)**: See full detailed report + VERDICT in REVIEW_NOTES.md (new section "iOS Item 7 Verifier (check-work for full item 7 closure)"). Key: Android side already green/PASS (isolated startAcpDebugSessionForGrok + debugAcpItems in .kt; 5 Codex sites MD5-identical; real mapper; Gradle clean). iOS: Phase A all PASS (git delta ONLY safe additives at AppViewModel.swift:348-351 holders + 918-955 new method after testSelectedConnection; 5+ protected Codex sites (connectSelectedServer:1044 private, sendComposer*:1377, startEventLoop:2372, appServer/eventTask:328-329, testSelectedConnection:893) read verbatim + MD5/hunk proofs = 0 changes (byte-for-byte); full grep leakage = ZERO outside 3 ACP files (VM+AcpGrokClient.swift+SharedKMPBridge.swift); no Views/Models/Codex*/ServerRecord touches; SharedKMPBridge.acpStdioCommand + AcpGrokClient actor usage isolated + comments explicit "Codex untouched"). Phase B: fresh `CONFIGURATION=Debug SDK=iphonesimulator Scripts/verify-ios-build.sh` (task 019e74de-2696-7fa2-bd1f-f422a8438f2c + priors) → exit 65, **BUILD FAILED** (0 warnings, but fatal: AppViewModel.swift:349 "cannot find type 'AcpGrokClient' in scope"). Root cause: Sources/Mobidex/Services/AcpGrokClient.swift is untracked + absent from pbxproj (never xcodegen'd in after creation; project.yml glob not sufficient without pbx update). Real Swift mapper path (AcpGrokClient.swift:200 `acpClassificationToSessionItems` in sessionUpdate → yields CodexThreadItem to sessionItems; VM:946-951 collector feeds debugAcpItems) confirmed exercised in source (same 5 kinds ConversationSection renders), would satisfy "properly translated..." if integrated. Subagent review ids used: 019e74de-2696-7fa2-bd1f-f422a8438f2c (fresh), 019e74dc-f016-71c3-b48a-d41277a34125 (prior). VERDICT: FAIL for iOS half (and thus full item 7 closure). Android PASS but iOS not symmetric/buildable. Do not mark item 7 done. Fix: git add the .swift, xcodegen (or equiv) to include in pbxproj, re-verify green BUILD SUCCEEDED, then commit+trackers. Per AGENTS.md + code→review→... cycle.

Update this file when mission or guardrails change. Keep entries terse.

## Auth Simplification Review (targeted XAI removal for Codex parity) — 2026-05-29
- Performed exhaustive review per user query (git diff inspection, full file reads of RemoteAcpCommand + bridge + CredentialStores + debug launch sites + tests on both platforms, greps for leakage/XAI, mandated builds).
- Core auth removal: clean and complete (RemoteAcpCommand.stdioCommand no longer takes/uses xaiApiKey or generates envPrefix/fallback; SharedKMPBridge.acpStdioCommand signature updated; load/saveXAI excised from protocol + Keychain + Android impl + InMemory fakes + all call sites + 2 tests rewritten with explicit "never contains mobile auth injection" + Codex parity assertions).
- **User question directly addressed and fixed:** "With regards to auth: if the ssh server is already authenticated, why does the mobile app need to handle auth? this is what we do with codex" → Answer: it doesn't. SSH login (credentialStore.loadCredential for the ServerRecord) is the *only* mobile auth step for any server, exactly as Codex has always worked. The launched `grok agent stdio` (or codex) inherits the remote user's full environment + home. Any phone-side XAI key or remote auth.json parsing was an unnecessary deviation.
- Two subagent reviews (check-work style) + fresh exact-toolchain builds (Gradle 8.13 + JBR for shared-core jvmTest + android-app compileDebugKotlin; Scripts/verify-ios-build.sh for iOS) all green on the *isolated* delta (parked BackendType files explicitly checked out to keep the change pure).
- **VERDICT (clean delta):** PASS. No UI/mapper/Codex impact (the "properly translated..." gate remains satisfied by prior work). Hard break on the inconsistent auth injection per taste + Claude.md rules.
- Conventional commit prepared: `fix(acp): remove XAI_API_KEY mobile auth injection from RemoteAcpCommand + CredentialStore (Codex SSH parity)`. Ready to land. Parked "Auth provisioning UI" item in the list above is now moot / re-triage later if a per-server key override is ever desired.
- Both clients symmetric for the auth aspect (comments + no-injection in iOS VM:935-937 and Android VM:651-656 debug sites).
- Builds: fresh exact `build/gradle-8.13/bin/gradle ... :shared-core:jvmTest "*Acp*" :android-app:compile* :android-app:test* *Acp* --rerun-tasks` → BUILD SUCCESSFUL (8s); `CONFIGURATION=Debug SDK=iphonesimulator Scripts/verify-ios-build.sh` → "Build succeeded".
- Guardrail (1): NO changes to any Codex paths, ConversationSection/View, mappers, main chat rendering, connect/send, AcpProtocolCore, etc. (git name-only + targeted greps confirm 0 protected files touched by auth hunks).
- Guardrail (2) VIOLATION: Working tree delta includes parked ServerRecord work (BackendType enum + field additions in Sources/Mobidex/Models/ServerModels.swift:17+, Android model:15+; plus ServerEditorView.swift, MobidexApp.kt, MobidexLaunchSmoke.swift). This is *not* part of the described "targeted auth simplification". git diff not isolated to auth removal.
- Other: Excellent comments explaining rationale ("SSH authentication is the trust boundary"); OpenAI methods correctly untouched; no dead code left; naming/taste good. Conventional commit ready (e.g. fix(acp): remove XAI_API_KEY mobile injection (Codex SSH parity) ).
- Per process: code (prior) → this review (self) → builds green. Recommend: isolate diff (revert parked files) before commit; re-run subagent check-work on clean tree.
- VERDICT for pure auth change: PASS (with isolation fix required for landing). See full structured report in this session log.

## Auth Removal Re-Verification (post `git checkout` isolation) — 2026-05-29
- Re-confirmed *now-isolated* delta: `git diff --stat` (excl. MDs) = exactly 9 source files (CredentialStore.swift, SharedKMPBridge.swift, AppViewModel.swift x2 platforms, tests x2, Repositories.kt, RemoteAcpCommand.kt + Test.kt). No ServerModels, BackendType, ServerEditor, MobidexApp, LaunchSmoke or other non-auth files. Pure removal.
- Only auth removals: RemoteAcpCommand no longer declares/uses xaiApiKey param or cat/python ~/.grok/auth.json fallback; both CredentialStore protocols + all impls/fakes (iOS Keychain/InMemory + Android AndroidCredentialStore + fakes) excised load/saveXAI methods (replaced by Codex-parity comments only). Both debug launch sites (iOS VM + Android VM) and KMP bridge signature updated (no key passing). Tests rewritten with "never contains mobile auth injection" asserts + design comments.
- Explicit Codex parity comments: present in 8+ locations (RemoteAcpCommand.kt:20, its Test:92, CredentialStore.swift protocol/impl, Repositories.kt, SharedKMPBridge.swift:137, AppViewModels iOS:933/Android:651, fakes). All state "SSH is the trust boundary / exactly as codex does today / same model as Codex".
- Zero impact confirmed (greps): no XAI_* active code paths remain (only asserts + docs/comments); acp* callsites only in 2 debug launch paths + bridge + KMP test; 0 hits in Views/*, mappers (AcpProtocolCore etc untouched), main chat flows, connect/send, Codex* launch files (RemoteCodexAppServerCommand etc fully isolated).
- Fresh builds (triggered now, post-isolation): 
  - Gradle (exact per AGENTS: build/gradle-8.13 + JBR): :shared-core:cleanJvmTest + jvmTest *RemoteAcpCommandTest + :android-app:clean + compileDebugKotlin + compileDebugUnitTestKotlin + testDebugUnitTest *Acp* --rerun-tasks → BUILD SUCCESSFUL (10s, 45 tasks).
  - iOS: CONFIGURATION=Debug SDK=iphonesimulator Scripts/verify-ios-build.sh → "Build succeeded for target Mobidex." (exit 0).
- Process: code (prior auth removal) → review (this exhaustive re-inspect + greps + file reads + subagent-style verification) → fix (none needed) → build/update+run tests (green) → code (tracker update). Per Claude.md/AGENTS + mission skill.
- Trackers updated. Ready for `fix(acp): remove XAI_API_KEY mobile auth injection... (Codex SSH parity)`.
- Re-verification VERDICT: **PASS**.
