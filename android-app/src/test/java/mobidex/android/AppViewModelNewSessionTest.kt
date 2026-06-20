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
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
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
import mobidex.android.model.conversationSections
import mobidex.android.service.MobidexSshService
import mobidex.android.service.RemoteTerminalSession
import mobidex.shared.CodexAccessMode
import mobidex.shared.ConversationSectionKind
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
    fun startNewSessionDefaultsToWorktreeAndStartsThreadThere() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val transport = ScriptedAppServerTransport(
            threadListResponses = ArrayDeque(List(6) { emptyList<JsonObject>() }),
        )
        val ssh = FakeSshService(transport)
        val model = viewModel(server, ssh)
        advanceUntilIdle()

        var completed = false
        model.startNewSession { completed = it }
        waitUntil { completed }

        assertTrue(completed, "state=${model.state.value}, methods=${transport.sentMethods}")
        assertEquals(listOf("/srv/app"), ssh.createdWorktreeProjectPaths)
        assertEquals(listOf<String?>("/srv/app-worktree"), transport.startThreadCwds)
        assertEquals(listOf<List<String>?>(listOf("/srv/app-worktree")), transport.startThreadRuntimeWorkspaceRoots)
        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals("/srv/app-worktree", model.state.value.selectedThread?.cwd)
        assertEquals(listOf("/srv/app", "/srv/app-worktree"), model.state.value.selectedProject?.sessionPaths)

        model.refreshThreads()
        waitUntil { transport.sentMethods.count { it == "thread/list" } >= 2 }
        advanceUntilIdle()

        assertEquals(
            listOf<List<String>?>(
                listOf("/srv/app", "/srv/app-worktree"),
                null,
            ),
            transport.threadListCwdFilters.takeLast(2),
        )
        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals("/srv/app-worktree", model.state.value.selectedThread?.cwd)
        assertEquals(listOf("thread-new"), model.state.value.threads.map { it.id })
    }

    @Test
    fun worktreeSessionSurvivesStaleDiscoveryAndEmptyThreadLists() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app", discovered = true, isAdded = true)
        val server = server(project)
        val transport = ScriptedAppServerTransport(
            threadListResponseProvider = { emptyList() },
        )
        val ssh = FakeSshService(
            transport,
            discoveredProjects = listOf(
                RemoteProject(
                    path = "/srv/app",
                    sessionPaths = listOf("/srv/app"),
                    discoveredSessionCount = 1,
                )
            ),
        )
        val model = viewModel(server, ssh)
        advanceUntilIdle()

        var completed = false
        model.startNewSession { completed = it }
        waitUntil { completed }

        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals("/srv/app-worktree", model.state.value.selectedThread?.cwd)

        val projectRefreshCount = transport.sentMethods.count { it == "thread/loaded/list" }
        model.refreshProjects()
        waitUntil {
            transport.sentMethods.count { it == "thread/loaded/list" } > projectRefreshCount &&
                !model.state.value.isDiscoveringProjects
        }
        assertEquals(
            listOf("/srv/app", "/srv/app-worktree"),
            model.state.value.selectedProject?.sessionPaths,
        )

        val listCount = transport.sentMethods.count { it == "thread/list" }
        model.refreshThreads()
        waitUntil { transport.sentMethods.count { it == "thread/list" } > listCount }
        advanceUntilIdle()

        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals("/srv/app-worktree", model.state.value.selectedThread?.cwd)
        assertEquals(listOf("thread-new"), model.state.value.threads.map { it.id })
    }

    @Test
    fun startNoFolderSessionFromProjectListOmitsCwd() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val transport = ScriptedAppServerTransport()
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        var completed = false
        model.startNoFolderSession { completed = it }
        waitUntil { completed }

        assertTrue(completed, "state=${model.state.value}, methods=${transport.sentMethods}")
        assertEquals(listOf<String?>(null), transport.startThreadCwds)
        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals(appServerDefaultCwd, model.state.value.selectedThread?.cwd)
        assertEquals("No Folder", model.state.value.selectedThread?.folderLabel)
        assertEquals(true, model.state.value.selectedThread?.isFolderless)
        assertEquals(listOf("thread-new"), model.state.value.noFolderThreads.map { it.id })
        assertEquals(listOf("thread-new"), model.state.value.selectedServer?.unscopedThreadIDs)

        val notificationListCount = transport.sentMethods.count { it == "thread/list" }
        transport.notifyThreadStarted("thread-new", appServerDefaultCwd)
        waitUntil { transport.sentMethods.count { it == "thread/list" } > notificationListCount }
        assertEquals("No Folder", model.state.value.selectedThread?.folderLabel)
        assertEquals(true, model.state.value.selectedThread?.isFolderless)

        model.setAccessMode(CodexAccessMode.WorkspaceWrite)
        var sendCompleted = false
        model.sendComposerInput("Follow up", emptyList()) { sendCompleted = it }
        waitUntil { transport.startTurnParams.isNotEmpty() }
        val turnParams = transport.startTurnParams.last()
        assertEquals("thread-new", turnParams["threadId"]?.jsonPrimitive?.contentOrNull)
        val sandboxPolicy = turnParams["sandboxPolicy"]?.jsonObject
        assertEquals("workspaceWrite", sandboxPolicy?.get("type")?.jsonPrimitive?.contentOrNull)
        assertEquals(0, (sandboxPolicy?.get("writableRoots") as? JsonArray)?.size)
        waitUntil { sendCompleted }
    }

    @Test
    fun startNoFolderSessionUsesObservedCodexChatRoot() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val desktopChat = threadJson(
            id = "thread-desktop-chat",
            cwd = "/Users/mazdak/Documents/Codex/2026-06-14/desktop-chat",
        )
        val transport = ScriptedAppServerTransport(
            threadListResponseProvider = { request ->
                val cwd = request["params"]?.jsonObject?.get("cwd")?.jsonPrimitive?.contentOrNull
                if (cwd == null) listOf(desktopChat) else emptyList()
            },
        )
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        model.connectSelectedServer()
        waitUntil {
            model.state.value.connectionState == ServerConnectionState.Connected &&
                !model.state.value.isRefreshingSessions &&
                transport.sentMethods.any { it == "thread/list" }
        }

        val connectedListCount = transport.sentMethods.count { it == "thread/list" }
        model.selectAllSessionsAndRefresh()
        waitUntil {
            model.state.value.isShowingAllSessions &&
                !model.state.value.isRefreshingSessions &&
                transport.sentMethods.count { it == "thread/list" } > connectedListCount
        }
        assertEquals(
            listOf("thread-desktop-chat"),
            model.state.value.noFolderThreads.map { it.id },
            "state=${model.state.value}, methods=${transport.sentMethods}",
        )

        var completed = false
        model.startNoFolderSession { completed = it }
        waitUntil { completed }

        assertTrue(completed, "state=${model.state.value}, methods=${transport.sentMethods}")
        assertEquals("/Users/mazdak/Documents/Codex", transport.startThreadCwds.last())
        assertEquals("/Users/mazdak/Documents/Codex", model.state.value.selectedThread?.cwd)
        assertEquals("No Folder", model.state.value.selectedThread?.folderLabel)
        assertEquals(listOf("thread-new", "thread-desktop-chat"), model.state.value.noFolderThreads.map { it.id })
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
        runCurrent()

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
    fun startNewSessionSelectionSurvivesOlderStaleThreadRefresh() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app", sessionPaths = emptyList())
        val server = server(project)
        val staleListGate = CompletableDeferred<Unit>()
        val transport = ScriptedAppServerTransport(
            threadListGates = ArrayDeque(listOf(null, staleListGate)),
            threadListResponses = ArrayDeque(listOf(emptyList<JsonObject>(), emptyList())),
        )
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        model.connectSelectedServer()
        waitUntil { transport.sentMethods.count { it == "thread/list" } >= 2 }

        var completed = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        waitUntil { completed }
        assertEquals("thread-new", model.state.value.selectedThreadID)

        staleListGate.complete(Unit)
        waitUntil { transport.sentMethods.count { it == "thread/list" } >= 2 }
        advanceUntilIdle()

        assertEquals("thread-new", model.state.value.selectedThreadID)
        assertEquals("thread-new", model.state.value.selectedThread?.id)
    }

    @Test
    fun threadStartedNotificationDuringNewSessionDoesNotLaunchSessionRefresh() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val startGate = CompletableDeferred<Unit>()
        val transport = ScriptedAppServerTransport(startThreadGate = startGate)
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        var completed = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        transport.awaitMethod("thread/start")
        runCurrent()

        transport.notifyThreadStarted("thread-new", project.path)
        waitUntil { model.state.value.selectedThreadID == "thread-new" }
        advanceTimeBy(1_000)
        runCurrent()

        assertFalse("thread/list" in transport.sentMethods, "methods=${transport.sentMethods}")
        startGate.complete(Unit)
        waitUntil { completed }
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
        // Drain the open-session refresh so its trailing "Projects synced." status can't
        // race past the blocked-open message asserted below.
        waitUntil { !model.state.value.isBusy }
        val resumeCountBeforeBlockedOpen = transport.sentMethods.count { it == "thread/resume" }

        var completed = false
        model.sendComposerInput("Do work", emptyList()) { completed = it }
        transport.awaitMethod("turn/start")
        // Bounded advance, not advanceUntilIdle: idling fast-forwards 120s of virtual time,
        // which can expire an in-flight RPC whose response still rides a real IO thread.
        advanceTimeBy(1_000)
        runCurrent()

        model.openThread(other)
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals("thread-current", model.state.value.selectedThreadID)
        assertEquals("Wait for the current session action to finish before opening another session.", model.state.value.statusMessage)

        turnGate.complete(Unit)
        waitUntil { completed }
        assertTrue(completed)
        assertEquals("thread-current", model.state.value.selectedThreadID)
        assertEquals(resumeCountBeforeBlockedOpen, transport.sentMethods.count { it == "thread/resume" })
    }

    @Test
    fun streamedDeltasKeepConversationSectionsEqualToFullProjection() = runTest(dispatcher) {
        val project = ProjectRecord(path = "/srv/app")
        val server = server(project)
        val transport = ScriptedAppServerTransport()
        val model = viewModel(server, FakeSshService(transport))
        advanceUntilIdle()

        var completed = false
        model.startNewSession(NewSessionLocation.ProjectDirectory) { completed = it }
        waitUntil { completed }
        assertEquals("thread-new", model.state.value.selectedThreadID)

        transport.notify(
            "turn/started",
            buildJsonObject {
                put("threadId", JsonPrimitive("thread-new"))
                put("turn", buildJsonObject {
                    put("id", JsonPrimitive("turn-1"))
                    put("status", JsonPrimitive("inProgress"))
                    put("items", JsonArray(emptyList()))
                })
            },
        )
        transport.notify(
            "item/started",
            buildJsonObject {
                put("threadId", JsonPrimitive("thread-new"))
                put("item", buildJsonObject {
                    put("type", JsonPrimitive("agentMessage"))
                    put("id", JsonPrimitive("item-1"))
                    put("text", JsonPrimitive("Hel"))
                })
            },
        )
        transport.notify(
            "item/agentMessage/delta",
            buildJsonObject {
                put("threadId", JsonPrimitive("thread-new"))
                put("itemId", JsonPrimitive("item-1"))
                put("delta", JsonPrimitive("lo"))
            },
        )
        transport.notify(
            "item/agentMessage/delta",
            buildJsonObject {
                put("threadId", JsonPrimitive("thread-new"))
                put("itemId", JsonPrimitive("item-1"))
                put("delta", JsonPrimitive(" world"))
            },
        )
        // Events arrive via the client's real IO read loop; wait for the conflated flush
        // to publish the fully accumulated section instead of advancing virtual time once.
        waitUntil(timeoutMillis = 10_000) {
            model.state.value.conversationSections.any {
                it.kind == ConversationSectionKind.Assistant && it.body == "Hello world"
            }
        }

        val state = model.state.value
        val assistantBodies = state.conversationSections
            .filter { it.kind == ConversationSectionKind.Assistant }
            .map { it.body }
        assertEquals(listOf("Hello world"), assistantBodies)
        // Invariant: the published (incremental + conflated) sections always equal the
        // full projection of the selected thread.
        assertEquals(state.selectedThread?.conversationSections().orEmpty(), state.conversationSections)
    }

    private fun viewModel(server: ServerRecord, ssh: FakeSshService): AppViewModel =
        AppViewModel(
            context = ApplicationProvider.getApplicationContext<Context>(),
            repository = FakeServerRepository(listOf(server)),
            credentialStore = FakeCredentialStore(),
            hostKeyStore = FakeHostKeyStore(),
            sshService = ssh,
            // Keep off-main parse/projection hops in the test scheduler's virtual time.
            projectionDispatcher = dispatcher,
        )

    private fun server(project: ProjectRecord): ServerRecord =
        server(listOf(project))

    private fun server(projects: List<ProjectRecord>): ServerRecord =
        ServerRecord(
            displayName = "Devbox",
            host = "example.com",
            username = "ubuntu",
            authMethod = ServerAuthMethod.Password,
            projects = projects,
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
    private val discoveredProjects: List<RemoteProject> = emptyList(),
) : MobidexSshService {
    var openAppServerCount = 0
    val createdWorktreeProjectPaths = mutableListOf<String>()

    override suspend fun testConnection(server: ServerRecord, credential: SSHCredential) = Unit
    override suspend fun discoverProjects(server: ServerRecord, credential: SSHCredential): List<RemoteProject> = discoveredProjects
    override suspend fun listDirectories(path: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        error("Directory listing is not used by these tests.")
    override suspend fun createDirectory(parentPath: String, folderName: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        error("Directory creation is not used by these tests.")
    override suspend fun ensureDirectory(path: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        error("Directory creation is not used by these tests.")
    override suspend fun createCodexWorktree(projectPath: String, server: ServerRecord, credential: SSHCredential): String {
        createdWorktreeProjectPaths += projectPath
        return "$projectPath-worktree"
    }
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

private const val appServerDefaultCwd = "/home/mazdak"

private class ScriptedAppServerTransport(
    private val startThreadGate: CompletableDeferred<Unit>? = null,
    private val startTurnGate: CompletableDeferred<Unit>? = null,
    private val threadListGates: ArrayDeque<CompletableDeferred<Unit>?> = ArrayDeque(),
    private val threadListResponses: ArrayDeque<List<JsonObject>> = ArrayDeque(),
    private val threadListResponseProvider: ((JsonObject) -> List<JsonObject>?)? = null,
) : CodexLineTransport {
    private val inbound = Channel<String>(Channel.UNLIMITED)
    private val observedMethods = mutableMapOf<String, CompletableDeferred<Unit>>()
    private val threadCwds = mutableMapOf<String, String>()
    val sentMethods = mutableListOf<String>()
    val startThreadCwds = mutableListOf<String?>()
    val startThreadRuntimeWorkspaceRoots = mutableListOf<List<String>?>()
    val threadListCwdFilters = mutableListOf<List<String>?>()
    val startTurnParams = mutableListOf<JsonObject>()

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
                val params = request["params"]?.jsonObject
                val cwd = params?.get("cwd")?.jsonPrimitive?.contentOrNull
                val runtimeWorkspaceRoots = (params?.get("runtimeWorkspaceRoots") as? JsonArray)
                    ?.mapNotNull { it.jsonPrimitive.contentOrNull }
                startThreadCwds += cwd
                startThreadRuntimeWorkspaceRoots += runtimeWorkspaceRoots
                val threadCwd = cwd ?: appServerDefaultCwd
                threadCwds["thread-new"] = threadCwd
                respond(id, buildJsonObject { put("thread", threadJson("thread-new", threadCwd)) })
            }
            "thread/list" -> {
                threadListCwdFilters += cwdFilter(request["params"]?.jsonObject?.get("cwd"))
                val gate = if (threadListGates.isEmpty()) null else threadListGates.removeFirst()
                gate?.await()
                val threads = threadListResponseProvider?.invoke(request)
                    ?: threadListResponses.removeFirstOrNull()
                    ?: listOf(threadJson("thread-new", "/srv/app"))
                respond(id, buildJsonObject { put("data", JsonArray(threads)) })
            }
            "thread/resume", "thread/read" -> {
                val threadID = request["params"]?.jsonObject?.get("threadId")?.jsonPrimitive?.contentOrNull ?: "thread-current"
                respond(id, buildJsonObject { put("thread", threadJson(threadID, threadCwds[threadID] ?: "/srv/app")) })
            }
            "turn/start" -> {
                startTurnParams += request["params"]?.jsonObject ?: buildJsonObject { }
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

    suspend fun notify(method: String, params: JsonObject) {
        inbound.send(
            JsonObject(
                mapOf(
                    "jsonrpc" to JsonPrimitive("2.0"),
                    "method" to JsonPrimitive(method),
                    "params" to params,
                )
            ).toString()
        )
    }

    suspend fun notifyThreadStarted(id: String, cwd: String) {
        notify("thread/started", buildJsonObject { put("thread", threadJson(id, cwd)) })
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

    private fun cwdFilter(value: JsonElement?): List<String>? = when (value) {
        is JsonArray -> value.mapNotNull { it.jsonPrimitive.contentOrNull }
        is JsonPrimitive -> value.contentOrNull?.let(::listOf)
        else -> null
    }
}
