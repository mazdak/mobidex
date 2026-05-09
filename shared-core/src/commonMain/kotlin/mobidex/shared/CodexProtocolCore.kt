package mobidex.shared

sealed interface JsonValue {
    data object Null : JsonValue
    data class BoolValue(val value: Boolean) : JsonValue
    data class IntValue(val value: Long) : JsonValue
    data class DoubleValue(val value: Double) : JsonValue
    data class StringValue(val value: String) : JsonValue
    data class ArrayValue(val value: List<JsonValue>) : JsonValue
    data class ObjectValue(val value: Map<String, JsonValue>) : JsonValue

    val intValue: Long?
        get() = (this as? IntValue)?.value

    val responseIdValue: Long?
        get() = when (this) {
            is IntValue -> value
            is StringValue -> value.toLongOrNull()
            else -> null
        }

    val stringValue: String?
        get() = (this as? StringValue)?.value

    operator fun get(key: String): JsonValue? = (this as? ObjectValue)?.value?.get(key)
}

fun jsonNull(): JsonValue = JsonValue.Null
fun jsonBool(value: Boolean): JsonValue = JsonValue.BoolValue(value)
fun jsonInt(value: Long): JsonValue = JsonValue.IntValue(value)
fun jsonDouble(value: Double): JsonValue = JsonValue.DoubleValue(value)
fun jsonString(value: String): JsonValue = JsonValue.StringValue(value)
fun jsonArray(value: List<JsonValue>): JsonValue = JsonValue.ArrayValue(value)
fun jsonObject(value: Map<String, JsonValue>): JsonValue = JsonValue.ObjectValue(value)

sealed interface CodexInputItem {
    val jsonValue: JsonValue

    data class Text(val text: String) : CodexInputItem {
        override val jsonValue: JsonValue = jsonObject(
            mapOf(
                "type" to jsonString("text"),
                "text" to jsonString(text),
                "text_elements" to jsonArray(emptyList()),
            )
        )
    }

    data class ImageUrl(val url: String) : CodexInputItem {
        override val jsonValue: JsonValue = jsonObject(
            mapOf(
                "type" to jsonString("image"),
                "url" to jsonString(url),
            )
        )
    }

    data class LocalImage(val path: String) : CodexInputItem {
        override val jsonValue: JsonValue = jsonObject(
            mapOf(
                "type" to jsonString("localImage"),
                "path" to jsonString(path),
            )
        )
    }

    data class Skill(val name: String, val path: String) : CodexInputItem {
        override val jsonValue: JsonValue = jsonObject(
            mapOf(
                "type" to jsonString("skill"),
                "name" to jsonString(name),
                "path" to jsonString(path),
            )
        )
    }

    data class Mention(val name: String, val path: String) : CodexInputItem {
        override val jsonValue: JsonValue = jsonObject(
            mapOf(
                "type" to jsonString("mention"),
                "name" to jsonString(name),
                "path" to jsonString(path),
            )
        )
    }
}

enum class CodexReasoningEffortOption(val label: String) {
    Low("Low"),
    Medium("Medium"),
    High("High"),
    XHigh("Extra High");

    val wireValue: String
        get() = when (this) {
            Low -> "low"
            Medium -> "medium"
            High -> "high"
            XHigh -> "xhigh"
        }
}

enum class CodexAccessMode(val label: String) {
    FullAccess("Full access"),
    WorkspaceWrite("Workspace"),
    ReadOnly("Read only"),
}

data class CodexTurnOptions(
    val reasoningEffort: CodexReasoningEffortOption? = null,
    val accessMode: CodexAccessMode? = null,
    val cwd: String? = null,
) {
    val jsonFields: Map<String, JsonValue>
        get() {
            val fields = linkedMapOf<String, JsonValue>()
            reasoningEffort?.let { fields["effort"] = jsonString(it.wireValue) }
            when (accessMode) {
                CodexAccessMode.FullAccess -> {
                    fields["approvalPolicy"] = jsonString("never")
                    fields["sandboxPolicy"] = jsonObject(mapOf("type" to jsonString("dangerFullAccess")))
                }
                CodexAccessMode.WorkspaceWrite -> {
                    fields["approvalPolicy"] = jsonString("on-request")
                    fields["sandboxPolicy"] = jsonObject(
                        mapOf(
                            "type" to jsonString("workspaceWrite"),
                            "writableRoots" to jsonArray(cwd?.let { listOf(jsonString(it)) } ?: emptyList()),
                            "networkAccess" to jsonBool(true),
                            "excludeTmpdirEnvVar" to jsonBool(false),
                            "excludeSlashTmp" to jsonBool(false),
                        )
                    )
                }
                CodexAccessMode.ReadOnly -> {
                    fields["approvalPolicy"] = jsonString("on-request")
                    fields["sandboxPolicy"] = jsonObject(
                        mapOf(
                            "type" to jsonString("readOnly"),
                            "networkAccess" to jsonBool(false),
                        )
                    )
                }
                null -> Unit
            }
            return fields
        }

    companion object {
        val Default = CodexTurnOptions()
    }
}

