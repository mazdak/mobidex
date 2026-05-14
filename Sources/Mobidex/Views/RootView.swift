import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var model: AppViewModel
    @State private var showingAddServer = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            ServerSidebarView(
                showingAddServer: $showingAddServer,
                columnVisibility: $columnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            )
                .navigationTitle("Servers")
        } content: {
            ProjectSessionListView(
                columnVisibility: $columnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            )
                .navigationTitle(model.selectedServer?.displayName ?? "Mobidex")
        } detail: {
            ConversationView()
        }
        .sheet(isPresented: $showingAddServer) {
            ServerEditorView(server: nil)
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

private struct ServerActionButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .imageScale(.medium)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .accessibilityLabel(title)
    }
}

struct ServerSidebarView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var showingAddServer: Bool
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

struct ProjectSessionListView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    @State private var showingProjectAdd = false
    @State private var selectedMode: ProjectSessionMode = .projects
    @State private var projectSearchText = ""
    @State private var sessionSearchText = ""
    @State private var isSessionRefreshRequested = false
    @State private var skipNextAllSessionsRefresh = false
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

                    LoadingSection(isLoading: selectedMode == .projects && contentIsLoading, title: "Loading projects...")

                    switch selectedMode {
                    case .projects:
                        let sections = projectSections(from: server.projects)
                        ProjectSectionsContent(
                            sections: sections,
                            unavailableTitle: projectsUnavailableTitle(server: server, sections: sections),
                            serverContentDisabled: serverContentDisabled,
                            contentOpacity: contentOpacity,
                            selectedMode: $selectedMode,
                            skipNextAllSessionsRefresh: $skipNextAllSessionsRefresh
                        ) {}
                    case .sessions:
                        let sessionSections = filteredSessionSections(model.sessionSections)
                        SessionsContent(
                            selectedProject: model.selectedProject,
                            isShowingAllSessions: model.isShowingAllSessions,
                            canCreateSession: model.canCreateSession,
                            showsArchivedSessions: $model.showsArchivedSessions,
                            sections: sessionSections,
                            selectedThreadID: model.selectedThreadID,
                            serverContentDisabled: serverContentDisabled,
                            contentOpacity: contentOpacity,
                            onStartNewSession: {
                                promoteDetailIfCompact()
                                Task { await model.startNewSession() }
                            },
                            onOpen: { thread in
                                promoteDetailIfCompact()
                                Task { await model.openThread(thread) }
                            }
                        )

                        if sessionSections.isEmpty {
                            Section("Sessions") {
                                ContentUnavailableView(
                                    sessionsUnavailableTitle,
                                    systemImage: "bubble.left.and.bubble.right",
                                    description: Text(sessionsUnavailableDescription)
                                )
                                    .frame(maxWidth: .infinity, minHeight: 260)
                                    .listRowSeparator(.hidden)
                            }
                        }
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
                .searchable(text: searchTextBinding, placement: .navigationBarDrawer(displayMode: .automatic), prompt: searchPrompt)
                .onChange(of: selectedMode) { _, newValue in
                    handleSelectedModeChange(newValue)
                }
                .onChange(of: model.showsArchivedSessions) { _, _ in
                    handleArchivedSessionsChange()
                }
                .toolbar {
                    SelectedServerToolbar(
                        server: server,
                        disabled: serverControlsDisabled,
                        showingProjectAdd: $showingProjectAdd,
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
    }

    private func handleSelectedModeChange(_ newValue: ProjectSessionMode) {
        guard newValue == .sessions else { return }
        if skipNextAllSessionsRefresh {
            skipNextAllSessionsRefresh = false
            return
        }
        isSessionRefreshRequested = true
        Task {
            await model.selectAllSessionsAndRefresh()
            isSessionRefreshRequested = false
        }
    }

    private func handleArchivedSessionsChange() {
        guard model.isAppServerConnected else { return }
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
                if model.isBusy {
                    ProgressView()
                }
            }
            HStack {
                Button {
                    Task { await model.connectSelectedServer(syncActiveChatCounts: true) }
                } label: {
                    ServerActionButtonLabel(
                        title: model.isAppServerConnected ? "Reconnect" : "Connect",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
                .frame(maxWidth: .infinity)
                .disabled(model.connectionState == .connecting)
                .accessibilityIdentifier("connectButton")
                Button {
                    showingTerminal = true
                } label: {
                    ServerActionButtonLabel(title: "Terminal", systemImage: "terminal")
                }
                .frame(maxWidth: .infinity)
                .disabled(serverControlsDisabled)
                .accessibilityIdentifier("terminalButton")
                Button {
                    showingDiagnostics = true
                } label: {
                    ServerActionButtonLabel(title: "Doctor", systemImage: "stethoscope")
                }
                .frame(maxWidth: .infinity)
                .disabled(serverControlsDisabled || model.isRunningConnectionDiagnostics)
                .accessibilityIdentifier("connectionDiagnosticsButton")
            }
            .buttonStyle(.bordered)

            Picker("List", selection: $selectedMode) {
                ForEach(ProjectSessionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var serverControlsDisabled: Bool {
        model.connectionState == .connecting
    }

    private var serverContentDisabled: Bool {
        contentIsLoading || serverControlsDisabled
    }

    private var contentIsLoading: Bool {
        switch selectedMode {
        case .projects:
            model.isDiscoveringProjects
        case .sessions:
            isSessionRefreshRequested || model.isRefreshingSessions
        }
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

    private var sessionsUnavailableDescription: String {
        if !model.isShowingAllSessions, model.selectedProject != nil, model.connectionState == .connected {
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

    private var trimmedProjectSearch: String {
        projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSessionSearch: String {
        sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPrompt: String {
        selectedMode == .sessions ? "Search Sessions" : "Search Projects"
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { selectedMode == .sessions ? sessionSearchText : projectSearchText },
            set: { value in
                if selectedMode == .sessions {
                    sessionSearchText = value
                } else {
                    projectSearchText = value
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
    @Binding var selectedMode: ProjectSessionMode
    @Binding var skipNextAllSessionsRefresh: Bool
    let onOpenProject: () -> Void

    @ViewBuilder
    var body: some View {
        ProjectListSection(
            title: "Projects",
            projects: sections.projects,
            serverContentDisabled: serverContentDisabled,
            contentOpacity: contentOpacity,
            selectedMode: $selectedMode,
            skipNextAllSessionsRefresh: $skipNextAllSessionsRefresh,
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
    @Binding var selectedMode: ProjectSessionMode
    @Binding var skipNextAllSessionsRefresh: Bool
    let onOpenProject: () -> Void

    @ViewBuilder
    var body: some View {
        if !projects.isEmpty {
            Section(title) {
                ForEach(projects) { project in
                    ProjectActionRow(
                        project: project,
                        selectedMode: $selectedMode,
                        skipNextAllSessionsRefresh: $skipNextAllSessionsRefresh,
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
    @Binding var selectedMode: ProjectSessionMode
    @Binding var skipNextAllSessionsRefresh: Bool
    let onOpenProject: () -> Void

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
        model.selectProject(project.id)
        if selectedMode == .sessions {
            skipNextAllSessionsRefresh = false
        } else {
            skipNextAllSessionsRefresh = true
            selectedMode = .sessions
        }
        onOpenProject()
        Task { await model.refreshThreads() }
    }
}

private struct SelectedServerMenu: View {
    let server: ServerRecord
    @Binding var editingServer: ServerRecord?
    @Binding var serverPendingDeletion: ServerRecord?
    @Binding var isDeleteServerConfirmationPresented: Bool

    var body: some View {
        Menu {
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
    let disabled: Bool
    @Binding var showingProjectAdd: Bool
    @Binding var editingServer: ServerRecord?
    @Binding var serverPendingDeletion: ServerRecord?
    @Binding var isDeleteServerConfirmationPresented: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            RefreshProjectsButton(disabled: disabled)
            AddProjectButton(showingProjectAdd: $showingProjectAdd, disabled: disabled)
            SelectedServerMenu(
                server: server,
                editingServer: $editingServer,
                serverPendingDeletion: $serverPendingDeletion,
                isDeleteServerConfirmationPresented: $isDeleteServerConfirmationPresented
            )
        }
    }
}

private struct RefreshProjectsButton: View {
    @EnvironmentObject private var model: AppViewModel
    let disabled: Bool

    var body: some View {
        Button {
            Task { await model.refreshProjects() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(disabled)
        .accessibilityLabel("Refresh Projects")
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
    let canCreateSession: Bool
    let onStartNewSession: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions in \(project.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onStartNewSession) {
                Label("New Session", systemImage: "plus.bubble")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreateSession)
            .accessibilityIdentifier("projectNewSessionButton")
        }
        .padding(.vertical, 2)
    }
}

private struct SessionsContent: View {
    let selectedProject: ProjectRecord?
    let isShowingAllSessions: Bool
    let canCreateSession: Bool
    @Binding var showsArchivedSessions: Bool
    let sections: [SessionListSection]
    let selectedThreadID: String?
    let serverContentDisabled: Bool
    let contentOpacity: Double
    let onStartNewSession: () -> Void
    let onOpen: (CodexThread) -> Void

    @ViewBuilder
    var body: some View {
        Section {
            if let project = selectedProject, !isShowingAllSessions {
                ProjectSessionScopeRow(
                    project: project,
                    canCreateSession: canCreateSession && !serverContentDisabled,
                    onStartNewSession: onStartNewSession
                )
            }
            Toggle("Show archived sessions", isOn: $showsArchivedSessions)
                .font(.subheadline)
        }
        .disabled(serverContentDisabled)
        .opacity(contentOpacity)

        SessionSectionsList(
            sections: sections,
            selectedThreadID: selectedThreadID,
            onOpen: onOpen
        )
        .disabled(serverContentDisabled)
        .opacity(contentOpacity)
    }
}

private struct SessionSectionsList: View {
    let sections: [SessionListSection]
    let selectedThreadID: String?
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

private enum ProjectSessionMode: String, CaseIterable, Identifiable {
    case projects
    case sessions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .projects: "Projects"
        case .sessions: "Sessions"
        }
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
