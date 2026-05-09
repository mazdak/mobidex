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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
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
import mobidex.android.model.CodexThreadItem
import mobidex.android.model.CodexTurn
import mobidex.android.model.PendingApproval
import mobidex.android.model.ProjectRecord
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.ServerRecord
import mobidex.android.model.conversationSections
import mobidex.android.service.CodexAppServerClient
import mobidex.android.service.CodexAppServerEvent
import mobidex.android.service.MobidexSshService
import mobidex.android.service.SshjMobidexSshService
import mobidex.android.service.array
import mobidex.android.service.long
import mobidex.android.service.obj
import mobidex.android.service.parseItem
import mobidex.android.service.parseStatus
import mobidex.android.service.parseThread
import mobidex.android.service.parseTokenUsage
import mobidex.android.service.parseTurn
import mobidex.android.service.string
import mobidex.android.service.toSharedJsonValue
import mobidex.android.service.turnOptions
import mobidex.shared.CodexAccessMode
import mobidex.shared.CodexInputItem
import mobidex.shared.CodexReasoningEffortOption
import mobidex.shared.CodexThreadSummary
import mobidex.shared.GitDiffSnapshot
import mobidex.shared.JsonValue
import mobidex.shared.ProjectCatalog
import mobidex.shared.ProjectListSections
import mobidex.shared.RemoteDirectoryListing
import mobidex.shared.RemoteProject
import mobidex.shared.SessionListSections
import mobidex.shared.jsonArray
import mobidex.shared.jsonNull
import mobidex.shared.jsonObject
import mobidex.shared.jsonString

data class MobidexUiState(
    val servers: List<ServerRecord> = emptyList(),
    val selectedServerID: String? = null,
    val selectedProjectID: String? = null,
    val threads: List<CodexThread> = emptyList(),
    val selectedThreadID: String? = null,
    val selectedThread: CodexThread? = null,
    val conversationSections: List<mobidex.shared.ConversationSection> = emptyList(),
    val pendingApprovals: List<PendingApproval> = emptyList(),
    val connectionState: ServerConnectionState = ServerConnectionState.Disconnected,
    val failureMessage: String? = null,
    val statusMessage: String? = null,
    val isBusy: Boolean = false,
    val isRefreshingSessions: Boolean = false,
    val selectedReasoningEffort: CodexReasoningEffortOption = CodexReasoningEffortOption.Medium,
    val selectedAccessMode: CodexAccessMode = CodexAccessMode.FullAccess,
    val showsArchivedSessions: Boolean = false,
    val isDiscoveringProjects: Boolean = false,
    val diffSnapshot: GitDiffSnapshot = GitDiffSnapshot.Empty,
    val isRefreshingChanges: Boolean = false,
    val tokenUsagePercent: Int? = null,
) {
    val selectedServer: ServerRecord?
        get() = servers.firstOrNull { it.id == selectedServerID }

    val selectedProject: ProjectRecord?
        get() = selectedServer?.projects?.firstOrNull { it.id == selectedProjectID }

    val canSendMessage: Boolean
        get() = connectionState == ServerConnectionState.Connected && !isBusy

    val canCreateSession: Boolean
        get() = connectionState == ServerConnectionState.Connected && !isBusy

    val activeTurnID: String?
        get() = selectedThread?.turns?.lastOrNull { it.status == "inProgress" }?.id
}

data class AndroidProjectListSections(
    val favorites: List<ProjectRecord>,
    val discovered: List<ProjectRecord>,
    val added: List<ProjectRecord>,
    val showInactiveDiscoveredFilter: Boolean,
    val showArchivedSessionFilter: Boolean,
    val discoveredTitle: String,
) {
    val isEmpty: Boolean
        get() = favorites.isEmpty() && discovered.isEmpty() && added.isEmpty()
}

