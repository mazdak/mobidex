package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AcpProtocolCoreTest {
    @Test
    fun initializeRequestHasSpecShape() {
        val req = AcpRpcRequests.initialize(42, clientName = "mobidex-test", clientVersion = "0.2.0")
        assertEquals(42L, req.id)
        assertEquals("initialize", req.method)
        val params = req.params as? JsonValue.ObjectValue
        assertNotNull(params)
        assertEquals(1L, params["protocolVersion"]?.intValue)
        // No client-side fs/terminal: the agent runs on the host where the files live.
        assertEquals(false, (params["clientCapabilities"]?.get("fs")?.get("readTextFile") as? JsonValue.BoolValue)?.value)
        assertEquals(false, (params["clientCapabilities"]?.get("fs")?.get("writeTextFile") as? JsonValue.BoolValue)?.value)
        assertEquals(false, (params["clientCapabilities"]?.get("terminal") as? JsonValue.BoolValue)?.value)
        assertEquals("mobidex-test", params["clientInfo"]?.get("name")?.stringValue)
    }

    @Test
    fun sessionNewAlwaysIncludesCwdAndMcpServers() {
        val req = AcpRpcRequests.sessionNew(3, cwd = "/work/project")
        assertEquals("session/new", req.method)
        val params = req.params as? JsonValue.ObjectValue
        assertEquals("/work/project", params?.get("cwd")?.stringValue)
        assertEquals(emptyList(), (params?.get("mcpServers") as? JsonValue.ArrayValue)?.value)
    }

    @Test
    fun sessionPromptUsesContentBlockArray() {
        val req = AcpRpcRequests.sessionPrompt(7, sessionId = "sess-123", prompt = "Fix the bug")
        assertEquals("session/prompt", req.method)
        val p = req.params as? JsonValue.ObjectValue
        assertEquals("sess-123", p?.get("sessionId")?.stringValue)
        val blocks = (p?.get("prompt") as? JsonValue.ArrayValue)?.value
        assertEquals(1, blocks?.size)
        assertEquals("text", blocks?.first()?.get("type")?.stringValue)
        assertEquals("Fix the bug", blocks?.first()?.get("text")?.stringValue)
    }

    @Test
    fun authenticateRequestCarriesMethodId() {
        val req = AcpRpcRequests.authenticate(5, methodId = "grok.com")
        assertEquals("authenticate", req.method)
        assertEquals("grok.com", (req.params as? JsonValue.ObjectValue)?.get("methodId")?.stringValue)
    }

    @Test
    fun extractsAuthMethodIdsFromInitializeResult() {
        val result = jsonObject(
            mapOf(
                "protocolVersion" to jsonInt(1),
                "authMethods" to jsonArray(
                    listOf(
                        jsonObject(mapOf("id" to jsonString("grok.com"), "name" to jsonString("Grok"))),
                        jsonObject(mapOf("id" to jsonString("api-key"))),
                    )
                ),
            )
        )
        assertEquals(listOf("grok.com", "api-key"), acpAuthMethodIds(result))
        assertEquals(emptyList(), acpAuthMethodIds(jsonObject(emptyMap())))
        assertEquals(emptyList(), acpAuthMethodIds(null))
    }

    @Test
    fun sessionSetModelHasSpecShape() {
        val req = AcpRpcRequests.sessionSetModel(9, sessionId = "s1", modelId = "sonnet")
        assertEquals("session/set_model", req.method)
        val params = req.params as? JsonValue.ObjectValue
        assertEquals("s1", params?.get("sessionId")?.stringValue)
        assertEquals("sonnet", params?.get("modelId")?.stringValue)
    }

    @Test
    fun parsesSessionModelsFromSessionNewResult() {
        val result = jsonObject(
            mapOf(
                "sessionId" to jsonString("s1"),
                "models" to jsonObject(
                    mapOf(
                        "availableModels" to jsonArray(
                            listOf(
                                jsonObject(
                                    mapOf(
                                        "modelId" to jsonString("default"),
                                        "name" to jsonString("Default (recommended)"),
                                        "description" to jsonString("Opus 4.6"),
                                    )
                                ),
                                jsonObject(mapOf("modelId" to jsonString("sonnet"), "name" to jsonString("Sonnet"))),
                            )
                        ),
                        "currentModelId" to jsonString("default"),
                    )
                ),
            )
        )
        val models = acpSessionModels(result)
        assertNotNull(models)
        assertEquals(listOf("default", "sonnet"), models.available.map { it.modelId })
        assertEquals("Default (recommended)", models.available.first().name)
        assertEquals("default", models.currentModelId)

        // Agents that advertise no models -> null (switching unsupported).
        assertNull(acpSessionModels(jsonObject(mapOf("sessionId" to jsonString("s2")))))
        assertNull(acpSessionModels(jsonObject(mapOf("models" to jsonObject(mapOf("availableModels" to jsonArray(emptyList())))))))
        assertNull(acpSessionModels(null))
    }

    @Test
    fun sessionCancelParamsCarrySessionId() {
        val params = AcpRpcRequests.sessionCancelParams("s9")
        assertEquals("s9", params["sessionId"]?.stringValue)
    }

    @Test
    fun classifiesSpecShapedAgentMessageChunk() {
        val envelope = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(
                mapOf(
                    "sessionId" to jsonString("s1"),
                    "update" to jsonObject(
                        mapOf(
                            "sessionUpdate" to jsonString("agent_message_chunk"),
                            "content" to jsonObject(mapOf("type" to jsonString("text"), "text" to jsonString("Hello from ACP"))),
                        )
                    ),
                )
            )
        )
        val cls = AcpProtocolCore.classifyInbound(envelope)
        assertEquals("sessionUpdate", cls?.kind)
        val chunk = cls?.sessionUpdate?.chunk
        assertTrue(chunk is AcpContentChunk.AgentMessageChunk)
        assertEquals("Hello from ACP", (chunk as AcpContentChunk.AgentMessageChunk).delta)
    }

    @Test
    fun classifiesLegacyChunkShapeWithAgentMessageChunk() {
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
        assertTrue(cls?.sessionUpdate?.chunk is AcpContentChunk.AgentMessageChunk)
    }

    @Test
    fun parsesSpecToolCallAndUpdate() {
        val call = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(
                mapOf(
                    "sessionId" to jsonString("s1"),
                    "update" to jsonObject(
                        mapOf(
                            "sessionUpdate" to jsonString("tool_call"),
                            "toolCallId" to jsonString("call_1"),
                            "title" to jsonString("Edit main.rs"),
                            "kind" to jsonString("edit"),
                            "status" to jsonString("pending"),
                            "rawInput" to jsonObject(mapOf("path" to jsonString("main.rs"))),
                        )
                    ),
                )
            )
        )
        val callChunk = AcpProtocolCore.classifyInbound(call)?.sessionUpdate?.chunk
        assertTrue(callChunk is AcpContentChunk.ToolCall)
        assertEquals("call_1", (callChunk as AcpContentChunk.ToolCall).toolCallId)
        assertEquals("Edit main.rs", callChunk.name)

        val update = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(
                mapOf(
                    "sessionId" to jsonString("s1"),
                    "update" to jsonObject(
                        mapOf(
                            "sessionUpdate" to jsonString("tool_call_update"),
                            "toolCallId" to jsonString("call_1"),
                            "status" to jsonString("completed"),
                            "content" to jsonArray(
                                listOf(
                                    jsonObject(
                                        mapOf(
                                            "type" to jsonString("content"),
                                            "content" to jsonObject(mapOf("type" to jsonString("text"), "text" to jsonString("done"))),
                                        )
                                    )
                                )
                            ),
                        )
                    ),
                )
            )
        )
        val updateChunk = AcpProtocolCore.classifyInbound(update)?.sessionUpdate?.chunk
        assertTrue(updateChunk is AcpContentChunk.ToolCallUpdate)
        val u = updateChunk as AcpContentChunk.ToolCallUpdate
        assertEquals("call_1", u.toolCallId)
        assertEquals("completed", u.status)
        assertEquals("done", u.output)
    }

    @Test
    fun parsesSpecPlanEntries() {
        val envelope = AcpRpcInboundEnvelope(
            method = "session/update",
            params = jsonObject(
                mapOf(
                    "sessionId" to jsonString("s1"),
                    "update" to jsonObject(
                        mapOf(
                            "sessionUpdate" to jsonString("plan"),
                            "entries" to jsonArray(
                                listOf(
                                    jsonObject(mapOf("content" to jsonString("Read the code"), "status" to jsonString("completed"))),
                                    jsonObject(mapOf("content" to jsonString("Write the fix"), "status" to jsonString("pending"))),
                                )
                            ),
                        )
                    ),
                )
            )
        )
        val chunk = AcpProtocolCore.classifyInbound(envelope)?.sessionUpdate?.chunk
        assertTrue(chunk is AcpContentChunk.Plan)
        val plan = chunk as AcpContentChunk.Plan
        assertEquals("[completed] Read the code\n[pending] Write the fix", plan.content)
    }

    @Test
    fun unknownSpecVariantsProduceNoUiItems() {
        for (variant in listOf("available_commands_update", "current_mode_update", "user_message_chunk")) {
            val envelope = AcpRpcInboundEnvelope(
                method = "session/update",
                params = jsonObject(
                    mapOf(
                        "sessionId" to jsonString("s1"),
                        "update" to jsonObject(mapOf("sessionUpdate" to jsonString(variant))),
                    )
                )
            )
            val cls = AcpProtocolCore.classifyInbound(envelope)
            assertEquals("sessionUpdate", cls?.kind, "variant $variant should still classify")
            assertEquals(emptyList(), cls?.toCodexSessionItems(), "variant $variant should map to no items")
        }
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
    fun mapsApprovalRequestToAgentEventItem() {
        val chunk = AcpContentChunk.ApprovalRequest(
            requestId = jsonInt(99),
            title = "Run rm -rf?",
            detail = "This will delete everything.",
        )
        val item = chunk.toCodexSessionItem("appr1")
        assertTrue(item is CodexSessionItem.AgentEvent)
        val ev = item as CodexSessionItem.AgentEvent
        assertEquals("Run rm -rf?", ev.label)
        assertEquals("This will delete everything.", ev.detail)
    }

    @Test
    fun classificationToCodexSessionItemsUsesStableIds() {
        val message = AcpRpcInboundClassification(
            kind = "sessionUpdate",
            method = "session/update",
            sessionUpdate = AcpSessionUpdate(
                sessionId = "s1",
                chunk = AcpContentChunk.AgentMessageChunk(delta = "hi"),
                rawParams = null
            )
        )
        assertEquals("acp-message", message.toCodexSessionItems().single().id)

        val tool = AcpRpcInboundClassification(
            kind = "sessionUpdate",
            method = "session/update",
            sessionUpdate = AcpSessionUpdate(
                sessionId = "s1",
                chunk = AcpContentChunk.ToolCallUpdate(toolCallId = "call_1", name = null, status = "completed", output = "ok"),
                rawParams = null
            )
        )
        assertEquals("call_1", tool.toCodexSessionItems().single().id)
    }

    @Test
    fun accumulatorCoalescesMessageDeltasAndResolvesToolCalls() {
        var items = emptyList<CodexSessionItem>()
        items = items.appendingAcpSessionItem(CodexSessionItem.AgentMessage(id = "acp-message", text = "Hel"))
        items = items.appendingAcpSessionItem(CodexSessionItem.AgentMessage(id = "acp-message", text = "lo"))
        assertEquals(1, items.size)
        assertEquals("Hello", (items.single() as CodexSessionItem.AgentMessage).text)

        items = items.appendingAcpSessionItem(CodexSessionItem.ToolCall(id = "call_1", label = "Edit file", status = "pending", detail = null))
        items = items.appendingAcpSessionItem(CodexSessionItem.ToolCall(id = "call_1", label = "tool", status = "completed", detail = "done"))
        assertEquals(2, items.size)
        val tool = items.last() as CodexSessionItem.ToolCall
        assertEquals("Edit file", tool.label) // update keeps the original title
        assertEquals("completed", tool.status)
        assertEquals("done", tool.detail)

        // A message after the tool call starts a new bubble even with the same stable id.
        items = items.appendingAcpSessionItem(CodexSessionItem.AgentMessage(id = "acp-message", text = "Next turn"))
        assertEquals(3, items.size)
    }

    @Test
    fun accumulatorMergesReasoningAndReplacesPlan() {
        var items = emptyList<CodexSessionItem>()
        items = items.appendingAcpSessionItem(CodexSessionItem.Reasoning(id = "acp-thought", summary = emptyList(), content = listOf("Think")))
        items = items.appendingAcpSessionItem(CodexSessionItem.Reasoning(id = "acp-thought", summary = emptyList(), content = listOf("ing...")))
        assertEquals(1, items.size)
        assertEquals(listOf("Thinking..."), (items.single() as CodexSessionItem.Reasoning).content)

        items = items.appendingAcpSessionItem(CodexSessionItem.Plan(id = "acp-plan", text = "[pending] step 1"))
        items = items.appendingAcpSessionItem(CodexSessionItem.Plan(id = "acp-plan", text = "[completed] step 1"))
        assertEquals(2, items.size)
        assertEquals("[completed] step 1", (items.last() as CodexSessionItem.Plan).text)
    }

    @Test
    fun parsesPermissionRequestAndChoosesOptions() {
        val params = jsonObject(
            mapOf(
                "sessionId" to jsonString("s1"),
                "toolCall" to jsonObject(
                    mapOf(
                        "toolCallId" to jsonString("call_1"),
                        "title" to jsonString("Run `cargo test`"),
                        "rawInput" to jsonObject(mapOf("command" to jsonString("cargo test"))),
                    )
                ),
                "options" to jsonArray(
                    listOf(
                        jsonObject(mapOf("optionId" to jsonString("allow-always"), "name" to jsonString("Always"), "kind" to jsonString("allow_always"))),
                        jsonObject(mapOf("optionId" to jsonString("allow"), "name" to jsonString("Allow"), "kind" to jsonString("allow_once"))),
                        jsonObject(mapOf("optionId" to jsonString("deny"), "name" to jsonString("Deny"), "kind" to jsonString("reject_once"))),
                    )
                ),
            )
        )
        val parsed = AcpProtocolCore.parsePermissionRequest(params)
        assertEquals("s1", parsed.sessionId)
        assertEquals("Run `cargo test`", parsed.title)
        assertTrue(parsed.detail?.contains("cargo test") == true)
        assertEquals(3, parsed.options.size)

        assertEquals("allow", AcpProtocolCore.choosePermissionOptionId(params, accept = true))
        assertEquals("deny", AcpProtocolCore.choosePermissionOptionId(params, accept = false))
        assertNull(AcpProtocolCore.choosePermissionOptionId(jsonObject(emptyMap()), accept = true))
    }

    @Test
    fun permissionResultsHaveSpecOutcomeShape() {
        val selected = AcpProtocolCore.permissionSelectedResult("allow")
        assertEquals("selected", selected["outcome"]?.get("outcome")?.stringValue)
        assertEquals("allow", selected["outcome"]?.get("optionId")?.stringValue)

        val cancelled = AcpProtocolCore.permissionCancelledResult()
        assertEquals("cancelled", cancelled["outcome"]?.get("outcome")?.stringValue)
    }

    @Test
    fun classifiesNullResultResponseAsVoidResult() {
        // Spec agents answer void methods (authenticate, ...) with "result": null; some platform
        // decoders drop the explicit null entirely. Both must classify as a result, not stall.
        val dropped = AcpProtocolCore.classifyInbound(AcpRpcInboundEnvelope(id = jsonInt(2)))
        assertEquals("resultResponse", dropped?.kind)
        assertEquals(JsonValue.Null, dropped?.result)

        val explicit = AcpProtocolCore.classifyInbound(AcpRpcInboundEnvelope(id = jsonInt(2), result = JsonValue.Null))
        assertEquals("resultResponse", explicit?.kind)
    }

    @Test
    fun numericIdWithMethodStaysServerRequest() {
        val cls = AcpProtocolCore.classifyInbound(
            AcpRpcInboundEnvelope(
                id = jsonInt(99),
                method = "session/request_permission",
                params = jsonObject(emptyMap()),
            )
        )
        assertEquals("serverRequest", cls?.kind)
        assertEquals("session/request_permission", cls?.method)
    }

    @Test
    fun statuslessToolCallUpdateKeepsExistingStatus() {
        var items = emptyList<CodexSessionItem>()
        items = items.appendingAcpSessionItem(CodexSessionItem.ToolCall(id = "tc", label = "Edit", status = "completed", detail = null))
        // Output-only update (mapper emits empty status when the update carried none).
        items = items.appendingAcpSessionItem(CodexSessionItem.ToolCall(id = "tc", label = "tool", status = "", detail = "output"))
        val tool = items.single() as CodexSessionItem.ToolCall
        assertEquals("completed", tool.status)
        assertEquals("output", tool.detail)

        // A status-less update with no prior card still appends something renderable.
        val fresh = emptyList<CodexSessionItem>().appendingAcpSessionItem(CodexSessionItem.ToolCall(id = "tc2", label = "tool", status = "", detail = null))
        assertEquals("running", (fresh.single() as CodexSessionItem.ToolCall).status)
    }

    @Test
    fun readableErrorExplainsAuthRequired() {
        val text = AcpProtocolCore.readableError(AcpProtocolCore.AUTH_REQUIRED_ERROR_CODE, "Authentication required")
        assertTrue(text.contains("authentication", ignoreCase = true))
        assertTrue(text.contains("reconnect"))
        assertEquals("boom", AcpProtocolCore.readableError(-32602, "boom"))
    }
}