fun textInput(text: String): JsonValue = inputItems(listOf(CodexInputItem.Text(text)))
fun inputItems(items: List<CodexInputItem>): JsonValue = jsonArray(items.map { it.jsonValue })

data class CodexRpcRequest(
    val id: Long,
    val method: String,
    val params: JsonValue? = null,
    val jsonrpc: String = "2.0",
)

data class CodexRpcNotification(
    val method: String,
    val params: JsonValue? = null,
    val jsonrpc: String = "2.0",
)

data class CodexRpcResultResponse(
    val id: JsonValue,
    val result: JsonValue,
    val jsonrpc: String = "2.0",
)

data class CodexRpcErrorInfo(
    val code: Int,
    val message: String,
) {
    val canIgnoreForLoadedThreadSummary: Boolean
        get() {
            val normalizedMessage = message.lowercase()
            return normalizedMessage.contains("not found") ||
                normalizedMessage.contains("not loaded") ||
                normalizedMessage.contains("unknown thread") ||
                normalizedMessage.contains("no such thread")
        }
}

data class CodexRpcInboundEnvelope(
    val id: JsonValue? = null,
    val method: String? = null,
    val params: JsonValue? = null,
    val result: JsonValue? = null,
    val error: CodexRpcErrorInfo? = null,
)

data class CodexRpcOutboundRequest(
    val id: Long,
    val method: String,
    val line: String,
)

data class CodexRpcInboundClassification(
    val kind: String,
    val id: JsonValue? = null,
    val numericId: Long? = null,
    val method: String? = null,
    val params: JsonValue? = null,
    val result: JsonValue? = null,
    val error: CodexRpcErrorInfo? = null,
)

sealed interface CodexAppServerEvent {
    data class Notification(val method: String, val params: JsonValue?) : CodexAppServerEvent
    data class ServerRequest(val id: JsonValue, val method: String, val params: JsonValue?) : CodexAppServerEvent
    data class Disconnected(val message: String) : CodexAppServerEvent
}

data class GitDiffToRemoteResponse(
    val sha: String,
    val diff: String,
)

fun CodexRpcRequest.encodeJsonLine(): String {
    val fields = linkedMapOf<String, JsonValue>(
        "jsonrpc" to jsonString(jsonrpc),
        "id" to jsonInt(id),
        "method" to jsonString(method),
    )
    params?.let { fields["params"] = it }
    return JsonValueCodec.encode(jsonObject(fields))
}

fun CodexRpcNotification.encodeJsonLine(): String {
    val fields = linkedMapOf<String, JsonValue>(
        "jsonrpc" to jsonString(jsonrpc),
        "method" to jsonString(method),
    )
    params?.let { fields["params"] = it }
    return JsonValueCodec.encode(jsonObject(fields))
}

fun CodexRpcResultResponse.encodeJsonLine(): String = JsonValueCodec.encode(
    jsonObject(
        linkedMapOf(
            "jsonrpc" to jsonString(jsonrpc),
            "id" to id,
            "result" to result,
        )
    )
)

object CodexRpcRequests {
    val userFacingThreadSourceKinds: JsonValue = jsonArray(
        listOf("cli", "vscode", "exec", "appServer").map(::jsonString)
    )

    fun threadList(
        id: Long,
        cwd: String? = null,
        limit: Int = 80,
        cursor: String? = null,
        archived: Boolean = false,
    ): CodexRpcRequest {
        val params = linkedMapOf<String, JsonValue>(
            "limit" to jsonInt(limit.toLong()),
            "sortKey" to jsonString("updated_at"),
            "sortDirection" to jsonString("desc"),
            "archived" to jsonBool(archived),
            "sourceKinds" to userFacingThreadSourceKinds,
        )
        if (!cwd.isNullOrEmpty()) params["cwd"] = jsonString(cwd)
        cursor?.let { params["cursor"] = jsonString(it) }
        return CodexRpcRequest(id = id, method = "thread/list", params = jsonObject(params))
    }

