# Memory / Performance / Concurrency Audit — 2026-06-11

Whole-app audit (iOS, Android, shared-core, transports) at master `47f948e`. Six parallel
audit passes (iOS memory / iOS performance / iOS concurrency / Android memory+performance /
Android concurrency / shared-core+transports); findings below are evidence-based with
file:line, deduplicated, and ranked. Several top findings were independently confirmed by
2–3 auditors. Audit is read-only — no fixes applied yet; proposed fix plan at the bottom.

Severity: **P0** plausible in normal use with user-visible breakage (lost data, wedged state,
crash) · **P1** real leak / hang / user-visible jank in realistic sessions · **P2** bounded
waste, timing-dependent race, or latent hazard.

---

## P0

### A1. Android: bounded channels + `trySend` silently drop chat deltas, approvals, and even Disconnected
`service/CodexAppServerClient.kt:51,197,201,217`, `service/AcpClient.kt:61-62,189,195`, `service/SshService.kt:330,437,515,554,596,629`
Every producer (SSH reader threads / IO readLoops) writes `Channel(BUFFERED)` (=64) with
`trySend` while the Main-thread consumer does full re-projection per item (see B1) and even
synchronous RPCs (`turn/completed` → `readThread`, AppViewModel.kt:2317) between receives.
Once the consumer falls 64 behind: deltas vanish (truncated/garbled chat), `ServerRequest`
approval prompts vanish (agent hangs awaiting an answer), terminal output drops during bursts,
and worst-case the `Disconnected` event itself is dropped → UI wedged on "Connected" with no
reconnect. **Fix:** suspending `send()` from producers (backpressure the socket) or UNLIMITED
for control events; move projection off the per-item path (B1).

## P1 — streaming performance (the dominant lever, both platforms)

### B1. Full conversation re-projection on every streamed delta, on the main thread
- iOS: `AppViewModel.swift:3184` (`rebuildConversationFromLiveItems`) called from every
  delta handler (3682, 3693, 3848, …) → `SharedKMPBridge.conversationSections(from:)`
  (SharedKMPBridge.swift:527) — every item crosses Swift→Kotlin AND Kotlin→Swift per delta,
  on `@MainActor`. ACP path identical: `AppViewModel.swift:1045-1047`.
- Android: delta handlers (`AppViewModel.kt:2590-2720`) → `thread.mapItems` (copies every
  turn/item list) → `conversationSections()` → full `CodexSessionProjection.sections(...)`;
  ACP collector `AppViewModel.kt:760-774` same, all on Main.
- shared: `CodexSessionProjection.kt:119-145` re-joins every Reasoning body (165) and every
  FileChange diff (185) per call.
Cost: O(total conversation chars) per delta → O(deltas × conversation) per turn; at tens of
deltas/sec on a long thread this saturates the main thread (typing/scroll jank; Android ANR
plausible) and is the producer-side pressure behind A1.
**Fix (one refactor):** incremental projection — re-section only the mutated item id (section
ids are provably stable during streaming) + conflate/debounce publishes (~50ms) + run off main.

### B2. Quadratic string accumulation per streamed message
`shared-core/AcpProtocolCore.kt:468` (`last.text + item.text` full copy per chunk), iOS
`AppViewModel.swift:3678`, Android `AppViewModel.kt:2596`. A 100KB message in 50-byte chunks
≈ 100M char copies — then multiplied by B1 re-reading the full text per delta. **Fix:**
per-item StringBuilder/chunk-list tail, materialize once per projection tick.

### B3. iOS: markdown parsed during view construction (the `State(initialValue:)` trap) — prior fix incomplete
`ConversationView.swift:1694-1697` — `MarkdownText.init` runs the KMP markdown parse inside
`State(initialValue:)`; SwiftUI discards the value for existing rows but the work runs on
EVERY body evaluation of every visible markdown row. Combined with B4/B5 this re-parses all
visible rows per delta and per scroll tick. **Fix:** cache parsed documents keyed by section
id + body hash; parse in `onAppear`/`onChange` only.

### B4. iOS: whole-conversation invalidation per notification via `statusMessage`
`AppViewModel.swift:2656-2658` sets `statusMessage = method` for every notification (incl.
non-selected threads); ConversationView observes the whole VM (`@EnvironmentObject`) and rows
carry a closure so nothing is Equatable-skipped → full visible re-render per event. **Fix:**
stop publishing statusMessage per notification; make row payloads Equatable.

### B5. iOS: unthrottled scroll-tick `@State` writes re-render all visible rows per frame
`ConversationView.swift:294-298, 491` — raw CGFloat distance written per scroll frame.
**Fix:** store only derived booleans, write on change.

