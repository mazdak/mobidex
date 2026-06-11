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
        case .command(_, let command, let cwd, _, let output):
            command.count + cwd.count + (output?.count ?? 0)
        case .fileChange(_, let changes, _):
            changes.reduce(0) { $0 + $1.path.count + $1.diff.count }
        case .toolCall(_, let label, _, let detail),
             .agentEvent(_, let label, _, let detail):
            label.count + (detail?.count ?? 0)
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

    var mergeStatusRank: Int {
        switch self {
        case .command(_, _, _, let status, _),
             .fileChange(_, _, let status),
             .toolCall(_, _, let status, _),
             .agentEvent(_, _, let status, _):
            status.mergeStatusRank
        default:
            0
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var mergeStatusRank: Int {
        switch lowercased() {
        case "completed", "failed", "cancelled", "canceled":
            2
        case "inprogress", "running":
            1
        default:
            0
        }
    }
}

struct StatusAlert: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var message: String
}

private enum OpenAITranscriptionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add an OpenAI API key in Settings before recording audio."
        case .invalidResponse:
            "OpenAI returned an invalid transcription response."
        case .requestFailed(let status, let message):
            "OpenAI transcription failed (\(status)): \(message)"
        }
    }
}

protocol OpenAITranscribing: Sendable {
    func transcribe(audioURL: URL, apiKey: String) async throws -> String
}