class AppViewModel(
    private val repository: ServerRepository,
    private val credentialStore: CredentialStore,
    private val hostKeyStore: HostKeyStore,
    private val sshService: MobidexSshService,
) : ViewModel() {
    private val _state = MutableStateFlow(MobidexUiState())
    val state: StateFlow<MobidexUiState> = _state.asStateFlow()

    private var appServer: CodexAppServerClient? = null
    private var eventJob: Job? = null
    private var diffSnapshotRequestID = 0L
    private var activeSessionRefreshes = 0
    private var sessionRefreshGeneration = 0L
    private val appContext = context.applicationContext

    init {
        viewModelScope.launch { loadServers() }
    }

    fun selectServer(serverID: String?) {
        if (_state.value.connectionState == ServerConnectionState.Connected || _state.value.connectionState == ServerConnectionState.Connecting) {
            _state.update { it.copy(statusMessage = "Disconnect before switching servers.") }
            return
        }
        resetSessionRefreshTracking()
        _state.update { state ->
            val server = state.servers.firstOrNull { it.id == serverID }
            state.copy(
                selectedServerID = serverID,
                selectedProjectID = server?.projects?.firstOrNull()?.id,
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                pendingApprovals = emptyList(),
                diffSnapshot = GitDiffSnapshot.Empty,
                failureMessage = null,
                statusMessage = null,
            )
        }
    }

    fun selectProject(projectID: String?) {
        val refreshGeneration = beginSessionRefresh()
        _state.update {
            it.copy(
                selectedProjectID = projectID,
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
                diffSnapshot = GitDiffSnapshot.Empty,
            )
        }
        refreshThreads(refreshGeneration = refreshGeneration)
    }

    fun setReasoningEffort(effort: CodexReasoningEffortOption) {
        _state.update { it.copy(selectedReasoningEffort = effort) }
    }

    fun setAccessMode(mode: CodexAccessMode) {
        _state.update { it.copy(selectedAccessMode = mode) }
    }

    fun setShowsArchivedSessions(show: Boolean) {
        if (_state.value.showsArchivedSessions == show) return
        val refreshGeneration = beginSessionRefresh()
        _state.update {
            it.copy(
                showsArchivedSessions = show,
                threads = emptyList(),
                selectedThreadID = null,
                selectedThread = null,
                conversationSections = emptyList(),
            )
        }
        refreshThreads(refreshGeneration = refreshGeneration)
    }

    fun showTerminalPlaceholder() {
        _state.update {
            it.copy(statusMessage = "Terminal entry point is in place. PTY transport and WebView rendering are not wired yet.")
        }
    }

    suspend fun listRemoteDirectories(path: String): RemoteDirectoryListing {
        val state = _state.value
        val server = state.selectedServer ?: error("Select a server before browsing folders.")
        return sshService.listDirectories(path, server, credentialStore.loadCredential(server.id))
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
                        selectedProjectID = next.projects.firstOrNull()?.id,
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
                        selectedProjectID = updated.firstOrNull()?.projects?.firstOrNull()?.id,
                        connectionState = if (wasSelected) ServerConnectionState.Disconnected else state.connectionState,
                        failureMessage = null,
                        statusMessage = "Deleted ${server.displayName}.",
                    )
                    if (wasSelected) deleted.clearingSessionScope() else deleted
                }
                credentialStore.deleteCredential(server.id)
                hostKeyStore.deleteHostKeyFingerprint(server.id)
                repository.saveServers(updated)
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
                require(server.projects.none { it.path == trimmed }) { "That project is already saved." }
                val project = ProjectRecord(path = trimmed)
                val updatedServer = server.copy(projects = server.projects + project, updatedAtEpochSeconds = Instant.now().epochSecond)
                val updated = state.servers.upsert(updatedServer)
                repository.saveServers(updated)
                _state.update {
                    it.copy(
                        servers = updated,
                        selectedProjectID = project.id,
                        threads = emptyList(),
                        selectedThreadID = null,
                        selectedThread = null,
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
            val updatedServer = server.copy(projects = server.projects.filterNot { it.id == project.id })
            val updated = state.servers.upsert(updatedServer)
            repository.saveServers(updated)
            resetSessionRefreshTracking()
            _state.update { current ->
                val removedSelectedProject = current.selectedProjectID == project.id
                val next = current.copy(
                    servers = updated,
                    selectedProjectID = if (removedSelectedProject) updatedServer.projects.firstOrNull()?.id else current.selectedProjectID,
                )
                if (removedSelectedProject) next.clearingSessionScope() else next
            }
        }
    }

    fun setProjectFavorite(project: ProjectRecord, favorite: Boolean) {
        viewModelScope.launch {
            val state = _state.value
            val server = state.selectedServer ?: return@launch
            val updatedServer = server.copy(projects = server.projects.map { if (it.id == project.id) it.copy(isFavorite = favorite) else it })
            val updated = state.servers.upsert(updatedServer)
            repository.saveServers(updated)
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

    fun connectSelectedServer() {
        viewModelScope.launch {
            val server = _state.value.selectedServer ?: return@launch
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
                    _state.update { it.copy(connectionState = ServerConnectionState.Connected, statusMessage = "App-server connected.") }
                    refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = false)
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
        viewModelScope.launch { disconnectInternal(updateState) }
    }

    fun refreshProjects() {
        viewModelScope.launch {
            runBusy("Syncing projects") {
                val server = _state.value.selectedServer ?: return@runBusy
                val client = appServer ?: error("Connect to the app-server before syncing projects.")
                refreshProjectsFromAppServer(server, client, includeRemoteDiscovery = true)
            }
        }
    }

    fun refreshThreads() {
        val refreshGeneration = beginSessionRefresh()
        refreshThreads(refreshGeneration = refreshGeneration)
    }

    private fun refreshThreads(refreshGeneration: Long) {
        viewModelScope.launch {
            try {
                runBusy("Refreshing sessions") {
                    val state = _state.value
                    val client = appServer ?: return@runBusy
                    val requestServerID = state.selectedServerID
                    val requestProjectID = state.selectedProjectID
                    val project = state.selectedProject
                    val cwd = project?.path
                    val sessionPaths = project?.sessionPaths ?: emptyList()
                    val includeArchived = state.showsArchivedSessions
                    val loaded = if (sessionPaths.isEmpty()) {
                        client.listThreads(cwd, includeArchived = includeArchived)
                    } else {
                        val exactMatches = sessionPaths.flatMap { path -> client.listThreads(path, includeArchived = includeArchived) }
                        if (exactMatches.isNotEmpty()) {
                            exactMatches.distinctBy { it.id }
                        } else {
                            val unscoped = client.listThreads(null, includeArchived = includeArchived)
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
                            unscoped.filter { it.id in groupedSessionIDs }.distinctBy { it.id }
                        }
                    }
                    _state.update { current ->
                        if (appServer !== client || current.selectedServerID != requestServerID || current.selectedProjectID != requestProjectID) {
                            current
                        } else {
                            current.copy(threads = loaded.sortedByDescending { thread -> thread.updatedAtEpochSeconds })
                        }
                    }
                }
            } finally {
                endSessionRefresh(refreshGeneration)
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
        activeSessionRefreshes = 0
        _state.update { it.copy(isRefreshingSessions = false) }
    }

    fun openThread(thread: CodexThread) {
        viewModelScope.launch {
            val requestServerID = _state.value.selectedServerID
            val requestProjectID = _state.value.selectedProjectID
            _state.update {
                it.copy(
                    selectedThreadID = thread.id,
                    selectedThread = thread,
                    conversationSections = thread.conversationSections(),
                    diffSnapshot = GitDiffSnapshot.Empty,
                )
            }
            runBusy("Opening session") {
                val client = appServer ?: return@runBusy
                val hydrated = client.resumeThread(thread.id)
                hydrateConversationIfCurrent(hydrated, requestServerID, requestProjectID, thread.id)
                refreshProjectsForCurrentScope(client, requestServerID)
            }
        }
    }

    fun startNewSession() {
        viewModelScope.launch {
            runBusy("Starting session") {
                val state = _state.value
                val client = appServer ?: return@runBusy
                val requestServerID = state.selectedServerID
                val requestProjectID = state.selectedProjectID
                val requestThreadID = state.selectedThreadID
                val cwd = state.selectedProject?.path ?: return@runBusy
                val thread = client.startThread(cwd)
                hydrateConversationIfCurrent(thread, requestServerID, requestProjectID, requestThreadID)
                _state.update { current ->
                    if (!requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                        current
                    } else {
                        current.copy(threads = (listOf(thread) + current.threads).distinctBy { item -> item.id })
                    }
                }
                refreshProjectsForCurrentScope(client, requestServerID)
            }
        }
    }

    fun sendComposerText(text: String) {
        sendComposerInput(text, emptyList(), onComplete = {})
    }

    fun sendComposerInput(text: String, attachmentUris: List<Uri>, onComplete: (Boolean) -> Unit = {}) {
        viewModelScope.launch {
            val trimmed = text.trim()
            if (trimmed.isEmpty() && attachmentUris.isEmpty()) {
                onComplete(false)
                return@launch
            }
            var didSubmitInput = false
            runBusy(if (attachmentUris.isEmpty()) "Sending" else "Uploading attachments") {
                val client = appServer ?: error("Connect to the app-server before sending a message.")
                val requestState = _state.value
                val requestServerID = requestState.selectedServerID
                val requestProjectID = requestState.selectedProjectID
                val requestThreadID = requestState.selectedThreadID
                var thread = requestState.selectedThread
                var createdThread = false
                if (thread == null) {
                    thread = client.startThread(requestState.selectedProject?.path)
                    createdThread = true
                    hydrateConversationIfCurrent(thread, requestServerID, requestProjectID, requestThreadID)
                }
                if (!requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                    return@runBusy
                }
                val input = buildList {
                    if (trimmed.isNotEmpty()) add(CodexInputItem.Text(trimmed))
                    addAll(stageAttachmentInputs(attachmentUris, requestState.selectedServer ?: error("Select a server before uploading attachments.")))
                }
                if (input.isEmpty()) return@runBusy
                val activeTurnID = _state.value.activeTurnID
                if (thread.status.isActive && activeTurnID != null) {
                    client.steer(thread.id, activeTurnID, input)
                    _state.update {
                        if (requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                            it.copy(statusMessage = "Steered active turn.")
                        } else {
                            it
                        }
                    }
                    didSubmitInput = true
                } else {
                    val turn = client.startTurn(
                        threadID = thread.id,
                        input = input,
                        options = turnOptions(_state.value.selectedReasoningEffort, _state.value.selectedAccessMode, thread.cwd),
                    )
                    if (!requestMatchesCurrentScope(client, requestServerID, requestProjectID, thread.id)) {
                        return@runBusy
                    }
                    hydrateConversation(thread.copy(status = thread.status.copy(type = if (turn.status == "inProgress") "active" else "idle"), turns = thread.turns.upsert(turn)))
                    didSubmitInput = true
                }
                refreshThreads()
                if (createdThread) refreshProjectsForCurrentScope(client, requestServerID)
            }
            onComplete(didSubmitInput)
        }
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
            val state = _state.value
            val thread = state.selectedThread ?: return@launch
            val turnID = state.activeTurnID ?: return@launch
            runBusy("Interrupting") {
                appServer?.interrupt(thread.id, turnID)
            }
        }
    }

    fun respond(approval: PendingApproval, accept: Boolean) {
        viewModelScope.launch {
            runBusy(if (accept) "Approving" else "Declining") {
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
                    selectedProjectID = servers.firstOrNull()?.projects?.firstOrNull()?.id,
                )
            }
        }.onFailure { error -> _state.update { it.copy(statusMessage = error.message) } }
    }

    private suspend fun disconnectInternal(updateState: Boolean = true) {
        eventJob?.cancel()
        eventJob = null
        appServer?.close()
        appServer = null
        resetSessionRefreshTracking()
        if (updateState) {
            val servers = _state.value.servers.clearingAppServerProjectState()
            repository.saveServers(servers)
            _state.update {
                it.copy(
                    servers = servers,
                    connectionState = ServerConnectionState.Disconnected,
                    pendingApprovals = emptyList(),
                    statusMessage = "App-server disconnected.",
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
                    val selectedProjectID = repairedSelectedProjectID(it.selectedProjectID, refreshed)
                    val projectSelectionChanged = selectedProjectID != it.selectedProjectID
                    it.copy(
                        servers = updatedServers,
                        selectedProjectID = selectedProjectID,
                        threads = if (projectSelectionChanged) emptyList() else it.threads,
                        selectedThreadID = if (projectSelectionChanged) null else it.selectedThreadID,
                        selectedThread = if (projectSelectionChanged) null else it.selectedThread,
                        conversationSections = if (projectSelectionChanged) emptyList() else it.conversationSections,
                        diffSnapshot = if (projectSelectionChanged) GitDiffSnapshot.Empty else it.diffSnapshot,
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
                isFavorite = previous?.isFavorite ?: shared.isFavorite,
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
        else -> projects.firstOrNull()?.id
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
            isFavorite = isFavorite,
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
            favorites = sections.favorites.mapNotNull { projectsByPath[it.path] },
            discovered = sections.discovered.mapNotNull { projectsByPath[it.path] },
            added = sections.added.mapNotNull { projectsByPath[it.path] },
            showInactiveDiscoveredFilter = sections.showInactiveDiscoveredFilter,
            showArchivedSessionFilter = sections.showArchivedSessionFilter,
            discoveredTitle = sections.discoveredTitle,
        )
    }

    private fun startEventLoop(client: CodexAppServerClient) {
        eventJob?.cancel()
        eventJob = viewModelScope.launch {
            client.events.collect { event ->
                when (event) {
                    is CodexAppServerEvent.Disconnected -> {
                        disconnectInternal(updateState = false)
                        val servers = _state.value.servers.clearingAppServerProjectState()
                        repository.saveServers(servers)
                        _state.update {
                            it.copy(
                                servers = servers,
                                connectionState = ServerConnectionState.Disconnected,
                                statusMessage = event.message,
                                pendingApprovals = emptyList(),
                            )
                        }
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

    private suspend fun handleNotification(method: String, params: JsonElement?) {
        when (method) {
            "thread/started" -> params.obj("thread")?.let {
                val thread = parseThread(it)
                if (threadMatchesCurrentScope(thread)) {
                    hydrateConversation(thread)
                }
                refreshThreads()
                appServer?.let { client -> refreshProjectsForCurrentScope(client, _state.value.selectedServerID) }
            }
            "turn/started", "turn/completed" -> {
                if (!eventTargetsSelectedThread(params)) return
                val turn = params.obj("turn")?.let { parseTurn(it) } ?: return
                _state.update { state ->
                    val thread = state.selectedThread ?: return@update state
                    val next = thread.copy(
                        status = if (method == "turn/started") thread.status.copy(type = "active") else thread.status.copy(type = "idle"),
                        turns = thread.turns.upsert(turn),
                    )
                    state.copy(selectedThread = next, conversationSections = next.conversationSections())
                }
                if (method == "turn/completed") {
                    refreshThreads()
                    _state.value.selectedThreadID?.let { id -> appServer?.readThread(id)?.let { hydrateConversation(it) } }
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
                refreshThreads()
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
            else -> if (method.startsWith("thread/")) refreshThreads()
        }
    }

    private fun hydrateConversation(thread: CodexThread) {
        _state.update {
            it.copy(
                selectedThreadID = thread.id,
                selectedThread = thread,
                conversationSections = thread.conversationSections(),
            )
        }
    }

    private fun hydrateConversationIfCurrent(
        thread: CodexThread,
        requestServerID: String?,
        requestProjectID: String?,
        requestThreadID: String?,
    ) {
        _state.update { state ->
            if (state.selectedServerID != requestServerID || state.selectedProjectID != requestProjectID || state.selectedThreadID != requestThreadID) {
                state
            } else {
                state.copy(
                    selectedThreadID = thread.id,
                    selectedThread = thread,
                    conversationSections = thread.conversationSections(),
                )
            }
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

    private fun upsertItem(item: CodexThreadItem) {
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val turn = thread.turns.lastOrNull() ?: return@update state
            val nextTurn = turn.copy(items = turn.items.upsert(item))
            val nextThread = thread.copy(turns = thread.turns.upsert(nextTurn))
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
    }

    private fun appendTextDelta(itemID: String?, delta: String?, agent: Boolean) {
        if (itemID == null || delta == null) return
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                when {
                    agent && item is CodexThreadItem.AgentMessage && item.id == itemID -> item.copy(text = item.text + delta)
                    !agent && item is CodexThreadItem.Plan && item.id == itemID -> item.copy(text = item.text + delta)
                    else -> item
                }
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
    }

    private fun appendCommandDelta(itemID: String?, delta: String?) {
        if (itemID == null || delta == null) return
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                if (item is CodexThreadItem.Command && item.id == itemID) {
                    item.copy(output = (item.output ?: "") + delta)
                } else {
                    item
                }
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
    }

    private fun appendReasoningDelta(itemID: String?, delta: String?, index: Int?, summary: Boolean) {
        if (itemID == null || delta == null) return
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                if (item is CodexThreadItem.Reasoning && item.id == itemID) {
                    if (summary) item.copy(summary = appendIndexed(item.summary, index, delta)) else item.copy(content = appendIndexed(item.content, index, delta))
                } else {
                    item
                }
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
    }

    private fun ensureReasoningPart(itemID: String?, index: Int?, summary: Boolean) {
        if (itemID == null || index == null) return
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                if (item is CodexThreadItem.Reasoning && item.id == itemID) {
                    if (summary) item.copy(summary = ensureIndexed(item.summary, index)) else item.copy(content = ensureIndexed(item.content, index))
                } else {
                    item
                }
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
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
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                if (item is CodexThreadItem.FileChange && item.id == itemID) item.copy(changes = changes) else item
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
    }

    private fun appendFileChangeOutputDelta(itemID: String?, delta: String?) {
        if (itemID == null || delta == null) return
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                if (item is CodexThreadItem.FileChange && item.id == itemID) {
                    val change = item.changes.firstOrNull() ?: mobidex.android.model.CodexFileChange("Patch output", "")
                    item.copy(changes = listOf(change.copy(diff = change.diff + delta)) + item.changes.drop(1))
                } else {
                    item
                }
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
    }

    private fun appendToolProgress(itemID: String?, message: String?) {
        if (itemID == null || message.isNullOrBlank()) return
        _state.update { state ->
            val thread = state.selectedThread ?: return@update state
            val nextThread = thread.mapItems { item ->
                if (item is CodexThreadItem.ToolCall && item.id == itemID) {
                    item.copy(detail = listOfNotNull(item.detail, message).joinToString("\n"))
                } else {
                    item
                }
            }
            state.copy(selectedThread = nextThread, conversationSections = nextThread.conversationSections())
        }
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
        _state.update { it.copy(isBusy = true, statusMessage = status, failureMessage = null) }
        runCatching { block() }
            .onFailure { error ->
                _state.update {
                    it.copy(
                        connectionState = if (marksFailure) ServerConnectionState.Failed else it.connectionState,
                        failureMessage = error.message,
                        statusMessage = error.message,
                    )
                }
            }
        _state.update { it.copy(isBusy = false) }
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
        runBlocking(Dispatchers.IO) { disconnectInternal(updateState = false) }
    }

    class Factory(private val context: Context) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            val hostKeyStore = SharedPreferencesHostKeyStore(context)
            return AppViewModel(
                repository = SharedPreferencesServerRepository(context),
                credentialStore = AndroidCredentialStore(context),
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
        diffSnapshot = GitDiffSnapshot.Empty,
        isRefreshingSessions = false,
        tokenUsagePercent = null,
    )

private fun List<ServerRecord>.clearingAppServerProjectState(): List<ServerRecord> =
    map { server ->
        server.copy(
            projects = server.projects.mapNotNull { project ->
                when {
                    !project.discovered -> project.copy(activeChatCount = 0, lastActiveChatAtEpochSeconds = null)
                    project.isFavorite -> project.copy(
                        discovered = false,
                        sessionPaths = listOf(project.path),
                        discoveredSessionCount = 0,
                        archivedSessionCount = 0,
                        activeChatCount = 0,
                        lastDiscoveredAtEpochSeconds = null,
                        lastActiveChatAtEpochSeconds = null,
                    )
                    else -> null
                }
            }
        )
    }

private fun List<ServerRecord>.upsert(server: ServerRecord): List<ServerRecord> =
    if (any { it.id == server.id }) map { if (it.id == server.id) server else it } else this + server

private fun List<CodexTurn>.upsert(turn: CodexTurn): List<CodexTurn> =
    if (any { it.id == turn.id }) map { if (it.id == turn.id) turn else it } else this + turn

private fun List<CodexThreadItem>.upsert(item: CodexThreadItem): List<CodexThreadItem> =
    if (any { it.id == item.id }) map { if (it.id == item.id) item else it } else this + item

private fun CodexThread.mapItems(transform: (CodexThreadItem) -> CodexThreadItem): CodexThread =
    copy(turns = turns.map { turn -> turn.copy(items = turn.items.map(transform)) })

private data class CachedAttachment(val localPath: String, val mimeType: String?) {
    val isImage: Boolean
        get() = mimeType?.startsWith("image/") == true || localPath.isImageAttachmentPath()
}

private fun String.isImageAttachmentPath(): Boolean =
    substringAfterLast('.', "").lowercase() in setOf("png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp")

private fun String.sanitizedAttachmentName(): String {
    val sanitized = replace(Regex("""[^A-Za-z0-9._-]"""), "_").trim('_')
    return sanitized.ifEmpty { "attachment" }
}
