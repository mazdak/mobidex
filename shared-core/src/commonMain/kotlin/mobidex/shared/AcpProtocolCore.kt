package mobidex.shared

/**
 * Minimal ACP (Agent Client Protocol) support for shared-core.
 *
 * Designed to run over plain line-delimited JSON-RPC (the raw CodexLineTransport / openRawExec path).
 * Mirrors the structure and JsonValue patterns from CodexProtocolCore for KMP compatibility and simplicity.
 *
 * Focus for sketch: initialize, session lifecycle, prompt, and the session/update chunk kinds that
 * map directly to existing UI elements (CodexSessionItem + ConversationSection rendering).
 */

// --- Outbound requests (builders) ---

object AcpRpcRequests {
    fun initialize(
        id: Long,
        clientName: String = "mobidex",
        clientTitle: String = "Mobidex",
        clientVersion: String = "0.1.0",
        capabilities: Map<String, JsonValue> = emptyMap(),
    ): CodexRpcRequest = CodexRpcRequest( // reuse the wire type; ACP is standard JSON-RPC 2.0
        id = id,
        method = "initialize",
        params = jsonObject(
            linkedMapOf(
                "clientInfo" to jsonObject(
                    linkedMapOf(
                        "name" to jsonString(clientName),
                        "title" to jsonString(clientTitle),
                        "version" to jsonString(clientVersion),
                    )
                ),
                "capabilities" to jsonObject(capabilities),
            )
        ),
    )

    fun sessionNew(id: Long, cwd: String? = null, title: String? = null): CodexRpcRequest {
        val params = linkedMapOf<String, JsonValue>()
        cwd?.let { params["cwd"] = jsonString(it) }
        title?.let { params["title"] = jsonString(it) }
        // ACP typically returns a sessionId in the result; some impls accept initial context here.
        return CodexRpcRequest(id = id, method = "session/new", params = if (params.isEmpty()) null else jsonObject(params))
    }

    fun sessionPrompt(
        id: Long,
        sessionId: String,
        prompt: String,
        context: List<JsonValue> = emptyList(),
        // Future: files, images, etc. via richer prompt structure
    ): CodexRpcRequest {
        val promptValue = jsonObject(
            linkedMapOf(
                "text" to jsonString(prompt),
                // ACP often uses content blocks; start simple with text.
            )
        )
        val params = linkedMapOf<String, JsonValue>(
            "sessionId" to jsonString(sessionId),
            "prompt" to promptValue,
        )
        if (context.isNotEmpty()) params["context"] = jsonArray(context)
        return CodexRpcRequest(id = id, method = "session/prompt", params = jsonObject(params))
    }

    fun sessionInterrupt(id: Long, sessionId: String): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "session/interrupt",
        params = jsonObject(mapOf("sessionId" to jsonString(sessionId))),
    )
}

// --- Inbound classification for ACP over the same line transport ---

data class AcpRpcInboundEnvelope(
    val id: JsonValue? = null,
    val method: String? = null,
    val params: JsonValue? = null,
    val result: JsonValue? = null,
    val error: CodexRpcErrorInfo? = null, // reuse error shape
)

data class AcpRpcInboundClassification(
    val kind: String,
    val id: JsonValue? = null,
    val numericId: Long? = null,
    val method: String? = null,
    val params: JsonValue? = null,
    val result: JsonValue? = null,
    val error: CodexRpcErrorInfo? = null,
    // ACP-specific convenience
    val sessionUpdate: AcpSessionUpdate? = null,
)

data class AcpSessionUpdate(
    val sessionId: String?,
    val chunk: AcpContentChunk?,
    val rawParams: JsonValue?,
)

sealed interface AcpContentChunk {
    val type: String

    data class AgentMessageChunk(val delta: String, override val type: String = "agent_message_chunk") : AcpContentChunk
    data class AgentThoughtChunk(val delta: String, val summary: String? = null, override val type: String = "agent_thought_chunk") : AcpContentChunk
    data class ToolCall(
        val toolCallId: String?,
        val name: String?,
        val args: JsonValue?,
        val status: String? = null,
        override val type: String = "tool_call",
    ) : AcpContentChunk

