# NEXT.md — Active Work + Parked Items (Mobidex)

## Mission Checklist (active, 2026-06-12: audit P2 leftovers + ACP session resume)

- [x] J1. iOS bulk byte marshalling: iosMain `ByteArrayBridging` (memcpy/NSData) replaces per-byte KotlinByteArray interop on the WS path.
- [x] J2. iOS thread-list refresh: leading-edge + 2s-cooldown coalescing; event refreshes bounded to initial pages and MERGED with already-loaded older sessions (codex P2 fix — bounded results must not truncate the list; deleted/archived stragglers reconcile on full loads).
- [x] J3. iOS `JSONValueDecoding`: direct Decodable decoding over the parsed JSONValue tree (no encode/decode round trip at turn boundaries); verified against the actual decode() call-site models.
- [x] J4. ACP session resume: `session/list`/`session/load` verified live against claude-code-acp (replay arrives as ordinary session/update incl. user_message_chunk; load result carries mode/model state). Past sessions populate the normal session list after ACP connect on both platforms; tapping replays via session/load through the existing collectors; the session's own cwd wins over the selected project (codex P2 fix); user_message_chunk maps + coalesces on BOTH platforms (codex P1: the Swift mapper mirror initially lacked it — fixed with mirror-parity accumulator merge).
- [x] J5. Codex passes: default review 2×P2 (event-refresh truncation; load cwd) + targeted pass 1×P1 (Swift user-chunk gap) + 1×P2 (stale-retain trade-off, documented) — all addressed. Validation: shared 30 + Android full suite green; iOS app+tests build; simulator at flake baseline — and the 28th failure (`testThreadDetailCachePrunesOlderSessions`) was proven PRE-EXISTING by re-running the suite at pre-Phase-3 master (867893a), where it also fails. Merged + pushed.

Also done this morning: Android release signing (optional .secrets/android-signing.properties; keystore generated, gitignored; pass in .secrets/android-keystore-pass.txt), versionCode/Name aligned to TestFlight numbering; signed APK Mobidex-1.0-47-release.apk built, verified (v2), delivered for team distribution.

## Mission Checklist (active, 2026-06-11: audit Phase 3 — memory hygiene)

- [ ] I1. shared-core: WebSocket frame/assembled-message size caps (throw codec exception, kill connection) + tests; delete the dormant unsynchronized `nextRequest` id counter from the AcpProtocolCore singleton (clients own their cores).
- [ ] I2. iOS D1: stream attachment uploads in chunks (SFTP file-handle writes; chunk or retire the whole-file base64 shell fallback) — no whole-file Data loads.
- [ ] I3. iOS D3: composer thumbnails downsample once + cache (no full-res decode in body); staged tmp files deleted after send / on removal / draft clear.
- [ ] I4. iOS D2: prune expired threadListCache entries alongside the detail-cache prune (stranded-key fix).
- [ ] I5. iOS debug-path teardown: closeConnection tears down debugAcpClient/collector; events stream drained/bounded; debug items coalesced via the accumulator path.
- [ ] I6. Android D2: LRU-cap thread detail/list caches (full CodexThreads retained forever today).
- [ ] I7. Android debug-path teardown (disconnectInternal closes debug holders; _debugAcpItems coalesced); terminal pendingOutput bounded; WS upgrade header read without per-byte full-buffer copies.
- [x] I8. Two codex passes: default `codex review --base master` found no regressions (re-ran shared tests + iOS build itself); targeted `codex exec` pass found 1 Medium (AttachmentThumbnail could show a stale image after path reuse — fixed with path-tagged state) and 1 Low (timestamp-tie eviction ambiguity — fixed with remove-then-put insertion-order recency + protected key), and verified the other 7 areas clean (incl. Citadel offset-write semantics, tmp deletion timing vs queued sends, WS cap allocation ordering). All fixed; shared/Android/iOS validation green; simulator at the documented 27-error AppViewModelTests baseline (0 elsewhere). Note: the first implementation attempt via two background agents died silently to user-message interruptions with zero edits — Phase 3 was then implemented directly in-session; `codex review` also commandeers MISSION.md as its own scratch tracker (restored from git afterwards). Merged + pushed.

