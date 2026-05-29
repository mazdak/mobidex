package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AcpProtocolCoreTest {
    @Test
    fun initializeRequestHasExpectedShape() {
        val req = AcpRpcRequests.initialize(42, clientName = "mobidex-test", clientVersion = "0.2.0")
        assertEquals(42L, req.id)
        assertEquals("initialize", req.method)
        val params = req.params as? JsonValue.ObjectValue
        assertNotNull(params)
        assertTrue(params.value.containsKey("clientInfo"))
        assertTrue(params.value.containsKey("capabilities"))
    }

    @Test
    fun sessionPromptRequestIncludesSessionAndTextPrompt() {
        val req = AcpRpcRequests.sessionPrompt(7, sessionId = "sess-123", prompt = "Fix the bug")
        assertEquals("session/prompt", req.method)
        val p = req.params as? JsonValue.ObjectValue
        assertEquals("sess-123", p?.get("sessionId")?.stringValue)
        assertEquals("Fix the bug", p?.get("prompt")?.get("text")?.stringValue)
    }

    @Test
    fun classifiesSessionUpdateWithAgentMessageChunk() {
        val envelope = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(
                mapOf(
                    "sessionId" to jsonString("s1"),
                    "chunk" to jsonObject(mapOf("type" to jsonString("agent_message_chunk"), "delta" to jsonString("Hello from Grok")))
                )
            )
        )
        val cls = AcpProtocolCore.classifyInbound(envelope)
        assertEquals("sessionUpdate", cls?.kind)
        assertNotNull(cls?.sessionUpdate?.chunk)
        assertTrue(cls!!.sessionUpdate!!.chunk is AcpContentChunk.AgentMessageChunk)
    }

    @Test
    fun mapsThoughtChunkToReasoningItem() {
        val chunk = AcpContentChunk.AgentThoughtChunk(delta = "Considering the alternatives...", summary = "Exploring options")
        val item = chunk.toCodexSessionItem(itemId = "t1")
        assertTrue(item is CodexSessionItem.Reasoning)
        val r = item as CodexSessionItem.Reasoning
        assertEquals(listOf("Exploring options"), r.summary)
        assertEquals(listOf("Considering the alternatives..."), r.content)
    }

    @Test
    fun mapsMessageChunkToAgentMessageItem() {
        val chunk = AcpContentChunk.AgentMessageChunk(delta = "The fix is to call foo().")
        val item = chunk.toCodexSessionItem("m42")
        assertTrue(item is CodexSessionItem.AgentMessage)
        assertEquals("The fix is to call foo().", (item as CodexSessionItem.AgentMessage).text)
    }

    @Test
    fun mapsToolCallToToolCallItem() {
        val chunk = AcpContentChunk.ToolCall(toolCallId = "tc1", name = "run_tests", args = jsonObject(emptyMap()), status = "running")
        val item = chunk.toCodexSessionItem("tc1")
        assertTrue(item is CodexSessionItem.ToolCall)
        val t = item as CodexSessionItem.ToolCall
        assertEquals("run_tests", t.label)
        assertEquals("running", t.status)
    }

    @Test
    fun mapsPlanChunkToPlanItem() {
        val chunk = AcpContentChunk.Plan(title = "Steps", content = "1. Edit\n2. Test")
        val item = chunk.toCodexSessionItem()
        assertTrue(item is CodexSessionItem.Plan)
        assertTrue((item as CodexSessionItem.Plan).text.contains("Steps"))
    }

    @Test
    fun classificationToCodexSessionItemsProducesRenderableItems() {
        val cls = AcpRpcInboundClassification(
            kind = "sessionUpdate",
            method = "session/update",
            sessionUpdate = AcpSessionUpdate(
                sessionId = "s1",
                chunk = AcpContentChunk.AgentThoughtChunk(delta = "thinking...", summary = null),
                rawParams = null
            )
        )
        val items = cls.toCodexSessionItems()
        assertEquals(1, items.size)
        assertTrue(items.first() is CodexSessionItem.Reasoning)
    }

    @Test
    fun mapsApprovalRequestToAgentEventItem() {
        val chunk = AcpContentChunk.ApprovalRequest(
            requestId = jsonInt(99),
            title = "Run rm -rf?",
            detail = "This will delete everything.",
        )
        val item = chunk.toCodexSessionItem("appr1")
        assertTrue(item is CodexSessionItem.AgentEvent)
        val ev = item as CodexSessionItem.AgentEvent
        assertEquals("approval_request", ev.label) // from chunk.type
        assertTrue(ev.detail?.contains("Run rm") == true)
    }

    @Test
    fun parsesAlternativeChunkTypeAliasesForThoughtAndMessage() {
        // reasoning alias
        val envThought = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(mapOf("chunk" to jsonObject(mapOf("type" to jsonString("reasoning"), "content" to jsonString("deep thought")))))
        )
        val clsThought = AcpProtocolCore.classifyInbound(envThought)
        val chunkThought = clsThought?.sessionUpdate?.chunk
        assertTrue(chunkThought is AcpContentChunk.AgentThoughtChunk)
        assertEquals("deep thought", (chunkThought as AcpContentChunk.AgentThoughtChunk).delta)

        // message alias
        val envMsg = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(mapOf("chunk" to jsonObject(mapOf("type" to jsonString("text"), "text" to jsonString("final answer")))))
        )
        val clsMsg = AcpProtocolCore.classifyInbound(envMsg)
        val chunkMsg = clsMsg?.sessionUpdate?.chunk
        assertTrue(chunkMsg is AcpContentChunk.AgentMessageChunk)
        assertEquals("final answer", (chunkMsg as AcpContentChunk.AgentMessageChunk).delta)
    }
}