    data class Plan(val title: String?, val content: String?, override val type: String = "plan") : AcpContentChunk
    data class ApprovalRequest(
        val requestId: JsonValue?,
        val title: String?,
        val detail: String?,
        override val type: String = "approval_request",
    ) : AcpContentChunk

    data class Other(val rawType: String, val raw: JsonValue?, override val type: String = rawType) : AcpContentChunk
}

object AcpProtocolCore {
    private val rpcCore = CodexRpcClientCore(initialRequestId = 1)

    fun nextRequest(method: String, params: JsonValue? = null): CodexRpcOutboundRequest =
        rpcCore.nextRequest(method, params)

    fun notificationLine(method: String, params: JsonValue? = null): String =
        rpcCore.notificationLine(method, params)

    fun resultLine(id: JsonValue, result: JsonValue): String =
        rpcCore.resultLine(id, result)

    fun classifyInbound(envelope: AcpRpcInboundEnvelope): AcpRpcInboundClassification? {
        val numericId = envelope.id?.responseIdValue
        val base = when {
            numericId != null && envelope.error != null -> AcpRpcInboundClassification(
                kind = "errorResponse", id = envelope.id, numericId = numericId, error = envelope.error
            )
            numericId != null && envelope.result != null -> AcpRpcInboundClassification(
                kind = "resultResponse", id = envelope.id, numericId = numericId, result = envelope.result
            )
            envelope.id != null && envelope.method != null -> AcpRpcInboundClassification(
                kind = "serverRequest", id = envelope.id, method = envelope.method, params = envelope.params
            )
            envelope.method != null -> {
                val update = if (envelope.method == "session/update") parseSessionUpdate(envelope.params) else null
                AcpRpcInboundClassification(
                    kind = if (update != null) "sessionUpdate" else "notification",
                    method = envelope.method,
                    params = envelope.params,
                    sessionUpdate = update,
                )
            }
            else -> null
        }
        return base
    }

    private fun parseSessionUpdate(params: JsonValue?): AcpSessionUpdate? {
        if (params == null) return null
        val sessionId = params["sessionId"]?.stringValue
        val chunkJson = params["chunk"] ?: params // some impls put chunk at top level of params
        val chunk = parseContentChunk(chunkJson)
        return AcpSessionUpdate(sessionId = sessionId, chunk = chunk, rawParams = params)
    }

    private fun parseContentChunk(json: JsonValue?): AcpContentChunk? {
        if (json == null) return null
        val t = json["type"]?.stringValue ?: json.stringValue ?: return null
        return when (t) {
            "agent_message_chunk", "agentMessageChunk", "message", "text" -> {
                val delta = json["delta"]?.stringValue ?: json["content"]?.stringValue ?: json["text"]?.stringValue ?: ""
                AcpContentChunk.AgentMessageChunk(delta = delta, type = t)
            }
            "agent_thought_chunk", "thought", "reasoning", "internal" -> {
                val delta = json["delta"]?.stringValue ?: json["content"]?.stringValue ?: ""
                val summary = json["summary"]?.stringValue
                AcpContentChunk.AgentThoughtChunk(delta = delta, summary = summary, type = t)
            }
            "tool_call", "toolCall", "function_call" -> {
                AcpContentChunk.ToolCall(
                    toolCallId = json["id"]?.stringValue ?: json["toolCallId"]?.stringValue,
                    name = json["name"]?.stringValue ?: json["tool"]?.stringValue,
                    args = json["args"] ?: json["arguments"],
                    status = json["status"]?.stringValue,
                    type = t,
                )
            }
            "plan", "plan_chunk" -> {
                AcpContentChunk.Plan(
                    title = json["title"]?.stringValue ?: json["name"]?.stringValue,
                    content = json["content"]?.stringValue ?: json["text"]?.stringValue ?: json["delta"]?.stringValue,
                    type = t,
                )
            }
            "approval_request", "permission_request", "approval" -> {
                AcpContentChunk.ApprovalRequest(
                    requestId = json["id"] ?: json["requestId"],
                    title = json["title"]?.stringValue,
                    detail = json["detail"]?.stringValue ?: json["message"]?.stringValue,
                    type = t,
                )
            }
            else -> AcpContentChunk.Other(rawType = t, raw = json, type = t)
        }
    }
}

