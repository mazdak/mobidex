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
        .safeAreaInset(edge: .bottom) {
            if let statusMessage = model.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
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
    @State private var showInactiveDiscoveredProjects = false
    @State private var isSessionRefreshRequested = false
    @State private var skipNextAllSessionsRefresh = false
    @State private var showingTerminal = false
    @State private var showingDiagnostics = false

    var body: some View {
        Group {
            if let server = model.selectedServer {
                List {
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
                    }

                    Section {
                        Picker("List", selection: $selectedMode) {
                            ForEach(ProjectSessionMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if contentIsLoading {
                        Section {
                            LoadingListStatusRow(title: loadingStatusTitle)
                                .listRowSeparator(.hidden)
                        }
                    }

                    switch selectedMode {
                    case .projects:
                        let sections = projectSections(from: server.projects)
                        if sections.showInactiveDiscoveredFilter {
                            Section {
                                Toggle("Show inactive discovered projects", isOn: $showInactiveDiscoveredProjects)
                                    .font(.subheadline)
                            }
                            .disabled(serverContentDisabled)
                            .opacity(contentOpacity)
                        }
                        if sections.showArchivedSessionFilter {
                            Section {
                                Toggle("Show archived sessions", isOn: $model.showsArchivedSessions)
                                    .font(.subheadline)
                            }
                            .disabled(serverContentDisabled)
                            .opacity(contentOpacity)
                        }

                        if !sections.favorites.isEmpty {
                            Section("Favorites") {
                                ForEach(sections.favorites) { project in
                                    projectRow(project)
                                }
                            }
                            .disabled(serverContentDisabled)
                            .opacity(contentOpacity)
                        }

                        if !sections.discovered.isEmpty {
                            Section(sections.discoveredTitle) {
                                ForEach(sections.discovered) { project in
                                    projectRow(project)
                                }
                            }
                            .disabled(serverContentDisabled)
                            .opacity(contentOpacity)
                        }

                        if sections.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    projectsUnavailableTitle(server: server, sections: sections),
                                    systemImage: "folder"
                                )
                                .frame(maxWidth: .infinity, minHeight: 260)
                                .listRowSeparator(.hidden)
                            }
                        }
                    case .sessions:
                        if let project = model.selectedProject, !model.isShowingAllSessions {
                            Section("Project") {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.displayName)
                                        .font(.headline)
                                    Text(project.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        Section {
                            Toggle("Show archived sessions", isOn: $model.showsArchivedSessions)
                                .font(.subheadline)
                        }
                        .disabled(serverContentDisabled)
                        .opacity(contentOpacity)

                        ForEach(model.sessionSections) { sessionSection in
                            Section(sessionSection.title) {
                                ForEach(sessionSection.threads) { thread in
                                    Button {
                                        promoteDetailIfCompact()
                                        Task { await model.openThread(thread) }
                                    } label: {
                                        ThreadRow(thread: thread, selected: thread.id == model.selectedThreadID)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("threadRow")
                                }
                            }
                        }
                        .disabled(serverContentDisabled)
                        .opacity(contentOpacity)
                        if model.threads.isEmpty {
                            Section("Sessions") {
                                ContentUnavailableView(
                                    sessionsUnavailableTitle,
                                    systemImage: "bubble.left.and.bubble.right"
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
                .searchable(text: $projectSearchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Projects")
                .onChange(of: projectSearchText) { _, newValue in
                    if !newValue.isEmpty {
                        selectedMode = .projects
                    }
                }
                .onChange(of: selectedMode) { _, newValue in
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
                .onChange(of: model.showsArchivedSessions) { _, _ in
                    guard model.isAppServerConnected else { return }
                    isSessionRefreshRequested = true
                    Task {
                        await model.refreshThreads()
                        isSessionRefreshRequested = false
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await model.refreshProjects() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(serverControlsDisabled)
                        .accessibilityLabel("Refresh Projects")

                        Button {
                            showingProjectAdd = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .disabled(serverControlsDisabled)
                        .accessibilityLabel("Add Project")
                    }
                }
                .sheet(isPresented: $showingProjectAdd) {
                    ProjectAddView()
                }
            } else {
                ContentUnavailableView("Select a Server", systemImage: "server.rack")
            }
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

    private var loadingStatusTitle: String {
        switch selectedMode {
        case .projects:
            "Loading projects..."
        case .sessions:
            "Loading sessions..."
        }
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
            return "Loading Sessions"
        }
        return model.connectionState == .connected ? "No Sessions" : "Connect to Load Sessions"
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

    private func projectSections(from projects: [ProjectRecord]) -> ProjectListSections {
        ProjectListSections(
            projects: projects,
            searchText: trimmedProjectSearch,
            showInactiveDiscoveredProjects: showInactiveDiscoveredProjects,
            showArchivedSessionProjects: model.showsArchivedSessions
        )
    }

    private func projectsUnavailableTitle(server: ServerRecord, sections: ProjectListSections) -> String {
        if !trimmedProjectSearch.isEmpty {
            return "No Matching Projects"
        }
        if model.isDiscoveringProjects {
            return "Loading Projects"
        }
        if !server.projects.isEmpty && sections.showArchivedSessionFilter && !model.showsArchivedSessions {
            return "No Active Projects"
        }
        return "No Projects"
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        Button {
            model.selectProject(project.id)
            if selectedMode == .sessions {
                skipNextAllSessionsRefresh = false
            } else {
                skipNextAllSessionsRefresh = true
                selectedMode = .sessions
            }
            Task { await model.refreshThreads() }
        } label: {
            ProjectRow(project: project, selected: project.id == model.selectedProjectID)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectRow")
        .swipeActions {
            Button {
                _ = model.setProjectFavorite(project, isFavorite: !project.isFavorite)
            } label: {
                Label(project.isFavorite ? "Unfavorite" : "Favorite", systemImage: project.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)

            if !project.discovered {
                Button(role: .destructive) {
                    model.removeProject(project)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
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
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "folder.fill" : "folder")
                .foregroundStyle(selected ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.subheadline.weight(.medium))
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if project.discovered {
                    Text(
                        project.discoveredSessionCount > 0
                            ? "\(project.discoveredSessionCount) active \(project.discoveredSessionCount == 1 ? "session" : "sessions")"
                            : "No active sessions"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if project.archivedSessionCount > 0 {
                        Text("\(project.archivedSessionCount) archived \(project.archivedSessionCount == 1 ? "session" : "sessions")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if project.activeChatCount > 0 {
                        Text("\(project.activeChatCount) loaded in app-server")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if project.sessionPaths.count > 1 {
                        Text("\(project.sessionPaths.count) worktree paths grouped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if project.isFavorite {
                Image(systemName: "star.fill")
                    .font(.body)
                    .foregroundStyle(.yellow)
            }
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
