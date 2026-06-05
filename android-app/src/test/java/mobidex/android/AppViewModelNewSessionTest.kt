package mobidex.android

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mobidex.android.data.CredentialStore
import mobidex.android.data.HostKeyStore
import mobidex.android.data.ServerRepository
import mobidex.android.model.CodexThread
import mobidex.android.model.CodexThreadStatus
import mobidex.android.model.ProjectRecord
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.ServerRecord
import mobidex.android.service.CodexAppServerClient
import mobidex.android.service.CodexLineTransport
import mobidex.android.service.MobidexSshService
import mobidex.android.service.RemoteTerminalSession
import mobidex.shared.RemoteDirectoryListing
import mobidex.shared.RemoteProject
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class AppViewModelNewSessionTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun installMainDispatcher() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun resetMainDispatcher() {
        Dispatchers.resetMain()
    }

    @Test
    fun startNewSessionConnectsWhenDisconnectedAndSelectsCreatedThread() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val transport = ScriptedAppServerTransport()
        val ssh = FakeSshService(transport)
        val model = viewModel(server, ssh)
        advanceUntilIdle()

        var completed = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        waitUntil { completed }

        assertTrue(completed, "state=${model.state.value}, methods=${transport.sentMethods}")
        assertEquals(1, ssh.openAppServerCount)
        assertEquals(ServerConnectionState.Connected, model.state.value.connectionState)
        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals(listOf("thread/start", "thread/loaded/list"), transport.sentMethods)
    }

    @Test
    fun selectingCurrentProjectShowsSessionListWithoutOpeningCachedThread() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val transport = ScriptedAppServerTransport()
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        var completed = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        waitUntil { completed }
        assertEquals("thread-new", model.state.value.selectedThreadID)

        model.selectProject(project.id)
        advanceUntilIdle()

        assertEquals(project.id, model.state.value.selectedProjectID)
        assertEquals(null, model.state.value.selectedThreadID)
        assertEquals(null, model.state.value.selectedThread)
        assertTrue(model.state.value.conversationSections.isEmpty())
        assertEquals(listOf("thread-new"), model.state.value.threads.map { it.id })
    }

    @Test
    fun startNewSessionConnectionFailureDoesNotLeaveConnectingState() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val ssh = FakeSshService(openFailure = IllegalStateException("auth failed"))
        val model = viewModel(server, ssh)
        advanceUntilIdle()

        var completed = true
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        waitUntil { !model.state.value.isBusy && !model.state.value.isStartingNewSession }

        assertFalse(completed)
        assertEquals(ServerConnectionState.Failed, model.state.value.connectionState)
        assertEquals("auth failed", model.state.value.failureMessage)
        assertEquals("auth failed", model.state.value.statusMessage)
    }

    @Test
    fun startNewSessionBlocksOpeningAnotherThreadUntilCreationFinishes() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val existing = thread("thread-old", project.path, preview = "Old work")
        val server = server(project)
        val startGate = CompletableDeferred<Unit>()
        val transport = ScriptedAppServerTransport(startThreadGate = startGate)
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        var completed = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        transport.awaitMethod("thread/start")
        advanceUntilIdle()

        model.openThread(existing)
        advanceUntilIdle()
        assertEquals(null, model.state.value.selectedThreadID)
        assertEquals("Wait for the current session action to finish before opening another session.", model.state.value.statusMessage)

        startGate.complete(Unit)
        waitUntil { completed }
        assertTrue(completed, "state=${model.state.value}, methods=${transport.sentMethods}")
        assertEquals("thread-new", model.state.value.selectedThreadID)
    }

    @Test
    fun sendComposerInputBlocksOpeningAnotherThreadWhileTurnStarts() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val current = thread("thread-current", project.path, preview = "Current")
        val other = thread("thread-other", project.path, preview = "Other")
        val server = server(project)
        val turnGate = CompletableDeferred<Unit>()
        val transport = ScriptedAppServerTransport(startTurnGate = turnGate)
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()
        var startCompleted = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { startCompleted = it }
        waitUntil { startCompleted }
        assertEquals("thread-new", model.state.value.selectedThreadID)

        model.openThread(current)
        waitUntil { model.state.value.selectedThreadID == "thread-current" }
        assertEquals("thread-current", model.state.value.selectedThreadID)
        val resumeCountBeforeBlockedOpen = transport.sentMethods.count { it == "thread/resume" }

        var completed = false
        model.sendComposerInput("Do work", emptyList()) { completed = it }
        transport.awaitMethod("turn/start")
        advanceUntilIdle()

        model.openThread(other)
        advanceUntilIdle()
        assertEquals("thread-current", model.state.value.selectedThreadID)
        assertEquals("Wait for the current session action to finish before opening another session.", model.state.value.statusMessage)

        turnGate.complete(Unit)
        waitUntil { completed }
        assertTrue(completed)
        assertEquals("thread-current", model.state.value.selectedThreadID)
        assertEquals(resumeCountBeforeBlockedOpen, transport.sentMethods.count { it == "thread/resume" })
    }

    private fun viewModel(server: ServerRecord, ssh: FakeSshService): AppViewModel =
        AppViewModel(
            context = ApplicationProvider.getApplicationContext<Context>(),
            repository = FakeServerRepository(listOf(server)),
            credentialStore = FakeCredentialStore(),
            hostKeyStore = FakeHostKeyStore(),
            sshService = ssh,
        )

    private fun server(project: ProjectRecord): ServerRecord =
        ServerRecord(
            displayName = "Devbox",
            host = "example.com",
            username = "ubuntu",
            authMethod = ServerAuthMethod.Password,
            projects = listOf(project),
        )

    private fun thread(id: String, cwd: String, preview: String = "New work"): CodexThread =
        CodexThread(
            id = id,
            preview = preview,
            cwd = cwd,
            status = CodexThreadStatus("idle"),
            updatedAtEpochSeconds = 1_770_000_300,
            createdAtEpochSeconds = 1_770_000_000,
        )
}

