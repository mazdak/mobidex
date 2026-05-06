import Foundation

struct PendingApproval: Identifiable, Equatable {
    var id: String
    var requestID: JSONValue
    var method: String
    var params: JSONValue?
    var title: String
    var detail: String
}

private extension CodexThreadItem {
    var mergeScore: Int {
        switch self {
        case .userMessage(_, let text),
             .agentMessage(_, let text),
             .plan(_, let text):
            text.count
        case .reasoning(_, let summary, let content):
            (summary + content).reduce(0) { $0 + $1.count }
        case .command(_, let command, let cwd, let status, let output):
            command.count + cwd.count + status.count + (output?.count ?? 0)
        case .fileChange(_, let changes, let status):
            status.count + changes.reduce(0) { $0 + $1.path.count + $1.diff.count }
        case .toolCall(_, let label, let status, let detail),
             .agentEvent(_, let label, let status, let detail):
            label.count + status.count + (detail?.count ?? 0)
        case .webSearch(_, let query),
             .image(_, let query),
             .review(_, let query):
            query.count
        case .contextCompaction:
            1
        case .unknown(_, let type):
            type.count
        }
    }
}

struct StatusAlert: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var message: String
}

struct AppServerReconnectStatus: Equatable {
    var attempt: Int
    var maxAttempts: Int
    var delayNanoseconds: UInt64

    var delaySeconds: Double {
        Double(delayNanoseconds) / 1_000_000_000
    }

    var label: String {
        let seconds = delaySeconds
        if delayNanoseconds == 0 {
            return "Reconnecting \(attempt)/\(maxAttempts)"
        }
        let delayLabel = seconds >= 1
            ? "\(Int(seconds.rounded()))s"
            : "\(Int((seconds * 1_000).rounded()))ms"
        return "Reconnect \(attempt)/\(maxAttempts) in \(delayLabel)"
    }
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

private enum AppOperation: Hashable {
    case testingConnection
    case connecting
    case discoveringProjects
    case refreshingSessions
    case openingThread
    case startingSession
    case sending
    case interrupting
    case refreshingChangedFiles
    case respondingToApproval
}

private enum ActiveTurnSendBehavior {
    case queue
    case steer
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
    @Published private(set) var conversationRenderToken = 0
    @Published private(set) var conversationFollowToken = 0
    @Published private(set) var conversationSendToken = 0
    @Published private(set) var conversationRenderDigest = ""
    @Published private(set) var pendingApprovals: [PendingApproval] = []
    @Published private(set) var connectionState: ServerConnectionState = .disconnected
    @Published private(set) var appServerReconnectStatus: AppServerReconnectStatus?
    @Published private(set) var statusMessage: String?
    @Published var statusAlert: StatusAlert?
    @Published private(set) var changedFiles: [String] = []
    @Published private(set) var diffSnapshot: GitDiffSnapshot = .empty
    @Published private(set) var queuedTurnInputCount = 0
    @Published private(set) var selectedThreadTokenUsage: CodexTokenUsage?
    @Published private(set) var switchingServerID: UUID?
    @Published var selectedReasoningEffort: CodexReasoningEffortOption = .medium
    @Published var selectedAccessMode: CodexAccessMode = .fullAccess
    @Published private var activeOperationCounts: [AppOperation: Int] = [:]

    private let repository: ServerRepository
    private let credentialStore: CredentialStore
    private let sshService: SSHService
    private let activeTurnRefreshIntervalNanoseconds: UInt64
    private let appServerReconnectDelayNanoseconds: UInt64
    private let maxAppServerReconnectAttempts: Int
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private var appServer: CodexAppServerClient?
    private var eventTask: Task<Void, Never>?
    private var appServerReconnectTask: Task<Void, Never>?
    private var activeTurnRefreshTask: Task<Void, Never>?
    private var activeTurnRefreshThreadID: String?
    private var connectionGeneration = 0
    private var sidebarSwitchGeneration = 0
    private var liveItems: [CodexThreadItem] = []
    private var selectedThreadLoadingCounts: [String: Int] = [:]
    private var queuedTurnInputsByThreadID: [String: [[CodexInputItem]]] = [:]
    private var isConnectingAppServer = false
    private var didLoadServers = false
    private var autoConnectAttemptedServerIDs = Set<UUID>()
    private var appServerReconnectAttemptsByServerID: [UUID: Int] = [:]

    init(
        repository: ServerRepository,
        credentialStore: CredentialStore,
        sshService: SSHService,
        activeTurnRefreshIntervalNanoseconds: UInt64 = 1_000_000_000,
        appServerReconnectDelayNanoseconds: UInt64 = 500_000_000,
        maxAppServerReconnectAttempts: Int = 3,
        loadServersOnInit: Bool = true
    ) {
        self.repository = repository
        self.credentialStore = credentialStore
        self.sshService = sshService
        self.activeTurnRefreshIntervalNanoseconds = activeTurnRefreshIntervalNanoseconds
        self.appServerReconnectDelayNanoseconds = appServerReconnectDelayNanoseconds
        self.maxAppServerReconnectAttempts = maxAppServerReconnectAttempts
        if loadServersOnInit {
            loadServers()
        }
    }

    static func appServerReconnectDelayNanoseconds(baseDelayNanoseconds: UInt64, attempt: Int) -> UInt64 {
        let fallbackBaseDelay: UInt64 = 10_000_000
        let cappedBaseDelay = max(baseDelayNanoseconds, fallbackBaseDelay)
        let cappedAttempt = max(min(attempt, 5), 1)
        let multiplier = UInt64(1) << UInt64(cappedAttempt - 1)
        let maxDelay: UInt64 = 8_000_000_000
        let multiplied = cappedBaseDelay.multipliedReportingOverflow(by: multiplier)
        guard !multiplied.overflow else {
            return maxDelay
        }
        return min(multiplied.partialValue, maxDelay)
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
        appServer != nil && !isSelectedThreadLoading && !isSessionMutationInFlight
    }