    fun initialize(id: Long, name: String, title: String, version: String): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "initialize",
        params = jsonObject(
            linkedMapOf(
                "clientInfo" to jsonObject(
                    linkedMapOf(
                        "name" to jsonString(name),
                        "title" to jsonString(title),
                        "version" to jsonString(version),
                    )
                ),
                "capabilities" to jsonObject(
                    linkedMapOf("experimentalApi" to jsonBool(true))
                ),
            )
        ),
    )

    fun loadedThreadList(id: Long, limit: Int = 200): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "thread/loaded/list",
        params = jsonObject(linkedMapOf("limit" to jsonInt(limit.toLong()))),
    )

    fun readThread(id: Long, threadId: String, includeTurns: Boolean): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "thread/read",
        params = jsonObject(
            linkedMapOf(
                "threadId" to jsonString(threadId),
                "includeTurns" to jsonBool(includeTurns),
            )
        ),
    )

    fun resumeThread(id: Long, threadId: String): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "thread/resume",
        params = jsonObject(linkedMapOf("threadId" to jsonString(threadId))),
    )

    fun startThread(id: Long, cwd: String? = null): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "thread/start",
        params = jsonObject(cwd?.let { linkedMapOf("cwd" to jsonString(it)) } ?: linkedMapOf()),
    )

    fun startTurn(
        id: Long,
        threadId: String,
        input: List<CodexInputItem>,
        options: CodexTurnOptions = CodexTurnOptions.Default,
    ): CodexRpcRequest {
        val params = linkedMapOf<String, JsonValue>()
        params.putAll(options.jsonFields)
        params["threadId"] = jsonString(threadId)
        params["input"] = inputItems(input)
        return CodexRpcRequest(id = id, method = "turn/start", params = jsonObject(params))
    }

    fun gitDiffToRemote(id: Long, cwd: String): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "gitDiffToRemote",
        params = jsonObject(mapOf("cwd" to jsonString(cwd))),
    )

    fun interruptTurn(id: Long, threadId: String, turnId: String): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "turn/interrupt",
        params = jsonObject(
            linkedMapOf(
                "threadId" to jsonString(threadId),
                "turnId" to jsonString(turnId),
            )
        ),
    )

    fun steerTurn(
        id: Long,
        threadId: String,
        expectedTurnId: String,
        input: List<CodexInputItem>,
    ): CodexRpcRequest = CodexRpcRequest(
        id = id,
        method = "turn/steer",
        params = jsonObject(
            linkedMapOf(
                "threadId" to jsonString(threadId),
                "expectedTurnId" to jsonString(expectedTurnId),
                "input" to inputItems(input),
            )
        ),
    )
}

object CodexRpcNotifications {
    fun initialized(): CodexRpcNotification = CodexRpcNotification(method = "initialized")
}

class CodexRpcClientCore(
    initialRequestId: Long = 1,
) {
    private var nextRequestId = initialRequestId

    fun nextRequest(method: String, params: JsonValue? = null): CodexRpcOutboundRequest {
        val id = nextRequestId
        nextRequestId += 1
        return CodexRpcOutboundRequest(
            id = id,
            method = method,
            line = CodexRpcRequest(id = id, method = method, params = params).encodeJsonLine(),
        )
    }

    fun notificationLine(method: String, params: JsonValue? = null): String =
        CodexRpcNotification(method = method, params = params).encodeJsonLine()

    fun resultLine(id: JsonValue, result: JsonValue): String =
        CodexRpcResultResponse(id = id, result = result).encodeJsonLine()

    fun classifyInbound(envelope: CodexRpcInboundEnvelope): CodexRpcInboundClassification? {
        val id = envelope.id
        val numericId = id?.responseIdValue
        return when {
            numericId != null && envelope.error != null -> CodexRpcInboundClassification(
                kind = "errorResponse",
                id = id,
                numericId = numericId,
                error = envelope.error,
            )
            numericId != null && envelope.result != null -> CodexRpcInboundClassification(
                kind = "resultResponse",
                id = id,
                numericId = numericId,
                result = envelope.result,
            )
            id != null && envelope.method != null -> CodexRpcInboundClassification(
                kind = "serverRequest",
                id = id,
                method = envelope.method,
                params = envelope.params,
            )
            envelope.method != null -> CodexRpcInboundClassification(
                kind = "notification",
                method = envelope.method,
                params = envelope.params,
            )
            else -> null
        }
    }
}

object JsonValueCodec {
    fun encode(value: JsonValue): String = when (value) {
        JsonValue.Null -> "null"
        is JsonValue.BoolValue -> if (value.value) "true" else "false"
        is JsonValue.IntValue -> value.value.toString()
        is JsonValue.DoubleValue -> value.value.toString()
        is JsonValue.StringValue -> encodeString(value.value)
        is JsonValue.ArrayValue -> value.value.joinToString(separator = ",", prefix = "[", postfix = "]") { encode(it) }
        is JsonValue.ObjectValue -> value.value.entries.joinToString(separator = ",", prefix = "{", postfix = "}") { (key, item) ->
            "${encodeString(key)}:${encode(item)}"
        }
    }

    private fun encodeString(value: String): String {
        val result = StringBuilder(value.length + 2)
        result.append('"')
        for (character in value) {
            when (character) {
                '"' -> result.append("\\\"")
                '\\' -> result.append("\\\\")
                '\b' -> result.append("\\b")
                '\u000C' -> result.append("\\f")
                '\n' -> result.append("\\n")
                '\r' -> result.append("\\r")
                '\t' -> result.append("\\t")
                else -> {
                    if (character.code < 0x20) {
                        result.append("\\u")
                        result.append(character.code.toString(16).padStart(4, '0'))
                    } else {
                        result.append(character)
                    }
                }
            }
        }
        result.append('"')
        return result.toString()
    }
}
