import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var model: AppViewModel
    @State private var showingAddServer = false
    @State private var showingSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            ServerSidebarView(
                showingAddServer: $showingAddServer,
                showingSettings: $showingSettings,
                columnVisibility: $columnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            )
                .navigationTitle("Servers")
        } content: {
            ProjectSessionListView(
                columnVisibility: $columnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            )
        } detail: {
            ConversationView()
        }
        .sheet(isPresented: $showingAddServer) {
            ServerEditorView(server: nil)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .alert(item: $model.statusAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            if newValue != .compact {
                columnVisibility = .automatic
            } else {
                promoteSmokeDetailIfNeeded()
            }
        }
        .onChange(of: model.selectedThreadID) { _, _ in
            promoteSmokeDetailIfNeeded()
        }
    }

    private func promoteSmokeDetailIfNeeded() {
        guard ProcessInfo.processInfo.environment["MOBIDEX_SMOKE_PROMOTE_DETAIL"] == "1",
              model.selectedThreadID != nil
        else {
            return
        }
        columnVisibility = .detailOnly
        preferredCompactColumn = .detail
    }
}

struct ServerSidebarView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var showingAddServer: Bool
    @Binding var showingSettings: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    @State private var editingServer: ServerRecord?

    var body: some View {
        List {
            ForEach(model.servers) { server in
                Button {
                    Task {
                        if await model.switchServerFromSidebar(server.id) {
                            promoteContentIfCompact()
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(server.displayName)
                                .font(.headline)
                            if model.switchingServerID == server.id {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        Text(server.endpointLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("serverRow")
                .contextMenu {
                    Button {
                        editingServer = server
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task { await model.deleteServer(server) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .overlay {
            if model.servers.isEmpty {
                ContentUnavailableView("No Servers", systemImage: "server.rack", description: Text("Add an SSH server to begin."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(item: $editingServer) { server in
            ServerEditorView(server: server)
        }
    }

    private func promoteContentIfCompact() {
        if horizontalSizeClass == .compact {
            preferredCompactColumn = .content
            columnVisibility = .doubleColumn
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppViewModel
    @State private var openAIAPIKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("OpenAI API key", text: $openAIAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if model.hasOpenAIAPIKey {
                        Text("An OpenAI key is stored in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("Used for audio transcription. The key is stored on this device and sent only to OpenAI when transcribing audio.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveOpenAIAPIKey(openAIAPIKey)
                        dismiss()
                    }
                }
            }
            .onAppear {
                openAIAPIKey = model.loadOpenAIAPIKeyForEditing()
            }
        }
    }
}

struct ProjectSessionListView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    @State private var showingProjectAdd = false
    @State private var sessionsProjectID: UUID?
    @State private var projectSearchText = ""
    @State private var sessionSearchText = ""
    @State private var isSessionRefreshRequested = false
    @State private var showingTerminal = false
    @State private var showingDiagnostics = false
    @State private var editingServer: ServerRecord?
    @State private var serverPendingDeletion: ServerRecord?
    @State private var isDeleteServerConfirmationPresented = false

    var body: some View {
        Group {
            if let server = model.selectedServer {
                List {
                    serverControlsSection(server)

                    if let sessionsProjectID, let project = server.projects.first(where: { $0.id == sessionsProjectID }) {
                        let sessionSections = filteredSessionSections(model.sessionSections)
                        SessionsContent(
                            selectedProject: project,
                            showsArchivedSessions: $model.showsArchivedSessions,
                            sections: sessionSections,
                            selectedThreadID: model.selectedThreadID,
                            serverContentDisabled: serverContentDisabled,
                            contentOpacity: contentOpacity,
                            onArchive: { thread in
                                Task { await model.archiveThread(thread) }
                            },
                            onUnarchive: { thread in
                                Task { await model.unarchiveThread(thread) }
                            },
                            onOpen: { thread in
                                promoteDetailIfCompact()
                                Task { await model.openThread(thread) }
                            }
                        )

                        if sessionSections.isEmpty {
                            Section {
                                Group {
                                    if let sessionsUnavailableDescription {
                                        ContentUnavailableView(
                                            sessionsUnavailableTitle,
                                            systemImage: "bubble.left.and.bubble.right",
                                            description: Text(sessionsUnavailableDescription)
                                        )
                                    } else {
                                        ContentUnavailableView(
                                            sessionsUnavailableTitle,
                                            systemImage: "bubble.left.and.bubble.right"
                                        )
                                    }
                                }
                                    .frame(maxWidth: .infinity, minHeight: 260)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    } else {
                        LoadingSection(isLoading: contentIsLoading, title: "Loading projects...")
                        let sections = projectSections(from: server.projects)
                        ProjectSectionsContent(
                            sections: sections,
                            unavailableTitle: projectsUnavailableTitle(server: server, sections: sections),
                            serverContentDisabled: serverContentDisabled,
                            contentOpacity: contentOpacity,
                            onOpenProject: { project in
                                sessionsProjectID = project.id
                                model.selectProject(project.id)
                                isSessionRefreshRequested = true
                                Task {
                                    await model.refreshThreadsIfNeeded()
                                    isSessionRefreshRequested = false
                                }
                            }
                        )
                    }
                }
                .sheet(isPresented: $showingTerminal) {
                    TerminalView()
                        .environmentObject(model)
                }
                .sheet(isPresented: $showingDiagnostics) {
                    ConnectionDiagnosticsView()
                        .environmentObject(model)
                }
                .task(id: server.id) {
                    await model.ensureSelectedServerConnected()
                }
                .searchable(text: searchTextBinding, placement: .navigationBarDrawer(displayMode: .automatic), prompt: searchPrompt)
                .onChange(of: model.showsArchivedSessions) { _, _ in
                    handleArchivedSessionsChange()
                }
                .onChange(of: server.id) { _, _ in
                    sessionsProjectID = nil
                }
                .toolbar {
                    SelectedServerToolbar(
                        server: server,
                        showingProjectSessions: sessionsProjectID != nil,
                        disabled: serverControlsDisabled,
                        onBackToProjects: {
                            sessionsProjectID = nil
                            sessionSearchText = ""
                        },
                        canCreateSession: model.canChooseNewSessionLocation,
                        onStartInNewWorktree: {
                            Task { await startNewSessionAndPromote(location: .codexWorktree) }
                        },
                        onStartInProjectDirectory: {
                            Task { await startNewSessionAndPromote(location: .projectDirectory) }
                        },
                        showingProjectAdd: $showingProjectAdd,
                        showingTerminal: $showingTerminal,
                        showingDiagnostics: $showingDiagnostics,
                        editingServer: $editingServer,
                        serverPendingDeletion: $serverPendingDeletion,
                        isDeleteServerConfirmationPresented: $isDeleteServerConfirmationPresented
                    )
                }
                .sheet(isPresented: $showingProjectAdd) {
                    ProjectAddView()
                }
                .sheet(item: $editingServer) { server in
                    ServerEditorView(server: server)
                }
                .confirmationDialog(
                    "Delete Server?",
                    isPresented: $isDeleteServerConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("Delete Server", role: .destructive) {
                        confirmDeleteServer()
                    }
                    Button("Cancel", role: .cancel) {
                        serverPendingDeletion = nil
                    }
                }
            } else {
                ContentUnavailableView("Select a Server", systemImage: "server.rack")
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarBackButtonHidden(sessionsProjectID != nil)
        .simultaneousGesture(edgeBackToProjectsGesture)
    }

    private var edgeBackToProjectsGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .global)
            .onEnded { value in
                guard sessionsProjectID != nil,
                      value.startLocation.x <= 24,
                      value.translation.width >= 80,
                      abs(value.translation.height) <= 60
                else {
                    return
                }
                withAnimation {
                    sessionsProjectID = nil
                    sessionSearchText = ""
                }
            }
    }

    private func handleArchivedSessionsChange() {
        guard model.isAppServerConnected, sessionsProjectID != nil else { return }
        isSessionRefreshRequested = true
        Task {
            await model.refreshThreads()
            isSessionRefreshRequested = false
        }
    }

    private func deleteServer(_ server: ServerRecord) {
        Task { await model.deleteServer(server) }
    }

    private func confirmDeleteServer() {
        guard let server = serverPendingDeletion else { return }
        serverPendingDeletion = nil
        deleteServer(server)
    }

    @ViewBuilder
    private func serverControlsSection(_ server: ServerRecord) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.endpointLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.connectionState.label)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if let reconnectStatus = model.appServerReconnectStatus {
                        Text(reconnectStatus.label)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if model.connectionState == .connecting {
                    ProgressView()
                }
            }
        }
    }

    private var serverControlsDisabled: Bool {
        model.connectionState == .connecting
    }

    private var serverContentDisabled: Bool {
        contentIsLoading
    }

    private var contentIsLoading: Bool {
        model.isDiscoveringProjects
    }

    private var contentOpacity: Double {
        serverContentDisabled ? 0.42 : 1
    }

    private var statusColor: Color {
        switch model.connectionState {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }

    private var sessionsUnavailableTitle: String {
        if isSessionRefreshRequested || model.isRefreshingSessions {
            return "Loading Sessions..."
        }
        return model.connectionState == .connected ? "No Sessions Yet" : "Connect to Load Sessions"
    }

    private var sessionsUnavailableDescription: String? {
        if isSessionRefreshRequested || model.isRefreshingSessions {
            return nil
        }
        if model.selectedProject != nil, model.connectionState == .connected {
            return "Start a new session for this project."
        }
        return "Sessions you open will show up here."
    }

    private func promoteDetailIfCompact() {
        if horizontalSizeClass == .compact {
            preferredCompactColumn = .detail
            columnVisibility = .detailOnly
        }
    }

    @MainActor
    private func startNewSessionAndPromote(location: NewSessionLocation) async {
        let createdThreadID = await model.startNewSession(location: location)
        guard createdThreadID != nil, model.selectedThreadID == createdThreadID else {
            return
        }
        promoteDetailIfCompact()
    }

    private var trimmedProjectSearch: String {
        projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSessionSearch: String {
        sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPrompt: String {
        sessionsProjectID == nil ? "Search Projects" : "Search Sessions"
    }

    private var navigationTitle: String {
        guard let server = model.selectedServer else { return "Mobidex" }
        guard let sessionsProjectID,
              let project = server.projects.first(where: { $0.id == sessionsProjectID })
        else {
            return server.displayName
        }
        return "\(project.displayName) Sessions"
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { sessionsProjectID == nil ? projectSearchText : sessionSearchText },
            set: { value in
                if sessionsProjectID == nil {
                    projectSearchText = value
                } else {
                    sessionSearchText = value
                }
            }
        )
    }

    private func projectSections(from projects: [ProjectRecord]) -> ProjectListSections {
        ProjectListSections(
            projects: projects.filter(\.isAddedToProjectList),
            searchText: trimmedProjectSearch,
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )
    }

    private func filteredSessionSections(_ sections: [SessionListSection]) -> [SessionListSection] {
        let query = trimmedSessionSearch
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            let threads = section.threads.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                    $0.cwd.localizedCaseInsensitiveContains(query)
            }
            guard !threads.isEmpty else { return nil }
            return SessionListSection(id: section.id, title: section.title, threads: threads)
        }
    }

    private func projectsUnavailableTitle(server: ServerRecord, sections: ProjectListSections) -> String {
        if !trimmedProjectSearch.isEmpty {
            return "No Matching Projects"
        }
        if model.isDiscoveringProjects {
            return "Loading Projects"
        }
        return "No Projects"
    }

}

private struct LoadingSection: View {
    let isLoading: Bool
    let title: String

    @ViewBuilder
    var body: some View {
        if isLoading {
            Section {
                LoadingListStatusRow(title: title)
                    .listRowSeparator(.hidden)
            }
        }
    }
}

private struct ProjectSectionsContent: View {
    let sections: ProjectListSections
    let unavailableTitle: String
    let serverContentDisabled: Bool
    let contentOpacity: Double
    let onOpenProject: (ProjectRecord) -> Void

    @ViewBuilder
    var body: some View {
        ProjectListSection(
            title: "Projects",
            projects: sections.projects,
            serverContentDisabled: serverContentDisabled,
            contentOpacity: contentOpacity,
            onOpenProject: onOpenProject
        )

        if sections.isEmpty {
            Section {
                ContentUnavailableView(
                    unavailableTitle,
                    systemImage: "folder",
                    description: Text("Add a project to get started.")
                )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .listRowSeparator(.hidden)
            }
        }
    }
}

private struct ProjectListSection: View {
    let title: String
    let projects: [ProjectRecord]
    let serverContentDisabled: Bool
    let contentOpacity: Double
    let onOpenProject: (ProjectRecord) -> Void

    @ViewBuilder
    var body: some View {
        if !projects.isEmpty {
            Section {
                ForEach(projects) { project in
                    ProjectActionRow(
                        project: project,
                        onOpenProject: onOpenProject
                    )
                }
            }
            .disabled(serverContentDisabled)
            .opacity(contentOpacity)
        }
    }
}

private struct ProjectActionRow: View {
    @EnvironmentObject private var model: AppViewModel
    let project: ProjectRecord
    let onOpenProject: (ProjectRecord) -> Void

    var body: some View {
        Button(action: openProject) {
            ProjectRow(project: project)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectRow")
        .swipeActions {
            Button(role: .destructive) {
                model.removeProject(project)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }

    private func openProject() {
        onOpenProject(project)
    }
}

private struct SelectedServerMenu: View {
    let server: ServerRecord
    let disabled: Bool
    @Binding var showingTerminal: Bool
    @Binding var showingDiagnostics: Bool
    @Binding var editingServer: ServerRecord?
    @Binding var serverPendingDeletion: ServerRecord?
    @Binding var isDeleteServerConfirmationPresented: Bool

    var body: some View {
        Menu {
            Button {
                showingTerminal = true
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .disabled(disabled)

            Button {
                showingDiagnostics = true
            } label: {
                Label("Doctor", systemImage: "stethoscope")
            }
            .disabled(disabled)

            Button {
                editingServer = server
            } label: {
                Label("Edit Settings", systemImage: "pencil")
            }

            Button(role: .destructive) {
                serverPendingDeletion = server
                isDeleteServerConfirmationPresented = true
            } label: {
                Label("Delete Server", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Server Actions")
    }
}

private struct SelectedServerToolbar: ToolbarContent {
    let server: ServerRecord
    let showingProjectSessions: Bool
    let disabled: Bool
    let onBackToProjects: () -> Void
    let canCreateSession: Bool
    let onStartInNewWorktree: () -> Void
    let onStartInProjectDirectory: () -> Void
    @Binding var showingProjectAdd: Bool
    @Binding var showingTerminal: Bool
    @Binding var showingDiagnostics: Bool
    @Binding var editingServer: ServerRecord?
    @Binding var serverPendingDeletion: ServerRecord?
    @Binding var isDeleteServerConfirmationPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if showingProjectSessions {
                Button(action: onBackToProjects) {
                    Label("Projects", systemImage: "chevron.left")
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            RefreshServerButton(showingProjectSessions: showingProjectSessions, disabled: disabled)
            if !showingProjectSessions {
                AddProjectButton(showingProjectAdd: $showingProjectAdd, disabled: disabled)
            } else {
                NewSessionButton(
                    canCreateSession: canCreateSession,
                    onStartInNewWorktree: onStartInNewWorktree,
                    onStartInProjectDirectory: onStartInProjectDirectory
                )
            }
            SelectedServerMenu(
                server: server,
                disabled: disabled,
                showingTerminal: $showingTerminal,
                showingDiagnostics: $showingDiagnostics,
                editingServer: $editingServer,
                serverPendingDeletion: $serverPendingDeletion,
                isDeleteServerConfirmationPresented: $isDeleteServerConfirmationPresented
            )
        }
    }
}

private struct RefreshServerButton: View {
    @EnvironmentObject private var model: AppViewModel
    let showingProjectSessions: Bool
    let disabled: Bool

    var body: some View {
        Button {
            Task { await refreshServer() }
        } label: {
            if isRefreshingCurrentContent {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(disabled || isRefreshingCurrentContent)
        .accessibilityLabel(isRefreshingCurrentContent ? "Refreshing" : model.isAppServerConnected ? "Refresh" : "Connect")
        .accessibilityIdentifier("refreshServerButton")
    }

    private var isRefreshingCurrentContent: Bool {
        showingProjectSessions ? model.isRefreshingSessions : model.isDiscoveringProjects
    }

    private func refreshServer() async {
        guard model.isAppServerConnected else {
            await model.connectSelectedServer(syncActiveChatCounts: true)
            return
        }
        if showingProjectSessions {
            await model.refreshThreads()
        } else {
            await model.refreshProjects()
        }
    }
}

private struct AddProjectButton: View {
    @Binding var showingProjectAdd: Bool
    let disabled: Bool

    var body: some View {
        Button {
            showingProjectAdd = true
        } label: {
            Image(systemName: "folder.badge.plus")
        }
        .disabled(disabled)
        .accessibilityLabel("Add Project")
    }
}

private struct ProjectSessionScopeRow: View {
    let project: ProjectRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct NewSessionButton: View {
    let canCreateSession: Bool
    let onStartInNewWorktree: () -> Void
    let onStartInProjectDirectory: () -> Void

    var body: some View {
        Menu {
            Button {
                onStartInNewWorktree()
            } label: {
                Label("Start in New Worktree", systemImage: "arrow.triangle.branch")
            }
            Button {
                onStartInProjectDirectory()
            } label: {
                Label("Start in Project Directory", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus.bubble")
        }
        .disabled(!canCreateSession)
        .accessibilityLabel("New Session")
        .accessibilityIdentifier("projectNewSessionButton")
    }
}

private struct SessionsContent: View {
    let selectedProject: ProjectRecord
    @Binding var showsArchivedSessions: Bool
    let sections: [SessionListSection]
    let selectedThreadID: String?
    let serverContentDisabled: Bool
    let contentOpacity: Double
    let onArchive: (CodexThread) -> Void
    let onUnarchive: (CodexThread) -> Void
    let onOpen: (CodexThread) -> Void

    @ViewBuilder
    var body: some View {
        Section {
            ProjectSessionScopeRow(project: selectedProject)
            Toggle("Show archived sessions", isOn: $showsArchivedSessions)
                .font(.subheadline)
        }
        .disabled(serverContentDisabled)
        .opacity(contentOpacity)

        SessionSectionsList(
            sections: sections,
            selectedThreadID: selectedThreadID,
            onArchive: onArchive,
            onUnarchive: onUnarchive,
            onOpen: onOpen
        )
        .disabled(serverContentDisabled)
        .opacity(contentOpacity)
    }
}

private struct SessionSectionsList: View {
    let sections: [SessionListSection]
    let selectedThreadID: String?
    let onArchive: (CodexThread) -> Void
    let onUnarchive: (CodexThread) -> Void
    let onOpen: (CodexThread) -> Void

    var body: some View {
        ForEach(sections) { sessionSection in
            Section(sessionSection.title) {
                ForEach(sessionSection.threads) { thread in
                    Button {
                        onOpen(thread)
                    } label: {
                        ThreadRow(thread: thread, selected: thread.id == selectedThreadID)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if thread.isArchived {
                            Button { onUnarchive(thread) } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            .tint(.blue)
                        } else {
                            Button { onArchive(thread) } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                    .contextMenu {
                        if thread.isArchived {
                            Button { onUnarchive(thread) } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                        } else {
                            Button { onArchive(thread) } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                    .accessibilityIdentifier("threadRow")
                }
            }
        }
    }
}

private struct LoadingListStatusRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("listLoadingStatus")
    }
}

struct ConnectionDiagnosticsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.isRunningConnectionDiagnostics {
                    Section {
                        LoadingListStatusRow(title: "Running diagnostics...")
                    }
                }
                if let report = model.connectionDiagnosticReport {
                    Section("Connection") {
                        diagnosticRow("Host", report.host)
                        diagnosticRow("Auth method", report.authMethod)
                        diagnosticRow("Failure stage", report.failureStage ?? "none")
                        diagnosticRow("SSH host key fingerprint", report.hostKeyFingerprint ?? "not observed")
                        if let pinned = report.pinnedHostKeyFingerprint {
                            diagnosticRow("Pinned SSH host key fingerprint", pinned)
                        }
                    }
                    if let note = report.doctorNote {
                        Section("Doctor") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(note.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    Section("Resolved Addresses") {
                        if report.resolvedAddresses.isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.resolvedAddresses, id: \.self) { address in
                                Text(address)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    Section("TCP Results") {
                        if report.tcpResults.isEmpty {
                            Text("Not run")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.tcpResults) { result in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.address)
                                        .font(.system(.body, design: .monospaced))
                                    Text(result.result)
                                        .font(.caption)
                                        .foregroundStyle(result.result == "connected" ? .green : .red)
                                }
                            }
                        }
                    }
                    Section("Stages") {
                        diagnosticRow("Remote command", report.remoteCommandResult ?? "not reached")
                        diagnosticRow("App-server", report.appServerResult ?? "not reached")
                    }
                    Section("Raw Error") {
                        diagnosticRow("Type", report.rawUnderlyingErrorType ?? "none")
                        diagnosticRow("Error", report.rawUnderlyingError ?? "none")
                    }
                } else {
                    Section {
                        ContentUnavailableView("No Diagnostics Yet", systemImage: "stethoscope")
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.diagnoseSelectedConnection() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRunningConnectionDiagnostics)
                    .accessibilityLabel("Run Diagnostics")
                }
            }
            .task {
                if model.connectionDiagnosticReport == nil {
                    await model.diagnoseSelectedConnection()
                }
            }
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: title == "Error" ? .default : .monospaced))
                .textSelection(.enabled)
        }
    }
}

struct ProjectRow: View {
    let project: ProjectRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.subheadline.weight(.medium))
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct ThreadRow: View {
    let thread: CodexThread
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(2)
                Text(thread.cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(thread.status.sessionLabel)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusColor: Color {
        switch thread.status.indicator {
        case .active:
            return .green
        case .needsAttention:
            return .red
        case .inactive:
            return .secondary.opacity(0.4)
        }
    }
}
