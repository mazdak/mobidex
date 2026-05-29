package mobidex.android.service

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonElement
import java.util.concurrent.atomic.AtomicLong
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mobidex.shared.AcpProtocolCore
import mobidex.shared.AcpRpcInboundEnvelope
import mobidex.shared.AcpRpcRequests
import mobidex.shared.CodexRpcRequest
import mobidex.shared.CodexSessionItem
import mobidex.shared.JsonValue
import mobidex.shared.encodeJsonLine
import mobidex.shared.toCodexSessionItems

/**
 * Thin ACP client for driving Grok agents (via `grok agent stdio` or equivalent) over a raw line transport.
 *
 * Designed for the Android/Kotlin side of the Mobidex ACP sketch.
 * - Uses CodexLineTransport (obtained via SshService.openRawExec + RemoteAcpCommand.stdioCommand)
 * - Leverages shared AcpProtocolCore for request building, inbound classification, and the critical
 *   chunk-to-CodexSessionItem mapper (so Grok thoughts render as Reasoning, messages as AgentMessage,
 *   tools/approvals/plans via existing ConversationSection UI with zero duplication).
 * - Minimal surface for initialize / session lifecycle / prompt.
 *
 * This is intentionally a sketch implementation: correlation + streaming via the shared mapper.
 * Later iterations can factor more into shared-core (AcpClientCore) and add iOS parity + approval flows.
 */