private class FakeServerRepository(initialServers: List<ServerRecord>) : ServerRepository {
    var servers = initialServers

    override suspend fun loadServers(): List<ServerRecord> = servers

    override suspend fun saveServers(servers: List<ServerRecord>) {
        this.servers = servers
    }
}

private suspend fun waitUntil(timeoutMillis: Long = 2_000, condition: () -> Boolean) {
    withTimeout(timeoutMillis) {
        while (!condition()) {
            delay(10)
        }
    }
}

private class FakeCredentialStore : CredentialStore {
    override suspend fun loadCredential(serverID: String): SSHCredential = SSHCredential(password = "secret")
    override suspend fun saveCredential(credential: SSHCredential, serverID: String) = Unit
    override suspend fun deleteCredential(serverID: String) = Unit
    override suspend fun loadOpenAIAPIKey(): String? = null
    override suspend fun saveOpenAIAPIKey(key: String?) = Unit
    // XAI methods removed; ACP uses same auth model as Codex (SSH is sufficient).
}

private class FakeHostKeyStore : HostKeyStore {
    override fun loadHostKeyFingerprint(serverID: String): String? = null
    override fun saveHostKeyFingerprint(serverID: String, host: String, port: Int, fingerprint: String) = Unit
    override fun deleteHostKeyFingerprint(serverID: String) = Unit
}

