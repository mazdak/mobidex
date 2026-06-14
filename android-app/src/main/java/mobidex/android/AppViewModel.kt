package mobidex.android

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mobidex.android.data.AndroidCredentialStore
import mobidex.android.data.CredentialStore
import mobidex.android.data.HostKeyStore
import mobidex.android.data.ServerRepository
import mobidex.android.data.SharedPreferencesHostKeyStore
import mobidex.android.data.SharedPreferencesServerRepository
import mobidex.android.model.CodexThread
import mobidex.android.model.CodexThreadStatus
import mobidex.android.model.CodexThreadItem
import mobidex.android.model.CodexTurn
import mobidex.android.model.PendingApproval
import mobidex.android.model.ProjectRecord
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.BackendType
import mobidex.android.model.ServerRecord
import mobidex.android.model.conversationSections
import mobidex.android.model.flattenedSharedItems
import mobidex.android.model.toThreadItem
import mobidex.android.service.AcpClient
import mobidex.android.service.CodexAppServerClient
import mobidex.android.service.CodexAppServerEvent
import mobidex.android.service.MobidexSshService
import mobidex.android.service.OpenAITranscriptionService
import mobidex.android.service.RemoteTerminalSession
import mobidex.android.service.SshjMobidexSshService
import mobidex.android.service.array
import mobidex.android.service.bool
import mobidex.android.service.long
import mobidex.android.service.obj
import mobidex.android.service.parseItem
import mobidex.android.service.parseStatus
import mobidex.android.service.parseThread
import mobidex.android.service.parseTokenUsage
import mobidex.android.service.parseTurn
import mobidex.android.service.parseTurnError
import mobidex.android.service.string
import mobidex.android.service.toJsonElement
import mobidex.android.service.toSharedJsonValue
import mobidex.android.service.turnOptions
import mobidex.shared.AcpProtocolCore
import mobidex.shared.appendingAcpSessionItem
import mobidex.shared.CodexAccessMode
import mobidex.shared.CodexInputItem
import mobidex.shared.CodexReasoningEffortOption
import mobidex.shared.CodexSessionCachePolicy
import mobidex.shared.CodexSessionItem
import mobidex.shared.CodexThreadSummary
import mobidex.shared.ConversationSection
import mobidex.shared.ConversationSectionAccumulator
import mobidex.shared.GitDiffSnapshot
import mobidex.shared.JsonValue
import mobidex.shared.ProjectCatalog
import mobidex.shared.ProjectListSections
import mobidex.shared.RemoteAcpCommand
import mobidex.shared.RemoteDirectoryListing
import mobidex.shared.RemoteProject
import mobidex.shared.RemoteServerLaunchDefaults
import mobidex.shared.SessionListSections
import mobidex.shared.jsonArray
import mobidex.shared.jsonNull
import mobidex.shared.jsonObject
import mobidex.shared.jsonString

data class MobidexUiState(
    val servers: List<ServerRecord> = emptyList(),
    val selectedServerID: String? = null,
    val selectedProjectID: String? = null,
    val isShowingAllSessions: Boolean = false,
    val threads: List<CodexThread> = emptyList(),
    val selectedThreadID: String? = null,
    val selectedThread: CodexThread? = null,
    val conversationSections: List<mobidex.shared.ConversationSection> = emptyList(),
    val pendingApprovals: List<PendingApproval> = emptyList(),
    // Model state the ACP agent advertised for the live session (null = no switching).
    val acpModels: mobidex.shared.AcpSessionModels? = null,
    val connectionState: ServerConnectionState = ServerConnectionState.Disconnected,
    val failureMessage: String? = null,
    val statusMessage: String? = null,
    val isBusy: Boolean = false,
    val isRefreshingSessions: Boolean = false,
    val isStartingNewSession: Boolean = false,
    val selectedReasoningEffort: CodexReasoningEffortOption = CodexReasoningEffortOption.Medium,
    val selectedAccessMode: CodexAccessMode = CodexAccessMode.FullAccess,
    val hasOpenAIAPIKey: Boolean = false,
    val showsArchivedSessions: Boolean = false,
    val isDiscoveringProjects: Boolean = false,
    val diffSnapshot: GitDiffSnapshot = GitDiffSnapshot.Empty,
    val isRefreshingChanges: Boolean = false,
    val tokenUsagePercent: Int? = null,
    val queuedTurnInputs: List<QueuedTurnInput> = emptyList(),
    val dismissedMacOSPrivacyWarning: Boolean = false,
) {
    val selectedServer: ServerRecord?
        get() = servers.firstOrNull { it.id == selectedServerID }

    val selectedProject: ProjectRecord?
        get() = selectedServer?.projects?.firstOrNull { it.id == selectedProjectID }

    val canSendMessage: Boolean
        get() = connectionState == ServerConnectionState.Connected && !isStartingNewSession

    val canCreateSession: Boolean
        get() = connectionState != ServerConnectionState.Connecting && selectedServer != null && selectedProject != null && !isBusy && !isStartingNewSession

    val activeTurnID: String?
        get() = selectedThread?.let { activeTurnID(it) }
}

private fun activeTurnID(thread: CodexThread): String? =
    if (thread.status.isActive) {
        thread.turns.lastOrNull { it.status == "inProgress" }?.id ?: thread.turns.lastOrNull()?.id
    } else {
        null
    }

enum class NewSessionLocation {
    CodexWorktree,
    ProjectDirectory,
}

data class QueuedTurnInput(
    val id: String = UUID.randomUUID().toString(),
    val input: List<CodexInputItem>,
) {
    val preview: String
        get() {
            val text = input.filterIsInstance<CodexInputItem.Text>()
                .joinToString(" ") { it.text.trim() }
                .trim()
            if (text.isNotEmpty()) return text
            val attachments = input.count { it is CodexInputItem.LocalImage || it is CodexInputItem.ImageUrl }
            return if (attachments == 1) "1 attachment" else "${maxOf(attachments, 1)} attachments"
        }
}

data class AndroidProjectListSections(
    val projects: List<ProjectRecord>,
    val discovered: List<ProjectRecord>,
    val added: List<ProjectRecord>,
    val showInactiveDiscoveredFilter: Boolean,
    val showArchivedSessionFilter: Boolean,
    val discoveredTitle: String,
) {
    val isEmpty: Boolean
        get() = projects.isEmpty() && discovered.isEmpty() && added.isEmpty()
}

data class AndroidSessionListSection(
    val id: String,
    val title: String,
    val threads: List<CodexThread>,
)

private const val MAX_APP_SERVER_RECONNECT_ATTEMPTS = 3

private data class ThreadScopeCacheKey(
    val serverID: String?,
    val projectID: String?,
    val cwd: String?,
    val sessionPaths: List<String>,
    val isShowingAllSessions: Boolean,
    val includeArchivedSessions: Boolean,
)

private data class ThreadDetailCacheKey(
    val serverID: String?,
    val threadID: String,
)

private data class CachedThreadList(
    val threads: List<CodexThread>,
    val selectedThreadID: String?,
    val fetchedAtEpochSeconds: Long,
)

private data class CachedThreadDetail(
    val thread: CodexThread,
    val fetchedAtEpochSeconds: Long,
)