    var canInterruptActiveTurn: Bool {
        appServer != nil && activeTurnID != nil
    }

    var isAppServerConnected: Bool {
        appServer != nil
    }

    var isBusy: Bool {
        activeOperationCounts.values.contains { $0 > 0 }
    }

    var canCreateSession: Bool {
        appServer != nil && !isSessionMutationInFlight
    }

    var contextUsageFraction: Double? {
        selectedThreadTokenUsage?.contextFraction
    }

    var contextUsagePercent: Int? {
        contextUsageFraction.map { min(max(Int(($0 * 100).rounded()), 0), 100) }
    }

    var selectedActivityLabel: String? {
        guard selectedThread?.status.isActive == true else {
            return nil
        }
        if isOperationActive(.sending) {
            return "Sending"
        }
        for item in liveItems.reversed() {
            switch item {
            case .reasoning:
                return "Thinking"
            case .command(_, _, _, let status, _),
                 .fileChange(_, _, let status),
                 .toolCall(_, _, let status, _),
                 .agentEvent(_, _, let status, _):
                guard !Self.isTerminalItemStatus(status) else {
                    continue
                }
                return status.isEmpty ? "Working" : status.capitalized
            case .agentMessage:
                return "Responding"
            default:
                continue
            }
        }
        return "Thinking"
    }

    var isRefreshingChanges: Bool {
        isOperationActive(.refreshingChangedFiles)
    }

    func loadCredential(for serverID: UUID) async -> SSHCredential {
        (try? await loadCredentialFromStore(serverID: serverID)) ?? SSHCredential()
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
        if let serverID {
            autoConnectAttemptedServerIDs.remove(serverID)
            appServerReconnectAttemptsByServerID.removeValue(forKey: serverID)
        }
        appServerReconnectTask?.cancel()
        appServerReconnectTask = nil
        appServerReconnectStatus = nil
        connectionState = .disconnected
        statusMessage = nil
        resetSessionState(clearThreads: true)
        pendingApprovals = []
        return true
    }

