package mobidex.shared

/**
 * Minimal ACP (Agent Client Protocol, agentclientprotocol.com) support for shared-core.
 *
 * Designed to run over plain line-delimited JSON-RPC (the raw CodexLineTransport / openRawExec path).
 * Mirrors the structure and JsonValue patterns from CodexProtocolCore for KMP compatibility and simplicity.
 *
 * Outbound requests follow the ACP v1 spec shapes (protocolVersion/clientCapabilities, cwd+mcpServers,
 * content-block prompts, session/cancel notification) so spec-strict agents such as
 * `@zed-industries/claude-code-acp` validate them. Inbound `session/update` parsing accepts both the
 * spec shape (`params.update` with a `sessionUpdate` discriminator) and the looser legacy shapes
 * (`params.chunk` with a `type` discriminator) that earlier agents emitted.
 */

// --- Outbound requests (builders) ---

object AcpRpcRequests {
    /** ACP protocol major version this client speaks. */
    const val PROTOCOL_VERSION = 1L

    fun initialize(
        id: Long,
        clientName: String = "mobidex",
        clientTitle: String = "Mobidex",
        clientVersion: String = "0.1.0",
    ): CodexRpcRequest = CodexRpcRequest( // reuse the wire type; ACP is standard JSON-RPC 2.0
        id = id,
        method = "initialize",
        params = jsonObject(
            linkedMapOf(
                "protocolVersion" to jsonInt(PROTOCOL_VERSION),
                // The agent runs on the remote host where the files live, so we deliberately do not
                // offer client-side fs or terminal capabilities; spec agents then degrade gracefully
                // and perform file/shell operations themselves.
                "clientCapabilities" to jsonObject(
                    linkedMapOf(
                        "fs" to jsonObject(
                            linkedMapOf(
                                "readTextFile" to jsonBool(false),
                                "writeTextFile" to jsonBool(false),
                            )
                        ),
                        "terminal" to jsonBool(false),
                    )
                ),
                "clientInfo" to jsonObject(
                    linkedMapOf(
                        "name" to jsonString(clientName),
                        "title" to jsonString(clientTitle),
                        "version" to jsonString(clientVersion),
                    )
                ),
            )
        ),
    )

    fun sessionNew(id: Long, cwd: String, title: String? = null): CodexRpcRequest {
        val params = linkedMapOf<String, JsonValue>(
            // Spec requires cwd (absolute path) and mcpServers on session/new.
            "cwd" to jsonString(cwd),
            "mcpServers" to jsonArray(emptyList()),
        )
        title?.let { params["title"] = jsonString(it) }
        return CodexRpcRequest(id = id, method = "session/new", params = jsonObject(params))
    }

    fun sessionPrompt(
        id: Long,
        sessionId: String,
        prompt: String,
        context: List<JsonValue> = emptyList(),
        // Future: files, images, etc. via richer content blocks
    ): CodexRpcRequest {
        val params = linkedMapOf<String, JsonValue>(
            "sessionId" to jsonString(sessionId),
            // Spec shape: prompt is an array of content blocks.
            "prompt" to jsonArray(
                listOf(
                    jsonObject(
                        linkedMapOf(
                            "type" to jsonString("text"),
                            "text" to jsonString(prompt),
                        )
                    )
                )
            ),
        )
        if (context.isNotEmpty()) params["context"] = jsonArray(context)
        return CodexRpcRequest(id = id, method = "session/prompt", params = jsonObject(params))
    }

    /** Spec cancellation is the `session/cancel` notification (no id, no response). */
    fun sessionCancelParams(sessionId: String): JsonValue =
        jsonObject(mapOf("sessionId" to jsonString(sessionId)))

    /**
     * `authenticate` with one of the method ids advertised in the initialize result.
     * Some agents (grok) require this before session/new even when already logged in on the host.
     */
    fun authenticate(id: Long, methodId: String): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "authenticate",
        params = jsonObject(mapOf("methodId" to jsonString(methodId))),
    )
}

