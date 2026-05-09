package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CodexProtocolCoreTest {
    @Test
    fun textInputUsesCurrentAppServerShape() {
        val input = inputItems(listOf(CodexInputItem.Text("Run tests"))) as JsonValue.ArrayValue
        val textInput = input.value.single() as JsonValue.ObjectValue

        assertEquals("text", textInput.value["type"]?.stringValue)
        assertEquals("Run tests", textInput.value["text"]?.stringValue)
        assertEquals(JsonValue.ArrayValue(emptyList()), textInput.value["text_elements"])
        assertNull(textInput.value["textElements"])
    }

    @Test
    fun localImageInputUsesCurrentAppServerShape() {
        val imagePath = "/tmp/image.png"
        val image = CodexInputItem.LocalImage(path = imagePath).jsonValue as JsonValue.ObjectValue

        assertEquals("localImage", image.value["type"]?.stringValue)
        assertEquals(imagePath, image.value["path"]?.stringValue)
    }

    @Test
    fun turnOptionsEncodeReasoningAndSandboxPolicies() {
        val workspace = CodexTurnOptions(
            reasoningEffort = CodexReasoningEffortOption.XHigh,
            accessMode = CodexAccessMode.WorkspaceWrite,
            cwd = "/srv/app",
        ).jsonFields
        val workspaceSandbox = workspace["sandboxPolicy"] as JsonValue.ObjectValue
        val writableRoots = workspaceSandbox.value["writableRoots"] as JsonValue.ArrayValue

        assertEquals("xhigh", workspace["effort"]?.stringValue)
        assertEquals("on-request", workspace["approvalPolicy"]?.stringValue)
        assertEquals("workspaceWrite", workspaceSandbox.value["type"]?.stringValue)
        assertEquals(listOf(jsonString("/srv/app")), writableRoots.value)
        assertEquals(JsonValue.BoolValue(true), workspaceSandbox.value["networkAccess"])

        val full = CodexTurnOptions(
            reasoningEffort = CodexReasoningEffortOption.Medium,
            accessMode = CodexAccessMode.FullAccess,
        ).jsonFields
        val fullSandbox = full["sandboxPolicy"] as JsonValue.ObjectValue
        assertEquals("medium", full["effort"]?.stringValue)
        assertEquals("never", full["approvalPolicy"]?.stringValue)
        assertEquals("dangerFullAccess", fullSandbox.value["type"]?.stringValue)

        val readOnly = CodexTurnOptions(
            reasoningEffort = CodexReasoningEffortOption.Low,
            accessMode = CodexAccessMode.ReadOnly,
        ).jsonFields
        val readOnlySandbox = readOnly["sandboxPolicy"] as JsonValue.ObjectValue
        assertEquals("low", readOnly["effort"]?.stringValue)
        assertEquals("on-request", readOnly["approvalPolicy"]?.stringValue)
        assertEquals("readOnly", readOnlySandbox.value["type"]?.stringValue)
        assertEquals(JsonValue.BoolValue(false), readOnlySandbox.value["networkAccess"])
    }

    @Test
    fun defaultTurnOptionsEmitNoImplicitReasoningOrSandbox() {
        val fields = CodexTurnOptions.Default.jsonFields

        assertFalse("effort" in fields)
        assertFalse("approvalPolicy" in fields)
        assertFalse("sandboxPolicy" in fields)
    }

    @Test
    fun loadedThreadSummaryIgnorableErrorsMatchSwiftRules() {
        assertTrue(CodexRpcErrorInfo(0, "thread not loaded").canIgnoreForLoadedThreadSummary)
        assertTrue(CodexRpcErrorInfo(0, "unknown thread id").canIgnoreForLoadedThreadSummary)
        assertFalse(CodexRpcErrorInfo(0, "permission denied").canIgnoreForLoadedThreadSummary)
    }
}

