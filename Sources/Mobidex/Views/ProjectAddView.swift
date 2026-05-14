import SwiftUI

struct ProjectAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppViewModel
    @State private var path = ""
    @State private var discoverySearchText = ""
    @State private var validationMessage: String?
    @State private var showingBrowser = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Path") {
                    HStack(spacing: 8) {
                        TextField("/home/user/project", text: $path)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(add)
                        Button {
                            showingBrowser = true
                        } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("Browse Remote Folders")
                    }
                }

                Section {
                    Button {
                        Task { await model.refreshProjects() }
                    } label: {
                        Label("Discover Projects", systemImage: "magnifyingglass")
                    }
                    .disabled(model.isDiscoveringProjects)

                    if model.isDiscoveringProjects {
                        HStack {
                            ProgressView()
                            Text("Discovering projects")
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Search discovered projects", text: $discoverySearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Discovery")
                }

                Section("Discovered Projects") {
                    if discoveredProjects.isEmpty {
                        ContentUnavailableView("No Discovered Projects", systemImage: "folder.badge.questionmark")
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(discoveredProjects) { project in
                            Button {
                                path = project.path
                                add()
                            } label: {
                                ProjectRow(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("projectValidationMessage")
                    }
                }
            }
            .navigationTitle("Add Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add()
                    }
                }
            }
            .onChange(of: path) { _, _ in
                validationMessage = nil
            }
            .sheet(isPresented: $showingBrowser) {
                RemoteDirectoryBrowserView(
                    initialPath: path.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "/"
                ) { selectedPath in
                    path = selectedPath
                    showingBrowser = false
                }
            }
        }
    }

    private func add() {
        if model.addProject(path: path) {
            dismiss()
        } else {
            validationMessage = model.statusMessage ?? "Mobidex could not save this project."
        }
    }

    private var discoveredProjects: [ProjectRecord] {
        let query = discoverySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (model.selectedServer?.projects ?? [])
            .filter { $0.discovered && !$0.isAddedToProjectList }
            .filter {
                query.isEmpty ||
                    $0.displayName.localizedCaseInsensitiveContains(query) ||
                    $0.path.localizedCaseInsensitiveContains(query)
            }
    }
}

private struct RemoteDirectoryBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppViewModel
    @State private var currentPath: String
    @State private var entries: [RemoteDirectoryEntry] = []
    @State private var isLoading = false
    @State private var folderName = ""
    @State private var errorMessage: String?
    let onSelect: (String) -> Void

    init(initialPath: String, onSelect: @escaping (String) -> Void) {
        _currentPath = State(initialValue: initialPath)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(currentPath)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if currentPath != "/" {
                    Section {
                        Button {
                            Task { await load(parentPath) }
                        } label: {
                            Label("Parent Folder", systemImage: "arrow.up")
                        }
                    }
                }
                Section("Create Folder") {
                    HStack(spacing: 8) {
                        TextField("Folder name", text: $folderName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await createFolder() } }
                        Button {
                            Task { await createFolder() }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .accessibilityLabel("Create Folder")
                    }
                }
                Section("Folders") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading Folders")
                                .foregroundStyle(.secondary)
                        }
                    } else if entries.isEmpty {
                        ContentUnavailableView("No Folders", systemImage: "folder")
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(entries) { entry in
                            Button {
                                Task { await load(entry.path) }
                            } label: {
                                Label(entry.name, systemImage: "folder")
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") { onSelect(currentPath) }
                        .disabled(isLoading)
                }
            }
            .task {
                await load(currentPath)
            }
        }
    }

    private var parentPath: String {
        guard currentPath != "/" else { return "/" }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        return parent.isEmpty ? "/" : parent
    }

    @MainActor
    private func load(_ path: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let listing = try await model.listRemoteDirectories(path: path)
            currentPath = listing.path
            entries = listing.entries
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func createFolder() async {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let listing = try await model.createRemoteDirectory(parentPath: currentPath, folderName: name)
            folderName = ""
            await load(listing.path)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