/** Extracts the advertised auth method ids from an `initialize` result (`authMethods[].id`). */
fun acpAuthMethodIds(initializeResult: JsonValue?): List<String> =
    ((initializeResult?.get("authMethods") as? JsonValue.ArrayValue)?.value.orEmpty())
        .mapNotNull { it["id"]?.stringValue }

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

    data class ToolCallUpdate(
        val toolCallId: String?,
        val name: String?,
        val status: String?,
        val output: String?,
        override val type: String = "tool_call_update",
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

// --- session/request_permission (agent -> client request) support ---

data class AcpPermissionOption(val optionId: String, val name: String?, val kind: String?)

data class AcpPermissionRequest(
    val sessionId: String?,
    val title: String?,
    val detail: String?,
    val options: List<AcpPermissionOption>,
)

object AcpProtocolCore {
    const val SESSION_UPDATE_METHOD = "session/update"
    const val PERMISSION_REQUEST_METHOD = "session/request_permission"

    /** JSON-RPC error code agents use for "authenticate first" (ACP auth_required). */
    const val AUTH_REQUIRED_ERROR_CODE = -32000

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
            envelope.id != null && envelope.method != null -> AcpRpcInboundClassification(
                kind = "serverRequest", id = envelope.id, method = envelope.method, params = envelope.params
            )
            numericId != null && envelope.error != null -> AcpRpcInboundClassification(
                kind = "errorResponse", id = envelope.id, numericId = numericId, error = envelope.error
            )
            // A response with neither error nor result is a spec-legal void result ("result": null);
            // platform decoders may drop the explicit null, so classify on the id alone.
            numericId != null -> AcpRpcInboundClassification(
                kind = "resultResponse", id = envelope.id, numericId = numericId, result = envelope.result ?: JsonValue.Null
            )
            envelope.method != null -> {
                val update = if (envelope.method == SESSION_UPDATE_METHOD) parseSessionUpdate(envelope.params) else null
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

    /** Human-readable error text; turns ACP auth_required into actionable guidance. */
    fun readableError(code: Int, message: String): String =
        if (code == AUTH_REQUIRED_ERROR_CODE) {
            "The agent requires authentication on the host. Log in on the server " +
                "(e.g. run the agent's login command, such as `claude /login`, or export its API key " +
                "in the remote shell), then reconnect. ($message)"
        } else {
            message
        }

    /** Parses `session/request_permission` params into a displayable summary + selectable options. */
    fun parsePermissionRequest(params: JsonValue?): AcpPermissionRequest {
        val toolCall = params?.get("toolCall")
        val title = toolCall?.get("title")?.stringValue
            ?: toolCall?.get("kind")?.stringValue
            ?: "Permission required"
        val detail = toolCall?.get("rawInput")?.let { JsonValueCodec.encode(it) }
        val options = ((params?.get("options") as? JsonValue.ArrayValue)?.value.orEmpty()).mapNotNull { option ->
            val optionId = option["optionId"]?.stringValue ?: return@mapNotNull null
            AcpPermissionOption(
                optionId = optionId,
                name = option["name"]?.stringValue,
                kind = option["kind"]?.stringValue,
            )
        }
        return AcpPermissionRequest(
            sessionId = params?.get("sessionId")?.stringValue,
            title = title,
            detail = detail,
            options = options,
        )
    }

    /**
     * Picks the option to answer with for a simple accept/decline UI:
     * accept prefers `allow_once` (then any allow), decline prefers `reject_once` (then any reject).
     */
    fun choosePermissionOptionId(params: JsonValue?, accept: Boolean): String? {
        val options = parsePermissionRequest(params).options
        val preferred = if (accept) "allow_once" else "reject_once"
        val prefix = if (accept) "allow" else "reject"
        return options.firstOrNull { it.kind == preferred }?.optionId
            ?: options.firstOrNull { it.kind?.startsWith(prefix) == true }?.optionId
    }

    fun permissionSelectedResult(optionId: String): JsonValue = jsonObject(
        mapOf(
            "outcome" to jsonObject(
                linkedMapOf(
                    "outcome" to jsonString("selected"),
                    "optionId" to jsonString(optionId),
                )
            )
        )
    )

    fun permissionCancelledResult(): JsonValue = jsonObject(
        mapOf("outcome" to jsonObject(mapOf("outcome" to jsonString("cancelled"))))
    )

    private fun parseSessionUpdate(params: JsonValue?): AcpSessionUpdate? {
        if (params == null) return null
        val sessionId = params["sessionId"]?.stringValue
        // Spec shape nests the variant under "update"; legacy agents used "chunk" or top-level params.
        val chunkJson = params["update"] ?: params["chunk"] ?: params
        val chunk = parseContentChunk(chunkJson)
        return AcpSessionUpdate(sessionId = sessionId, chunk = chunk, rawParams = params)
    }

    private fun parseContentChunk(json: JsonValue?): AcpContentChunk? {
        if (json == null) return null
        val t = json["sessionUpdate"]?.stringValue // spec discriminator
            ?: json["type"]?.stringValue // legacy discriminator
            ?: json.stringValue
            ?: return null
        return when (t) {
            "agent_message_chunk", "agentMessageChunk", "message", "text" -> {
                AcpContentChunk.AgentMessageChunk(delta = textContent(json), type = t)
            }
            "agent_thought_chunk", "thought", "reasoning", "internal" -> {
                AcpContentChunk.AgentThoughtChunk(
                    delta = textContent(json),
                    summary = json["summary"]?.stringValue,
                    type = t,
                )
            }
            "tool_call", "toolCall", "function_call" -> {
                AcpContentChunk.ToolCall(
                    toolCallId = json["toolCallId"]?.stringValue ?: json["id"]?.stringValue,
                    name = json["title"]?.stringValue ?: json["name"]?.stringValue ?: json["tool"]?.stringValue
                        ?: json["kind"]?.stringValue,
                    args = json["rawInput"] ?: json["args"] ?: json["arguments"],
                    status = json["status"]?.stringValue,
                    type = t,
                )
            }
            "tool_call_update" -> {
                AcpContentChunk.ToolCallUpdate(
                    toolCallId = json["toolCallId"]?.stringValue,
                    name = json["title"]?.stringValue,
                    status = json["status"]?.stringValue, // null when the update only carries output
                    output = toolCallOutput(json),
                    type = t,
                )
            }
            "plan", "plan_chunk" -> {
                AcpContentChunk.Plan(
                    title = json["title"]?.stringValue ?: json["name"]?.stringValue,
                    content = planContent(json),
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

    /** Extracts text from spec content blocks (`content: {type:"text", text}`), or legacy flat fields. */
    private fun textContent(json: JsonValue): String =
        json["content"]?.let { it["text"]?.stringValue ?: it.stringValue }
            ?: json["delta"]?.stringValue
            ?: json["text"]?.stringValue
            ?: ""

    /** Best-effort text from a tool_call_update `content` array (ToolCallContent blocks) or rawOutput. */
    private fun toolCallOutput(json: JsonValue): String? {
        val fromBlocks = (json["content"] as? JsonValue.ArrayValue)?.value
            ?.mapNotNull { block -> block["content"]?.get("text")?.stringValue ?: block["text"]?.stringValue }
            ?.filter { it.isNotBlank() }
            ?.joinToString("\n")
            ?.ifBlank { null }
        return fromBlocks ?: json["rawOutput"]?.let { it.stringValue ?: JsonValueCodec.encode(it) }
    }

    /** Renders spec plan entries (`entries: [{content, status, ...}]`) or legacy flat content as text. */
    private fun planContent(json: JsonValue): String? {
        val entries = (json["entries"] as? JsonValue.ArrayValue)?.value
        if (entries != null) {
            return entries.mapNotNull { entry ->
                val content = entry["content"]?.stringValue ?: return@mapNotNull null
                val status = entry["status"]?.stringValue
                if (status != null) "[$status] $content" else content
            }.joinToString("\n").ifBlank { null }
        }
        return json["content"]?.stringValue ?: json["text"]?.stringValue ?: json["delta"]?.stringValue
    }
}

// --- UI translation: ACP chunks → existing CodexSessionItem (so ConversationView + projection render them) ---

/**
 * Maps an ACP content chunk (from session/update) into the existing CodexSessionItem model.
 * This lets ACP agent responses flow through the same rich chat UI (Reasoning for thoughts,
 * AgentMessage for final text, ToolCall, Plan, etc.) with zero changes to ConversationView or
 * the KMP projection.
 *
 * Unknown variants (`Other`, e.g. available_commands_update / current_mode_update) intentionally
 * produce no UI item.
 */
fun AcpContentChunk.toCodexSessionItem(itemId: String = "acp-chunk"): CodexSessionItem? =
    when (this) {
        is AcpContentChunk.AgentMessageChunk -> {
            if (delta.isNotEmpty()) CodexSessionItem.AgentMessage(id = itemId, text = delta) else null
        }
        is AcpContentChunk.AgentThoughtChunk -> {
            val summaryList = summary?.let { listOf(it) } ?: emptyList()
            val contentList = if (delta.isNotEmpty()) listOf(delta) else emptyList()
            if (summaryList.isNotEmpty() || contentList.isNotEmpty()) {
                CodexSessionItem.Reasoning(id = itemId, summary = summaryList, content = contentList)
            } else null
        }
        is AcpContentChunk.ToolCall -> {
            val label = name ?: "tool"
            val detail = args?.let { JsonValueCodec.encode(it) } ?: status
            CodexSessionItem.ToolCall(id = itemId, label = label, status = status ?: "running", detail = detail)
        }
        is AcpContentChunk.ToolCallUpdate -> {
            // Empty status = "this update did not carry a status"; the accumulator keeps the
            // existing card's status in that case instead of regressing a completed card.
            CodexSessionItem.ToolCall(
                id = itemId,
                label = name ?: "tool",
                status = status ?: "",
                detail = output,
            )
        }
        is AcpContentChunk.Plan -> {
            val text = listOfNotNull(title, content).joinToString("\n").trim()
            if (text.isNotBlank()) CodexSessionItem.Plan(id = itemId, text = text) else null
        }
        is AcpContentChunk.ApprovalRequest -> {
            CodexSessionItem.AgentEvent(
                id = itemId,
                label = title ?: type,
                status = "pending",
                detail = detail,
            )
        }
        is AcpContentChunk.Other -> null
    }

/**
 * Convenience: turn a full session/update classification into zero or more CodexSessionItems.
 * Uses stable per-kind ids (and the toolCallId for tool calls) so [appendingAcpSessionItem]
 * can coalesce streamed deltas and apply tool_call_update to the original tool card.
 */
fun AcpRpcInboundClassification.toCodexSessionItems(): List<CodexSessionItem> {
    val chunk = sessionUpdate?.chunk ?: return emptyList()
    val itemId = when (chunk) {
        is AcpContentChunk.AgentMessageChunk -> "acp-message"
        is AcpContentChunk.AgentThoughtChunk -> "acp-thought"
        is AcpContentChunk.ToolCall -> chunk.toolCallId ?: "acp-tool"
        is AcpContentChunk.ToolCallUpdate -> chunk.toolCallId ?: "acp-tool"
        is AcpContentChunk.Plan -> "acp-plan"
        else -> "acp-chunk"
    }
    return listOfNotNull(chunk.toCodexSessionItem(itemId))
}

/**
 * Streaming accumulator for mapped ACP items:
 * - consecutive AgentMessage / Reasoning deltas merge into the previous item (one chat bubble per turn)
 * - ToolCall items update-in-place by id (tool_call_update resolves the original card)
 * - Plan items replace the previous plan with the same id
 * - anything else appends
 */
fun List<CodexSessionItem>.appendingAcpSessionItem(item: CodexSessionItem): List<CodexSessionItem> {
    val last = lastOrNull()
    when (item) {
        is CodexSessionItem.AgentMessage -> {
            if (last is CodexSessionItem.AgentMessage && last.id == item.id) {
                return dropLast(1) + last.copy(text = last.text + item.text)
            }
        }
        is CodexSessionItem.Reasoning -> {
            if (last is CodexSessionItem.Reasoning && last.id == item.id) {
                val mergedContent = (last.content + item.content)
                    .joinToString("")
                    .let { if (it.isEmpty()) emptyList() else listOf(it) }
                return dropLast(1) + last.copy(
                    summary = (last.summary + item.summary).distinct(),
                    content = mergedContent,
                )
            }
        }
        is CodexSessionItem.ToolCall -> {
            val index = indexOfLast { it is CodexSessionItem.ToolCall && it.id == item.id }
            if (index >= 0) {
                val existing = this[index] as CodexSessionItem.ToolCall
                val merged = existing.copy(
                    label = if (item.label == "tool") existing.label else item.label,
                    status = item.status.ifEmpty { existing.status },
                    detail = item.detail ?: existing.detail,
                )
                return toMutableList().apply { this[index] = merged }
            }
            if (item.status.isEmpty()) {
                return this + item.copy(status = "running")
            }
        }
        is CodexSessionItem.Plan -> {
            val index = indexOfLast { it is CodexSessionItem.Plan && it.id == item.id }
            if (index >= 0) {
                return toMutableList().apply { this[index] = item }
            }
        }
        else -> Unit
    }
    return this + item
}
