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

                    Section("Projects") {
                        ForEach(server.projects) { project in
                            Button {
                                model.selectProject(project.id)
                                promoteDetailIfCompact()
                                Task { await model.refreshThreads() }
                            } label: {
                                ProjectRow(project: project, selected: project.id == model.selectedProjectID)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("projectRow")
                            .swipeActions {
                                Button(role: .destructive) {
                                    model.removeProject(project)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

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