    @discardableResult
    func switchServerFromSidebar(_ serverID: UUID?) async -> Bool {
        sidebarSwitchGeneration &+= 1
        let switchGeneration = sidebarSwitchGeneration
        if selectedServerID == serverID {
            switchingServerID = nil
            statusMessage = nil
            return true
        }
        switchingServerID = serverID
        if let serverID,
           let server = servers.first(where: { $0.id == serverID }) {
            statusMessage = "Switching to \(server.displayName)"
        } else {
            statusMessage = "Switching servers"
        }
        defer {
            if sidebarSwitchGeneration == switchGeneration {
                switchingServerID = nil
            }
        }
        if isConnectingAppServer {
            connectionGeneration &+= 1
            isConnectingAppServer = false
            connectionState = .disconnected
        }
        if connectionState == .connected || connectionState == .connecting || appServer != nil {
            await closeConnection(updateState: false)
            connectionState = .disconnected
        }
        guard sidebarSwitchGeneration == switchGeneration else {
            return false
        }
        return selectServer(serverID)
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
    func saveServer(_ server: ServerRecord, credential: SSHCredential, connectAfterSave: Bool = false) async -> Bool {
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
        next.targetShellRCFile = next.targetShellRCFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.targetShellRCFile.isEmpty {
            next.targetShellRCFile = "$HOME/.zshrc"
        }
        next.updatedAt = .now

        do {
            let previousCredential = try await loadCredentialFromStore(serverID: next.id)
            do {
                try await saveCredentialToStore(normalizedCredential, serverID: next.id)
            } catch {
                try? await saveCredentialToStore(previousCredential, serverID: next.id)
                throw error
            }

            autoConnectAttemptedServerIDs.remove(next.id)
            appServerReconnectAttemptsByServerID.removeValue(forKey: next.id)
            let wasSelected = selectedServerID == next.id
            let shouldDisconnectSavedSelection = wasSelected && (appServer != nil || connectionState == .connecting)

            var nextServers = servers
            if let index = nextServers.firstIndex(where: { $0.id == server.id }) {
                next.createdAt = nextServers[index].createdAt
                next.projects = nextServers[index].projects
                nextServers[index] = next
            } else {
                nextServers.append(next)
            }

            if shouldDisconnectSavedSelection {
                nextServers = serversClearingOpenSessionCounts(nextServers)
            }

            do {
                try persistServers(nextServers)
            } catch {
                try? await saveCredentialToStore(previousCredential, serverID: next.id)
                throw error
            }
            servers = nextServers
            if shouldDisconnectSavedSelection {
                await disconnect()
            }
            let shouldSelectSavedServer = selectedServerID == nil
                || wasSelected
                || (connectionState != .connected && connectionState != .connecting)
            if shouldSelectSavedServer {
                selectedServerID = next.id
                selectedProjectID = next.projects.first?.id
                connectionState = .disconnected
                resetSessionState(clearThreads: true)
            }
            statusMessage = "Saved \(next.displayName)."
            if connectAfterSave {
                let savedServerID = next.id
                Task { [weak self] in
                    await self?.connectSavedServerIfStillSelected(savedServerID)
                }
            }
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
            oldCredential = try await loadCredentialFromStore(serverID: server.id)
        } catch {
            statusMessage = error.localizedDescription
            return false
        }

        do {
            try await deleteCredentialFromStore(serverID: server.id)
        } catch {
            try? await saveCredentialToStore(oldCredential, serverID: server.id)
            statusMessage = error.localizedDescription
            return false
        }

        do {
            try persistServers(nextServers)
            autoConnectAttemptedServerIDs.remove(server.id)
            appServerReconnectAttemptsByServerID.removeValue(forKey: server.id)
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
            try? await saveCredentialToStore(oldCredential, serverID: server.id)
            statusMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func addProject(path: String) -> Bool {
        guard let selectedServerID else {
            statusMessage = "Select a server before adding a project."
            return false
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a remote project path."
            return false
        }

        var nextServers = servers
        guard let index = nextServers.firstIndex(where: { $0.id == selectedServerID }) else {
            statusMessage = "The selected server is no longer available."
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
            statusMessage = "Added \(project.displayName)."
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
        await runOperation(.testingConnection, status: "Testing connection", marksConnectionFailure: true) {
            let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
            try await sshService.testConnection(server: selectedServer, credential: credential)
            if appServer == nil {
                connectionState = .disconnected
            }
            let message = "Connection test passed for \(selectedServer.displayName)."
            statusMessage = message
            statusAlert = StatusAlert(title: "Connection Test Passed", message: message)
        }
        if case .failed(let message) = connectionState {
            statusAlert = StatusAlert(title: "Connection Test Failed", message: message)
        }
    }

    func ensureSelectedServerConnected() async {
        guard let serverID = selectedServerID else {
            return
        }
        await autoConnectSelectedServer(serverID)
    }

    private func connectSavedServerIfStillSelected(_ serverID: UUID) async {
        await autoConnectSelectedServer(serverID)
    }

    func loadServersIfNeeded() async {
        guard !didLoadServers else {
            return
        }
        didLoadServers = true
        do {
            let repository = repository
            let loadedServers = try await Task.detached(priority: .userInitiated) {
                try repository.loadServers()
            }.value
            let normalizedServers = serversClearingOpenSessionCounts(loadedServers)
            servers = normalizedServers
            if normalizedServers != loadedServers {
                try? persistServers(normalizedServers)
            }
            if selectedServerID == nil {
                selectedServerID = servers.first?.id
                selectedProjectID = selectedServer?.projects.first?.id
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func autoConnectSelectedServer(_ serverID: UUID) async {
        guard selectedServerID == serverID,
              !autoConnectAttemptedServerIDs.contains(serverID),
              !isAppServerConnected,
              !isConnectingAppServer
        else {
            return
        }
        autoConnectAttemptedServerIDs.insert(serverID)
        await connectSelectedServer(syncActiveChatCounts: true)
        if selectedServerID != serverID {
            autoConnectAttemptedServerIDs.remove(serverID)
        }
    }

    func connectSelectedServer(syncActiveChatCounts: Bool = false) async {
        await connectSelectedServer(syncActiveChatCounts: syncActiveChatCounts, preservingVisibleState: false)
    }

    private func connectSelectedServer(syncActiveChatCounts: Bool, preservingVisibleState: Bool) async {
        guard !isConnectingAppServer else { return }
        guard let targetServer = selectedServer else { return }
        isConnectingAppServer = true
        connectionState = .connecting
        defer {
            isConnectingAppServer = false
        }
        await closeConnection(
            updateState: false,
            clearOpenSessionCounts: !preservingVisibleState,
            cancelReconnect: !preservingVisibleState
        )
        var connectGeneration = connectionGeneration
        guard selectedServerID == targetServer.id else {
            connectionState = .disconnected
            statusMessage = AppViewModelError.selectionChanged.localizedDescription
            return
        }
        var credential: SSHCredential?
        let didConnect = await runOperation(.connecting, status: "Connecting", marksConnectionFailure: true) {
            connectionState = .connecting
            guard selectedServerID == targetServer.id else {
                throw AppViewModelError.selectionChanged
            }
            let loadedCredential = try await loadCredentialFromStore(serverID: targetServer.id)
            credential = loadedCredential
            guard selectedServerID == targetServer.id, connectionGeneration == connectGeneration else {
                credential = nil
                return
            }
            let connectedAppServer: CodexAppServerClient
            do {
                connectedAppServer = try await sshService.openAppServer(server: targetServer, credential: loadedCredential)
            } catch {
                guard selectedServerID == targetServer.id, connectionGeneration == connectGeneration else {
                    credential = nil
                    return
                }
                throw error
            }
            guard selectedServerID == targetServer.id, connectionGeneration == connectGeneration else {
                await connectedAppServer.close()
                credential = nil
                return
            }
            appServer = connectedAppServer
            startEventLoop()
            connectGeneration = connectionGeneration
            connectionState = .connected
            statusMessage = "App-server connected."
        }

        guard didConnect, let credential else {
            return
        }
        appServerReconnectAttemptsByServerID.removeValue(forKey: targetServer.id)
        appServerReconnectStatus = nil

        var syncSucceeded = true
        syncSucceeded = await runOperation(.discoveringProjects, status: "Syncing projects") {
            try await refreshProjectsUsingCredential(credential, server: targetServer, syncActiveChatCounts: syncActiveChatCounts)
        } && syncSucceeded

        guard connectionStillMatches(targetServer.id, generation: connectGeneration) else {
            if disconnectedFromTargetServer(targetServer.id) {
                return
            }
            markSelectionChanged()
            return
        }

        syncSucceeded = await runOperation(.refreshingSessions, status: "Refreshing sessions") {
            try await loadThreads()
        } && syncSucceeded

        if syncSucceeded, connectionState == .connected, connectionGeneration == connectGeneration {
            statusMessage = "App-server connected."
        }
    }

    func refreshProjects() async {
        guard let selectedServer else { return }
        await runOperation(.discoveringProjects, status: "Discovering projects") {
            let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
            try await refreshProjectsUsingCredential(credential, server: selectedServer, syncActiveChatCounts: true)
        }
    }

    func refreshThreads() async {
        await runOperation(.refreshingSessions, status: "Refreshing sessions") {
            try await loadThreads()
        }
    }

    func openThread(_ thread: CodexThread) async {
        let scope = currentThreadLoadScope
        selectedThreadID = thread.id
        selectedThreadTokenUsage = nil
        hydrateConversation(from: thread)
        beginSelectedThreadLoad(threadID: thread.id)
        await runOperation(.openingThread, status: "Opening session") {
            defer {
                endSelectedThreadLoad(threadID: thread.id, scope: scope)
            }
            guard let appServer else {
                return
            }
            let hydrated = try await resumeThreadForAttachment(thread.id, appServer: appServer)
            guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                return
            }
            selectedThreadID = hydrated.id
            hydrateConversation(from: hydrated)
        }
    }

    func startNewSession() async {
        guard selectedProject != nil else { return }
        guard appServer != nil else {
            statusMessage = "Connect to the app-server before starting a new session."
            return
        }
        guard !isOperationActive(.startingSession) else { return }
        let scope = currentThreadLoadScope
        await runOperation(.startingSession, status: "Starting session") {
            guard let appServer else {
                statusMessage = "Connect to the app-server before starting a new session."
                return
            }
            let thread = try await appServer.startThread(cwd: scope.cwd)
            guard currentThreadLoadScope == scope, threadMatchesScope(thread, scope: scope) else {
                return
            }
            selectedThreadID = thread.id
            selectedThreadTokenUsage = nil
            hydrateConversation(from: thread)
            threads = prioritizeActiveThreads([thread] + threads.filter { $0.id != thread.id })
            statusMessage = "New session created."
        }
    }

    @discardableResult
    func sendComposerText(_ text: String) async -> Bool {
        await sendComposerInput(text: text, localImagePaths: [])
    }

    @discardableResult
    func sendComposerInput(text: String, localAttachmentPaths: [String]) async -> Bool {
        await sendComposerInput(text: text, localPaths: localAttachmentPaths, activeTurnBehavior: .queue)
    }

    @discardableResult
    func sendComposerInput(text: String, localAttachmentPaths: [String], queueWhenActive: Bool) async -> Bool {
        await sendComposerInput(
            text: text,
            localPaths: localAttachmentPaths,
            activeTurnBehavior: queueWhenActive ? .queue : .steer
        )
    }

    @discardableResult
    func sendComposerInput(text: String, localImagePaths: [String]) async -> Bool {
        await sendComposerInput(text: text, localPaths: localImagePaths, activeTurnBehavior: .queue)
    }

    @discardableResult
    func steerComposerText(_ text: String) async -> Bool {
        await sendComposerInput(text: text, localPaths: [], activeTurnBehavior: .steer)
    }

    @discardableResult
    private func sendComposerInput(
        text: String,
        localPaths: [String],
        activeTurnBehavior: ActiveTurnSendBehavior
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var input: [CodexInputItem] = []
        if !trimmed.isEmpty {
            input.append(.text(trimmed))
        }
        let localPaths = localPaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return await sendInputItems(input, localAttachmentPaths: localPaths, activeTurnBehavior: activeTurnBehavior)
    }

    @discardableResult
    func sendComposerText(_ text: String, queueWhenActive: Bool) async -> Bool {
        await sendComposerInput(
            text: text,
            localPaths: [],
            activeTurnBehavior: queueWhenActive ? .queue : .steer
        )
    }

    func queueComposerText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let selectedThreadID else {
            _ = await sendComposerText(trimmed)
            return
        }
        guard selectedThread?.status.isActive == true else {
            _ = await sendComposerText(trimmed)
            return
        }
        queuedTurnInputsByThreadID[selectedThreadID, default: []].append([.text(trimmed)])
        refreshQueuedTurnInputCount()
        statusMessage = "Queued message for after the current turn."
    }

    @discardableResult
    func refreshChangedFilesForSelectedProject() async -> [String] {
        let snapshot = await refreshDiffSnapshot()
        return snapshot.files.map(\.path)
    }

    @discardableResult
    func refreshDiffSnapshot(cwd explicitCwd: String? = nil) async -> GitDiffSnapshot {
        guard appServer != nil else {
            statusMessage = "Connect to the app-server before checking changed files."
            return .empty
        }
        let scope = currentThreadLoadScope
        guard let cwd = explicitCwd ?? scope.cwd, !cwd.isEmpty else {
            statusMessage = "Select a project before checking changed files."
            return .empty
        }

        var refreshedSnapshot: GitDiffSnapshot = .empty
        await runOperation(.refreshingChangedFiles, status: "Checking changed files") {
            guard let appServer else { return }
            let snapshot = try await appServer.diffSnapshot(cwd: cwd)
            guard currentThreadLoadScope == scope else {
                return
            }
            if explicitCwd != nil, selectedThread?.cwd != cwd {
                return
            }
            diffSnapshot = snapshot
            changedFiles = snapshot.files.map(\.path)
            refreshedSnapshot = snapshot
        }
        return refreshedSnapshot
    }

    private func sendInputItems(
        _ baseInput: [CodexInputItem],
        localAttachmentPaths: [String] = [],
        activeTurnBehavior: ActiveTurnSendBehavior = .queue
    ) async -> Bool {
        guard !baseInput.isEmpty || !localAttachmentPaths.isEmpty else { return false }
        guard appServer != nil else {
            statusMessage = "Connect to the app-server before sending a message."
            return false
        }
        guard !isSelectedThreadLoading else {
            statusMessage = "Wait for the session to finish loading before sending a message."
            return false
        }
        guard !isOperationActive(.sending) else { return false }

        let scope = currentThreadLoadScope
        let startingThreadID = selectedThreadID
        let startingThread = selectedThread
        var didSubmitInput = false
        let sent = await runOperation(.sending, status: localAttachmentPaths.isEmpty ? "Sending" : "Uploading attachments") {
            guard let appServer else { return }
            guard currentThreadLoadScope == scope else { return }
            var input = baseInput
            if !localAttachmentPaths.isEmpty {
                input.append(contentsOf: try await stageLocalAttachmentInputs(localAttachmentPaths))
                guard currentThreadLoadScope == scope else { return }
            }
            guard !input.isEmpty else { return }
            guard selectedThreadID == startingThreadID else {
                statusMessage = "The selected session changed before the message could be sent."
                return
            }
            if let startingThread, selectedThread?.id != startingThread.id {
                statusMessage = "The selected session changed before the message could be sent."
                return
            }
            var thread: CodexThread
            var shouldHydrateThreadsAfterSend = true
            if let startingThread {
                thread = selectedThread ?? startingThread
            } else if startingThreadID != nil {
                statusMessage = "The selected session changed before the message could be sent."
                return
            } else {
                thread = try await appServer.startThread(cwd: scope.cwd)
                let selectionMatchesStartedThread = selectedThreadID == startingThreadID
                    || (startingThreadID == nil && selectedThreadID == thread.id)
                guard currentThreadLoadScope == scope, selectionMatchesStartedThread, threadMatchesScope(thread, scope: scope) else {
                    return
                }
                selectedThreadID = thread.id
                refreshQueuedTurnInputCount()
            }

            if thread.status.isActive {
                if activeTurnBehavior == .queue {
                    if activeTurnID == nil {
                        beginSelectedThreadLoad(threadID: thread.id)
                        defer {
                            endSelectedThreadLoad(threadID: thread.id, scope: scope)
                        }
                        let hydrated = try await appServer.readThread(threadID: thread.id)
                        guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                            return
                        }
                        hydrateConversation(from: hydrated)
                        thread = hydrated
                    }
                    if thread.status.isActive {
                        queuedTurnInputsByThreadID[thread.id, default: []].append(input)
                        refreshQueuedTurnInputCount()
                        statusMessage = "Queued message for after the current turn."
                        didSubmitInput = true
                        return
                    }
                }
                if thread.status.isActive, activeTurnBehavior == .steer, activeTurnID == nil {
                    beginSelectedThreadLoad(threadID: thread.id)
                    defer {
                        endSelectedThreadLoad(threadID: thread.id, scope: scope)
                    }
                    let hydrated = try await appServer.readThread(threadID: thread.id)
                    guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                        return
                    }
                    hydrateConversation(from: hydrated)
                    thread = hydrated
                }
                if thread.status.isActive, activeTurnBehavior == .steer {
                    guard let activeTurnID else {
                        queuedTurnInputsByThreadID[thread.id, default: []].append(input)
                        refreshQueuedTurnInputCount()
                        statusMessage = "Queued message until the active turn is available."
                        didSubmitInput = true
                        return
                    }
                    try await appServer.steer(threadID: thread.id, expectedTurnID: activeTurnID, input: input)
                    guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                        return
                    }
                    didSubmitInput = true
                    shouldHydrateThreadsAfterSend = false
                }
            }
            if !thread.status.isActive {
                let turn = try await appServer.startTurn(
                    threadID: thread.id,
                    input: input,
                    options: currentTurnOptions(cwd: thread.cwd)
                )
                guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                    return
                }
                didSubmitInput = true
                thread.status = turn.status == "inProgress" ? .active(flags: []) : .idle
                upsert(turn: turn, in: &thread)
                selectedThread = thread
                liveItems = thread.turns.flatMap(\.items)
                rebuildConversationFromLiveItems()
                refreshQueuedTurnInputCount()
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
           if let selectedThreadID,
           selectedThread?.status.isActive != true,
           queuedTurnInputsByThreadID[selectedThreadID]?.isEmpty == false {
            await startNextQueuedTurnIfReady(threadID: selectedThreadID)
        }
        return sent && didSubmitInput
    }

    private func stageLocalAttachmentInputs(_ localPaths: [String]) async throws -> [CodexInputItem] {
        guard !localPaths.isEmpty else {
            return []
        }
        guard let selectedServer else {
            throw AppViewModelError.selectionChanged
        }
        let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
        let remotePaths = try await sshService.stageLocalFiles(
            localPaths: localPaths,
            server: selectedServer,
            credential: credential
        )
        return zip(localPaths, remotePaths).map { localPath, remotePath in
            if Self.isImageAttachment(localPath) {
                return .localImage(path: remotePath)
            }
            return .mention(name: URL(fileURLWithPath: localPath).lastPathComponent, path: remotePath)
        }
    }

    private static func isImageAttachment(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"].contains(ext)
    }

    private static func isTerminalItemStatus(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["completed", "complete", "failed", "cancelled", "canceled", "done"].contains(normalized)
    }

    func interruptActiveTurn() async {
        guard let appServer, let selectedThread, let activeTurnID else {
            return
        }
        await runOperation(.interrupting, status: "Interrupting") {
            try await appServer.interrupt(threadID: selectedThread.id, turnID: activeTurnID)
        }
    }

    func respond(to approval: PendingApproval, accept: Bool) async {
        await runOperation(.respondingToApproval, status: accept ? "Approving" : "Declining") {
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

    private func closeConnection(
        updateState: Bool,
        clearOpenSessionCounts shouldClearOpenSessionCounts: Bool = true,
        cancelReconnect: Bool = true
    ) async {
        connectionGeneration &+= 1
        if cancelReconnect {
            appServerReconnectTask?.cancel()
            appServerReconnectTask = nil
            appServerReconnectStatus = nil
        }
        eventTask?.cancel()
        eventTask = nil
        cancelActiveTurnRefresh()
        await appServer?.close()
        appServer = nil
        pendingApprovals = []
        queuedTurnInputsByThreadID.removeAll()
        refreshQueuedTurnInputCount()
        if shouldClearOpenSessionCounts {
            clearOpenSessionCounts()
        }
        if updateState {
            if let selectedServerID {
                appServerReconnectAttemptsByServerID.removeValue(forKey: selectedServerID)
            }
            connectionState = .disconnected
            appServerReconnectStatus = nil
        }
    }

    private var activeTurnID: String? {
        guard let selectedThread, selectedThread.status.isActive else {
            return nil
        }
        return selectedThread.turns.last(where: { $0.status == "inProgress" })?.id ?? selectedThread.turns.last?.id
    }

    private var isSessionMutationInFlight: Bool {
        isOperationActive(.connecting)
            || isOperationActive(.startingSession)
            || isOperationActive(.sending)
            || isOperationActive(.interrupting)
            || isOperationActive(.respondingToApproval)
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
        didLoadServers = true
        do {
            let loadedServers = try repository.loadServers()
            let normalizedServers = serversClearingOpenSessionCounts(loadedServers)
            servers = normalizedServers
            if normalizedServers != loadedServers {
                try? persistServers(normalizedServers)
            }
            selectedServerID = servers.first?.id
            selectedProjectID = selectedServer?.projects.first?.id
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func persistServers(_ servers: [ServerRecord]) throws {
        try repository.saveServers(servers)
    }

    private func serversClearingOpenSessionCounts(_ servers: [ServerRecord]) -> [ServerRecord] {
        servers.map { server in
            var server = server
            server.projects = server.projects.map { project in
                var project = project
                project.activeChatCount = 0
                project.lastActiveChatAt = nil
                return project
            }
            return server
        }
    }

    private func loadCredentialFromStore(serverID: UUID) async throws -> SSHCredential {
        let credentialStore = credentialStore
        return try await Task.detached(priority: .userInitiated) {
            try credentialStore.loadCredential(serverID: serverID)
        }.value
    }

    private func currentTurnOptions(cwd: String?) -> CodexTurnOptions {
        CodexTurnOptions(
            reasoningEffort: selectedReasoningEffort,
            accessMode: selectedAccessMode,
            cwd: cwd
        )
    }

    private func saveCredentialToStore(_ credential: SSHCredential, serverID: UUID) async throws {
        let credentialStore = credentialStore
        try await Task.detached(priority: .userInitiated) {
            try credentialStore.saveCredential(credential, serverID: serverID)
        }.value
    }

    private func deleteCredentialFromStore(serverID: UUID) async throws {
        let credentialStore = credentialStore
        try await Task.detached(priority: .userInitiated) {
            try credentialStore.deleteCredential(serverID: serverID)
        }.value
    }

    private func refreshProjectsUsingCredential(_ credential: SSHCredential, server: ServerRecord, syncActiveChatCounts: Bool) async throws {
        let previousScope = currentThreadLoadScope
        let discovered = try await sshService.discoverProjects(server: server, credential: credential)
        var nextServers = servers
        guard let index = nextServers.firstIndex(where: { $0.id == server.id }) else {
            return
        }

        let openSessions: [CodexThread]?
        if syncActiveChatCounts, let appServer {
            openSessions = try await listOpenSessionsForProjectCounts(appServer: appServer)
        } else {
            openSessions = nil
        }
        nextServers[index].projects = ProjectCatalog.refreshedProjects(
            existing: nextServers[index].projects,
            discovered: discovered,
            openSessions: openSessions
        )
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

    private func listOpenSessionsForProjectCounts(appServer: CodexAppServerClient) async throws -> [CodexThread] {
        try await listOpenSessionSummaries(appServer: appServer)
    }

    private func listOpenSessionSummaries(appServer: CodexAppServerClient) async throws -> [CodexThread] {
        let loadedThreadIDs = try await appServer.listLoadedThreadIDs(limit: 1_000)
        guard !loadedThreadIDs.isEmpty else {
            return []
        }

        var summaries: [CodexThread] = []
        var seen = Set<String>()
        for threadID in loadedThreadIDs where seen.insert(threadID).inserted {
            do {
                let thread = try await appServer.readThreadSummary(threadID: threadID)
                guard thread.isUserFacingSession else {
                    continue
                }
                summaries.append(thread)
            } catch CodexAppServerClientError.appServer(let error) {
                guard error.canIgnoreForLoadedThreadSummary else {
                    throw CodexAppServerClientError.appServer(error)
                }
            }
        }

        return summaries.sorted { lhs, rhs in
            if lhs.status.isActive != rhs.status.isActive {
                return lhs.status.isActive && !rhs.status.isActive
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
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
            publishConversationSections([])
            changedFiles = []
            diffSnapshot = .empty
            clearSelectedThreadLoads()
            refreshQueuedTurnInputCount()
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

    private func resumeThreadForAttachment(_ threadID: String, appServer: CodexAppServerClient) async throws -> CodexThread {
        do {
            return try await appServer.resumeThread(threadID: threadID)
        } catch {
            statusMessage = "Opened session history; live resume failed: \(error.localizedDescription)"
            return try await appServer.readThread(threadID: threadID)
        }
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
            let completedThreadID = params?["threadId"]?.stringValue
            if let turn = try? decode(CodexTurn.self, from: params?["turn"]) {
                applyTurnCompleted(turn)
            }
            await refreshSelectedThreadAfterEvent()
            if let completedThreadID {
                await startNextQueuedTurnIfReady(threadID: completedThreadID)
            }
        case "thread/status/changed":
            if eventTargetsSelectedThread(params),
               let status = try? decode(CodexThreadStatus.self, from: params?["status"]) {
                applySelectedThreadStatus(status)
            }
            await refreshThreadListAfterEvent()
        case "thread/tokenUsage/updated":
            guard eventTargetsSelectedThread(params),
                  let tokenUsage = try? decode(CodexTokenUsage.self, from: params?["tokenUsage"])
            else {
                return
            }
            selectedThreadTokenUsage = tokenUsage
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
            if let selectedSummary = loadedThreads.first(where: { $0.id == selectedThreadID }),
               selectedSummary.status.isActive {
                applySelectedThreadStatus(selectedSummary.status)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshThreadListAfterEvent() async {
        guard appServer != nil else { return }
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
        let serverID = selectedServerID
        connectionGeneration &+= 1
        eventTask = nil
        let closedAppServer = appServer
        appServer = nil
        pendingApprovals = []
        cancelActiveTurnRefresh()
        await closedAppServer?.close()
        guard let serverID,
              shouldAttemptAppServerReconnect(serverID: serverID)
        else {
            clearOpenSessionCounts()
            connectionState = .disconnected
            statusMessage = message
            return
        }
        connectionState = .connecting
        statusMessage = "\(message) Reconnecting app-server."
        scheduleAppServerReconnect(serverID: serverID, disconnectMessage: message)
    }

    private func shouldAttemptAppServerReconnect(serverID: UUID) -> Bool {
        guard selectedServerID == serverID,
              selectedServer != nil,
              maxAppServerReconnectAttempts > 0
        else {
            return false
        }
        return (appServerReconnectAttemptsByServerID[serverID] ?? 0) < maxAppServerReconnectAttempts
    }

    private func scheduleAppServerReconnect(serverID: UUID, disconnectMessage: String) {
        appServerReconnectAttemptsByServerID[serverID, default: 0] += 1
        let attempt = appServerReconnectAttemptsByServerID[serverID] ?? 1
        let waitNanoseconds = Self.appServerReconnectDelayNanoseconds(
            baseDelayNanoseconds: appServerReconnectDelayNanoseconds,
            attempt: attempt
        )
        appServerReconnectStatus = AppServerReconnectStatus(
            attempt: attempt,
            maxAttempts: maxAppServerReconnectAttempts,
            delayNanoseconds: waitNanoseconds
        )
        appServerReconnectTask?.cancel()
        appServerReconnectTask = Task { [weak self] in
            await self?.runScheduledAppServerReconnect(
                serverID: serverID,
                disconnectMessage: disconnectMessage,
                attempt: attempt,
                waitNanoseconds: waitNanoseconds
            )
        }
    }

    private func runScheduledAppServerReconnect(
        serverID: UUID,
        disconnectMessage: String,
        attempt: Int,
        waitNanoseconds: UInt64
    ) async {
        do {
            try await Task.sleep(nanoseconds: waitNanoseconds)
        } catch {
            return
        }
        while selectedServerID == serverID, appServer == nil, isConnectingAppServer {
            do {
                try await Task.sleep(nanoseconds: waitNanoseconds)
            } catch {
                return
            }
        }
        guard selectedServerID == serverID, appServer == nil, connectionState == .connecting else {
            return
        }
        appServerReconnectStatus = AppServerReconnectStatus(
            attempt: attempt,
            maxAttempts: maxAppServerReconnectAttempts,
            delayNanoseconds: 0
        )
        appServerReconnectTask = nil
        await connectSelectedServer(syncActiveChatCounts: true, preservingVisibleState: true)
        guard selectedServerID == serverID else {
            return
        }
        if appServer == nil {
            if shouldAttemptAppServerReconnect(serverID: serverID) {
                connectionState = .connecting
                statusMessage = "\(disconnectMessage) Reconnecting app-server."
                scheduleAppServerReconnect(serverID: serverID, disconnectMessage: disconnectMessage)
            } else {
                appServerReconnectStatus = nil
                clearOpenSessionCounts()
                if case .failed(let reconnectMessage) = connectionState {
                    statusMessage = "\(disconnectMessage) Reconnect failed: \(reconnectMessage)"
                }
            }
        }
    }

    private func connectionStillMatches(_ serverID: UUID, generation: Int) -> Bool {
        selectedServerID == serverID && connectionGeneration == generation
    }

    private func disconnectedFromTargetServer(_ serverID: UUID) -> Bool {
        guard selectedServerID == serverID, appServer == nil else {
            return false
        }
        return connectionState == .disconnected || connectionState == .connecting
    }

    private func markSelectionChanged() {
        connectionState = .disconnected
        statusMessage = AppViewModelError.selectionChanged.localizedDescription
    }

    private func clearOpenSessionCounts() {
        let normalizedServers = serversClearingOpenSessionCounts(servers)
        if normalizedServers != servers {
            servers = normalizedServers
            try? persistServers(normalizedServers)
        }
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
        guard !scope.sessionPaths.isEmpty else {
            return try await listOpenSessionSummaries(appServer: appServer)
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

    private func hydrateConversation(from thread: CodexThread) {
        selectedThread = thread
        liveItems = thread.turns.flatMap(\.items)
        rebuildConversationFromLiveItems()
        refreshQueuedTurnInputCount()
        if thread.status.isActive {
            scheduleActiveTurnRefresh(threadID: thread.id, scope: currentThreadLoadScope)
        } else if activeTurnRefreshThreadID == thread.id {
            cancelActiveTurnRefresh()
        }
    }

    private func applySelectedThreadStatus(_ status: CodexThreadStatus) {
        guard var thread = selectedThread else { return }
        thread.status = status
        selectedThread = thread
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index].status = status
        }
        if status.isActive {
            scheduleActiveTurnRefresh(threadID: thread.id, scope: currentThreadLoadScope)
        } else if activeTurnRefreshThreadID == thread.id {
            cancelActiveTurnRefresh()
        }
    }

    private func applyActivePoll(_ polledThread: CodexThread) {
        selectedThread = polledThread
        if let index = threads.firstIndex(where: { $0.id == polledThread.id }) {
            threads[index] = polledThread
        }
        liveItems = mergedLiveItems(current: liveItems, polled: polledThread.turns.flatMap(\.items))
        rebuildConversationFromLiveItems()
        refreshQueuedTurnInputCount()
    }

    private func mergedLiveItems(current: [CodexThreadItem], polled: [CodexThreadItem]) -> [CodexThreadItem] {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var seen = Set<String>()
        var merged = polled.map { polledItem -> CodexThreadItem in
            seen.insert(polledItem.id)
            guard let currentItem = currentByID[polledItem.id] else {
                return polledItem
            }
            return currentItem.mergeScore >= polledItem.mergeScore ? currentItem : polledItem
        }
        merged.append(contentsOf: current.filter { seen.insert($0.id).inserted })
        return merged
    }

    private func rebuildConversationFromLiveItems() {
        let nextSections = CodexSessionProjection.sections(from: liveItems)
        publishConversationSections(nextSections)
    }

    private func publishConversationSections(_ nextSections: [ConversationSection]) {
        let didChange = conversationSections != nextSections
        conversationSections = nextSections
        conversationRevision += 1
        conversationRenderToken += 1
        conversationRenderDigest = Self.conversationRenderDigest(for: nextSections)
        if didChange, selectedThread?.status.isActive == true {
            conversationFollowToken += 1
        }
    }

    func requestConversationSendScroll() {
        conversationSendToken += 1
    }

    private static func conversationRenderDigest(for sections: [ConversationSection]) -> String {
        sections.map { section in
            [
                section.id,
                "\(section.kind)",
                section.title,
                section.body,
                section.detail ?? "",
                section.status ?? ""
            ].joined(separator: "\u{1F}")
        }
        .joined(separator: "\u{1E}")
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
            if thread.status.isActive {
                applyActivePoll(thread)
                return
            }
            hydrateConversation(from: thread)
            await startNextQueuedTurnIfReady(threadID: threadID)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func cancelActiveTurnRefresh() {
        activeTurnRefreshTask?.cancel()
        activeTurnRefreshTask = nil
        activeTurnRefreshThreadID = nil
    }

    private func startNextQueuedTurnIfReady(threadID: String) async {
        guard appServer != nil,
              selectedThreadID == threadID,
              selectedThread?.status.isActive != true,
              !isOperationActive(.sending),
              let input = dequeueQueuedInput(threadID: threadID)
        else {
            return
        }

        let scope = currentThreadLoadScope
        var queuedTurnSent = false
        let didStart = await runOperation(.sending, status: "Sending queued message") {
            guard let appServer,
                  currentThreadLoadScope == scope,
                  selectedThreadID == threadID
            else {
                return
            }

            let turn = try await appServer.startTurn(
                threadID: threadID,
                input: input,
                options: currentTurnOptions(cwd: selectedThread?.cwd ?? scope.cwd)
            )
            queuedTurnSent = true
            guard currentThreadLoadScope == scope, selectedThreadID == threadID else {
                return
            }

            var thread = selectedThread
                ?? threads.first { $0.id == threadID }
                ?? CodexThread(
                    id: threadID,
                    preview: "",
                    cwd: scope.cwd ?? "",
                    status: .idle,
                    updatedAt: .now,
                    createdAt: .now
                )
            thread.status = turn.status == "inProgress" ? .active(flags: []) : .idle
            upsert(turn: turn, in: &thread)
            selectedThread = thread
            liveItems = thread.turns.flatMap(\.items)
            rebuildConversationFromLiveItems()

            if turn.status == "inProgress" {
                scheduleActiveTurnRefresh(threadID: thread.id, scope: scope)
            } else {
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
            await refreshThreadListAfterEvent()
        }

        if !didStart || !queuedTurnSent {
            prependQueuedInput(input, threadID: threadID)
        } else if selectedThreadID == threadID,
                  selectedThread?.status.isActive != true,
                  queuedTurnInputsByThreadID[threadID]?.isEmpty == false {
            await startNextQueuedTurnIfReady(threadID: threadID)
        }
    }

    private func dequeueQueuedInput(threadID: String) -> [CodexInputItem]? {
        guard var queue = queuedTurnInputsByThreadID[threadID], !queue.isEmpty else {
            refreshQueuedTurnInputCount()
            return nil
        }
        let input = queue.removeFirst()
        if queue.isEmpty {
            queuedTurnInputsByThreadID.removeValue(forKey: threadID)
        } else {
            queuedTurnInputsByThreadID[threadID] = queue
        }
        refreshQueuedTurnInputCount()
        return input
    }

    private func prependQueuedInput(_ input: [CodexInputItem], threadID: String) {
        var queue = queuedTurnInputsByThreadID[threadID] ?? []
        queue.insert(input, at: 0)
        queuedTurnInputsByThreadID[threadID] = queue
        refreshQueuedTurnInputCount()
    }

    private func refreshQueuedTurnInputCount() {
        queuedTurnInputCount = selectedThreadID.flatMap { queuedTurnInputsByThreadID[$0]?.count } ?? 0
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
        selectedThreadTokenUsage = nil
        liveItems = []
        publishConversationSections([])
        changedFiles = []
        diffSnapshot = .empty
        clearSelectedThreadLoads()
        refreshQueuedTurnInputCount()
        pendingApprovals = []
    }

    private func normalizedCredential(for authMethod: ServerAuthMethod, credential: SSHCredential) -> SSHCredential {
        switch authMethod {
        case .password:
            SSHCredential(
                password: credential.password,
                privateKeyPEM: nil,
                privateKeyPassphrase: nil
            )
        case .privateKey:
            SSHCredential(
                password: nil,
                privateKeyPEM: credential.privateKeyPEM,
                privateKeyPassphrase: credential.privateKeyPassphrase
            )
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

    @discardableResult
    private func runOperation(
        _ operation: AppOperation,
        status: String,
        marksConnectionFailure: Bool = false,
        body: () async throws -> Void
    ) async -> Bool {
        activeOperationCounts[operation, default: 0] += 1
        statusMessage = status
        defer { finishOperation(operation) }
        do {
            try await body()
            return true
        } catch {
            if marksConnectionFailure {
                connectionState = .failed(error.localizedDescription)
            }
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func isOperationActive(_ operation: AppOperation) -> Bool {
        (activeOperationCounts[operation] ?? 0) > 0
    }

    private func finishOperation(_ operation: AppOperation) {
        let nextCount = max((activeOperationCounts[operation] ?? 0) - 1, 0)
        if nextCount == 0 {
            activeOperationCounts.removeValue(forKey: operation)
        } else {
            activeOperationCounts[operation] = nextCount
        }
    }
}
