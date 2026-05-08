package mobidex.android.ui

import android.animation.ValueAnimator
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.foundation.text.KeyboardOptions
import mobidex.android.AppViewModel
import mobidex.android.MobidexUiState
import mobidex.android.model.CodexThread
import mobidex.android.model.PendingApproval
import mobidex.android.model.ProjectRecord
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.ServerRecord
import mobidex.shared.CodexAccessMode
import mobidex.shared.CodexReasoningEffortOption
import mobidex.shared.ConversationSection
import mobidex.shared.ConversationSectionKind
import mobidex.shared.GitDiffSnapshot

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
        ProjectSessionPane(state, model, onAddProject, Modifier.width(380.dp).fillMaxHeight())
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
                0 -> ServerPane(state, model, onAddServer, onEditServer, Modifier.fillMaxSize())
                1 -> ProjectSessionPane(state, model, onAddProject, Modifier.fillMaxSize(), onOpenDetail = { tab = 2 })
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
) {
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
                                IconButton(onClick = { model.deleteServer(server) }) {
                                    Icon(Icons.Default.Delete, contentDescription = "Delete Server")
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (server.id == state.selectedServerID) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else Color.Transparent),
                    )
                    TextButton(
                        onClick = { model.selectServer(server.id) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                    Text("Select")
                }
                    HorizontalDivider()
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProjectSessionPane(
    state: MobidexUiState,
    model: AppViewModel,
    onAddProject: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenDetail: () -> Unit = {},
) {
    var mode by remember { mutableStateOf(ProjectSessionMode.Projects) }
    var search by remember { mutableStateOf("") }
    var showInactive by remember { mutableStateOf(false) }
    val server = state.selectedServer

    Column(modifier) {
        PaneHeader(server?.displayName ?: "Mobidex", Icons.Default.FolderOpen) {
            IconButton(onClick = { model.refreshProjects() }, enabled = server != null && state.connectionState == ServerConnectionState.Connected) {
                Icon(Icons.Default.Refresh, contentDescription = "Refresh Projects")
            }
            IconButton(onClick = onAddProject, enabled = server != null) {
                Icon(Icons.Default.Add, contentDescription = "Add Project")
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
                OutlinedButton(onClick = { model.testSelectedConnection() }) {
                    Icon(Icons.Default.Check, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("Test")
                }
                Button(onClick = { model.connectSelectedServer() }) {
                    Text(if (state.connectionState == ServerConnectionState.Connected) "Reconnect Codex" else "Connect Codex")
                }
            }
            SecondaryTabRow(selectedTabIndex = mode.ordinal) {
                ProjectSessionMode.entries.forEach { item ->
                    Tab(selected = mode == item, onClick = { mode = item }, text = { Text(item.label) })
                }
            }
        }

        when (mode) {
            ProjectSessionMode.Projects -> ProjectList(state, model, search, showInactive, { search = it }, { showInactive = it }, onOpenDetail)
            ProjectSessionMode.Sessions -> ThreadList(state, model, onOpenDetail)
        }
    }
}

@Composable
private fun ProjectList(
    state: MobidexUiState,
    model: AppViewModel,
    search: String,
    showInactive: Boolean,
    onSearchChange: (String) -> Unit,
    onShowInactiveChange: (Boolean) -> Unit,
    onOpenDetail: () -> Unit,
) {
    val projects = state.selectedServer?.projects.orEmpty()
    val filtered = projects
        .filter { search.isBlank() || it.displayName.contains(search, true) || it.path.contains(search, true) }
        .sortedWith(
            compareByDescending<ProjectRecord> { it.isFavorite }
                .thenByDescending { it.activeChatCount }
                .thenByDescending { it.discoveredSessionCount }
                .thenBy { it.displayName.lowercase() }
        )
    val favorites = filtered.filter { it.isFavorite }
    val discovered = filtered.filter { it.discovered && !it.isFavorite && (it.activeChatCount > 0 || it.discoveredSessionCount > 0 || showInactive || search.isNotBlank()) }
    val added = filtered.filter { !it.discovered && !it.isFavorite }
    val showInactiveToggle = projects.any { it.discovered && !it.isFavorite && it.discoveredSessionCount == 0 && it.activeChatCount == 0 }

    Column {
        OutlinedTextField(
            value = search,
            onValueChange = onSearchChange,
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            placeholder = { Text("Search Projects") },
            modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(),
            singleLine = true,
        )
        if (showInactiveToggle) {
            FilterChip(
                selected = showInactive,
                onClick = { onShowInactiveChange(!showInactive) },
                label = { Text("Show inactive discovered projects") },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
        LazyColumn(Modifier.weight(1f, fill = true)) {
            section("Favorites", favorites) { ProjectRow(it, state, model, onOpenDetail) }
            section("Discovered", discovered) { ProjectRow(it, state, model, onOpenDetail) }
            section("Added", added) { ProjectRow(it, state, model, onOpenDetail) }
            if (favorites.isEmpty() && discovered.isEmpty() && added.isEmpty()) {
                item { EmptyState("No Projects", "Connect or add a project path.", Icons.Default.Folder) }
            }
        }
    }
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
private fun ProjectRow(project: ProjectRecord, state: MobidexUiState, model: AppViewModel, onOpenDetail: () -> Unit) {
    ListItem(
        headlineContent = { Text(project.displayName, fontWeight = FontWeight.SemiBold) },
        supportingContent = {
            Column {
                Text(project.path, maxLines = 1, overflow = TextOverflow.Ellipsis)
                projectSupportingLabels(project).forEach { label ->
                    Text(label, style = MaterialTheme.typography.labelSmall)
                }
            }
        },
        leadingContent = { Icon(if (project.id == state.selectedProjectID) Icons.Default.FolderOpen else Icons.Default.Folder, contentDescription = null) },
        trailingContent = {
            Row {
                IconButton(onClick = { model.setProjectFavorite(project, !project.isFavorite) }) {
                    Icon(if (project.isFavorite) Icons.Default.Star else Icons.Default.StarBorder, contentDescription = "Favorite")
                }
                if (!project.discovered) {
                    IconButton(onClick = { model.removeProject(project) }) {
                        Icon(Icons.Default.Delete, contentDescription = "Remove Project")
                    }
                }
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .background(if (project.id == state.selectedProjectID) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else Color.Transparent),
    )
    TextButton(
        onClick = {
            model.selectProject(project.id)
            onOpenDetail()
        },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Open")
    }
}

internal fun projectSupportingLabels(project: ProjectRecord): List<String> {
    if (!project.discovered) return emptyList()
    return buildList {
        if (project.activeChatCount > 0) {
            add(if (project.activeChatCount == 1) "1 loaded in app-server" else "${project.activeChatCount} loaded in app-server")
        }
        if (project.discoveredSessionCount > 0) {
            add(if (project.discoveredSessionCount == 1) "1 discovered session" else "${project.discoveredSessionCount} discovered sessions")
        }
        if (project.activeChatCount == 0 && project.discoveredSessionCount == 0) {
            add("No loaded sessions")
        }
        if (project.sessionPaths.size > 1) {
            add("${project.sessionPaths.size} worktree paths grouped")
        }
    }
}

@Composable
private fun ThreadList(state: MobidexUiState, model: AppViewModel, onOpenDetail: () -> Unit) {
    if (state.threads.isEmpty()) {
        EmptyState(
            if (state.connectionState == ServerConnectionState.Connected) "No Sessions" else "Connect to Load Sessions",
            "Sessions from CLI, VS Code, exec, and app-server sources appear here.",
            Icons.Default.Description,
        )
    } else {
        LazyColumn {
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
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Open") }
                HorizontalDivider()
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
                if (state.canCreateSession) "No Sessions" else "Connect to Create a Session",
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
            state = state,
            model = model,
            onSend = {
                model.sendComposerText(composer)
                composer = ""
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
private fun Composer(
    value: String,
    onValueChange: (String) -> Unit,
    state: MobidexUiState,
    model: AppViewModel,
    onSend: () -> Unit,
) {
    var showEffort by remember { mutableStateOf(false) }
    var showAccess by remember { mutableStateOf(false) }
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
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box {
                AssistChip(onClick = { showAccess = true }, label = { Text(state.selectedAccessMode.label) })
                DropdownMenu(expanded = showAccess, onDismissRequest = { showAccess = false }) {
                    CodexAccessMode.entries.forEach { mode ->
                        DropdownMenuItem(text = { Text(mode.label) }, onClick = {
                            model.setAccessMode(mode)
                            showAccess = false
                        })
                    }
                }
            }
            Box {
                AssistChip(onClick = { showEffort = true }, label = { Text("5.5 ${state.selectedReasoningEffort.label}") })
                DropdownMenu(expanded = showEffort, onDismissRequest = { showEffort = false }) {
                    CodexReasoningEffortOption.entries.forEach { effort ->
                        DropdownMenuItem(text = { Text(effort.label) }, onClick = {
                            model.setReasoningEffort(effort)
                            showEffort = false
                        })
                    }
                }
            }
            if (state.tokenUsagePercent != null) Text("${state.tokenUsagePercent}%", style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onSend, enabled = value.trim().isNotEmpty() && state.canSendMessage) {
                Icon(Icons.Default.ArrowUpward, contentDescription = "Send")
            }
        }
    }
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
    var codexPath by remember(original?.id) { mutableStateOf(original?.codexPath ?: "codex") }
    var shellRc by remember(original?.id) { mutableStateOf(original?.targetShellRCFile ?: "\$HOME/.zshrc") }
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
                    connectAfterSave = original == null,
                )
                onDismiss()
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ProjectAddDialog(onDismiss: () -> Unit, onAdd: (String) -> Unit) {
    var path by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Project") },
        text = {
            OutlinedTextField(
                value = path,
                onValueChange = { path = it },
                label = { Text("Remote Path") },
                placeholder = { Text("/home/user/project") },
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = { Button(onClick = { onAdd(path) }) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
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
    if (!state.statusMessage.isNullOrBlank()) Text(state.statusMessage, style = MaterialTheme.typography.labelSmall)
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