// --- UI translation: ACP chunks → existing CodexSessionItem (so ConversationView + projection render them) ---

/**
 * Maps an ACP content chunk (from session/update) into the existing CodexSessionItem model.
 * This lets Grok/ACP responses flow through the same rich chat UI (Reasoning for thoughts,
 * AgentMessage for final text, ToolCall, Plan, etc.) with zero changes to ConversationView or
 * the KMP projection.
 *
 * Sketch version: simple, accumulating-friendly. Real version can carry more metadata (ids, status).
 */
fun AcpContentChunk.toCodexSessionItem(itemId: String = "acp-chunk"): CodexSessionItem? =
    when (this) {
        is AcpContentChunk.AgentMessageChunk -> {
            if (delta.isNotBlank()) CodexSessionItem.AgentMessage(id = itemId, text = delta) else null
        }
        is AcpContentChunk.AgentThoughtChunk -> {
            val summaryList = summary?.let { listOf(it) } ?: emptyList()
            val contentList = if (delta.isNotBlank()) listOf(delta) else emptyList()
            if (summaryList.isNotEmpty() || contentList.isNotEmpty()) {
                CodexSessionItem.Reasoning(id = itemId, summary = summaryList, content = contentList)
            } else null
        }
        is AcpContentChunk.ToolCall -> {
            val label = name ?: "tool"
            val detail = args?.let { JsonValueCodec.encode(it) } ?: status
            CodexSessionItem.ToolCall(id = itemId, label = label, status = status ?: "running", detail = detail)
        }
        is AcpContentChunk.Plan -> {
            val text = listOfNotNull(title, content).joinToString("\n").trim()
            if (text.isNotBlank()) CodexSessionItem.Plan(id = itemId, text = text) else null
        }
        is AcpContentChunk.ApprovalRequest,
        is AcpContentChunk.Other -> {
            // Surface as a generic agent event for now (UI already renders AgentEvent compactly).
            val label = this.type
            val detail = (this as? AcpContentChunk.ApprovalRequest)?.title ?: (this as? AcpContentChunk.Other)?.raw?.let { JsonValueCodec.encode(it) }
            CodexSessionItem.AgentEvent(id = itemId, label = label, status = "pending", detail = detail)
        }
    }

/**
 * Convenience: turn a full session/update classification into zero or more CodexSessionItems.
 * Useful for clients that want to feed the existing liveItems / projection pipeline directly.
 */
fun AcpRpcInboundClassification.toCodexSessionItems(): List<CodexSessionItem> {
    val update = sessionUpdate ?: return emptyList()
    // Callers doing live streaming should prefer stable IDs from chunk metadata when available.
    return listOfNotNull(update.chunk?.toCodexSessionItem())
}

// --- Minimal ACP client shell (KMP-friendly, transport-agnostic) ---

interface AcpLineTransport {
    // Reuse the existing neutral line interface in practice (CodexLineTransport on platforms).
    // This alias makes intent clear for ACP paths without forcing a rename yet.
}

class AcpClientCore(
    private val transport: /* CodexLineTransport or equivalent line pump */ Any, // placeholder until platform wiring
) {
    private val rpc = AcpProtocolCore
    private var nextId = 1L

    // The real client (in platform code) will:
    // - send lines via transport using rpc.nextRequest(...)
    // - read lines, parse with JsonValueCodec or platform JSON, classify with AcpProtocolCore.classifyInbound
    // - map interesting sessionUpdate chunks via .toCodexSessionItem() into the UI model
    // - handle server requests (approvals) by emitting Codex-style ServerRequest events

    // This core provides the reusable request builders + classification + mapping.
}
