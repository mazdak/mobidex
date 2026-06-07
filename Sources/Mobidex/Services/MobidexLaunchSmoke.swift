import Foundation

enum MobidexLaunchSmoke {
    private static let resultFilename = "mobidex-smoke-result.json"
    fileprivate static let defaultServerID = UUID(uuidString: "00000000-0000-0000-0000-00000000D0C5")!

    @MainActor
    static func runIfRequested(model: AppViewModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MOBIDEX_SMOKE"] == "1" else { return }

        var currentStage = "configuring"
        do {
            let config = try SmokeConfig(environment: environment)
            currentStage = "saving-server"
            try writeResult(.running(stage: "saving-server", message: nil))

            let server = ServerRecord(
                id: config.serverID,
                displayName: config.displayName,
                host: config.host,
                port: config.port,
                username: config.username,
                codexPath: config.codexPath,
                executionPath: config.executionPath,
                authMethod: config.authMethod,
                projects: [config.seedProject]
            )
            let saved = await model.saveServer(
                server,
                credential: SSHCredential(
                    password: config.password,
                    privateKeyPEM: config.privateKey,
                    privateKeyPassphrase: config.privateKeyPassphrase
                )
            )
            guard saved else {
                throw SmokeError.failed(model.statusMessage ?? "Saving the smoke server failed.")
            }

            if config.mode == "seed" {
                try writeResult(.success(
                    message: "In-app SSH seed smoke ready.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: false
                ))
                return
            }

            if config.mode == "connection" {
                currentStage = "testing-connection"
                try writeResult(.running(stage: "testing-connection", message: nil))
                await model.testSelectedConnection()
                if case .failed(let message) = model.connectionState {
                    throw SmokeError.failed(message)
                }
                try writeResult(.success(
                    message: "In-app SSH connection smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: false
                ))
                return
            }

            if config.mode == "add-discovered-project" {
                currentStage = "adding-discovered-project"
                try writeResult(.running(stage: "adding-discovered-project", message: nil))
                guard model.addProject(path: config.cwd) else {
                    throw SmokeError.failed(model.statusMessage ?? "Adding discovered project failed.")
                }
                guard model.selectedProject?.path == config.cwd,
                      model.selectedProject?.isAddedToProjectList == true
                else {
                    throw SmokeError.failed("Discovered project was not selected as an added project.")
                }
                try writeResult(.success(
                    message: "In-app add discovered project smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.selectedServer?.projects.filter(\.isAddedToProjectList).count ?? 0,
                    conversationSectionCount: 0,
                    assistantSectionCount: 0,
                    expectedTextFound: false,
                    selectedThreadLoaded: false
                ))
                return
            }

            if config.mode == "terminal" {
                let expectedText = config.expectedText ?? "mobidex-terminal-smoke"
                currentStage = "opening-terminal"
                try writeResult(.running(stage: "opening-terminal", message: nil))
                let terminal = try await model.openTerminalSession(columns: 80, rows: 24)
                let capture = TerminalSmokeCapture()
                let reader = Task {
                    do {
                        for try await data in terminal.output {
                            await capture.append(data)
                        }
                    } catch {
                        await capture.fail(error)
                    }
                }
                defer {
                    reader.cancel()
                    Task { await terminal.close() }
                }

                currentStage = "writing-terminal-command"
                try writeResult(.running(stage: "writing-terminal-command", message: nil))
                try await terminal.write(Data("printf '%s\\r\\n' \(expectedText.shellQuotedForSmokeCommand())\r".utf8))

                currentStage = "waiting-for-terminal-output"
                try writeResult(.running(stage: "waiting-for-terminal-output", message: nil))
                let deadline = Date().addingTimeInterval(config.timeout)
                var foundOutput = false
                while Date() < deadline {
                    if let error = await capture.errorMessage {
                        throw SmokeError.failed("Terminal output stream failed: \(error)")
                    }
                    if await capture.contains(expectedText) {
                        foundOutput = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                guard foundOutput else {
                    let preview = await capture.preview()
                    throw SmokeError.failed("Timed out waiting for terminal output. Captured: \(preview)")
                }

                try writeResult(.success(
                    message: "In-app SSH terminal smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: true,
                    selectedThreadLoaded: model.selectedThread != nil
                ))
                return
            }

            currentStage = "connecting"
            try writeResult(.running(stage: "connecting", message: nil))
            await model.connectSelectedServer()
            guard model.connectionState == .connected else {
                throw SmokeError.failed(model.connectionState.label)
            }

            if config.mode == "new-session" {
                currentStage = "starting-new-session"
                try writeResult(.running(stage: "starting-new-session", message: nil))
                guard await model.startNewSession(location: config.newSessionLocation) != nil else {
                    throw SmokeError.failed(model.statusMessage ?? "Starting a new session failed.")
                }
                guard model.selectedThread != nil else {
                    throw SmokeError.failed("New session did not select a thread.")
                }

                var expectedTextFound = false
                if let prompt = config.prompt {
                    currentStage = "sending-new-session-turn"
                    try writeResult(.running(stage: "sending-new-session-turn", message: nil))
                    await model.sendComposerText(prompt)
                    currentStage = "waiting-for-new-session-text"
                    try writeResult(.running(stage: "waiting-for-new-session-text", message: nil))
                    expectedTextFound = await waitForExpectedText(config.expectedText, model: model, timeout: config.timeout)
                    guard expectedTextFound else {
                        throw SmokeError.failed("Timed out waiting for expected assistant text.")
                    }
                }

                try writeResult(.success(
                    message: "In-app SSH new-session smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: expectedTextFound,
                    selectedThreadLoaded: model.selectedThread != nil
                ))
                return
            }

            if config.mode == "join" {
                currentStage = "loading-sessions"
                try writeResult(.running(stage: "loading-sessions", message: nil))
                await model.refreshThreadsIfNeeded()
                guard let thread = model.threads.first else {
                    throw SmokeError.failed("No existing sessions were returned for \(config.cwd).")
                }
                currentStage = "opening-session"
                try writeResult(.running(stage: "opening-session", message: nil))
                await model.openThread(thread)
                let threadLoaded = await waitForCondition(timeout: config.timeout) {
                    model.selectedThread?.id == thread.id
                }
                guard threadLoaded else {
                    throw SmokeError.failed("Timed out waiting for existing session to open.")
                }
                try writeResult(.success(
                    message: "In-app SSH join smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: false,
                    selectedThreadLoaded: true
                ))
                return
            }

            if config.mode == "browse-directories" {
                currentStage = "browsing-directories"
                try writeResult(.running(stage: "browsing-directories", message: nil))
                let listing = try await model.listRemoteDirectories(path: config.browsePath)
                guard !listing.entries.isEmpty else {
                    throw SmokeError.failed("Remote folder browser returned no folders for \(listing.path).")
                }
                try writeResult(.success(
                    message: "In-app SSH remote folder browse smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: listing.entries.count,
                    conversationSectionCount: 0,
                    assistantSectionCount: 0,
                    expectedTextFound: false,
                    selectedThreadLoaded: false
                ))
                return
            }

            if config.mode == "control" {
                currentStage = "starting-control-turn"
                try writeResult(.running(stage: "starting-control-turn", message: nil))
                await model.sendComposerText(config.prompt ?? "Start control smoke")

                currentStage = "waiting-for-approval"
                try writeResult(.running(stage: "waiting-for-approval", message: nil))
                guard let approval = await waitForApproval(model: model, timeout: config.timeout) else {
                    throw SmokeError.failed("Timed out waiting for approval request.")
                }

                currentStage = "approving"
                try writeResult(.running(stage: "approving", message: nil))
                await model.respond(to: approval, accept: true)
                let approvalHandled = await waitForCondition(timeout: config.timeout) {
                    model.pendingApprovals.isEmpty
                }
                guard approvalHandled else {
                    throw SmokeError.failed("Timed out waiting for approval resolution.")
                }

                currentStage = "steering"
                try writeResult(.running(stage: "steering", message: nil))
                await model.steerComposerText(config.steerText)

                currentStage = "waiting-for-steer-text"
                try writeResult(.running(stage: "waiting-for-steer-text", message: nil))
                let steerTextFound = await waitForExpectedText(config.expectedText, model: model, timeout: config.timeout)
                guard steerTextFound else {
                    throw SmokeError.failed("Timed out waiting for steered assistant text.")
                }

                currentStage = "interrupting"
                try writeResult(.running(stage: "interrupting", message: nil))
                await model.interruptActiveTurn()
                let interruptHandled = await waitForCondition(timeout: config.timeout) {
                    !model.canInterruptActiveTurn
                }
                guard interruptHandled else {
                    throw SmokeError.failed("Timed out waiting for interrupt completion.")
                }

                try writeResult(.success(
                    message: "In-app SSH control smoke succeeded.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: steerTextFound,
                    approvalHandled: approvalHandled,
                    interruptHandled: interruptHandled
                ))
                return
            }

            if config.mode == "approval" {
                currentStage = "starting-approval-turn"
                try writeResult(.running(stage: "starting-approval-turn", message: nil))
                await model.sendComposerText(config.prompt ?? "Start approval smoke")

                currentStage = "waiting-for-approval-ui"
                try writeResult(.running(stage: "waiting-for-approval-ui", message: nil))
                guard await waitForApproval(model: model, timeout: config.timeout) != nil else {
                    throw SmokeError.failed("Timed out waiting for approval request.")
                }
                let threadLoaded = await waitForCondition(timeout: config.timeout) {
                    model.selectedThread != nil
                }
                guard threadLoaded else {
                    throw SmokeError.failed("Timed out waiting for selected thread UI state.")
                }

                try writeResult(.success(
                    message: "In-app SSH approval UI smoke reached pending approval state.",
                    mode: config.mode,
                    authMethod: config.authMethod.rawValue,
                    sessionCount: model.threads.count,
                    conversationSectionCount: model.conversationSections.count,
                    assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                    expectedTextFound: false,
                    pendingApprovalCount: model.pendingApprovals.count,
                    canInterruptActiveTurn: model.canInterruptActiveTurn,
                    selectedThreadLoaded: model.selectedThread != nil
                ))
                return
            }

            var expectedTextFound = false
            if let prompt = config.prompt {
                currentStage = "sending-turn"
                try writeResult(.running(stage: "sending-turn", message: nil))
                await model.sendComposerText(prompt)
                currentStage = "waiting-for-text"
                try writeResult(.running(stage: "waiting-for-text", message: nil))
                expectedTextFound = await waitForExpectedText(config.expectedText, model: model, timeout: config.timeout)
                guard expectedTextFound else {
                    throw SmokeError.failed("Timed out waiting for expected assistant text.")
                }
            }

            try writeResult(.success(
                message: "In-app SSH smoke succeeded.",
                mode: config.mode,
                authMethod: config.authMethod.rawValue,
                sessionCount: model.threads.count,
                conversationSectionCount: model.conversationSections.count,
                assistantSectionCount: model.conversationSections.filter { $0.kind == .assistant }.count,
                expectedTextFound: expectedTextFound
            ))
        } catch {
            try? writeResult(.failure(stage: currentStage, message: error.localizedDescription))
        }
    }

    @MainActor
    private static func waitForExpectedText(_ expectedText: String?, model: AppViewModel, timeout: TimeInterval) async -> Bool {
        guard let expectedText, !expectedText.isEmpty else {
            return true
        }
        return await waitForCondition(timeout: timeout) {
            model.conversationSections.contains(where: { section in
                section.kind == .assistant && section.body.contains(expectedText)
            })
        }
    }

    @MainActor
    private static func waitForApproval(model: AppViewModel, timeout: TimeInterval) async -> PendingApproval? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let approval = model.pendingApprovals.first {
                return approval
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }

    @MainActor
    private static func waitForCondition(timeout: TimeInterval, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private static func writeResult(_ result: SmokeResult) throws {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = documents.appendingPathComponent(resultFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: url, options: .atomic)
    }
}

private struct SmokeConfig {
    var serverID: UUID
    var displayName: String
    var host: String
    var port: Int
    var username: String
    var codexPath: String
    var executionPath: String
    var authMethod: ServerAuthMethod
    var mode: String
    var cwd: String
    var password: String?
    var privateKey: String?
    var privateKeyPassphrase: String?
    var prompt: String?
    var steerText: String
    var expectedText: String?
    var newSessionLocation: NewSessionLocation
    var seedProject: ProjectRecord
    var browsePath: String
    var timeout: TimeInterval

    init(environment: [String: String]) throws {
        guard let host = environment["MOBIDEX_SMOKE_HOST"]?.nonEmpty else {
            throw SmokeError.failed("Missing MOBIDEX_SMOKE_HOST.")
        }
        guard let username = environment["MOBIDEX_SMOKE_USER"]?.nonEmpty else {
            throw SmokeError.failed("Missing MOBIDEX_SMOKE_USER.")
        }
        guard let cwd = environment["MOBIDEX_SMOKE_CWD"]?.nonEmpty else {
            throw SmokeError.failed("Missing MOBIDEX_SMOKE_CWD.")
        }

        let parsedAuthMethod: ServerAuthMethod
        let parsedPassword: String?
        let parsedPrivateKey: String?
        let parsedPrivateKeyPassphrase: String?
        switch environment["MOBIDEX_SMOKE_AUTH"]?.nonEmpty ?? "private-key" {
        case "password":
            guard let password = environment["MOBIDEX_SMOKE_PASSWORD"]?.nonEmpty else {
                throw SmokeError.failed("Missing MOBIDEX_SMOKE_PASSWORD.")
            }
            parsedAuthMethod = .password
            parsedPassword = password
            parsedPrivateKey = nil
            parsedPrivateKeyPassphrase = nil
        case "private-key", "privateKey":
            guard let privateKeyBase64 = environment["MOBIDEX_SMOKE_PRIVATE_KEY_BASE64"]?.nonEmpty,
                  let privateKeyData = Data(base64Encoded: privateKeyBase64),
                  let privateKey = String(data: privateKeyData, encoding: .utf8),
                  !privateKey.isEmpty
            else {
                throw SmokeError.failed("Missing or invalid MOBIDEX_SMOKE_PRIVATE_KEY_BASE64.")
            }
            parsedAuthMethod = .privateKey
            parsedPassword = nil
            parsedPrivateKey = privateKey
            parsedPrivateKeyPassphrase = environment["MOBIDEX_SMOKE_PRIVATE_KEY_PASSPHRASE"]?.nonEmpty
        default:
            throw SmokeError.failed("Unsupported MOBIDEX_SMOKE_AUTH. Use password or private-key.")
        }

        let parsedMode = environment["MOBIDEX_SMOKE_MODE"]?.nonEmpty ?? (parsedAuthMethod == .password ? "connection" : "turn")
        guard parsedMode == "turn" || parsedMode == "connection" || parsedMode == "control" || parsedMode == "approval" || parsedMode == "seed" || parsedMode == "new-session" || parsedMode == "join" || parsedMode == "browse-directories" || parsedMode == "add-discovered-project" || parsedMode == "terminal" else {
            throw SmokeError.failed("Unsupported MOBIDEX_SMOKE_MODE. Use turn, connection, control, approval, seed, terminal, new-session, join, browse-directories, or add-discovered-project.")
        }
        let parsedNewSessionLocation: NewSessionLocation
        switch environment["MOBIDEX_SMOKE_NEW_SESSION_LOCATION"]?.nonEmpty ?? "project-directory" {
        case "project-directory", "projectDirectory":
            parsedNewSessionLocation = .projectDirectory
        case "worktree", "codex-worktree", "codexWorktree":
            parsedNewSessionLocation = .codexWorktree
        default:
            throw SmokeError.failed("Unsupported MOBIDEX_SMOKE_NEW_SESSION_LOCATION. Use project-directory or worktree.")
        }
        self.serverID = environment["MOBIDEX_SMOKE_SERVER_ID"].flatMap(UUID.init(uuidString:)) ?? MobidexLaunchSmoke.defaultServerID
        self.displayName = environment["MOBIDEX_SMOKE_DISPLAY_NAME"]?.nonEmpty ?? "Smoke SSH"
        self.host = host
        self.port = environment["MOBIDEX_SMOKE_PORT"].flatMap(Int.init) ?? 22
        self.username = username
        let launchConfig = SharedKMPBridge.normalizedRemoteLaunchConfig(
            codexPath: environment["MOBIDEX_SMOKE_CODEX_PATH"],
            executionPath: environment["MOBIDEX_SMOKE_EXECUTION_PATH"]
        )
        self.codexPath = launchConfig.codexPath
        self.executionPath = launchConfig.executionPath
        self.authMethod = parsedAuthMethod
        self.mode = parsedMode
        self.cwd = cwd
        self.password = parsedPassword
        self.privateKey = parsedPrivateKey
        self.privateKeyPassphrase = parsedPrivateKeyPassphrase
        self.prompt = environment["MOBIDEX_SMOKE_PROMPT"]?.nonEmpty
        self.steerText = environment["MOBIDEX_SMOKE_STEER_TEXT"]?.nonEmpty ?? "Steer control smoke"
        self.expectedText = environment["MOBIDEX_SMOKE_EXPECTED_TEXT"]?.nonEmpty
        self.newSessionLocation = parsedNewSessionLocation
        self.browsePath = environment["MOBIDEX_SMOKE_BROWSE_PATH"]?.nonEmpty ?? "~"
        switch environment["MOBIDEX_SMOKE_SEED_PROJECT_STATE"]?.nonEmpty ?? "added" {
        case "added":
            self.seedProject = ProjectRecord(path: cwd, isAdded: true)
        case "discovered":
            self.seedProject = ProjectRecord(path: cwd, discovered: true, discoveredSessionCount: 1, isAdded: false)
        default:
            throw SmokeError.failed("Unsupported MOBIDEX_SMOKE_SEED_PROJECT_STATE. Use added or discovered.")
        }
        self.timeout = environment["MOBIDEX_SMOKE_TIMEOUT"].flatMap(TimeInterval.init) ?? 120
    }
}

private struct SmokeResult: Encodable {
    var status: String
    var stage: String?
    var message: String
    var mode: String?
    var authMethod: String?
    var sessionCount: Int?
    var conversationSectionCount: Int?
    var assistantSectionCount: Int?
    var expectedTextFound: Bool?
    var approvalHandled: Bool?
    var interruptHandled: Bool?
    var pendingApprovalCount: Int?
    var canInterruptActiveTurn: Bool?
    var selectedThreadLoaded: Bool?
    var timestamp: Date

    static func running(stage: String, message: String?) -> SmokeResult {
        SmokeResult(
            status: "running",
            stage: stage,
            message: message ?? stage,
            mode: nil,
            authMethod: nil,
            sessionCount: nil,
            conversationSectionCount: nil,
            assistantSectionCount: nil,
            expectedTextFound: nil,
            approvalHandled: nil,
            interruptHandled: nil,
            pendingApprovalCount: nil,
            canInterruptActiveTurn: nil,
            selectedThreadLoaded: nil,
            timestamp: .now
        )
    }

    static func success(
        message: String,
        mode: String,
        authMethod: String,
        sessionCount: Int,
        conversationSectionCount: Int,
        assistantSectionCount: Int,
        expectedTextFound: Bool,
        approvalHandled: Bool? = nil,
        interruptHandled: Bool? = nil,
        pendingApprovalCount: Int? = nil,
        canInterruptActiveTurn: Bool? = nil,
        selectedThreadLoaded: Bool? = nil
    ) -> SmokeResult {
        SmokeResult(
            status: "success",
            stage: nil,
            message: message,
            mode: mode,
            authMethod: authMethod,
            sessionCount: sessionCount,
            conversationSectionCount: conversationSectionCount,
            assistantSectionCount: assistantSectionCount,
            expectedTextFound: expectedTextFound,
            approvalHandled: approvalHandled,
            interruptHandled: interruptHandled,
            pendingApprovalCount: pendingApprovalCount,
            canInterruptActiveTurn: canInterruptActiveTurn,
            selectedThreadLoaded: selectedThreadLoaded,
            timestamp: .now
        )
    }

    static func failure(stage: String, message: String) -> SmokeResult {
        SmokeResult(
            status: "failure",
            stage: stage,
            message: message,
            mode: nil,
            authMethod: nil,
            sessionCount: nil,
            conversationSectionCount: nil,
            assistantSectionCount: nil,
            expectedTextFound: nil,
            approvalHandled: nil,
            interruptHandled: nil,
            pendingApprovalCount: nil,
            canInterruptActiveTurn: nil,
            selectedThreadLoaded: nil,
            timestamp: .now
        )
    }
}

private actor TerminalSmokeCapture {
    private(set) var errorMessage: String?
    private var output = ""

    func append(_ data: Data) {
        output.append(String(decoding: data, as: UTF8.self))
        if output.count > 8_000 {
            output = String(output.suffix(8_000))
        }
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func contains(_ text: String) -> Bool {
        output.contains(text)
    }

    func preview() -> String {
        output
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .suffix(1_000)
            .description
    }
}

private enum SmokeError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    func shellQuotedForSmokeCommand() -> String {
        "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
