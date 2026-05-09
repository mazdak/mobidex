package mobidex.android.service

import java.util.concurrent.ConcurrentHashMap
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
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mobidex.android.model.CodexThread
import mobidex.android.model.CodexTurn
import mobidex.shared.CodexAccessMode
import mobidex.shared.CodexInputItem
import mobidex.shared.CodexReasoningEffortOption
import mobidex.shared.CodexRpcClientCore
import mobidex.shared.CodexRpcErrorInfo
import mobidex.shared.CodexRpcInboundEnvelope
import mobidex.shared.CodexRpcRequests
import mobidex.shared.CodexTurnOptions
import mobidex.shared.GitDiffFileParser
import mobidex.shared.GitDiffSnapshot
import mobidex.shared.JsonValue
import mobidex.shared.jsonBool
import mobidex.shared.jsonObject
import mobidex.shared.jsonString

interface CodexLineTransport {
    val inboundLines: Flow<String>
    suspend fun sendLine(line: String)
    suspend fun close()
}

sealed interface CodexAppServerEvent {
    data class Notification(val method: String, val params: JsonElement?) : CodexAppServerEvent
    data class ServerRequest(val id: JsonElement, val method: String, val params: JsonElement?) : CodexAppServerEvent
    data class Disconnected(val message: String) : CodexAppServerEvent
}