private class FakeSshService(
    private val transport: ScriptedAppServerTransport = ScriptedAppServerTransport(),
    private val openFailure: Throwable? = null,
) : MobidexSshService {
    var openAppServerCount = 0

    override suspend fun testConnection(server: ServerRecord, credential: SSHCredential) = Unit
    override suspend fun discoverProjects(server: ServerRecord, credential: SSHCredential): List<RemoteProject> = emptyList()
    override suspend fun listDirectories(path: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        error("Directory listing is not used by these tests.")
    override suspend fun createDirectory(parentPath: String, folderName: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        error("Directory creation is not used by these tests.")
    override suspend fun ensureDirectory(path: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        error("Directory creation is not used by these tests.")
    override suspend fun createCodexWorktree(projectPath: String, server: ServerRecord, credential: SSHCredential): String = "$projectPath-worktree"
    override suspend fun stageLocalFiles(localPaths: List<String>, server: ServerRecord, credential: SSHCredential): List<String> = emptyList()
    override suspend fun openAppServer(server: ServerRecord, credential: SSHCredential): CodexAppServerClient {
        openAppServerCount += 1
        openFailure?.let { throw it }
        return CodexAppServerClient(transport)
    }
    override suspend fun openRawExec(server: ServerRecord, credential: SSHCredential, command: String): CodexLineTransport =
        error("Raw exec / ACP path is not used by these tests.")
    override suspend fun openTerminal(cwd: String?, columns: Int, rows: Int, server: ServerRecord, credential: SSHCredential): RemoteTerminalSession =
        error("Terminal is not used by these tests.")
}

private class ScriptedAppServerTransport(
    private val startThreadGate: CompletableDeferred<Unit>? = null,
    private val startTurnGate: CompletableDeferred<Unit>? = null,
) : CodexLineTransport {
    private val inbound = Channel<String>(Channel.UNLIMITED)
    private val observedMethods = mutableMapOf<String, CompletableDeferred<Unit>>()
    val sentMethods = mutableListOf<String>()

    override val inboundLines: Flow<String> = inbound.receiveAsFlow()

    override suspend fun sendLine(line: String) {
        val request = Json.parseToJsonElement(line).jsonObject
        val id = request["id"] ?: JsonPrimitive(0)
        val method = request["method"]?.jsonPrimitive?.contentOrNull.orEmpty()
        sentMethods += method
        observedMethods.getOrPut(method) { CompletableDeferred() }.complete(Unit)
        when (method) {
            "thread/start" -> {
                startThreadGate?.await()
                respond(id, buildJsonObject { put("thread", threadJson("thread-new", "/srv/app")) })
            }
            "thread/list" -> respond(id, buildJsonObject { put("data", JsonArray(listOf(threadJson("thread-new", "/srv/app")))) })
            "thread/resume", "thread/read" -> {
                val threadID = request["params"]?.jsonObject?.get("threadId")?.jsonPrimitive?.contentOrNull ?: "thread-current"
                respond(id, buildJsonObject { put("thread", threadJson(threadID, "/srv/app")) })
            }
            "turn/start" -> {
                startTurnGate?.await()
                respond(id, buildJsonObject {
                    put("turn", buildJsonObject {
                        put("id", JsonPrimitive("turn-1"))
                        put("status", JsonPrimitive("completed"))
                        put("items", JsonArray(emptyList()))
                    })
                })
            }
            else -> respond(id, buildJsonObject { })
        }
    }

    suspend fun awaitMethod(method: String) {
        observedMethods.getOrPut(method) { CompletableDeferred() }.await()
    }

    override suspend fun close() {
        inbound.close()
    }

    private suspend fun respond(id: JsonElement, result: JsonElement) {
        inbound.send(JsonObject(mapOf("jsonrpc" to JsonPrimitive("2.0"), "id" to id, "result" to result)).toString())
    }

    private fun threadJson(id: String, cwd: String): JsonObject =
        buildJsonObject {
            put("id", JsonPrimitive(id))
            put("preview", JsonPrimitive(id))
            put("cwd", JsonPrimitive(cwd))
            put("status", buildJsonObject { put("type", JsonPrimitive("idle")) })
            put("updatedAt", JsonPrimitive(1_770_000_300))
            put("createdAt", JsonPrimitive(1_770_000_000))
            put("turns", JsonArray(emptyList()))
        }
}
