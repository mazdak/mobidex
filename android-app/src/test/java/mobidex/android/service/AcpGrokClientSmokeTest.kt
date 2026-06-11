package mobidex.android.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import mobidex.shared.AcpProtocolCore
import mobidex.shared.CodexSessionItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Focused smoke for AcpGrokClient + the shared mapper against spec-shaped ACP traffic
 * (the wire format both `grok agent stdio` and `claude-code-acp` emit).
 *
 * Uses a scripted CodexLineTransport that answers requests like a spec agent:
 * - initialize -> result with authMethods
 * - first session/new -> auth_required (-32000), exercising the authenticate-and-retry path
 * - second session/new -> sessionId, then streams spec `session/update` notifications and a
 *   `session/request_permission` server request
 *
 * Verifies chunks flow out as the existing CodexSessionItem kinds the UI renders, that the
 * permission request surfaces on [AcpGrokClient.serverRequests], and that answering it writes
 * the spec outcome shape back to the transport. No real SSH or agent binary required.
 */
class AcpGrokClientSmokeTest {

    @Test
    fun smoke_specAgentRoundTrip_emitsMappedItemsAndAnswersPermission() = runBlocking {
        val transport = ScriptedAcpAgentTransport()
        val client = AcpGrokClient(transport)

        client.initialize()
        val sid = client.createSession(cwd = "/work/project", title = "smoke")
        assertEquals("sess-smoke-001", sid)
        assertTrue(
            "auth_required should trigger authenticate before the session/new retry",
            transport.sentMethods.contains("authenticate")
        )

        val collected = mutableListOf<CodexSessionItem>()
        val permission = async {
            withTimeout(1_500) { awaitFirstServerRequest(client) }
        }
        withTimeout(1_500) {
            try {
                client.sessionItems.collect { item ->
                    collected += item
                    val toolCompleted = collected.filterIsInstance<CodexSessionItem.ToolCall>().any { it.status == "completed" }
                    val done = collected.any { it is CodexSessionItem.Reasoning } &&
                        collected.any { it is CodexSessionItem.AgentMessage } &&
                        collected.any { it is CodexSessionItem.Plan } &&
                        toolCompleted
                    if (done) throw CancellationException("enough items for smoke")
                }
            } catch (_: CancellationException) {
                // expected drain
            }
        }

        // The permission request surfaced as a server request (not a chat item).
        val request = permission.await()
        assertEquals(AcpProtocolCore.PERMISSION_REQUEST_METHOD, request.method)
        val optionId = AcpProtocolCore.choosePermissionOptionId(request.params, accept = true)
        assertEquals("allow", optionId)
        client.respondToServerRequest(request.id, AcpProtocolCore.permissionSelectedResult(optionId!!))
        val outcomeLine = transport.sentLines.last()
        assertTrue("permission answer should carry the spec outcome shape", outcomeLine.contains("\"outcome\":\"selected\""))
        assertTrue(outcomeLine.contains("\"optionId\":\"allow\""))

        client.close()

        // Mapper assertions — spec chunks → existing UI item kinds.
        val reasoning = collected.filterIsInstance<CodexSessionItem.Reasoning>().first()
        assertTrue(reasoning.content.any { it.contains("Thinking about") })
        val message = collected.filterIsInstance<CodexSessionItem.AgentMessage>().first()
        assertTrue(message.text.contains("Here is the plan"))
        val toolCalls = collected.filterIsInstance<CodexSessionItem.ToolCall>()
        assertTrue("tool_call and tool_call_update share the stable toolCallId", toolCalls.all { it.id == "tc-1" })
        assertTrue(toolCalls.any { it.status == "completed" && it.detail?.contains("file contents") == true })
        val plan = collected.filterIsInstance<CodexSessionItem.Plan>().first()
        assertTrue(plan.text.contains("[pending] Wire the client"))
    }

    private suspend fun awaitFirstServerRequest(client: AcpGrokClient): AcpServerRequest {
        var result: AcpServerRequest? = null
        try {
            client.serverRequests.collect { request ->
                result = request
                throw CancellationException("got server request")
            }
        } catch (_: CancellationException) {
            // expected drain
        }
        return result ?: error("no server request received")
    }

    /** Replies to outbound requests like a spec ACP agent and streams canned spec updates. */
    private class ScriptedAcpAgentTransport : CodexLineTransport {
        private val ch = Channel<String>(Channel.UNLIMITED)
        val sentLines = mutableListOf<String>()
        val sentMethods = mutableListOf<String>()
        private var sessionNewCount = 0

        override val inboundLines: Flow<String> = ch.receiveAsFlow()

        override suspend fun sendLine(line: String) {
            sentLines += line
            val obj = AppJson.parseToJsonElement(line).jsonObject
            val method = obj["method"]?.jsonPrimitive?.contentOrNull ?: return
            sentMethods += method
            val id = obj["id"]?.jsonPrimitive?.longOrNull ?: return
            when (method) {
                "initialize" -> respond(
                    """{"jsonrpc":"2.0","id":$id,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[{"id":"grok.com","name":"Grok"}]}}"""
                )
                "session/new" -> {
                    sessionNewCount += 1
                    if (sessionNewCount == 1) {
                        respond("""{"jsonrpc":"2.0","id":$id,"error":{"code":-32000,"message":"Authentication required"}}""")
                    } else {
                        respond("""{"jsonrpc":"2.0","id":$id,"result":{"sessionId":"sess-smoke-001"}}""")
                        streamSpecUpdates()
                    }
                }
                // Spec agents answer void methods with an explicit null result.
                "authenticate" -> respond("""{"jsonrpc":"2.0","id":$id,"result":null}""")
            }
        }

        private fun streamSpecUpdates() {
            val sid = "sess-smoke-001"
            listOf(
                """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"$sid","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Thinking about the best way to implement the feature..."}}}}""",
                """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"$sid","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Here is the plan for the ACP integration."}}}}""",
                """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"$sid","update":{"sessionUpdate":"tool_call","toolCallId":"tc-1","title":"Read App.kt","kind":"read","status":"pending","rawInput":{"path":"src/App.kt"}}}}""",
                """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"$sid","update":{"sessionUpdate":"tool_call_update","toolCallId":"tc-1","status":"completed","content":[{"type":"content","content":{"type":"text","text":"file contents"}}]}}}""",
                """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"$sid","update":{"sessionUpdate":"plan","entries":[{"content":"Wire the client","priority":"high","status":"pending"}]}}}""",
                """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"$sid","update":{"sessionUpdate":"available_commands_update","availableCommands":[]}}}""",
                """{"jsonrpc":"2.0","id":99,"method":"session/request_permission","params":{"sessionId":"$sid","toolCall":{"toolCallId":"tc-2","title":"Run `git status`"},"options":[{"optionId":"allow","name":"Allow","kind":"allow_once"},{"optionId":"deny","name":"Deny","kind":"reject_once"}]}}""",
            ).forEach { ch.trySend(it) }
        }

        private fun respond(line: String) {
            ch.trySend(line)
        }

        override suspend fun close() {
            ch.close()
        }
    }
}
