package mobidex.android.ui

import android.animation.ValueAnimator
import android.net.Uri
import android.util.Base64
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewAssetLoader
import androidx.compose.foundation.text.KeyboardOptions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import mobidex.android.AndroidProjectListSections
import mobidex.android.AppViewModel
import mobidex.android.MobidexUiState
import mobidex.android.model.CodexThread
import mobidex.android.model.PendingApproval
import mobidex.android.model.ProjectRecord
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.ServerRecord
import mobidex.android.service.RemoteTerminalSession
import mobidex.shared.CodexAccessMode
import mobidex.shared.CodexReasoningEffortOption
import mobidex.shared.ConversationSection
import mobidex.shared.ConversationSectionKind
import mobidex.shared.GitDiffSnapshot
import mobidex.shared.RemoteDirectoryEntry
import mobidex.shared.RemoteServerLaunchDefaults
import org.json.JSONObject

@Composable
fun MobidexApp(model: AppViewModel) {
    val state by model.state.collectAsState()
    var showServerEditor by remember { mutableStateOf<ServerRecord?>(null) }
    var showNewServer by remember { mutableStateOf(false) }
    var showProjectAdd by remember { mutableStateOf(false) }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints {
            if (maxWidth >= 960.dp) {
                WideMobidexApp(
                    state = state,
                    model = model,
                    onAddServer = { showNewServer = true },
                    onEditServer = { showServerEditor = it },
                    onAddProject = { showProjectAdd = true },
                )
            } else {
                CompactMobidexApp(
                    state = state,
                    model = model,
                    onAddServer = { showNewServer = true },
                    onEditServer = { showServerEditor = it },
                    onAddProject = { showProjectAdd = true },
                )
            }
        }
    }

    val editingServer = showServerEditor
    if (showNewServer || editingServer != null) {
        ServerEditorDialog(
            original = editingServer,
            model = model,
            onDismiss = {
                showNewServer = false
                showServerEditor = null
            },
        )
    }
    if (showProjectAdd) {
        ProjectAddDialog(
            model = model,
            onDismiss = { showProjectAdd = false },
            onAdd = { path ->
                model.addProject(path)
                showProjectAdd = false
            },
        )
    }
}

@Composable
private fun WideMobidexApp(
    state: MobidexUiState,
    model: AppViewModel,
    onAddServer: () -> Unit,
    onEditServer: (ServerRecord) -> Unit,
    onAddProject: () -> Unit,
) {
    Row(Modifier.fillMaxSize()) {
        ServerPane(state, model, onAddServer, onEditServer, Modifier.width(300.dp).fillMaxHeight())
        VerticalDivider(Modifier.fillMaxHeight())
        ProjectSessionPane(state, model, onAddProject, onEditServer, Modifier.width(380.dp).fillMaxHeight())
        VerticalDivider(Modifier.fillMaxHeight())
        ConversationPane(state, model, Modifier.weight(1f).fillMaxHeight())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CompactMobidexApp(
    state: MobidexUiState,
    model: AppViewModel,
    onAddServer: () -> Unit,
    onEditServer: (ServerRecord) -> Unit,
    onAddProject: () -> Unit,
) {
    var tab by remember { mutableStateOf(0) }
    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        Text(
                            compactTitle(tab, state),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                )
                PrimaryTabRow(selectedTabIndex = tab) {
                    Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Servers") })
                    Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Projects") })
                    Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("Chat") })
                }
            }
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (tab) {
                0 -> ServerPane(state, model, onAddServer, onEditServer, Modifier.fillMaxSize(), onOpenProjects = { tab = 1 })
                1 -> ProjectSessionPane(state, model, onAddProject, onEditServer, Modifier.fillMaxSize(), onOpenDetail = { tab = 2 })
                else -> ConversationPane(state, model, Modifier.fillMaxSize())
            }
        }
    }
}

private fun compactTitle(tab: Int, state: MobidexUiState): String =
    when (tab) {
        0 -> "Servers"
        1 -> state.selectedServer?.displayName ?: "Mobidex"
        else -> state.selectedProject?.displayName ?: "Chat"
    }