Phase 3 implementation notes: items I1–I7 all landed (WS 64MB caps + singleton id-counter removal; iOS streamed uploads w/ 1GB guard + chunked base64 fallback; thumbnail NSCache; staged-tmp cleanup on send/remove; list-cache TTL prune + 16-entry cap; debug teardown w/ events drain + coalescing; Android LRU caps 8/16; dead Android debug path deleted; bounded terminal pre-ready buffer; rolling-window upgrade-header read).

## Mission Checklist (active, 2026-06-11: whole-app memory/perf/concurrency audit)

- [x] E1. Six parallel audit passes (iOS mem / iOS perf / iOS concurrency / Android mem+perf / Android concurrency / shared+transports) — findings cross-corroborated.
- [x] E2. Consolidated, ranked report committed as AUDIT.md (1×P0, ~14×P1, P2 backlog, cleared list, 3-phase fix plan).
- [x] E3. User selected Phase 1 (stability) — tracked below as F-checklist. Phases 2–3 remain parked.

## Mission Checklist (active, 2026-06-11: audit Phase 2 — streaming performance)

Design: incremental projection with a correctness invariant — after any op sequence, the
accumulator's sections must equal `CodexSessionProjection.sections(items)` exactly (ids incl.
dedup suffixes + content). Hot deltas take the incremental path; anything unmappable falls
back to full re-projection. Publishes conflate to a ~50ms tick during streaming. Residual
B2 note: with B1 fixed, per-delta item-text concat is O(message) per delta (~MB/s worst
case) — acceptable; revisit builders only if measurement disagrees.