private struct OpenAITranscriptionService: OpenAITranscribing {
    func transcribe(audioURL: URL, apiKey: String) async throws -> String {
        let boundary = "mobidex-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(audioURL: audioURL, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAITranscriptionError.requestFailed(http.statusCode, message)
        }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw OpenAITranscriptionError.invalidResponse
        }
        return text
    }

    private func multipartBody(audioURL: URL, boundary: String) throws -> Data {
        var body = Data()
        body.appendPart("--\(boundary)\r\n")
        body.appendPart("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendPart("gpt-4o-transcribe\r\n")
        body.appendPart("--\(boundary)\r\n")
        body.appendPart("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendPart("text\r\n")
        body.appendPart("--\(boundary)\r\n")
        body.appendPart("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        body.appendPart("Content-Type: audio/mp4\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        body.appendPart("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendPart(_ value: String) {
        append(Data(value.utf8))
    }
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
    case missingProject
    case newSessionBlocked
    case newSessionConnectionFailed(String)
    case noActiveTurnToSteer
    case operationTimedOut(String)
    case missingAcpWorkingDirectory

    var errorDescription: String? {
        switch self {
        case .selectionChanged:
            "The selected server or project changed before the operation finished."
        case .missingProject:
            "Select a project before starting a new session."
        case .newSessionBlocked:
            "Finish the current session action before starting a new session."
        case .newSessionConnectionFailed(let message):
            message
        case .noActiveTurnToSteer:
            "There is no active turn to steer."
        case .operationTimedOut(let message):
            message
        case .missingAcpWorkingDirectory:
            "Select a project before connecting an ACP agent."
        }
    }
}

private enum TerminalSessionError: LocalizedError {
    case missingServer
    case unsupportedBackend

    var errorDescription: String? {
        switch self {
        case .missingServer:
            "Select a server before opening a terminal."
        case .unsupportedBackend:
            "Terminal sessions are not available for this SSH backend."
        }
    }
}

private struct ThreadLoadScope: Equatable, Hashable {
    var serverID: UUID?
    var projectID: UUID?
    var cwd: String?
    var sessionPaths: Set<String>
    var includeArchivedSessions: Bool
}

private struct CachedThreadList {
    var threads: [CodexThread]
    var selectedThreadID: String?
    var fetchedAt: Date
}

private struct ThreadDetailCacheKey: Hashable {
    var serverID: UUID?
    var threadID: String
}

private struct CachedThreadDetail {
    var thread: CodexThread
    var liveItems: [CodexThreadItem]
    var sections: [ConversationSection]
    var tokenUsage: CodexTokenUsage?
    var fetchedAt: Date
    var lastAccessedAt: Date
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

enum NewSessionLocation: Equatable {
    case codexWorktree
    case projectDirectory
}

struct QueuedTurnInput: Identifiable, Equatable {
    let id: UUID
    var input: [CodexInputItem]

    var preview: String {
        let text = input.compactMap { item -> String? in
            if case .text(let value) = item {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        if !text.isEmpty {
            return text
        }
        let attachmentCount = input.filter {
            if case .localImage = $0 { return true }
            if case .imageURL = $0 { return true }
            return false
        }.count
        return attachmentCount == 1 ? "1 attachment" : "\(max(attachmentCount, 1)) attachments"
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var servers: [ServerRecord] = []
    @Published private(set) var selectedServerID: UUID?
    @Published private(set) var selectedProjectID: UUID?
    @Published private(set) var isShowingAllSessions = false
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
    @Published private(set) var connectionDiagnosticReport: SSHDiagnosticReport?
    @Published private(set) var isRunningConnectionDiagnostics = false
    @Published private(set) var statusMessage: String?
    @Published var statusAlert: StatusAlert?
    @Published private(set) var changedFiles: [String] = []
    @Published private(set) var diffSnapshot: GitDiffSnapshot = .empty
    @Published private(set) var queuedTurnInputCount = 0
    @Published private(set) var queuedTurnInputs: [QueuedTurnInput] = []
    @Published private(set) var selectedThreadTokenUsage: CodexTokenUsage?
    @Published private(set) var switchingServerID: UUID?
    @Published var selectedReasoningEffort: CodexReasoningEffortOption = .medium
    @Published var selectedAccessMode: CodexAccessMode = .fullAccess
    @Published private(set) var hasOpenAIAPIKey = false
    @Published var showsArchivedSessions = false
    @Published private var activeOperationCounts: [AppOperation: Int] = [:]

    private let repository: ServerRepository
    private let credentialStore: CredentialStore
    private let sshService: SSHService
    private let openAITranscriptionService: any OpenAITranscribing
    private let activeTurnRefreshIntervalNanoseconds: UInt64
    private let appServerReconnectDelayNanoseconds: UInt64
    private let maxAppServerReconnectAttempts: Int
    private let sessionListCacheTTL: TimeInterval
    private let threadDetailCacheTTL: TimeInterval
    private let maxThreadDetailCacheEntries: Int
    private let sessionStartOperationTimeoutSeconds: Double
    private let remoteDirectoryOperationTimeoutSeconds: Double = 60
    private let sessionListInitialPageLimit = 1
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
    private var sessionRefreshListLoadGeneration = 0
    private var sessionRefreshDetailLoadGeneration = 0
    private var queuedTurnInputsByThreadID: [String: [QueuedTurnInput]] = [:]
    private var isConnectingAppServer = false
    private var didLoadServers = false
    private var suppressThreadAutoSelection = false
    private var suppressCachedThreadSelection = false
    private var autoConnectAttemptedServerIDs = Set<UUID>()
    private var appServerReconnectAttemptsByServerID: [UUID: Int] = [:]

    // ACP / Grok debug wiring (item 7 minimal path, Codex untouched).
    // Parallel holders + surface so mapped sessionItems (CodexThreadItem from the bridged KMP mapper)
    // can be driven over real openRawExec + AcpClient without touching appServer/eventTask/connectSelectedServer/send paths.
    private var debugAcpClient: AcpClient?
    private var debugAcpCollectorTask: Task<Void, Never>?
    @Published private(set) var debugAcpItems: [CodexThreadItem] = []
    var debugAcpConversationSections: [ConversationSection] {
        SharedKMPBridge.conversationSections(from: debugAcpItems)
    }
    @Published private(set) var isShowingAcpDebugPreview = false

    // ACP / Grok *production* wiring.
    // When selectedServer.backendType == .acp, the main connectSelectedServer / send / approval / close
    // paths drive these instead of appServer + eventTask. The collector feeds the primary conversation state
    // (via the same SharedKMPBridge.conversationSections(from:) the debug preview already uses) so Grok
    // chunks render as identical rich UI elements in the normal ConversationView.
    // Zero changes to any Codex paths. Reuses AcpClient actor + mapper + raw-exec + (post-simplification) auth model.
    private var acpClient: AcpClient?
    private var acpCollectorTask: Task<Void, Never>?
    private var acpEventsTask: Task<Void, Never>?
    private var acpItems: [CodexThreadItem] = []
    private var acpSessionId: String?
    // Model state the ACP agent advertised for the live session (empty = no switching).
    @Published private(set) var acpModelOptions: [AcpModelOption] = []
    @Published private(set) var acpCurrentModelId: String?

    private var threadListCache: [ThreadLoadScope: CachedThreadList] = [:]
    private var threadDetailCache: [ThreadDetailCacheKey: CachedThreadDetail] = [:]
    private var suppressNextConversationDetailCache = false

    // Incremental conversation projection: the accumulator mirrors the visible item list
    // (liveItems on Codex, acpItems on ACP) so streamed deltas re-project one item instead of
    // the whole conversation, and `@Published` assignments conflate to ~50ms during streaming.
    private let conversationAccumulator = ConversationSectionAccumulator()
    private var conversationFlushTask: Task<Void, Never>?
    private var lastConversationFlushAt: ContinuousClock.Instant?
    private let conversationFlushInterval: Duration = .milliseconds(50)

    init(
        repository: ServerRepository,
        credentialStore: CredentialStore,
        sshService: SSHService,
        openAITranscriptionService: any OpenAITranscribing = OpenAITranscriptionService(),
        activeTurnRefreshIntervalNanoseconds: UInt64 = 1_000_000_000,
        appServerReconnectDelayNanoseconds: UInt64 = 500_000_000,
        maxAppServerReconnectAttempts: Int = 3,
        sessionListCacheTTL: TimeInterval = SharedKMPBridge.defaultSessionListCacheTTL,
        threadDetailCacheTTL: TimeInterval = SharedKMPBridge.defaultThreadDetailCacheTTL,
        maxThreadDetailCacheEntries: Int = 8,
        sessionStartOperationTimeoutSeconds: Double = 30,
        loadServersOnInit: Bool = true
    ) {
        self.repository = repository
        self.credentialStore = credentialStore
        self.sshService = sshService
        self.openAITranscriptionService = openAITranscriptionService
        self.activeTurnRefreshIntervalNanoseconds = activeTurnRefreshIntervalNanoseconds
        self.appServerReconnectDelayNanoseconds = appServerReconnectDelayNanoseconds
        self.maxAppServerReconnectAttempts = maxAppServerReconnectAttempts
        self.sessionListCacheTTL = sessionListCacheTTL
        self.threadDetailCacheTTL = threadDetailCacheTTL
        self.maxThreadDetailCacheEntries = max(1, maxThreadDetailCacheEntries)
        self.sessionStartOperationTimeoutSeconds = sessionStartOperationTimeoutSeconds
        if loadServersOnInit {
            loadServers()
            refreshOpenAIAPIKeyState()
        }
    }

    func loadOpenAIAPIKeyForEditing() -> String {
        (try? credentialStore.loadOpenAIAPIKey()) ?? ""
    }

    func saveOpenAIAPIKey(_ key: String) {
        do {
            try credentialStore.saveOpenAIAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty)
            refreshOpenAIAPIKeyState()
            statusMessage = hasOpenAIAPIKey ? "OpenAI API key saved." : "OpenAI API key removed."
        } catch {
            statusMessage = error.localizedDescription
            statusAlert = StatusAlert(title: "Settings Not Saved", message: error.localizedDescription)
        }
    }

    func transcribeAudio(at url: URL) async throws -> String {
        guard let apiKey = try credentialStore.loadOpenAIAPIKey()?.nonEmpty else {
            throw OpenAITranscriptionError.missingAPIKey
        }
        return try await openAITranscriptionService.transcribe(audioURL: url, apiKey: apiKey)
    }

    @discardableResult
    func refreshOpenAIAPIKeyState() -> Bool {
        hasOpenAIAPIKey = ((try? credentialStore.loadOpenAIAPIKey()) ?? nil)?.nonEmpty != nil
        return hasOpenAIAPIKey
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
        (appServer != nil || acpClient != nil) && !isSessionMutationInFlight
    }

    var canInterruptActiveTurn: Bool {
        (appServer != nil || acpClient != nil) && activeTurnID != nil
    }

    var isAppServerConnected: Bool {
        appServer != nil || acpClient != nil
    }

    var isBusy: Bool {
        activeOperationCounts.values.contains { $0 > 0 }
    }

    var canCreateSession: Bool {
        appServer != nil && selectedProject != nil && !isSessionMutationInFlight
    }

    var canChooseNewSessionLocation: Bool {
        selectedServer != nil && selectedProject != nil && !isNewSessionBlockedBySessionAction
    }

    var isStartingNewSession: Bool {
        isOperationActive(.startingSession)
    }

    private var isNewSessionBlockedBySessionAction: Bool {
        isOperationActive(.startingSession)
            || isOperationActive(.sending)
            || isOperationActive(.interrupting)
            || isOperationActive(.respondingToApproval)
    }

    var sessionSections: [SessionListSection] {
        SessionListSections.sections(threads: threads, projects: selectedServer?.projects ?? [])
    }

    var contextUsageFraction: Double? {
        selectedThreadTokenUsage?.contextFraction
    }

    var contextUsagePercent: Int? {
        contextUsageFraction.map { min(max(Int(($0 * 100).rounded()), 0), 100) }
    }

    var isRefreshingChanges: Bool {
        isOperationActive(.refreshingChangedFiles)
    }

    var isRefreshingSessions: Bool {
        isOperationActive(.refreshingSessions)
    }

    var isDiscoveringProjects: Bool {
        isOperationActive(.discoveringProjects)
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
        isShowingAllSessions = false
        suppressCachedThreadSelection = false
        selectedProjectID = serverID.flatMap { id in
            servers.first { $0.id == id }?.projects.firstAddedProjectID
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
        // Full ACP teardown (mirrors closeConnection): leaving the events task running or the
        // client unclosed lets a stale disconnect/serverRequest corrupt the next connection's
        // state, and leaks the SSH channel + remote agent process.
        acpCollectorTask?.cancel()
        acpCollectorTask = nil
        acpEventsTask?.cancel()
        acpEventsTask = nil
        if let client = acpClient { Task { await client.close() } }
        acpClient = nil
        acpSessionId = nil
        acpItems = []
        acpModelOptions = []
        acpCurrentModelId = nil
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
        isShowingAllSessions = false
        suppressThreadAutoSelection = true
        suppressCachedThreadSelection = true
        invalidateSessionRefreshes()
        selectedProjectID = projectID
        if restoreCachedSessionState(for: currentThreadLoadScope) {
            return
        }
        resetSessionState(clearThreads: true)
    }

    func selectAllSessions() {
        guard !isShowingAllSessions || selectedProjectID != nil else {
            return
        }
        isShowingAllSessions = true
        suppressThreadAutoSelection = true
        suppressCachedThreadSelection = true
        invalidateSessionRefreshes()
        selectedProjectID = nil
        if restoreCachedSessionState(for: currentThreadLoadScope) {
            return
        }
        resetSessionState(clearThreads: true)
    }

    @discardableResult
    func setProjectAdded(_ project: ProjectRecord, isAdded: Bool) -> Bool {
        guard let selectedServerID else {
            return false
        }

        var nextServers = servers
        guard let serverIndex = nextServers.firstIndex(where: { $0.id == selectedServerID }),
              let projectIndex = nextServers[serverIndex].projects.firstIndex(where: { $0.id == project.id })
        else {
            return false
        }

        guard nextServers[serverIndex].projects[projectIndex].isAdded != isAdded else {
            return true
        }

        nextServers[serverIndex].projects[projectIndex].isAdded = isAdded
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
        let launchConfig = SharedKMPBridge.normalizedRemoteLaunchConfig(
            codexPath: next.codexPath,
            executionPath: next.executionPath
        )
        next.codexPath = launchConfig.codexPath
        next.executionPath = launchConfig.executionPath
        next.acpLaunchCommand = next.acpLaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? SharedKMPBridge.defaultAcpLaunchCommand
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
            let shouldDisconnectSavedSelection = wasSelected && (appServer != nil || acpClient != nil || connectionState == .connecting)

            var nextServers = servers
            var previousEndpoint: (host: String, port: Int)?
            if let index = nextServers.firstIndex(where: { $0.id == server.id }) {
                previousEndpoint = (nextServers[index].host, nextServers[index].port)
                next.createdAt = nextServers[index].createdAt
                next.projects = nextServers[index].projects
                nextServers[index] = next
            } else {
                nextServers.append(next)
            }

            if shouldDisconnectSavedSelection {
                nextServers = serversClearingOpenSessionCounts(nextServers)
            }

            if let previousEndpoint {
                SSHHostKeyPinStore.migrateLegacyEndpointPin(
                    serverID: next.id,
                    host: previousEndpoint.host,
                    port: previousEndpoint.port
                )
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
                isShowingAllSessions = false
                selectedProjectID = next.projects.firstAddedProjectID
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
                isShowingAllSessions = false
                selectedProjectID = selectedServer?.projects.firstAddedProjectID
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
        let project: ProjectRecord
        if let projectIndex = nextServers[index].projects.firstIndex(where: { $0.path == trimmed }) {
            guard !nextServers[index].projects[projectIndex].isAddedToProjectList else {
                statusMessage = "That project is already saved."
                return false
            }
            nextServers[index].projects[projectIndex].isAdded = true
            project = nextServers[index].projects[projectIndex]
        } else {
            project = ProjectRecord(path: trimmed, isAdded: true)
            nextServers[index].projects.append(project)
        }
        nextServers[index].updatedAt = .now

        do {
            try persistServers(nextServers)
            servers = nextServers
            isShowingAllSessions = false
            selectedProjectID = project.id
            invalidateSessionCaches(for: selectedServerID)
            resetSessionState(clearThreads: true)
            statusMessage = "Added \(project.displayName)."
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func listRemoteDirectories(path: String) async throws -> RemoteDirectoryListing {
        guard let selectedServer else {
            throw SSHServiceError.remoteDirectoryBrowseFailed("Select a server before browsing folders.")
        }
        let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
        return try await withTimeout(seconds: remoteDirectoryOperationTimeoutSeconds) {
            try await self.sshService.listDirectories(path: path, server: selectedServer, credential: credential)
        }
    }

    func createRemoteDirectory(parentPath: String, folderName: String) async throws -> RemoteDirectoryListing {
        guard let selectedServer else {
            throw SSHServiceError.remoteDirectoryBrowseFailed("Select a server before creating folders.")
        }
        let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
        return try await withTimeout(seconds: remoteDirectoryOperationTimeoutSeconds) {
            try await self.sshService.createDirectory(
                parentPath: parentPath,
                folderName: folderName,
                server: selectedServer,
                credential: credential
            )
        }
    }

    func createRemoteProjectDirectory(path: String) async throws -> RemoteDirectoryListing {
        guard let selectedServer else {
            throw SSHServiceError.remoteDirectoryBrowseFailed("Select a server before creating folders.")
        }
        let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
        return try await withTimeout(seconds: remoteDirectoryOperationTimeoutSeconds) {
            try await self.sshService.ensureDirectory(path: path, server: selectedServer, credential: credential)
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
        if let projectIndex = nextServers[index].projects.firstIndex(where: { $0.id == project.id }),
           nextServers[index].projects[projectIndex].discovered {
            nextServers[index].projects[projectIndex].isAdded = false
        } else {
            nextServers[index].projects.removeAll { $0.id == project.id }
        }
        nextServers[index].updatedAt = .now
        let removedSelectedProject = selectedProjectID == project.id
        let nextSelectedProjectID = removedSelectedProject ? nextServers[index].projects.firstAddedProjectID : selectedProjectID

        do {
            try persistServers(nextServers)
            servers = nextServers
            selectedProjectID = nextSelectedProjectID
            invalidateSessionCaches(for: selectedServerID)
            if removedSelectedProject {
                isShowingAllSessions = false
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

    /// Minimal debug/experimental path (parity with Android).
    /// Drives the server's configured ACP launch command over SSH raw exec + the Swift AcpClient
    /// (actor) + bridged mapper. Emits the exact CodexThreadItem kinds (reasoning for thoughts,
    /// agentMessage, toolCall, etc.) into a parallel debug surface (`debugAcpItems`) that reuses
    /// the same models already rendered by ConversationView / ConversationSection.
    ///
    /// Codex connectSelectedServer / send / disconnect paths are 100% untouched (byte-for-byte).
    func startAcpDebugSession(initialPrompt: String? = nil) async {
        guard let server = selectedServer else { return }

        // Cancel prior debug ACP session (simple reset, no hidden sharing with Codex state).
        debugAcpCollectorTask?.cancel()
        if let prior = debugAcpClient {
            await prior.close()
        }
        debugAcpClient = nil
        debugAcpItems = []

        await runOperation(.connecting, status: "Starting ACP debug session", marksConnectionFailure: true) {
            let credential = try await loadCredentialFromStore(serverID: server.id)
            // No agent keys from the phone. SSH authentication is the trust boundary;
            // the remote agent process reads its own auth (exactly as codex does today).
            let command = SharedKMPBridge.acpShellCommand(
                launchCommand: server.acpLaunchCommand,
                executionPath: server.executionPath
            )
            let transport = try await sshService.openRawExec(server: server, credential: credential, command: command)
            let client = AcpClient(transport: transport)
            debugAcpClient = client

            let sid: String
            do {
                try await client.initialize()
                // ACP spec requires an absolute cwd on session/new.
                guard let cwd = selectedProject?.path else {
                    throw AppViewModelError.missingAcpWorkingDirectory
                }
                sid = try await client.createSession(cwd: cwd, title: "ACP debug session").sessionId
            } catch {
                // Never strand a half-open transport / remote agent process on failure.
                await client.close()
                debugAcpClient = nil
                throw error
            }

            statusMessage = "ACP session \(sid) connected (debug)."

            if let prompt = initialPrompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await client.sendPrompt(sessionId: sid, text: prompt)
            }

            debugAcpCollectorTask = Task { [weak self] in
                guard let self else { return }
                for await item in client.sessionItems {
                    await MainActor.run {
                        self.debugAcpItems.append(item)
                    }
                }
            }
        }
    }

    func presentAcpDebugPreview() {
        isShowingAcpDebugPreview = true
    }

    /// Production ACP path helper (called from main send / connect branches when backendType == .acp).
    /// Launches the server's configured ACP stdio command via openRawExec + AcpClient actor for
    /// the currently selected project. Collector feeds the *main* conversationSections via the exact same
    /// SharedKMPBridge.conversationSections(from:) projection used by the debug preview and (on the
    /// KMP side) by the Android production collector. This makes a .acp ServerRecord "just work"
    /// in the normal chat UI with identical rich elements (Reasoning, ToolCall, Plan, etc.).
    ///
    /// Codex paths remain 100% untouched.
    private func startAcpProductionSessionForCurrentProject() async -> Bool {
        guard let server = selectedServer, server.backendType == .acp else { return false }
        let projectPath = selectedProject?.path

        // Cancel prior production ACP session for this server if project changed or we are restarting.
        acpCollectorTask?.cancel()
        acpEventsTask?.cancel()
        if let prior = acpClient {
            await prior.close()
        }
        acpClient = nil
        acpItems = []
        resyncConversationAccumulator(items: acpItems)

        // Ownership guard: closeConnection / a newer connect bumps connectionGeneration, and a
        // stale attempt closes whatever it built instead of installing it (prevents leaked
        // clients and disconnect-during-connect resurrecting a connection).
        let generation = connectionGeneration

        return await runOperation(.connecting, status: "Starting ACP agent", marksConnectionFailure: true) {
            let credential = try await loadCredentialFromStore(serverID: server.id)
            let command = SharedKMPBridge.acpShellCommand(
                launchCommand: server.acpLaunchCommand,
                executionPath: server.executionPath
            )
            let transport = try await sshService.openRawExec(server: server, credential: credential, command: command)
            let client = AcpClient(transport: transport)

            do {
                try await client.initialize()
                // ACP spec requires an absolute cwd on session/new. executionPath is a PATH list
                // (binary lookup), never a working directory — only a selected project provides cwd.
                guard let cwd = projectPath else {
                    throw AppViewModelError.missingAcpWorkingDirectory
                }
                let session = try await client.createSession(cwd: cwd, title: server.displayName)
                guard generation == self.connectionGeneration, self.selectedServer?.id == server.id else {
                    await client.close()
                    return
                }
                acpClient = client
                acpSessionId = session.sessionId
                acpModelOptions = session.modelOptions
                acpCurrentModelId = session.currentModelId
            } catch {
                // Never strand a half-open transport / remote agent process on failure.
                await client.close()
                throw error
            }

            statusMessage = "ACP agent session connected."

            acpCollectorTask = Task { [weak self] in
                guard let self else { return }
                for await item in client.sessionItems {
                    await MainActor.run {
                        guard self.acpClient === client else { return } // stale session
                        // Coalesce streamed deltas / resolve tool cards before projecting.
                        let previousItems = self.acpItems
                        self.acpItems = SharedKMPBridge.appendingAcpThreadItem(previousItems, item)
                        // Drive the normal ConversationView through the incremental accumulator
                        // (same projection as before; one bridged item per chunk instead of all).
                        self.applyAcpConversationChange(previous: previousItems, next: self.acpItems)
                    }
                }
            }

            // Permission round-trip: surface session/request_permission as the same approval cards
            // Codex uses; respond(to:accept:) answers via the spec outcome shape.
            acpEventsTask = Task { [weak self] in
                guard let self else { return }
                for await event in client.events {
                    await MainActor.run {
                        guard self.acpClient === client else { return } // stale session
                        self.handleAcpEvent(event)
                    }
                }
            }
        }
    }

    private func handleAcpEvent(_ event: CodexAppServerEvent) {
        switch event {
        case .serverRequest(let id, let method, let params):
            guard method == SharedKMPBridge.acpPermissionRequestMethod else { return }
            let summary = SharedKMPBridge.acpPermissionSummary(params: params)
            pendingApprovals.append(PendingApproval(
                id: "acp-\(id)-\(pendingApprovals.count)",
                requestID: id,
                method: method,
                params: params,
                title: summary.title,
                detail: summary.detail
            ))
        case .disconnected(let message):
            statusMessage = message
            pendingApprovals = []
            acpModelOptions = []
            acpCurrentModelId = nil
            if connectionState == .connected {
                connectionState = .failed(message)
            }
        case .notification:
            break
        }
    }

    func dismissAcpDebugPreview() {
        isShowingAcpDebugPreview = false
    }

    func diagnoseSelectedConnection() async {
        guard let selectedServer else { return }
        isRunningConnectionDiagnostics = true
        statusMessage = "Running connection diagnostics"
        defer {
            isRunningConnectionDiagnostics = false
        }
        let credential: SSHCredential
        do {
            credential = try await loadCredentialFromStore(serverID: selectedServer.id)
        } catch {
            connectionDiagnosticReport = SSHDiagnosticReport(
                host: selectedServer.endpointLabel,
                resolvedAddresses: [],
                tcpResults: [],
                hostKeyFingerprint: nil,
                pinnedHostKeyFingerprint: nil,
                authMethod: selectedServer.authMethod.label.lowercased(),
                failureStage: "credential",
                rawUnderlyingErrorType: String(reflecting: type(of: error)),
                rawUnderlyingError: String(describing: error),
                remoteCommandResult: nil,
                appServerResult: nil
            )
            statusMessage = "Connection diagnostics failed."
            return
        }
        let report = await sshService.diagnoseConnection(server: selectedServer, credential: credential)
        connectionDiagnosticReport = report
        statusMessage = report.summary
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
                isShowingAllSessions = false
                selectedProjectID = selectedServer?.projects.firstAddedProjectID
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
        if targetServer.backendType == .acp {
            // ACP production path: use the pre-built helper (collector drives main conversationSections via SharedKMPBridge + mapper).
            // Early return keeps the entire Codex connect body below byte-for-byte untouched.
            isConnectingAppServer = true
            defer {
                isConnectingAppServer = false
            }
            await closeConnection(updateState: false, clearOpenSessionCounts: !preservingVisibleState, cancelReconnect: !preservingVisibleState)
            connectionState = .connecting
            let connected = await startAcpProductionSessionForCurrentProject()
            // acpClient != nil distinguishes a real connect from a stale-bailed attempt
            // (user disconnected/switched mid-connect): the latter must not resurrect
            // a Connected state with no client behind it.
            if connected, selectedServerID == targetServer.id, acpClient != nil {
                connectionState = .connected
            }
            return
        }
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
            statusMessage = "Server connected."
        }

        guard didConnect, let credential else {
            return
        }
        appServerReconnectAttemptsByServerID.removeValue(forKey: targetServer.id)
        appServerReconnectStatus = nil

        var syncSucceeded = true
        syncSucceeded = await runOperation(.discoveringProjects, status: "Syncing projects") {
            try await refreshProjectsUsingCredential(
                credential,
                server: targetServer,
                syncActiveChatCounts: syncActiveChatCounts,
                includeRemoteDiscovery: true
            )
        } && syncSucceeded

        guard connectionStillMatches(targetServer.id, generation: connectGeneration) else {
            if disconnectedFromTargetServer(targetServer.id) {
                return
            }
            markSelectionChanged()
            return
        }

        syncSucceeded = await runOperation(.refreshingSessions, status: "Refreshing sessions") {
            try await loadThreads(forceReload: true)
        } && syncSucceeded

        if syncSucceeded, connectionState == .connected, connectionGeneration == connectGeneration {
            statusMessage = "Server connected."
        }
    }

    func refreshProjects() async {
        guard let selectedServer else { return }
        await runOperation(.discoveringProjects, status: "Discovering projects") {
            let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
            try await refreshProjectsUsingCredential(
                credential,
                server: selectedServer,
                syncActiveChatCounts: true,
                includeRemoteDiscovery: true
            )
        }
    }

    func openTerminalSession(columns: Int = 80, rows: Int = 24) async throws -> RemoteTerminalSession {
        guard let selectedServer else {
            throw TerminalSessionError.missingServer
        }
        guard let terminalService = sshService as? TerminalSSHService else {
            throw TerminalSessionError.unsupportedBackend
        }
        do {
            statusMessage = "Opening terminal"
            let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
            let cwd = selectedThread?.cwd ?? selectedProject?.path
            let session = try await terminalService.openTerminal(cwd: cwd, columns: columns, rows: rows, server: selectedServer, credential: credential)
            statusMessage = nil
            return session
        } catch {
            statusMessage = error.localizedDescription
            throw error
        }
    }

    func refreshThreads() async {
        await runOperation(.refreshingSessions, status: "Refreshing sessions") {
            try await loadThreads(forceReload: true)
        }
    }

    func refreshThreadsIfNeeded() async {
        let scope = currentThreadLoadScope
        if restoreCachedSessionState(for: scope), canUseCachedSessionState(for: scope) {
            return
        }
        await runOperation(.refreshingSessions, status: "Refreshing sessions") {
            try await loadThreads(forceReload: false)
        }
    }

    func selectAllSessionsAndRefresh() async {
        await runOperation(.refreshingSessions, status: "Refreshing sessions") {
            selectAllSessions()
            try await loadThreads(forceReload: true)
        }
    }

    func selectAllSessionsAndRefreshIfNeeded() async {
        selectAllSessions()
        await refreshThreadsIfNeeded()
    }

    func openThread(_ thread: CodexThread) async {
        let scope = currentThreadLoadScope
        let shouldPromoteProject = isShowingAllSessions
        suppressThreadAutoSelection = false
        suppressCachedThreadSelection = false
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
            if shouldPromoteProject {
                promoteProjectToProjectList(for: hydrated)
            }
        }
    }

    @discardableResult
    func startNewSession(location: NewSessionLocation = .codexWorktree) async -> String? {
        guard let selectedServer else { return nil }
        guard let selectedProject else {
            statusMessage = AppViewModelError.missingProject.localizedDescription
            return nil
        }
        guard !isNewSessionBlockedBySessionAction else {
            statusMessage = AppViewModelError.newSessionBlocked.localizedDescription
            return nil
        }
        let cwd = selectedProject.path
        let scope = currentThreadLoadScope
        var createdThreadID: String?
        suppressThreadAutoSelection = true
        invalidateSessionRefreshes()
        resetSessionState(clearThreads: false)
        await runOperation(.startingSession, status: "Starting session") {
            let timeoutSeconds = timeoutSecondsLabel(sessionStartOperationTimeoutSeconds)
            if appServer == nil {
                statusMessage = "Connecting before starting session"
                if isConnectingAppServer {
                    try await waitForNewSessionConnectionStep(timeoutSeconds: timeoutSeconds) {
                        await self.waitForAppServerConnectionAttempt()
                    }
                }
                if appServer == nil {
                    try await waitForNewSessionConnectionStep(timeoutSeconds: timeoutSeconds) {
                        await self.connectSelectedServer(syncActiveChatCounts: false, preservingVisibleState: true)
                    }
                }
            }
            guard let appServer else {
                throw AppViewModelError.newSessionConnectionFailed(
                    statusMessage ?? "Connect to the server before starting a new session."
                )
            }
            guard selectedServerID == selectedServer.id,
                  selectedProjectID == selectedProject.id,
                  currentThreadLoadScope == scope else {
                throw AppViewModelError.selectionChanged
            }
            let sessionCwd: String
            switch location {
            case .codexWorktree:
                statusMessage = "Creating worktree"
                let credential = try await loadCredentialFromStore(serverID: selectedServer.id)
                guard selectedServerID == selectedServer.id,
                      selectedProjectID == selectedProject.id,
                      currentThreadLoadScope == scope else {
                    throw AppViewModelError.selectionChanged
                }
                sessionCwd = try await withTimeout(
                    seconds: sessionStartOperationTimeoutSeconds,
                    timeoutMessage: "Creating the worktree timed out after \(timeoutSeconds) seconds."
                ) {
                    try await self.sshService.createCodexWorktree(from: cwd, server: selectedServer, credential: credential)
                }
            case .projectDirectory:
                sessionCwd = cwd
            }
            guard selectedServerID == selectedServer.id,
                  selectedProjectID == selectedProject.id,
                  currentThreadLoadScope == scope else {
                throw AppViewModelError.selectionChanged
            }
            statusMessage = "Creating session"
            let thread = try await withTimeout(
                seconds: sessionStartOperationTimeoutSeconds,
                timeoutMessage: "Creating the session timed out after \(timeoutSeconds) seconds."
            ) {
                try await appServer.startThread(cwd: sessionCwd)
            }
            guard currentThreadLoadScope == scope else {
                return
            }
            selectedThreadID = thread.id
            selectedThreadTokenUsage = nil
            changedFiles = []
            diffSnapshot = .empty
            pendingApprovals = []
            hydrateConversation(from: thread)
            suppressThreadAutoSelection = false
            suppressCachedThreadSelection = false
            createdThreadID = thread.id
            threads = sortedThreads([thread] + threads.filter { $0.id != thread.id })
            invalidateSessionCaches(for: selectedServerID)
            cacheThreadList(threads, scope: currentThreadLoadScope)
            cacheThreadDetail(thread: thread, liveItems: liveItems, sections: conversationSections)
            statusMessage = location == .codexWorktree ? "New session created in a worktree." : "New session created."
        }
        if createdThreadID == nil,
           selectedServerID == selectedServer.id,
           selectedProjectID == selectedProject.id,
           currentThreadLoadScope == scope {
            suppressThreadAutoSelection = false
        }
        return createdThreadID
    }

    private func waitForNewSessionConnectionStep(
        timeoutSeconds: Int,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        do {
            try await withTimeout(
                seconds: sessionStartOperationTimeoutSeconds,
                timeoutMessage: "Connecting before starting the session timed out after \(timeoutSeconds) seconds.",
                operation: operation
            )
        } catch AppViewModelError.operationTimedOut(let message) {
            connectionGeneration &+= 1
            isConnectingAppServer = false
            if appServer == nil {
                connectionState = .failed(message)
            }
            throw AppViewModelError.operationTimedOut(message)
        }
    }

    private func waitForAppServerConnectionAttempt() async {
        while isConnectingAppServer {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
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
        queuedTurnInputsByThreadID[selectedThreadID, default: []].append(QueuedTurnInput(id: UUID(), input: [.text(trimmed)]))
        refreshQueuedTurnInputCount()
        statusMessage = "Queued message for after the current turn."
    }

    func deleteQueuedTurnInput(_ id: UUID) {
        guard let selectedThreadID else { return }
        queuedTurnInputsByThreadID[selectedThreadID]?.removeAll { $0.id == id }
        if queuedTurnInputsByThreadID[selectedThreadID]?.isEmpty == true {
            queuedTurnInputsByThreadID.removeValue(forKey: selectedThreadID)
        }
        refreshQueuedTurnInputCount()
    }

    func moveQueuedTurnInput(_ id: UUID, direction: Int) {
        guard direction != 0, let selectedThreadID,
              var queue = queuedTurnInputsByThreadID[selectedThreadID],
              let index = queue.firstIndex(where: { $0.id == id })
        else { return }
        let nextIndex = min(max(index + direction, 0), queue.count - 1)
        guard nextIndex != index else { return }
        let item = queue.remove(at: index)
        queue.insert(item, at: nextIndex)
        queuedTurnInputsByThreadID[selectedThreadID] = queue
        refreshQueuedTurnInputCount()
    }

    func steerQueuedTurnInputNow(_ id: UUID) async {
        guard let appServer, let selectedThreadID,
              var queue = queuedTurnInputsByThreadID[selectedThreadID],
              let index = queue.firstIndex(where: { $0.id == id })
        else {
            statusMessage = "There is no active turn to steer."
            return
        }
        let item = queue[index]
        let scope = currentThreadLoadScope
        var localEchoID: String?
        var removedFromQueue = false
        let sent = await runOperation(.sending, status: "Steering active turn") {
            guard currentThreadLoadScope == scope, self.selectedThreadID == selectedThreadID else {
                throw AppViewModelError.selectionChanged
            }
            beginSelectedThreadLoad(threadID: selectedThreadID)
            defer {
                endSelectedThreadLoad(threadID: selectedThreadID, scope: scope)
            }
            let thread = try await appServer.readThread(threadID: selectedThreadID)
            guard currentThreadLoadScope == scope, self.selectedThreadID == selectedThreadID else {
                throw AppViewModelError.selectionChanged
            }
            hydrateConversation(from: thread)
            guard let activeTurnID = Self.activeTurnID(in: thread) else {
                throw AppViewModelError.noActiveTurnToSteer
            }
            queue.removeAll { $0.id == id }
            if queue.isEmpty {
                queuedTurnInputsByThreadID.removeValue(forKey: selectedThreadID)
            } else {
                queuedTurnInputsByThreadID[selectedThreadID] = queue
            }
            removedFromQueue = true
            refreshQueuedTurnInputCount()
            localEchoID = appendLocalUserEcho(input: item.input, turnID: activeTurnID)
            try await appServer.steer(threadID: selectedThreadID, expectedTurnID: activeTurnID, input: item.input)
            statusMessage = "Steered active turn."
            await refreshThreadListAfterEvent()
        }
        if !sent {
            if let localEchoID {
                removeLocalUserEcho(id: localEchoID)
            }
            if removedFromQueue {
                prependQueuedInput(item, threadID: selectedThreadID)
            }
        }
    }

    func archiveThread(_ thread: CodexThread) async {
        guard let appServer else {
            statusMessage = "Connect to the server before archiving a session."
            return
        }
        let archivedID = thread.id
        await runOperation(.openingThread, status: "Archiving session") {
            try await appServer.archiveThread(threadID: archivedID)
            queuedTurnInputsByThreadID.removeValue(forKey: archivedID)
            threads.removeAll { $0.id == archivedID }
            threadListCache.removeAll()
            threadDetailCache.removeValue(forKey: threadDetailCacheKey(threadID: archivedID))
            if selectedThreadID == archivedID {
                if let fallback = threads.first {
                    selectedThreadID = fallback.id
                    hydrateConversation(from: fallback, cacheDetail: false)
                } else {
                    selectedThreadID = nil
                    selectedThread = nil
                    liveItems = []
                    selectedThreadTokenUsage = nil
                    resetConversationSections(items: [])
                }
            }
            refreshQueuedTurnInputCount()
            await refreshThreadListAfterEvent()
        }
    }

    func unarchiveThread(_ thread: CodexThread) async {
        guard let appServer else {
            statusMessage = "Connect to the server before unarchiving a session."
            return
        }
        await runOperation(.openingThread, status: "Unarchiving session") {
            let restored = try await appServer.unarchiveThread(threadID: thread.id)
            if let index = threads.firstIndex(where: { $0.id == restored.id }) {
                threads[index] = restored
            } else {
                threads.insert(restored, at: 0)
            }
            threadListCache.removeAll()
            await refreshThreadListAfterEvent()
        }
    }

    @discardableResult
    func refreshChangedFilesForSelectedProject() async -> [String] {
        let snapshot = await refreshDiffSnapshot()
        return snapshot.files.map(\.path)
    }

    @discardableResult
    func refreshDiffSnapshot(cwd explicitCwd: String? = nil) async -> GitDiffSnapshot {
        guard appServer != nil else {
            statusMessage = "Connect to the server before checking changed files."
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
        if selectedServer?.backendType == .acp {
            // ACP production send path (simple text prompt for v1; attachments/ rich input future).
            // Uses stored sid + client; optimistic local echo appended to acpItems so it appears via the
            // SharedKMPBridge.conversationSections mapper (identical rich UI elements as debug preview + Android).
            guard let client = acpClient, let sid = acpSessionId else {
                statusMessage = "No active ACP session."
                return false
            }
            guard !isOperationActive(.sending) else { return false }
            let text = baseInput.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: " ")
            if !text.isEmpty {
                // Local user echo as CodexThreadItem (the type the Swift client + bridge expect).
                let echo = CodexThreadItem.userMessage(id: "local-\(UUID().uuidString)", text: text)
                await MainActor.run {
                    let previousItems = acpItems
                    acpItems.append(echo)
                    applyAcpConversationChange(previous: previousItems, next: acpItems)
                }
            }
            await runOperation(.sending, status: "Sending") {
                do {
                    try await client.sendPrompt(sessionId: sid, text: text)
                } catch {
                    await MainActor.run { statusMessage = error.localizedDescription }
                }
            }
            return true
        }
        guard appServer != nil else {
            statusMessage = "Connect to the server before sending a message."
            return false
        }
        guard !isOperationActive(.sending) else { return false }

        let scope = currentThreadLoadScope
        let startingThreadID = selectedThreadID
        let startingThread = selectedThread
        var localSteerEchoID: String?
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
                        queuedTurnInputsByThreadID[thread.id, default: []].append(QueuedTurnInput(id: UUID(), input: input))
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
                        queuedTurnInputsByThreadID[thread.id, default: []].append(QueuedTurnInput(id: UUID(), input: input))
                        refreshQueuedTurnInputCount()
                        statusMessage = "Queued message until the active turn is available."
                        didSubmitInput = true
                        return
                    }
                    localSteerEchoID = appendLocalUserEcho(input: input, turnID: activeTurnID)
                    try await appServer.steer(threadID: thread.id, expectedTurnID: activeTurnID, input: input)
                    guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                        return
                    }
                    if localSteerEchoID != nil {
                        statusMessage = "Steered active turn."
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
                let displayTurn = Self.turnForDisplay(turn, input: input)
                guard currentThreadLoadScope == scope, selectedThreadID == thread.id else {
                    return
                }
                didSubmitInput = true
                thread.status = displayTurn.status == "inProgress" ? .active(flags: []) : .idle
                upsert(turn: displayTurn, in: &thread)
                selectedThread = thread
                liveItems = Self.visibleLiveItems(from: thread)
                rebuildConversationFromLiveItems()
                refreshQueuedTurnInputCount()
                if displayTurn.status == "inProgress" {
                    scheduleActiveTurnRefresh(threadID: thread.id, scope: scope)
                    shouldHydrateThreadsAfterSend = false
                }
                if displayTurn.status != "inProgress" {
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
                try await loadThreads(forceReload: true)
            } else {
                await refreshThreadListAfterEvent()
            }
        }
           if let selectedThreadID,
           selectedThread?.status.isActive != true,
           queuedTurnInputsByThreadID[selectedThreadID]?.isEmpty == false {
            await startNextQueuedTurnIfReady(threadID: selectedThreadID)
        }
        if !sent, let localSteerEchoID {
            removeLocalUserEcho(id: localSteerEchoID)
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

    func interruptActiveTurn() async {
        if let acpClient, let acpSessionId {
            await runOperation(.interrupting, status: "Interrupting") {
                try await acpClient.cancel(sessionId: acpSessionId)
                // Spec: answer in-flight permission requests with the cancelled outcome.
                for approval in pendingApprovals {
                    try? await acpClient.respondToServerRequest(
                        id: approval.requestID,
                        result: SharedKMPBridge.acpPermissionCancelledResult()
                    )
                }
                pendingApprovals = []
            }
            return
        }
        guard let appServer, let selectedThread, let activeTurnID else {
            return
        }
        await runOperation(.interrupting, status: "Interrupting") {
            try await appServer.interrupt(threadID: selectedThread.id, turnID: activeTurnID)
        }
    }

    /// Switches the live ACP session to one of the models advertised at session/new.
    func setAcpModel(_ modelId: String) async {
        guard let acpClient, let acpSessionId, acpCurrentModelId != modelId else { return }
        await runOperation(.sending, status: "Switching model") {
            try await acpClient.setModel(sessionId: acpSessionId, modelId: modelId)
            if self.acpClient === acpClient {
                self.acpCurrentModelId = modelId
                self.statusMessage = "Model switched."
            }
        }
    }

    func respond(to approval: PendingApproval, accept: Bool) async {
        await runOperation(.respondingToApproval, status: accept ? "Approving" : "Declining") {
            if let acpClient {
                // ACP permission round-trip: answer session/request_permission with the spec
                // outcome shape, picking the agent-advertised option that matches accept/decline.
                let result = SharedKMPBridge.acpPermissionResponse(params: approval.params, accept: accept)
                try await acpClient.respondToServerRequest(id: approval.requestID, result: result)
                pendingApprovals.removeAll { $0.id == approval.id }
                return
            }
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
        acpCollectorTask?.cancel()
        acpCollectorTask = nil
        acpEventsTask?.cancel()
        acpEventsTask = nil
        // Await the close so old-transport teardown cannot interleave with (and report errors
        // into) the next connection's setup.
        if let c = acpClient { await c.close() }
        acpModelOptions = []
        acpCurrentModelId = nil
        acpClient = nil
        acpSessionId = nil
        acpItems = []
        // Conversation stays visible after close; resync silently so the next incremental op
        // cannot pair a stale accumulator with the cleared item list.
        resyncConversationAccumulator(items: acpItems)
        cancelActiveTurnRefresh()
        await appServer?.close()
        appServer = nil
        pendingApprovals = []
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
        return Self.activeTurnID(in: selectedThread)
    }

    private static func activeTurnID(in thread: CodexThread) -> String? {
        guard thread.status.isActive else { return nil }
        return thread.turns.last(where: { $0.status == "inProgress" })?.id ?? thread.turns.last?.id
    }

    private var isSessionMutationInFlight: Bool {
        isOperationActive(.connecting)
            || isOperationActive(.startingSession)
            || isOperationActive(.sending)
            || isOperationActive(.interrupting)
            || isOperationActive(.respondingToApproval)
    }

    private var currentThreadLoadScope: ThreadLoadScope {
        if isShowingAllSessions {
            return ThreadLoadScope(
                serverID: selectedServerID,
                projectID: nil,
                cwd: nil,
                sessionPaths: [],
                includeArchivedSessions: showsArchivedSessions
            )
        }
        return ThreadLoadScope(
            serverID: selectedServerID,
            projectID: selectedProjectID,
            cwd: selectedProject?.path,
            sessionPaths: Set(selectedProject?.sessionPaths ?? selectedProject.map { [$0.path] } ?? []),
            includeArchivedSessions: showsArchivedSessions
        )
    }

    private func threadDetailCacheKey(threadID: String) -> ThreadDetailCacheKey {
        ThreadDetailCacheKey(serverID: selectedServerID, threadID: threadID)
    }

    private func cacheThreadList(_ threads: [CodexThread], scope: ThreadLoadScope) {
        threadListCache[scope] = CachedThreadList(
            threads: threads,
            selectedThreadID: selectedThreadID,
            fetchedAt: .now
        )
    }

    private func cacheThreadDetail(thread: CodexThread, liveItems: [CodexThreadItem], sections: [ConversationSection]) {
        let now = Date.now
        threadDetailCache[threadDetailCacheKey(threadID: thread.id)] = CachedThreadDetail(
            thread: thread,
            liveItems: liveItems,
            sections: sections,
            tokenUsage: selectedThreadID == thread.id ? selectedThreadTokenUsage : nil,
            fetchedAt: now,
            lastAccessedAt: now
        )
        pruneThreadDetailCache(now: now)
    }

    private func restoreCachedSessionState(for scope: ThreadLoadScope) -> Bool {
        guard let cachedList = threadListCache[scope] else {
            return false
        }
        let previousThreadID = selectedThreadID
        threads = cachedList.threads
        selectedThreadID = cachedSelectedThreadID(in: cachedList)
        pendingApprovals = []
        if previousThreadID != selectedThreadID {
            selectedThreadTokenUsage = nil
        }
        guard let selectedThreadID else {
            selectedThread = nil
            liveItems = []
            selectedThreadTokenUsage = nil
            resetConversationSections(items: [])
            changedFiles = []
            diffSnapshot = .empty
            clearSelectedThreadLoads()
            refreshQueuedTurnInputCount()
            return true
        }
        let selectedDetailKey = threadDetailCacheKey(threadID: selectedThreadID)
        if var detail = threadDetailCache[selectedDetailKey],
           isCacheEntryFresh(fetchedAt: detail.fetchedAt, ttl: threadDetailCacheTTL) {
            detail.lastAccessedAt = .now
            threadDetailCache[selectedDetailKey] = detail
            selectedThread = detail.thread
            liveItems = detail.liveItems
            selectedThreadTokenUsage = detail.tokenUsage
            resetConversationSections(items: detail.liveItems, prebuilt: detail.sections)
        } else if let summary = cachedList.threads.first(where: { $0.id == selectedThreadID }) {
            selectedThreadTokenUsage = nil
            hydrateConversation(from: summary, cacheDetail: false)
        } else {
            selectedThread = nil
            liveItems = []
            selectedThreadTokenUsage = nil
            resetConversationSections(items: [])
        }
        changedFiles = []
        diffSnapshot = .empty
        clearSelectedThreadLoads()
        refreshQueuedTurnInputCount()
        return true
    }

    private func canUseCachedSessionState(for scope: ThreadLoadScope) -> Bool {
        pruneThreadDetailCache(now: .now)
        guard let cachedList = threadListCache[scope],
              isSessionListCacheFresh(for: scope)
        else {
            return false
        }
        guard let selectedThreadID = cachedSelectedThreadID(in: cachedList) else {
            return true
        }
        guard let detail = threadDetailCache[threadDetailCacheKey(threadID: selectedThreadID)] else {
            return false
        }
        return isCacheEntryFresh(fetchedAt: detail.fetchedAt, ttl: threadDetailCacheTTL)
    }

    private func isThreadDetailCacheFresh(threadID: String) -> Bool {
        guard let detail = threadDetailCache[threadDetailCacheKey(threadID: threadID)] else {
            return false
        }
        return isCacheEntryFresh(fetchedAt: detail.fetchedAt, ttl: threadDetailCacheTTL)
    }

    private func pruneThreadDetailCache(now: Date) {
        threadDetailCache = threadDetailCache.filter { _, detail in
            isCacheEntryFresh(fetchedAt: detail.fetchedAt, ttl: threadDetailCacheTTL, now: now)
        }
        guard threadDetailCache.count > maxThreadDetailCacheEntries else { return }

        let selectedKey = selectedThreadID.map(threadDetailCacheKey(threadID:))
        let removableKeys = threadDetailCache
            .filter { key, _ in selectedKey.map { key != $0 } ?? true }
            .sorted { lhs, rhs in
                if lhs.value.lastAccessedAt != rhs.value.lastAccessedAt {
                    return lhs.value.lastAccessedAt < rhs.value.lastAccessedAt
                }
                return lhs.key.threadID < rhs.key.threadID
            }
            .map(\.key)

        let removalCount = max(0, threadDetailCache.count - maxThreadDetailCacheEntries)
        for key in removableKeys.prefix(removalCount) {
            threadDetailCache.removeValue(forKey: key)
        }
    }

    private func cachedSelectedThreadID(in cachedList: CachedThreadList) -> String? {
        guard !suppressCachedThreadSelection else {
            return nil
        }
        if let selectedThreadID = cachedList.selectedThreadID,
           cachedList.threads.contains(where: { $0.id == selectedThreadID }) {
            return selectedThreadID
        }
        return cachedList.threads.first?.id
    }

    private func isSessionListCacheFresh(for scope: ThreadLoadScope, now: Date = .now) -> Bool {
        guard let entry = threadListCache[scope] else {
            return false
        }
        return isCacheEntryFresh(fetchedAt: entry.fetchedAt, ttl: sessionListCacheTTL, now: now)
    }

    private func isCacheEntryFresh(fetchedAt: Date, ttl: TimeInterval, now: Date = .now) -> Bool {
        let elapsed = now.timeIntervalSince(fetchedAt)
        return ttl > 0 && elapsed >= 0 && elapsed < ttl
    }

    private func invalidateSessionCaches(for serverID: UUID?) {
        threadListCache = threadListCache.filter { key, _ in
            key.serverID != serverID
        }
        threadDetailCache = threadDetailCache.filter { key, _ in
            key.serverID != serverID
        }
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
            isShowingAllSessions = false
            selectedProjectID = selectedServer?.projects.firstAddedProjectID
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

    private func refreshProjectsUsingCredential(
        _ credential: SSHCredential,
        server: ServerRecord,
        syncActiveChatCounts: Bool,
        includeRemoteDiscovery: Bool
    ) async throws {
        let previousScope = currentThreadLoadScope
        var nextServers = servers
        guard let index = nextServers.firstIndex(where: { $0.id == server.id }) else {
            return
        }
        let discovered = if includeRemoteDiscovery {
            try await sshService.discoverProjects(server: server, credential: credential)
        } else {
            nextServers[index].projects.remoteDiscoverySnapshot
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
        let nextSelectedProjectID: UUID?
        if isShowingAllSessions {
            nextSelectedProjectID = nil
        } else if nextServers[index].projects.contains(where: { $0.id == selectedProjectID && $0.isAddedToProjectList }) {
            nextSelectedProjectID = selectedProjectID
        } else {
            nextSelectedProjectID = nextServers[index].projects.firstAddedProjectID
        }
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
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private func loadThreads(forceReload: Bool) async throws {
        guard let appServer else {
            return
        }
        let scope = currentThreadLoadScope
        if !forceReload, restoreCachedSessionState(for: scope), canUseCachedSessionState(for: scope) {
            await drainSelectedQueueIfReady()
            return
        }
        sessionRefreshListLoadGeneration &+= 1
        let listLoadGeneration = sessionRefreshListLoadGeneration
        let loadedThreads = try await listThreads(matching: scope, appServer: appServer, pageLimit: sessionListInitialPageLimit)
        guard self.appServer === appServer,
              sessionRefreshListLoadGeneration == listLoadGeneration,
              currentThreadLoadScope == scope else {
            return
        }
        let prioritizedThreads = sortedThreadsPreservingSelectedThread(
            loadedThreads,
            scope: scope,
            preserveMissingSelectedThread: true
        )
        threads = prioritizedThreads
        loadCompleteThreadListAfterInitialSessionRefresh(
            scope: scope,
            appServer: appServer,
            listLoadGeneration: listLoadGeneration
        )

        let currentSelection = selectedThreadID.flatMap { id in
            prioritizedThreads.first { $0.id == id }
        }
        if currentSelection == nil, selectedThreadID != nil {
            selectedThreadID = nil
            selectedThread = nil
            liveItems = []
            selectedThreadTokenUsage = nil
            resetConversationSections(items: [])
            changedFiles = []
            diffSnapshot = .empty
            clearSelectedThreadLoads()
            refreshQueuedTurnInputCount()
            return
        }
        if currentSelection == nil, suppressThreadAutoSelection, suppressCachedThreadSelection {
            selectedThreadID = nil
            selectedThread = nil
            liveItems = []
            selectedThreadTokenUsage = nil
            resetConversationSections(items: [])
            changedFiles = []
            diffSnapshot = .empty
            clearSelectedThreadLoads()
            refreshQueuedTurnInputCount()
            return
        }
        guard let threadToShow = currentSelection ?? prioritizedThreads.first else {
            selectedThreadID = nil
            selectedThread = nil
            liveItems = []
            selectedThreadTokenUsage = nil
            resetConversationSections(items: [])
            changedFiles = []
            diffSnapshot = .empty
            clearSelectedThreadLoads()
            refreshQueuedTurnInputCount()
            return
        }

        selectedThreadID = threadToShow.id
        if selectedThread?.id != threadToShow.id {
            hydrateConversation(from: threadToShow, cacheDetail: false)
        }

        loadSelectedThreadDetailAfterSessionRefresh(
            threadID: threadToShow.id,
            scope: scope,
            appServer: appServer,
            expectedSelectedThread: selectedThread
        )
        await drainSelectedQueueIfReady()
    }

    private func loadCompleteThreadListAfterInitialSessionRefresh(
        scope: ThreadLoadScope,
        appServer: CodexAppServerClient,
        listLoadGeneration: Int
    ) {
        Task {
            do {
                await Task.yield()
                guard self.appServer === appServer,
                      sessionRefreshListLoadGeneration == listLoadGeneration,
                      currentThreadLoadScope == scope else {
                    return
                }
                let loadedThreads = try await listThreads(matching: scope, appServer: appServer)
                guard self.appServer === appServer,
                      sessionRefreshListLoadGeneration == listLoadGeneration,
                      currentThreadLoadScope == scope else {
                    return
                }
                let sorted = sortedThreadsPreservingSelectedThread(
                    loadedThreads,
                    scope: scope,
                    preserveMissingSelectedThread: false
                )
                threads = sorted
                cacheThreadList(sorted, scope: scope)
                selectThreadAfterCompleteListLoad(
                    sorted,
                    scope: scope,
                    appServer: appServer
                )
            } catch {
                guard self.appServer === appServer,
                      sessionRefreshListLoadGeneration == listLoadGeneration,
                      currentThreadLoadScope == scope else {
                    return
                }
                statusMessage = "Session list failed to finish loading: \(error.localizedDescription)"
            }
        }
    }

    private func invalidateSessionRefreshes() {
        sessionRefreshListLoadGeneration &+= 1
        sessionRefreshDetailLoadGeneration &+= 1
    }

    private func selectThreadAfterCompleteListLoad(
        _ sortedThreads: [CodexThread],
        scope: ThreadLoadScope,
        appServer: CodexAppServerClient
    ) {
        if let selectedThreadID {
            guard let selectedSummary = sortedThreads.first(where: { $0.id == selectedThreadID }) else {
                guard !(suppressThreadAutoSelection && suppressCachedThreadSelection),
                      let fallbackThread = sortedThreads.first else {
                    self.selectedThreadID = nil
                    selectedThread = nil
                    liveItems = []
                    selectedThreadTokenUsage = nil
                    resetConversationSections(items: [])
                    changedFiles = []
                    diffSnapshot = .empty
                    clearSelectedThreadLoads()
                    refreshQueuedTurnInputCount()
                    return
                }
                self.selectedThreadID = fallbackThread.id
                hydrateConversation(from: fallbackThread, cacheDetail: false)
                loadSelectedThreadDetailAfterSessionRefresh(
                    threadID: fallbackThread.id,
                    scope: scope,
                    appServer: appServer,
                    expectedSelectedThread: selectedThread
                )
                return
            }
            let needsSummaryHydration = selectedThread?.id != selectedSummary.id
            if needsSummaryHydration {
                hydrateConversation(from: selectedSummary, cacheDetail: false)
            }
            if needsSummaryHydration || !isThreadDetailCacheFresh(threadID: selectedSummary.id) {
                loadSelectedThreadDetailAfterSessionRefresh(
                    threadID: selectedSummary.id,
                    scope: scope,
                    appServer: appServer,
                    expectedSelectedThread: selectedThread
                )
            }
            return
        }

        guard !(suppressThreadAutoSelection && suppressCachedThreadSelection),
              let threadToShow = sortedThreads.first else {
            return
        }
        selectedThreadID = threadToShow.id
        hydrateConversation(from: threadToShow, cacheDetail: false)
        loadSelectedThreadDetailAfterSessionRefresh(
            threadID: threadToShow.id,
            scope: scope,
            appServer: appServer,
            expectedSelectedThread: selectedThread
        )
    }

    private func loadSelectedThreadDetailAfterSessionRefresh(
        threadID: String,
        scope: ThreadLoadScope,
        appServer: CodexAppServerClient,
        expectedSelectedThread: CodexThread?
    ) {
        sessionRefreshDetailLoadGeneration &+= 1
        let detailLoadGeneration = sessionRefreshDetailLoadGeneration
        beginSelectedThreadLoad(threadID: threadID)
        Task {
            defer {
                endSelectedThreadLoad(threadID: threadID, scope: scope)
            }
            do {
                let hydrated = try await appServer.readThread(threadID: threadID)
                guard self.appServer === appServer,
                      sessionRefreshDetailLoadGeneration == detailLoadGeneration,
                      currentThreadLoadScope == scope,
                      selectedThreadID == threadID,
                      selectedThread == expectedSelectedThread else {
                    return
                }
                hydrateConversation(from: hydrated)
            } catch {
                guard self.appServer === appServer,
                      sessionRefreshDetailLoadGeneration == detailLoadGeneration,
                      currentThreadLoadScope == scope,
                      selectedThreadID == threadID,
                      selectedThread == expectedSelectedThread else {
                    return
                }
                statusMessage = "Session details failed to load: \(error.localizedDescription)"
            }
        }
    }

    private func resumeThreadForAttachment(_ threadID: String, appServer: CodexAppServerClient) async throws -> CodexThread {
        do {
            return try await appServer.resumeThread(threadID: threadID)
        } catch {
            statusMessage = "Opened session history; live resume failed: \(error.localizedDescription)"
            return try await appServer.readThread(threadID: threadID)
        }
    }

    private func promoteProjectToProjectList(for thread: CodexThread) {
        guard let selectedServerID else { return }
        var nextServers = servers
        guard let serverIndex = nextServers.firstIndex(where: { $0.id == selectedServerID }) else {
            return
        }
        let threadPath = thread.cwd
        let projectIndex = nextServers[serverIndex].projects.firstIndex {
            $0.path == threadPath || $0.sessionPaths.contains(threadPath)
        }
        if let projectIndex {
            guard !nextServers[serverIndex].projects[projectIndex].isAddedToProjectList else {
                return
            }
            nextServers[serverIndex].projects[projectIndex].isAdded = true
        } else {
            nextServers[serverIndex].projects.append(ProjectRecord(path: threadPath, isAdded: true))
        }
        nextServers[serverIndex].updatedAt = .now
        do {
            try persistServers(nextServers)
            servers = nextServers
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func sortedThreads(_ threads: [CodexThread]) -> [CodexThread] {
        threads.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private func sortedThreadsPreservingSelectedThread(
        _ loadedThreads: [CodexThread],
        scope: ThreadLoadScope,
        preserveMissingSelectedThread: Bool
    ) -> [CodexThread] {
        guard preserveMissingSelectedThread,
              let selectedThreadID,
              !loadedThreads.contains(where: { $0.id == selectedThreadID }),
              let selectedThread,
              selectedThread.id == selectedThreadID,
              threadMatchesScope(selectedThread, scope: scope)
        else {
            return sortedThreads(loadedThreads)
        }
        return sortedThreads(loadedThreads + [selectedThread])
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
            if method != "error", Self.shouldSurfaceNotificationStatus(method) {
                statusMessage = method
            }
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

    // Streaming-class notifications (item/* spam, deltas, terminal echo) arrive tens of times
    // per second; publishing each to `statusMessage` would invalidate every observer of the
    // view model per delta. Turn/thread lifecycle methods still surface.
    private static func shouldSurfaceNotificationStatus(_ method: String) -> Bool {
        if method.hasPrefix("item/") { return false }
        if method.localizedCaseInsensitiveContains("delta") { return false }
        if method.contains("terminalInteraction") { return false }
        return true
    }

    private func handleNotification(method: String, params: JSONValue?) async {
        switch method {
        case "error":
            guard eventTargetsSelectedThread(params),
                  let error = try? decode(CodexTurnError.self, from: params?["error"])
            else {
                return
            }
            let willRetry = params?["willRetry"]?.boolValue ?? false
            showTurnError(error, turnID: params?["turnId"]?.stringValue, willRetry: willRetry)
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
                if turn.status == "failed", let error = turn.error {
                    statusMessage = turnErrorStatusMessage(error)
                }
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
            let loadedThreads = try await listThreads(matching: scope, appServer: appServer)
            guard currentThreadLoadScope == scope else {
                return
            }
            let sorted = sortedThreads(loadedThreads)
            threads = sorted
            cacheThreadList(sorted, scope: scope)
            if let selectedSummary = loadedThreads.first(where: { $0.id == selectedThreadID }),
               selectedSummary.status.isActive {
                applySelectedThreadStatus(selectedSummary.status)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshThreadListAfterEvent() async {
        guard let appServer else { return }
        let scope = currentThreadLoadScope
        do {
            let loadedThreads = try await listThreads(matching: scope, appServer: appServer)
            guard currentThreadLoadScope == scope else {
                return
            }
            let sorted = sortedThreads(loadedThreads)
            threads = sorted
            cacheThreadList(sorted, scope: scope)
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
        statusMessage = "\(message) Reconnecting server."
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
                statusMessage = "\(disconnectMessage) Reconnecting server."
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
        if scope.sessionPaths.contains(thread.cwd) {
            return true
        }
        guard let projectPath = scope.cwd, let selectedServer else {
            return false
        }
        return SharedKMPBridge.sessionIDsForProject(
            threads: [thread],
            projects: selectedServer.projects,
            projectPath: projectPath
        ).contains(thread.id)
    }

    private func listThreads(
        matching scope: ThreadLoadScope,
        appServer: CodexAppServerClient,
        pageLimit: Int? = nil
    ) async throws -> [CodexThread] {
        guard !scope.sessionPaths.isEmpty else {
            return try await appServer.listThreads(
                cwd: nil,
                includeArchived: scope.includeArchivedSessions,
                pageLimit: pageLimit
            )
        }
        var merged: [CodexThread] = []
        var seen = Set<String>()
        for cwd in scope.sessionPaths.sorted() {
            let loaded = try await appServer.listThreads(
                cwd: cwd,
                includeArchived: scope.includeArchivedSessions,
                pageLimit: pageLimit
            )
            for thread in loaded where seen.insert(thread.id).inserted {
                merged.append(thread)
            }
        }
        if let projectPath = scope.cwd,
           let selectedServer {
            let unscopedThreads = try await appServer.listThreads(
                cwd: nil,
                includeArchived: scope.includeArchivedSessions,
                pageLimit: pageLimit
            )
            let groupedSessionIDs = SharedKMPBridge.sessionIDsForProject(
                threads: unscopedThreads,
                projects: selectedServer.projects,
                projectPath: projectPath
            )
            for thread in unscopedThreads where groupedSessionIDs.contains(thread.id) && seen.insert(thread.id).inserted {
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

    private func hydrateConversation(from thread: CodexThread, cacheDetail: Bool = true) {
        sessionRefreshDetailLoadGeneration &+= 1
        let displayThread = threadPreservingExistingUserMessages(thread, existing: selectedThread)
        selectedThread = displayThread
        liveItems = Self.visibleLiveItems(from: displayThread)
        if !cacheDetail {
            suppressNextConversationDetailCache = true
        }
        defer {
            if !cacheDetail {
                suppressNextConversationDetailCache = false
            }
        }
        rebuildConversationFromLiveItems()
        if cacheDetail {
            cacheThreadList(threads, scope: currentThreadLoadScope)
        }
        refreshQueuedTurnInputCount()
        if thread.status.isActive {
            scheduleActiveTurnRefresh(threadID: thread.id, scope: currentThreadLoadScope)
        } else if activeTurnRefreshThreadID == thread.id {
            cancelActiveTurnRefresh()
        }
        if !thread.status.isActive {
            Task { await self.drainSelectedQueueIfReady() }
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
        let currentThread = selectedThread
        let displayThread = threadPreservingExistingUserMessages(polledThread, existing: currentThread)
        selectedThread = displayThread
        if let index = threads.firstIndex(where: { $0.id == displayThread.id }) {
            threads[index] = displayThread
        }
        liveItems = Self.mergedLiveItems(
            current: liveItems,
            polled: displayThread.turns.flatMap(\.items),
            dropCurrentItemIDs: Self.currentUserEchoItemIDs(currentThread: currentThread, polledThread: displayThread)
        )
        rebuildConversationFromLiveItems()
        refreshQueuedTurnInputCount()
    }

    static func mergedLiveItems(
        current: [CodexThreadItem],
        polled: [CodexThreadItem],
        dropCurrentItemIDs: Set<String> = []
    ) -> [CodexThreadItem] {
        let currentByID = bestItemsByID(current)
        var seen = Set<String>()
        var indexByID: [String: Int] = [:]
        var merged: [CodexThreadItem] = []
        for polledItem in polled {
            if let index = indexByID[polledItem.id] {
                merged[index] = bestLiveItem(merged[index], polledItem)
                continue
            }
            seen.insert(polledItem.id)
            let item = currentByID[polledItem.id].map { bestLiveItem($0, polledItem) } ?? polledItem
            indexByID[polledItem.id] = merged.count
            merged.append(item)
        }
        for currentItem in current {
            guard seen.insert(currentItem.id).inserted else {
                continue
            }
            if dropCurrentItemIDs.contains(currentItem.id) {
                continue
            }
            let item = currentByID[currentItem.id] ?? currentItem
            indexByID[currentItem.id] = merged.count
            merged.append(item)
        }
        return merged
    }

    static func currentUserEchoItemIDs(currentThread: CodexThread?, polledThread: CodexThread) -> Set<String> {
        guard let currentThread else {
            return []
        }
        let polledTurnsByID = Dictionary(uniqueKeysWithValues: polledThread.turns.map { ($0.id, $0) })
        var echoIDs = Set<String>()
        for currentTurn in currentThread.turns {
            guard let polledTurn = polledTurnsByID[currentTurn.id] else {
                continue
            }
            let polledUserTexts = Set(polledTurn.items.compactMap { item -> String? in
                if case .userMessage(_, let text) = item {
                    return text
                }
                return nil
            })
            let polledItemIDs = Set(polledTurn.items.map(\.id))
            guard !polledUserTexts.isEmpty else {
                continue
            }
            for item in currentTurn.items {
                if case .userMessage(let id, let text) = item,
                   !polledItemIDs.contains(id),
                   polledUserTexts.contains(text) {
                    echoIDs.insert(id)
                }
            }
        }
        return echoIDs
    }

    private static func bestItemsByID(_ items: [CodexThreadItem]) -> [String: CodexThreadItem] {
        var result: [String: CodexThreadItem] = [:]
        for item in items {
            result[item.id] = result[item.id].map { bestLiveItem($0, item) } ?? item
        }
        return result
    }

    private static func bestLiveItem(_ lhs: CodexThreadItem, _ rhs: CodexThreadItem) -> CodexThreadItem {
        if lhs.mergeStatusRank != rhs.mergeStatusRank {
            return lhs.mergeStatusRank > rhs.mergeStatusRank ? lhs : rhs
        }
        if lhs.mergeScore != rhs.mergeScore {
            return lhs.mergeScore > rhs.mergeScore ? lhs : rhs
        }
        return rhs
    }

    private func rebuildConversationFromLiveItems() {
        resetConversationSections(items: liveItems)
    }

    /// Full re-projection: resyncs the accumulator to `items` and publishes immediately.
    /// Hydration, turn boundaries, and structural edits (removal, reorder, id changes) must
    /// not lag behind the streaming conflation window.
    private func resetConversationSections(items: [CodexThreadItem], prebuilt: [ConversationSection]? = nil) {
        conversationAccumulator.reset(items: items, prebuilt: prebuilt)
        flushConversationSections()
    }

    /// Resyncs the accumulator without publishing (and drops any pending conflated flush).
    /// Used where the item list is cleared but the published conversation intentionally stays
    /// on screen (e.g. closeConnection keeps the last conversation visible).
    private func resyncConversationAccumulator(items: [CodexThreadItem]) {
        conversationFlushTask?.cancel()
        conversationFlushTask = nil
        conversationAccumulator.reset(items: items)
    }

    /// Incremental delta path: re-projects only the mutated item and conflates the publish.
    /// Falls back to a full rebuild whenever the accumulator no longer mirrors liveItems.
    private func updateLiveItemIncrementally(at index: Int, with item: CodexThreadItem) {
        liveItems[index] = item
        guard conversationAccumulator.sections.count == liveItems.count,
              conversationAccumulator.updateAt(index, with: item)
        else {
            rebuildConversationFromLiveItems()
            return
        }
        scheduleConversationFlush()
    }

    private func appendLiveItemIncrementally(_ item: CodexThreadItem) {
        liveItems.append(item)
        guard conversationAccumulator.sections.count == liveItems.count - 1 else {
            rebuildConversationFromLiveItems()
            return
        }
        conversationAccumulator.append(item)
        scheduleConversationFlush()
    }

    /// ACP collector path: `appendingAcpThreadItem` returns a fresh array that differs from
    /// the previous one by at most one element (append or in-place merge). Map that change
    /// onto the accumulator; anything else falls back to a full re-projection.
    private func applyAcpConversationChange(previous: [CodexThreadItem], next: [CodexThreadItem]) {
        guard conversationAccumulator.sections.count == previous.count else {
            resetConversationSections(items: next)
            return
        }
        if next.count == previous.count + 1, let appended = next.last {
            conversationAccumulator.append(appended)
            scheduleConversationFlush()
            return
        }
        if next.count == previous.count {
            guard let changedIndex = next.indices.first(where: { previous[$0] != next[$0] }) else {
                return
            }
            guard conversationAccumulator.updateAt(changedIndex, with: next[changedIndex]) else {
                resetConversationSections(items: next)
                return
            }
            scheduleConversationFlush()
            return
        }
        resetConversationSections(items: next)
    }

    /// Conflated publish for streaming updates: immediate when outside the flush window
    /// (leading edge), otherwise a single trailing flush is scheduled for the window's end.
    private func scheduleConversationFlush() {
        guard conversationFlushTask == nil else { return }
        let now = ContinuousClock.now
        guard let lastFlush = lastConversationFlushAt, now - lastFlush < conversationFlushInterval else {
            flushConversationSections()
            return
        }
        let delay = conversationFlushInterval - (now - lastFlush)
        conversationFlushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.conversationFlushTask = nil
            self.flushConversationSections()
        }
    }

    private func flushConversationSections() {
        conversationFlushTask?.cancel()
        conversationFlushTask = nil
        lastConversationFlushAt = ContinuousClock.now
        publishConversationSections(conversationAccumulator.sections)
    }

    private static func visibleLiveItems(from thread: CodexThread) -> [CodexThreadItem] {
        thread.turns.flatMap { turn in
            var items = turn.items
            if let errorItem = failedTurnErrorItem(turn) {
                items.append(errorItem)
            }
            return items
        }
    }

    private static func failedTurnErrorItem(_ turn: CodexTurn) -> CodexThreadItem? {
        guard turn.status == "failed", let error = turn.error else {
            return nil
        }
        return turnErrorItem(error, turnID: turn.id, willRetry: false)
    }

    private static func turnErrorItem(_ error: CodexTurnError, turnID: String, willRetry: Bool) -> CodexThreadItem {
        .agentEvent(
            id: "turn-error-\(turnID)",
            label: willRetry ? "Turn Error" : "Turn Failed",
            status: willRetry ? "retrying" : "failed",
            detail: [error.message.nonEmpty, error.displayDetail].compactMap { $0 }.joined(separator: "\n")
        )
    }

    private func showTurnError(_ error: CodexTurnError, turnID: String?, willRetry: Bool) {
        statusMessage = turnErrorStatusMessage(error, willRetry: willRetry)
        let item = Self.turnErrorItem(
            error,
            turnID: turnID?.nonEmpty ?? "live-\(abs(error.message.hashValue))",
            willRetry: willRetry
        )
        upsertLiveItem(item)
    }

    private func turnErrorStatusMessage(_ error: CodexTurnError, willRetry: Bool = false) -> String {
        let prefix = willRetry ? "Temporary Codex error" : "Codex turn failed"
        return "\(prefix): \(error.message)"
    }

    private func publishConversationSections(_ nextSections: [ConversationSection]) {
        let didChange = conversationSections != nextSections
        if didChange {
            conversationSections = nextSections
        }
        if let selectedThread, !suppressNextConversationDetailCache {
            cacheThreadDetail(thread: selectedThread, liveItems: liveItems, sections: nextSections)
        }
        guard didChange else { return }
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
        guard let last = sections.last else { return "" }
        return [
            "\(sections.count)",
            last.id,
            "\(last.kind)",
            "\(last.title.count)",
            "\(last.body.count)",
            "\(last.detail?.count ?? 0)",
            "\(last.status?.count ?? 0)"
        ].joined(separator: ":")
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
        let nextTurn = turnPreservingLocalUserEcho(turn, in: thread)
        if let index = thread.turns.firstIndex(where: { $0.id == turn.id }) {
            thread.turns[index] = nextTurn
        } else {
            thread.turns.append(nextTurn)
        }
    }

    private func upsertLiveItem(_ item: CodexThreadItem) {
        if case .userMessage(_, let text) = item {
            let localEchoIndex = liveItems.firstIndex(where: { existing in
               if case .userMessage(let id, let existingText) = existing {
                   return id.hasPrefix("local-user-") && existingText == text
               }
               return false
            })
            if let localEchoIndex {
                let localEchoID = liveItems[localEchoIndex].id
                liveItems[localEchoIndex] = item
                replaceSelectedThreadItem(id: localEchoID, with: item)
                // The item id changed (local echo -> server id), so the section id changes too:
                // not expressible as an in-place update — full re-projection.
                rebuildConversationFromLiveItems()
                return
            }
            replaceSelectedThreadLocalUserEcho(text: text, with: item)
        }
        if let index = liveItems.firstIndex(where: { $0.id == item.id }) {
            updateLiveItemIncrementally(at: index, with: item)
        } else {
            appendLiveItemIncrementally(item)
        }
    }

    private func replaceSelectedThreadItem(id itemID: String, with item: CodexThreadItem) {
        guard var thread = selectedThread else { return }
        var didReplace = false
        thread.turns = thread.turns.map { turn in
            guard turn.items.contains(where: { $0.id == itemID }) else {
                return turn
            }
            didReplace = true
            var turn = turn
            turn.items = turn.items.map { $0.id == itemID ? item : $0 }
            return turn
        }
        if didReplace {
            selectedThread = thread
        }
    }

    private func replaceSelectedThreadLocalUserEcho(text: String, with item: CodexThreadItem) {
        guard var thread = selectedThread else { return }
        for turnIndex in thread.turns.indices.reversed() {
            guard let itemIndex = thread.turns[turnIndex].items.firstIndex(where: { existing in
                if case .userMessage(let id, let existingText) = existing {
                    return id.hasPrefix("local-user-") && existingText == text
                }
                return false
            }) else {
                continue
            }
            thread.turns[turnIndex].items[itemIndex] = item
            selectedThread = thread
            return
        }
    }

    private func turnPreservingLocalUserEcho(_ turn: CodexTurn, in thread: CodexThread) -> CodexTurn {
        guard let existing = thread.turns.first(where: { $0.id == turn.id }) else { return turn }
        return Self.turnMergingLocalUserEchoes(turn, existing: existing)
    }

    private func threadPreservingExistingUserMessages(_ thread: CodexThread, existing: CodexThread?) -> CodexThread {
        guard let existing else { return thread }
        var thread = thread
        thread.turns = thread.turns.map { turn in
            guard let existingTurn = existing.turns.first(where: { $0.id == turn.id }) else { return turn }
            return Self.turnMergingLocalUserEchoes(turn, existing: existingTurn)
        }
        return thread
    }

    private static func turnMergingLocalUserEchoes(_ incoming: CodexTurn, existing: CodexTurn) -> CodexTurn {
        let incomingUserIDs = Set(incoming.items.compactMap { item -> String? in
            if case .userMessage(let id, _) = item { return id }
            return nil
        })
        let incomingUserTexts = Set(incoming.items.compactMap { item -> String? in
            if case .userMessage(_, let text) = item { return text }
            return nil
        })
        let localEchoes = existing.items.compactMap { item -> CodexThreadItem? in
            guard case .userMessage(let id, let text) = item,
                  id.hasPrefix("local-user-"),
                  !incomingUserIDs.contains(id),
                  !incomingUserTexts.contains(text)
            else {
                return nil
            }
            return item
        }
        guard !localEchoes.isEmpty else { return incoming }
        var turn = incoming
        let insertAt = turn.items.prefix { Self.isUserMessage($0) }.count
        turn.items.insert(contentsOf: localEchoes, at: insertAt)
        return turn
    }

    private static func isUserMessage(_ item: CodexThreadItem) -> Bool {
        if case .userMessage = item { return true }
        return false
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
        liveItems = Self.visibleLiveItems(from: thread)
        rebuildConversationFromLiveItems()
        scheduleActiveTurnRefresh(threadID: thread.id, scope: currentThreadLoadScope)
    }

    @discardableResult
    private func appendLocalUserEcho(input: [CodexInputItem], turnID: String) -> String? {
        guard let text = Self.displayText(for: input) else { return nil }
        guard !liveItems.contains(where: { existing in
            if case .userMessage(_, let existingText) = existing {
                return existingText == text
            }
            return false
        }) else {
            return nil
        }
        let item = CodexThreadItem.userMessage(id: "local-user-\(turnID)-\(UUID().uuidString)", text: text)
        if var thread = selectedThread {
            if let turnIndex = thread.turns.firstIndex(where: { $0.id == turnID }) {
                thread.turns[turnIndex].items.append(item)
            } else {
                thread.turns.append(CodexTurn(id: turnID, items: [item], status: "inProgress"))
            }
            selectedThread = thread
        }
        appendLiveItemIncrementally(item)
        return item.id
    }

    private func removeLocalUserEcho(id itemID: String) {
        liveItems.removeAll { $0.id == itemID }
        if var thread = selectedThread {
            thread.turns = thread.turns.map { turn in
                var turn = turn
                turn.items.removeAll { $0.id == itemID }
                return turn
            }
            selectedThread = thread
        }
        rebuildConversationFromLiveItems()
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
        liveItems = Self.visibleLiveItems(from: thread)
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

    private func drainSelectedQueueIfReady() async {
        guard let selectedThreadID,
              selectedThread?.status.isActive != true,
              queuedTurnInputsByThreadID[selectedThreadID]?.isEmpty == false
        else {
            return
        }
        await startNextQueuedTurnIfReady(threadID: selectedThreadID)
    }

    private func startNextQueuedTurnIfReady(threadID: String) async {
        guard appServer != nil,
              selectedThreadID == threadID,
              selectedThread?.status.isActive != true,
              !isOperationActive(.sending),
              let queuedInput = dequeueQueuedInput(threadID: threadID)
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
                input: queuedInput.input,
                options: currentTurnOptions(cwd: selectedThread?.cwd ?? scope.cwd)
            )
            let displayTurn = Self.turnForDisplay(turn, input: queuedInput.input)
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
            thread.status = displayTurn.status == "inProgress" ? .active(flags: []) : .idle
            upsert(turn: displayTurn, in: &thread)
            selectedThread = thread
            liveItems = Self.visibleLiveItems(from: thread)
            rebuildConversationFromLiveItems()

            if displayTurn.status == "inProgress" {
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
            prependQueuedInput(queuedInput, threadID: threadID)
        } else if selectedThreadID == threadID,
                  selectedThread?.status.isActive != true,
                  queuedTurnInputsByThreadID[threadID]?.isEmpty == false {
            await startNextQueuedTurnIfReady(threadID: threadID)
        }
    }

    private static func turnForDisplay(_ turn: CodexTurn, input: [CodexInputItem]) -> CodexTurn {
        guard !turn.items.contains(where: { item in
            if case .userMessage = item { return true }
            return false
        }),
              let text = displayText(for: input)
        else {
            return turn
        }
        var turn = turn
        turn.items.insert(.userMessage(id: "local-user-\(turn.id)", text: text), at: 0)
        return turn
    }

    private static func displayText(for input: [CodexInputItem]) -> String? {
        let text = input.map { item in
            switch item {
            case .text(let text):
                return text
            case .imageURL(let url):
                return "[image: \(url)]"
            case .localImage(let path):
                return "[localImage: \(URL(fileURLWithPath: path).lastPathComponent)]"
            case .skill(let name, _):
                return "[skill: \(name)]"
            case .mention(let name, _):
                return "[mention: \(name)]"
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        return text.nonEmpty
    }

    private func dequeueQueuedInput(threadID: String) -> QueuedTurnInput? {
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

    private func prependQueuedInput(_ input: QueuedTurnInput, threadID: String) {
        var queue = queuedTurnInputsByThreadID[threadID] ?? []
        queue.insert(input, at: 0)
        queuedTurnInputsByThreadID[threadID] = queue
        refreshQueuedTurnInputCount()
    }

    private func refreshQueuedTurnInputCount() {
        queuedTurnInputs = selectedThreadID.flatMap { queuedTurnInputsByThreadID[$0] } ?? []
        queuedTurnInputCount = queuedTurnInputs.count
    }

    private func appendAgentMessageDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .agentMessage(let id, let text) = liveItems[index] {
            updateLiveItemIncrementally(at: index, with: .agentMessage(id: id, text: text + delta))
        } else {
            appendLiveItemIncrementally(.agentMessage(id: itemID, text: delta))
        }
    }

    private func appendCommandOutputDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .command(let id, let command, let cwd, let status, let output) = liveItems[index] {
            updateLiveItemIncrementally(
                at: index,
                with: .command(id: id, command: command, cwd: cwd, status: status, output: (output ?? "") + delta)
            )
        } else {
            appendLiveItemIncrementally(.command(id: itemID, command: "Command", cwd: "", status: "inProgress", output: delta))
        }
    }

    private func appendPlanDelta(itemID: String?, delta: String?) {
        guard let itemID, let delta else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .plan(let id, let text) = liveItems[index] {
            updateLiveItemIncrementally(at: index, with: .plan(id: id, text: text + delta))
        } else {
            appendLiveItemIncrementally(.plan(id: itemID, text: delta))
        }
    }

    private func applyTurnPlanUpdate(turnID: String?, params: JSONValue?) {
        guard let turnID else { return }
        let itemID = "turn-plan-\(turnID)"
        let text = turnPlanText(explanation: params?["explanation"]?.stringValue, plan: params?["plan"])
        guard !text.isEmpty else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .plan(let id, _) = liveItems[index] {
            updateLiveItemIncrementally(at: index, with: .plan(id: id, text: text))
        } else {
            appendLiveItemIncrementally(.plan(id: itemID, text: text))
        }
    }

    private func applyTurnDiffUpdate(turnID: String?, diff: String?) {
        guard let turnID, let diff, !diff.isEmpty else { return }
        let itemID = "turn-diff-\(turnID)"
        let change = CodexFileChange(path: "Turn diff", diff: diff)
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .fileChange = liveItems[index] {
            updateLiveItemIncrementally(at: index, with: .fileChange(id: itemID, changes: [change], status: "inProgress"))
        } else {
            appendLiveItemIncrementally(.fileChange(id: itemID, changes: [change], status: "inProgress"))
        }
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
            updateLiveItemIncrementally(
                at: index,
                with: .fileChange(id: itemID, changes: changes, status: status.isEmpty ? "inProgress" : status)
            )
        } else {
            appendLiveItemIncrementally(.fileChange(id: itemID, changes: changes, status: "inProgress"))
        }
    }

    private func appendToolProgress(itemID: String?, message: String?) {
        guard let itemID, let message, !message.isEmpty else { return }
        if let index = liveItems.firstIndex(where: { $0.id == itemID }),
           case .toolCall(let id, let label, _, let detail) = liveItems[index] {
            let nextDetail = [detail, message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            updateLiveItemIncrementally(at: index, with: .toolCall(id: id, label: label, status: "inProgress", detail: nextDetail))
        } else {
            appendLiveItemIncrementally(.toolCall(id: itemID, label: "MCP tool", status: "inProgress", detail: message))
        }
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
            updateLiveItemIncrementally(
                at: index,
                with: .fileChange(id: itemID, changes: changes, status: status.isEmpty ? "inProgress" : status)
            )
        } else {
            appendLiveItemIncrementally(.fileChange(id: itemID, changes: [patchOutput], status: "inProgress"))
        }
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
            updateLiveItemIncrementally(at: index, with: .reasoning(id: itemID, summary: summary, content: content))
        } else {
            update(&summary, &content)
            appendLiveItemIncrementally(.reasoning(id: itemID, summary: summary, content: content))
        }
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
        resetConversationSections(items: [])
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

private func withTimeout<T: Sendable>(
    seconds: Double,
    timeoutMessage: String = "",
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let state = TimeoutContinuation(continuation)
        let operationTask = Task {
            do {
                state.resume(with: .success(try await operation()))
            } catch {
                state.resume(with: .failure(error))
            }
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                return
            }
            let message = timeoutMessage.isEmpty
                ? "Remote folder browsing timed out after \(Int(seconds)) seconds."
                : timeoutMessage
            state.resume(with: .failure(AppViewModelError.operationTimedOut(message)))
        }
        state.onResume {
            operationTask.cancel()
            timeoutTask.cancel()
        }
    }
}

private func timeoutSecondsLabel(_ seconds: Double) -> Int {
    max(1, Int(ceil(seconds)))
}

private final class TimeoutContinuation<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var cancellation: (() -> Void)?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func onResume(_ cancellation: @escaping () -> Void) {
        var shouldCancel = false
        lock.withLock {
            if continuation == nil {
                shouldCancel = true
            } else {
                self.cancellation = cancellation
            }
        }
        if shouldCancel {
            cancellation()
        }
    }

    func resume(with result: Result<T, Error>) {
        let pair: (CheckedContinuation<T, Error>, (() -> Void)?)? = lock.withLock {
            guard let continuation else {
                return nil
            }
            self.continuation = nil
            let cancellation = self.cancellation
            self.cancellation = nil
            return (continuation, cancellation)
        }
        guard let pair else {
            return
        }
        pair.1?()
        pair.0.resume(with: result)
    }
}

/// Swift mirror of the shared-core `ConversationSectionAccumulator` (CodexSessionProjection.kt):
/// maintains the projected section list so streaming deltas cost one bridged item conversion
/// instead of re-projecting the entire conversation across the KMP boundary per delta.
///
/// Invariant: after any sequence of operations, `sections` equals
/// `SharedKMPBridge.conversationSections(from: items)` for the mirrored item list — including
/// the `#n` dedup suffixes, which `allocate` mirrors from the shared `uniquelyIdentified`
/// exactly. Callers fall back to `reset` for any operation they cannot map incrementally.
final class ConversationSectionAccumulator {
    private var emittedIDs: Set<String> = []
    private var countsByID: [String: Int] = [:]
    private(set) var sections: [ConversationSection] = []

    /// Rebuilds from scratch. When `prebuilt` is supplied (a full projection of the same item
    /// list, e.g. from the thread-detail cache), it is adopted verbatim and only the
    /// id-allocation state is replayed from the item ids — valid because every section's
    /// pre-dedup id is its item's id.
    func reset(items: [CodexThreadItem], prebuilt: [ConversationSection]? = nil) {
        emittedIDs.removeAll(keepingCapacity: true)
        countsByID.removeAll(keepingCapacity: true)
        for item in items {
            _ = allocate(item.id)
        }
        if let prebuilt, prebuilt.count == items.count {
            sections = prebuilt
        } else {
            sections = items.isEmpty ? [] : SharedKMPBridge.conversationSections(from: items)
        }
    }

    func append(_ item: CodexThreadItem) {
        sections.append(SharedKMPBridge.conversationSection(from: item, id: allocate(item.id)))
    }

    /// Re-projects one item in place, preserving the section's allocated id (streaming updates
    /// never change row identity). Returns false when the index is out of range.
    @discardableResult
    func updateAt(_ index: Int, with item: CodexThreadItem) -> Bool {
        guard sections.indices.contains(index) else { return false }
        sections[index] = SharedKMPBridge.conversationSection(from: item, id: sections[index].id)
        return true
    }

    // Mirrors the shared `uniquelyIdentified` suffixing exactly.
    private func allocate(_ baseID: String) -> String {
        if emittedIDs.insert(baseID).inserted {
            return baseID
        }
        var count = (countsByID[baseID] ?? 1) + 1
        var nextID = "\(baseID)#\(count)"
        while !emittedIDs.insert(nextID).inserted {
            count += 1
            nextID = "\(baseID)#\(count)"
        }
        countsByID[baseID] = count
        return nextID
    }
}