class CodexAppServerClient(private val transport: CodexLineTransport) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val eventsChannel = Channel<CodexAppServerEvent>(Channel.BUFFERED)
    private val rpcCore = CodexRpcClientCore()
    private val rpcCoreMutex = Mutex()
    private val pending = ConcurrentHashMap<Long, CompletableDeferred<JsonElement>>()
    private var closed = false

    val events: Flow<CodexAppServerEvent> = eventsChannel.receiveAsFlow()

    init {
        scope.launch { readLoop() }
    }

    suspend fun initialize() {
        request("initialize", CodexRpcRequests.initialize(0, "mobidex-android", "Mobidex Android", "0.1.0").params?.toJsonElement())
        transport.sendLine(rpcCore.notificationLine("initialized"))
    }

    suspend fun listThreads(cwd: String?, limit: Int = 80): List<CodexThread> {
        var cursor: String? = null
        val threads = mutableListOf<CodexThread>()
        do {
            val result = request("thread/list", CodexRpcRequests.threadList(0, cwd, limit, cursor).params?.toJsonElement())
            val obj = result.jsonObject
            threads += obj["data"]?.let { array ->
                array as? JsonArray
            }?.map(::parseThread).orEmpty()
                .filter { it.isUserFacingSession }
            cursor = obj["nextCursor"]?.jsonPrimitive?.contentOrNull
        } while (cursor != null)
        return if (cwd.isNullOrEmpty()) threads else threads.filter { it.cwd == cwd }
    }

    suspend fun listLoadedThreadIDs(limit: Int = 1_000): List<String> {
        val result = request("thread/loaded/list", CodexRpcRequests.loadedThreadList(0, limit).params?.toJsonElement())
        return (result.jsonObject["data"] as? JsonArray)
            ?.mapNotNull { it.jsonPrimitive.contentOrNull }
            .orEmpty()
    }

    suspend fun readThread(threadID: String): CodexThread {
        val result = request("thread/read", CodexRpcRequests.readThread(0, threadID, true).params?.toJsonElement())
        return parseThread(result.jsonObject["thread"] ?: result)
    }

    suspend fun readThreadSummary(threadID: String): CodexThread {
        val result = request("thread/read", CodexRpcRequests.readThread(0, threadID, false).params?.toJsonElement())
        return parseThread(result.jsonObject["thread"] ?: result)
    }

    suspend fun resumeThread(threadID: String): CodexThread {
        val result = request("thread/resume", CodexRpcRequests.resumeThread(0, threadID).params?.toJsonElement())
        return parseThread(result.jsonObject["thread"] ?: result)
    }

    suspend fun startThread(cwd: String?): CodexThread {
        val result = request("thread/start", CodexRpcRequests.startThread(0, cwd).params?.toJsonElement())
        return parseThread(result.jsonObject["thread"] ?: result)
    }

    suspend fun startTurn(threadID: String, input: List<CodexInputItem>, options: CodexTurnOptions): CodexTurn {
        val result = request("turn/start", CodexRpcRequests.startTurn(0, threadID, input, options).params?.toJsonElement())
        return parseTurn(result.jsonObject["turn"] ?: result)
    }

    suspend fun steer(threadID: String, expectedTurnID: String, input: List<CodexInputItem>) {
        request("turn/steer", CodexRpcRequests.steerTurn(0, threadID, expectedTurnID, input).params?.toJsonElement())
    }

    suspend fun interrupt(threadID: String, turnID: String) {
        request("turn/interrupt", CodexRpcRequests.interruptTurn(0, threadID, turnID).params?.toJsonElement())
    }

    suspend fun diffSnapshot(cwd: String): GitDiffSnapshot {
        val result = request("gitDiffToRemote", CodexRpcRequests.gitDiffToRemote(0, cwd).params?.toJsonElement())
        val sha = result.jsonObject["sha"]?.jsonPrimitive?.contentOrNull ?: ""
        val diff = result.jsonObject["diff"]?.jsonPrimitive?.contentOrNull ?: ""
        return GitDiffSnapshot(sha = sha, diff = diff, files = GitDiffFileParser.files(diff))
    }

    suspend fun respondToServerRequest(id: JsonElement, result: JsonValue) {
        transport.sendLine(rpcCore.resultLine(id.toSharedJsonValue(), result))
    }

    suspend fun close() {
        if (closed) return
        closed = true
        failPending(IllegalStateException("The app-server connection closed."))
        transport.close()
        eventsChannel.close()
    }

    private suspend fun request(method: String, params: JsonElement?): JsonElement {
        check(!closed) { "The app-server connection is closed." }
        val waiter = CompletableDeferred<JsonElement>()
        val request = rpcCoreMutex.withLock {
            val next = rpcCore.nextRequest(method, params?.toSharedJsonValue())
            pending[next.id] = waiter
            next
        }
        try {
            transport.sendLine(request.line)
        } catch (error: Throwable) {
            pending.remove(request.id)?.completeExceptionally(error)
            throw error
        }
        return waiter.await()
    }

    private suspend fun readLoop() {
        try {
            transport.inboundLines.collect { line ->
                val message = AppJson.parseToJsonElement(line).jsonObject
                val action = rpcCore.classifyInbound(message.toSharedEnvelope()) ?: return@collect
                when (action.kind) {
                    "errorResponse" -> {
                        val id = action.numericId ?: return@collect
                        val error = action.error?.message ?: "The app-server returned an error."
                        pending.remove(id)?.completeExceptionally(IllegalStateException(error))
                    }
                    "resultResponse" -> {
                        val id = action.numericId ?: return@collect
                        val result = action.result?.toJsonElement() ?: return@collect
                        pending.remove(id)?.complete(result)
                    }
                    "serverRequest" -> {
                        val id = action.id?.toJsonElement() ?: return@collect
                        val method = action.method ?: return@collect
                        eventsChannel.trySend(CodexAppServerEvent.ServerRequest(id, method, action.params?.toJsonElement()))
                    }
                    "notification" -> {
                        val method = action.method ?: return@collect
                        eventsChannel.trySend(CodexAppServerEvent.Notification(method, action.params?.toJsonElement()))
                    }
                }
            }
            disconnectFromReader(IllegalStateException("The app-server stream ended."))
        } catch (error: Throwable) {
            if (!closed) {
                disconnectFromReader(error)
            }
        }
    }

    private suspend fun disconnectFromReader(error: Throwable) {
        closed = true
        failPending(error)
        transport.close()
        eventsChannel.trySend(CodexAppServerEvent.Disconnected(error.message ?: "The app-server connection failed."))
        eventsChannel.close()
    }

    private fun failPending(error: Throwable) {
        pending.values.forEach { it.completeExceptionally(error) }
        pending.clear()
    }
}

private fun JsonObject.toSharedEnvelope(): CodexRpcInboundEnvelope =
    CodexRpcInboundEnvelope(
        id = get("id")?.toSharedJsonValue(),
        method = get("method")?.jsonPrimitive?.contentOrNull,
        params = get("params")?.toSharedJsonValue(),
        result = get("result")?.toSharedJsonValue(),
        error = get("error")?.jsonObject?.let { error ->
            CodexRpcErrorInfo(
                code = error["code"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0,
                message = error["message"]?.jsonPrimitive?.contentOrNull ?: "The app-server returned an error.",
            )
        },
    )

fun turnOptions(effort: CodexReasoningEffortOption, accessMode: CodexAccessMode, cwd: String?): CodexTurnOptions =
    CodexTurnOptions(reasoningEffort = effort, accessMode = accessMode, cwd = cwd)
