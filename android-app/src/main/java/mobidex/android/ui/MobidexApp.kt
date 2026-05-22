package mobidex.android.ui

import android.Manifest
import android.animation.ValueAnimator
import android.media.MediaRecorder
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
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
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
import java.io.File
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
    var showSettings by remember { mutableStateOf(false) }
    val composerDrafts = remember { mutableStateMapOf<String, AndroidComposerDraft>() }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints {
            if (maxWidth >= 960.dp) {
                WideMobidexApp(
                    state = state,
                    model = model,
                    composerDrafts = composerDrafts,
                    onAddServer = { showNewServer = true },
                    onEditServer = { showServerEditor = it },
                    onAddProject = { showProjectAdd = true },
                    onSettings = { showSettings = true },
                )
            } else {
                CompactMobidexApp(
                    state = state,
                    model = model,
                    composerDrafts = composerDrafts,
                    onAddServer = { showNewServer = true },
                    onEditServer = { showServerEditor = it },
                    onAddProject = { showProjectAdd = true },
                    onSettings = { showSettings = true },
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
    if (showSettings) {
        SettingsDialog(model = model, onDismiss = { showSettings = false })
    }
}

@Composable
private fun WideMobidexApp(
    state: MobidexUiState,
    model: AppViewModel,
    composerDrafts: MutableMap<String, AndroidComposerDraft>,
    onAddServer: () -> Unit,
    onEditServer: (ServerRecord) -> Unit,
    onAddProject: () -> Unit,
    onSettings: () -> Unit,
) {
    Row(Modifier.fillMaxSize()) {
        ServerPane(state, model, onAddServer, onEditServer, onSettings, Modifier.width(300.dp).fillMaxHeight())
        VerticalDivider(Modifier.fillMaxHeight())
        ProjectSessionPane(state, model, onAddProject, onEditServer, Modifier.width(380.dp).fillMaxHeight())
        VerticalDivider(Modifier.fillMaxHeight())
        ConversationPane(state, model, composerDrafts, Modifier.weight(1f).fillMaxHeight())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CompactMobidexApp(
    state: MobidexUiState,
    model: AppViewModel,
    composerDrafts: MutableMap<String, AndroidComposerDraft>,
    onAddServer: () -> Unit,
    onEditServer: (ServerRecord) -> Unit,
    onAddProject: () -> Unit,
    onSettings: () -> Unit,
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
                0 -> ServerPane(state, model, onAddServer, onEditServer, onSettings, Modifier.fillMaxSize(), onOpenProjects = { tab = 1 })
                1 -> ProjectSessionPane(state, model, onAddProject, onEditServer, Modifier.fillMaxSize(), onOpenDetail = { tab = 2 })
                else -> ConversationPane(state, model, composerDrafts, Modifier.fillMaxSize())
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
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenProjects: () -> Unit = {},
) {
    var serverPendingDeletion by remember { mutableStateOf<ServerRecord?>(null) }
    Column(modifier) {
        PaneHeader("Servers", Icons.Default.Storage) {
            IconButton(onClick = onSettings) {
                Icon(Icons.Default.Settings, contentDescription = "Settings")
            }
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
    var sessionsProjectID by remember(state.selectedServerID) { mutableStateOf<String?>(null) }
    var projectSearch by remember { mutableStateOf("") }
    var sessionSearch by remember { mutableStateOf("") }
    var showInactive by remember { mutableStateOf(false) }
    var showTerminal by remember { mutableStateOf(false) }
    var serverPendingDeletion by remember { mutableStateOf<ServerRecord?>(null) }
    val server = state.selectedServer
    val sessionsProject = server?.projects?.firstOrNull { it.id == sessionsProjectID }
    val connectionMode = state.connectionState == ServerConnectionState.Connecting

    Column(modifier) {
        PaneHeader(sessionsProject?.displayName ?: server?.displayName ?: "Mobidex", Icons.Default.FolderOpen) {
            if (sessionsProject != null) {
                TextButton(
                    onClick = {
                        sessionsProjectID = null
                        sessionSearch = ""
                    },
                ) {
                    Text("Projects")
                }
            }
            IconButton(
                onClick = {
                    if (sessionsProject != null) {
                        model.refreshThreads()
                    } else {
                        model.refreshProjects()
                    }
                },
                enabled = server != null && state.connectionState == ServerConnectionState.Connected,
            ) {
                Icon(Icons.Default.Refresh, contentDescription = "Refresh Projects")
            }
            if (sessionsProject == null) {
                IconButton(onClick = onAddProject, enabled = server != null) {
                    Icon(Icons.Default.Add, contentDescription = "Add Project")
                }
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
        LaunchedEffect(server.id) {
            if (state.connectionState == ServerConnectionState.Disconnected) {
                model.connectSelectedServer()
            }
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
        }

        if (showTerminal) {
            TerminalPane(
                state = state,
                model = model,
                onClose = { showTerminal = false },
                modifier = Modifier.weight(1f),
            )
        } else if (sessionsProject != null) {
            ThreadList(state, model, sessionSearch, { sessionSearch = it }, disabled = connectionMode, onOpenDetail = onOpenDetail)
        } else {
            ProjectList(
                state,
                model,
                projectSearch,
                showInactive,
                { projectSearch = it },
                { showInactive = it },
                disabled = connectionMode,
                onOpenSessions = { project ->
                    sessionsProjectID = project.id
                    model.selectProject(project.id)
                },
            )
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
private fun SettingsDialog(model: AppViewModel, onDismiss: () -> Unit) {
    var openAIKey by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        openAIKey = model.loadOpenAIAPIKeyForEditing()
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Settings") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = openAIKey,
                    onValueChange = { openAIKey = it },
                    label = { Text("OpenAI API key") },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                Text(
                    "Used for audio transcription. The key is stored on this device and sent only to OpenAI when transcribing audio.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            Button(onClick = {
                model.saveOpenAIAPIKey(openAIKey)
                onDismiss()
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
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
    onOpenSessions: (ProjectRecord) -> Unit,
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
        LazyColumn(Modifier.weight(1f, fill = true).graphicsLayer { alpha = contentAlpha }) {
            section("Projects", sections.projects) { ProjectRow(it, state, model, onOpenSessions, enabled = !contentIsLoading) }
            if (sections.isEmpty) {
                item { EmptyState(projectEmptyTitle(state, sections, search), "Add a project to get started.", Icons.Default.Folder) }
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
private fun ProjectRow(project: ProjectRecord, state: MobidexUiState, model: AppViewModel, onOpenDetail: (ProjectRecord) -> Unit, enabled: Boolean = true) {
    ListItem(
        headlineContent = { Text(project.displayName, fontWeight = FontWeight.SemiBold) },
        supportingContent = {
            Column {
                Text(project.path, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        },
        leadingContent = { Icon(Icons.Default.Folder, contentDescription = null) },
        trailingContent = {
            IconButton(onClick = { model.removeProject(project) }, enabled = enabled) {
                Icon(Icons.Default.Delete, contentDescription = "Remove Project")
            }
        },
        modifier = Modifier
            .fillMaxWidth(),
    )
    TextButton(
        onClick = {
            onOpenDetail(project)
        },
        enabled = enabled,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Open")
    }
}

@Composable
private fun ThreadList(
    state: MobidexUiState,
    model: AppViewModel,
    search: String,
    onSearchChange: (String) -> Unit,
    disabled: Boolean = false,
    onOpenDetail: () -> Unit,
) {
    val contentDisabled = disabled
    val contentAlpha = if (contentDisabled) 0.42f else 1f
    val sections = model.sessionSections(search)
    Column(Modifier.fillMaxSize()) {
        if (!state.isShowingAllSessions) {
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
                    IconButton(
                        onClick = {
                            model.startNewSession()
                            onOpenDetail()
                        },
                        enabled = state.canCreateSession && !contentDisabled,
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "New Session")
                    }
                }
            }
        }
        OutlinedTextField(
            value = search,
            onValueChange = onSearchChange,
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            placeholder = { Text("Search Sessions") },
            modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(),
            enabled = !contentDisabled,
            singleLine = true,
        )
        FilterChip(
            selected = state.showsArchivedSessions,
            onClick = { model.setShowsArchivedSessions(!state.showsArchivedSessions) },
            enabled = !contentDisabled,
            label = { Text("Show archived sessions") },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp).graphicsLayer { alpha = contentAlpha },
        )
        if (sections.isEmpty()) {
            EmptyState(
                sessionEmptyTitle(state),
                if (!state.isShowingAllSessions && state.selectedProject != null && state.connectionState == ServerConnectionState.Connected) {
                    "Start a new session for this project."
                } else {
                    "Sessions you open will show up here."
                },
                Icons.Default.Description,
            )
        } else {
            LazyColumn(Modifier.weight(1f, fill = true).graphicsLayer { alpha = contentAlpha }) {
                sections.forEach { section ->
                    item(key = "section-${section.id}") {
                        Text(section.title, modifier = Modifier.padding(16.dp, 14.dp, 16.dp, 6.dp), style = MaterialTheme.typography.labelLarge)
                    }
                    items(section.threads, key = { it.id }) { thread ->
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
}

@Composable
private fun ConversationPane(
    state: MobidexUiState,
    model: AppViewModel,
    composerDrafts: MutableMap<String, AndroidComposerDraft>,
    modifier: Modifier = Modifier,
) {
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
                SessionDetailMode.Chat -> ChatTimeline(state, model, composerDrafts, Modifier.weight(1f))
                SessionDetailMode.Changes -> ChangesView(state, model, Modifier.weight(1f))
            }
        } else if (project != null) {
            ProjectHeader(project, state, model)
            EmptyState(
                projectSessionEmptyTitle(state),
                "Start a new session for this project.",
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
        state.connectionState == ServerConnectionState.Connected -> "No Sessions Yet"
        else -> "Connect to Load Sessions"
    }

internal fun projectSessionEmptyTitle(state: MobidexUiState): String =
    when {
        state.isRefreshingSessions -> "Loading Sessions..."
        state.connectionState == ServerConnectionState.Connected -> "No Sessions Yet"
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
        IconButton(onClick = { model.startNewSession() }, enabled = state.canCreateSession) {
            Icon(Icons.Default.Add, contentDescription = "New Session")
        }
    }
    HorizontalDivider()
}

@Composable
private fun ChatTimeline(
    state: MobidexUiState,
    model: AppViewModel,
    composerDrafts: MutableMap<String, AndroidComposerDraft>,
    modifier: Modifier = Modifier,
) {
    val composerKey = state.composerDraftKey()
    var composer by remember(composerKey) { mutableStateOf(composerKey?.let { composerDrafts[it]?.text }.orEmpty()) }
    var attachmentUris by remember(composerKey) { mutableStateOf(composerKey?.let { composerDrafts[it]?.attachmentUris }.orEmpty()) }
    var composerEditGeneration by remember(composerKey) { mutableStateOf(0) }
    val currentComposerKey by rememberUpdatedState(composerKey)
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    var shouldFollowTail by remember(state.selectedThreadID) { mutableStateOf(true) }
    var isNearBottom by remember(state.selectedThreadID) { mutableStateOf(true) }
    var programmaticScrollInProgress by remember(state.selectedThreadID) { mutableStateOf(false) }
    val timelineItemCount = state.pendingApprovals.size + state.conversationSections.size
    val tailSignature = state.conversationSections.lastOrNull()?.let { "${it.id}:${it.body.length}:${it.status}" }
        ?: state.pendingApprovals.lastOrNull()?.id
    fun submitComposerInput(queueWhenActive: Boolean) {
        val sentText = composer
        val sentAttachments = attachmentUris
        val submittedComposerKey = composerKey
        val submittedEditGeneration = composerEditGeneration
        composer = ""
        attachmentUris = emptyList()
        submittedComposerKey?.let { composerDrafts.remove(it) }
        model.sendComposerInput(sentText, sentAttachments, queueWhenActive = queueWhenActive) { sent ->
            if (sent || composerEditGeneration != submittedEditGeneration || submittedComposerKey != currentComposerKey) return@sendComposerInput
            composer = sentText
            attachmentUris = sentAttachments
            submittedComposerKey?.let {
                composerDrafts[it] = AndroidComposerDraft(sentText, sentAttachments)
            }
        }
    }

    LaunchedEffect(listState, state.selectedThreadID, timelineItemCount) {
        snapshotFlow {
            Triple(
                listState.firstVisibleItemIndex,
                listState.firstVisibleItemScrollOffset,
                listState.isScrollInProgress,
            )
        }.collect {
            val near = listState.isNearTimelineBottom()
            isNearBottom = near
            if (near) {
                shouldFollowTail = true
            } else if (!programmaticScrollInProgress) {
                shouldFollowTail = false
            }
        }
    }

    LaunchedEffect(state.selectedThreadID, timelineItemCount, tailSignature, shouldFollowTail) {
        if (!shouldFollowTail || timelineItemCount == 0) return@LaunchedEffect
        programmaticScrollInProgress = true
        try {
            listState.animateScrollToItem(timelineItemCount - 1)
            isNearBottom = true
        } finally {
            programmaticScrollInProgress = false
        }
    }

    Column(modifier) {
        Box(Modifier.weight(1f)) {
            LazyColumn(Modifier.fillMaxSize(), state = listState, reverseLayout = false) {
                items(state.pendingApprovals, key = { it.id }) { approval ->
                    ApprovalCard(approval, model)
                }
                items(state.conversationSections, key = { it.id }) { section ->
                    ConversationSectionRow(section)
                }
            }
            if (!isNearBottom && timelineItemCount > 0) {
                FloatingActionButton(
                    onClick = {
                        shouldFollowTail = true
                        isNearBottom = true
                        coroutineScope.launch {
                            programmaticScrollInProgress = true
                            try {
                                listState.animateScrollToItem(timelineItemCount - 1)
                            } finally {
                                programmaticScrollInProgress = false
                            }
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(18.dp)
                        .size(44.dp),
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary,
                ) {
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Scroll to latest message")
                }
            }
        }
        Composer(
            value = composer,
            onValueChange = {
                composer = it
                composerEditGeneration += 1
                composerKey?.let { key ->
                    composerDrafts.updateComposerDraft(key, composer, attachmentUris)
                }
            },
            attachmentUris = attachmentUris,
            onAttachmentUrisChange = {
                attachmentUris = it
                composerEditGeneration += 1
                composerKey?.let { key ->
                    composerDrafts.updateComposerDraft(key, composer, attachmentUris)
                }
            },
            state = state,
            model = model,
            onSend = {
                submitComposerInput(queueWhenActive = false)
            },
            onSendFollowUp = {
                submitComposerInput(queueWhenActive = true)
            },
            onTranscript = { transcript ->
                val separator = if (composer.trim().isEmpty()) "" else "\n"
                composer += "$separator$transcript"
                composerEditGeneration += 1
                composerKey?.let { key ->
                    composerDrafts.updateComposerDraft(key, composer, attachmentUris)
                }
            },
        )
    }
}

private data class AndroidComposerDraft(
    val text: String,
    val attachmentUris: List<Uri>,
)

private fun MobidexUiState.composerDraftKey(): String? {
    val serverID = selectedServerID ?: return null
    selectedThreadID?.let { return "server:$serverID|thread:$it" }
    selectedProjectID?.let { return "server:$serverID|project:$it" }
    return "server:$serverID|new"
}

private fun MutableMap<String, AndroidComposerDraft>.updateComposerDraft(
    key: String,
    text: String,
    attachmentUris: List<Uri>,
) {
    if (text.isEmpty() && attachmentUris.isEmpty()) {
        remove(key)
    } else {
        this[key] = AndroidComposerDraft(text, attachmentUris)
    }
}

private fun LazyListState.isNearTimelineBottom(bufferItems: Int = 2, bufferPixels: Int = 96): Boolean {
    val info = layoutInfo
    if (info.totalItemsCount == 0) return true
    val lastVisible = info.visibleItemsInfo.lastOrNull() ?: return false
    val lastIndex = info.totalItemsCount - 1
    if (lastVisible.index < lastIndex) {
        return lastVisible.index >= lastIndex - bufferItems
    }
    return lastVisible.offset + lastVisible.size <= info.viewportEndOffset + bufferPixels
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
    onTranscript: (String) -> Unit,
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var showAttachOptions by remember { mutableStateOf(false) }
    var showEffort by remember { mutableStateOf(false) }
    var showAccess by remember { mutableStateOf(false) }
    var showSendOptions by remember { mutableStateOf(false) }
    var audioRecorder by remember { mutableStateOf<MediaRecorder?>(null) }
    var audioFile by remember { mutableStateOf<File?>(null) }
    var isRecordingAudio by remember { mutableStateOf(false) }
    var isTranscribingAudio by remember { mutableStateOf(false) }
    var audioError by remember { mutableStateOf<String?>(null) }
    val sendEnabled = !isTranscribingAudio && (value.trim().isNotEmpty() || attachmentUris.isNotEmpty()) && state.canSendMessage
    fun stopAndTranscribeAudio() {
        val file = audioFile
        val recorder = audioRecorder
        audioRecorder = null
        audioFile = null
        isRecordingAudio = false
        audioError = null
        val stopped = runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        if (stopped.isFailure) {
            runCatching { file?.delete() }
            audioError = stopped.exceptionOrNull()?.message ?: "Could not finish audio recording."
        } else if (file != null) {
            isTranscribingAudio = true
            coroutineScope.launch {
                try {
                    runCatching { model.transcribeAudio(file) }
                        .onSuccess(onTranscript)
                        .onFailure { error -> audioError = error.message ?: "Could not transcribe audio." }
                } finally {
                    withContext(NonCancellable) {
                        runCatching { file.delete() }
                    }
                    isTranscribingAudio = false
                }
            }
        }
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) {
            audioError = "Allow microphone access in Settings to record audio."
            return@rememberLauncherForActivityResult
        }
        audioError = null
        var startedFile: File? = null
        var startedRecorder: MediaRecorder? = null
        runCatching {
            val file = File(context.cacheDir, "mobidex-audio-${System.currentTimeMillis()}.m4a")
            val recorder = MediaRecorder(context).apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44_100)
                setAudioChannels(1)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            startedFile = file
            startedRecorder = recorder
            audioFile = file
            audioRecorder = recorder
            isRecordingAudio = true
        }.onFailure { error ->
            runCatching { startedRecorder?.release() }
            runCatching { startedFile?.delete() }
            audioError = error.message ?: "Could not start audio recording."
        }
    }
    fun requestAudioRecording() {
        coroutineScope.launch {
            if (!model.refreshOpenAIAPIKeyState()) {
                audioError = "Add an OpenAI API key in Settings before recording audio."
                return@launch
            }
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
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
            enabled = !isTranscribingAudio,
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
        if (isRecordingAudio) {
            RecordingIndicator(onStop = { stopAndTranscribeAudio() })
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box {
                IconButton(onClick = { showAttachOptions = true }) {
                    Icon(Icons.Default.Add, contentDescription = "Attach")
                }
                DropdownMenu(expanded = showAttachOptions, onDismissRequest = { showAttachOptions = false }) {
                    DropdownMenuItem(
                        text = { Text(if (isRecordingAudio) "Stop Recording" else "Record Audio") },
                        onClick = {
                            showAttachOptions = false
                            if (isRecordingAudio) {
                                stopAndTranscribeAudio()
                            } else {
                                requestAudioRecording()
                            }
                        },
                        leadingIcon = { Icon(if (isRecordingAudio) Icons.Default.Stop else Icons.Default.Mic, contentDescription = null) },
                        enabled = !isTranscribingAudio,
                    )
                    DropdownMenuItem(
                        text = { Text("Photo") },
                        onClick = {
                            showAttachOptions = false
                            photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                        leadingIcon = { Icon(Icons.Default.Photo, contentDescription = null) },
                    )
                    DropdownMenuItem(
                        text = { Text("File") },
                        onClick = {
                            showAttachOptions = false
                            filePicker.launch(arrayOf("*/*"))
                        },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.InsertDriveFile, contentDescription = null) },
                    )
                }
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
        audioError?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun RecordingIndicator(onStop: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
        shape = MaterialTheme.shapes.medium,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.error),
            )
            Text("Recording", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Button(
                onClick = onStop,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError,
                ),
            ) {
                Icon(Icons.Default.Stop, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Stop")
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
    val state by model.state.collectAsState()
    var path by remember { mutableStateOf("") }
    var discoverySearch by remember { mutableStateOf("") }
    var showingBrowser by remember { mutableStateOf(false) }
    val discoveredProjects = state.selectedServer?.projects.orEmpty()
        .filter { it.discovered && !it.isAdded }
        .filter {
            val query = discoverySearch.trim()
            query.isEmpty() || it.displayName.contains(query, ignoreCase = true) || it.path.contains(query, ignoreCase = true)
        }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Project") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = path,
                        onValueChange = { path = it },
                        label = { Text("Remote Path") },
                        placeholder = { Text("~/project") },
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { showingBrowser = true }) {
                        Icon(Icons.Default.Folder, contentDescription = "Browse Remote Folders")
                    }
                }
                OutlinedButton(onClick = { model.refreshProjects() }, enabled = !state.isDiscoveringProjects) {
                    Icon(Icons.Default.Search, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("Discover Projects")
                }
                OutlinedTextField(
                    value = discoverySearch,
                    onValueChange = { discoverySearch = it },
                    label = { Text("Search discovered projects") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                if (state.isDiscoveringProjects) {
                    LoadingListStatusRow("Discovering projects...")
                }
                LazyColumn(Modifier.height(220.dp)) {
                    if (discoveredProjects.isEmpty()) {
                        item { EmptyState("No Discovered Projects", "", Icons.Default.Folder, Modifier.height(180.dp)) }
                    }
                    items(discoveredProjects, key = { it.id }) { project ->
                        ListItem(
                            headlineContent = { Text(project.displayName, fontWeight = FontWeight.SemiBold) },
                            supportingContent = { Text(project.path, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            leadingContent = { Icon(Icons.Default.Folder, contentDescription = null) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        TextButton(
                            onClick = {
                                onAdd(project.path)
                                onDismiss()
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text("Add") }
                        HorizontalDivider()
                    }
                }
            }
        },
        confirmButton = { Button(onClick = { onAdd(path) }) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
    if (showingBrowser) {
        RemoteDirectoryBrowserDialog(
            model = model,
            initialPath = path.trim().ifEmpty { "~" },
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
    var folderName by remember { mutableStateOf("") }
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

    fun createFolder() {
        val name = folderName.trim()
        if (name.isEmpty()) return
        scope.launch {
            isLoading = true
            errorMessage = null
            runCatching { model.createRemoteDirectory(currentPath, name) }
                .onSuccess { listing ->
                    folderName = ""
                    load(listing.path)
                }
                .onFailure { error ->
                    errorMessage = error.message ?: "Could not create folder."
                    isLoading = false
                }
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
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = folderName,
                        onValueChange = { folderName = it },
                        label = { Text("New Folder") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                    IconButton(onClick = { createFolder() }, enabled = folderName.trim().isNotEmpty() && !isLoading) {
                        Icon(Icons.Default.Add, contentDescription = "Create Folder")
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
