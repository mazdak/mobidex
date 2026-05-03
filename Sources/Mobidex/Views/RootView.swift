import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var model: AppViewModel
    @State private var showingAddServer = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            ServerSidebarView(showingAddServer: $showingAddServer)
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

struct ServerSidebarView: View {
    @EnvironmentObject private var model: AppViewModel
    @Binding var showingAddServer: Bool
    @State private var editingServer: ServerRecord?

    var body: some View {
        List(selection: selectedServerBinding) {
            ForEach(model.servers) { server in
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.displayName)
                        .font(.headline)
                    Text(server.endpointLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("serverRow")
                .tag(server.id)
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

    private var selectedServerBinding: Binding<UUID?> {
        Binding {
            model.selectedServerID
        } set: { serverID in
            _ = model.selectServer(serverID)
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

    var body: some View {
        Group {
            if let server = model.selectedServer {
                List {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.endpointLabel)
                                    .font(.subheadline)
                                Text(model.connectionState.label)
                                    .font(.caption)
                                    .foregroundStyle(statusColor)
                            }
                            Spacer()
                            if model.isBusy {
                                ProgressView()
                            }
                        }
                        HStack {
                            Button {
                                Task { await model.testSelectedConnection() }
                            } label: {
                                Label("Test", systemImage: "checkmark.circle")
                            }
                            .accessibilityIdentifier("testConnectionButton")
                            Button {
                                Task { await model.connectSelectedServer() }
                            } label: {
                                Label("Connect", systemImage: "bolt.horizontal")
                            }
                            .accessibilityIdentifier("connectButton")
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

                    switch selectedMode {
                    case .projects:
                        Section("Projects") {
                            ForEach(visibleProjects(from: server.projects)) { project in
                                HStack(spacing: 10) {
                                    Button {
                                        model.selectProject(project.id)
                                        promoteDetailIfCompact()
                                        Task { await model.refreshThreads() }
                                    } label: {
                                        ProjectRow(project: project, selected: project.id == model.selectedProjectID)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("projectRow")

                                    Button {
                                        _ = model.setProjectFavorite(project, isFavorite: !project.isFavorite)
                                    } label: {
                                        Image(systemName: project.isFavorite ? "star.fill" : "star")
                                            .foregroundStyle(project.isFavorite ? .yellow : .secondary)
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(project.isFavorite ? "Remove Favorite" : "Add Favorite")
                                    .accessibilityIdentifier("projectFavoriteButton")
                                }
                                .swipeActions {
                                    Button {
                                        _ = model.setProjectFavorite(project, isFavorite: !project.isFavorite)
                                    } label: {
                                        Label(project.isFavorite ? "Unfavorite" : "Favorite", systemImage: project.isFavorite ? "star.slash" : "star")
                                    }
                                    .tint(.yellow)

                                    Button(role: .destructive) {
                                        model.removeProject(project)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    case .sessions:
                        Section("Sessions") {
                            ForEach(model.threads) { thread in
                                Button {
                                    promoteDetailIfCompact()
                                    Task { await model.openThread(thread) }
                                } label: {
                                    ThreadRow(thread: thread, selected: thread.id == model.selectedThreadID)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("threadRow")
                            }
                            if model.threads.isEmpty {
                                ContentUnavailableView("No Sessions", systemImage: "bubble.left.and.bubble.right")
                            }
                        }
                    }
                }
                .searchable(text: $projectSearchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Projects")
                .onChange(of: projectSearchText) { _, newValue in
                    if !newValue.isEmpty {
                        selectedMode = .projects
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await model.refreshProjects() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh Projects")

                        Button {
                            showingProjectAdd = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
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

    private var statusColor: Color {
        switch model.connectionState {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }

    private func promoteDetailIfCompact() {
        if horizontalSizeClass == .compact {
            preferredCompactColumn = .detail
            columnVisibility = .detailOnly
        }
    }

    private func visibleProjects(from projects: [ProjectRecord]) -> [ProjectRecord] {
        let trimmedSearch = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = projects.filter { project in
            guard !trimmedSearch.isEmpty else {
                return true
            }
            return project.displayName.localizedCaseInsensitiveContains(trimmedSearch)
                || project.path.localizedCaseInsensitiveContains(trimmedSearch)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            let lhsDate = lhs.lastSeenAt ?? .distantPast
            let rhsDate = rhs.lastSeenAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
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
                        project.threadCount > 0
                            ? "\(project.threadCount) \(project.threadCount == 1 ? "session" : "sessions") found in .codex"
                            : "No sessions found in .codex"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if project.discovered {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .fill(thread.status.isActive ? Color.green : Color.secondary.opacity(0.4))
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
                Text(thread.status.label)
                    .font(.caption2)
                    .foregroundStyle(thread.status.isActive ? .green : .secondary)
            }
        }
    }
}
