package mobidex.android.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonElement
import java.util.concurrent.atomic.AtomicLong
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mobidex.shared.AcpProtocolCore
import mobidex.shared.AcpRpcInboundEnvelope
import mobidex.shared.AcpRpcRequests
import mobidex.shared.CodexSessionItem
import mobidex.shared.JsonValue
import mobidex.shared.AcpSessionModels
import mobidex.shared.acpAuthMethodIds
import mobidex.shared.acpSessionModels
import mobidex.shared.encodeJsonLine
import mobidex.shared.toCodexSessionItems

/** An agent -> client JSON-RPC request (e.g. `session/request_permission`) awaiting a response. */
data class AcpServerRequest(
    val id: JsonValue,
    val method: String,
    val params: JsonValue?,
)

/** A created ACP session: its id plus the model state the agent advertised (null = no switching). */
data class AcpSession(
    val sessionId: String,
    val models: AcpSessionModels?,
)

/** JSON-RPC error from the agent, with the code preserved for auth_required handling. */
class AcpRpcException(val code: Int, message: String) : Exception(message)

/**
 * Thin ACP client for driving spec-compliant stdio agents (`grok agent stdio`,
 * `bunx @zed-industries/claude-code-acp`, ...) over a raw line transport.
 *
 * - Uses CodexLineTransport (obtained via SshService.openRawExec + RemoteAcpCommand.shellCommand)
 * - Leverages shared AcpProtocolCore for request building, inbound classification, and the
 *   chunk-to-CodexSessionItem mapper (so agent thoughts render as Reasoning, messages as
 *   AgentMessage, tools/plans via the existing ConversationSection UI with zero duplication).
 * - Authenticates on demand: when session/new fails with auth_required, retries once after
 *   `authenticate` with the first method the agent advertised (grok requires this even when
 *   logged in on the host).
 * - Surfaces agent -> client requests (permission prompts) on [serverRequests] for the
 *   ViewModel to answer via [respondToServerRequest].
 */