@Composable
private fun ServerPane(
    state: MobidexUiState,
    model: AppViewModel,
    onAddServer: () -> Unit,
    onEditServer: (ServerRecord) -> Unit,
    modifier: Modifier = Modifier,
    onOpenProjects: () -> Unit = {},
) {
    var serverPendingDeletion by remember { mutableStateOf<ServerRecord?>(null) }
    Column(modifier) {
        PaneHeader("Servers", Icons.Default.Storage) {
            IconButton(onClick = onAddServer) {
                Icon(Icons.Default.Add, contentDescription = "Add Server")
            }
        }
        if (state.servers.isEmpty()) {
            EmptyState("No Servers", "Add an SSH server to begin.", Icons.Default.Storage)
        } else {
            LazyColumn(Modifier.weight(1f)) {
                items(state.servers, key = { it.id }) { server ->
                    ListItem(
                        headlineContent = { Text(server.displayName, fontWeight = FontWeight.SemiBold) },
                        supportingContent = { Text(server.endpointLabel, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        leadingContent = { Icon(Icons.Default.Storage, contentDescription = null) },
                        trailingContent = {
                            Row {
                                TextButton(onClick = { onEditServer(server) }) { Text("Edit") }
                                IconButton(onClick = { serverPendingDeletion = server }) {
                                    Icon(Icons.Default.Delete, contentDescription = "Delete Server")
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color.Transparent),
                    )
                    TextButton(
                        onClick = {
                            model.switchServerFromList(server.id)
                            onOpenProjects()
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Select")
                    }
                    HorizontalDivider()
                }
            }
        }
    }

    serverPendingDeletion?.let { pending ->
        DeleteServerConfirmationDialog(
            server = pending,
            onDismiss = { serverPendingDeletion = null },
            onConfirm = {
                serverPendingDeletion = null
                model.deleteServer(pending)
            },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProjectSessionPane(
    state: MobidexUiState,
    model: AppViewModel,
    onAddProject: () -> Unit,
    onEditServer: (ServerRecord) -> Unit,
    modifier: Modifier = Modifier,
    onOpenDetail: () -> Unit = {},
) {
    var mode by remember { mutableStateOf(ProjectSessionMode.Projects) }
    var search by remember { mutableStateOf("") }
    var showInactive by remember { mutableStateOf(false) }
    var showTerminal by remember { mutableStateOf(false) }
    var serverPendingDeletion by remember { mutableStateOf<ServerRecord?>(null) }
    val server = state.selectedServer
    val connectionMode = state.connectionState == ServerConnectionState.Connecting

    Column(modifier) {
        PaneHeader(server?.displayName ?: "Mobidex", Icons.Default.FolderOpen) {
            IconButton(onClick = { model.refreshProjects() }, enabled = server != null && state.connectionState == ServerConnectionState.Connected) {
                Icon(Icons.Default.Refresh, contentDescription = "Refresh Projects")
            }
            IconButton(onClick = onAddProject, enabled = server != null) {
                Icon(Icons.Default.Add, contentDescription = "Add Project")
            }
            if (server != null) {
                SelectedServerActionsMenu(
                    server = server,
                    onEditServer = onEditServer,
                    onDeleteServer = { serverPendingDeletion = it },
                )
            }
        }
        if (server == null) {
            EmptyState("Select a Server", "Choose a saved SSH server.", Icons.Default.Storage)
            return@Column
        }

        Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(server.endpointLabel, style = MaterialTheme.typography.bodyMedium)
            StatusRow(state)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { model.connectSelectedServer() }, enabled = !connectionMode) {
                    Text(if (state.connectionState == ServerConnectionState.Connected) "Reconnect" else "Connect")
                }
                OutlinedButton(onClick = { showTerminal = true }, enabled = !connectionMode) {
                    Icon(Icons.Default.Description, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("Terminal")
                }
            }
            SecondaryTabRow(selectedTabIndex = mode.ordinal) {
                ProjectSessionMode.entries.forEach { item ->
                    Tab(selected = mode == item, onClick = { mode = item }, text = { Text(item.label) })
                }
            }
        }

        if (showTerminal) {
            TerminalPane(
                state = state,
                model = model,
                onClose = { showTerminal = false },
                modifier = Modifier.weight(1f),
            )
        } else {
            when (mode) {
                ProjectSessionMode.Projects -> ProjectList(state, model, search, showInactive, { search = it }, { showInactive = it }, disabled = connectionMode, onOpenSessions = { mode = ProjectSessionMode.Sessions })
                ProjectSessionMode.Sessions -> ThreadList(state, model, disabled = connectionMode, onOpenDetail = onOpenDetail)
            }
        }
    }

    serverPendingDeletion?.let { pending ->
        DeleteServerConfirmationDialog(
            server = pending,
            onDismiss = { serverPendingDeletion = null },
            onConfirm = {
                serverPendingDeletion = null
                model.deleteServer(pending)
            },
        )
    }
}

@Composable
private fun DeleteServerConfirmationDialog(
    server: ServerRecord,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete server?") },
        text = { Text("This removes ${server.displayName} and its saved credentials from Mobidex.") },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text("Delete", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}

@Composable
private fun SelectedServerActionsMenu(
    server: ServerRecord,
    onEditServer: (ServerRecord) -> Unit,
    onDeleteServer: (ServerRecord) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(Icons.Default.MoreVert, contentDescription = "Server Actions")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("Edit Settings") },
                leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) },
                onClick = {
                    expanded = false
                    onEditServer(server)
                },
            )
            DropdownMenuItem(
                text = { Text("Delete Server", color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null) },
                onClick = {
                    expanded = false
                    onDeleteServer(server)
                },
            )
        }
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun TerminalPane(state: MobidexUiState, model: AppViewModel, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var terminalReady by remember { mutableStateOf(false) }
    val pendingOutput = remember { mutableStateListOf(base64TerminalChunk("Opening terminal...\n")) }
    var terminal by remember { mutableStateOf<RemoteTerminalSession?>(null) }

    fun evaluateTerminal(script: String) {
        webView?.post {
            webView?.evaluateJavascript(script, null)
        }
    }

    fun writeToTerminal(encoded: String) {
        if (!terminalReady) {
            pendingOutput.add(encoded)
            return
        }
        evaluateTerminal("window.mobidexTerminal?.writeBase64(${JSONObject.quote(encoded)})")
    }

    fun appendSystemLine(line: String) {
        writeToTerminal(base64TerminalChunk("\n$line\n"))
    }

    fun clearOpeningLine() {
        pendingOutput.clear()
        if (terminalReady) {
            evaluateTerminal("window.mobidexTerminal?.clear()")
        }
    }

    fun send(text: String) {
        val session = terminal ?: return
        scope.launch {
            runCatching { session.write(text) }.onFailure { error ->
                appendSystemLine(error.message ?: "Terminal write failed.")
            }
        }
    }

    fun sendThroughTerminalBridge(text: String) {
        if (!terminalReady) {
            send(text)
            return
        }
        evaluateTerminal("window.mobidexTerminal?.send(${JSONObject.quote(text)})")
    }

    LaunchedEffect(state.selectedServer?.id, state.selectedProject?.id, state.selectedThreadID) {
        pendingOutput.clear()
        pendingOutput.add(base64TerminalChunk("Opening terminal...\n"))
        var activeSession: RemoteTerminalSession? = null
        try {
            val session = model.openTerminalSession(columns = 80, rows = 24)
            activeSession = session
            terminal = session
            clearOpeningLine()
            session.output.collect { chunk ->
                writeToTerminal(base64TerminalChunk(chunk))
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            appendSystemLine(error.message ?: "Terminal failed.")
        } finally {
            withContext(NonCancellable) {
                activeSession?.close()
            }
            if (terminal === activeSession) {
                terminal = null
            }
        }
    }

    Column(modifier.background(Color.Black)) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("Terminal", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(state.selectedThread?.cwd ?: state.selectedProject?.path ?: state.selectedServer?.endpointLabel.orEmpty(), style = MaterialTheme.typography.bodySmall)
            }
            TextButton(onClick = onClose) { Text("Close") }
        }
        AndroidView(
            factory = { context ->
                val assetLoader = WebViewAssetLoader.Builder()
                    .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
                    .build()
                WebView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    setBackgroundColor(android.graphics.Color.BLACK)
                    webViewClient = object : WebViewClient() {
                        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                            assetLoader.shouldInterceptRequest(request.url)
                    }
                    settings.javaScriptEnabled = true
                    settings.allowFileAccess = false
                    settings.allowContentAccess = false
                    addJavascriptInterface(
                        TerminalAndroidBridge { rawMessage ->
                            post {
                                val message = runCatching { JSONObject(rawMessage) }.getOrNull() ?: return@post
                                when (message.optString("type")) {
                                    "ready" -> {
                                        terminalReady = true
                                        val queued = pendingOutput.toList()
                                        pendingOutput.clear()
                                        queued.forEach { writeToTerminal(it) }
                                        evaluateTerminal("window.mobidexTerminal?.focus()")
                                    }
                                    "input" -> send(message.optString("data"))
                                    "resize" -> {
                                        val columns = message.optInt("cols").takeIf { it > 0 } ?: return@post
                                        val rows = message.optInt("rows").takeIf { it > 0 } ?: return@post
                                        val session = terminal ?: return@post
                                        scope.launch {
                                            runCatching { session.resize(columns, rows) }
                                        }
                                    }
                                    "error" -> appendSystemLine(message.optString("message", "Terminal failed."))
                                }
                            }
                        },
                        "MobidexAndroid",
                    )
                    webView = this
                    loadUrl("https://appassets.androidplatform.net/assets/terminal/index.html")
                }
            },
            update = { webView = it },
            onRelease = { released ->
                if (webView === released) {
                    webView = null
                }
                released.removeJavascriptInterface("MobidexAndroid")
                released.stopLoading()
                released.destroy()
            },
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        )
        FlowRow(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(onClick = { sendThroughTerminalBridge("\u0003") }, enabled = terminal != null) { Text("Ctrl-C") }
            OutlinedButton(onClick = { sendThroughTerminalBridge("\u001B") }, enabled = terminal != null) { Text("Esc") }
            OutlinedButton(onClick = { sendThroughTerminalBridge("\t") }, enabled = terminal != null) { Text("Tab") }
            OutlinedButton(onClick = { evaluateTerminal("window.mobidexTerminal?.clear()") }) { Text("Clear") }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(">", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                singleLine = true,
                placeholder = { Text("Input") },
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = {
                    if (input.isEmpty()) return@Button
                    val submitted = input
                    input = ""
                    sendThroughTerminalBridge("$submitted\n")
                },
                enabled = input.isNotEmpty() && terminal != null,
            ) {
                Text("Send")
            }
        }
    }
}

private class TerminalAndroidBridge(private val onMessage: (String) -> Unit) {
    @JavascriptInterface
    fun postMessage(message: String) {
        onMessage(message)
    }
}

private fun base64TerminalChunk(text: String): String =
    Base64.encodeToString(text.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)

@Composable
private fun ProjectList(
    state: MobidexUiState,
    model: AppViewModel,
    search: String,
    showInactive: Boolean,
    onSearchChange: (String) -> Unit,
    onShowInactiveChange: (Boolean) -> Unit,
    disabled: Boolean = false,
    onOpenSessions: () -> Unit,
) {
    val sections = model.projectSections(search, showInactive, state.showsArchivedSessions)
    val contentIsLoading = state.isDiscoveringProjects || disabled
    val contentAlpha = if (contentIsLoading) 0.42f else 1f

    Column {
        OutlinedTextField(
            value = search,
            onValueChange = onSearchChange,
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            placeholder = { Text("Search Projects") },
            modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(),
            enabled = !contentIsLoading,
            singleLine = true,
        )
        if (contentIsLoading) {
            LoadingListStatusRow("Loading projects...")
        }
        if (sections.showInactiveDiscoveredFilter) {
            FilterChip(
                selected = showInactive,
                onClick = { onShowInactiveChange(!showInactive) },
                enabled = !contentIsLoading,
                label = { Text("Show inactive discovered projects") },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).graphicsLayer { alpha = contentAlpha },
            )
        }
        if (sections.showArchivedSessionFilter) {
            FilterChip(
                selected = state.showsArchivedSessions,
                onClick = { model.setShowsArchivedSessions(!state.showsArchivedSessions) },
                enabled = !contentIsLoading,
                label = { Text("Show archived sessions") },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).graphicsLayer { alpha = contentAlpha },
            )
        }
        LazyColumn(Modifier.weight(1f, fill = true).graphicsLayer { alpha = contentAlpha }) {
            section("Favorites", sections.favorites) { ProjectRow(it, state, model, onOpenSessions, enabled = !contentIsLoading) }
            section(sections.discoveredTitle, sections.discovered) { ProjectRow(it, state, model, onOpenSessions, enabled = !contentIsLoading) }
            if (sections.isEmpty) {
                item { EmptyState(projectEmptyTitle(state, sections, search), "Connect or add a project path.", Icons.Default.Folder) }
            }
        }
    }
}