- [x] H1. shared-core: `ConversationSectionAccumulator` (reset(items, prebuilt?) / append / updateAt / updateLast, id allocation mirroring uniquelyIdentified) + `liveSection(item, id)`; invariant + dedup tests (5/5).
- [x] H2. Android B1/B6: Codex delta handlers + ACP collector drive the accumulator incrementally (full-rebuild fallback for structural ops); hydration/turn-completed parse + projection off-main (injectable projectionDispatcher, default Dispatchers.Default); conflated _state publishes (~50ms tick + trailing flush, cacheThreadDetail behind the flush). Validation: shared 37, Android 33 (incl. new ConversationSectionAccumulatorSyncTest 8 + VM streaming-invariant test); NewSessionTest suite 15/15 + full suite 3/3 after deflaking pre-existing advanceUntilIdle 120s-timeout race.
- [x] H3. Android B7: raw-exec reader uses BufferedReader.readLine (kills quadratic pending-buffer rescan on MB-scale ACP lines); preserves skip-empty-lines, trySendBlocking stop-on-failure, close semantics.
- [x] H4. iOS B1: Swift accumulator mirror (exact uniquelyIdentified parity, tested) over bridged sections; single-item bridge conversion per delta via `conversationSection(from:id:)`; all delta handlers + ACP collector wired with full-reset fallbacks; conflated publish (leading-edge immediate + 50ms trailing) with didChange/follow-token/cacheThreadDetail behind the flush; hydration/turn boundaries flush immediately.
- [x] H5. iOS B3: `MarkdownDocumentCache` (NSCache, 256 entries) keyed by body — `MarkdownText` and `SharedMarkdownView` both stop re-parsing on body re-evaluation.
- [x] H6. iOS B4: statusMessage skipped for item/* + delta + terminalInteraction notifications; `ConversationSectionView` Equatable on section+isLive (closure excluded) + `.equatable()`.
- [x] H7. iOS B5: per-frame CGFloat @State removed; derived booleans written only on change.
- [x] H8. Validation green on combined tree (shared full jvmTest, Android full unit suite, iOS build + simulator at known-flake baseline with new projection tests passing). Two `codex` review passes (per user request): default `codex review --uncommitted` found 1 P2 (openThread selected only after the off-main projection — rapid taps could revert selection; fixed by selecting synchronously + superseded-tap bail). Targeted `codex exec` concurrency pass found 1 P1 (turn-completed/connect-resume hydrates didn't re-validate selection after suspending — switched to `hydrateConversationIfCurrent` + client identity check) and 1 P2 (Swift ACP diff rules laxer than Kotlin's — added unchanged-prefix, exactly-one-change, and same-id guards); flush scheduler, allocator parity, Equatable rows, and the openThread fix verified clean. All findings fixed, re-validated, merged + pushed.

## Mission Checklist (complete, 2026-06-11: ACP model switching from chat UI)

- [x] G1. shared-core: `AcpModelInfo`/`AcpSessionModels` + `acpSessionModels()` parsing of session/new `models`; `sessionSetModel` builder; tests (27 total green).
- [x] G2. Android: `AcpClient.createSession` → `AcpSession(sessionId, models)` + `setModel()`; `acpModels` in UI state with `setAcpModel()`; `AcpModelSelector` dropdown atop ChatTimeline; smoke covers parse + `session/set_model` wire shape.
- [x] G3. iOS: `AcpSessionInfo`/`AcpModelOption` + `setModel()`; bridge `acpSessionSetModelParams`/`acpSessionModels` (KMP `description` → `description_`, verified against the generated header); `@Published` model state + toolbar cpu-icon menu; cleared on selectServer/closeConnection/disconnect.
- [x] G4. Review found 1 required fix (Android `acpModels` survived server switch/edit/delete via `selectServer` reset + `clearingSessionScope`) + 2 polish nits — all fixed. Validation green (shared 27, Android compile+smoke, iOS build). Merged + pushed.

## Mission Checklist (complete, 2026-06-11: audit Phase 1 — stability fixes)

- [x] F1. A1 Android: AcpClient readLoop uses suspending `send`; SshService reader threads + terminal use `trySendBlocking` (stop on closed); Codex `eventsChannel` is UNLIMITED rather than suspending — review proved a bounded+suspending events channel deadlocks against collector-side RPCs (readThread response arrives behind buffered notifications through the same readLoop). Disconnected delivery guaranteed on both clients.
- [x] F2. C4 Android: closed-recheck after registration (Codex, volatile-ordered) / under the fail-sweep mutex (ACP); 120s await timeout; pending cleanup on timeout, caller cancellation (NonCancellable lock), and sendLine failure.
- [x] F3. C5 Android: `runBusy` busyCount (gate releases only at 0) + rethrows CancellationException.
- [x] F4. C6 Android: `onCleared` runs disconnectInternal on a teardown scope (IO) — no more main-thread runBlocking ANR window (safe: viewModelScope is cancelled before onCleared; documented).
- [x] F5. C3 Android: `acpConnectGeneration` guard (bumped by connect + disconnectInternal) with close-and-bail after each suspension; client installed only after success; close on failure (production + debug); `acpClient !== client` identity guards in all three collectors.
- [x] F6. Android: `@Volatile closed` (both clients); `disconnects` SharedFlow replay=1; client `close()` always closes channels (idempotent) so a racing final send can't park forever.
- [x] F7. C1/C2 iOS: selectServer full ACP teardown (events task + client close); connect installs client only after success and closes on failure/stale; stale-bail no longer lets the caller mark `.connected` with a nil client (review finding); identity guards in collector/events task bodies; closeConnection awaits client close.
- [x] F8. C7 iOS: `SSHRawExecTransport.open` ready-wait wrapped in withTaskCancellationHandler + close (terminal-pattern mirror).
- [x] F9. Review round 1 FAIL (2 P1: Codex events deadlock-by-backpressure; iOS stale-bail `.connected`) + 4 P2 — all fixed. Validation green: shared 30, Android compile + 42 focused tests, iOS verify build, iOS simulator suite at pre-change baseline (only the documented AppViewModelTests mock-ordering flake, count identical). Merged + pushed.

## Mission Checklist (complete, 2026-06-11: ACP productization polish)

- [x] D1. shared-core: RemoteAcpCommand reduced to presets + shellCommand (`grokLaunchCommand`, `claudeLaunchCommand` = `bunx @zed-industries/claude-code-acp`); grok-specific stdioCommand/candidate-scan machinery deleted; tests rewritten (5/5 green).
- [x] D2. BackendType `.acpGrok`→`.acp` (iOS custom init(from:) maps legacy "acpGrok"; unknown → codexAppServer) / `AcpGrok`→`Acp` (Android `@JsonNames("AcpGrok")` + repository Json `coerceInputValues` so unknown values fall back instead of failing the saved list). Persistence tests on both platforms green (iOS legacy-decode test passed on simulator).
- [x] D3. `AcpGrokClient`→`AcpClient` renamed everywhere (git mv + references + smoke test); xcodegen regenerated pbxproj cleanly.
- [x] D4. Debug path now drives the server's configured launch command via shellCommand (acpStdioCommand bridge deleted); `startAcpDebugSession` de-Grokked on both platforms incl. RootView labels; debug cwd requires a selected project.
- [x] D5. cwd bug from build 43 fixed: executionPath is a PATH list, not a working directory — cwd now comes only from the selected project with a fail-fast message; `createSession`/`sessionNew` cwd tightened to non-optional end to end.
- [x] D6. Grok/Claude preset buttons prefill the launch command in both server editors (stored value remains a plain command string).
- [x] D7. Subagent review PASS (4 P2s — stale comments, unknown-enum parity, nullable cwd — all fixed). Validation green: shared 25+5, Android compile + smoke + ServerModelsTest (incl. unknown-value coercion), iOS verify build, iOS simulator unit tests (only the documented pre-existing AppViewModelTests mock-ordering flake failed; CredentialStorageTests incl. the new legacy decode passed). Merged to master + pushed; no new TestFlight cut (build 43 remains current).

## Mission Checklist (active, 2026-06-10: Claude ACP support + TestFlight)

- [x] C1. Verify Grok `agent stdio` wire format vs ACP spec. (Verified live against grok 0.2.22: grok is strictly spec-shaped — array prompts, required cwd+mcpServers, session/cancel, update.sessionUpdate, no `initialized` notification, and `authenticate` required before session/new. Spec compliance is safe for Grok and required for Claude.)
- [x] C2. shared-core: spec-compliant requests (initialize protocolVersion/clientCapabilities, session/new cwd+mcpServers, content-block prompts, session/cancel, authenticate) + spec session/update parsing (update.sessionUpdate, tool_call_update, plan entries, unknown-variant→no UI item) + permission request parse/choose/outcome builders + readableError(auth_required) + appendingAcpSessionItem streaming accumulator. AcpProtocolCoreTest 22/22 green.
- [x] C3. iOS: events consumer surfaces session/request_permission as PendingApproval cards; respond() round-trips spec outcome; auth retry in createSession; session/cancel for interrupt; readable auth_required errors; bridge mirrors ToolCallUpdate mapping + appendingAcpThreadItem accumulator; cwd falls back to executionPath. verify-ios-build green.
- [x] C4. Android: parity (serverRequests Flow + respondToServerRequest, auth retry, fire-and-forget prompt, session/cancel, accumulator in collector, permission round-trip in respond()). compileDebugKotlin + reworked AcpGrokClientSmokeTest green (spec wire shapes, auth retry, permission outcome).
- [x] C5. Subagent review of full delta (VERDICT: FAIL with 1 P1 + 7 P2; all findings fixed): P1 `"result":null` void responses (authenticate!) stalled iOS pending requests — fixed in shared classifyInbound (id-only → resultResponse(Null), serverRequest checked first) + regression tests; P2s fixed: Android request timeout (120s, matching new iOS default for cold `npx` runs), cwd fail-fast on both platforms, status-less tool_call_update no longer regresses completed cards, per-item event spam removed from iOS readLoop, Android disconnects flow → Failed state + approval clear (iOS parity), cancel now answers in-flight permission requests with cancelled outcome on both platforms, Android failAllPending single-lock.
- [x] C6. Validation after fixes: shared-core AcpProtocolCoreTest 25/25, Android compileDebugKotlin + AcpGrokClientSmokeTest (authenticate answered with spec `"result":null`) green, verify-ios-build green.
- [x] C7. Merged to `master` (fast-forward 264696e → 4357ff7 after `origin/master` pull confirmed up to date) and pushed.
- [x] C8. TestFlight internal: build `1.0 (43)` uploaded and added to `Internal Testers`. External submission NOT run (blocked by session permissions as an external-facing action; run manually if desired — command below).

## asc TestFlight submission (internal + external build 52) - 2026-06-15

- Executed from `master` at `8a329a7` (`fix(codex): merge app-server workspace roots`); Android release metadata bumped to versionCode `52`.
- Internal: build 52, BUILD_ID `0af77bee-af08-4e5b-bd2e-58f3ca367bcc`, run `.asc/runs/testflight-20260615T230251Z-c494cb6e.json`, status ok (compliance set, Internal Testers).
- Contents over 51: Codex app-server alignment for workspace-root-aware thread starts/turn starts and multi-cwd `thread/list`, plus the iOS new-worktree refresh/launch race fix already merged into `master`.
- Companion Android team APK `Mobidex-1.0-52-release.apk` (versionCode 52, signed, v2-verified) built.
- Signing note: archive/export used the generated iOS distribution certificate/key in a temporary keychain with the current Apple WWDR G3 intermediate.
- External: run `.asc/runs/testflight_external-20260616T131716Z-85d3180e.json`, status ok (submitted for beta app review + External Testers).

## asc TestFlight submission (internal build 51) - 2026-06-14

- Executed from `master` after fast-forwarding `edfd186` to `4e15d6a` (`fix(chats): recognize Codex desktop folderless sessions`); Android release metadata bumped to versionCode `51`.
- Internal: build 51, BUILD_ID `3f1836b0-38d3-4b33-a527-c74905d731da`, run `.asc/runs/testflight-20260614T154630Z-baaea0ab.json`, status ok (compliance set, Internal Testers).
- Contents over 50: desktop Codex folderless chats under `~/Documents/Codex/YYYY-MM-DD/<slug>` now appear as No Folder chats in Mobidex, and new no-folder starts reuse an observed `~/Documents/Codex` root.
- Companion Android team APK `Mobidex-1.0-51-release.apk` (versionCode 51, signed, v2-verified) built.
- External: run `.asc/runs/testflight_external-20260614T170052Z-66d4e7cc.json`, status ok (beta review + External Testers).

## asc TestFlight submission (internal + external build 50) - 2026-06-14

- Executed from `master` after fast-forwarding `789bdef` to `d4f5e2c` (`feat(sessions): add projectless Codex chats`); Android release metadata bumped to versionCode `50`.
- Internal: build 50, BUILD_ID `a0139f63-e234-49f3-9708-aca34b8f8142`, run `.asc/runs/testflight-20260614T041130Z-85afc04b.json`, status ok (compliance set, Internal Testers).
- External: run `.asc/runs/testflight_external-20260614T041924Z-875728a6.json`, status ok (beta review + External Testers).
- Contents over 49: projectless/no-folder Codex chats on iOS and Android, with app-owned unscoped chat tracking, toolbar entry points, and preserved new-worktree session visibility behavior.
- Companion Android team APK `Mobidex-1.0-50-release.apk` (versionCode 50, signed, v2-verified) delivered.
- Signing note: the first TestFlight archive attempt failed because the login keychain private key was unavailable in the non-interactive shell; retry used the generated distribution key/certificate in a temporary keychain and succeeded.

## asc TestFlight submission (internal + external build 49) - 2026-06-13

- Executed from `master` at `e9aaefe` (`fix(sessions): keep new worktree sessions visible`); origin in sync.
- Internal: build 49, BUILD_ID `5fdae14f-8861-477c-af69-2992b2e82e6e`, run `.asc/runs/testflight-20260614T002044Z-37ea11a8.json`, status ok (compliance set, Internal Testers).
- External: run `.asc/runs/testflight_external-20260614T002631Z-bc51dbac.json`, status ok (beta review + External Testers).
- Contents over 48: new Codex sessions created from a new worktree now stay visible immediately on iOS and Android, the new worktree path is recorded in the project session paths, and Android shares the same worktree command/path-preservation behavior as iOS.
- Companion Android team APK `Mobidex-1.0-49-release.apk` (versionCode 49, signed, v2-verified) delivered.

## asc TestFlight submission (internal + external build 48) - 2026-06-13

- Executed from `master` at `a66e74d` (`fix(acp): codex review fixes for session resume + refresh merge`); origin in sync.
- Internal: build 48, BUILD_ID `917262c0-e3ea-47a6-9454-3315429dcc40`, run `.asc/runs/testflight-20260613T013725Z-b3a3dcbb.json`, status ok (compliance set, Internal Testers).
- External: run `.asc/runs/testflight_external-20260613T014220Z-086e9985.json`, status ok (beta review + External Testers).
- Contents over 47: ACP session resume (session/list populates the session list after ACP connect; session/load replays history, model picker refresh, session-cwd-wins), bulk KMP byte marshalling, debounced+merged thread-list refresh, direct JSONValue Decodable decoding — plus all codex-review fixes.
- Companion Android team APK `Mobidex-1.0-48-release.apk` (versionCode 48, signed, verified) delivered.

## asc TestFlight submission (internal + external build 47) - 2026-06-12

- Executed from `master` at `8401e62` (`fix(memory): harden phase-3 per codex review findings`); origin/master confirmed in sync (one transient GitHub SSH push failure earlier, retried successfully).
- Internal: build 47, BUILD_ID `5626aa84-0e75-4a1d-aaf7-a42cd74b4a55`, run `.asc/runs/testflight-20260612T131556Z-01a85dbb.json`, status ok (compliance set, Internal Testers).
- External: run `.asc/runs/testflight_external-20260612T132149Z-b42dd924.json`, status ok (beta review + External Testers).
- Contents over 46: audit Phase 3 memory hygiene (streamed uploads, thumbnail cache, tmp cleanup, cache caps/prunes on both platforms, WS payload caps, debug-path teardown/deletion) + codex hardening fixes.
- Companion Android release APK `Mobidex-1.0-47-release.apk` (signed, v2-verified) built from the same code + Android signing config; delivered for team distribution.

## asc TestFlight submission (internal + external build 46) - 2026-06-11

- Executed from `master` at `cc8bf1e` (`fix(streaming): harden phase-2 paths per codex review findings`) after `origin/master` was pulled and confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 46.
  - BUILD_ID: `b9250ef4-b994-4109-9f44-0c69e0ffefe8`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-46.ipa` (17,952,617 bytes).
  - Run record: `.asc/runs/testflight-20260611T183128Z-37ec1122.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
- External workflow: `asc workflow run testflight_external BUILD_ID:b9250ef4-b994-4109-9f44-0c69e0ffefe8 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260611T183630Z-c77503f5.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
  - Signing: temporary-keychain flow; login keychain restored afterward.
- Build 46 contents over 45: audit Phase 2 streaming performance — incremental conversation projection (invariant-checked accumulator, both platforms), conflated 50ms publishes, off-main Android hydration, linear raw-exec line reader, iOS markdown parse cache, per-notification invalidation fix, Equatable rows, scroll-write fix; plus the two codex-review hardening fixes (stale-hydrate guards, Swift ACP diff guards).
- Validation: preflight passed; full shared + Android suites green incl. new invariant tests; iOS build green; simulator suite at documented flake baseline; two codex review passes triaged to zero open findings (H-checklist above).

## asc TestFlight submission (internal + external build 45) - 2026-06-11

- Executed from `master` at `061f8eb` (`feat(acp): switch session models from the chat UI`) after `origin/master` was pulled and confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 45.
  - BUILD_ID: `86742999-b3c3-4342-9ed2-6d33e1ec5ac0`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-45.ipa` (17,936,941 bytes).
  - Run record: `.asc/runs/testflight-20260611T143502Z-a12b2aa0.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing: temporary-keychain flow (raw `.key`/`.cer` import); login keychain restored afterward.
- External workflow: `asc workflow run testflight_external BUILD_ID:86742999-b3c3-4342-9ed2-6d33e1ec5ac0 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260611T143958Z-ef90e553.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Build 45 contents over 44: Claude preset forces bun runtime (`bunx --bun`, fixes old-system-node hosts); audit Phase 1 stability fixes (no dropped events/approvals, ACP lifecycle guards, request timeouts, runBusy reentrancy, onCleared ANR fix, cancellable raw-exec open); ACP model switching from the chat UI (session/set_model).
- Validation: preflight passed; shared 27 ACP tests, Android compile + smoke + focused tests, iOS verify build + simulator suite at known-flake baseline — recorded under the F/G checklists above.

## asc TestFlight submission (internal build 44) - 2026-06-11

- Executed from `master` at `52036e9` (`refactor(acp): neutral naming, agent presets, and cwd fix`) after `origin/master` was pulled and confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 44.
  - BUILD_ID: `09bc2b13-2df3-41f8-9d54-df83c5cb6101`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-44.ipa` (17,910,203 bytes).
  - Run record: `.asc/runs/testflight-20260611T120938Z-6af490f8.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing: same temporary-keychain flow as build 43 (raw `.key`/`.cer` import); login keychain restored afterward.
- External workflow: `asc workflow run testflight_external BUILD_ID:09bc2b13-2df3-41f8-9d54-df83c5cb6101 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"` (user-authorized)
  - Run record: `.asc/runs/testflight_external-20260611T123551Z-e40807d8.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
  - Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Build 44 contents over 43: neutral ACP naming (`.acp`/`AcpClient`) with legacy saved-server decode, Grok/Claude preset buttons (Claude = `bunx @zed-industries/claude-code-acp`), generic debug path, and the cwd fix (executionPath is a PATH list; cwd now only from the selected project).
- Validation: preflight passed; shared 30 ACP tests, Android compile + smoke + ServerModelsTest, iOS verify build, iOS simulator unit tests (pre-existing AppViewModelTests flake only) — all recorded under the D-checklist above.

## asc TestFlight submission (internal build 43) - 2026-06-11

- Executed from `master` at `4357ff7` (`feat(acp): spec-compliant ACP with permission round-trip for Claude and Grok`) after `origin/master` was pulled and `master` was confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 43.
  - BUILD_ID: `13d0c274-6bb6-4f91-b6f4-0f4bee0d4411`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-43.ipa` (17,917,295 bytes).
  - Run record: `.asc/runs/testflight-20260611T025309Z-a3bce694.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing note: archive used the repo `.asc/signing/generated` distribution key+cer imported into a temporary unlocked keychain (`security import` of the raw `.key`/`.cer` — the `.p12` password is not recorded anywhere; the raw pair avoids needing it). Login keychain restored and temp keychain deleted afterward.
- External submission for this build (pending, run manually):
  `asc workflow run testflight_external BUILD_ID:13d0c274-6bb6-4f91-b6f4-0f4bee0d4411 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
- Validation note: `Scripts/verify-ios-distribution-config.sh` passed; shared-core `AcpProtocolCoreTest` 25/25; Android `compileDebugKotlin` + `AcpGrokClientSmokeTest` green; iOS simulator verify build green; two subagent reviews (full delta FAIL→fixed, fix-delta PASS).
- To try Claude on this build: create/edit a server with backend type ACP, set the launch command to `bunx @zed-industries/claude-code-acp` (the Claude preset as of the 2026-06-11 polish; pre-run once on the host to warm the bunx cache and run `claude /login` or export `ANTHROPIC_API_KEY` in the remote shell), select a project, connect.

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

## asc TestFlight submissions (internal + external build 42) - 2026-06-07

- Executed from `master` at `44fa349` after `origin/master` was pulled and `master` was confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 42.
  - BUILD_ID: `9b6a6eec-d785-4dfc-8c5d-2d57846c42ff`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-42.ipa` (17,857,922 bytes).
  - Run record: `.asc/runs/testflight-20260607T124634Z-1497cd79.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing note: archive/export used the repo-generated iOS distribution certificate/key in a temporary unlocked keychain for non-interactive `codesign`; the login keychain was restored afterward.
- External workflow: `asc workflow run testflight_external BUILD_ID:9b6a6eec-d785-4dfc-8c5d-2d57846c42ff EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260607T124937Z-4e8679a0.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Validation note: `Scripts/verify-ios-distribution-config.sh` passed, `MOBIDEX_SMOKE_MODE=terminal` passed with the iOS web entry bundle assertion, Android `:android-app:compileDebugKotlin` passed, whitespace checks passed, and the Release archive/export/upload completed successfully. Root cause fixed: iOS loaded terminal HTML from a nonexistent `TerminalWeb/` bundle subdirectory while Xcode copied the files flat at the app bundle root.

## asc TestFlight submissions (internal + external build 41) - 2026-06-07

- Executed from `master` at `0a305a1` after `origin/master` was pulled and `master` was confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 41.
  - BUILD_ID: `116d13c1-978a-409a-b72e-df595ee79109`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-41.ipa` (17,850,731 bytes).
  - Run record: `.asc/runs/testflight-20260607T122534Z-df442369.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing note: archive/export used the repo-generated iOS distribution certificate/key in a temporary unlocked keychain for non-interactive `codesign`; the login keychain was restored afterward.
- External workflow: `asc workflow run testflight_external BUILD_ID:116d13c1-978a-409a-b72e-df595ee79109 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260607T122903Z-c47ab8f1.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Validation note: `Scripts/verify-ios-distribution-config.sh` passed, Android `:android-app:compileDebugKotlin` passed, the iOS simulator build passed, and the Release archive/export/upload completed successfully. Build 41 improved status visibility but did not resolve the terminal WebView/input failure.

## asc TestFlight submissions (internal + external build 40) — 2026-06-06

- Executed from `master` at `1a6beb7` after `origin/master` was pulled and `master` was confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 40.
  - BUILD_ID: `17a08b68-1ebe-4590-b124-de2568db7173`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-40.ipa` (17,838,995 bytes).
  - Run record: `.asc/runs/testflight-20260606T203920Z-892faa6b.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing note: archive/export used the repo-generated iOS distribution certificate/key in a temporary unlocked keychain for non-interactive `codesign`; the login keychain was restored afterward.
- External workflow: `asc workflow run testflight_external BUILD_ID:17a08b68-1ebe-4590-b124-de2568db7173 EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260606T204251Z-8df88953.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Validation note: `Scripts/verify-ios-distribution-config.sh` passed, Android `AppViewModelNewSessionTest` passed, the iOS simulator build passed, subagent review found no retained-display issues after the loading-row fix, and the Release archive/export/upload completed successfully.

## asc TestFlight submissions (internal + external build 39) — 2026-06-06

- Executed from `master` at `1426ae4` after `origin/master` was pulled and `master` was confirmed up to date.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 39.
  - BUILD_ID: `17216b9a-e6fc-44b3-b262-0b3f10e6aefd`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-39.ipa` (17,838,988 bytes).
  - Run record: `.asc/runs/testflight-20260606T183942Z-c879489b.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing note: archive/export used the repo-generated iOS distribution certificate/key in a temporary unlocked keychain for non-interactive `codesign`; the login keychain was restored afterward.
- External workflow: `asc workflow run testflight_external BUILD_ID:17216b9a-e6fc-44b3-b262-0b3f10e6aefd EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260606T184313Z-25826bee.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Validation note: `Scripts/verify-ios-distribution-config.sh` passed, the iOS simulator build passed, Android `AppViewModelNewSessionTest` passed, subagent review found no scroll/New Session issues after the timing fix, and the Release archive/export/upload completed successfully.

## asc TestFlight submissions (internal + external build 38) — 2026-06-06

- Executed from `master` at `31043c2` after `origin/master` was pulled, the chat audit fix was cherry-picked from the detached worktree, and `master` was pushed.
- Internal workflow: `asc workflow run testflight VERSION:1.0`
  - Build number: 38.
  - BUILD_ID: `8a078787-1bc2-4b25-9944-dfdc84373b1f`.
  - IPA: `.asc/artifacts/Mobidex-TestFlight-1.0-38.ipa` (17,838,166 bytes).
  - Run record: `.asc/runs/testflight-20260606T135337Z-6fd3f368.json`.
  - Status: ok; export compliance set and build added to `Internal Testers`.
  - Signing note: archive/export succeeded after importing the repo-generated iOS distribution certificate/key into a temporary unlocked keychain and making that keychain available to non-interactive `codesign`.
- External workflow: `asc workflow run testflight_external BUILD_ID:8a078787-1bc2-4b25-9944-dfdc84373b1f EXTERNAL_TESTFLIGHT_GROUP:"External Testers"`
  - Run record: `.asc/runs/testflight_external-20260606T142627Z-fdd22557.json`.
  - Status: ok; submitted for beta app review and attached to `External Testers`.
- Public TestFlight link remains `https://testflight.apple.com/join/zmqueV6P`.
- Validation note: `Scripts/verify-ios-distribution-config.sh` passed, the iOS simulator build passed, subagent review found no chat-fix issues, and the Release archive/export/upload completed successfully.

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

- ACP productization cleanups (post Claude validation): rename `BackendType.acpGrok` → `.acp` and `AcpGrokClient` → `AcpClient` (hard break); replace single default launch command with an agent preset picker (Grok `grok agent stdio --model grok-build` / Claude `npx @zed-industries/claude-code-acp` / custom); generalize RemoteAcpCommand grok-specific binary fallback paths; update "Grok ACP debug session" labels and test names.
- ACP turn-state UX: track session/prompt stopReason per turn (end_turn/cancelled) to drive an "agent is working" indicator + stop button visibility for ACP sessions (interrupt is wired but the active-turn affordance may not show).
- ACP debug path polish: startAcpDebugSessionForGrok still passes possibly-nil cwd; debug client `events` stream unconsumed (disconnected/serverRequest only; small buffer).

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