class AcpClient(
    private val transport: CodexLineTransport,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val itemsChannel = Channel<CodexSessionItem>(Channel.BUFFERED)
    private val serverRequestChannel = Channel<AcpServerRequest>(Channel.BUFFERED)
    private val pending = mutableMapOf<Long, CompletableDeferred<JsonElement>>()
    private val pendingMutex = Mutex()

    @Volatile
    private var closed = false
    private var currentSessionId: String? = null
    private val idCounter = AtomicLong(1)
    private var authMethodIds: List<String> = emptyList()

    private companion object {
        // Generous: a cold `bunx @zed-industries/claude-code-acp` may download the package
        // on the host before answering initialize.
        const val REQUEST_TIMEOUT_MS = 120_000L
    }

    /** Emits mapped CodexSessionItem instances (AgentMessage, Reasoning for thoughts, ToolCall, Plan, ...). */
    val sessionItems: Flow<CodexSessionItem> = itemsChannel.receiveAsFlow()

    /** Emits agent -> client requests (permission prompts) that must be answered via [respondToServerRequest]. */
    val serverRequests: Flow<AcpServerRequest> = serverRequestChannel.receiveAsFlow()

    // replay = 1: a disconnect that fires before the ViewModel's collector subscribes
    // (e.g. the transport dies right after createSession) must still be observed.
    private val _disconnects = MutableSharedFlow<String>(replay = 1)

    /** Emits once when the transport ends or fails after a successful start (parity with the iOS events stream). */
    val disconnects: SharedFlow<String> = _disconnects.asSharedFlow()

    init {
        scope.launch { readLoop() }
    }

    suspend fun initialize() {
        check(!closed) { "ACP client is closed." }
        val result = sendRequestAndAwait(AcpRpcRequests.initialize(id = nextId()))
        authMethodIds = acpAuthMethodIds(result.toSharedJsonValue())
    }

    /**
     * Creates a new ACP session and returns its id plus advertised model state. When the agent
     * answers auth_required, authenticates with its first advertised method and retries once.
     */
    suspend fun createSession(cwd: String, title: String? = null): AcpSession {
        check(!closed) { "ACP client is closed." }
        val result = try {
            sendRequestAndAwait(AcpRpcRequests.sessionNew(id = nextId(), cwd = cwd, title = title))
        } catch (error: AcpRpcException) {
            val methodId = authMethodIds.firstOrNull()
            if (error.code != AcpProtocolCore.AUTH_REQUIRED_ERROR_CODE || methodId == null) throw error
            sendRequestAndAwait(AcpRpcRequests.authenticate(id = nextId(), methodId = methodId))
            sendRequestAndAwait(AcpRpcRequests.sessionNew(id = nextId(), cwd = cwd, title = title))
        }
        val sid = extractSessionId(result) ?: error("session/new did not return a sessionId in result: $result")
        currentSessionId = sid
        return AcpSession(sessionId = sid, models = acpSessionModels(result.toSharedJsonValue()))
    }

    /** Switches the session's model to one of the ids advertised by [createSession]. */
    suspend fun setModel(sessionId: String, modelId: String) {
        check(!closed) { "ACP client is closed." }
        sendRequestAndAwait(AcpRpcRequests.sessionSetModel(id = nextId(), sessionId = sessionId, modelId = modelId))
    }

    /** Fire-and-forget: the prompt result (stopReason) only arrives when the whole turn ends. */
    suspend fun sendPrompt(sessionId: String, text: String) {
        check(!closed) { "ACP client is closed." }
        val req = AcpRpcRequests.sessionPrompt(id = nextId(), sessionId = sessionId, prompt = text)
        transport.sendLine(req.encodeJsonLine())
    }

    /** Spec cancellation: `session/cancel` notification (the agent answers the prompt with stopReason=cancelled). */
    suspend fun cancel(sessionId: String) {
        check(!closed) { "ACP client is closed." }
        transport.sendLine(AcpProtocolCore.notificationLine("session/cancel", AcpRpcRequests.sessionCancelParams(sessionId)))
    }

    /** Answers an agent -> client request (e.g. a permission prompt outcome). */
    suspend fun respondToServerRequest(id: JsonValue, result: JsonValue) {
        check(!closed) { "ACP client is closed." }
        transport.sendLine(AcpProtocolCore.resultLine(id, result))
    }

    suspend fun close() {
        if (!closed) {
            closed = true
            failAllPending(IllegalStateException("ACP client closed."))
            transport.close()
        }
        // Always close the channels (idempotent): a close() racing disconnect() must not
        // leave the reader's final send parked on a full buffer forever.
        itemsChannel.close()
        serverRequestChannel.close()
    }

    private fun nextId(): Long = idCounter.getAndIncrement() // monotonic to avoid collisions on rapid initialize + session/new (codex review P2)

    private suspend fun sendRequestAndAwait(req: mobidex.shared.CodexRpcRequest): JsonElement {
        val waiter = CompletableDeferred<JsonElement>()
        pendingMutex.withLock {
            // Re-check under the same lock failAllPending uses: registering after the fail
            // sweep would otherwise orphan the waiter until the timeout.
            check(!closed) { "ACP client is closed." }
            pending[req.id] = waiter
        }
        try {
            transport.sendLine(req.encodeJsonLine())
        } catch (e: Throwable) {
            // NonCancellable: if sendLine failed via cancellation, the suspending lock would
            // otherwise rethrow immediately and leak the pending entry.
            withContext(NonCancellable) { pendingMutex.withLock { pending.remove(req.id) } }
            waiter.completeExceptionally(e)
            throw e
        }
        try {
            return withTimeout(REQUEST_TIMEOUT_MS) { waiter.await() }
        } catch (e: TimeoutCancellationException) {
            pendingMutex.withLock { pending.remove(req.id) }
            throw IllegalStateException("ACP request ${req.method} timed out after ${REQUEST_TIMEOUT_MS / 1000}s.", e)
        } catch (e: CancellationException) {
            // Caller cancelled: drop the registration (a cancelled coroutine cannot take a
            // suspending lock, so do it under NonCancellable).
            withContext(NonCancellable) { pendingMutex.withLock { pending.remove(req.id) } }
            throw e
        }
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
                        val code = classification.error?.code ?: 0
                        val err = AcpProtocolCore.readableError(code, classification.error?.message ?: "ACP error")
                        pendingMutex.withLock { pending.remove(id) }?.completeExceptionally(AcpRpcException(code, err))
                    }
                    "resultResponse" -> {
                        val id = classification.numericId ?: return@collect
                        val resultEl = classification.result?.toJsonElement() ?: return@collect
                        pendingMutex.withLock { pending.remove(id) }?.complete(resultEl)
                    }
                    "sessionUpdate" -> {
                        // The key path: agent chunks → existing UI model via the shared mapper.
                        // Suspending send: backpressure the transport instead of silently
                        // dropping chat content when the consumer falls behind.
                        classification.toCodexSessionItems().forEach { item ->
                            itemsChannel.send(item)
                        }
                    }
                    "serverRequest" -> {
                        val id = classification.id ?: return@collect
                        val method = classification.method ?: return@collect
                        serverRequestChannel.send(AcpServerRequest(id = id, method = method, params = classification.params))
                    }
                    else -> {
                        // Ignore other notifications (vendor extensions, stopReason-less acks, ...).
                    }
                }
            }
            if (!closed) disconnect("ACP transport stream ended.")
        } catch (error: Throwable) {
            if (!closed) disconnect(error.message ?: "ACP read error: ${error::class.simpleName}")
        }
    }

    private suspend fun disconnect(message: String) {
        closed = true
        failAllPending(IllegalStateException(message))
        _disconnects.tryEmit(message)
        runCatching {
            itemsChannel.send(
                CodexSessionItem.AgentEvent(
                    id = "acp-disconnect-${System.currentTimeMillis()}",
                    label = "disconnected",
                    status = "error",
                    detail = message,
                )
            )
        }
        itemsChannel.close()
        serverRequestChannel.close()
    }

    private suspend fun failAllPending(error: Throwable) {
        val toFail = pendingMutex.withLock {
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