@Composable
private fun LoadingListStatusRow(title: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

internal fun projectEmptyTitle(state: MobidexUiState, sections: AndroidProjectListSections, search: String): String =
    when {
        search.trim().isNotEmpty() -> "No Matching Projects"
        state.isDiscoveringProjects -> "Loading Projects"
        state.selectedServer?.projects?.isNotEmpty() == true && sections.showArchivedSessionFilter && !state.showsArchivedSessions -> "No Active Projects"
        else -> "No Projects"
    }

private fun androidx.compose.foundation.lazy.LazyListScope.section(
    title: String,
    projects: List<ProjectRecord>,
    row: @Composable (ProjectRecord) -> Unit,
) {
    if (projects.isEmpty()) return
    item { Text(title, modifier = Modifier.padding(16.dp, 14.dp, 16.dp, 6.dp), style = MaterialTheme.typography.labelLarge) }
    items(projects, key = { it.id }) { project ->
        row(project)
        HorizontalDivider()
    }
}

@Composable
private fun ProjectRow(project: ProjectRecord, state: MobidexUiState, model: AppViewModel, onOpenDetail: () -> Unit, enabled: Boolean = true) {
    ListItem(
        headlineContent = { Text(project.displayName, fontWeight = FontWeight.SemiBold) },
        supportingContent = {
            Column {
                Text(project.path, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        },
        leadingContent = { Icon(Icons.Default.Folder, contentDescription = null) },
        trailingContent = {
            Row {
                IconButton(onClick = { model.setProjectFavorite(project, !project.isFavorite) }, enabled = enabled) {
                    Icon(if (project.isFavorite) Icons.Default.Star else Icons.Default.StarBorder, contentDescription = "Favorite")
                }
                if (!project.discovered) {
                    IconButton(onClick = { model.removeProject(project) }, enabled = enabled) {
                        Icon(Icons.Default.Delete, contentDescription = "Remove Project")
                    }
                }
            }
        },
        modifier = Modifier
            .fillMaxWidth(),
    )
    TextButton(
        onClick = {
            model.selectProject(project.id)
            onOpenDetail()
        },
        enabled = enabled,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Open")
    }
}

@Composable
private fun ThreadList(state: MobidexUiState, model: AppViewModel, disabled: Boolean = false, onOpenDetail: () -> Unit) {
    val contentDisabled = state.isRefreshingSessions || disabled
    val contentAlpha = if (contentDisabled) 0.42f else 1f
    Column(Modifier.fillMaxSize()) {
        state.selectedProject?.let { project ->
            Row(
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Default.Folder, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Column(Modifier.weight(1f)) {
                    Text("Sessions in ${project.displayName}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(project.path, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        FilterChip(
            selected = state.showsArchivedSessions,
            onClick = { model.setShowsArchivedSessions(!state.showsArchivedSessions) },
            enabled = !contentDisabled,
            label = { Text("Show archived sessions") },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).graphicsLayer { alpha = contentAlpha },
        )
        if (state.threads.isEmpty()) {
            EmptyState(
                sessionEmptyTitle(state),
                "Sessions from CLI, VS Code, exec, and app-server sources appear here.",
                Icons.Default.Description,
            )
        } else {
            LazyColumn(Modifier.weight(1f, fill = true).graphicsLayer { alpha = contentAlpha }) {
                items(state.threads, key = { it.id }) { thread ->
                    ListItem(
                        headlineContent = { Text(thread.title, fontWeight = if (thread.id == state.selectedThreadID) FontWeight.SemiBold else FontWeight.Normal) },
                        supportingContent = {
                            Column {
                                Text(thread.cwd, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(thread.status.sessionLabel, color = threadStatusColor(thread))
                            }
                        },
                        leadingContent = {
                            Box(Modifier.size(10.dp).clip(CircleShape).background(threadStatusColor(thread)))
                        },
                        modifier = Modifier.background(if (thread.id == state.selectedThreadID) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else Color.Transparent),
                    )
                    TextButton(
                        onClick = {
                            model.openThread(thread)
                            onOpenDetail()
                        },
                        enabled = !contentDisabled,
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Open") }
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun ConversationPane(state: MobidexUiState, model: AppViewModel, modifier: Modifier = Modifier) {
    var detail by remember { mutableStateOf(SessionDetailMode.Chat) }
    val thread = state.selectedThread
    val project = state.selectedProject
    Column(modifier) {
        MacOSPrivacyWarningBanner(state, model)
        if (thread != null) {
            ConversationHeader(thread, state, model)
            SecondaryTabRow(selectedTabIndex = detail.ordinal) {
                SessionDetailMode.entries.forEach { mode ->
                    Tab(selected = detail == mode, onClick = { detail = mode }, text = { Text(mode.label) })
                }
            }
            when (detail) {
                SessionDetailMode.Chat -> ChatTimeline(state, model, Modifier.weight(1f))
                SessionDetailMode.Changes -> ChangesView(state, model, Modifier.weight(1f))
            }
        } else if (project != null) {
            ProjectHeader(project, state, model)
            EmptyState(
                projectSessionEmptyTitle(state),
                "Start a session from this project.",
                Icons.Default.Description,
                Modifier.weight(1f),
            )
        } else {
            EmptyState("Select a Session", "Choose a project or session to continue.", Icons.Default.Description, Modifier.weight(1f))
        }
    }
}

@Composable
private fun MacOSPrivacyWarningBanner(state: MobidexUiState, model: AppViewModel) {
    val warning = macOSPrivacyWarningForConversation(state)
    if (warning.isNullOrBlank() || state.dismissedMacOSPrivacyWarning) return
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.55f))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Default.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary)
        Text(warning, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
        IconButton(onClick = { model.dismissMacOSPrivacyWarningForever() }, modifier = Modifier.size(32.dp)) {
            Icon(Icons.Default.Close, contentDescription = "Dismiss macOS privacy warning")
        }
    }
    HorizontalDivider()
}

private fun macOSPrivacyWarningForConversation(state: MobidexUiState): String? =
    state.selectedThread?.cwd?.let { ProjectRecord.macOSPrivacyWarning(listOf(it)) }
        ?: state.selectedProject?.macOSPrivacyWarning

internal fun sessionEmptyTitle(state: MobidexUiState): String =
    when {
        state.isRefreshingSessions -> "Loading Sessions..."
        state.connectionState == ServerConnectionState.Connected -> "No Sessions"
        else -> "Connect to Load Sessions"
    }

internal fun projectSessionEmptyTitle(state: MobidexUiState): String =
    when {
        state.isRefreshingSessions -> "Loading Sessions..."
        state.connectionState == ServerConnectionState.Connected -> "No Sessions"
        else -> "Connect to Create a Session"
    }

@Composable
private fun ConversationHeader(thread: CodexThread, state: MobidexUiState, model: AppViewModel) {
    Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(thread.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(thread.cwd, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (state.activeTurnID != null) {
            IconButton(onClick = { model.interruptActiveTurn() }) {
                Icon(Icons.Default.Stop, contentDescription = "Stop Turn")
            }
        }
        SessionStatusDot(thread)
    }
    HorizontalDivider()
}

@Composable
private fun SessionStatusDot(thread: CodexThread) {
    val color = sessionHeaderStatusColor(thread)
    val shouldPulse = thread.status.isActive && ValueAnimator.areAnimatorsEnabled()
    Box(
        Modifier
            .size(28.dp)
            .semantics { contentDescription = sessionHeaderStatusDescription(thread) },
        contentAlignment = Alignment.Center,
    ) {
        if (shouldPulse) {
            val transition = rememberInfiniteTransition(label = "session status pulse")
            val pulseScale by transition.animateFloat(
                initialValue = 1f,
                targetValue = 2.35f,
                animationSpec = infiniteRepeatable(tween(durationMillis = 1050), RepeatMode.Reverse),
                label = "session status pulse scale",
            )
            val pulseAlpha by transition.animateFloat(
                initialValue = 0.28f,
                targetValue = 0.10f,
                animationSpec = infiniteRepeatable(tween(durationMillis = 1050), RepeatMode.Reverse),
                label = "session status pulse alpha",
            )
            Box(
                Modifier
                    .size(12.dp)
                    .graphicsLayer(scaleX = pulseScale, scaleY = pulseScale)
                    .clip(CircleShape)
                    .background(color.copy(alpha = pulseAlpha))
            )
        }
        Box(Modifier.size(11.dp).clip(CircleShape).background(color))
    }
}

@Composable
private fun ProjectHeader(project: ProjectRecord, state: MobidexUiState, model: AppViewModel) {
    Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f)) {
            Text(project.displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(project.path, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Button(onClick = { model.startNewSession() }, enabled = state.canCreateSession) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(Modifier.width(6.dp))
            Text("New Session")
        }
    }
    HorizontalDivider()
}

@Composable
private fun ChatTimeline(state: MobidexUiState, model: AppViewModel, modifier: Modifier = Modifier) {
    var composer by remember { mutableStateOf("") }
    var attachmentUris by remember(state.selectedThreadID) { mutableStateOf<List<Uri>>(emptyList()) }
    Column(modifier) {
        LazyColumn(Modifier.weight(1f), reverseLayout = false) {
            items(state.pendingApprovals, key = { it.id }) { approval ->
                ApprovalCard(approval, model)
            }
            items(state.conversationSections, key = { it.id }) { section ->
                ConversationSectionRow(section)
            }
        }
        Composer(
            value = composer,
            onValueChange = { composer = it },
            attachmentUris = attachmentUris,
            onAttachmentUrisChange = { attachmentUris = it },
            state = state,
            model = model,
            onSend = {
                val sentText = composer
                val sentAttachments = attachmentUris
                model.sendComposerInput(sentText, sentAttachments, queueWhenActive = false) { sent ->
                    if (!sent || composer != sentText || attachmentUris != sentAttachments) return@sendComposerInput
                    composer = ""
                    attachmentUris = emptyList()
                }
            },
            onSendFollowUp = {
                val sentText = composer
                val sentAttachments = attachmentUris
                model.sendComposerInput(sentText, sentAttachments, queueWhenActive = true) { sent ->
                    if (!sent || composer != sentText || attachmentUris != sentAttachments) return@sendComposerInput
                    composer = ""
                    attachmentUris = emptyList()
                }
            },
        )
    }
}

@Composable
private fun ApprovalCard(approval: PendingApproval, model: AppViewModel) {
    Column(
        Modifier
            .padding(16.dp)
            .background(MaterialTheme.colorScheme.tertiary.copy(alpha = 0.10f), MaterialTheme.shapes.medium)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(approval.title, fontWeight = FontWeight.SemiBold)
        if (approval.detail.isNotBlank()) Text(approval.detail, style = MaterialTheme.typography.bodySmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { model.respond(approval, true) }) {
                Icon(Icons.Default.Check, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Approve")
            }
            OutlinedButton(onClick = { model.respond(approval, false) }) {
                Icon(Icons.Default.Close, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Decline")
            }
        }
    }
}

@Composable
private fun ConversationSectionRow(section: ConversationSection) {
    val isUser = section.kind == ConversationSectionKind.User
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.88f)
                .background(sectionBackground(section), MaterialTheme.shapes.medium)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(section.title, style = MaterialTheme.typography.labelLarge, color = sectionAccent(section))
            if (section.body.isNotBlank()) {
                Text(
                    section.body,
                    fontFamily = if (section.usesCompactTypography) FontFamily.Monospace else FontFamily.Default,
                    style = if (section.usesCompactTypography) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium,
                )
            }
            if (!section.detail.isNullOrBlank()) Text(section.detail!!, style = MaterialTheme.typography.bodySmall)
            if (!section.status.isNullOrBlank()) Text(section.status!!, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun Composer(
    value: String,
    onValueChange: (String) -> Unit,
    attachmentUris: List<Uri>,
    onAttachmentUrisChange: (List<Uri>) -> Unit,
    state: MobidexUiState,
    model: AppViewModel,
    onSend: () -> Unit,
    onSendFollowUp: () -> Unit,
) {
    var showEffort by remember { mutableStateOf(false) }
    var showAccess by remember { mutableStateOf(false) }
    var showSendOptions by remember { mutableStateOf(false) }
    val sendEnabled = (value.trim().isNotEmpty() || attachmentUris.isNotEmpty()) && state.canSendMessage
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        if (uris.isNotEmpty()) onAttachmentUrisChange(attachmentUris + uris)
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) onAttachmentUrisChange(attachmentUris + uris)
    }
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text("Ask for follow-up changes") },
            minLines = 1,
            maxLines = 5,
            modifier = Modifier.fillMaxWidth(),
        )
        if (attachmentUris.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                attachmentUris.forEach { uri ->
                    AssistChip(
                        onClick = { onAttachmentUrisChange(attachmentUris - uri) },
                        label = { Text(uri.lastPathSegment ?: "Attachment", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        leadingIcon = { Icon(Icons.Default.Close, contentDescription = null) },
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IconButton(onClick = { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Icon(Icons.Default.Photo, contentDescription = "Attach Photo")
            }
            IconButton(onClick = { filePicker.launch(arrayOf("*/*")) }) {
                Icon(Icons.AutoMirrored.Filled.InsertDriveFile, contentDescription = "Attach File")
            }
            Box {
                IconButton(onClick = { showAccess = true }) {
                    Icon(state.selectedAccessMode.icon, contentDescription = "Next turn access mode ${state.selectedAccessMode.label}")
                }
                DropdownMenu(expanded = showAccess, onDismissRequest = { showAccess = false }) {
                    CodexAccessMode.entries.forEach { mode ->
                        DropdownMenuItem(
                            text = { Text(mode.label) },
                            onClick = {
                                model.setAccessMode(mode)
                                showAccess = false
                            },
                            leadingIcon = {
                                if (mode == state.selectedAccessMode) Icon(Icons.Default.Check, contentDescription = null)
                            },
                        )
                    }
                }
            }
            Box {
                AssistChip(onClick = { showEffort = true }, label = { Text("5.5 ${state.selectedReasoningEffort.label}") })
                DropdownMenu(expanded = showEffort, onDismissRequest = { showEffort = false }) {
                    CodexReasoningEffortOption.entries.forEach { effort ->
                        DropdownMenuItem(
                            text = { Text(effort.label) },
                            onClick = {
                                model.setReasoningEffort(effort)
                                showEffort = false
                            },
                            leadingIcon = {
                                if (effort == state.selectedReasoningEffort) Icon(Icons.Default.Check, contentDescription = null)
                            },
                        )
                    }
                }
            }
            state.tokenUsagePercent?.let { percent ->
                ContextUsageIndicator(percent)
            }
            Spacer(Modifier.weight(1f))
            Box {
                SendIconButton(
                    enabled = sendEnabled,
                    activeTurn = state.selectedThread?.status?.isActive == true,
                    onSend = onSend,
                    onShowOptions = { showSendOptions = true },
                )
                DropdownMenu(expanded = showSendOptions, onDismissRequest = { showSendOptions = false }) {
                    DropdownMenuItem(
                        text = { Text("Send to Codex") },
                        onClick = {
                            showSendOptions = false
                            onSend()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Send as Follow-up") },
                        onClick = {
                            showSendOptions = false
                            onSendFollowUp()
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun ContextUsageIndicator(percent: Int) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }, modifier = Modifier.size(36.dp)) {
            CircularProgressIndicator(
                progress = { (percent.coerceIn(0, 100) / 100f) },
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("Context window $percent% used") },
                onClick = { expanded = false },
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SendIconButton(
    enabled: Boolean,
    activeTurn: Boolean,
    onSend: () -> Unit,
    onShowOptions: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(48.dp)
            .clip(CircleShape)
            .combinedClickable(
                enabled = enabled,
                onClick = onSend,
                onLongClick = { if (activeTurn) onShowOptions() },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Default.ArrowUpward,
            contentDescription = "Send",
            tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
        )
    }
}

private val CodexAccessMode.icon: ImageVector
    get() = when (this) {
        CodexAccessMode.FullAccess -> Icons.Default.Security
        CodexAccessMode.WorkspaceWrite -> Icons.Default.Folder
        CodexAccessMode.ReadOnly -> Icons.Default.Visibility
    }

@Composable
private fun ChangesView(state: MobidexUiState, model: AppViewModel, modifier: Modifier = Modifier) {
    LaunchedEffect(state.selectedThread?.cwd) {
        if (state.selectedThread != null) model.refreshDiffSnapshot()
    }
    Column(modifier) {
        Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Changed Files", style = MaterialTheme.typography.titleMedium)
                Text(state.selectedThread?.cwd ?: state.selectedProject?.path ?: "", style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            IconButton(onClick = { model.refreshDiffSnapshot() }, enabled = state.connectionState == ServerConnectionState.Connected) {
                Icon(Icons.Default.Refresh, contentDescription = "Refresh Changes")
            }
        }
        if (state.isRefreshingChanges) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (state.diffSnapshot.isEmpty) {
            EmptyState(if (state.connectionState == ServerConnectionState.Connected) "No Changes" else "Connect to Check Changes", "", Icons.Default.Description)
        } else {
            DiffContent(state.diffSnapshot)
        }
    }
}

@Composable
private fun DiffContent(snapshot: GitDiffSnapshot) {
    var selectedPath by remember(snapshot) { mutableStateOf(snapshot.files.firstOrNull()?.path) }
    Row(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.width(260.dp).fillMaxHeight().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))) {
            items(snapshot.files, key = { it.path }) { file ->
                ListItem(
                    headlineContent = { Text(file.path, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                    supportingContent = { Text("${changedLineCount(file.diff)} changed lines") },
                    modifier = Modifier.background(if (selectedPath == file.path) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else Color.Transparent),
                )
                TextButton(onClick = { selectedPath = file.path }, modifier = Modifier.fillMaxWidth()) { Text("View") }
                HorizontalDivider()
            }
        }
        Text(
            text = snapshot.files.firstOrNull { it.path == selectedPath }?.diff ?: snapshot.diff,
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun ServerEditorDialog(original: ServerRecord?, model: AppViewModel, onDismiss: () -> Unit) {
    var displayName by remember(original?.id) { mutableStateOf(original?.displayName ?: "") }
    var host by remember(original?.id) { mutableStateOf(original?.host ?: "") }
    var port by remember(original?.id) { mutableStateOf((original?.port ?: 22).toString()) }
    var username by remember(original?.id) { mutableStateOf(original?.username ?: "") }
    var codexPath by remember(original?.id) { mutableStateOf(original?.codexPath ?: RemoteServerLaunchDefaults.codexPath) }
    var shellRc by remember(original?.id) { mutableStateOf(original?.targetShellRCFile ?: RemoteServerLaunchDefaults.targetShellRCFile) }
    var authMethod by remember(original?.id) { mutableStateOf(original?.authMethod ?: ServerAuthMethod.Password) }
    var password by remember(original?.id) { mutableStateOf("") }
    var privateKey by remember(original?.id) { mutableStateOf("") }
    var passphrase by remember(original?.id) { mutableStateOf("") }
    var revealPrivateKey by remember(original?.id) { mutableStateOf(original == null) }

    LaunchedEffect(original?.id) {
        if (original != null) {
            model.loadCredential(original.id) { credential ->
                password = credential.password.orEmpty()
                privateKey = credential.privateKeyPEM.orEmpty()
                passphrase = credential.privateKeyPassphrase.orEmpty()
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (original == null) "Add Server" else "Edit Server") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(displayName, { displayName = it }, label = { Text("Name") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(host, { host = it }, label = { Text("Host") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(port, { port = it.filter(Char::isDigit) }, label = { Text("Port") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(username, { username = it }, label = { Text("Username") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(shellRc, { shellRc = it }, label = { Text("Target Shell RC File") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(codexPath, { codexPath = it }, label = { Text("Full Path to Codex") }, modifier = Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = authMethod == ServerAuthMethod.Password, onClick = { authMethod = ServerAuthMethod.Password })
                    Text("Password")
                    RadioButton(selected = authMethod == ServerAuthMethod.PrivateKey, onClick = { authMethod = ServerAuthMethod.PrivateKey })
                    Text("Private Key")
                }
                if (authMethod == ServerAuthMethod.Password) {
                    OutlinedTextField(
                        password,
                        { password = it },
                        label = { Text("Password") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    OutlinedTextField(
                        privateKey,
                        { privateKey = it },
                        label = { Text("OpenSSH Private Key") },
                        minLines = 5,
                        visualTransformation = if (revealPrivateKey) VisualTransformation.None else PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        trailingIcon = {
                            IconButton(onClick = { revealPrivateKey = !revealPrivateKey }) {
                                Icon(
                                    if (revealPrivateKey) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                    contentDescription = if (revealPrivateKey) "Hide Private Key" else "Show Private Key",
                                )
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        passphrase,
                        { passphrase = it },
                        label = { Text("Passphrase") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            Button(onClick = {
                val server = ServerRecord(
                    id = original?.id ?: java.util.UUID.randomUUID().toString(),
                    displayName = displayName,
                    host = host,
                    port = port.toIntOrNull() ?: 22,
                    username = username,
                    codexPath = codexPath,
                    targetShellRCFile = shellRc,
                    authMethod = authMethod,
                    projects = original?.projects.orEmpty(),
                    createdAtEpochSeconds = original?.createdAtEpochSeconds ?: java.time.Instant.now().epochSecond,
                )
                model.saveServer(
                    server,
                    SSHCredential(
                        password = if (authMethod == ServerAuthMethod.Password) password else null,
                        privateKeyPEM = if (authMethod == ServerAuthMethod.PrivateKey) privateKey else null,
                        privateKeyPassphrase = if (authMethod == ServerAuthMethod.PrivateKey) passphrase else null,
                    ),
                    connectAfterSave = false,
                )
                onDismiss()
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ProjectAddDialog(model: AppViewModel, onDismiss: () -> Unit, onAdd: (String) -> Unit) {
    var path by remember { mutableStateOf("") }
    var showingBrowser by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Project") },
        text = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = path,
                    onValueChange = { path = it },
                    label = { Text("Remote Path") },
                    placeholder = { Text("/home/user/project") },
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { showingBrowser = true }) {
                    Icon(Icons.Default.Folder, contentDescription = "Browse Remote Folders")
                }
            }
        },
        confirmButton = { Button(onClick = { onAdd(path) }) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
    if (showingBrowser) {
        RemoteDirectoryBrowserDialog(
            model = model,
            initialPath = path.trim().ifEmpty { "/" },
            onDismiss = { showingBrowser = false },
            onChoose = { selectedPath ->
                path = selectedPath
                showingBrowser = false
            },
        )
    }
}

@Composable
private fun RemoteDirectoryBrowserDialog(
    model: AppViewModel,
    initialPath: String,
    onDismiss: () -> Unit,
    onChoose: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var currentPath by remember { mutableStateOf(initialPath) }
    var entries by remember { mutableStateOf<List<RemoteDirectoryEntry>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    fun load(path: String) {
        scope.launch {
            isLoading = true
            errorMessage = null
            runCatching { model.listRemoteDirectories(path) }
                .onSuccess { listing ->
                    currentPath = listing.path
                    entries = listing.entries
                }
                .onFailure { error ->
                    entries = emptyList()
                    errorMessage = error.message ?: "Could not browse remote folders."
                }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        load(initialPath)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Browse") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(currentPath, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                if (currentPath != "/") {
                    TextButton(onClick = { load(parentPath(currentPath)) }) {
                        Icon(Icons.Default.ArrowUpward, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("Parent Folder")
                    }
                }
                if (isLoading) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text("Loading Folders")
                    }
                } else {
                    LazyColumn(Modifier.height(320.dp)) {
                        items(entries, key = { it.path }) { entry ->
                            ListItem(
                                headlineContent = { Text(entry.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                leadingContent = { Icon(Icons.Default.Folder, contentDescription = null) },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            TextButton(onClick = { load(entry.path) }, modifier = Modifier.fillMaxWidth()) {
                                Text("Open")
                            }
                            HorizontalDivider()
                        }
                    }
                }
                errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { Button(onClick = { onChoose(currentPath) }, enabled = !isLoading) { Text("Choose") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

private fun parentPath(path: String): String {
    val trimmed = path.trimEnd('/')
    if (trimmed.isEmpty()) return "/"
    return trimmed.substringBeforeLast('/', missingDelimiterValue = "").ifEmpty { "/" }
}

@Composable
private fun PaneHeader(title: String, icon: ImageVector, actions: @Composable RowScope.() -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(64.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null)
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        actions()
    }
    HorizontalDivider()
}

@Composable
private fun StatusRow(state: MobidexUiState) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(connectionColor(state.connectionState)))
        Text(state.failureMessage ?: state.connectionState.label, color = connectionColor(state.connectionState), style = MaterialTheme.typography.bodySmall)
        if (state.isBusy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
    }
}

@Composable
private fun EmptyState(title: String, detail: String, icon: ImageVector, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(42.dp), tint = MaterialTheme.colorScheme.secondary)
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        if (detail.isNotBlank()) Text(detail, style = MaterialTheme.typography.bodySmall)
    }
}

private enum class ProjectSessionMode(val label: String) {
    Projects("Projects"),
    Sessions("Sessions"),
}

private enum class SessionDetailMode(val label: String) {
    Chat("Chat"),
    Changes("Changes"),
}

@Composable
private fun connectionColor(state: ServerConnectionState): Color =
    when (state) {
        ServerConnectionState.Connected -> Color(0xFF12805C)
        ServerConnectionState.Connecting -> Color(0xFF9A6400)
        ServerConnectionState.Failed -> MaterialTheme.colorScheme.error
        ServerConnectionState.Disconnected -> MaterialTheme.colorScheme.secondary
    }

@Composable
private fun threadStatusColor(thread: CodexThread): Color =
    when {
        thread.status.isActive -> Color(0xFF12805C)
        thread.status.type == "systemError" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.7f)
    }

@Composable
private fun sessionHeaderStatusColor(thread: CodexThread): Color =
    if (thread.hasErrorStatus) MaterialTheme.colorScheme.error else Color(0xFF12805C)

private fun sessionHeaderStatusDescription(thread: CodexThread): String =
    when {
        thread.hasErrorStatus -> "Session needs attention"
        thread.status.isActive -> "Session active"
        else -> "Session ready"
    }

private val CodexThread.hasErrorStatus: Boolean
    get() {
        val normalized = status.type.lowercase()
        return normalized == "systemerror" || normalized.contains("error") || normalized.contains("fail")
    }

@Composable
private fun sectionBackground(section: ConversationSection): Color =
    when (section.kind) {
        ConversationSectionKind.User -> MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        ConversationSectionKind.Assistant -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.65f)
        ConversationSectionKind.Command, ConversationSectionKind.FileChange -> MaterialTheme.colorScheme.tertiary.copy(alpha = 0.10f)
        else -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.42f)
    }

@Composable
private fun sectionAccent(section: ConversationSection): Color =
    when (section.kind) {
        ConversationSectionKind.User -> MaterialTheme.colorScheme.primary
        ConversationSectionKind.Assistant -> MaterialTheme.colorScheme.tertiary
        ConversationSectionKind.Command, ConversationSectionKind.FileChange -> Color(0xFF9A6400)
        else -> MaterialTheme.colorScheme.secondary
    }

private fun changedLineCount(diff: String): Int =
    diff.lineSequence().count { (it.startsWith("+") && !it.startsWith("+++")) || (it.startsWith("-") && !it.startsWith("---")) }
