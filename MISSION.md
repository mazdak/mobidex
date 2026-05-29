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

**Critical decisions logged:**
- Decision: Reuse/extend existing raw exec transport scaffolding + CodexLineTransport abstraction rather than new parallel AcpTransport (simpler, less code, already documented for this use).
- Decision: New `RemoteAcpCommand.kt` (separate from codex command file) for ACP launch command generation — clean separation, obvious naming.
- (Future) Backend type on ServerRecord or dedicated "Grok Agents" section in server list for UX.

**Current phase:** Initial sketch/implementation per "Yeah sketch it" request. Focus on command gen + minimal AcpClient handshake + one smoke path.