### B6. Android: turn-completed does full `readThread` + parse + projection on Main
`AppViewModel.kt:2317`, parse on main also at 852-857, 1297. Multi-MB sessions freeze frames
at every turn boundary. **Fix:** `withContext(Dispatchers.Default)` for parse+projection.

### B7. Android: raw-exec line transport rescans the pending buffer per chunk (quadratic on long lines)
`service/SshService.kt:543-556` — `pending += chunk; pending.split('\n')` per 8KB chunk. ACP
agents emit MB-scale single-line JSON (large tool results): a 5MB line ≈ GBs of char copying,
stalling all inbound traffic. **Fix:** `BufferedReader.readLine()` (already wrapped at :542)
or scan only the new chunk.

## P1 — lifecycle / correctness

### C1. iOS: server switch / failed connect leaks a live AcpClient and corrupts the next connection
`AppViewModel.swift:552-556` (selectServer cancels only `acpCollectorTask`, never
`acpEventsTask`, never `close()`); `:1027` assigns `acpClient` before initialize/createSession
can throw. The orphan's later EOF drives the still-running `acpEventsTask` →
`handleAcpEvent` marks the NEW healthy connection `.failed`, clears its approvals, can append
phantom approvals. Also leaks SSH + remote agent process. (Found independently by two
auditors.) **Fix:** selectServer mirrors closeConnection's ACP teardown; close client on
connect failure; identity-guard (`self.acpClient === client`) inside both ACP task bodies.

### C2. iOS: ACP collector/events tasks lack the generation guard the Codex path has
`AppViewModel.swift:1040-1061` vs the Codex guard at `:2651`. Cancelled-but-already-resumed
loop bodies append stale items/approvals into the NEXT session's state; `respond(to:)` can
send an old requestID to the new client. **Fix:** same as C1 (identity/generation check
before mutating).

### C3. Android: ACP connect has no ownership guard — double-connect leaks a live client and interleaves two agents into one chat
`AppViewModel.kt:713-825` (no equivalent of the Codex `:834` staleness check). Second connect
while `openRawExec` is in flight → two clients, two collector sets, one never closed.
**Fix:** generation token / `acpClient === client` checks after each suspension point.

### C4. Android: `CodexAppServerClient.request` can hang forever
`service/CodexAppServerClient.kt:161-176, 205-224` — register-after-`failPending` race (no
`closed` re-check under the mutex) + no await timeout → `runBusy` never completes → `isBusy`
wedged until restart. `AcpClient` has the same registration race but its 120s timeout caps it.
**Fix:** re-check `closed` under the mutex when registering; wrap await in `withTimeout`;
remove pending entry on caller cancellation.

### C5. Android: `runBusy` is not reentrant and swallows `CancellationException`
`AppViewModel.kt:2737-2750` — concurrent runBusy calls release each other's gate mid-mutation;
cancelled connects record "Job was cancelled" as a failure. **Fix:** busy counter; rethrow
CancellationException.

### C6. Android: `onCleared` runs sshj teardown in `runBlocking` on Main (ANR window)
`AppViewModel.kt:2793-2795` + `SshService.kt:496-502` (`join(1s)` per channel × up to 3
connections). **Fix:** NonCancellable app-scoped coroutine instead of blocking.

### C7. iOS: `SSHRawExecTransport.open` waits on a continuation with no cancellation handler or timeout
`SSHClientService.swift:1209` (vs the correct pattern at :777-788) — hung host ⇒
"Starting ACP agent" hangs uncancellably. **Fix:** `withTaskCancellationHandler` + close.

## P1 — memory

### D1. iOS: attachments load entire files into memory (and ~4x via base64 shell fallback)
`SSHClientService.swift:483-492, 646-649`; any-file importer at `ConversationView.swift:126`.
Large video/archive ⇒ realistic OOM. **Fix:** chunked SFTP streaming; drop/chunk base64 path.

### D2. Android: thread caches retain full conversations forever
`AppViewModel.kt:227-228, 1155-1204` — every visited session's entire CodexThread retained,
refreshed per delta, no LRU/cap (iOS detail cache is capped at 8; its list cache strands
expired keys — `AppViewModel.swift:376, 2061-2067`). **Fix:** LRU cap (Android), prune
expired list-cache entries (iOS).

### D3. iOS: composer thumbnails decode full-resolution images in `body`
`ConversationView.swift:1241-1246` — 48MP photo ⇒ >100MB spike, re-decoded per keystroke.
**Fix:** `preparingThumbnail`/CGImageSource downsample once + cache. (Related P2: staged tmp
files never deleted — `ConversationView.swift:894-959`, `AppViewModel.swift:1908-1927`.)