class AppViewModel(
    context: Context,
    private val repository: ServerRepository,
    private val credentialStore: CredentialStore,
    private val hostKeyStore: HostKeyStore,
    private val sshService: MobidexSshService,
    // Heavy thread parse/projection work hops here (audit B6); tests inject their test
    // dispatcher so that work stays in virtual time.
    private val projectionDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val _state = MutableStateFlow(MobidexUiState())
    val state: StateFlow<MobidexUiState> = _state.asStateFlow()

    private var appServer: CodexAppServerClient? = null
    private var eventJob: Job? = null
    private var diffSnapshotRequestID = 0L
    private var activeSessionRefreshes = 0
    private var sessionRefreshGeneration = 0L
    private var sessionRefreshListLoadGeneration = 0L
    private var sessionRefreshDetailLoadGeneration = 0L
    private var sessionMutationGeneration = 0L
    private val unlistedStartedThreadIDs = mutableSetOf<String>()
    private val sessionListInitialPageLimit = 1
    private var isSendingInput = false
    private var isStartingSession = false
    private val queuedTurnInputsByThreadID = mutableMapOf<String, MutableList<QueuedTurnInput>>()
    private val threadListCache = mutableMapOf<ThreadScopeCacheKey, CachedThreadList>()
    private val threadDetailCache = mutableMapOf<ThreadDetailCacheKey, CachedThreadDetail>()
    private val reconnectAttemptsByServerID = mutableMapOf<String, Int>()
    private var reconnectJob: Job? = null
    private var suppressThreadAutoSelection = false
    private var suppressCachedThreadSelection = false

    // ACP / Grok *production* wiring (acp-production-wiring chunk).
    // When selectedServer.backendType == Acp, connect/send/approval/close paths drive these
    // instead of appServer/eventJob. Collector feeds the *main* conversation state (same hydrate/append
    // paths used by Codex events) so Grok/ACP chunks render as identical rich UI elements (Reasoning,
    // AgentMessage, ToolCall with live status, Plan, interactive AgentEvent) via existing ConversationSection.
    // Zero changes to any Codex paths or parked logic. Reuses AcpClient + mapper + auth + raw-exec.
    private var acpClient: AcpClient? = null
    private var acpJob: Job? = null
    private var acpSessionId: String? = null
    // Bumped by every ACP connect attempt and by disconnect; in-flight attempts that lose
    // the race close what they built instead of installing it.
    private var acpConnectGeneration = 0
    private val _acpSessionItems = MutableStateFlow<List<CodexSessionItem>>(emptyList())

    // Incremental conversation projection (audit B1). Each accumulator mirrors exactly the
    // item list whose projection is published (flattened visible thread items for Codex,
    // _acpSessionItems for ACP); any update that can't be mapped to a single item resets
    // from a full projection so published sections never drift from
    // CodexSessionProjection.sections(items).
    private val codexSections = ConversationSectionAccumulator()
    private var codexSectionsThreadId: String? = null
    private val acpSections = ConversationSectionAccumulator()

    // Streamed section publishes are conflated to ~1 per 50ms with a trailing flush; the
    // per-delta thread-detail cache write rides the same flush instead of running per delta.
    private var sectionsFlushJob: Job? = null
    private var pendingSectionsPublish: (() -> Unit)? = null

    // Counts overlapping runBusy blocks so one finishing doesn't release the gate while
    // another is still mutating session state.
    private var busyCount = 0

    // Teardown on ViewModel clear must not block the main thread (sshj close + join can take
    // seconds per connection); this scope outlives the ViewModel just long enough to close.
    private val teardownScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences("mobidex", Context.MODE_PRIVATE)

    init {
        _state.update {
            it.copy(dismissedMacOSPrivacyWarning = preferences.getBoolean(MACOS_PRIVACY_WARNING_DISMISSED_KEY, false))
        }
        viewModelScope.launch { refreshOpenAIAPIKeyState() }
        viewModelScope.launch { loadServers() }
    }

    suspend fun loadOpenAIAPIKeyForEditing(): String = credentialStore.loadOpenAIAPIKey().orEmpty()

    fun saveOpenAIAPIKey(key: String) {
        viewModelScope.launch {
            runCatching {
                credentialStore.saveOpenAIAPIKey(key.trim().ifEmpty { null })
                refreshOpenAIAPIKeyState()
            }.onSuccess {
                _state.update { state ->
                    state.copy(statusMessage = if (state.hasOpenAIAPIKey) "OpenAI API key saved." else "OpenAI API key removed.")
                }
            }.onFailure { error ->
                _state.update { it.copy(statusMessage = error.message ?: "Could not save OpenAI API key.") }
            }
        }
    }

    suspend fun transcribeAudio(file: File): String {
        val key = credentialStore.loadOpenAIAPIKey()?.takeIf { it.isNotBlank() }
            ?: error("Add an OpenAI API key in Settings before recording audio.")
        return OpenAITranscriptionService().transcribe(file, key)
    }

    suspend fun refreshOpenAIAPIKeyState(): Boolean {
        val hasKey = !credentialStore.loadOpenAIAPIKey().isNullOrBlank()
        _state.update { it.copy(hasOpenAIAPIKey = hasKey) }
        return hasKey
    }

    fun selectServer(serverID: String?) {
        if (_state.value.connectionState == ServerConnectionState.Connected || _state.value.connectionState == ServerConnectionState.Connecting) {
            _state.update { it.copy(statusMessage = "Disconnect before switching servers.") }
            return
        }
        resetSessionRefreshTracking()
        suppressCachedThreadSelection = false
        _state.update { state ->
            val server = state.servers.firstOrNull { it.id == serverID }
            state.copy(
                selectedServerID = serverID,
                selectedProjectID = server?.projects?.firstSavedProjectID,
                isShowingAllSessions = false,
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                pendingApprovals = emptyList(),
                acpModels = null,
                diffSnapshot = GitDiffSnapshot.Empty,
                failureMessage = null,
                statusMessage = null,
                tokenUsagePercent = null,
            )
        }
    }

    fun switchServerFromList(serverID: String?) {
        viewModelScope.launch {
            if (_state.value.selectedServerID == serverID) return@launch
            if (_state.value.connectionState == ServerConnectionState.Connected || _state.value.connectionState == ServerConnectionState.Connecting) {
                disconnectInternal(updateState = false)
                _state.update { it.copy(connectionState = ServerConnectionState.Disconnected) }
            }
            selectServer(serverID)
        }
    }

    fun selectServerAndConnect(serverID: String?) {
        viewModelScope.launch {
            val state = _state.value
            if (state.selectedServerID == serverID && state.connectionState == ServerConnectionState.Connected) return@launch
            if (state.connectionState == ServerConnectionState.Connected || state.connectionState == ServerConnectionState.Connecting) {
                disconnectInternal(updateState = false)
                _state.update { it.copy(connectionState = ServerConnectionState.Disconnected) }
            }
            selectServer(serverID)
            connectSelectedServer()
        }
    }

    fun selectProject(projectID: String?) {
        if (isSessionMutationInFlight()) {
            _state.update { it.copy(statusMessage = "Wait for the current session action to finish before switching projects.") }
            return
        }
        resetSessionRefreshTracking()
        suppressThreadAutoSelection = true
        suppressCachedThreadSelection = true
        _state.update { state ->
            state.copy(
                selectedProjectID = projectID,
                isShowingAllSessions = false,
            )
        }
        val cacheKey = currentThreadScopeCacheKey()
        if (restoreCachedSessionState(cacheKey)) {
            if (!canUseCachedSessionState(cacheKey)) {
                refreshThreadsIfNeeded()
            }
            return
        }
        _state.update { state ->
            state.copy(
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                diffSnapshot = GitDiffSnapshot.Empty,
                tokenUsagePercent = null,
            )
        }
        refreshThreadsIfNeeded()
    }

    fun selectAllSessionsAndRefresh() {
        if (isSessionMutationInFlight()) {
            _state.update { it.copy(statusMessage = "Wait for the current session action to finish before changing session scope.") }
            return
        }
        resetSessionRefreshTracking()
        suppressThreadAutoSelection = true
        suppressCachedThreadSelection = true
        _state.update { state ->
            state.copy(
                selectedProjectID = null,
                isShowingAllSessions = true,
            )
        }
        val cacheKey = currentThreadScopeCacheKey()
        if (restoreCachedSessionState(cacheKey)) {
            if (!canUseCachedSessionState(cacheKey)) {
                refreshThreadsIfNeeded()
            }
            return
        }
        _state.update { state ->
            state.copy(
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                diffSnapshot = GitDiffSnapshot.Empty,
                tokenUsagePercent = null,
            )
        }
        refreshThreadsIfNeeded()
    }

    fun dismissMacOSPrivacyWarningForever() {
        preferences.edit().putBoolean(MACOS_PRIVACY_WARNING_DISMISSED_KEY, true).apply()
        _state.update { it.copy(dismissedMacOSPrivacyWarning = true) }
    }

    fun setReasoningEffort(effort: CodexReasoningEffortOption) {
        _state.update { it.copy(selectedReasoningEffort = effort) }
    }

    fun setAccessMode(mode: CodexAccessMode) {
        _state.update { it.copy(selectedAccessMode = mode) }
    }

    fun setShowsArchivedSessions(show: Boolean) {
        if (_state.value.showsArchivedSessions == show) return
        if (isSessionMutationInFlight()) {
            _state.update { it.copy(statusMessage = "Wait for the current session action to finish before changing session scope.") }
            return
        }
        resetSessionRefreshTracking()
        suppressThreadAutoSelection = true
        _state.update {
            it.copy(
                showsArchivedSessions = show,
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                tokenUsagePercent = null,
            )
        }
        refreshThreadsIfNeeded()
    }

    suspend fun openTerminalSession(columns: Int = 80, rows: Int = 24): RemoteTerminalSession {
        val state = _state.value
        val server = state.selectedServer ?: error("Select a server before opening a terminal.")
        return runCatching {
            _state.update { it.copy(statusMessage = "Opening terminal") }
            sshService.openTerminal(
                cwd = state.selectedThread?.cwd ?: state.selectedProject?.path,
                columns = columns,
                rows = rows,
                server = server,
                credential = credentialStore.loadCredential(server.id),
            )
        }.onSuccess {
            _state.update { state -> state.copy(statusMessage = null) }
        }.onFailure { error ->
            _state.update { state -> state.copy(statusMessage = error.message) }
        }.getOrThrow()
    }

    suspend fun listRemoteDirectories(path: String): RemoteDirectoryListing {
        val state = _state.value
        val server = state.selectedServer ?: error("Select a server before browsing folders.")
        return withRemoteDirectoryBrowseTimeout {
            sshService.listDirectories(path, server, credentialStore.loadCredential(server.id))
        }
    }

    suspend fun createRemoteDirectory(parentPath: String, folderName: String): RemoteDirectoryListing {
        val state = _state.value
        val server = state.selectedServer ?: error("Select a server before creating folders.")
        return withRemoteDirectoryBrowseTimeout {
            sshService.createDirectory(parentPath, folderName, server, credentialStore.loadCredential(server.id))
        }
    }

    suspend fun createRemoteProjectDirectory(path: String): RemoteDirectoryListing {
        val state = _state.value
        val server = state.selectedServer ?: error("Select a server before creating folders.")
        return withRemoteDirectoryBrowseTimeout {
            sshService.ensureDirectory(path, server, credentialStore.loadCredential(server.id))
        }
    }

    fun loadCredential(serverID: String, onLoaded: (SSHCredential) -> Unit) {
        viewModelScope.launch { onLoaded(credentialStore.loadCredential(serverID)) }
    }

    fun saveServer(server: ServerRecord, credential: SSHCredential, connectAfterSave: Boolean) {
        viewModelScope.launch {
            runBusy("Saving server") {
                val next = server.normalized
                require(next.host.isNotBlank()) { "Enter the SSH host for this server." }
                require(next.username.isNotBlank()) { "Enter the SSH username for this server." }
                when (next.authMethod) {
                    mobidex.android.model.ServerAuthMethod.Password -> require(credential.password?.isNotBlank() == true) {
                        "Enter the SSH password for this server."
                    }
                    mobidex.android.model.ServerAuthMethod.PrivateKey -> require(credential.privateKeyPEM?.isNotBlank() == true) {
                        "Paste an OpenSSH private key for this server."
                    }
                }
                credentialStore.saveCredential(credential, next.id)
                val current = _state.value
                val previous = current.servers.firstOrNull { it.id == next.id }
                val editedSelectedServer = current.selectedServerID == next.id
                if (editedSelectedServer && current.connectionState != ServerConnectionState.Disconnected) {
                    disconnectInternal(updateState = false)
                }
                if (editedSelectedServer || previous == null) {
                    resetSessionRefreshTracking()
                }
                val updated = current.servers.upsert(next)
                repository.saveServers(updated)
                _state.update { state ->
                    val saved = state.copy(
                        servers = updated,
                        selectedServerID = next.id,
                        selectedProjectID = next.projects.firstSavedProjectID,
                        isShowingAllSessions = false,
                        connectionState = if (editedSelectedServer) ServerConnectionState.Disconnected else state.connectionState,
                        failureMessage = null,
                        statusMessage = "Saved ${next.displayName}.",
                    )
                    if (editedSelectedServer || previous == null) saved.clearingSessionScope() else saved
                }
                if (connectAfterSave) connectSelectedServer()
            }
        }
    }

    fun deleteServer(server: ServerRecord) {
        viewModelScope.launch {
            runBusy("Deleting server") {
                val current = _state.value
                val wasSelected = current.selectedServerID == server.id
                val updated = current.servers.filterNot { it.id == server.id }
                if (wasSelected) {
                    resetSessionRefreshTracking()
                }
                _state.update { state ->
                    val deleted = state.copy(
                        servers = updated,
                        selectedServerID = updated.firstOrNull()?.id,
                        selectedProjectID = updated.firstOrNull()?.projects?.firstSavedProjectID,
                        isShowingAllSessions = false,
                        connectionState = if (wasSelected) ServerConnectionState.Disconnected else state.connectionState,
                        failureMessage = null,
                        statusMessage = "Deleted ${server.displayName}.",
                    )
                    if (wasSelected) deleted.clearingSessionScope() else deleted
                }
                credentialStore.deleteCredential(server.id)
                hostKeyStore.deleteHostKeyFingerprint(server.id)
                repository.saveServers(updated)
                invalidateSessionCaches(server.id)
                if (wasSelected) disconnectInternal(updateState = false)
            }
        }
    }

    fun addProject(path: String) {
        viewModelScope.launch {
            runBusy("Adding project") {
                val trimmed = path.trim()
                require(trimmed.isNotBlank()) { "Enter a remote project path." }
                val state = _state.value
                val server = state.selectedServer ?: error("Select a server before adding a project.")
                val existing = server.projects.firstOrNull { it.path == trimmed }
                require(existing?.isSavedProject != true) { "That project is already saved." }
                val project = existing?.copy(isAdded = true) ?: ProjectRecord(path = trimmed, isAdded = true)
                val updatedProjects = if (existing == null) {
                    server.projects + project
                } else {
                    server.projects.map { if (it.id == existing.id) project else it }
                }
                val updatedServer = server.copy(projects = updatedProjects, updatedAtEpochSeconds = Instant.now().epochSecond)
                val updated = state.servers.upsert(updatedServer)
                repository.saveServers(updated)
                invalidateSessionCaches(server.id)
                _state.update {
                    it.copy(
                        servers = updated,
                        selectedProjectID = project.id,
                        threads = emptyList(),
                        selectedThreadID = null,
                        selectedThread = null,
                        conversationSections = emptyList(),
                        diffSnapshot = GitDiffSnapshot.Empty,
                        tokenUsagePercent = null,
                        statusMessage = "Added ${project.displayName}.",
                    )
                }
            }
        }
    }

    fun removeProject(project: ProjectRecord) {
        viewModelScope.launch {
            val state = _state.value
            val server = state.selectedServer ?: return@launch
            val updatedProjects = if (project.discovered) {
                server.projects.map { if (it.id == project.id) it.copy(isAdded = false) else it }
            } else {
                server.projects.filterNot { it.id == project.id }
            }
            val updatedServer = server.copy(projects = updatedProjects)
            val updated = state.servers.upsert(updatedServer)
            repository.saveServers(updated)
            invalidateSessionCaches(server.id)
            resetSessionRefreshTracking()
            _state.update { current ->
                val removedSelectedProject = current.selectedProjectID == project.id
                val next = current.copy(
                    servers = updated,
                    selectedProjectID = if (removedSelectedProject) updatedServer.projects.firstSavedProjectID else current.selectedProjectID,
                )
                if (removedSelectedProject) next.clearingSessionScope() else next
            }
        }
    }

    fun setProjectAdded(project: ProjectRecord, added: Boolean) {
        viewModelScope.launch {
            val state = _state.value
            val server = state.selectedServer ?: return@launch
            val updatedServer = server.copy(projects = server.projects.map { if (it.id == project.id) it.copy(isAdded = added) else it })
            val updated = state.servers.upsert(updatedServer)
            repository.saveServers(updated)
            invalidateSessionCaches(server.id)
            _state.update { it.copy(servers = updated) }
        }
    }

    fun testSelectedConnection() {
        viewModelScope.launch {
            runBusy("Testing connection", marksFailure = true) {
                val server = _state.value.selectedServer ?: return@runBusy
                sshService.testConnection(server, credentialStore.loadCredential(server.id))
                _state.update { it.copy(statusMessage = "Connection test passed for ${server.displayName}.") }
            }
        }
    }

    /**
     * Production ACP launch (called from connectSelectedServer / send paths when backendType == Acp).
     * Mirrors the debug path but:
     * - Uses the production acpClient/acpJob/acpSessionId holders (co-scoped with VM)
     * - Collector appends to _acpSessionItems and publishes the ConversationSection list kept
     *   equal to CodexSessionProjection.sections(_acpSessionItems) by the incremental
     *   accumulator (audit B1), conflated to ~1 publish per 50ms during streaming.
     *   This makes ACP chunks (Reasoning/AgentMessage/ToolCall/Plan/AgentEvent) appear in the
     *   normal ConversationView with zero UI or Codex changes.
     * - SSH credential only (no XAI injection; exactly as Codex).
     *
     * Codex connect/send/disconnect bodies are 100% untouched (early return before them).
     */
    private fun startAcpProductionSessionForCurrentProject() {
        viewModelScope.launch {
            val server = _state.value.selectedServer ?: return@launch
            if (server.backendType != BackendType.Acp) return@launch

            // Ownership guard: only the newest connect attempt may install a client; any
            // disconnect or newer connect bumps the generation, and stale attempts close
            // whatever they built instead of installing it (prevents double-connect leaks
            // and disconnect-during-connect resurrecting a connection).
            val generation = ++acpConnectGeneration

            acpJob?.cancel()
            acpClient?.let { runCatching { it.close() } }
            acpClient = null
            acpSessionId = null
            _acpSessionItems.value = emptyList()
            acpSections.reset(emptyList())
            pendingSectionsPublish = null
            _state.update {
                it.copy(
                    conversationSections = emptyList(),
                    pendingApprovals = emptyList(),
                    acpModels = null,
                    failureMessage = null,
                    statusMessage = "Starting ACP agent..."
                )
            }

            runBusy("Starting ACP agent", marksFailure = true) {
                val credential = credentialStore.loadCredential(server.id)
                // Codex parity: SSH is the trust boundary. The remote ACP command inherits
                // the logged-in user's env (no mobile-side agent auth injection).
                val command = RemoteAcpCommand.shellCommand(
                    launchCommand = server.acpLaunchCommand,
                    executionPath = server.executionPath,
                )
                val transport = sshService.openRawExec(server, credential, command)
                if (generation != acpConnectGeneration) {
                    runCatching { transport.close() }
                    return@runBusy
                }
                val client = AcpClient(transport)
                val session = try {
                    client.initialize()
                    // ACP spec requires an absolute cwd on session/new. executionPath is a PATH list
                    // (binary lookup), never a working directory — only a selected project provides cwd.
                    val cwd = _state.value.selectedProject?.path
                        ?: error("Select a project before connecting an ACP agent.")
                    val created = client.createSession(cwd = cwd, title = server.displayName)
                    if (generation != acpConnectGeneration) {
                        runCatching { client.close() }
                        return@runBusy
                    }
                    acpClient = client
                    acpSessionId = created.sessionId
                    created
                } catch (error: Throwable) {
                    // Never strand a half-open transport / remote agent process on failure.
                    runCatching { client.close() }
                    throw error
                }

                _state.update {
                    it.copy(
                        connectionState = ServerConnectionState.Connected,
                        failureMessage = null,
                        acpModels = session.models,
                        statusMessage = "ACP agent session ${session.sessionId} connected."
                    )
                }

                // Past sessions (agents advertising session/list) populate the normal session
                // list so they can be reopened via session/load; empty for agents without it.
                val pastSessions = client.listSessions()
                if (generation == acpConnectGeneration && acpClient === client && pastSessions.isNotEmpty()) {
                    _state.update { state ->
                        state.copy(threads = pastSessions.map { it.toPlaceholderThread() })
                    }
                }

                acpJob = launch {
                    launch {
                        client.sessionItems.collect { item ->
                            if (acpClient !== client) return@collect // stale session
                            // Coalesce streamed deltas / resolve tool cards before projecting.
                            val previous = _acpSessionItems.value
                            val next = previous.appendingAcpSessionItem(item)
                            _acpSessionItems.value = next
                            // Audit B1: mirror the single-item change onto the accumulator
                            // instead of re-projecting the whole session per chunk, then
                            // drive the *main* conversationSections through the conflated
                            // publish. Sections stay equal to the full shared projection.
                            acpSections.applyItemsChange(previous, next)
                            val sections = acpSections.sections.toList()
                            publishStreamedSections {
                                _state.update { s ->
                                    if (acpClient === client && s.selectedServerID == server.id) {
                                        s.copy(conversationSections = sections)
                                    } else {
                                        s
                                    }
                                }
                            }
                        }
                    }
                    launch {
                        client.serverRequests.collect { request ->
                            if (acpClient !== client) return@collect // stale session
                            if (request.method != AcpProtocolCore.PERMISSION_REQUEST_METHOD) return@collect
                            val permission = AcpProtocolCore.parsePermissionRequest(request.params)
                            _state.update {
                                it.copy(
                                    pendingApprovals = it.pendingApprovals + PendingApproval(
                                        id = "acp-${request.id}",
                                        requestId = request.id.toJsonElement(),
                                        method = request.method,
                                        params = request.params?.toJsonElement(),
                                        title = permission.title ?: "Permission required",
                                        detail = permission.detail ?: "",
                                    )
                                )
                            }
                        }
                    }
                    launch {
                        client.disconnects.collect { message ->
                            if (acpClient !== client) return@collect // stale session
                            if (_state.value.selectedServerID == server.id) {
                                _state.update {
                                    it.copy(
                                        connectionState = ServerConnectionState.Failed,
                                        pendingApprovals = emptyList(),
                                        acpModels = null,
                                        failureMessage = message,
                                        statusMessage = message,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fun connectSelectedServer() {
        viewModelScope.launch {
            val server = _state.value.selectedServer ?: return@launch
            if (server.backendType == BackendType.Acp) {
                // ACP production path: delegate to the holder-based launcher + mapper collector.
                // This makes a backendType=acp ServerRecord drive the normal rich chat UI.
                disconnectInternal(updateState = false)
                _state.update { it.copy(connectionState = ServerConnectionState.Connecting, failureMessage = null, statusMessage = "Connecting") }
                startAcpProductionSessionForCurrentProject()
                // Note: the collector inside the helper will set Connected + sections when ready.
                // Early return keeps every byte of the Codex path below 100% unchanged.
                return@launch
            }
            // Codex path (byte-for-byte identical; guardrail enforced in every review).
            reconnectJob?.cancel()
            reconnectJob = null
            disconnectInternal(updateState = false)
            _state.update { it.copy(connectionState = ServerConnectionState.Connecting, failureMessage = null, statusMessage = "Connecting") }
            runBusy("Connecting", marksFailure = true) {
                val credential = credentialStore.loadCredential(server.id)
                val client = sshService.openAppServer(server, credential)
                if (_state.value.selectedServerID != server.id || _state.value.connectionState != ServerConnectionState.Connecting) {
                    client.close()
                    return@runBusy
                }
                appServer = client
                startEventLoop(client)
                val refreshGeneration = beginSessionRefresh()
                var refreshHandedOff = false
                try {
                    _state.update { it.copy(connectionState = ServerConnectionState.Connected, statusMessage = "Server connected.") }
                    reconnectAttemptsByServerID.remove(server.id)
                    runCatching {
                        refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = true)
                    }.recoverCatching {
                        refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = false)
                    }.onFailure { error ->
                        _state.update { it.copy(statusMessage = error.message ?: "Project refresh failed after connect.") }
                    }
                    _state.value.selectedThreadID?.let { threadID ->
                        val requestServerID = _state.value.selectedServerID
                        val requestProjectID = _state.value.selectedProjectID
                        // Audit B6: thread parse runs off-main; hydrateConversation projects off-main
                        // too. Selection may change while the resume is in flight — hydrate only if
                        // this thread/server is still selected and the client is still installed.
                        withContext(projectionDispatcher) {
                            runCatching { client.resumeThread(threadID) }
                                .recoverCatching { client.readThread(threadID) }
                                .getOrNull()
                        }?.let { hydrated ->
                            if (appServer === client) {
                                hydrateConversationIfCurrent(hydrated, requestServerID, requestProjectID, threadID)
                            }
                        }
                    }
                    refreshThreads(refreshGeneration = refreshGeneration)
                    refreshHandedOff = true
                } finally {
                    if (!refreshHandedOff) {
                        endSessionRefresh(refreshGeneration)
                    }
                }
            }
        }
    }

    fun disconnect(updateState: Boolean = true) {
        viewModelScope.launch {
            reconnectJob?.cancel()
            reconnectJob = null
            _state.value.selectedServerID?.let { reconnectAttemptsByServerID.remove(it) }
            disconnectInternal(updateState)
        }
    }

    fun refreshProjects() {
        viewModelScope.launch {
            runBusy("Discovering projects") {
                val server = _state.value.selectedServer ?: return@runBusy
                val client = appServer
                if (client != null) {
                    refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = true)
                } else {
                    refreshProjectsFromSsh(server)
                }
            }
        }
    }

    fun refreshThreads() {
        val refreshGeneration = beginSessionRefresh()
        refreshThreads(refreshGeneration = refreshGeneration, forceReload = true)
    }

    private fun refreshThreadsIfNeeded() {
        val cacheKey = currentThreadScopeCacheKey()
        if (restoreCachedSessionState(cacheKey) && canUseCachedSessionState(cacheKey)) {
            drainSelectedQueueIfReady()
            return
        }
        val refreshGeneration = beginSessionRefresh()
        refreshThreads(refreshGeneration = refreshGeneration, forceReload = false)
    }

    private fun refreshThreads(refreshGeneration: Long, forceReload: Boolean = true) {
        viewModelScope.launch {
            try {
                runBusy("Refreshing sessions") {
                    val state = _state.value
                    val client = appServer ?: return@runBusy
                    val cacheKey = currentThreadScopeCacheKey(state)
                    if (!forceReload && restoreCachedSessionState(cacheKey) && canUseCachedSessionState(cacheKey)) {
                        return@runBusy
                    }
                    val requestServerID = state.selectedServerID
                    val requestProjectID = state.selectedProjectID
                    val requestAllSessions = state.isShowingAllSessions
                    val includeArchived = state.showsArchivedSessions
                    sessionRefreshListLoadGeneration += 1
                    val listLoadGeneration = sessionRefreshListLoadGeneration
                    var selectedThreadIDToHydrate: String? = null
                    val loaded = loadThreadsForScope(client, state, pageLimit = sessionListInitialPageLimit)
                    _state.update { current ->
                        if (appServer !== client ||
                            sessionRefreshListLoadGeneration != listLoadGeneration ||
                            current.selectedServerID != requestServerID ||
                            current.selectedProjectID != requestProjectID ||
                            current.isShowingAllSessions != requestAllSessions ||
                            current.showsArchivedSessions != includeArchived
                        ) {
                            current
                        } else {
                            val sorted = sortedThreadsPreservingSelectedThread(
                                loadedThreads = loaded,
                                state = current,
                                preserveMissingSelectedThread = true,
                            )
                            val selectedID = current.selectedThreadID?.takeIf { id -> sorted.any { it.id == id } }
                            if (selectedID != null && !isThreadDetailCacheFresh(cacheKey.serverID, selectedID)) {
                                selectedThreadIDToHydrate = selectedID
                            }
                            if (current.selectedThreadID != null && selectedID == null) {
                                current.copy(
                                    threads = sorted,
                                    selectedThreadID = null,
                                    selectedThread = null,
                                    conversationSections = emptyList(),
                                    pendingApprovals = emptyList(),
                                    diffSnapshot = GitDiffSnapshot.Empty,
                                    tokenUsagePercent = null,
                                    queuedTurnInputs = emptyList(),
                                )
                            } else {
                                current.copy(threads = sorted)
                            }
                        }
                    }
                    selectedThreadIDToHydrate?.let { threadID ->
                        hydrateSelectedThreadDetailAfterSessionRefresh(
                            client = client,
                            requestServerID = requestServerID,
                            requestProjectID = requestProjectID,
                            requestThreadID = threadID,
                            expectedSelectedThread = _state.value.selectedThread,
                        )
                    }
                    loadCompleteThreadListAfterInitialSessionRefresh(client, state, cacheKey, listLoadGeneration)
                    drainSelectedQueueIfReady()
                }
            } finally {
                endSessionRefresh(refreshGeneration)
            }
        }
    }

    private suspend fun loadThreadsForScope(
        client: CodexAppServerClient,
        state: MobidexUiState,
        pageLimit: Int?,
    ): List<CodexThread> {
        val project = state.selectedProject
        val cwd = if (state.isShowingAllSessions) null else project?.path
        val sessionPaths = if (state.isShowingAllSessions) emptyList() else project?.sessionPaths ?: emptyList()
        val includeArchived = state.showsArchivedSessions
        return if (sessionPaths.isEmpty()) {
            client.listThreads(cwd, includeArchived = includeArchived, pageLimit = pageLimit)
        } else {
            val exactMatches = sessionPaths.flatMap { path -> client.listThreads(path, includeArchived = includeArchived, pageLimit = pageLimit) }
            val unscoped = client.listThreads(null, includeArchived = includeArchived, pageLimit = pageLimit)
            val groupedSessionIDs = SessionListSections.sessionIdsForProject(
                sessions = unscoped.map { thread ->
                    CodexThreadSummary(
                        id = thread.id,
                        cwd = thread.cwd,
                        updatedAtEpochSeconds = thread.updatedAtEpochSeconds,
                    )
                },
                projects = state.selectedServer?.projects?.map { it.toSharedProject() }.orEmpty(),
                projectPath = cwd.orEmpty(),
            )
            (exactMatches + unscoped.filter { it.id in groupedSessionIDs }).distinctBy { it.id }
        }
    }

    private fun loadCompleteThreadListAfterInitialSessionRefresh(
        client: CodexAppServerClient,
        requestState: MobidexUiState,
        cacheKey: ThreadScopeCacheKey,
        listLoadGeneration: Long,
    ) {
        viewModelScope.launch {
            var selectedThreadIDToHydrate: String? = null
            runCatching { loadThreadsForScope(client, requestState, pageLimit = null) }
                .onSuccess { loaded ->
                    _state.update { current ->
                        if (appServer !== client ||
                            sessionRefreshListLoadGeneration != listLoadGeneration ||
                            current.selectedServerID != requestState.selectedServerID ||
                            current.selectedProjectID != requestState.selectedProjectID ||
                            current.isShowingAllSessions != requestState.isShowingAllSessions ||
                            current.showsArchivedSessions != requestState.showsArchivedSessions
                        ) {
                            current
                        } else {
                            val sorted = sortedThreadsPreservingSelectedThread(
                                loadedThreads = loaded,
                                state = current,
                                preserveMissingSelectedThread = false,
                            )
                            cacheThreads(cacheKey, sorted)
                            val selectedID = current.selectedThreadID?.takeIf { id -> sorted.any { it.id == id } }
                            if (selectedID != null && !isThreadDetailCacheFresh(cacheKey.serverID, selectedID)) {
                                selectedThreadIDToHydrate = selectedID
                            }
                            if (current.selectedThreadID != null && selectedID == null) {
                                current.copy(
                                    threads = sorted,
                                    selectedThreadID = null,
                                    selectedThread = null,
                                    conversationSections = emptyList(),
                                    pendingApprovals = emptyList(),
                                    diffSnapshot = GitDiffSnapshot.Empty,
                                    tokenUsagePercent = null,
                                    queuedTurnInputs = emptyList(),
                                )
                            } else {
                                current.copy(threads = sorted)
                            }
                        }
                    }
                    selectedThreadIDToHydrate?.let { threadID ->
                        hydrateSelectedThreadDetailAfterSessionRefresh(
                            client = client,
                            requestServerID = requestState.selectedServerID,
                            requestProjectID = requestState.selectedProjectID,
                            requestThreadID = threadID,
                            expectedSelectedThread = _state.value.selectedThread,
                        )
                    }
                }
                .onFailure { error ->
                    _state.update { current ->
                        if (appServer === client &&
                            sessionRefreshListLoadGeneration == listLoadGeneration &&
                            current.selectedServerID == requestState.selectedServerID &&
                            current.selectedProjectID == requestState.selectedProjectID &&
                            current.isShowingAllSessions == requestState.isShowingAllSessions &&
                            current.showsArchivedSessions == requestState.showsArchivedSessions
                        ) {
                            current.copy(statusMessage = error.message ?: "Session list failed to finish loading.")
                        } else {
                            current
                        }
                    }
                }
        }
    }

    private fun beginSessionRefresh(): Long {
        activeSessionRefreshes += 1
        _state.update { it.copy(isRefreshingSessions = true) }
        return sessionRefreshGeneration
    }

    private fun endSessionRefresh(refreshGeneration: Long) {
        if (refreshGeneration != sessionRefreshGeneration) {
            return
        }
        activeSessionRefreshes = maxOf(0, activeSessionRefreshes - 1)
        if (activeSessionRefreshes == 0) {
            _state.update { it.copy(isRefreshingSessions = false) }
        }
    }

    private fun resetSessionRefreshTracking() {
        sessionRefreshGeneration += 1
        sessionRefreshListLoadGeneration += 1
        sessionRefreshDetailLoadGeneration += 1
        activeSessionRefreshes = 0
        _state.update { it.copy(isRefreshingSessions = false) }
    }

    private fun hydrateSelectedThreadDetailAfterSessionRefresh(
        client: CodexAppServerClient,
        requestServerID: String?,
        requestProjectID: String?,
        requestThreadID: String,
        expectedSelectedThread: CodexThread?,
    ) {
        sessionRefreshDetailLoadGeneration += 1
        val detailLoadGeneration = sessionRefreshDetailLoadGeneration
        viewModelScope.launch {
            runCatching { client.resumeThread(requestThreadID) }
                .recoverCatching { client.readThread(requestThreadID) }
                .onSuccess { hydrated ->
                    if (appServer === client &&
                        sessionRefreshDetailLoadGeneration == detailLoadGeneration &&
                        _state.value.selectedThread == expectedSelectedThread
                    ) {
                        hydrateConversationIfCurrent(hydrated, requestServerID, requestProjectID, requestThreadID)
                    }
                }
                .onFailure { error ->
                    _state.update { state ->
                        if (appServer === client &&
                            sessionRefreshDetailLoadGeneration == detailLoadGeneration &&
                            state.selectedServerID == requestServerID &&
                            state.selectedProjectID == requestProjectID &&
                            state.selectedThreadID == requestThreadID &&
                            state.selectedThread == expectedSelectedThread
                        ) {
                            state.copy(statusMessage = error.message ?: "Session details failed to load.")
                        } else {
                            state
                        }
                    }
                }
        }
    }

    private fun currentThreadScopeCacheKey(state: MobidexUiState = _state.value): ThreadScopeCacheKey {
        val project = state.selectedProject
        return ThreadScopeCacheKey(
            serverID = state.selectedServerID,
            projectID = if (state.isShowingAllSessions) null else state.selectedProjectID,
            cwd = if (state.isShowingAllSessions) null else project?.path,
            sessionPaths = if (state.isShowingAllSessions) emptyList() else project?.sessionPaths.orEmpty().sorted(),
            isShowingAllSessions = state.isShowingAllSessions,
            includeArchivedSessions = state.showsArchivedSessions,
        )
    }

    private fun cacheThreads(cacheKey: ThreadScopeCacheKey, threads: List<CodexThread>) {
        // Remove-then-put keeps LinkedHashMap iteration order == write recency for eviction.
        threadListCache.remove(cacheKey)
        threadListCache[cacheKey] = CachedThreadList(
            threads = threads,
            selectedThreadID = _state.value.selectedThreadID,
            fetchedAtEpochSeconds = Instant.now().epochSecond,
        )
        threadListCache.evictOldestBeyond(MAX_CACHED_THREAD_LISTS, protect = cacheKey)
    }

    private fun sortedThreadsPreservingSelectedThread(
        loadedThreads: List<CodexThread>,
        state: MobidexUiState,
        preserveMissingSelectedThread: Boolean,
    ): List<CodexThread> {
        val selectedID = state.selectedThreadID
        val selectedThread = state.selectedThread
        unlistedStartedThreadIDs.removeAll(loadedThreads.map { it.id }.toSet())
        val shouldPreserveMissingSelectedThread = preserveMissingSelectedThread ||
            (selectedID != null && selectedID in unlistedStartedThreadIDs)
        val threads = if (
            shouldPreserveMissingSelectedThread &&
            selectedID != null &&
            selectedThread?.id == selectedID &&
            loadedThreads.none { it.id == selectedID } &&
            threadMatchesScope(selectedThread, state)
        ) {
            loadedThreads + selectedThread
        } else {
            loadedThreads
        }
        return threads.sortedWith(
            compareByDescending<CodexThread> { it.updatedAtEpochSeconds }
                .thenBy { it.id },
        )
    }

    private fun threadMatchesScope(thread: CodexThread, state: MobidexUiState): Boolean {
        if (state.isShowingAllSessions) return true
        val project = state.selectedProject ?: return false
        val paths = project.sessionPaths.ifEmpty { listOf(project.path) }
        if (thread.cwd in paths) return true
        return thread.id in SessionListSections.sessionIdsForProject(
            sessions = listOf(CodexThreadSummary(thread.id, thread.cwd, thread.updatedAtEpochSeconds)),
            projects = state.selectedServer?.projects?.map { it.toSharedProject() }.orEmpty(),
            projectPath = project.path,
        )
    }

    private fun cacheThreadDetail(serverID: String?, thread: CodexThread) {
        val key = ThreadDetailCacheKey(serverID, thread.id)
        // Each entry retains a full conversation; without a cap a day of browsing sessions
        // accumulates tens-to-hundreds of MB (audit D2). Remove-then-put keeps iteration
        // order == write recency; streaming flushes rewrite the selected session's entry
        // continuously, so it always stays newest.
        threadDetailCache.remove(key)
        threadDetailCache[key] = CachedThreadDetail(
            thread = thread,
            fetchedAtEpochSeconds = Instant.now().epochSecond,
        )
        threadDetailCache.evictOldestBeyond(MAX_CACHED_THREAD_DETAILS, protect = key)
    }

    private fun cacheCurrentSelectedThreadDetail() {
        val state = _state.value
        val thread = state.selectedThread ?: return
        cacheThreadDetail(state.selectedServerID, thread)
    }

    private fun restoreCachedSessionState(cacheKey: ThreadScopeCacheKey): Boolean {
        val cached = threadListCache[cacheKey] ?: return false
        val selectedID = cachedSelectedThreadID(cached)
        val detail = selectedID
            ?.let { id -> threadDetailCache[ThreadDetailCacheKey(cacheKey.serverID, id)] }
            ?.takeIf { detail ->
                CodexSessionCachePolicy.isFresh(
                    fetchedAtEpochSeconds = detail.fetchedAtEpochSeconds,
                    nowEpochSeconds = Instant.now().epochSecond,
                    ttlSeconds = CodexSessionCachePolicy.DEFAULT_THREAD_DETAIL_TTL_SECONDS,
                )
            }
        val selectedThread = detail?.thread ?: selectedID?.let { id -> cached.threads.firstOrNull { it.id == id } }
        val sections = selectedThread?.let { rebuildThreadSections(it) }.orEmpty()
        _state.update { state ->
            state.copy(
                threads = cached.threads,
                selectedThreadID = selectedID,
                selectedThread = selectedThread,
                conversationSections = sections,
                pendingApprovals = emptyList(),
                diffSnapshot = GitDiffSnapshot.Empty,
                tokenUsagePercent = null,
            )
        }
        return true
    }

    private fun canUseCachedSessionState(cacheKey: ThreadScopeCacheKey): Boolean {
        val cached = threadListCache[cacheKey] ?: return false
        if (!isSessionCacheFresh(cacheKey)) return false
        val selectedID = cachedSelectedThreadID(cached) ?: return true
        return isThreadDetailCacheFresh(cacheKey.serverID, selectedID)
    }

    private fun cachedSelectedThreadID(cached: CachedThreadList): String? {
        if (suppressCachedThreadSelection) return null
        cached.selectedThreadID
            ?.takeIf { id -> cached.threads.any { it.id == id } }
            ?.let { return it }
        return cached.threads.firstOrNull()?.id
    }

    private fun isSessionCacheFresh(cacheKey: ThreadScopeCacheKey): Boolean =
        CodexSessionCachePolicy.isFresh(
            fetchedAtEpochSeconds = threadListCache[cacheKey]?.fetchedAtEpochSeconds,
            nowEpochSeconds = Instant.now().epochSecond,
            ttlSeconds = CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
        )

    private fun isThreadDetailCacheFresh(serverID: String?, threadID: String): Boolean =
        CodexSessionCachePolicy.isFresh(
            fetchedAtEpochSeconds = threadDetailCache[ThreadDetailCacheKey(serverID, threadID)]?.fetchedAtEpochSeconds,
            nowEpochSeconds = Instant.now().epochSecond,
            ttlSeconds = CodexSessionCachePolicy.DEFAULT_THREAD_DETAIL_TTL_SECONDS,
        )

    private fun invalidateSessionCaches(serverID: String?) {
        threadListCache.keys.removeAll { it.serverID == serverID }
        threadDetailCache.keys.removeAll { it.serverID == serverID }
    }

    fun openThread(thread: CodexThread) {
        if (isSessionMutationInFlight()) {
            _state.update { it.copy(statusMessage = "Wait for the current session action to finish before opening another session.") }
            return
        }
        acpClient?.let { client ->
            openAcpSession(client, thread)
            return
        }
        viewModelScope.launch {
            suppressThreadAutoSelection = false
            suppressCachedThreadSelection = false
            sessionRefreshDetailLoadGeneration += 1
            val requestState = _state.value
            val requestServerID = requestState.selectedServerID
            val requestProjectID = requestState.selectedProjectID
            val shouldPromoteProject = requestState.isShowingAllSessions
            // Select synchronously (before any suspension) so a slower projection from an
            // earlier tap can never revert a newer selection; sections follow once projected.
            _state.update {
                it.copy(
                    selectedThreadID = thread.id,
                    selectedThread = thread,
                    conversationSections = emptyList(),
                    diffSnapshot = GitDiffSnapshot.Empty,
                    tokenUsagePercent = null,
                )
            }
            // Audit B6: the tapped thread's initial projection runs off-main.
            val projected = withContext(projectionDispatcher) { projectThreadSections(thread) }
            if (_state.value.selectedThreadID != thread.id) return@launch // superseded by a newer tap
            adoptThreadSections(projected)
            _state.update { it.copy(conversationSections = projected.sections) }
            runBusy("Opening session") {
                val client = appServer ?: return@runBusy
                val hydrated = withContext(projectionDispatcher) { client.resumeThread(thread.id) }
                hydrateConversationIfCurrent(hydrated, requestServerID, requestProjectID, thread.id)
                if (shouldPromoteProject) {
                    promoteProjectToProjectList(hydrated)
                }
                refreshProjectsForCurrentScope(client, requestServerID)
            }
        }
    }

    fun startNewSession(location: NewSessionLocation = NewSessionLocation.CodexWorktree, onComplete: (Boolean) -> Unit = {}) {
        if (isSessionMutationInFlight()) {
            _state.update { it.copy(statusMessage = "A session action is already in progress.") }
            onComplete(false)
            return
        }
        val initialState = _state.value
        if (initialState.selectedServer == null) {
            _state.update { it.copy(statusMessage = "Select a server before starting a session.") }
            onComplete(false)
            return
        }
        if (initialState.selectedProject == null) {
            _state.update { it.copy(statusMessage = "Select a project before starting a session.") }
            onComplete(false)
            return
        }
        isStartingSession = true
        sessionMutationGeneration += 1
        suppressThreadAutoSelection = true
        resetSessionRefreshTracking()
        _state.update {
            it.copy(
                isStartingNewSession = true,
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                pendingApprovals = emptyList(),
                diffSnapshot = GitDiffSnapshot.Empty,
                tokenUsagePercent = null,
            )
        }
        viewModelScope.launch {
            var createdThread = false
            try {
                runBusy("Starting session") {
                    val state = _state.value
                    val requestServerID = state.selectedServerID
                    val requestProjectID = state.selectedProjectID
                    val requestThreadID = state.selectedThreadID
                    val server = state.selectedServer ?: error("Select a server before starting a session.")
                    val cwd = state.selectedProject?.path ?: error("Select a project before starting a session.")
                    var client = appServer
                    if (client == null) {
                        _state.update { it.copy(connectionState = ServerConnectionState.Connecting, statusMessage = "Connecting before starting session") }
                        val connectedClient = try {
                            val credential = credentialStore.loadCredential(server.id)
                            requireSessionSelection(requestServerID, requestProjectID, requestThreadID)
                            sshService.openAppServer(server, credential)
                        } catch (error: Throwable) {
                            if (error is CancellationException) throw error
                            _state.update {
                                it.copy(
                                    connectionState = ServerConnectionState.Failed,
                                    failureMessage = error.message,
                                    statusMessage = error.message ?: "Connection failed before starting session.",
                                )
                            }
                            throw error
                        }
                        if (_state.value.selectedServerID != server.id) {
                            connectedClient.close()
                            _state.update { it.copy(connectionState = ServerConnectionState.Disconnected) }
                            error("The selected server changed before the session could start.")
                        }
                        appServer = connectedClient
                        startEventLoop(connectedClient)
                        _state.update { it.copy(connectionState = ServerConnectionState.Connected, failureMessage = null, statusMessage = "Server connected.") }
                        client = connectedClient
                    }
                    requireSessionMutationScope(client, requestServerID, requestProjectID, requestThreadID)
                    val sessionCwd = when (location) {
                        NewSessionLocation.CodexWorktree -> {
                            _state.update { it.copy(statusMessage = "Creating worktree") }
                            val credential = credentialStore.loadCredential(server.id)
                            requireSessionMutationScope(client, requestServerID, requestProjectID, requestThreadID)
                            withNewSessionOperationTimeout("Creating the worktree timed out after 30 seconds.") {
                                sshService.createCodexWorktree(cwd, server, credential)
                            }
                        }
                        NewSessionLocation.ProjectDirectory -> cwd
                    }
                    requireSessionMutationScope(client, requestServerID, requestProjectID, requestThreadID)
                    _state.update { it.copy(statusMessage = "Creating session") }
                    val thread = if (location == NewSessionLocation.CodexWorktree) {
                        withNewSessionOperationTimeout("Creating the session timed out after 30 seconds.") {
                            client.startThread(sessionCwd)
                        }
                    } else {
                        client.startThread(sessionCwd)
                    }
                    if (location == NewSessionLocation.CodexWorktree) {
                        rememberSessionPath(sessionCwd, requestServerID, requestProjectID)
                    }
                    unlistedStartedThreadIDs += thread.id
                    val adopted = hydrateConversationIfCurrent(
                        thread,
                        requestServerID,
                        requestProjectID,
                        requestThreadID,
                        clearPerThreadState = true,
                        acceptedStartedThreadID = thread.id,
                    )
                    if (!adopted) return@runBusy
                    createdThread = true
                    suppressThreadAutoSelection = false
                    suppressCachedThreadSelection = false
                    _state.update { current ->
                        if (appServer !== client || current.selectedServerID != requestServerID || current.selectedProjectID != requestProjectID || current.selectedThreadID != thread.id) {
                            current
                        } else {
                            current.copy(threads = (listOf(thread) + current.threads).distinctBy { item -> item.id })
                        }
                    }
                    invalidateSessionCaches(requestServerID)
                    cacheThreads(currentThreadScopeCacheKey(), _state.value.threads)
                    refreshProjectsForCurrentScope(client, requestServerID)
                }
            } finally {
                isStartingSession = false
                _state.update { it.copy(isStartingNewSession = false) }
                if (_state.value.selectedThreadID == null) {
                    suppressThreadAutoSelection = false
                }
                onComplete(createdThread)
            }
        }
    }

    private suspend fun rememberSessionPath(sessionPath: String, serverID: String?, projectID: String?) {
        if (sessionPath.isBlank() || serverID == null || projectID == null) return
        val state = _state.value
        val server = state.servers.firstOrNull { it.id == serverID } ?: return
        val project = server.projects.firstOrNull { it.id == projectID } ?: return
        val normalizedSessionPaths = ProjectRecord.normalizedSessionPaths(project.sessionPaths + sessionPath, project.path)
        if (normalizedSessionPaths == project.sessionPaths) return
        val updatedProject = project.copy(sessionPaths = normalizedSessionPaths)
        val updatedServer = server.copy(
            projects = server.projects.map { if (it.id == projectID) updatedProject else it },
            updatedAtEpochSeconds = Instant.now().epochSecond,
        )
        val updated = state.servers.upsert(updatedServer)
        repository.saveServers(updated)
        invalidateSessionCaches(serverID)
        _state.update { current ->
            if (current.selectedServerID == serverID) current.copy(servers = updated) else current
        }
    }

    fun sendComposerText(text: String) {
        sendComposerInput(text, emptyList(), onComplete = {})
    }

    fun sendComposerInput(text: String, attachmentUris: List<Uri>, queueWhenActive: Boolean = false, onComplete: (Boolean) -> Unit = {}) {
        viewModelScope.launch {
            val trimmed = text.trim()
            if (trimmed.isEmpty() && attachmentUris.isEmpty()) {
                onComplete(false)
                return@launch
            }
            if (isSendingInput) {
                onComplete(false)
                return@launch
            }
            isSendingInput = true
            sessionMutationGeneration += 1
            var didSubmitInput = false
            try {
                runBusy(if (attachmentUris.isEmpty()) "Sending" else "Uploading attachments") {
                    val serverForSend = _state.value.selectedServer
                    if (serverForSend?.backendType == BackendType.Acp) {
                        // ACP production send: delegate to client (simple prompt for now; attachments future).
                        // Appends a local UserMessage item so the echo appears in the mapped sections.
                        val sid = acpSessionId ?: run {
                            _state.update { it.copy(statusMessage = "No active ACP session.") }
                            return@runBusy
                        }
                        val textToSend = trimmed
                        if (textToSend.isNotBlank()) {
                            // Optimistic local echo using the same item type the mapper produces.
                            val userEcho = CodexSessionItem.UserMessage(id = "local-${System.currentTimeMillis()}", text = textToSend)
                            val previous = _acpSessionItems.value
                            val next = previous + userEcho
                            _acpSessionItems.value = next
                            acpSections.applyItemsChange(previous, next)
                            val sections = acpSections.sections.toList()
                            publishStreamedSections {
                                _state.update { s ->
                                    if (s.selectedServerID == serverForSend.id) s.copy(conversationSections = sections) else s
                                }
                            }
                            runCatching { acpClient?.sendPrompt(sid, textToSend) }
                                .onFailure { e -> _state.update { it.copy(statusMessage = e.message ?: "ACP send failed") } }
                        }
                        didSubmitInput = true
                        return@runBusy
                    }
                    // Codex path (untouched body below).
                    val client = appServer ?: error("Connect to the server before sending a message.")
                    val requestState = _state.value
                    val requestServerID = requestState.selectedServerID
                    val requestProjectID = requestState.selectedProjectID
                    val requestThreadID = requestState.selectedThreadID
                    var thread = requestState.selectedThread
                    var createdThread = false
                    if (thread == null) {
                        suppressThreadAutoSelection = true
                        requireSessionMutationScope(client, requestServerID, requestProjectID, requestThreadID)
                        thread = client.startThread(requestState.selectedProject?.path)
                        unlistedStartedThreadIDs += thread.id
                        createdThread = true
                        if (!hydrateConversationIfCurrent(thread, requestServerID, requestProjectID, requestThreadID, acceptedStartedThreadID = thread.id)) {
                            return@runBusy
                        }
                        suppressThreadAutoSelection = false
                    }
                    if (!requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                        return@runBusy
                    }
                    val input = buildList {
                        if (trimmed.isNotEmpty()) add(CodexInputItem.Text(trimmed))
                        addAll(stageAttachmentInputs(attachmentUris, requestState.selectedServer ?: error("Select a server before uploading attachments.")))
                    }
                    if (input.isEmpty()) return@runBusy
                    if (thread.status.isActive) {
                        val activeTurnID = _state.value.activeTurnID
                        if (queueWhenActive) {
                            queuedTurnInputsByThreadID.getOrPut(thread.id) { mutableListOf() }.add(QueuedTurnInput(input = input))
                            refreshQueuedTurnInputs()
                            _state.update {
                                if (requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                                    it.copy(statusMessage = "Queued message for after the current turn.")
                                } else {
                                    it
                                }
                            }
                            didSubmitInput = true
                        } else if (activeTurnID != null) {
                            val localEchoID = appendLocalUserEcho(thread.id, activeTurnID, input)
                            try {
                                client.steer(thread.id, activeTurnID, input)
                            } catch (error: Exception) {
                                localEchoID?.let { removeLocalUserEcho(thread.id, it) }
                                throw error
                            }
                            _state.update {
                                if (requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                                    it.copy(statusMessage = "Steered active turn.")
                                } else {
                                    it
                                }
                            }
                            didSubmitInput = true
                        } else {
                            queuedTurnInputsByThreadID.getOrPut(thread.id) { mutableListOf() }.add(QueuedTurnInput(input = input))
                            refreshQueuedTurnInputs()
                            _state.update {
                                if (requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                                    it.copy(statusMessage = "Queued message until the active turn is available.")
                                } else {
                                    it
                                }
                            }
                            didSubmitInput = true
                        }
                    } else {
                        val turn = client.startTurn(
                            threadID = thread.id,
                            input = input,
                            options = turnOptions(_state.value.selectedReasoningEffort, _state.value.selectedAccessMode, thread.cwd),
                        ).forDisplay(input)
                        if (!requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                            return@runBusy
                        }
                        hydrateConversation(thread.copy(status = thread.status.copy(type = if (turn.status == "inProgress") "active" else "idle"), turns = thread.turns.upsert(turn)))
                        didSubmitInput = true
                    }
                    refreshThreads()
                    if (createdThread) refreshProjectsForCurrentScope(client, requestServerID)
                }
            } finally {
                isSendingInput = false
                if (_state.value.selectedThreadID == null) {
                    suppressThreadAutoSelection = false
                }
            }
            onComplete(didSubmitInput)
        }
    }

    fun archiveThread(thread: CodexThread) {
        viewModelScope.launch {
            runBusy("Archiving session") {
                val client = appServer ?: error("Connect to the server before archiving a session.")
                client.archiveThread(thread.id)
                queuedTurnInputsByThreadID.remove(thread.id)
                refreshQueuedTurnInputs()
                _state.update { state ->
                    val nextThreads = state.threads.filterNot { it.id == thread.id }
                    if (state.selectedThreadID == thread.id) {
                        val fallback = nextThreads.firstOrNull()
                        state.copy(
                            threads = nextThreads,
                            selectedThreadID = fallback?.id,
                            selectedThread = fallback,
                            conversationSections = fallback?.conversationSections().orEmpty(),
                        )
                    } else {
                        state.copy(threads = nextThreads)
                    }
                }
                threadListCache.clear()
                threadDetailCache.remove(ThreadDetailCacheKey(_state.value.selectedServerID, thread.id))
                refreshThreads()
            }
        }
    }

    fun unarchiveThread(thread: CodexThread) {
        viewModelScope.launch {
            runBusy("Unarchiving session") {
                val client = appServer ?: error("Connect to the server before unarchiving a session.")
                val restored = client.unarchiveThread(thread.id)
                _state.update { state ->
                    val nextThreads = state.threads.filterNot { it.id == restored.id }.toMutableList()
                    nextThreads.add(0, restored)
                    state.copy(threads = nextThreads)
                }
                threadListCache.clear()
                refreshThreads()
            }
        }
    }

    fun deleteQueuedTurnInput(id: String) {
        val threadID = _state.value.selectedThreadID ?: return
        queuedTurnInputsByThreadID[threadID]?.removeAll { it.id == id }
        if (queuedTurnInputsByThreadID[threadID]?.isEmpty() == true) queuedTurnInputsByThreadID.remove(threadID)
        refreshQueuedTurnInputs()
    }

    fun moveQueuedTurnInput(id: String, direction: Int) {
        if (direction == 0) return
        val threadID = _state.value.selectedThreadID ?: return
        val queue = queuedTurnInputsByThreadID[threadID] ?: return
        val index = queue.indexOfFirst { it.id == id }
        if (index < 0) return
        val nextIndex = (index + direction).coerceIn(0, queue.lastIndex)
        if (nextIndex == index) return
        val item = queue.removeAt(index)
        queue.add(nextIndex, item)
        refreshQueuedTurnInputs()
    }

    fun steerQueuedTurnInputNow(id: String) {
        viewModelScope.launch {
            val initialState = _state.value
            val threadID = initialState.selectedThreadID ?: return@launch
            val requestServerID = initialState.selectedServerID
            val requestProjectID = initialState.selectedProjectID
            val queue = queuedTurnInputsByThreadID[threadID] ?: return@launch
            val index = queue.indexOfFirst { it.id == id }
            if (index < 0) return@launch
            val item = queue[index]
            var removedFromQueue = false
            var localEchoID: String? = null
            try {
                val client = appServer ?: error("Connect to the server before steering.")
                val thread = client.readThread(threadID)
                if (!requestMatchesCurrentScope(client, requestServerID, requestProjectID, threadID)) {
                    error("The selected session scope changed before the action could finish.")
                }
                hydrateConversation(thread)
                val activeTurnID = activeTurnID(thread) ?: error("There is no active turn to steer.")
                val currentQueue = queuedTurnInputsByThreadID[threadID] ?: return@launch
                val currentIndex = currentQueue.indexOfFirst { it.id == id }
                if (currentIndex < 0) return@launch
                currentQueue.removeAt(currentIndex)
                if (currentQueue.isEmpty()) queuedTurnInputsByThreadID.remove(threadID)
                removedFromQueue = true
                refreshQueuedTurnInputs()
                localEchoID = appendLocalUserEcho(threadID, activeTurnID, item.input)
                client.steer(threadID, activeTurnID, item.input)
                _state.update { it.copy(statusMessage = "Steered active turn.") }
                refreshThreads()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                localEchoID?.let { removeLocalUserEcho(threadID, it) }
                if (removedFromQueue) {
                    queuedTurnInputsByThreadID.getOrPut(threadID) { mutableListOf() }.add(index.coerceAtMost(queuedTurnInputsByThreadID[threadID]?.size ?: 0), item)
                }
                refreshQueuedTurnInputs()
                _state.update { it.copy(statusMessage = error.message) }
            }
        }
    }

    private fun refreshQueuedTurnInputs() {
        val threadID = _state.value.selectedThreadID
        _state.update { it.copy(queuedTurnInputs = threadID?.let { id -> queuedTurnInputsByThreadID[id].orEmpty() }.orEmpty()) }
    }

    private fun appendLocalUserEcho(threadID: String, turnID: String, input: List<CodexInputItem>): String? {
        val text = input.displayText() ?: return null
        val thread = _state.value.selectedThread?.takeIf { it.id == threadID } ?: return null
        if (thread.turns.any { turn -> turn.items.any { it is CodexThreadItem.UserMessage && it.text == text } }) {
            return null
        }
        val item = CodexThreadItem.UserMessage(id = "local-user-$turnID-${System.currentTimeMillis()}", text = text)
        val nextTurns = if (thread.turns.any { it.id == turnID }) {
            thread.turns.map { turn -> if (turn.id == turnID) turn.copy(items = turn.items + item) else turn }
        } else {
            thread.turns + CodexTurn(id = turnID, items = listOf(item), status = "inProgress")
        }
        val nextThread = thread.copy(turns = nextTurns)
        // Structural change (item inserted): full resync keeps the accumulator drift-free.
        val sections = rebuildThreadSections(nextThread)
        _state.update { state ->
            if (state.selectedThread?.id == threadID) state.copy(selectedThread = nextThread, conversationSections = sections) else state
        }
        cacheCurrentSelectedThreadDetail()
        return item.id
    }

    private fun removeLocalUserEcho(threadID: String, itemID: String) {
        val thread = _state.value.selectedThread?.takeIf { it.id == threadID } ?: return
        val nextThread = thread.copy(
            turns = thread.turns.map { turn -> turn.copy(items = turn.items.filterNot { it.id == itemID }) }
        )
        // Structural change (item removed): full resync keeps the accumulator drift-free.
        val sections = rebuildThreadSections(nextThread)
        _state.update { state ->
            if (state.selectedThread?.id == threadID) state.copy(selectedThread = nextThread, conversationSections = sections) else state
        }
        cacheCurrentSelectedThreadDetail()
    }

    private suspend fun stageAttachmentInputs(uris: List<Uri>, server: ServerRecord): List<CodexInputItem> {
        if (uris.isEmpty()) return emptyList()
        val attachments = withContext(Dispatchers.IO) {
            uris.map { uri -> CachedAttachment(copyAttachmentToCache(uri), appContext.contentResolver.getType(uri)) }
        }
        val remotePaths = sshService.stageLocalFiles(attachments.map { it.localPath }, server, credentialStore.loadCredential(server.id))
        return attachments.zip(remotePaths).map { (attachment, remotePath) ->
            if (attachment.isImage) {
                CodexInputItem.LocalImage(remotePath)
            } else {
                CodexInputItem.Mention(File(attachment.localPath).name, remotePath)
            }
        }
    }

    private fun copyAttachmentToCache(uri: Uri): String {
        val name = attachmentDisplayName(uri).sanitizedAttachmentName()
        val directory = File(appContext.cacheDir, "mobidex-attachments/${UUID.randomUUID()}").also { it.mkdirs() }
        val destination = File(directory, name)
        appContext.contentResolver.openInputStream(uri)?.use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        } ?: error("Could not read the selected attachment.")
        return destination.absolutePath
    }

    private fun attachmentDisplayName(uri: Uri): String {
        appContext.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                cursor.getString(index)?.takeIf { it.isNotBlank() }?.let { return it }
            }
        }
        return uri.lastPathSegment?.takeIf { it.isNotBlank() } ?: "attachment"
    }

    fun interruptActiveTurn() {
        viewModelScope.launch {
            acpClient?.let { client ->
                val sid = acpSessionId ?: return@launch
                runBusy("Interrupting") {
                    client.cancel(sid)
                    // Spec: answer in-flight permission requests with the cancelled outcome.
                    _state.value.pendingApprovals.forEach { approval ->
                        runCatching {
                            client.respondToServerRequest(
                                approval.requestId.toSharedJsonValue(),
                                AcpProtocolCore.permissionCancelledResult(),
                            )
                        }
                    }
                    _state.update { it.copy(pendingApprovals = emptyList()) }
                }
                return@launch
            }
            val state = _state.value
            val thread = state.selectedThread ?: return@launch
            val turnID = state.activeTurnID ?: return@launch
            runBusy("Interrupting") {
                appServer?.interrupt(thread.id, turnID)
            }
        }
    }

    /** Reopens a past ACP session: history replays through the normal item collector. */
    private fun openAcpSession(client: AcpClient, thread: CodexThread) {
        viewModelScope.launch {
            // The session's own cwd wins: listed sessions can span working directories, and
            // session/load must target where that conversation actually ran.
            val cwd = thread.cwd.ifBlank { null } ?: _state.value.selectedProject?.path
            if (cwd == null) {
                _state.update { it.copy(statusMessage = "Select a project before reopening an ACP session.") }
                return@launch
            }
            runBusy("Loading session") {
                // Replay arrives through client.sessionItems; clear the live surface first.
                _acpSessionItems.value = emptyList()
                acpSections.reset(emptyList())
                _state.update {
                    it.copy(
                        selectedThreadID = thread.id,
                        conversationSections = emptyList(),
                        pendingApprovals = emptyList(),
                    )
                }
                val session = client.loadSession(sessionId = thread.id, cwd = cwd)
                if (acpClient === client) {
                    acpSessionId = session.sessionId
                    _state.update { state ->
                        state.copy(
                            acpModels = session.models ?: state.acpModels,
                            statusMessage = "Reopened ACP session ${session.sessionId}.",
                        )
                    }
                }
            }
        }
    }

    /** Switches the live ACP session to one of the models advertised at session/new. */
    fun setAcpModel(modelId: String) {
        viewModelScope.launch {
            val client = acpClient ?: return@launch
            val sid = acpSessionId ?: return@launch
            val models = _state.value.acpModels ?: return@launch
            if (models.currentModelId == modelId) return@launch
            runBusy("Switching model") {
                client.setModel(sid, modelId)
                if (acpClient === client) {
                    _state.update {
                        it.copy(
                            acpModels = it.acpModels?.copy(currentModelId = modelId),
                            statusMessage = "Model switched.",
                        )
                    }
                }
            }
        }
    }

    fun respond(approval: PendingApproval, accept: Boolean) {
        viewModelScope.launch {
            runBusy(if (accept) "Approving" else "Declining") {
                acpClient?.let { client ->
                    // ACP permission round-trip: answer session/request_permission with the spec
                    // outcome shape, picking the agent-advertised option that matches accept/decline.
                    val params = approval.params?.toSharedJsonValue()
                    val optionId = AcpProtocolCore.choosePermissionOptionId(params, accept)
                    val result = optionId?.let { AcpProtocolCore.permissionSelectedResult(it) }
                        ?: AcpProtocolCore.permissionCancelledResult()
                    client.respondToServerRequest(approval.requestId.toSharedJsonValue(), result)
                    _state.update { it.copy(pendingApprovals = it.pendingApprovals.filterNot { pending -> pending.id == approval.id }) }
                    return@runBusy
                }
                // Codex path (untouched).
                appServer?.respondToServerRequest(approval.requestId, approvalResponse(approval, accept))
                _state.update { it.copy(pendingApprovals = it.pendingApprovals.filterNot { pending -> pending.id == approval.id }) }
            }
        }
    }

    fun refreshDiffSnapshot() {
        viewModelScope.launch {
            val state = _state.value
            val client = appServer
            val requestServerID = state.selectedServerID
            val requestProjectID = state.selectedProjectID
            val requestThreadID = state.selectedThreadID
            val cwd = state.selectedThread?.cwd ?: state.selectedProject?.path ?: return@launch
            val requestID = ++diffSnapshotRequestID
            _state.update { it.copy(isRefreshingChanges = true) }
            runCatching { client?.diffSnapshot(cwd) ?: GitDiffSnapshot.Empty }
                .onSuccess { snapshot ->
                    _state.update {
                        if (appServer === client && it.selectedServerID == requestServerID && it.selectedProjectID == requestProjectID && it.selectedThreadID == requestThreadID) {
                            it.copy(diffSnapshot = snapshot, isRefreshingChanges = false)
                        } else if (diffSnapshotRequestID == requestID) {
                            it.copy(isRefreshingChanges = false)
                        } else {
                            it
                        }
                    }
                }
                .onFailure { error ->
                    _state.update {
                        if (appServer === client && it.selectedServerID == requestServerID && it.selectedProjectID == requestProjectID && it.selectedThreadID == requestThreadID) {
                            it.copy(statusMessage = error.message, isRefreshingChanges = false)
                        } else if (diffSnapshotRequestID == requestID) {
                            it.copy(isRefreshingChanges = false)
                        } else {
                            it
                        }
                    }
                }
        }
    }

    private suspend fun loadServers() {
        runCatching {
            val loadedServers = repository.loadServers()
            val servers = loadedServers.clearingAppServerProjectState()
            if (servers != loadedServers) repository.saveServers(servers)
            _state.update {
                it.copy(
                    servers = servers,
                    selectedServerID = servers.firstOrNull()?.id,
                    selectedProjectID = servers.firstOrNull()?.projects?.firstSavedProjectID,
                    isShowingAllSessions = false,
                )
            }
        }.onFailure { error -> _state.update { it.copy(statusMessage = error.message) } }
    }

    // Called from viewModelScope (Main) everywhere except onCleared, which runs it on
    // teardownScope (IO) — safe only because androidx cancels viewModelScope before
    // onCleared, so no Main-thread caller can race it. Keep it that way.
    private suspend fun disconnectInternal(updateState: Boolean = true) {
        eventJob?.cancel()
        eventJob = null
        acpConnectGeneration += 1 // invalidate any in-flight ACP connect attempt
        acpJob?.cancel()
        acpJob = null
        acpClient?.let { runCatching { it.close() } }
        acpClient = null
        acpSessionId = null
        _acpSessionItems.value = emptyList()
        acpSections.reset(emptyList())
        pendingSectionsPublish = null
        appServer?.close()
        appServer = null
        refreshQueuedTurnInputs()
        resetSessionRefreshTracking()
        if (updateState) {
            val servers = _state.value.servers.clearingAppServerProjectState()
            repository.saveServers(servers)
            _state.update {
                it.copy(
                    servers = servers,
                    connectionState = ServerConnectionState.Disconnected,
                    pendingApprovals = emptyList(),
                    conversationSections = emptyList(),
                    acpModels = null,
                    statusMessage = "Server disconnected.",
                )
            }
        }
    }

    private suspend fun refreshProjectsFromAppServer(
        server: ServerRecord,
        client: CodexAppServerClient,
        includeRemoteDiscovery: Boolean,
    ) {
        _state.update { it.copy(isDiscoveringProjects = true) }
        try {
            val openSessions = listOpenSessionSummaries(client)
            val discoveredProjects = if (includeRemoteDiscovery) {
                sshService.discoverProjects(server, credentialStore.loadCredential(server.id))
            } else {
                null
            }
            val current = _state.value
            if (!projectSyncStillCurrent(server.id, client)) return
            val currentServer = current.servers.firstOrNull { it.id == server.id } ?: return
            val refreshed = refreshedProjects(currentServer.projects, discoveredProjects, openSessions)
            val updatedServer = currentServer.copy(projects = refreshed, updatedAtEpochSeconds = Instant.now().epochSecond)
            val updatedServers = current.servers.upsert(updatedServer)
            repository.saveServers(updatedServers)
            if (!projectSyncStillCurrent(server.id, client)) {
                repository.saveServers(_state.value.servers)
                return
            }
            _state.update {
                if (projectSyncStillCurrent(server.id, client)) {
                    val selectedProjectID = if (it.isShowingAllSessions) {
                        null
                    } else {
                        repairedSelectedProjectID(it.selectedProjectID, refreshed)
                    }
                    val projectSelectionChanged = selectedProjectID != it.selectedProjectID
                    it.copy(
                        servers = updatedServers,
                        selectedProjectID = selectedProjectID,
                        threads = if (projectSelectionChanged) emptyList() else it.threads,
                        selectedThreadID = if (projectSelectionChanged) null else it.selectedThreadID,
                        selectedThread = if (projectSelectionChanged) null else it.selectedThread,
                        conversationSections = if (projectSelectionChanged) emptyList() else it.conversationSections,
                        diffSnapshot = if (projectSelectionChanged) GitDiffSnapshot.Empty else it.diffSnapshot,
                        tokenUsagePercent = if (projectSelectionChanged) null else it.tokenUsagePercent,
                        statusMessage = "Projects synced.",
                    )
                } else {
                    it
                }
            }
        } finally {
            _state.update { it.copy(isDiscoveringProjects = false) }
        }
    }

    private suspend fun refreshProjectsFromSsh(server: ServerRecord) {
        _state.update { it.copy(isDiscoveringProjects = true) }
        try {
            val discoveredProjects = sshService.discoverProjects(server, credentialStore.loadCredential(server.id))
            val current = _state.value
            if (current.selectedServerID != server.id) return
            val currentServer = current.servers.firstOrNull { it.id == server.id } ?: return
            val refreshed = refreshedProjects(currentServer.projects, discoveredProjects, emptyList())
            val updatedServer = currentServer.copy(projects = refreshed, updatedAtEpochSeconds = Instant.now().epochSecond)
            val updatedServers = current.servers.upsert(updatedServer)
            repository.saveServers(updatedServers)
            _state.update {
                if (it.selectedServerID != server.id) {
                    it
                } else {
                    val selectedProjectID = if (it.isShowingAllSessions) {
                        null
                    } else {
                        repairedSelectedProjectID(it.selectedProjectID, refreshed)
                    }
                    val projectSelectionChanged = selectedProjectID != it.selectedProjectID
                    it.copy(
                        servers = updatedServers,
                        selectedProjectID = selectedProjectID,
                        threads = if (projectSelectionChanged) emptyList() else it.threads,
                        selectedThreadID = if (projectSelectionChanged) null else it.selectedThreadID,
                        selectedThread = if (projectSelectionChanged) null else it.selectedThread,
                        conversationSections = if (projectSelectionChanged) emptyList() else it.conversationSections,
                        diffSnapshot = if (projectSelectionChanged) GitDiffSnapshot.Empty else it.diffSnapshot,
                        tokenUsagePercent = if (projectSelectionChanged) null else it.tokenUsagePercent,
                        statusMessage = "Projects discovered.",
                    )
                }
            }
        } finally {
            _state.update { it.copy(isDiscoveringProjects = false) }
        }
    }

    private suspend fun refreshProjectsForCurrentScope(client: CodexAppServerClient, serverID: String?) {
        val server = _state.value.servers.firstOrNull { it.id == serverID } ?: return
        if (projectSyncStillCurrent(server.id, client)) {
            refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = false)
        }
    }

    private fun projectSyncStillCurrent(serverID: String, client: CodexAppServerClient): Boolean {
        val state = _state.value
        return appServer === client &&
            state.selectedServerID == serverID &&
            state.connectionState == ServerConnectionState.Connected
    }

    private suspend fun listOpenSessionSummaries(client: CodexAppServerClient): List<CodexThread> {
        val seen = mutableSetOf<String>()
        return client.listLoadedThreadIDs(limit = 1_000)
            .filter { seen.add(it) }
            .mapNotNull { threadID ->
                runCatching { client.readThreadSummary(threadID) }
                    .getOrElse { error ->
                        if (canIgnoreForLoadedThreadSummary(error)) null else throw error
                    }
            }
            .filter { it.isUserFacingSession }
            .sortedWith(
                compareByDescending<CodexThread> { it.status.isActive }
                    .thenByDescending { it.updatedAtEpochSeconds }
                    .thenBy { it.id }
            )
    }

    private fun canIgnoreForLoadedThreadSummary(error: Throwable): Boolean {
        val message = error.message?.lowercase().orEmpty()
        return "not found" in message ||
            "not loaded" in message ||
            "unknown thread" in message ||
            "no such thread" in message
    }

    private fun refreshedProjects(
        existing: List<ProjectRecord>,
        discoveredProjects: List<RemoteProject>?,
        openSessions: List<CodexThread>,
    ): List<ProjectRecord> {
        val existingByPath = existing.associateBy { it.path }
        return ProjectCatalog.refreshedProjects(
            existingProjects = existing.map { it.toSharedProject() },
            discoveredProjects = discoveredProjects ?: existing.discoveredRemoteProjects(),
            openSessions = openSessions.map {
                mobidex.shared.CodexThreadSummary(it.id, it.cwd, it.updatedAtEpochSeconds)
            },
        ).map { shared ->
            val previous = existingByPath[shared.path]
            ProjectRecord(
                id = previous?.id ?: java.util.UUID.randomUUID().toString(),
                path = shared.path,
                sessionPaths = shared.sessionPaths,
                displayName = shared.displayName,
                discovered = shared.discovered,
                discoveredSessionCount = shared.discoveredSessionCount,
                archivedSessionCount = shared.archivedSessionCount,
                activeChatCount = shared.activeChatCount,
                lastDiscoveredAtEpochSeconds = shared.lastDiscoveredAtEpochSeconds,
                lastActiveChatAtEpochSeconds = shared.lastActiveChatAtEpochSeconds,
                isAdded = previous?.let { it.isAdded || !it.discovered || shared.isAdded } ?: shared.isAdded,
            )
        }
    }

    private fun List<ProjectRecord>.discoveredRemoteProjects(): List<RemoteProject> =
        filter { it.discovered }.map { project ->
            RemoteProject(
                path = project.path,
                sessionPaths = project.sessionPaths,
                discoveredSessionCount = project.discoveredSessionCount,
                archivedSessionCount = project.archivedSessionCount,
                lastDiscoveredAtEpochSeconds = project.lastDiscoveredAtEpochSeconds,
            )
        }

    private fun repairedSelectedProjectID(selectedProjectID: String?, projects: List<ProjectRecord>): String? = when {
        selectedProjectID != null && projects.any { it.id == selectedProjectID } -> selectedProjectID
        else -> projects.firstSavedProjectID
    }

    private fun ProjectRecord.toSharedProject(): mobidex.shared.ProjectRecord =
        mobidex.shared.ProjectRecord(
            path = path,
            sessionPaths = sessionPaths,
            displayName = displayName,
            discovered = discovered,
            discoveredSessionCount = discoveredSessionCount,
            archivedSessionCount = archivedSessionCount,
            activeChatCount = activeChatCount,
            lastDiscoveredAtEpochSeconds = lastDiscoveredAtEpochSeconds,
            lastActiveChatAtEpochSeconds = lastActiveChatAtEpochSeconds,
            isAdded = isAdded,
        )

    fun projectSections(searchText: String, showInactive: Boolean, showArchived: Boolean): AndroidProjectListSections {
        val projects = _state.value.selectedServer?.projects.orEmpty()
        val projectsByPath = projects.associateBy { it.path }
        val sections = ProjectListSections.from(
            projects = projects.map { it.toSharedProject() },
            searchText = searchText,
            showInactiveDiscoveredProjects = showInactive,
            showArchivedSessionProjects = showArchived,
        )
        return AndroidProjectListSections(
            projects = sections.projects.mapNotNull { projectsByPath[it.path] },
            discovered = sections.discovered.mapNotNull { projectsByPath[it.path] },
            added = sections.added.mapNotNull { projectsByPath[it.path] },
            showInactiveDiscoveredFilter = sections.showInactiveDiscoveredFilter,
            showArchivedSessionFilter = sections.showArchivedSessionFilter,
            discoveredTitle = sections.discoveredTitle,
        )
    }

    fun sessionSections(searchText: String): List<AndroidSessionListSection> {
        val state = _state.value
        val query = searchText.trim()
        val matchingThreads = state.threads.filter { thread ->
            query.isEmpty() ||
                thread.title.contains(query, ignoreCase = true) ||
                thread.cwd.contains(query, ignoreCase = true)
        }
        val threadsByID = matchingThreads.associateBy { it.id }
        return SessionListSections.from(
            sessions = matchingThreads.map {
                CodexThreadSummary(
                    id = it.id,
                    cwd = it.cwd,
                    updatedAtEpochSeconds = it.updatedAtEpochSeconds,
                )
            },
            projects = state.selectedServer?.projects?.map { it.toSharedProject() }.orEmpty(),
        ).map { section ->
            AndroidSessionListSection(
                id = section.id,
                title = section.title,
                threads = section.sessionIds.mapNotNull { threadsByID[it] },
            )
        }.filter { it.threads.isNotEmpty() }
    }

    private fun startEventLoop(client: CodexAppServerClient) {
        eventJob?.cancel()
        eventJob = viewModelScope.launch {
            client.events.collect { event ->
                when (event) {
                    is CodexAppServerEvent.Disconnected -> {
                        handleAppServerDisconnected(client, event.message)
                    }
                    is CodexAppServerEvent.ServerRequest -> {
                        if (!eventTargetsSelectedThread(event.params)) return@collect
                        _state.update {
                            it.copy(
                                pendingApprovals = it.pendingApprovals + PendingApproval(
                                    id = event.id.toString(),
                                    requestId = event.id,
                                    method = event.method,
                                    params = event.params,
                                    title = approvalTitle(event.method),
                                    detail = approvalDetail(event.params),
                                )
                            )
                        }
                    }
                    is CodexAppServerEvent.Notification -> handleNotification(event.method, event.params)
                }
            }
        }
    }

    private suspend fun handleAppServerDisconnected(client: CodexAppServerClient, message: String) {
        val serverID = _state.value.selectedServerID
        eventJob = null
        if (appServer === client) {
            appServer = null
        }
        refreshQueuedTurnInputs()
        resetSessionRefreshTracking()
        client.close()
        if (serverID != null && shouldReconnect(serverID)) {
            _state.update {
                it.copy(
                    connectionState = ServerConnectionState.Connecting,
                    statusMessage = "$message Reconnecting server.",
                    pendingApprovals = emptyList(),
                )
            }
            scheduleReconnect(serverID, message)
            return
        }
        val servers = _state.value.servers.clearingAppServerProjectState()
        repository.saveServers(servers)
        _state.update {
            it.copy(
                servers = servers,
                connectionState = ServerConnectionState.Disconnected,
                statusMessage = message,
                pendingApprovals = emptyList(),
            )
        }
    }

    private fun shouldReconnect(serverID: String): Boolean =
        _state.value.selectedServerID == serverID &&
            _state.value.selectedServer != null &&
            (reconnectAttemptsByServerID[serverID] ?: 0) < MAX_APP_SERVER_RECONNECT_ATTEMPTS

    private fun scheduleReconnect(serverID: String, disconnectMessage: String) {
        reconnectJob?.cancel()
        reconnectJob = viewModelScope.launch {
            var lastFailureMessage = disconnectMessage
            while (shouldReconnect(serverID) && appServer == null) {
                val attempt = (reconnectAttemptsByServerID[serverID] ?: 0) + 1
                reconnectAttemptsByServerID[serverID] = attempt
                delay(appServerReconnectDelayMillis(attempt))
                if (_state.value.selectedServerID != serverID || appServer != null) {
                    reconnectJob = null
                    return@launch
                }
                _state.update {
                    it.copy(
                        connectionState = ServerConnectionState.Connecting,
                        statusMessage = "$disconnectMessage Reconnecting server ($attempt/$MAX_APP_SERVER_RECONNECT_ATTEMPTS).",
                    )
                }
                if (reconnectSelectedServerOnce(serverID)) {
                    reconnectJob = null
                    return@launch
                }
                lastFailureMessage = _state.value.failureMessage ?: _state.value.statusMessage ?: "Reconnect failed."
            }
            if (_state.value.selectedServerID == serverID && appServer == null) {
                val servers = _state.value.servers.clearingAppServerProjectState()
                repository.saveServers(servers)
                _state.update {
                    it.copy(
                        servers = servers,
                        connectionState = ServerConnectionState.Failed,
                        failureMessage = lastFailureMessage,
                        statusMessage = lastFailureMessage,
                        pendingApprovals = emptyList(),
                    )
                }
            }
            reconnectJob = null
        }
    }

    private suspend fun reconnectSelectedServerOnce(serverID: String): Boolean {
        val server = _state.value.servers.firstOrNull { it.id == serverID } ?: return false
        return try {
            val credential = credentialStore.loadCredential(server.id)
            val client = sshService.openAppServer(server, credential)
            if (_state.value.selectedServerID != server.id) {
                client.close()
                return false
            }
            appServer = client
            startEventLoop(client)
            _state.update {
                it.copy(
                    connectionState = ServerConnectionState.Connected,
                    failureMessage = null,
                    statusMessage = "Server reconnected.",
                )
            }
            reconnectAttemptsByServerID.remove(server.id)
            runCatching { refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = true) }
                .onFailure { error -> _state.update { it.copy(statusMessage = error.message ?: "Project refresh failed after reconnect.") } }
            val requestProjectID = _state.value.selectedProjectID
            _state.value.selectedThreadID?.let { threadID ->
                runCatching { client.resumeThread(threadID) }
                    .recoverCatching { client.readThread(threadID) }
                    .getOrNull()
                    ?.let { hydrateConversationIfCurrent(it, serverID, requestProjectID, threadID) }
            }
            val refreshGeneration = beginSessionRefresh()
            var refreshHandedOff = false
            try {
                refreshThreads(refreshGeneration = refreshGeneration, forceReload = true)
                refreshHandedOff = true
            } finally {
                if (!refreshHandedOff) {
                    endSessionRefresh(refreshGeneration)
                }
            }
            true
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            _state.update {
                it.copy(
                    failureMessage = error.message ?: "Reconnect failed.",
                    statusMessage = error.message ?: "Reconnect failed.",
                )
            }
            false
        }
    }

    private fun appServerReconnectDelayMillis(attempt: Int): Long {
        val multiplier = 1L shl (attempt - 1).coerceIn(0, 5)
        return minOf(8_000L, 500L * multiplier)
    }

    private suspend fun handleNotification(method: String, params: JsonElement?) {
        val notificationSessionMutationGeneration = sessionMutationGeneration
        val sessionMutationWasInFlight = isSessionMutationInFlight()
        when (method) {
            "error" -> {
                if (!eventTargetsSelectedThread(params)) return
                val error = parseTurnError(params.obj("error")) ?: return
                val willRetry = params.bool("willRetry") == true
                showTurnError(error.toThreadItem("turn-error-${params.string("turnId") ?: "live-${error.message.hashCode()}"}", willRetry), error.message, willRetry)
            }
            "thread/started" -> params.obj("thread")?.let {
                val thread = parseThread(it)
                if (threadMatchesCurrentScope(thread) && (_state.value.selectedThreadID == null || _state.value.selectedThreadID == thread.id)) {
                    hydrateConversation(thread)
                }
                refreshThreadsFromNotification(notificationSessionMutationGeneration, sessionMutationWasInFlight)
                appServer?.let { client -> refreshProjectsForCurrentScope(client, _state.value.selectedServerID) }
            }
            "turn/started", "turn/completed" -> {
                val targetsSelectedThread = eventTargetsSelectedThread(params)
                val turn = params.obj("turn")?.let { parseTurn(it) }
                if (targetsSelectedThread && turn != null) {
                    val thread = _state.value.selectedThread
                    if (thread != null) {
                        val next = thread.copy(
                            status = if (method == "turn/started") thread.status.copy(type = "active") else thread.status.copy(type = "idle"),
                            turns = thread.turns.upsert(turn),
                        )
                        _state.update { state ->
                            if (state.selectedThread !== thread) return@update state
                            state.copy(
                                selectedThread = next,
                                statusMessage = if (method == "turn/completed" && turn.status == "failed" && turn.error != null) {
                                    turnErrorStatusMessage(turn.error.message)
                                } else {
                                    state.statusMessage
                                },
                            )
                        }
                        // Audit B6: full projection off-main. Adopt only if nothing replaced
                        // the thread while projecting — a racing mutation rebuilds from `next`
                        // itself, so skipping the stale snapshot is the drift-free outcome.
                        val projected = withContext(projectionDispatcher) { projectThreadSections(next) }
                        if (_state.value.selectedThread === next) {
                            adoptThreadSections(projected)
                            _state.update { state ->
                                if (state.selectedThread === next) state.copy(conversationSections = projected.sections) else state
                            }
                            cacheCurrentSelectedThreadDetail()
                        }
                    }
                } else if (method == "turn/started") {
                    return
                }
                if (method == "turn/completed") {
                    refreshThreadsFromNotification(notificationSessionMutationGeneration, sessionMutationWasInFlight)
                    if (targetsSelectedThread) {
                        val client = appServer
                        val requestServerID = _state.value.selectedServerID
                        val requestProjectID = _state.value.selectedProjectID
                        val threadID = _state.value.selectedThreadID
                        if (client != null && threadID != null) {
                            // Audit B6: readThread response parsing happens off-main too. The
                            // suspension means the user may have switched thread/server before
                            // the read returns — hydrate only if the selection is still current.
                            val hydrated = withContext(projectionDispatcher) { client.readThread(threadID) }
                            if (appServer === client) {
                                hydrateConversationIfCurrent(hydrated, requestServerID, requestProjectID, threadID)
                            }
                        }
                    }
                    params.string("threadId")?.let { startNextQueuedTurnIfReady(it) }
                }
            }
            "item/started", "item/completed" -> {
                if (!eventTargetsSelectedThread(params)) return
                params.obj("item")?.let { upsertItem(parseItem(it)) }
            }
            "item/agentMessage/delta" -> if (eventTargetsSelectedThread(params)) appendTextDelta(params.string("itemId"), params.string("delta"), agent = true)
            "item/plan/delta" -> if (eventTargetsSelectedThread(params)) appendTextDelta(params.string("itemId"), params.string("delta"), agent = false)
            "item/commandExecution/outputDelta" -> if (eventTargetsSelectedThread(params)) appendCommandDelta(params.string("itemId"), params.string("delta"))
            "item/commandExecution/terminalInteraction" -> if (eventTargetsSelectedThread(params)) appendCommandDelta(params.string("itemId"), terminalInteractionText(params.string("stdin")))
            "item/reasoning/summaryTextDelta" -> if (eventTargetsSelectedThread(params)) appendReasoningDelta(params.string("itemId"), params.string("delta"), params.long("summaryIndex")?.toInt(), summary = true)
            "item/reasoning/summaryPartAdded" -> if (eventTargetsSelectedThread(params)) ensureReasoningPart(params.string("itemId"), params.long("summaryIndex")?.toInt(), summary = true)
            "item/reasoning/textDelta" -> if (eventTargetsSelectedThread(params)) appendReasoningDelta(params.string("itemId"), params.string("delta"), params.long("contentIndex")?.toInt(), summary = false)
            "turn/plan/updated" -> if (eventTargetsSelectedThread(params)) applyTurnPlanUpdate(params.string("turnId"), params)
            "turn/diff/updated" -> if (eventTargetsSelectedThread(params)) applyTurnDiffUpdate(params.string("turnId"), params.string("diff"))
            "item/fileChange/patchUpdated" -> if (eventTargetsSelectedThread(params)) applyFileChangePatch(params.string("itemId"), params.array("changes")?.map { mobidex.android.service.parseFileChange(it) }.orEmpty())
            "item/fileChange/outputDelta" -> if (eventTargetsSelectedThread(params)) appendFileChangeOutputDelta(params.string("itemId"), params.string("delta"))
            "item/mcpToolCall/progress" -> if (eventTargetsSelectedThread(params)) appendToolProgress(params.string("itemId"), params.string("message"))
            "thread/status/changed" -> params.obj("status")?.let { status ->
                if (!eventTargetsSelectedThread(params)) return
                _state.update { state ->
                    val thread = state.selectedThread ?: return@update state
                    val next = thread.copy(status = parseStatus(status))
                    state.copy(selectedThread = next)
                }
                cacheCurrentSelectedThreadDetail()
                refreshThreadsFromNotification(notificationSessionMutationGeneration, sessionMutationWasInFlight)
            }
            "thread/tokenUsage/updated" -> {
                if (!eventTargetsSelectedThread(params)) return
                val usage = parseTokenUsage(params.obj("tokenUsage"))
                _state.update { it.copy(tokenUsagePercent = usage?.contextPercent) }
            }
            "serverRequest/resolved" -> {
                if (!eventTargetsSelectedThread(params)) return
                val requestID = params?.jsonObject?.get("requestId")?.toString()
                _state.update { it.copy(pendingApprovals = it.pendingApprovals.filterNot { approval -> approval.id == requestID }) }
            }
            else -> if (method.startsWith("thread/")) refreshThreadsFromNotification(notificationSessionMutationGeneration, sessionMutationWasInFlight)
        }
    }

    private fun refreshThreadsFromNotification(notificationSessionMutationGeneration: Long, sessionMutationWasInFlight: Boolean) {
        if (!sessionMutationWasInFlight &&
            notificationSessionMutationGeneration == sessionMutationGeneration &&
            !isSessionMutationInFlight()
        ) {
            refreshThreads()
        }
    }

    private suspend fun hydrateConversation(thread: CodexThread) {
        sessionRefreshDetailLoadGeneration += 1
        val serverID = _state.value.selectedServerID
        val existingSelected = _state.value.selectedThread
        // Audit B6: echo merge + full projection run off-main; only state writes stay on Main.
        val projected = withContext(projectionDispatcher) {
            projectThreadSections(thread.preserveExistingUserMessages(existingSelected))
        }
        val displayThread = projected.thread
        cacheThreadDetail(serverID, displayThread)
        adoptThreadSections(projected)
        _state.update {
            it.copy(
                selectedThreadID = displayThread.id,
                selectedThread = displayThread,
                conversationSections = projected.sections,
                queuedTurnInputs = queuedTurnInputsByThreadID[displayThread.id].orEmpty(),
            )
        }
        cacheThreads(currentThreadScopeCacheKey(), _state.value.threads)
    }

    private suspend fun promoteProjectToProjectList(thread: CodexThread) {
        val state = _state.value
        val server = state.selectedServer ?: return
        val existing = server.projects.firstOrNull { it.path == thread.cwd || thread.cwd in it.sessionPaths }
        val updatedProject = existing?.copy(isAdded = true) ?: ProjectRecord(path = thread.cwd, isAdded = true)
        if (existing?.isAdded == true) return
        val updatedServer = server.copy(
            projects = if (existing == null) {
                server.projects + updatedProject
            } else {
                server.projects.map { if (it.id == existing.id) updatedProject else it }
            },
            updatedAtEpochSeconds = Instant.now().epochSecond,
        )
        val updated = state.servers.upsert(updatedServer)
        repository.saveServers(updated)
        _state.update {
            if (it.selectedServerID == server.id) it.copy(servers = updated) else it
        }
    }

    private suspend fun hydrateConversationIfCurrent(
        thread: CodexThread,
        requestServerID: String?,
        requestProjectID: String?,
        requestThreadID: String?,
        clearPerThreadState: Boolean = false,
        acceptedStartedThreadID: String? = null,
    ): Boolean {
        fun selectionMatches(state: MobidexUiState): Boolean {
            val threadMatches = state.selectedThreadID == requestThreadID ||
                (requestThreadID == null && acceptedStartedThreadID != null && state.selectedThreadID == acceptedStartedThreadID)
            return state.selectedServerID == requestServerID && state.selectedProjectID == requestProjectID && threadMatches
        }

        val initial = _state.value
        if (!selectionMatches(initial)) return false
        // Audit B6: echo merge + full projection run off-main; selection is re-validated
        // inside the state update after resuming on Main.
        val projected = withContext(projectionDispatcher) {
            projectThreadSections(thread.preserveExistingUserMessages(initial.selectedThread))
        }
        var didHydrate = false
        _state.update { state ->
            if (!selectionMatches(state)) {
                state
            } else {
                didHydrate = true
                var next = state.copy(
                    selectedThreadID = projected.thread.id,
                    selectedThread = projected.thread,
                    conversationSections = projected.sections,
                )
                if (clearPerThreadState) {
                    next = next.copy(
                        pendingApprovals = emptyList(),
                        diffSnapshot = GitDiffSnapshot.Empty,
                        isRefreshingChanges = false,
                        tokenUsagePercent = null,
                    )
                }
                next
            }
        }
        if (didHydrate) {
            sessionRefreshDetailLoadGeneration += 1
            adoptThreadSections(projected)
            cacheThreadDetail(requestServerID, _state.value.selectedThread ?: thread)
            drainSelectedQueueIfReady()
        }
        return didHydrate
    }

    private fun drainSelectedQueueIfReady() {
        val thread = _state.value.selectedThread ?: return
        if (thread.status.isActive) return
        if (queuedTurnInputsByThreadID[thread.id].isNullOrEmpty()) return
        viewModelScope.launch { startNextQueuedTurnIfReady(thread.id) }
    }

    private suspend fun startNextQueuedTurnIfReady(threadID: String) {
        var inFlightQueuedInput: QueuedTurnInput? = null
        try {
            while (queuedTurnInputsByThreadID[threadID]?.isNotEmpty() == true) {
                val queue = queuedTurnInputsByThreadID[threadID] ?: return
                val queuedInput = queue.removeFirstOrNull() ?: return
                inFlightQueuedInput = queuedInput
                if (queue.isEmpty()) {
                    queuedTurnInputsByThreadID.remove(threadID)
                }
                refreshQueuedTurnInputs()
                val client = appServer
                if (client == null) {
                    queuedTurnInputsByThreadID.getOrPut(threadID) { mutableListOf() }.add(0, queuedInput)
                    refreshQueuedTurnInputs()
                    return
                }
                val state = _state.value
                val thread = state.selectedThread?.takeIf { it.id == threadID } ?: client.readThread(threadID)
                if (thread.status.isActive) {
                    queuedTurnInputsByThreadID.getOrPut(threadID) { mutableListOf() }.add(0, queuedInput)
                    inFlightQueuedInput = null
                    refreshQueuedTurnInputs()
                    return
                }
                val turn = client.startTurn(
                    threadID = thread.id,
                    input = queuedInput.input,
                    options = turnOptions(state.selectedReasoningEffort, state.selectedAccessMode, thread.cwd),
                ).forDisplay(queuedInput.input)
                inFlightQueuedInput = null
                if (state.selectedThreadID == threadID) {
                    hydrateConversation(thread.copy(status = thread.status.copy(type = if (turn.status == "inProgress") "active" else "idle"), turns = thread.turns.upsert(turn)))
                }
                refreshThreads()
                if (turn.status == "inProgress") return
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            inFlightQueuedInput?.let {
                queuedTurnInputsByThreadID.getOrPut(threadID) { mutableListOf() }.add(0, it)
                refreshQueuedTurnInputs()
            }
            _state.update { it.copy(statusMessage = error.message) }
        }
    }

    private fun requestMatchesCurrentScope(
        client: CodexAppServerClient,
        requestServerID: String?,
        requestProjectID: String?,
        requestThreadID: String?,
    ): Boolean {
        val state = _state.value
        return appServer === client &&
            state.selectedServerID == requestServerID &&
            state.selectedProjectID == requestProjectID &&
            state.selectedThreadID == requestThreadID
    }

    private fun requireSessionMutationScope(
        client: CodexAppServerClient,
        requestServerID: String?,
        requestProjectID: String?,
        requestThreadID: String?,
    ) {
        check(requestMatchesCurrentScope(client, requestServerID, requestProjectID, requestThreadID)) {
            "The selected session scope changed before the action could finish."
        }
    }

    private fun requireSessionSelection(
        requestServerID: String?,
        requestProjectID: String?,
        requestThreadID: String?,
    ) {
        val state = _state.value
        check(
            state.selectedServerID == requestServerID &&
                state.selectedProjectID == requestProjectID &&
                state.selectedThreadID == requestThreadID
        ) {
            "The selected session scope changed before the action could finish."
        }
    }

    private fun isSessionMutationInFlight(): Boolean =
        isStartingSession || isSendingInput || _state.value.isStartingNewSession

    private fun eventTargetsSelectedThread(params: JsonElement?): Boolean {
        val selectedThreadID = _state.value.selectedThreadID ?: return false
        val threadID = params.string("threadId") ?: params.string("conversationId") ?: return false
        return selectedThreadID == threadID
    }

    private fun threadMatchesCurrentScope(thread: CodexThread): Boolean {
        val state = _state.value
        if (state.selectedThreadID == thread.id) return true
        if (state.selectedThreadID != null) return false
        val project = state.selectedProject
        val paths = project?.sessionPaths.orEmpty()
        if (paths.isEmpty() || thread.cwd in paths) return true
        val projectPath = project?.path ?: return false
        return thread.id in SessionListSections.sessionIdsForProject(
            sessions = listOf(CodexThreadSummary(thread.id, thread.cwd, thread.updatedAtEpochSeconds)),
            projects = state.selectedServer?.projects?.map { it.toSharedProject() }.orEmpty(),
            projectPath = projectPath,
        )
    }

    /**
     * Publishes streamed conversationSections at most ~once per 50ms with a trailing flush
     * (audit B1): the first publish in a window applies immediately so single updates stay
     * snappy; bursts coalesce into the trailing flush. [apply] must re-validate selection
     * itself because the flush can run after the user switched threads or servers.
     */
    private fun publishStreamedSections(apply: () -> Unit) {
        if (sectionsFlushJob != null) {
            pendingSectionsPublish = apply
            return
        }
        apply()
        cacheCurrentSelectedThreadDetail()
        sectionsFlushJob = viewModelScope.launch {
            delay(STREAMED_SECTIONS_FLUSH_WINDOW_MILLIS)
            sectionsFlushJob = null
            pendingSectionsPublish?.let { pending ->
                pendingSectionsPublish = null
                publishStreamedSections(pending)
            }
        }
    }

    /** Adopts a fully projected thread; any pending streamed flush predates it and is dropped. */
    private fun adoptThreadSections(projected: ProjectedThread) {
        pendingSectionsPublish = null
        codexSectionsThreadId = projected.thread.id
        codexSections.reset(projected.items, projected.sections)
    }

    /** Full projection + accumulator resync for [thread]; every fallback funnels through here. */
    private fun rebuildThreadSections(thread: CodexThread): List<ConversationSection> {
        val projected = projectThreadSections(thread)
        adoptThreadSections(projected)
        return projected.sections
    }

    /**
     * O(changed item) projection for a streamed update to [itemId] inside [thread]. Anything
     * the accumulator can't map unambiguously falls back to the full rebuild — different
     * thread, structural change, duplicate item ids (legacy mapItems semantics update every
     * duplicate), changed row identity, or Unknown items (their section body embeds the real
     * turn id, which liveSection cannot reproduce). Correctness over speed, always.
     */
    private fun streamedThreadSections(thread: CodexThread, itemId: String): List<ConversationSection> {
        if (codexSectionsThreadId == thread.id) {
            val items = thread.flattenedSharedItems()
            val index = items.indexOfLast { it.id == itemId }
            if (index >= 0 && items[index] !is CodexSessionItem.Unknown && items.indexOfFirst { it.id == itemId } == index) {
                if (items.size == codexSections.sections.size) {
                    val allocatedId = codexSections.sections[index].id
                    if ((allocatedId == itemId || allocatedId.startsWith("$itemId#")) && codexSections.updateAt(index, items[index])) {
                        return codexSections.sections.toList()
                    }
                } else if (items.size == codexSections.sections.size + 1 && index == items.lastIndex) {
                    codexSections.append(items[index])
                    return codexSections.sections.toList()
                }
            }
        }
        return rebuildThreadSections(thread)
    }

    /**
     * Applies a streamed single-item thread mutation: selectedThread updates immediately
     * (it is the substrate the next delta builds on) while sections flow through the
     * incremental accumulator + conflated publish.
     */
    private fun applyStreamedItemUpdate(nextThread: CodexThread, itemId: String) {
        val sections = streamedThreadSections(nextThread, itemId)
        _state.update { state ->
            if (state.selectedThread?.id == nextThread.id) state.copy(selectedThread = nextThread) else state
        }
        publishStreamedSections {
            _state.update { state ->
                if (state.selectedThreadID == nextThread.id) state.copy(conversationSections = sections) else state
            }
        }
    }

    private fun upsertItem(item: CodexThreadItem) {
        val thread = _state.value.selectedThread ?: return
        val turn = thread.turns.lastOrNull() ?: return
        val nextTurn = turn.copy(items = turn.items.upsert(item))
        val nextThread = thread.copy(turns = thread.turns.upsert(nextTurn))
        applyStreamedItemUpdate(nextThread, item.id)
    }

    private fun showTurnError(item: CodexThreadItem.AgentEvent, message: String, willRetry: Boolean) {
        val nextStatus = turnErrorStatusMessage(message, willRetry)
        _state.update { it.copy(statusMessage = nextStatus) }
        val thread = _state.value.selectedThread ?: return
        if (thread.turns.isEmpty()) return
        val turn = thread.turns.last()
        val nextTurn = turn.copy(items = turn.items.upsert(item))
        val nextThread = thread.copy(turns = thread.turns.upsert(nextTurn))
        applyStreamedItemUpdate(nextThread, item.id)
    }

    private fun turnErrorStatusMessage(message: String, willRetry: Boolean = false): String =
        "${if (willRetry) "Temporary Codex error" else "Codex turn failed"}: $message"

    private fun appendTextDelta(itemID: String?, delta: String?, agent: Boolean) {
        if (itemID == null || delta == null) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            when {
                agent && item is CodexThreadItem.AgentMessage && item.id == itemID -> item.copy(text = item.text + delta)
                !agent && item is CodexThreadItem.Plan && item.id == itemID -> item.copy(text = item.text + delta)
                else -> item
            }
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun appendCommandDelta(itemID: String?, delta: String?) {
        if (itemID == null || delta == null) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            if (item is CodexThreadItem.Command && item.id == itemID) {
                item.copy(output = (item.output ?: "") + delta)
            } else {
                item
            }
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun appendReasoningDelta(itemID: String?, delta: String?, index: Int?, summary: Boolean) {
        if (itemID == null || delta == null) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            if (item is CodexThreadItem.Reasoning && item.id == itemID) {
                if (summary) item.copy(summary = appendIndexed(item.summary, index, delta)) else item.copy(content = appendIndexed(item.content, index, delta))
            } else {
                item
            }
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun ensureReasoningPart(itemID: String?, index: Int?, summary: Boolean) {
        if (itemID == null || index == null) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            if (item is CodexThreadItem.Reasoning && item.id == itemID) {
                if (summary) item.copy(summary = ensureIndexed(item.summary, index)) else item.copy(content = ensureIndexed(item.content, index))
            } else {
                item
            }
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun applyTurnPlanUpdate(turnID: String?, params: JsonElement?) {
        val text = buildString {
            params.string("explanation")?.takeIf { it.isNotBlank() }?.let { append(it) }
            params?.jsonObject?.get("plan")?.let { plan ->
                if (isNotEmpty()) append("\n\n")
                append(plan.toString())
            }
        }.ifBlank { return }
        val item = CodexThreadItem.Plan(id = "turn-plan-${turnID ?: "live"}", text = text)
        upsertItem(item)
    }

    private fun applyTurnDiffUpdate(turnID: String?, diff: String?) {
        if (diff.isNullOrBlank()) return
        upsertItem(
            CodexThreadItem.FileChange(
                id = "turn-diff-${turnID ?: "live"}",
                changes = listOf(mobidex.android.model.CodexFileChange("Working tree", diff)),
                status = "updated",
            )
        )
    }

    private fun applyFileChangePatch(itemID: String?, changes: List<mobidex.android.model.CodexFileChange>) {
        if (itemID == null) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            if (item is CodexThreadItem.FileChange && item.id == itemID) item.copy(changes = changes) else item
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun appendFileChangeOutputDelta(itemID: String?, delta: String?) {
        if (itemID == null || delta == null) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            if (item is CodexThreadItem.FileChange && item.id == itemID) {
                val change = item.changes.firstOrNull() ?: mobidex.android.model.CodexFileChange("Patch output", "")
                item.copy(changes = listOf(change.copy(diff = change.diff + delta)) + item.changes.drop(1))
            } else {
                item
            }
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun appendToolProgress(itemID: String?, message: String?) {
        if (itemID == null || message.isNullOrBlank()) return
        val thread = _state.value.selectedThread ?: return
        val nextThread = thread.mapItems { item ->
            if (item is CodexThreadItem.ToolCall && item.id == itemID) {
                item.copy(detail = listOfNotNull(item.detail, message).joinToString("\n"))
            } else {
                item
            }
        }
        applyStreamedItemUpdate(nextThread, itemID)
    }

    private fun terminalInteractionText(stdin: String?): String? =
        stdin?.takeIf { it.isNotEmpty() }?.let { "\n${'$'} $it\n" }

    private fun appendIndexed(values: List<String>, index: Int?, delta: String): List<String> {
        val target = index ?: values.lastIndex.coerceAtLeast(0)
        val mutable = ensureIndexed(values, target).toMutableList()
        mutable[target] = mutable[target] + delta
        return mutable
    }

    private fun ensureIndexed(values: List<String>, index: Int): List<String> {
        if (index < 0 || index < values.size) return values
        return values + List(index - values.size + 1) { "" }
    }

    private suspend fun runBusy(status: String, marksFailure: Boolean = false, block: suspend () -> Unit) {
        busyCount += 1
        _state.update { it.copy(isBusy = true, statusMessage = status, failureMessage = null) }
        try {
            block()
        } catch (cancellation: CancellationException) {
            // Structured cancellation is not a failure; let it propagate.
            throw cancellation
        } catch (error: Throwable) {
            _state.update {
                it.copy(
                    connectionState = if (marksFailure) ServerConnectionState.Failed else it.connectionState,
                    failureMessage = error.message,
                    statusMessage = error.message,
                )
            }
        } finally {
            busyCount -= 1
            if (busyCount == 0) {
                _state.update { it.copy(isBusy = false) }
            }
        }
    }

    private fun approvalTitle(method: String): String =
        when {
            method.contains("exec", ignoreCase = true) -> "Command approval"
            method.contains("patch", ignoreCase = true) || method.contains("file", ignoreCase = true) -> "File change approval"
            else -> "Approval request"
        }

    private fun approvalResponse(approval: PendingApproval, accept: Boolean): JsonValue =
        when (approval.method) {
            "item/commandExecution/requestApproval", "item/fileChange/requestApproval" ->
                jsonObject(mapOf("decision" to jsonString(if (accept) "accept" else "decline")))
            "execCommandApproval", "applyPatchApproval" ->
                jsonObject(mapOf("decision" to jsonString(if (accept) "approved" else "denied")))
            "item/permissions/requestApproval" ->
                jsonObject(
                    mapOf(
                        "permissions" to if (accept) {
                            approval.params?.jsonObject?.get("permissions")?.toSharedJsonValue() ?: jsonObject(emptyMap())
                        } else {
                            jsonObject(emptyMap())
                        },
                        "scope" to jsonString("turn"),
                    )
                )
            "mcpServer/elicitation/request" ->
                jsonObject(mapOf("action" to jsonString("decline"), "content" to jsonNull(), "_meta" to jsonNull()))
            "item/tool/requestUserInput" ->
                jsonObject(mapOf("answers" to jsonObject(emptyMap())))
            "item/tool/call" ->
                jsonObject(mapOf("contentItems" to jsonArray(emptyList()), "success" to mobidex.shared.jsonBool(false)))
            else -> jsonObject(mapOf("decision" to jsonString(if (accept) "approved" else "decline")))
        }

    private fun approvalDetail(params: JsonElement?): String =
        params?.jsonObject?.entries
            ?.joinToString("\n") { (key, value) ->
                val text = (value as? JsonPrimitive)?.contentOrNull ?: value.toString()
                "$key: $text"
            }
            ?: ""

    override fun onCleared() {
        // sshj teardown does network I/O with second-scale joins; blocking main here is an
        // ANR window. The teardown scope outlives the ViewModel just long enough to close.
        teardownScope.launch { disconnectInternal(updateState = false) }
    }

    class Factory(private val context: Context) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            val appContext = context.applicationContext
            val hostKeyStore = SharedPreferencesHostKeyStore(appContext)
            return AppViewModel(
                context = appContext,
                repository = SharedPreferencesServerRepository(appContext),
                credentialStore = AndroidCredentialStore(appContext),
                hostKeyStore = hostKeyStore,
                sshService = SshjMobidexSshService(hostKeyStore),
            ) as T
        }
    }
}

private fun MobidexUiState.clearingSessionScope(): MobidexUiState =
    copy(
        threads = emptyList(),
        selectedThreadID = null,
        selectedThread = null,
        conversationSections = emptyList(),
        pendingApprovals = emptyList(),
        acpModels = null,
        diffSnapshot = GitDiffSnapshot.Empty,
        isRefreshingSessions = false,
        tokenUsagePercent = null,
    )

internal fun List<ServerRecord>.clearingAppServerProjectState(): List<ServerRecord> =
    map { server ->
        val launchConfig = RemoteServerLaunchDefaults.normalize(server.codexPath, server.executionPath)
        server.copy(
            codexPath = launchConfig.codexPath,
            executionPath = launchConfig.executionPath,
            projects = server.projects.map { project ->
                project.copy(
                    activeChatCount = 0,
                    lastActiveChatAtEpochSeconds = null,
                )
            }
        )
    }

private fun List<ServerRecord>.upsert(server: ServerRecord): List<ServerRecord> =
    if (any { it.id == server.id }) map { if (it.id == server.id) server else it } else this + server

private val List<ProjectRecord>.firstSavedProjectID: String?
    get() = firstOrNull { it.isSavedProject }?.id ?: firstOrNull()?.id

private fun List<CodexTurn>.upsert(turn: CodexTurn): List<CodexTurn> =
    if (any { it.id == turn.id }) {
        map { existing -> if (existing.id == turn.id) turn.preserveLocalUserEcho(existing) else existing }
    } else {
        this + turn
    }

private fun CodexTurn.preserveLocalUserEcho(existing: CodexTurn): CodexTurn {
    return mergeLocalUserEchoes(existing)
}

private fun CodexTurn.forDisplay(input: List<CodexInputItem>): CodexTurn {
    if (items.any { it is CodexThreadItem.UserMessage }) return this
    val text = input.displayText() ?: return this
    return copy(items = listOf(CodexThreadItem.UserMessage(id = "local-user-$id", text = text)) + items)
}

private fun List<CodexInputItem>.displayText(): String? =
    mapNotNull { item ->
        when (item) {
            is CodexInputItem.Text -> item.text
            is CodexInputItem.ImageUrl -> "[image: ${item.url}]"
            is CodexInputItem.LocalImage -> "[localImage: ${File(item.path).name}]"
            is CodexInputItem.Skill -> "[skill: ${item.name}]"
            is CodexInputItem.Mention -> "[mention: ${item.name}]"
        }.trim().ifEmpty { null }
    }.joinToString("\n").ifEmpty { null }

private fun CodexThread.preserveExistingUserMessages(existing: CodexThread?): CodexThread {
    existing ?: return this
    return copy(
        turns = turns.map { turn ->
            val existingTurn = existing.turns.firstOrNull { it.id == turn.id }
            if (existingTurn == null) turn else turn.mergeLocalUserEchoes(existingTurn)
        }
    )
}

private fun CodexTurn.mergeLocalUserEchoes(existing: CodexTurn): CodexTurn {
    val incomingUserIDs = items.filterIsInstance<CodexThreadItem.UserMessage>().map { it.id }.toSet()
    val incomingUserTexts = items.filterIsInstance<CodexThreadItem.UserMessage>().map { it.text }.toSet()
    val localEchoes = existing.items.filterIsInstance<CodexThreadItem.UserMessage>().filter {
        it.id.startsWith("local-user-") && it.id !in incomingUserIDs && it.text !in incomingUserTexts
    }
    if (localEchoes.isEmpty()) return this
    val insertAt = items.takeWhile { it is CodexThreadItem.UserMessage }.count()
    return copy(items = items.toMutableList().apply { addAll(insertAt, localEchoes) })
}

private fun List<CodexThreadItem>.upsert(item: CodexThreadItem): List<CodexThreadItem> =
    if (item is CodexThreadItem.UserMessage) {
        val localEchoIndex = indexOfFirst {
            it is CodexThreadItem.UserMessage && it.id.startsWith("local-user-") && it.text == item.text
        }
        if (localEchoIndex >= 0) {
            mapIndexed { index, existing -> if (index == localEchoIndex) item else existing }
        } else if (any { it.id == item.id }) {
            map { if (it.id == item.id) item else it }
        } else {
            this + item
        }
    } else if (any { it.id == item.id }) {
        map { if (it.id == item.id) item else it }
    } else {
        this + item
    }

private fun CodexThread.mapItems(transform: (CodexThreadItem) -> CodexThreadItem): CodexThread =
    copy(turns = turns.map { turn -> turn.copy(items = turn.items.map(transform)) })

/** A thread together with its flattened item list and the full projection of exactly that list. */
private data class ProjectedThread(
    val thread: CodexThread,
    val items: List<CodexSessionItem>,
    val sections: List<ConversationSection>,
)

private fun projectThreadSections(thread: CodexThread): ProjectedThread =
    ProjectedThread(thread, thread.flattenedSharedItems(), thread.conversationSections())

/**
 * Mirrors a single items-list change onto the accumulator without re-projecting the whole
 * list: append (size +1, unchanged prefix), single-index in-place update (size and item id
 * unchanged), or no-op. Anything structurally ambiguous — multiple changes, removals,
 * changed row identity, an out-of-sync accumulator — falls back to a full
 * [ConversationSectionAccumulator.reset], because the projected sections must always equal
 * `CodexSessionProjection.sections(next)` exactly.
 */
internal fun ConversationSectionAccumulator.applyItemsChange(
    previous: List<CodexSessionItem>,
    next: List<CodexSessionItem>,
) {
    if (sections.size == previous.size) {
        if (next.size == previous.size + 1 && next.subList(0, previous.size) == previous) {
            append(next.last())
            return
        }
        if (next.size == previous.size) {
            var changedIndex = -1
            for (index in next.indices) {
                if (next[index] != previous[index]) {
                    if (changedIndex >= 0) {
                        changedIndex = -2 // more than one index changed
                        break
                    }
                    changedIndex = index
                }
            }
            when {
                changedIndex == -1 -> return // nothing changed
                changedIndex >= 0 &&
                    next[changedIndex].id == previous[changedIndex].id &&
                    updateAt(changedIndex, next[changedIndex]) -> return
            }
        }
    }
    reset(next)
}

private data class CachedAttachment(val localPath: String, val mimeType: String?) {
    val isImage: Boolean
        get() = mimeType?.startsWith("image/") == true || localPath.isImageAttachmentPath()
}

private fun String.isImageAttachmentPath(): Boolean =
    substringAfterLast('.', "").lowercase() in setOf("png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp")

private const val MACOS_PRIVACY_WARNING_DISMISSED_KEY = "dismissedMacOSPrivacyWarning"
private const val STREAMED_SECTIONS_FLUSH_WINDOW_MILLIS = 50L
private const val MAX_CACHED_THREAD_DETAILS = 8 // mirrors the iOS detail-cache cap
private const val MAX_CACHED_THREAD_LISTS = 16

/** Maps a past ACP session summary into the session-list model the UI already renders. */
private fun mobidex.shared.AcpSessionSummary.toPlaceholderThread(): CodexThread {
    val updatedEpoch = updatedAt?.let { runCatching { Instant.parse(it).epochSecond }.getOrNull() } ?: 0L
    return CodexThread(
        id = sessionId,
        preview = title?.trim().orEmpty().ifEmpty { "ACP session" },
        cwd = cwd.orEmpty(),
        status = CodexThreadStatus(type = "idle"),
        updatedAtEpochSeconds = updatedEpoch,
        createdAtEpochSeconds = updatedEpoch,
    )
}

/**
 * Evicts in iteration order until the map is within [cap], never evicting [protect].
 * Callers re-insert keys on write (remove-then-put), making a LinkedHashMap-backed
 * mutableMapOf's iteration order equal write recency — deterministic, no timestamp ties.
 */
internal fun <K, V> MutableMap<K, V>.evictOldestBeyond(cap: Int, protect: K) {
    while (size > cap) {
        val oldest = keys.firstOrNull { it != protect } ?: return
        remove(oldest)
    }
}
private const val REMOTE_DIRECTORY_BROWSE_TIMEOUT_MILLIS = 20_000L
private const val NEW_SESSION_OPERATION_TIMEOUT_MILLIS = 30_000L

private suspend fun <T> withRemoteDirectoryBrowseTimeout(block: suspend () -> T): T =
    try {
        withTimeout(REMOTE_DIRECTORY_BROWSE_TIMEOUT_MILLIS) { block() }
    } catch (error: TimeoutCancellationException) {
        throw IllegalStateException("Remote folder browsing timed out after 20 seconds.", error)
    }

private suspend fun <T> withNewSessionOperationTimeout(message: String, block: suspend () -> T): T =
    try {
        withTimeout(NEW_SESSION_OPERATION_TIMEOUT_MILLIS) { block() }
    } catch (error: TimeoutCancellationException) {
        throw IllegalStateException(message, error)
    }

private fun String.sanitizedAttachmentName(): String {
    val sanitized = replace(Regex("""[^A-Za-z0-9._-]"""), "_").trim('_')
    return sanitized.ifEmpty { "attachment" }
}