class AcpGrokClient(
    private val transport: CodexLineTransport,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val itemsChannel = Channel<CodexSessionItem>(Channel.BUFFERED)
    private val pending = mutableMapOf<Long, CompletableDeferred<JsonElement>>()
    private val pendingMutex = Mutex()
    private var closed = false
    private var currentSessionId: String? = null
    private val idCounter = AtomicLong(1)

    /** Emits mapped CodexSessionItem instances (AgentMessage, Reasoning for thoughts, ToolCall, Plan, AgentEvent for approvals, etc.). */
    val sessionItems: Flow<CodexSessionItem> = itemsChannel.receiveAsFlow()

    init {
        scope.launch { readLoop() }
    }

    suspend fun initialize() {
        check(!closed) { "ACP client is closed." }
        val req = AcpRpcRequests.initialize(id = nextId())
        // Fire the request; for sketch we don't strictly await the initialize result before proceeding.
        transport.sendLine(req.encodeJsonLine())
        // Many ACP servers also expect a client "initialized" notification after receiving the result.
        // We keep it simple here; real impl can await the response first.
    }

    /**
     * Creates a new ACP session and returns its sessionId.
     * The result from `session/new` is expected to contain a "sessionId" (or "id") field.
     */
    suspend fun createSession(cwd: String? = null, title: String? = null): String {
        check(!closed) { "ACP client is closed." }
        val req = AcpRpcRequests.sessionNew(id = nextId(), cwd = cwd, title = title)
        val result = sendRequestAndAwait(req)
        val sid = extractSessionId(result) ?: error("session/new did not return a sessionId in result: $result")
        currentSessionId = sid
        return sid
    }

    suspend fun sendPrompt(sessionId: String, text: String) {
        check(!closed) { "ACP client is closed." }
        val req = AcpRpcRequests.sessionPrompt(id = nextId(), sessionId = sessionId, prompt = text)
        // For streaming agents, the prompt request itself often returns quickly (or with an ack),
        // while content arrives via session/update notifications.
        sendRequestAndAwait(req) // best-effort await; many impls return immediately
    }

    suspend fun interrupt(sessionId: String) {
        check(!closed) { "ACP client is closed." }
        val req = AcpRpcRequests.sessionInterrupt(id = nextId(), sessionId = sessionId)
        transport.sendLine(req.encodeJsonLine())
    }

    suspend fun close() {
        if (closed) return
        closed = true
        failAllPending(IllegalStateException("ACP client closed."))
        transport.close()
        itemsChannel.close()
    }

    private fun nextId(): Long = idCounter.getAndIncrement() // monotonic to avoid collisions on rapid initialize + session/new (codex review P2)

    private suspend fun sendRequestAndAwait(req: mobidex.shared.CodexRpcRequest): JsonElement {
        val waiter = CompletableDeferred<JsonElement>()
        pendingMutex.withLock {
            pending[req.id] = waiter
        }
        try {
            transport.sendLine(req.encodeJsonLine())
        } catch (e: Throwable) {
            pendingMutex.withLock { pending.remove(req.id) }
            waiter.completeExceptionally(e)
            throw e
        }
        return waiter.await()
    }

    private suspend fun readLoop() {
        try {
            transport.inboundLines.collect { line ->
                if (line.isBlank()) return@collect
                val message = AppJson.parseToJsonElement(line).jsonObject
                val envelope = message.toAcpEnvelope()
                val classification = AcpProtocolCore.classifyInbound(envelope) ?: return@collect

                when (classification.kind) {
                    "errorResponse" -> {
                        val id = classification.numericId ?: return@collect
                        val err = classification.error?.message ?: "ACP error"
                        pendingMutex.withLock { pending.remove(id) }?.completeExceptionally(IllegalStateException(err))
                    }
                    "resultResponse" -> {
                        val id = classification.numericId ?: return@collect
                        val resultEl = classification.result?.toJsonElement() ?: return@collect
                        pendingMutex.withLock { pending.remove(id) }?.complete(resultEl)
                    }
                    "sessionUpdate" -> {
                        // This is the key path: Grok chunks → existing UI model via the mapper added for the user's requirement.
                        val items = classification.toCodexSessionItems()
                        items.forEach { item ->
                            itemsChannel.trySend(item)
                        }
                    }
                    "serverRequest" -> {
                        // ACP interactive approval / permission request.
                        // For sketch: surface as a generic AgentEvent so the existing UI can show it.
                        // Real impl will later call back with approval response using resultLine.
                        val detail = classification.params?.let { JsonValueCodec.encode(it) } // reuse if available, else toString
                        val ev = CodexSessionItem.AgentEvent(
                            id = "acp-approval-${System.currentTimeMillis()}",
                            label = classification.method ?: "approvalRequest",
                            status = "pending",
                            detail = detail,
                        )
                        itemsChannel.trySend(ev)
                    }
                    else -> {
                        // Ignore other notifications for minimal sketch.
                    }
                }
            }
            if (!closed) disconnect("ACP transport stream ended.")
        } catch (error: Throwable) {
            if (!closed) disconnect(error.message ?: "ACP read error: ${error::class.simpleName}")
        }
    }

    private fun disconnect(message: String) {
        closed = true
        failAllPending(IllegalStateException(message))
        itemsChannel.trySend(
            CodexSessionItem.AgentEvent(
                id = "acp-disconnect-${System.currentTimeMillis()}",
                label = "disconnected",
                status = "error",
                detail = message,
            )
        )
        itemsChannel.close()
    }

    private fun failAllPending(error: Throwable) {
        // Shutdown path: use a cheap synchronized snapshot instead of suspending Mutex.withLock.
        val toFail = synchronized(pending) {
            val snapshot = pending.toMap()
            pending.clear()
            snapshot
        }
        toFail.values.forEach { it.completeExceptionally(error) }
    }

    private fun extractSessionId(result: JsonElement): String? {
        val obj = result as? JsonObject ?: return null
        return obj["sessionId"]?.jsonPrimitive?.contentOrNull
            ?: obj["session_id"]?.jsonPrimitive?.contentOrNull
            ?: obj["id"]?.jsonPrimitive?.contentOrNull
            ?: obj["session"]?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull
    }

    private fun JsonObject.toAcpEnvelope(): AcpRpcInboundEnvelope =
        AcpRpcInboundEnvelope(
            id = this["id"]?.toSharedJsonValue(),
            method = this["method"]?.jsonPrimitive?.contentOrNull,
            params = this["params"]?.toSharedJsonValue(),
            result = this["result"]?.toSharedJsonValue(),
            error = this["error"]?.jsonObject?.let { err ->
                mobidex.shared.CodexRpcErrorInfo(
                    code = err["code"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0,
                    message = err["message"]?.jsonPrimitive?.contentOrNull ?: "ACP error",
                )
            },
        )
}

// Small helper to avoid pulling in extra shared codec if not public.
private object JsonValueCodec {
    fun encode(v: JsonValue): String = v.toString() // sufficient for sketch logging/detail
}