## P2 (selected; full details in the audit transcripts)

- **Shared:** `AcpProtocolCore` singleton holds an unsynchronized `CodexRpcClientCore` id
  counter (`AcpProtocolCore.kt:191`, counter `CodexProtocolCore.kt:393-397`) — dormant today
  (every live client owns its own counter) but a latent cross-client id-collision API; delete
  `nextRequest` from the singleton. WebSocket frame/message size unbounded
  (`WebSocketFrameCodec.kt:167-189`) — cap and kill the connection. Tool-call args/output
  re-encoded per update (`AcpProtocolCore.kt:368,410`); JsonValueCodec joinToString encoder
  copies per nesting level. `appendingAcpSessionItem` full-list copy per chunk (fold into B1
  fix).
- **iOS:** per-byte KotlinByteArray interop on the WS path (~4 crossings/byte,
  `SharedKMPBridge.swift:962-977`) — memcpy marshal instead. Unbounded `events` AsyncStream +
  never-closed client in the DEBUG ACP path (`AppViewModel.swift:983-990`); debug collector
  doesn't coalesce. Thread-list refresh paginates everything per completed item
  (`AppViewModel.swift:2691, 2996`) — debounce + pageLimit. `cacheThreadDetail` +
  full-content equality compare run per delta before the didChange guard
  (`AppViewModel.swift:3230-3237`). Double JSON round-trip on main for turn/thread payloads
  (`AppViewModel.swift:4014-4020`). Fire-and-forget `Task { await c.close() }` in
  closeConnection (`:1997`) — await it. `withTimeout` doesn't propagate caller cancellation
  (`:4058-4087`) — use a task group. Connect reentrancy gate resettable by timeout
  (`:1480-1487`) — gate on generation. Dead `CodexSSHWebSocketTransport` byte handler spawns
  unordered per-chunk Tasks (`CodexSSHWebSocketTransport.swift:563-586`) — delete or fix
  before reuse. `@unchecked Sendable` transports with unsynchronized task vars.
- **Android:** `closed` flags not `@Volatile` (`AcpClient.kt:65`, `CodexAppServerClient.kt:55`).
  ACP `disconnects` SharedFlow replay=0 loses an emission before the collector subscribes
  (`AcpClient.kt:82-85` + `AppViewModel.kt:795`) — replay=1. `interruptActiveTurn`
  snapshot-then-clear can wipe an unanswered approval (`AppViewModel.kt:1745-1761`).
  Cancellation during `openAppServer`/`openRawExec` discards a connected client
  (`SshService.kt:165-190`; terminal path already hardened). `saveServers` snapshot writes can
  land out of order (`Repositories.kt:40`). Up to 1,000 serial `readThreadSummary` RPCs per
  connect (`AppViewModel.kt:1979-1995`). Single unstable `MobidexUiState` recomposes the whole
  tree per update; per-delta section instance churn defeats Compose skipping; streaming row
  re-parses its full markdown body per delta; autoscroll effect restarts per delta
  (`MobidexApp.kt:1325-1382, 1610-1655`). Debug ACP client/job never torn down on disconnect
  (`AppViewModel.kt:237-240, 661-663`). Terminal pendingOutput unbounded pre-ready
  (`MobidexApp.kt:664-678`). WS upgrade header read byte-at-a-time with full copy per byte
  (`SshService.kt:371-383`).

## Explicitly checked and cleared
Production WebSocket reassembly is NOT quadratic on either platform (stateful parser, offsets
advanced). Actor-internal continuation machinery in both iOS clients is correctly serialized
(no double-resume). iOS Codex eventTask generation guards are solid. Android eventJob/acpJob
cancelled on all connect/disconnect paths; LazyColumn keys correct; terminal session closed
via NonCancellable. Request-id generation safe in every live client. iOS threadDetailCache
TTL+cap fine. No `Channel.UNLIMITED` misuse. Keystore crypto thread-safe.

## Proposed fix plan
1. **Stability (small, high value):** A1 channel sends; C1–C3 ACP lifecycle guards/teardown;
   C4 request timeout + closed-recheck; C5 runBusy counter; C6 onCleared; C7 cancellation
   handler; Android `@Volatile` closed + disconnects replay=1.
2. **Streaming performance (one coordinated refactor):** B1 incremental projection +
   B2 string accumulation + publish conflation, off-main on Android; then B3 markdown cache,
   B4/B5 invalidation fixes, B6 off-main parse, B7 readLine.
3. **Memory hygiene:** D1 streamed uploads, D2 cache caps, D3 thumbnails + tmp cleanup,
   debug-path teardown, WS size caps, singleton id-counter removal.
