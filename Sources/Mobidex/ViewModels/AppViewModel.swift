import Foundation

struct PendingApproval: Identifiable, Equatable {
    var id: String
    var requestID: JSONValue
    var method: String
    var params: JSONValue?
    var title: String
    var detail: String
}

struct StatusAlert: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var message: String
}

private enum AppViewModelError: LocalizedError {
    case selectionChanged

    var errorDescription: String? {
        switch self {
        case .selectionChanged:
            "The selected server or project changed before the operation finished."
        }
    }
}

private struct ThreadLoadScope: Equatable {
    var serverID: UUID?
    var projectID: UUID?
    var cwd: String?
    var sessionPaths: Set<String>
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var servers: [ServerRecord] = []
    @Published private(set) var selectedServerID: UUID?
    @Published private(set) var selectedProjectID: UUID?
    @Published private(set) var threads: [CodexThread] = []
    @Published private(set) var selectedThreadID: String?
    @Published private(set) var selectedThread: CodexThread?
    @Published private(set) var conversationSections: [ConversationSection] = []
    @Published private(set) var isSelectedThreadLoading = false
    @Published private(set) var conversationRevision = 0
    @Published private(set) var pendingApprovals: [PendingApproval] = []
    @Published private(set) var connectionState: ServerConnectionState = .disconnected
    @Published private(set) var statusMessage: String?
    @Published var statusAlert: StatusAlert?
    @Published private(set) var isBusy = false

    private let repository: ServerRepository
    private let credentialStore: CredentialStore
    private let sshService: SSHService
    private let activeTurnRefreshIntervalNanoseconds: UInt64
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private var appServer: CodexAppServerClient?
    private var eventTask: Task<Void, Never>?
    private var activeTurnRefreshTask: Task<Void, Never>?
    private var activeTurnRefreshThreadID: String?
    private var connectionGeneration = 0
    private var liveItems: [CodexThreadItem] = []
    private var selectedThreadLoadingCounts: [String: Int] = [:]

    init(
        repository: ServerRepository,
        credentialStore: CredentialStore,
        sshService: SSHService,
        activeTurnRefreshIntervalNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.repository = repository
        self.credentialStore = credentialStore
        self.sshService = sshService
        self.activeTurnRefreshIntervalNanoseconds = activeTurnRefreshIntervalNanoseconds
        loadServers()
    }

    var selectedServer: ServerRecord? {
        guard let selectedServerID else { return nil }
        return servers.first { $0.id == selectedServerID }
    }

    var selectedProject: ProjectRecord? {
        guard let selectedProjectID, let selectedServer else { return nil }
        return selectedServer.projects.first { $0.id == selectedProjectID }
    }

    var canSendMessage: Bool {
        appServer != nil
    }

    var canInterruptActiveTurn: Bool {
        appServer != nil && activeTurnID != nil
    }

    var isAppServerConnected: Bool {
        appServer != nil
    }

    func loadCredential(for serverID: UUID) -> SSHCredential {
        (try? credentialStore.loadCredential(serverID: serverID)) ?? SSHCredential()
    }

    @discardableResult
    func selectServer(_ serverID: UUID?) -> Bool {
        guard selectedServerID != serverID else {
            return true
        }
        guard connectionState != .connected && connectionState != .connecting else {
            statusMessage = "Disconnect before switching servers."
            return false
        }

        selectedServerID = serverID
        selectedProjectID = serverID.flatMap { id in
            servers.first { $0.id == id }?.projects.first?.id
        }
        resetSessionState(clearThreads: true)
        pendingApprovals = []
        return true
    }

    func selectProject(_ projectID: UUID?) {
        guard selectedProjectID != projectID else {
            return
        }
        selectedProjectID = projectID
        resetSessionState(clearThreads: true)
    }