class CodexProtocolWireEncodingTest {
    @Test
    fun threadListRequestEncodesCurrentWireShape() {
        val line = CodexRpcRequests.threadList(id = 1, cwd = "/srv/app", limit = 20).encodeJsonLine()

        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"thread/list\",\"params\":{\"limit\":20,\"sortKey\":\"updated_at\",\"sortDirection\":\"desc\",\"archived\":false,\"sourceKinds\":[\"cli\",\"vscode\",\"exec\",\"appServer\"],\"cwd\":\"/srv/app\"}}",
            line,
        )
    }

    @Test
    fun threadListRequestCanRequestArchivedThreads() {
        val line = CodexRpcRequests.threadList(id = 1, cwd = "/srv/app", limit = 20, archived = true).encodeJsonLine()

        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"thread/list\",\"params\":{\"limit\":20,\"sortKey\":\"updated_at\",\"sortDirection\":\"desc\",\"archived\":true,\"sourceKinds\":[\"cli\",\"vscode\",\"exec\",\"appServer\"],\"cwd\":\"/srv/app\"}}",
            line,
        )
    }

    @Test
    fun lifecycleAndThreadRequestsEncodeCurrentWireShape() {
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"mobidex\",\"title\":\"Mobidex\",\"version\":\"0.1.0\"},\"capabilities\":{\"experimentalApi\":true}}}",
            CodexRpcRequests.initialize(id = 1, name = "mobidex", title = "Mobidex", version = "0.1.0").encodeJsonLine(),
        )
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}",
            CodexRpcNotifications.initialized().encodeJsonLine(),
        )
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"thread/loaded/list\",\"params\":{\"limit\":200}}",
            CodexRpcRequests.loadedThreadList(id = 2).encodeJsonLine(),
        )
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"thread/read\",\"params\":{\"threadId\":\"thread-1\",\"includeTurns\":true}}",
            CodexRpcRequests.readThread(id = 3, threadId = "thread-1", includeTurns = true).encodeJsonLine(),
        )
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"thread/resume\",\"params\":{\"threadId\":\"thread-1\"}}",
            CodexRpcRequests.resumeThread(id = 4, threadId = "thread-1").encodeJsonLine(),
        )
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"thread/start\",\"params\":{\"cwd\":\"/srv/app\"}}",
            CodexRpcRequests.startThread(id = 5, cwd = "/srv/app").encodeJsonLine(),
        )
    }

    @Test
    fun startTurnRequestEncodesCurrentWireShape() {
        val line = CodexRpcRequests.startTurn(
            id = 2,
            threadId = "thread-1",
            input = listOf(CodexInputItem.Text("Run tests")),
        ).encodeJsonLine()

        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"turn/start\",\"params\":{\"threadId\":\"thread-1\",\"input\":[{\"type\":\"text\",\"text\":\"Run tests\",\"text_elements\":[]}]}}",
            line,
        )
    }

    @Test
    fun startTurnWithOptionsEncodesCurrentWireShape() {
        val line = CodexRpcRequests.startTurn(
            id = 3,
            threadId = "thread-1",
            input = listOf(CodexInputItem.Text("Run tests")),
            options = CodexTurnOptions(
                reasoningEffort = CodexReasoningEffortOption.XHigh,
                accessMode = CodexAccessMode.WorkspaceWrite,
                cwd = "/srv/app",
            ),
        ).encodeJsonLine()

        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"turn/start\",\"params\":{\"effort\":\"xhigh\",\"approvalPolicy\":\"on-request\",\"sandboxPolicy\":{\"type\":\"workspaceWrite\",\"writableRoots\":[\"/srv/app\"],\"networkAccess\":true,\"excludeTmpdirEnvVar\":false,\"excludeSlashTmp\":false},\"threadId\":\"thread-1\",\"input\":[{\"type\":\"text\",\"text\":\"Run tests\",\"text_elements\":[]}]}}",
            line,
        )
    }

    @Test
    fun turnControlRequestsEncodeCurrentWireShape() {
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"turn/interrupt\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\"}}",
            CodexRpcRequests.interruptTurn(id = 1, threadId = "thread-1", turnId = "turn-1").encodeJsonLine(),
        )
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"turn/steer\",\"params\":{\"threadId\":\"thread-1\",\"expectedTurnId\":\"turn-1\",\"input\":[{\"type\":\"text\",\"text\":\"Keep going\",\"text_elements\":[]}]}}",
            CodexRpcRequests.steerTurn(
                id = 2,
                threadId = "thread-1",
                expectedTurnId = "turn-1",
                input = listOf(CodexInputItem.Text("Keep going")),
            ).encodeJsonLine(),
        )
    }

    @Test
    fun jsonEncodingEscapesStrings() {
        assertEquals("\"line\\nquote\\\"slash\\\\\"", JsonValueCodec.encode(jsonString("line\nquote\"slash\\")))
    }

    @Test
    fun jsonEncodingKeepsLargeIntegers() {
        assertEquals("2147483648", JsonValueCodec.encode(jsonInt(2_147_483_648L)))
    }
}

class CodexRpcClientCoreTest {
    @Test
    fun clientCoreAllocatesRequestIDsAndEncodesLines() {
        val core = CodexRpcClientCore()

        val first = core.nextRequest("thread/read", jsonObject(mapOf("threadId" to jsonString("thread-1"))))
        val second = core.nextRequest("thread/list")

        assertEquals(1, first.id)
        assertEquals("thread/read", first.method)
        assertEquals(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"thread/read\",\"params\":{\"threadId\":\"thread-1\"}}",
            first.line,
        )
        assertEquals(2, second.id)
        assertEquals("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"thread/list\"}", second.line)
        assertEquals("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}", core.notificationLine("initialized"))
    }

    @Test
    fun clientCoreClassifiesInboundEnvelopes() {
        val core = CodexRpcClientCore()

        val result = core.classifyInbound(CodexRpcInboundEnvelope(id = jsonInt(1), result = jsonString("ok")))
        assertEquals("resultResponse", result?.kind)
        assertEquals(1, result?.numericId)
        assertEquals(jsonString("ok"), result?.result)

        val stringIDResult = core.classifyInbound(CodexRpcInboundEnvelope(id = jsonString("2147483648"), result = jsonString("ok")))
        assertEquals("resultResponse", stringIDResult?.kind)
        assertEquals(2_147_483_648L, stringIDResult?.numericId)

        val error = core.classifyInbound(
            CodexRpcInboundEnvelope(id = jsonInt(2), error = CodexRpcErrorInfo(code = -1, message = "nope"))
        )
        assertEquals("errorResponse", error?.kind)
        assertEquals(2, error?.numericId)
        assertEquals("nope", error?.error?.message)

        val serverRequest = core.classifyInbound(
            CodexRpcInboundEnvelope(id = jsonString("server-1"), method = "permission/request")
        )
        assertEquals("serverRequest", serverRequest?.kind)
        assertEquals(jsonString("server-1"), serverRequest?.id)

        val notification = core.classifyInbound(CodexRpcInboundEnvelope(method = "turn/started"))
        assertEquals("notification", notification?.kind)
    }
}