    @discardableResult
    func setProjectFavorite(_ project: ProjectRecord, isFavorite: Bool) -> Bool {
        guard let selectedServerID else {
            return false
        }

        var nextServers = servers
        guard let serverIndex = nextServers.firstIndex(where: { $0.id == selectedServerID }),
              let projectIndex = nextServers[serverIndex].projects.firstIndex(where: { $0.id == project.id })
        else {
            return false
        }

        guard nextServers[serverIndex].projects[projectIndex].isFavorite != isFavorite else {
            return true
        }

        nextServers[serverIndex].projects[projectIndex].isFavorite = isFavorite
        nextServers[serverIndex].updatedAt = .now

        do {
            try persistServers(nextServers)
            servers = nextServers
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveServer(_ server: ServerRecord, credential: SSHCredential) async -> Bool {
        let trimmedHost = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            statusMessage = "Enter the SSH host for this server."
            return false
        }
        let trimmedUsername = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            statusMessage = "Enter the SSH username for this server."
            return false
        }
        let normalizedCredential = normalizedCredential(for: server.authMethod, credential: credential)
        guard credentialIsUsable(normalizedCredential, authMethod: server.authMethod) else {
            statusMessage = credentialRequiredMessage(for: server.authMethod)
            return false
        }

        var next = server
        next.host = trimmedHost
        next.username = trimmedUsername
        next.displayName = next.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.displayName.isEmpty {
            next.displayName = trimmedHost
        }
        next.codexPath = next.codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.codexPath.isEmpty {
            next.codexPath = "codex"
        }
        next.updatedAt = .now

        var nextServers = servers
        if let index = nextServers.firstIndex(where: { $0.id == server.id }) {
            nextServers[index] = next
        } else {
            nextServers.append(next)
        }

        do {
            try persistServers(nextServers)
            do {
                try credentialStore.saveCredential(normalizedCredential, serverID: next.id)
            } catch {
                try? persistServers(servers)
                throw error
            }
            let wasSelected = selectedServerID == next.id
            if wasSelected && (connectionState == .connected || connectionState == .connecting) {
                await disconnect()
            }
            servers = nextServers
            if selectedServerID == nil || wasSelected || (connectionState != .connected && connectionState != .connecting) {
                selectedServerID = next.id
                selectedProjectID = next.projects.first?.id
                resetSessionState(clearThreads: true)
            }
            statusMessage = "Saved \(next.displayName)."
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteServer(_ server: ServerRecord) async -> Bool {
        let oldServers = servers
        var nextServers = servers
        nextServers.removeAll { $0.id == server.id }
        guard nextServers.count != servers.count else {
            return true
        }

        let oldCredential: SSHCredential
        do {
            oldCredential = try credentialStore.loadCredential(serverID: server.id)
        } catch {
            statusMessage = error.localizedDescription
            return false
        }

        do {
            try credentialStore.deleteCredential(serverID: server.id)
        } catch {
            try? credentialStore.saveCredential(oldCredential, serverID: server.id)
            statusMessage = error.localizedDescription
            return false
        }

        do {
            try persistServers(nextServers)
            if selectedServerID == server.id {
                await disconnect()
            }
            servers = nextServers
            if selectedServerID == server.id {
                selectedServerID = servers.first?.id
                selectedProjectID = selectedServer?.projects.first?.id
                resetSessionState(clearThreads: true)
            }
            statusMessage = "Deleted \(server.displayName)."
            return true
        } catch {
            try? persistServers(oldServers)
            try? credentialStore.saveCredential(oldCredential, serverID: server.id)
            statusMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addProject(path: String) -> Bool {
        guard let selectedServerID else {
            return false
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a remote project path."
            return false
        }

        var nextServers = servers
        guard let index = nextServers.firstIndex(where: { $0.id == selectedServerID }) else {
            return false
        }
        guard !nextServers[index].projects.contains(where: { $0.path == trimmed }) else {
            statusMessage = "That project is already saved."
            return false
        }

        let project = ProjectRecord(path: trimmed)
        nextServers[index].projects.append(project)
        nextServers[index].updatedAt = .now

        do {
            try persistServers(nextServers)
            servers = nextServers
            selectedProjectID = project.id
            resetSessionState(clearThreads: true)
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func removeProject(_ project: ProjectRecord) -> Bool {
        guard let selectedServerID else {
            return false
        }

        var nextServers = servers
        guard let index = nextServers.firstIndex(where: { $0.id == selectedServerID }) else {
            return false
        }
        nextServers[index].projects.removeAll { $0.id == project.id }
        nextServers[index].updatedAt = .now
        let removedSelectedProject = selectedProjectID == project.id
        let nextSelectedProjectID = removedSelectedProject ? nextServers[index].projects.first?.id : selectedProjectID

        do {
            try persistServers(nextServers)
            servers = nextServers
            selectedProjectID = nextSelectedProjectID
            if removedSelectedProject {
                resetSessionState(clearThreads: true)
            }
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func testSelectedConnection() async {
        guard let selectedServer else { return }
        isBusy = true
        statusMessage = "Testing connection"
        do {
            let credential = try credentialStore.loadCredential(serverID: selectedServer.id)
            try await sshService.testConnection(server: selectedServer, credential: credential)
            if appServer == nil {
                connectionState = .disconnected
            }
            let message = "Connection test passed for \(selectedServer.displayName)."
            statusMessage = message
            statusAlert = StatusAlert(title: "Connection Test Passed", message: message)
        } catch {
            let message = error.localizedDescription
            connectionState = .failed(message)
            statusMessage = message
            statusAlert = StatusAlert(title: "Connection Test Failed", message: message)
        }
        isBusy = false
    }

    func connectSelectedServer() async {
        guard let targetServer = selectedServer else { return }
        connectionState = .connecting
        await closeConnection(updateState: false)
        guard selectedServerID == targetServer.id else {
            connectionState = .disconnected
            statusMessage = AppViewModelError.selectionChanged.localizedDescription
            return
        }
        await runBusy("Connecting") {
            connectionState = .connecting
            guard selectedServerID == targetServer.id else {
                throw AppViewModelError.selectionChanged
            }
            let credential = try credentialStore.loadCredential(serverID: targetServer.id)
            let connectedAppServer = try await sshService.openAppServer(server: targetServer, credential: credential)
            guard selectedServerID == targetServer.id else {
                await connectedAppServer.close()
                throw AppViewModelError.selectionChanged
            }
            appServer = connectedAppServer
            startEventLoop()
            connectionState = .connected
            statusMessage = "App-server connected."
            try await refreshProjectsUsingCredential(credential, server: targetServer, syncActiveThreadCounts: false)
            guard selectedServerID == targetServer.id else {
                throw AppViewModelError.selectionChanged
            }
            try await loadThreads()
        }
    }

    func refreshProjects() async {
        guard let selectedServer else { return }
        await runBusy("Discovering projects") {
            let credential = try credentialStore.loadCredential(serverID: selectedServer.id)
            try await refreshProjectsUsingCredential(credential, server: selectedServer, syncActiveThreadCounts: true)
        }
    }

    func refreshThreads() async {
        await runBusy("Refreshing sessions") {
            try await loadThreads()
        }
    }

    func openThread(_ thread: CodexThread) async {
        let scope = currentThreadLoadScope
        selectedThreadID = thread.id
        hydrateConversation(from: thread)
        beginSelectedThreadLoad(threadID: thread.id)
        await runBusy("Opening thread") {
            defer {
                endSelectedThreadLoad(threadID: thread.id, scope: scope)
            }
            guard let appServer else {
                return
            }
            let hydrated = try await appServer.readThread(threadID: thread.id)
            guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                return
            }
            selectedThreadID = hydrated.id
            hydrateConversation(from: hydrated)
        }
    }

    func startNewThread() async {
        guard selectedProject != nil else { return }
        guard !isBusy else { return }
        let scope = currentThreadLoadScope
        await runBusy("Starting thread") {
            guard let appServer else {
                statusMessage = "Connect to the app-server before starting a new session."
                return
            }
            let thread = try await appServer.startThread(cwd: scope.cwd)
            guard currentThreadLoadScope == scope, threadMatchesScope(thread, scope: scope) else {
                return
            }
            selectedThreadID = thread.id
            hydrateConversation(from: thread)
            threads = prioritizeActiveThreads([thread] + threads.filter { $0.id != thread.id })
            statusMessage = "New session created."
        }
    }

    func sendComposerText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard canSendMessage else {
            statusMessage = "Connect to the app-server before sending a message."
            return
        }

        let scope = currentThreadLoadScope
        let startingThreadID = selectedThreadID
        await runBusy("Sending") {
            guard let appServer else { return }
            guard currentThreadLoadScope == scope else { return }
            var thread: CodexThread
            var shouldHydrateThreadsAfterSend = true
            if let selectedThread {
                thread = selectedThread
            } else {
                thread = try await appServer.startThread(cwd: scope.cwd)
                let selectionMatchesStartedThread = selectedThreadID == startingThreadID
                    || (startingThreadID == nil && selectedThreadID == thread.id)
                guard currentThreadLoadScope == scope, selectionMatchesStartedThread, threadMatchesScope(thread, scope: scope) else {
                    return
                }
                selectedThreadID = thread.id
            }

            if thread.status.isActive {
                guard let activeTurnID else {
                    statusMessage = "The active turn is missing its turn id."
                    return
                }
                try await appServer.steer(threadID: thread.id, expectedTurnID: activeTurnID, text: trimmed)
                guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                    return
                }
                shouldHydrateThreadsAfterSend = false
            } else {
                let turn = try await appServer.startTurn(threadID: thread.id, text: trimmed)
                guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                    return
                }
                thread.status = turn.status == "inProgress" ? .active(flags: []) : .idle
                upsert(turn: turn, in: &thread)
                selectedThread = thread
                liveItems = thread.turns.flatMap(\.items)
                rebuildConversationFromLiveItems()
                if turn.status == "inProgress" {
                    scheduleActiveTurnRefresh(threadID: thread.id, scope: scope)
                    shouldHydrateThreadsAfterSend = false
                }
                if turn.status != "inProgress" {
                    beginSelectedThreadLoad(threadID: thread.id)
                    defer {
                        endSelectedThreadLoad(threadID: thread.id, scope: scope)
                    }
                    let hydrated = try await appServer.readThread(threadID: thread.id)
                    guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                        return
                    }
                    hydrateConversation(from: hydrated)
                }
            }
            if shouldHydrateThreadsAfterSend {
                try await loadThreads()
            } else {
                await refreshThreadListAfterEvent()
            }
        }
    }

    func interruptActiveTurn() async {
        guard let appServer, let selectedThread, let activeTurnID else {
            return
        }
        await runBusy("Interrupting") {
            try await appServer.interrupt(threadID: selectedThread.id, turnID: activeTurnID)
        }
    }

    func respond(to approval: PendingApproval, accept: Bool) async {
        await runBusy(accept ? "Approving" : "Declining") {
            guard let appServer else { return }
            guard let result = approvalResponse(for: approval, accept: accept) else {
                return
            }
            try await appServer.respondToServerRequest(id: approval.requestID, result: result)
            pendingApprovals.removeAll { $0.id == approval.id }
        }
    }

    func disconnect() async {
        await closeConnection(updateState: true)
    }

    private func closeConnection(updateState: Bool) async {
        connectionGeneration &+= 1
        eventTask?.cancel()
        eventTask = nil
        cancelActiveTurnRefresh()
        await appServer?.close()
        appServer = nil
        pendingApprovals = []
        if updateState {
            connectionState = .disconnected
        }
    }

    private var activeTurnID: String? {
        guard let selectedThread, selectedThread.status.isActive else {
            return nil
        }
        return selectedThread.turns.last(where: { $0.status == "inProgress" })?.id ?? selectedThread.turns.last?.id
    }

    private var currentThreadLoadScope: ThreadLoadScope {
        ThreadLoadScope(
            serverID: selectedServerID,
            projectID: selectedProjectID,
            cwd: selectedProject?.path,
            sessionPaths: Set(selectedProject?.sessionPaths ?? selectedProject.map { [$0.path] } ?? [])
        )
    }

    private func loadServers() {
        do {
            servers = try repository.loadServers()
            selectedServerID = servers.first?.id
            selectedProjectID = selectedServer?.projects.first?.id
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func persistServers(_ servers: [ServerRecord]) throws {
        try repository.saveServers(servers)
    }

    private func refreshProjectsUsingCredential(_ credential: SSHCredential, server: ServerRecord, syncActiveThreadCounts: Bool) async throws {
        let previousScope = currentThreadLoadScope
        let discovered = try await sshService.discoverProjects(server: server, credential: credential)
        var nextServers = servers
        guard let index = nextServers.firstIndex(where: { $0.id == server.id }) else {
            return
        }

        var existing = Dictionary(uniqueKeysWithValues: nextServers[index].projects.map { ($0.path, $0) })
        let discoveredPaths = Set(discovered.map(\.path))
        for path in Array(existing.keys) where !discoveredPaths.contains(path) {
            guard var record = existing[path], record.discovered else {
                continue
            }
            guard record.isFavorite else {
                existing.removeValue(forKey: path)
                continue
            }
            record.discovered = false
            record.sessionPaths = [record.path]
            record.threadCount = 0
            record.lastSeenAt = nil
            existing[path] = record
        }
        for project in discovered {
            var record = existing[project.path] ?? ProjectRecord(path: project.path)
            record.discovered = true
            record.sessionPaths = ProjectRecord.normalizedSessionPaths(project.sessionPaths, primaryPath: project.path)
            record.threadCount = project.threadCount
            record.lastSeenAt = project.lastSeenAt
            existing[project.path] = record
        }
        if syncActiveThreadCounts, let appServer {
            let activeThreads = try await appServer.listThreads(limit: 1_000)
            applyActiveThreadCounts(activeThreads, to: &existing)
        }
        nextServers[index].projects = existing.values.sorted { lhs, rhs in
            (lhs.lastSeenAt ?? .distantPast) > (rhs.lastSeenAt ?? .distantPast)
        }
        nextServers[index].updatedAt = .now
        let nextSelectedProjectID = nextServers[index].projects.contains { $0.id == selectedProjectID }
            ? selectedProjectID
            : nextServers[index].projects.first?.id
        try persistServers(nextServers)
        servers = nextServers
        if selectedServerID == server.id {
            selectedProjectID = nextSelectedProjectID
            if currentThreadLoadScope != previousScope {
                resetSessionState(clearThreads: true)
            }
        }
    }

    private func loadThreads() async throws {
        guard let appServer else {
            return
        }
        let scope = currentThreadLoadScope
        let loadedThreads = try await listThreads(matching: scope)
        guard currentThreadLoadScope == scope else {
            return
        }
        let prioritizedThreads = prioritizeActiveThreads(loadedThreads)
        threads = prioritizedThreads

        let currentSelection = selectedThreadID.flatMap { id in
            prioritizedThreads.first { $0.id == id }
        }
        guard let threadToShow = currentSelection ?? prioritizedThreads.first else {
            selectedThreadID = nil
            selectedThread = nil
            liveItems = []
            conversationSections = []
            conversationRevision += 1
            clearSelectedThreadLoads()
            return
        }

        selectedThreadID = threadToShow.id
        if selectedThread?.id != threadToShow.id {
            hydrateConversation(from: threadToShow)
        }

        beginSelectedThreadLoad(threadID: threadToShow.id)
        defer {
            endSelectedThreadLoad(threadID: threadToShow.id, scope: scope)
        }
        let hydrated = try await appServer.readThread(threadID: threadToShow.id)
        guard currentThreadLoadScope == scope, selectedThreadID == threadToShow.id else {
            return
        }
        hydrateConversation(from: hydrated)
    }

    private func prioritizeActiveThreads(_ threads: [CodexThread]) -> [CodexThread] {
        threads.enumerated().sorted { lhs, rhs in
            let lhsActive = lhs.element.status.isActive
            let rhsActive = rhs.element.status.isActive
            if lhsActive != rhsActive {
                return lhsActive && !rhsActive
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func startEventLoop() {
        guard let events = appServer?.events else { return }
        eventTask?.cancel()
        connectionGeneration &+= 1
        let generation = connectionGeneration
        eventTask = Task { [weak self, events] in
            for await event in events {
                await self?.handle(event, generation: generation)
            }
        }
    }

    private func handle(_ event: CodexAppServerEvent, generation: Int) async {
        guard generation == connectionGeneration else {
            return
        }
        switch event {
        case .notification(let method, let params):
            statusMessage = method
            await handleNotification(method: method, params: params)
        case .serverRequest(let id, let method, let params):
            guard eventTargetsSelectedThread(params) else {
                return
            }
            pendingApprovals.append(PendingApproval(
                id: "\(id)-\(method)",
                requestID: id,
                method: method,
                params: params,
                title: approvalTitle(method: method, params: params),
                detail: approvalDetail(params: params)
            ))
        case .disconnected(let message):
            await handleDisconnected(message, generation: generation)
        }
    }

    private func handleNotification(method: String, params: JSONValue?) async {
        switch method {
        case "item/started", "item/completed":
            if eventTargetsSelectedThread(params), let item = try? decode(CodexThreadItem.self, from: params?["item"]) {
                upsertLiveItem(item)
            }
            if method == "item/completed" {
                await refreshThreadListAfterEvent()
            }
        case "item/agentMessage/delta":
            guard eventTargetsSelectedThread(params) else { return }
            appendAgentMessageDelta(itemID: params?["itemId"]?.stringValue, delta: params?["delta"]?.stringValue)
        case "item/commandExecution/outputDelta":
            guard eventTargetsSelectedThread(params) else { return }
            appendCommandOutputDelta(itemID: params?["itemId"]?.stringValue, delta: params?["delta"]?.stringValue)
        case "item/commandExecution/terminalInteraction":
            guard eventTargetsSelectedThread(params) else { return }
            appendCommandOutputDelta(
                itemID: params?["itemId"]?.stringValue,
                delta: terminalInteractionText(stdin: params?["stdin"]?.stringValue)
            )
        case "item/plan/delta":
            guard eventTargetsSelectedThread(params) else { return }
            appendPlanDelta(itemID: params?["itemId"]?.stringValue, delta: params?["delta"]?.stringValue)
        case "turn/plan/updated":
            guard eventTargetsSelectedThread(params) else { return }
            applyTurnPlanUpdate(turnID: params?["turnId"]?.stringValue, params: params)
        case "turn/diff/updated":
            guard eventTargetsSelectedThread(params) else { return }
            applyTurnDiffUpdate(turnID: params?["turnId"]?.stringValue, diff: params?["diff"]?.stringValue)
        case "item/fileChange/patchUpdated":
            guard eventTargetsSelectedThread(params) else { return }
            if let changes = try? decode([CodexFileChange].self, from: params?["changes"]) {
                applyFileChangePatch(itemID: params?["itemId"]?.stringValue, changes: changes)
            }
        case "item/fileChange/outputDelta":
            guard eventTargetsSelectedThread(params) else { return }
            appendFileChangeOutputDelta(itemID: params?["itemId"]?.stringValue, delta: params?["delta"]?.stringValue)
        case "serverRequest/resolved":
            guard eventTargetsSelectedThread(params) else { return }
            removeResolvedApproval(requestID: params?["requestId"])
        case "item/reasoning/summaryTextDelta":
            guard eventTargetsSelectedThread(params) else { return }
            appendReasoningDelta(
                itemID: params?["itemId"]?.stringValue,
                delta: params?["delta"]?.stringValue,
                index: params?["summaryIndex"]?.intValue,
                target: .summary
            )
        case "item/reasoning/summaryPartAdded":
            guard eventTargetsSelectedThread(params) else { return }
            ensureReasoningPart(itemID: params?["itemId"]?.stringValue, index: params?["summaryIndex"]?.intValue, target: .summary)
        case "item/reasoning/textDelta":
            guard eventTargetsSelectedThread(params) else { return }
            appendReasoningDelta(
                itemID: params?["itemId"]?.stringValue,
                delta: params?["delta"]?.stringValue,
                index: params?["contentIndex"]?.intValue,
                target: .content
            )
        case "item/mcpToolCall/progress":
            guard eventTargetsSelectedThread(params) else { return }
            appendToolProgress(itemID: params?["itemId"]?.stringValue, message: params?["message"]?.stringValue)
        case "turn/started":
            guard eventTargetsSelectedThread(params) else { return }
            if let turn = try? decode(CodexTurn.self, from: params?["turn"]) {
                applyTurnStarted(turn)
            }
        case "turn/completed":
            guard eventTargetsSelectedThread(params) else { return }
            if let turn = try? decode(CodexTurn.self, from: params?["turn"]) {
                applyTurnCompleted(turn)
            }
            await refreshSelectedThreadAfterEvent()
        case "thread/started":
            if let thread = try? decode(CodexThread.self, from: params?["thread"]) {
                let scope = currentThreadLoadScope
                if threadMatchesScope(thread, scope: scope), selectedThreadID == nil {
                    selectedThreadID = thread.id
                    hydrateConversation(from: thread)
                } else if threadMatchesScope(thread, scope: scope), selectedThreadID == thread.id, selectedThread == nil {
                    hydrateConversation(from: thread)
                }
            }
            await refreshThreadListAfterEvent()
        default:
            if method.hasPrefix("thread/") {
                await refreshThreadListAfterEvent()
            }
        }
    }

    private func refreshSelectedThreadAfterEvent() async {
        guard let selectedThreadID, let appServer else { return }
        let scope = currentThreadLoadScope
        do {
            beginSelectedThreadLoad(threadID: selectedThreadID)
            defer {
                endSelectedThreadLoad(threadID: selectedThreadID, scope: scope)
            }
            let thread = try await appServer.readThread(threadID: selectedThreadID)
            guard currentThreadLoadScope == scope, self.selectedThreadID == selectedThreadID else {
                return
            }
            hydrateConversation(from: thread)
            let loadedThreads = try await listThreads(matching: scope)
            guard currentThreadLoadScope == scope else {
                return
            }
            threads = prioritizeActiveThreads(loadedThreads)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshThreadListAfterEvent() async {
        guard let appServer else { return }
        let scope = currentThreadLoadScope
        do {
            let loadedThreads = try await listThreads(matching: scope)
            guard currentThreadLoadScope == scope else {
                return
            }
            threads = prioritizeActiveThreads(loadedThreads)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func handleDisconnected(_ message: String, generation: Int) async {
        guard generation == connectionGeneration else {
            return
        }
        connectionGeneration &+= 1
        eventTask = nil
        let closedAppServer = appServer
        appServer = nil
        pendingApprovals = []
        cancelActiveTurnRefresh()
        await closedAppServer?.close()
        connectionState = .failed(message)
        statusMessage = message
    }

    private func eventTargetsSelectedThread(_ params: JSONValue?) -> Bool {
        guard let selectedThreadID else {
            return false
        }
        let threadID = params?["threadId"]?.stringValue ?? params?["conversationId"]?.stringValue
        guard let threadID else { return false }
        return selectedThreadID == threadID
    }

    private func threadMatchesScope(_ thread: CodexThread, scope: ThreadLoadScope) -> Bool {
        guard !scope.sessionPaths.isEmpty else {
            return true
        }
        return scope.sessionPaths.contains(thread.cwd)
    }

    private func listThreads(matching scope: ThreadLoadScope) async throws -> [CodexThread] {
        guard let appServer else {
            return []
        }
        guard scope.sessionPaths.count > 1 else {
            return try await appServer.listThreads(cwd: scope.cwd)
        }
        var merged: [CodexThread] = []
        var seen = Set<String>()
        for cwd in scope.sessionPaths.sorted() {
            let loaded = try await appServer.listThreads(cwd: cwd)
            for thread in loaded where seen.insert(thread.id).inserted {
                merged.append(thread)
            }
        }
        return merged.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private func applyActiveThreadCounts(_ threads: [CodexThread], to projects: inout [String: ProjectRecord]) {
        for path in projects.keys {
            guard var record = projects[path] else { continue }
            record.threadCount = 0
            record.lastSeenAt = nil
            projects[path] = record
        }

        var projectPathBySessionPath: [String: String] = [:]
        var projectPathByCodexWorktreeName: [String: String] = [:]
        var ambiguousCodexWorktreeNames = Set<String>()
        for (path, record) in projects {
            for sessionPath in ProjectRecord.normalizedSessionPaths(record.sessionPaths, primaryPath: record.path) {
                projectPathBySessionPath[sessionPath] = path
            }
            guard !isCodexWorktreePath(record.path) else { continue }
            let name = URL(fileURLWithPath: record.path).lastPathComponent
            if projectPathByCodexWorktreeName[name] != nil {
                ambiguousCodexWorktreeNames.insert(name)
            } else {
                projectPathByCodexWorktreeName[name] = path
            }
        }
        for name in ambiguousCodexWorktreeNames {
            projectPathByCodexWorktreeName.removeValue(forKey: name)
        }

        for thread in threads {
            let projectPath = projectPathBySessionPath[thread.cwd]
                ?? codexWorktreeMainProjectPath(for: thread.cwd, candidates: projectPathByCodexWorktreeName)
                ?? thread.cwd
            var record = projects[projectPath] ?? ProjectRecord(path: projectPath, discovered: true)
            record.discovered = true
            record.sessionPaths = ProjectRecord.normalizedSessionPaths(record.sessionPaths + [thread.cwd], primaryPath: record.path)
            record.threadCount += 1
            record.lastSeenAt = max(record.lastSeenAt ?? .distantPast, thread.updatedAt)
            projects[projectPath] = record
        }
    }

    private func codexWorktreeMainProjectPath(for cwd: String, candidates: [String: String]) -> String? {
        guard isCodexWorktreePath(cwd) else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return candidates[name]
    }

    private func isCodexWorktreePath(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        guard let codexIndex = components.lastIndex(of: ".codex") else {
            return false
        }
        let worktreesIndex = codexIndex + 1
        let hashIndex = codexIndex + 2
        let projectIndex = codexIndex + 3
        return components.indices.contains(projectIndex)
            && components.indices.contains(hashIndex)
            && components.indices.contains(worktreesIndex)
            && components[worktreesIndex] == "worktrees"
            && !components[hashIndex].isEmpty
            && !components[projectIndex].isEmpty
    }

    private func hydrateConversation(from thread: CodexThread) {
        selectedThread = thread
        liveItems = thread.turns.flatMap(\.items)
        rebuildConversationFromLiveItems()
        if thread.status.isActive {
            scheduleActiveTurnRefresh(threadID: thread.id, scope: currentThreadLoadScope)
        } else if activeTurnRefreshThreadID == thread.id {
            cancelActiveTurnRefresh()
        }
    }

    private func rebuildConversationFromLiveItems() {
        conversationSections = CodexSessionProjection.sections(from: liveItems)
        conversationRevision += 1
    }

    private func beginSelectedThreadLoad(threadID: String) {
        selectedThreadLoadingCounts[threadID, default: 0] += 1
        if selectedThreadID == threadID {
            isSelectedThreadLoading = true
        }
    }

    private func endSelectedThreadLoad(threadID: String, scope: ThreadLoadScope) {
        let nextCount = max((selectedThreadLoadingCounts[threadID] ?? 0) - 1, 0)
        if nextCount == 0 {
            selectedThreadLoadingCounts.removeValue(forKey: threadID)
        } else {
            selectedThreadLoadingCounts[threadID] = nextCount
        }
        guard currentThreadLoadScope == scope, selectedThreadID == threadID else {
            return
        }
        isSelectedThreadLoading = (selectedThreadLoadingCounts[threadID] ?? 0) > 0
    }

    private func clearSelectedThreadLoads() {
        selectedThreadLoadingCounts.removeAll()
        isSelectedThreadLoading = false
    }

    private func upsert(turn: CodexTurn, in thread: inout CodexThread) {
        if let index = thread.turns.firstIndex(where: { $0.id == turn.id }) {
            thread.turns[index] = turn
        } else {
            thread.turns.append(turn)
        }
    }

    private func upsertLiveItem(_ item: CodexThreadItem) {
        if let index = liveItems.firstIndex(where: { $0.id == item.id }) {
            liveItems[index] = item
        } else {
            liveItems.append(item)
        }
        rebuildConversationFromLiveItems()
    }

    private func applyTurnStarted(_ turn: CodexTurn) {
        guard var thread = selectedThread else {
            liveItems.append(contentsOf: turn.items)
            rebuildConversationFromLiveItems()
            return
        }
        thread.status = .active(flags: [])
        upsert(turn: turn, in: &thread)
        selectedThread = thread
        liveItems = thread.turns.flatMap(\.items)
        rebuildConversationFromLiveItems()
        scheduleActiveTurnRefresh(threadID: thread.id, scope: currentThreadLoadScope)
    }

    private func applyTurnCompleted(_ turn: CodexTurn) {
        guard var thread = selectedThread else {
            liveItems = turn.items
            rebuildConversationFromLiveItems()
            cancelActiveTurnRefresh()
            return
        }
        thread.status = .idle
        upsert(turn: turn, in: &thread)
        selectedThread = thread
        liveItems = thread.turns.flatMap(\.items)
        rebuildConversationFromLiveItems()
        cancelActiveTurnRefresh()
    }

    private func scheduleActiveTurnRefresh(threadID: String, scope: ThreadLoadScope) {
        guard appServer != nil else { return }
        if activeTurnRefreshThreadID == threadID, activeTurnRefreshTask != nil {
            return
        }
        cancelActiveTurnRefresh()
        activeTurnRefreshThreadID = threadID
        let generation = connectionGeneration
        let interval = activeTurnRefreshIntervalNanoseconds
        activeTurnRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled {
                    return
                }
                await self?.refreshActiveTurnIfStillSelected(threadID: threadID, scope: scope, generation: generation)
            }
        }
    }

    private func refreshActiveTurnIfStillSelected(threadID: String, scope: ThreadLoadScope, generation: Int) async {
        guard generation == connectionGeneration,
              currentThreadLoadScope == scope,
              selectedThreadID == threadID,
              let appServer
        else {
            cancelActiveTurnRefresh()
            return
        }

        do {
            beginSelectedThreadLoad(threadID: threadID)
            defer {
                endSelectedThreadLoad(threadID: threadID, scope: scope)
            }
            let thread = try await appServer.readThread(threadID: threadID)
            guard generation == connectionGeneration,
                  currentThreadLoadScope == scope,
                  selectedThreadID == threadID
            else {
                cancelActiveTurnRefresh()
                return
            }
            guard !thread.status.isActive else {
                return
            }
            hydrateConversation(from: thread)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func cancelActiveTurnRefresh() {
        activeTurnRefreshTask?.cancel()
        activeTurnRefreshTask = nil
        activeTurnRefreshThreadID = nil
    }

    private func appendAgentMessageDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .agentMessage(let id, let text) = liveItems[index] {
            liveItems[index] = .agentMessage(id: id, text: text + delta)
        } else {
            liveItems.append(.agentMessage(id: itemID, text: delta))
        }
        rebuildConversationFromLiveItems()
    }

    private func appendCommandOutputDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .command(let id, let command, let cwd, let status, let output) = liveItems[index] {
            liveItems[index] = .command(id: id, command: command, cwd: cwd, status: status, output: (output ?? "") + delta)
        } else {
            liveItems.append(.command(id: itemID, command: "Command", cwd: "", status: "inProgress", output: delta))
        }
        rebuildConversationFromLiveItems()
    }

    private func appendPlanDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .plan(let id, let text) = liveItems[index] {
            liveItems[index] = .plan(id: id, text: text + delta)
        } else {
            liveItems.append(.plan(id: itemID, text: delta))
        }
        rebuildConversationFromLiveItems()
    }

    private func applyTurnPlanUpdate(turnID: String?, params: JSONValue?) {
        guard let turnID else { return }
        let itemID = "turn-plan-\(turnID)"
        let text = turnPlanText(explanation: params?["explanation"]?.stringValue, plan: params?["plan"])
        guard !text.isEmpty else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .plan(let id, _) = liveItems[index] {
            liveItems[index] = .plan(id: id, text: text)
        } else {
            liveItems.append(.plan(id: itemID, text: text))
        }
        rebuildConversationFromLiveItems()
    }

    private func applyTurnDiffUpdate(turnID: String?, diff: String?) {
        guard let turnID, let diff, !diff.isEmpty else { return }
        let itemID = "turn-diff-\(turnID)"
        let change = CodexFileChange(path: "Turn diff", diff: diff)
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .fileChange = liveItems[index] {
            liveItems[index] = .fileChange(id: itemID, changes: [change], status: "inProgress")
        } else {
            liveItems.append(.fileChange(id: itemID, changes: [change], status: "inProgress"))
        }
        rebuildConversationFromLiveItems()
    }

    private func turnPlanText(explanation: String?, plan: JSONValue?) -> String {
        var lines: [String] = []
        if let explanation, !explanation.isEmpty {
            lines.append(explanation)
        }
        if case .array(let steps) = plan {
            lines.append(contentsOf: steps.compactMap { step in
                guard case .object(let object) = step,
                      let title = object["step"]?.stringValue,
                      !title.isEmpty else {
                    return nil
                }
                let status = object["status"]?.stringValue ?? "pending"
                return "[\(status)] \(title)"
            })
        }
        return lines.joined(separator: "\n")
    }

    private func applyFileChangePatch(itemID: String?, changes: [CodexFileChange]) {
        guard let itemID else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .fileChange(_, _, let status) = liveItems[index] {
            liveItems[index] = .fileChange(id: itemID, changes: changes, status: status.isEmpty ? "inProgress" : status)
        } else {
            liveItems.append(.fileChange(id: itemID, changes: changes, status: "inProgress"))
        }
        rebuildConversationFromLiveItems()
    }

    private func appendToolProgress(itemID: String?, message: String?) {
        guard let itemID, let message, !message.isEmpty else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .toolCall(let id, let label, _, let detail) = liveItems[index] {
            let nextDetail = [detail, message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            liveItems[index] = .toolCall(id: id, label: label, status: "inProgress", detail: nextDetail)
        } else {
            liveItems.append(.toolCall(id: itemID, label: "MCP tool", status: "inProgress", detail: message))
        }
        rebuildConversationFromLiveItems()
    }

    private func terminalInteractionText(stdin: String?) -> String? {
        guard let stdin, !stdin.isEmpty else { return nil }
        return "\nstdin: \(stdin)"
    }

    private func removeResolvedApproval(requestID: JSONValue?) {
        guard let requestID else { return }
        pendingApprovals.removeAll { $0.requestID == requestID }
    }

    private func appendFileChangeOutputDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        let patchOutput = CodexFileChange(path: "", diff: delta)
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .fileChange(_, var changes, let status) = liveItems[index] {
            if changes.isEmpty {
                changes.append(patchOutput)
            } else {
                changes[changes.index(before: changes.endIndex)].diff += delta
            }
            liveItems[index] = .fileChange(id: itemID, changes: changes, status: status.isEmpty ? "inProgress" : status)
        } else {
            liveItems.append(.fileChange(id: itemID, changes: [patchOutput], status: "inProgress"))
        }
        rebuildConversationFromLiveItems()
    }

    private enum ReasoningDeltaTarget {
        case summary
        case content
    }

    private func appendReasoningDelta(itemID: String?, delta: String?, index: Int?, target: ReasoningDeltaTarget) {
        guard let itemID, let delta, let index else { return }
        updateReasoning(itemID: itemID) { summary, content in
            switch target {
            case .summary:
                summary = appending(delta, to: summary, at: index)
            case .content:
                content = appending(delta, to: content, at: index)
            }
        }
    }

    private func ensureReasoningPart(itemID: String?, index: Int?, target: ReasoningDeltaTarget) {
        guard let itemID, let index else { return }
        updateReasoning(itemID: itemID) { summary, content in
            switch target {
            case .summary:
                summary = appending("", to: summary, at: index)
            case .content:
                content = appending("", to: content, at: index)
            }
        }
    }

    private func updateReasoning(
        itemID: String,
        update: (_ summary: inout [String], _ content: inout [String]) -> Void
    ) {
        var summary: [String] = []
        var content: [String] = []
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .reasoning(_, let currentSummary, let currentContent) = liveItems[index] {
            summary = currentSummary
            content = currentContent
            update(&summary, &content)
            liveItems[index] = .reasoning(id: itemID, summary: summary, content: content)
        } else {
            update(&summary, &content)
            liveItems.append(.reasoning(id: itemID, summary: summary, content: content))
        }
        rebuildConversationFromLiveItems()
    }

    private func appending(_ delta: String, to values: [String], at index: Int) -> [String] {
        var next = values
        while next.count <= index {
            next.append("")
        }
        next[index] += delta
        return next
    }

    private func resetSessionState(clearThreads: Bool) {
        cancelActiveTurnRefresh()
        if clearThreads {
            threads = []
        }
        selectedThreadID = nil
        selectedThread = nil
        liveItems = []
        conversationSections = []
        conversationRevision += 1
        clearSelectedThreadLoads()
        pendingApprovals = []
    }

    private func normalizedCredential(for authMethod: ServerAuthMethod, credential: SSHCredential) -> SSHCredential {
        switch authMethod {
        case .password:
            SSHCredential(password: credential.password, privateKeyPEM: nil, privateKeyPassphrase: nil)
        case .privateKey:
            SSHCredential(password: nil, privateKeyPEM: credential.privateKeyPEM, privateKeyPassphrase: credential.privateKeyPassphrase)
        }
    }

    private func credentialIsUsable(_ credential: SSHCredential, authMethod: ServerAuthMethod) -> Bool {
        switch authMethod {
        case .password:
            !(credential.password ?? "").isEmpty
        case .privateKey:
            !(credential.privateKeyPEM ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func credentialRequiredMessage(for authMethod: ServerAuthMethod) -> String {
        switch authMethod {
        case .password:
            "Enter the SSH password for this server."
        case .privateKey:
            "Paste an OpenSSH private key for this server."
        }
    }

    private func approvalResponse(for approval: PendingApproval, accept: Bool) -> JSONValue? {
        switch approval.method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            return .object([
                "decision": .string(accept ? "accept" : "decline")
            ])
        case "execCommandApproval", "applyPatchApproval":
            return .object([
                "decision": .string(accept ? "approved" : "denied")
            ])
        case "item/permissions/requestApproval":
            return .object([
                "permissions": accept ? (approval.params?["permissions"] ?? .object([:])) : .object([:]),
                "scope": .string("turn")
            ])
        case "account/chatgptAuthTokens/refresh":
            statusMessage = "Mobidex cannot refresh remote ChatGPT auth tokens yet."
            return nil
        case "mcpServer/elicitation/request":
            guard !accept else {
                statusMessage = "Mobidex cannot answer MCP elicitations yet."
                return nil
            }
            return .object([
                "action": .string("decline"),
                "content": .null,
                "_meta": .null
            ])
        case "item/tool/requestUserInput":
            guard !accept else {
                statusMessage = "Mobidex cannot answer tool input forms yet."
                return nil
            }
            return .object(["answers": .object([:])])
        case "item/tool/call":
            guard !accept else {
                statusMessage = "Mobidex cannot run dynamic tools yet."
                return nil
            }
            return .object([
                "contentItems": .array([]),
                "success": .bool(false)
            ])
        default:
            guard !accept else {
                statusMessage = "Mobidex cannot approve \(approval.method) yet."
                return nil
            }
            return .object(["decision": .string("decline")])
        }
    }

    private func approvalTitle(method: String, params: JSONValue?) -> String {
        switch method {
        case "item/commandExecution/requestApproval":
            "Command approval"
        case "item/fileChange/requestApproval":
            "File change approval"
        case "item/permissions/requestApproval":
            "Permission approval"
        case "item/tool/requestUserInput":
            "Input requested"
        case "mcpServer/elicitation/request":
            "MCP input requested"
        case "execCommandApproval":
            "Command approval"
        case "applyPatchApproval":
            "Patch approval"
        case "account/chatgptAuthTokens/refresh":
            "Auth refresh requested"
        default:
            method
        }
    }

    private func approvalDetail(params: JSONValue?) -> String {
        [
            params?["cwd"]?.stringValue,
            params?["reason"]?.stringValue,
            params?["command"].flatMap(commandDetail),
            params?["grantRoot"]?.stringValue.map { "Grant root: \($0)" },
            params?["itemId"]?.stringValue.map { "Item: \($0)" },
            params?["conversationId"]?.stringValue.map { "Thread: \($0)" },
            params?["callId"]?.stringValue.map { "Call: \($0)" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func commandDetail(_ value: JSONValue) -> String? {
        switch value {
        case .string(let command):
            return command.isEmpty ? nil : command
        case .array(let parts):
            let command = parts.compactMap(\.stringValue).joined(separator: " ")
            return command.isEmpty ? nil : command
        default:
            return nil
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue?) throws -> T {
        guard let value else {
            throw CodexAppServerClientError.invalidResponse
        }
        let data = try jsonEncoder.encode(value)
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func runBusy(_ status: String, operation: () async throws -> Void) async {
        isBusy = true
        statusMessage = status
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            connectionState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }
}
