import XCTest
import NIOCore
@testable import Mobidex

final class AppViewModelTests: XCTestCase {
    @MainActor
    func testSaveServerRejectsMissingHostBeforePersistence() async throws {
        let repository = InMemoryServerRepository()
        let credentials = SpyCredentialStore()
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())
        let server = ServerRecord(displayName: "", host: "  ", username: "mazdak", authMethod: .password)

        let saved = await viewModel.saveServer(server, credential: SSHCredential(password: "secret"))

        XCTAssertFalse(saved)
        XCTAssertTrue(viewModel.servers.isEmpty)
        XCTAssertTrue(try repository.loadServers().isEmpty)
        XCTAssertTrue(credentials.savedServerIDs.isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "Enter the SSH host for this server.")
    }

    @MainActor
    func testSaveServerRejectsMissingCredentialBeforePersistence() async throws {
        let repository = InMemoryServerRepository()
        let credentials = SpyCredentialStore()
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())
        let server = ServerRecord(displayName: "", host: "build.example.com", username: "mazdak", authMethod: .password)

        let saved = await viewModel.saveServer(server, credential: SSHCredential(password: ""))

        XCTAssertFalse(saved)
        XCTAssertTrue(viewModel.servers.isEmpty)
        XCTAssertTrue(try repository.loadServers().isEmpty)
        XCTAssertTrue(credentials.savedServerIDs.isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "Enter the SSH password for this server.")
    }

    @MainActor
    func testSaveServerNormalizesRequiredFields() async throws {
        let repository = InMemoryServerRepository()
        let credentials = SpyCredentialStore()
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())
        let server = ServerRecord(displayName: "  ", host: " build.example.com ", username: " mazdak ", codexPath: "  ", authMethod: .password)

        let saved = await viewModel.saveServer(server, credential: SSHCredential(password: "secret"))

        XCTAssertTrue(saved)
        let savedServer = try XCTUnwrap(viewModel.servers.first)
        XCTAssertEqual(savedServer.displayName, "build.example.com")
        XCTAssertEqual(savedServer.host, "build.example.com")
        XCTAssertEqual(savedServer.username, "mazdak")
        XCTAssertEqual(savedServer.codexPath, "codex")
        XCTAssertEqual(try credentials.loadCredential(serverID: savedServer.id).password, "secret")
    }

    @MainActor
    func testLoadServersClearsPersistedOpenSessionCounts() async throws {
        let project = ProjectRecord(
            path: "/srv/app",
            discovered: true,
            discoveredSessionCount: 513,
            activeChatCount: 513,
            lastActiveChatAt: Date(timeIntervalSince1970: 1_770_000_500)
        )
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let viewModel = AppViewModel(repository: repository, credentialStore: InMemoryCredentialStore(), sshService: StubSSHService())

        let loadedProject = try XCTUnwrap(viewModel.servers.first?.projects.first)
        XCTAssertEqual(loadedProject.discoveredSessionCount, 513)
        XCTAssertEqual(loadedProject.activeChatCount, 0)
        XCTAssertNil(loadedProject.lastActiveChatAt)
        let persistedProject = try XCTUnwrap(repository.loadServers().first?.projects.first)
        XCTAssertEqual(persistedProject.activeChatCount, 0)
        XCTAssertNil(persistedProject.lastActiveChatAt)
    }

    @MainActor
    func testDeferredServerLoadDoesNotPopulateModelUntilRequested() async throws {
        let project = ProjectRecord(
            path: "/srv/app",
            discovered: true,
            activeChatCount: 7,
            lastActiveChatAt: Date(timeIntervalSince1970: 1_770_000_500)
        )
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: InMemoryCredentialStore(),
            sshService: StubSSHService(),
            loadServersOnInit: false
        )

        XCTAssertTrue(viewModel.servers.isEmpty)
        await viewModel.loadServersIfNeeded()

        let loadedProject = try XCTUnwrap(viewModel.servers.first?.projects.first)
        XCTAssertEqual(loadedProject.path, "/srv/app")
        XCTAssertEqual(loadedProject.activeChatCount, 0)
        XCTAssertNil(loadedProject.lastActiveChatAt)
        XCTAssertEqual(viewModel.selectedServerID, server.id)
    }

    @MainActor
    func testAddProjectPersistsSelectsAndReportsSuccess() throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let viewModel = AppViewModel(repository: repository, credentialStore: InMemoryCredentialStore(), sshService: StubSSHService())

        XCTAssertTrue(viewModel.addProject(path: " /srv/app "))

        let project = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(project.path, "/srv/app")
        XCTAssertEqual(viewModel.selectedProjectID, project.id)
        XCTAssertEqual(try repository.loadServers().first?.projects.first?.path, "/srv/app")
        XCTAssertEqual(viewModel.statusMessage, "Added app.")
    }

    @MainActor
    func testAddProjectRejectsMissingSelectionWithStatus() {
        let viewModel = AppViewModel(
            repository: InMemoryServerRepository(),
            credentialStore: InMemoryCredentialStore(),
            sshService: StubSSHService(),
            loadServersOnInit: false
        )

        XCTAssertFalse(viewModel.addProject(path: "/srv/app"))

        XCTAssertEqual(viewModel.statusMessage, "Select a server before adding a project.")
    }

    @MainActor
    func testAddProjectRejectsDuplicateWithStatus() {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let viewModel = AppViewModel(
            repository: InMemoryServerRepository(servers: [server]),
            credentialStore: InMemoryCredentialStore(),
            sshService: StubSSHService()
        )

        XCTAssertFalse(viewModel.addProject(path: "/srv/app"))

        XCTAssertEqual(viewModel.statusMessage, "That project is already saved.")
    }

    @MainActor
    func testUnexpectedAppServerDisconnectWithoutReconnectClearsOpenSessionCounts() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            maxAppServerReconnectAttempts: 0
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)
        let countedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(countedProject.activeChatCount, 1)
        XCTAssertEqual(countedProject.lastActiveChatAt, Date(timeIntervalSince1970: 1_770_000_500))
        let persistedCountedProject = try XCTUnwrap(repository.loadServers().first?.projects.first)
        XCTAssertEqual(persistedCountedProject.activeChatCount, 1)

        transport.finishInbound()

        try await waitForConnectionState(.disconnected, in: viewModel)
        XCTAssertEqual(viewModel.statusMessage, "The app-server stream ended.")
        let disconnectedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(disconnectedProject.activeChatCount, 0)
        XCTAssertNil(disconnectedProject.lastActiveChatAt)
        let persistedDisconnectedProject = try XCTUnwrap(repository.loadServers().first?.projects.first)
        XCTAssertEqual(persistedDisconnectedProject.activeChatCount, 0)
        XCTAssertNil(persistedDisconnectedProject.lastActiveChatAt)
    }

    @MainActor
    func testUnexpectedAppServerDisconnectReconnectsAndPreservesOpenSessionCounts() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let firstTransport = MockCodexLineTransport()
        let secondTransport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServers: [
            CodexAppServerClient(transport: firstTransport),
            CodexAppServerClient(transport: secondTransport)
        ])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService,
            appServerReconnectDelayNanoseconds: 0
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: firstTransport)
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.activeChatCount, 1)

        firstTransport.finishInbound(throwing: ChannelError.inputClosed)

        try await connectWithSingleOpenSessionAfterReconnect(in: viewModel, transport: secondTransport)
        try await waitForConnectionState(.connected, in: viewModel)
        try await waitForStatusMessage("App-server connected.", in: viewModel)
        XCTAssertNil(viewModel.appServerReconnectStatus)
        XCTAssertEqual(sshService.openAppServerCallCount, 2)
        let reconnectedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(reconnectedProject.activeChatCount, 1)
        XCTAssertEqual(reconnectedProject.lastActiveChatAt, Date(timeIntervalSince1970: 1_770_000_500))
    }

    @MainActor
    func testUnexpectedAppServerDisconnectRetriesReconnectOpenFailure() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let firstTransport = MockCodexLineTransport()
        let secondTransport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServerOpenResults: [
            .success(CodexAppServerClient(transport: firstTransport)),
            .failure(TestError.unexpectedSSH),
            .success(CodexAppServerClient(transport: secondTransport))
        ])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService,
            appServerReconnectDelayNanoseconds: 0,
            maxAppServerReconnectAttempts: 2
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: firstTransport)
        firstTransport.finishInbound(throwing: ChannelError.inputClosed)

        try await connectWithSingleOpenSessionAfterReconnect(in: viewModel, transport: secondTransport)
        try await waitForStatusMessage("App-server connected.", in: viewModel)
        XCTAssertEqual(sshService.openAppServerCallCount, 3)
        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.activeChatCount, 1)
    }

    @MainActor
    func testAppServerReconnectDelayUsesCappedExponentialBackoff() {
        XCTAssertEqual(
            AppViewModel.appServerReconnectDelayNanoseconds(baseDelayNanoseconds: 100_000_000, attempt: 1),
            100_000_000
        )
        XCTAssertEqual(
            AppViewModel.appServerReconnectDelayNanoseconds(baseDelayNanoseconds: 100_000_000, attempt: 2),
            200_000_000
        )
        XCTAssertEqual(
            AppViewModel.appServerReconnectDelayNanoseconds(baseDelayNanoseconds: 100_000_000, attempt: 4),
            800_000_000
        )
        XCTAssertEqual(
            AppViewModel.appServerReconnectDelayNanoseconds(baseDelayNanoseconds: 0, attempt: 1),
            10_000_000
        )
        XCTAssertEqual(
            AppViewModel.appServerReconnectDelayNanoseconds(baseDelayNanoseconds: 3_000_000_000, attempt: 5),
            8_000_000_000
        )
        XCTAssertEqual(
            AppServerReconnectStatus(attempt: 2, maxAttempts: 3, delayNanoseconds: 200_000_000).label,
            "Reconnect 2/3 in 200ms"
        )
        XCTAssertEqual(
            AppServerReconnectStatus(attempt: 3, maxAttempts: 3, delayNanoseconds: 2_000_000_000).label,
            "Reconnect 3/3 in 2s"
        )
        XCTAssertEqual(
            AppServerReconnectStatus(attempt: 3, maxAttempts: 3, delayNanoseconds: 0).label,
            "Reconnecting 3/3"
        )
    }

    @MainActor
    func testUnexpectedAppServerDisconnectClearsOpenSessionCountsAfterReconnectFailure() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            appServerReconnectDelayNanoseconds: 0,
            maxAppServerReconnectAttempts: 1
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.activeChatCount, 1)

        transport.finishInbound(throwing: ChannelError.inputClosed)

        try await waitForStatusMessage(
            "The app-server SSH channel closed. Reconnect failed: The app-server connection closed.",
            in: viewModel
        )
        XCTAssertNil(viewModel.appServerReconnectStatus)
        let failedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(failedProject.activeChatCount, 0)
        XCTAssertNil(failedProject.lastActiveChatAt)
    }

    @MainActor
    func testManualDisconnectCancelsScheduledAppServerReconnect() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let firstTransport = MockCodexLineTransport()
        let secondTransport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServers: [
            CodexAppServerClient(transport: firstTransport),
            CodexAppServerClient(transport: secondTransport)
        ])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService,
            appServerReconnectDelayNanoseconds: 500_000_000
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: firstTransport)
        firstTransport.finishInbound(throwing: ChannelError.inputClosed)
        try await waitForConnectionState(.connecting, in: viewModel)
        try await waitForReconnectStatus(
            AppServerReconnectStatus(attempt: 1, maxAttempts: 3, delayNanoseconds: 500_000_000),
            in: viewModel
        )

        await viewModel.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertEqual(sshService.openAppServerCallCount, 1)
        XCTAssertFalse(secondTransport.sentLinesSnapshot.compactMap(methodName).contains("initialize"))
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.activeChatCount, 0)
        XCTAssertNil(viewModel.appServerReconnectStatus)
    }

    @MainActor
    func testAppServerDisconnectDuringConnectSyncReconnectsAfterSyncUnwinds() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let firstTransport = MockCodexLineTransport()
        let secondTransport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(
            appServers: [
                CodexAppServerClient(transport: firstTransport),
                CodexAppServerClient(transport: secondTransport)
            ],
            discoveredProjectBatches: [[RemoteProject(path: "/srv/app", discoveredSessionCount: 1, lastDiscoveredAt: nil)]]
        )
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService,
            appServerReconnectDelayNanoseconds: 0
        )

        let connectTask = Task { await viewModel.connectSelectedServer(syncActiveChatCounts: true) }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: firstTransport, after: cursor)
        cursor = initialize.nextCursor
        firstTransport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        _ = try await waitForRequest(method: "thread/loaded/list", in: firstTransport, after: cursor)

        firstTransport.finishInbound(throwing: ChannelError.inputClosed)
        await connectTask.value

        try await connectWithSingleOpenSessionAfterReconnect(in: viewModel, transport: secondTransport)
        try await waitForStatusMessage("App-server connected.", in: viewModel)
        XCTAssertEqual(sshService.openAppServerCallCount, 2)
        XCTAssertEqual(viewModel.connectionState, .connected)
    }

    @MainActor
    func testAppServerChannelErrorShowsReadableDisconnectMessage() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            maxAppServerReconnectAttempts: 0
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)

        transport.finishInbound(throwing: ChannelError.inputClosed)

        try await waitForConnectionState(.disconnected, in: viewModel)
        XCTAssertEqual(viewModel.statusMessage, "The app-server SSH channel closed.")
    }

    @MainActor
    func testManualDisconnectClearsOpenSessionCounts() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)
        let countedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(countedProject.activeChatCount, 1)

        await viewModel.disconnect()

        XCTAssertEqual(viewModel.connectionState, .disconnected)
        let disconnectedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(disconnectedProject.activeChatCount, 0)
        XCTAssertNil(disconnectedProject.lastActiveChatAt)
        let persistedDisconnectedProject = try XCTUnwrap(repository.loadServers().first?.projects.first)
        XCTAssertEqual(persistedDisconnectedProject.activeChatCount, 0)
        XCTAssertNil(persistedDisconnectedProject.lastActiveChatAt)
    }

    @MainActor
    func testUnscopedSessionListUsesThreadListHistory() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        let params = try requestParams(for: list, in: transport)
        XCTAssertNil(params["cwd"])
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-open","preview":"Open work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000500,"createdAt":1770000000,"source":"appServer","turns":[]},
          {"id":"thread-old","preview":"Old work","cwd":"/srv/old","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"source":"cli","turns":[]},
          {"id":"thread-subagent","preview":"Review worker","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000600,"createdAt":1770000000,"source":{"subagent":"review"},"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = read.nextCursor
        let readParams = try requestParams(for: read, in: transport)
        XCTAssertEqual(readParams["threadId"] as? String, "thread-open")
        XCTAssertEqual(readParams["includeTurns"] as? Bool, true)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-open",
          "preview":"Open work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000500,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        XCTAssertEqual(viewModel.threads.map(\.id), ["thread-open", "thread-old"])
        XCTAssertEqual(viewModel.selectedThreadID, "thread-open")
        XCTAssertFalse(transport.sentLinesSnapshot.compactMap(methodName).contains("thread/loaded/list"))

        cursor = transport.sentLinesSnapshot.count
        let newSessionTask = Task { await viewModel.startNewSession() }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        let startParams = try requestParams(for: startThread, in: transport)
        XCTAssertEqual(startParams["cwd"] as? String, "/srv/app")
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"New work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000700,
          "createdAt":1770000700,
          "turns":[]
        }}}
        """)
        await newSessionTask.value

        XCTAssertEqual(viewModel.selectedThreadID, "thread-new")
        await viewModel.disconnect()
    }

    @MainActor
    func testSessionSectionsGroupByProjectAndSortByTime() async throws {
        let projects = [
            ProjectRecord(path: "/srv/app", sessionPaths: ["/srv/app", "/srv/.codex/worktrees/a/app"]),
            ProjectRecord(path: "/srv/tools"),
        ]
        let threads = [
            CodexThread(
                id: "tools-old",
                preview: "Tools old",
                cwd: "/srv/tools",
                status: .idle,
                updatedAt: Date(timeIntervalSince1970: 10),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            CodexThread(
                id: "app-worktree-new",
                preview: "App worktree",
                cwd: "/srv/.codex/worktrees/a/app",
                status: .idle,
                updatedAt: Date(timeIntervalSince1970: 40),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            CodexThread(
                id: "unknown",
                preview: "Loose",
                cwd: "/tmp/loose",
                status: .idle,
                updatedAt: Date(timeIntervalSince1970: 30),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            CodexThread(
                id: "app-main-old",
                preview: "App main",
                cwd: "/srv/app",
                status: .idle,
                updatedAt: Date(timeIntervalSince1970: 20),
                createdAt: Date(timeIntervalSince1970: 1)
            ),
        ]
        let sections = SessionListSections.sections(threads: threads, projects: projects)

        XCTAssertEqual(sections.map(\.title), ["app", "/tmp/loose", "tools"])
        XCTAssertEqual(sections.first?.threads.map(\.id), ["app-worktree-new", "app-main-old"])
    }

    @MainActor
    func testSelectingProjectLoadsSessionsWithoutOpeningOne() async throws {
        let appProject = ProjectRecord(path: "/srv/app")
        let toolsProject = ProjectRecord(path: "/srv/tools")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [appProject, toolsProject]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        var params = try requestParams(for: initialList, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        transport.receive("""
        {"id":\(initialList.id),"result":{"data":[
          {"id":"thread-app","preview":"App work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let initialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = initialRead.nextCursor
        transport.receive("""
        {"id":\(initialRead.id),"result":{"thread":{
          "id":"thread-app",
          "preview":"App work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value
        XCTAssertEqual(viewModel.selectedThreadID, "thread-app")

        viewModel.selectProject(toolsProject.id)
        XCTAssertNil(viewModel.selectedThreadID)
        cursor = transport.sentLinesSnapshot.count
        let refreshTask = Task { await viewModel.refreshThreads() }
        let toolsList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        params = try requestParams(for: toolsList, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/tools")
        transport.receive("""
        {"id":\(toolsList.id),"result":{"data":[
          {"id":"thread-tools","preview":"Tools work","cwd":"/srv/tools","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await refreshTask.value

        XCTAssertEqual(viewModel.threads.map(\.id), ["thread-tools"])
        XCTAssertNil(viewModel.selectedThreadID)
        XCTAssertNil(viewModel.selectedThread)
        XCTAssertTrue(viewModel.conversationSections.isEmpty)
        await viewModel.disconnect()
    }

    @MainActor
    func testAppServerDisconnectDuringConnectSyncKeepsDisconnectReason() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [[RemoteProject(path: "/srv/app", discoveredSessionCount: 1, lastDiscoveredAt: nil)]]
            ),
            maxAppServerReconnectAttempts: 0
        )

        let connectTask = Task { await viewModel.connectSelectedServer(syncActiveChatCounts: true) }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        _ = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)

        transport.finishInbound(throwing: ChannelError.inputClosed)
        await connectTask.value

        XCTAssertEqual(viewModel.connectionState, ServerConnectionState.disconnected)
        XCTAssertEqual(viewModel.statusMessage, "The app-server SSH channel closed.")
    }

    @MainActor
    func testSavingSelectedServerWithFailedLiveAppServerClearsOpenSessionCountsAndDisconnects() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 37)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                testConnectionError: TestError.discovery
            )
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)
        XCTAssertTrue(viewModel.isAppServerConnected)
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.activeChatCount, 1)

        await viewModel.testSelectedConnection()
        XCTAssertTrue(viewModel.isAppServerConnected)

        var editedServer = server
        editedServer.displayName = "Renamed Box"
        let saved = await viewModel.saveServer(editedServer, credential: SSHCredential(password: "secret"))

        XCTAssertTrue(saved)
        XCTAssertFalse(viewModel.isAppServerConnected)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        let savedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(viewModel.selectedServer?.displayName, "Renamed Box")
        XCTAssertEqual(savedProject.activeChatCount, 0)
        XCTAssertNil(savedProject.lastActiveChatAt)
        let persistedServer = try XCTUnwrap(repository.loadServers().first)
        XCTAssertEqual(persistedServer.displayName, "Renamed Box")
        XCTAssertEqual(persistedServer.projects.first?.activeChatCount, 0)
        XCTAssertNil(persistedServer.projects.first?.lastActiveChatAt)
    }

    @MainActor
    func testSaveNewServerCanStartAppServerConnectionAfterSave() async throws {
        let repository = InMemoryServerRepository()
        let credentials = InMemoryCredentialStore()
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)

        let saved = await viewModel.saveServer(
            server,
            credential: SSHCredential(password: "secret"),
            connectAfterSave: true
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.selectedServerID, server.id)
        let ensureTask = Task { @MainActor in
            await viewModel.ensureSelectedServerConnected()
        }
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: 0)
        var cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        cursor = loadedList.nextCursor
        transport.receive(#"{"id":\#(loadedList.id),"result":{"data":[]}}"#)
        let emptyScopeList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive(#"{"id":\#(emptyScopeList.id),"result":{"data":[],"nextCursor":null}}"#)

        try await waitForConnectionState(.connected, in: viewModel)
        await ensureTask.value
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(sshService.openAppServerCallCount, 1)
        await viewModel.disconnect()
    }

    @MainActor
    func testSelectingAnotherServerClearsStaleConnectionFailure() async throws {
        let first = ServerRecord(displayName: "Bad Box", host: "bad.example.com", username: "mazdak", authMethod: .password)
        let second = ServerRecord(displayName: "Good Box", host: "good.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [first, second])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: first.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(openAppServerError: SSHServiceError.authenticationFailed)
        )

        await viewModel.connectSelectedServer()
        XCTAssertEqual(
            viewModel.connectionState,
            .failed("SSH authentication failed. Check the username and saved password or private key.")
        )

        XCTAssertTrue(viewModel.selectServer(second.id))

        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertNil(viewModel.statusMessage)
    }

    @MainActor
    func testSidebarServerSwitchDisconnectsActiveAppServerBeforeSelecting() async throws {
        let first = ServerRecord(displayName: "First Box", host: "first.example.com", username: "mazdak", authMethod: .password)
        let second = ServerRecord(displayName: "Second Box", host: "second.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [first, second])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: first.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)
        XCTAssertEqual(viewModel.connectionState, .connected)

        let switched = await viewModel.switchServerFromSidebar(second.id)
        XCTAssertTrue(switched)

        XCTAssertEqual(viewModel.selectedServerID, second.id)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertNil(viewModel.selectedThreadID)
        XCTAssertTrue(viewModel.conversationSections.isEmpty)
    }

    @MainActor
    func testSidebarServerSwitchUsesLatestTapWhileConnectIsInFlight() async throws {
        let first = ServerRecord(displayName: "First Box", host: "first.example.com", username: "mazdak", authMethod: .password)
        let second = ServerRecord(displayName: "Second Box", host: "second.example.com", username: "mazdak", authMethod: .password)
        let third = ServerRecord(displayName: "Third Box", host: "third.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [first, second, third])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: first.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(
                openAppServerError: TestError.unexpectedSSH,
                openAppServerDelayNanoseconds: 120_000_000
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        try await waitForConnectionState(.connecting, in: viewModel)

        let firstSwitchSucceeded = await viewModel.switchServerFromSidebar(second.id)
        let secondSwitchSucceeded = await viewModel.switchServerFromSidebar(third.id)

        await connectTask.value

        XCTAssertTrue(firstSwitchSucceeded)
        XCTAssertTrue(secondSwitchSucceeded)
        XCTAssertEqual(viewModel.selectedServerID, third.id)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertNil(viewModel.switchingServerID)
    }

    @MainActor
    func testSidebarCurrentServerTapCancelsPendingSwitch() async throws {
        let first = ServerRecord(displayName: "First Box", host: "first.example.com", username: "mazdak", authMethod: .password)
        let second = ServerRecord(displayName: "Second Box", host: "second.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [first, second])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: first.id)
        let transport = MockCodexLineTransport(closeDelayNanoseconds: 120_000_000)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        try await connectWithSingleOpenSession(in: viewModel, transport: transport)
        XCTAssertEqual(viewModel.connectionState, .connected)

        let pendingSwitchTask = Task { await viewModel.switchServerFromSidebar(second.id) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let cancelled = await viewModel.switchServerFromSidebar(first.id)
        let pendingSwitchSucceeded = await pendingSwitchTask.value

        XCTAssertTrue(cancelled)
        XCTAssertFalse(pendingSwitchSucceeded)
        XCTAssertEqual(viewModel.selectedServerID, first.id)
        XCTAssertNil(viewModel.switchingServerID)
    }

    @MainActor
    func testAutoConnectCanRetryAfterFailureWhenServerIsReselected() async throws {
        let first = ServerRecord(displayName: "Bad Box", host: "bad.example.com", username: "mazdak", authMethod: .password)
        let second = ServerRecord(displayName: "Good Box", host: "good.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [first, second])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: first.id)
        let sshService = StubSSHService(openAppServerError: SSHServiceError.authenticationFailed)
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: sshService)

        await viewModel.ensureSelectedServerConnected()

        XCTAssertEqual(sshService.openAppServerCallCount, 1)
        XCTAssertEqual(
            viewModel.connectionState,
            .failed("SSH authentication failed. Check the username and saved password or private key.")
        )

        await viewModel.ensureSelectedServerConnected()
        XCTAssertEqual(sshService.openAppServerCallCount, 1)

        XCTAssertTrue(viewModel.selectServer(second.id))
        XCTAssertTrue(viewModel.selectServer(first.id))

        await viewModel.ensureSelectedServerConnected()

        XCTAssertEqual(sshService.openAppServerCallCount, 2)
        XCTAssertEqual(
            viewModel.connectionState,
            .failed("SSH authentication failed. Check the username and saved password or private key.")
        )
    }

    @MainActor
    func testSaveServerPreservesConcurrentProjectStateChanges() async throws {
        let project = ProjectRecord(path: "/work/buildbox")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = BlockingSaveCredentialStore()
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())
        let editedServer = ServerRecord(
            id: server.id,
            displayName: "Renamed Box",
            host: server.host,
            username: server.username,
            authMethod: server.authMethod,
            projects: server.projects,
            createdAt: server.createdAt,
            updatedAt: server.updatedAt
        )

        let saveTask = Task { @MainActor in
            await viewModel.saveServer(editedServer, credential: SSHCredential(password: "secret"))
        }
        try await waitForCredentialSaveStart(credentials)

        XCTAssertTrue(viewModel.setProjectFavorite(project, isFavorite: true))

        credentials.releaseSave()
        let saved = await saveTask.value

        XCTAssertTrue(saved)
        let savedServer = try XCTUnwrap(viewModel.servers.first)
        XCTAssertEqual(savedServer.displayName, "Renamed Box")
        XCTAssertEqual(savedServer.projects.first?.isFavorite, true)
        XCTAssertEqual(try repository.loadServers().first?.projects.first?.isFavorite, true)
    }

    @MainActor
    func testSaveSelectedServerInvalidatesInFlightConnection() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "old.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "old-secret"), serverID: server.id)
        let sshService = BlockingOpenSSHService()
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: sshService)

        let connectTask = Task { @MainActor in
            await viewModel.connectSelectedServer(syncActiveChatCounts: true)
        }
        try await waitForOpenAppServerStart(sshService)
        let editedServer = ServerRecord(
            id: server.id,
            displayName: "Updated Box",
            host: "new.example.com",
            username: server.username,
            authMethod: server.authMethod,
            projects: server.projects,
            createdAt: server.createdAt,
            updatedAt: server.updatedAt
        )

        let saved = await viewModel.saveServer(editedServer, credential: SSHCredential(password: "new-secret"))

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        sshService.releaseOpen()
        await connectTask.value

        XCTAssertFalse(viewModel.isAppServerConnected)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertEqual(viewModel.servers.first?.host, "new.example.com")
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id).password, "new-secret")
    }

    @MainActor
    func testSelectedServerSavePersistenceFailureKeepsExistingConnection() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = FailingSaveServerRepository(servers: [server], failOnSaveNumber: 2)
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "old-secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { @MainActor in
            await viewModel.connectSelectedServer(syncActiveChatCounts: true)
        }
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: 0)
        var cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        cursor = loadedList.nextCursor
        transport.receive(#"{"id":\#(loadedList.id),"result":{"data":[]}}"#)
        let emptyScopeList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive(#"{"id":\#(emptyScopeList.id),"result":{"data":[],"nextCursor":null}}"#)
        try await waitForConnectionState(.connected, in: viewModel)
        await connectTask.value
        let editedServer = ServerRecord(
            id: server.id,
            displayName: "Updated Box",
            host: "updated.example.com",
            username: server.username,
            authMethod: server.authMethod,
            projects: server.projects,
            createdAt: server.createdAt,
            updatedAt: server.updatedAt
        )

        let saved = await viewModel.saveServer(editedServer, credential: SSHCredential(password: "new-secret"))

        XCTAssertFalse(saved)
        XCTAssertTrue(viewModel.isAppServerConnected)
        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(viewModel.servers.first?.host, "build.example.com")
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id).password, "old-secret")
        await viewModel.disconnect()
    }

    @MainActor
    func testSaveServerRestoresPreviousCredentialWhenCredentialSaveFails() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let oldCredential = SSHCredential(password: "old-secret")
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = FailingFirstSaveCredentialStore(initialCredential: oldCredential)
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        let updatedServer = ServerRecord(
            id: server.id,
            displayName: "Updated Box",
            host: "updated.example.com",
            username: "mazdak",
            authMethod: .password,
            createdAt: server.createdAt,
            updatedAt: server.updatedAt
        )
        let saved = await viewModel.saveServer(
            updatedServer,
            credential: SSHCredential(password: "new-secret")
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id), oldCredential)
    }

    @MainActor
    func testStartNewSessionRequiresAppServerConnection() async throws {
        let project = ProjectRecord(path: "/Users/mazdak/Code/mobdex")
        let server = ServerRecord(
            displayName: "Mazdak",
            host: "192.168.1.239",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = SpyCredentialStore()
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        XCTAssertTrue(viewModel.selectServer(server.id))
        viewModel.selectProject(project.id)
        await viewModel.startNewSession()

        XCTAssertEqual(viewModel.statusMessage, "Connect to the app-server before starting a new session.")
    }

    @MainActor
    func testTestConnectionPublishesSuccessAlert() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = SpyCredentialStore(values: [server.id: SSHCredential(password: "secret")])
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        await viewModel.testSelectedConnection()

        XCTAssertEqual(viewModel.statusMessage, "Connection test passed for Build Box.")
        XCTAssertEqual(viewModel.statusAlert?.title, "Connection Test Passed")
        XCTAssertEqual(viewModel.statusAlert?.message, "Connection test passed for Build Box.")
    }

    @MainActor
    func testConnectionLoadsCredentialOffMainThread() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = ThreadCheckingCredentialStore(credential: SSHCredential(password: "secret"))
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        await viewModel.testSelectedConnection()

        XCTAssertEqual(viewModel.statusAlert?.title, "Connection Test Passed")
        XCTAssertFalse(credentials.loadRanOnMainThread)
    }

    @MainActor
    func testTestConnectionPublishesFailureAlert() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = SpyCredentialStore(values: [server.id: SSHCredential(password: "secret")])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(testConnectionError: SSHServiceError.authenticationFailed)
        )

        await viewModel.testSelectedConnection()

        XCTAssertEqual(viewModel.statusAlert?.title, "Connection Test Failed")
        XCTAssertEqual(viewModel.statusAlert?.message, "SSH authentication failed. Check the username and saved password or private key.")
        XCTAssertEqual(viewModel.connectionState, .failed("SSH authentication failed. Check the username and saved password or private key."))
    }

    @MainActor
    func testAppDeclaresLocalNetworkUsageForLANSSH() async throws {
        let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String

        XCTAssertEqual(usageDescription, "Mobidex connects to SSH servers on your local network.")
    }

    func testLocalNetworkPermissionErrorIsActionable() throws {
        let error = SSHServiceError.localNetworkPermissionDenied(
            "192.168.1.239",
            22,
            "192.168.1.239:22: operation not permitted"
        )

        XCTAssertEqual(
            error.localizedDescription,
            "iOS may be blocking local-network access to 192.168.1.239:22. Allow Local Network access for Mobidex in Settings, then try again. Underlying failure: 192.168.1.239:22: operation not permitted"
        )
    }

    func testRealNIOConnectionErrorMapsToReadableSSHFailure() async throws {
        let server = ServerRecord(displayName: "Closed Local Port", host: "127.0.0.1", port: 1, username: "mazdak", authMethod: .password)
        let service = CitadelSSHService()

        do {
            try await service.testConnection(server: server, credential: SSHCredential(password: "unused"))
            XCTFail("Expected a closed local SSH port to fail.")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.hasPrefix("Could not connect to 127.0.0.1:1:"), message)
            XCTAssertFalse(message.contains("NIOConnectionError"), message)
            XCTAssertFalse(message.contains("NIOPosix"), message)
        }
    }

    @MainActor
    func testConnectMapsClosedChannelToAppServerMessage() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = SpyCredentialStore(values: [server.id: SSHCredential(password: "secret")])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(
                openAppServerError: SSHServiceError.appServerClosed(
                    command: "codex app-server --listen stdio://",
                    details: nil
                )
            )
        )

        await viewModel.connectSelectedServer()

        XCTAssertEqual(
            viewModel.statusMessage,
            "SSH connected, but the server closed the app-server session while starting `codex app-server --listen stdio://`. Check the Codex path and that Codex app-server can run on the server."
        )
    }

    func testProjectRecordDecodesMissingFavoriteAndSessionPathsWithDefaults() throws {
        let data = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "path": "/srv/app",
          "displayName": "app",
          "discovered": true,
          "discoveredSessionCount": 2,
          "activeChatCount": 0,
          "lastDiscoveredAt": 1770000300
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let project = try decoder.decode(ProjectRecord.self, from: data)

        XCTAssertFalse(project.isFavorite)
        XCTAssertEqual(project.sessionPaths, ["/srv/app"])
    }

    func testThreadStatusSessionLabelsUseWorkingAndReadyLanguage() throws {
        XCTAssertEqual(CodexThreadStatus.idle.sessionLabel, "Ready")
        XCTAssertEqual(CodexThreadStatus.active(flags: []).sessionLabel, "Working")
        XCTAssertEqual(CodexThreadStatus.active(flags: ["waitingOnApproval"]).sessionLabel, "Working: waitingOnApproval")
    }

    func testThreadStatusIndicatorsSurfaceAttentionStates() throws {
        XCTAssertEqual(CodexThreadStatus.active(flags: []).indicator, .active)
        XCTAssertEqual(CodexThreadStatus.idle.indicator, .inactive)
        XCTAssertEqual(CodexThreadStatus.notLoaded.indicator, .inactive)
        XCTAssertEqual(CodexThreadStatus.systemError.indicator, .needsAttention)
        XCTAssertEqual(CodexThreadStatus.unknown("transportError").indicator, .needsAttention)
        XCTAssertEqual(CodexThreadStatus.unknown("idleButUnknown").indicator, .inactive)
    }

    @MainActor
    func testStartNewSessionCreatesAndSelectsThreadWhenConnected() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value
        XCTAssertEqual(viewModel.selectedThreadID, "thread-1")

        cursor = transport.sentLinesSnapshot.count
        let newSessionTask = Task { await viewModel.startNewSession() }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        let params = try requestParams(for: startThread, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"New thread",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000400,
          "createdAt":1770000400,
          "turns":[]
        }}}
        """)
        await newSessionTask.value

        XCTAssertEqual(viewModel.selectedThreadID, "thread-new")
        XCTAssertEqual(viewModel.selectedThread?.id, "thread-new")
        XCTAssertEqual(viewModel.threads.map(\.id), ["thread-new", "thread-1"])
        XCTAssertTrue(viewModel.conversationSections.isEmpty)
        XCTAssertTrue(viewModel.pendingApprovals.isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "New session created.")
        await viewModel.disconnect()
    }

    @MainActor
    func testOpenThreadShowsLoadingUntilReliableReadCompletes() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let initialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = initialRead.nextCursor
        transport.receive("""
        {"id":\(initialRead.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value
        XCTAssertFalse(viewModel.isSelectedThreadLoading)

        let thread = try XCTUnwrap(viewModel.threads.first)
        let openTask = Task { await viewModel.openThread(thread) }
        let read = try await waitForRequest(method: "thread/resume", in: transport, after: cursor)
        XCTAssertTrue(viewModel.isSelectedThreadLoading)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000301,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await openTask.value

        XCTAssertFalse(viewModel.isSelectedThreadLoading)
        XCTAssertEqual(viewModel.selectedThread?.updatedAt, Date(timeIntervalSince1970: 1_770_000_301))
        await viewModel.disconnect()
    }

    @MainActor
    func testOpenThreadFallsBackToReadWhenResumeFails() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let initialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = initialRead.nextCursor
        transport.receive("""
        {"id":\(initialRead.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        let thread = try XCTUnwrap(viewModel.threads.first)
        let openTask = Task { await viewModel.openThread(thread) }
        let resume = try await waitForRequest(method: "thread/resume", in: transport, after: cursor)
        cursor = resume.nextCursor
        transport.receive(#"{"id":\#(resume.id),"error":{"code":-32000,"message":"resume unavailable"}}"#)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000302,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await openTask.value

        XCTAssertEqual(viewModel.selectedThread?.updatedAt, Date(timeIntervalSince1970: 1_770_000_302))
        XCTAssertEqual(viewModel.statusMessage, "Opened session history; live resume failed: resume unavailable")
        await viewModel.disconnect()
    }

    @MainActor
    func testThreadStatusChangedNotificationUpdatesSelectedThread() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let initialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = initialRead.nextCursor
        transport.receive("""
        {"id":\(initialRead.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        transport.receive("""
        {"method":"thread/status/changed","params":{
          "threadId":"thread-1",
          "status":{"type":"active","activeFlags":["waitingOnApproval"]}
        }}
        """)
        try await waitForSelectedThreadStatus("Working: waitingOnApproval", in: viewModel)
        let notificationList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(notificationList.id),"result":{"data":[
          {"id":"thread-1","preview":"Existing work","cwd":"/srv/app","status":{"type":"active","activeFlags":["waitingOnApproval"]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        XCTAssertEqual(viewModel.threads.first?.status.sessionLabel, "Working: waitingOnApproval")
        await viewModel.disconnect()
    }

    @MainActor
    func testTokenUsageNotificationUpdatesSelectedContextUsage() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let initialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = initialRead.nextCursor
        transport.receive("""
        {"id":\(initialRead.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        transport.receive("""
        {"method":"thread/tokenUsage/updated","params":{
          "threadId":"thread-other",
          "turnId":"turn-other",
          "tokenUsage":{
            "total":{"totalTokens":16384,"inputTokens":15000,"cachedInputTokens":0,"outputTokens":1000,"reasoningOutputTokens":384},
            "last":{"totalTokens":512,"inputTokens":384,"cachedInputTokens":128,"outputTokens":96,"reasoningOutputTokens":32},
            "modelContextWindow":32768
          }
        }}
        """)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(viewModel.contextUsageFraction)

        transport.receive("""
        {"method":"thread/tokenUsage/updated","params":{
          "threadId":"thread-1",
          "turnId":"turn-1",
          "tokenUsage":{
            "total":{"totalTokens":8192,"inputTokens":7000,"cachedInputTokens":1000,"outputTokens":900,"reasoningOutputTokens":292},
            "last":{"totalTokens":512,"inputTokens":384,"cachedInputTokens":128,"outputTokens":96,"reasoningOutputTokens":32},
            "modelContextWindow":32768
          }
        }}
        """)

        try await waitForContextUsageFraction(0.25, in: viewModel)
        XCTAssertEqual(viewModel.contextUsagePercent, 25)

        let newSessionTask = Task { await viewModel.startNewSession() }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000400,
          "createdAt":1770000400,
          "turns":[]
        }}}
        """)
        await newSessionTask.value
        XCTAssertNil(viewModel.contextUsageFraction)
        await viewModel.disconnect()
    }

    @MainActor
    func testConnectLoadsProjectThreadsAcrossWorktreeSessionPaths() async throws {
        let project = ProjectRecord(
            path: "/srv/fullstack",
            sessionPaths: ["/srv/fullstack", "/srv/.codex/worktrees/a/fullstack"]
        )
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [
                    [RemoteProject(path: "/srv/old", discoveredSessionCount: 1, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))],
                    []
                ]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let worktreeList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = worktreeList.nextCursor
        var params = try requestParams(for: worktreeList, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/.codex/worktrees/a/fullstack")
        XCTAssertEqual(params["archived"] as? Bool, false)
        transport.receive("""
        {"id":\(worktreeList.id),"result":{"data":[
          {"id":"thread-worktree","preview":"Worktree","cwd":"/srv/.codex/worktrees/a/fullstack","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"turns":[]},
          {"id":"thread-other","preview":"Other","cwd":"/srv/other","status":{"type":"idle"},"updatedAt":1770000500,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let mainList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = mainList.nextCursor
        params = try requestParams(for: mainList, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/fullstack")
        XCTAssertEqual(params["archived"] as? Bool, false)
        transport.receive("""
        {"id":\(mainList.id),"result":{"data":[
          {"id":"thread-main","preview":"Main","cwd":"/srv/fullstack","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-worktree",
          "preview":"Worktree",
          "cwd":"/srv/.codex/worktrees/a/fullstack",
          "status":{"type":"idle"},
          "updatedAt":1770000400,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        XCTAssertEqual(viewModel.threads.map(\.id), ["thread-worktree", "thread-main"])
        XCTAssertEqual(viewModel.selectedThreadID, "thread-worktree")
        await viewModel.disconnect()
    }

    @MainActor
    func testConnectKeepsAppServerConnectedWhenInitialSessionSyncCannotDecode() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [
                    [RemoteProject(path: "/srv/app", discoveredSessionCount: 1, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))]
                ]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        let params = try requestParams(for: list, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        transport.receive(#"{"id":\#(list.id),"result":{"data":[{"id":"bad-thread"}],"nextCursor":null}}"#)

        await connectTask.value

        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertTrue(viewModel.isAppServerConnected)
        XCTAssertTrue(viewModel.statusMessage?.contains("thread/list") == true, viewModel.statusMessage ?? "")
        XCTAssertTrue(viewModel.statusMessage?.contains("missing key `cwd`") == true, viewModel.statusMessage ?? "")
        await viewModel.disconnect()
    }

    @MainActor
    func testStartNewSessionIgnoresSecondTapWhileBusy() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [
                    [RemoteProject(path: "/srv/old", discoveredSessionCount: 1, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))],
                    []
                ]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive(#"{"id":\#(list.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        cursor = transport.sentLinesSnapshot.count
        let firstTap = Task { await viewModel.startNewSession() }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        await viewModel.startNewSession()
        let sentMethods = transport.sentLinesSnapshot.compactMap(methodName)
        XCTAssertEqual(sentMethods.filter { $0 == "thread/start" }.count, 1)

        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"New thread",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000400,
          "createdAt":1770000400,
          "turns":[]
        }}}
        """)
        await firstTap.value
        await viewModel.disconnect()
    }

    @MainActor
    func testDeleteServerRestoresCredentialWhenMetadataRollbackIsNeeded() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = FailingSaveServerRepository(servers: [server], failOnSaveNumber: 1)
        let credential = SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil)
        let credentials = SpyCredentialStore(values: [server.id: credential])
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        let deleted = await viewModel.deleteServer(server)

        XCTAssertFalse(deleted)
        XCTAssertEqual(viewModel.servers, [server])
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id), credential)
        XCTAssertEqual(credentials.deletedServerIDs, [server.id])
        XCTAssertEqual(credentials.savedServerIDs, [server.id])
    }

    @MainActor
    func testDeleteServerStopsBeforeMetadataMutationWhenCredentialLoadFails() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = FailingSaveServerRepository(servers: [server])
        let credentials = SpyCredentialStore(loadError: TestError.credentialLoad)
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        let deleted = await viewModel.deleteServer(server)

        XCTAssertFalse(deleted)
        XCTAssertEqual(viewModel.servers, [server])
        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertTrue(credentials.deletedServerIDs.isEmpty)
        XCTAssertTrue(credentials.savedServerIDs.isEmpty)
    }

    @MainActor
    func testDeleteServerRestoresCredentialWhenCredentialDeleteFails() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = FailingSaveServerRepository(servers: [server])
        let credential = SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil)
        let credentials = SpyCredentialStore(
            values: [server.id: credential],
            deleteError: TestError.credentialDelete,
            removeBeforeDeleteError: true
        )
        let viewModel = AppViewModel(repository: repository, credentialStore: credentials, sshService: StubSSHService())

        let deleted = await viewModel.deleteServer(server)

        XCTAssertFalse(deleted)
        XCTAssertEqual(viewModel.servers, [server])
        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id), credential)
        XCTAssertEqual(credentials.deletedServerIDs, [server.id])
        XCTAssertEqual(credentials.savedServerIDs, [server.id])
    }

    @MainActor
    func testRefreshProjectsStoresDiscoveredSessionCounts() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(discoveredProjects: [
                RemoteProject(
                    path: "/srv/app",
                    discoveredSessionCount: 3,
                    lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300)
                )
            ])
        )

        await viewModel.refreshProjects()

        let project = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(project.path, "/srv/app")
        XCTAssertEqual(project.sessionPaths, ["/srv/app"])
        XCTAssertTrue(project.discovered)
        XCTAssertEqual(project.discoveredSessionCount, 3)
        XCTAssertEqual(project.lastDiscoveredAt, Date(timeIntervalSince1970: 1_770_000_300))
    }

    @MainActor
    func testRefreshProjectsFailureDoesNotMarkConnectionFailed() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(discoverProjectsError: TestError.discovery)
        )

        await viewModel.refreshProjects()

        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertNotNil(viewModel.statusMessage)
    }

    @MainActor
    func testRefreshProjectsStoresDiscoveredWorktreeSessionPaths() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(discoveredProjects: [
                RemoteProject(
                    path: "/srv/fullstack",
                    sessionPaths: ["/srv/fullstack", "/srv/.codex/worktrees/a/fullstack"],
                    discoveredSessionCount: 5,
                    lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_500)
                )
            ])
        )

        await viewModel.refreshProjects()

        let project = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(project.path, "/srv/fullstack")
        XCTAssertEqual(project.sessionPaths, ["/srv/fullstack", "/srv/.codex/worktrees/a/fullstack"])
        XCTAssertEqual(project.discoveredSessionCount, 5)
    }

    @MainActor
    func testProjectFavoritePersistsAndSurvivesDiscoveryRefresh() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(discoveredProjects: [
                RemoteProject(path: "/srv/app", discoveredSessionCount: 4, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_400))
            ])
        )

        XCTAssertTrue(viewModel.setProjectFavorite(project, isFavorite: true))
        var savedProject = try XCTUnwrap(try repository.loadServers().first?.projects.first)
        XCTAssertTrue(savedProject.isFavorite)

        await viewModel.refreshProjects()

        savedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertTrue(savedProject.isFavorite)
        XCTAssertEqual(savedProject.discoveredSessionCount, 4)
    }

    @MainActor
    func testRefreshProjectsRemovesStaleDiscoveredProjects() async throws {
        let project = ProjectRecord(
            path: "/srv/app",
            displayName: "app",
            discovered: true,
            discoveredSessionCount: 3,
            lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300)
        )
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(discoveredProjects: [])
        )

        await viewModel.refreshProjects()

        XCTAssertTrue(try XCTUnwrap(viewModel.selectedServer).projects.isEmpty)
    }

    @MainActor
    func testRefreshProjectsClearsThreadStateWhenSelectedProjectIsRemoved() async throws {
        let project = ProjectRecord(path: "/srv/old", discovered: true, discoveredSessionCount: 1)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [
                    [RemoteProject(path: "/srv/old", discoveredSessionCount: 1, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))],
                    []
                ]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-old","preview":"Old","cwd":"/srv/old","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-old",
          "preview":"Old",
          "cwd":"/srv/old",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value
        XCTAssertEqual(viewModel.selectedThreadID, "thread-old")

        cursor = transport.sentLinesSnapshot.count
        let refreshTask = Task { await viewModel.refreshProjects() }
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(loadedList.id),"result":{"data":[]}}
        """)
        await refreshTask.value

        XCTAssertTrue(try XCTUnwrap(viewModel.selectedServer).projects.isEmpty)
        XCTAssertNil(viewModel.selectedProject)
        XCTAssertTrue(viewModel.threads.isEmpty)
        XCTAssertNil(viewModel.selectedThreadID)
        XCTAssertNil(viewModel.selectedThread)
        XCTAssertTrue(viewModel.conversationSections.isEmpty)
        await viewModel.disconnect()
    }

    @MainActor
    func testRefreshProjectsPreservesAllSessionsScope() async throws {
        let project = ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 1)
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(
                discoveredProjects: [
                    RemoteProject(path: "/srv/app", discoveredSessionCount: 2, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))
                ]
            )
        )

        viewModel.selectAllSessions()
        await viewModel.refreshProjects()

        XCTAssertTrue(viewModel.isShowingAllSessions)
        XCTAssertNil(viewModel.selectedProjectID)
        XCTAssertNil(viewModel.selectedProject)
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.discoveredSessionCount, 2)
    }

    @MainActor
    func testConnectedRefreshAddsOpenSessionCountsWithoutReplacingDiscoveryCounts() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let discovered = [
            RemoteProject(path: "/srv/app", discoveredSessionCount: 37, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))
        ]
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [discovered]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        var params = try requestParams(for: initialList, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        transport.receive("""
        {"id":\(initialList.id),"result":{"data":[],"nextCursor":null}}
        """)
        await connectTask.value
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.discoveredSessionCount, 37)

        cursor = transport.sentLinesSnapshot.count
        let refreshTask = Task { await viewModel.refreshProjects() }
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        cursor = loadedList.nextCursor
        transport.receive("""
        {"id":\(loadedList.id),"result":{"data":["thread-open-1","thread-open-2"]}}
        """)
        let firstSummary = try await respondToThreadSummary(
            threadID: "thread-open-1",
            preview: "One",
            cwd: "/srv/app",
            updatedAt: 1_770_000_400,
            in: transport,
            after: cursor
        )
        cursor = firstSummary.nextCursor
        _ = try await respondToThreadSummary(
            threadID: "thread-open-2",
            preview: "Two",
            cwd: "/srv/app",
            statusJSON: #"{"type":"active","activeFlags":[]}"#,
            updatedAt: 1_770_000_500,
            in: transport,
            after: cursor
        )
        await refreshTask.value

        let refreshedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(refreshedProject.discoveredSessionCount, 37)
        XCTAssertEqual(refreshedProject.lastDiscoveredAt, Date(timeIntervalSince1970: 1_770_000_300))
        XCTAssertEqual(refreshedProject.activeChatCount, 2)
        XCTAssertEqual(refreshedProject.lastActiveChatAt, Date(timeIntervalSince1970: 1_770_000_500))
        await viewModel.disconnect()
    }

    @MainActor
    func testConnectCanSyncDiscoveryCountsWithOpenSessionCounts() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let discovered = [
            RemoteProject(path: "/srv/app", discoveredSessionCount: 37, lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300))
        ]
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [discovered]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer(syncActiveChatCounts: true) }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        cursor = loadedList.nextCursor
        transport.receive("""
        {"id":\(loadedList.id),"result":{"data":[]}}
        """)
        let scopedList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        let scopedParams = try requestParams(for: scopedList, in: transport)
        XCTAssertEqual(scopedParams["cwd"] as? String, "/srv/app")
        transport.receive("""
        {"id":\(scopedList.id),"result":{"data":[],"nextCursor":null}}
        """)
        await connectTask.value

        let refreshedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(refreshedProject.discoveredSessionCount, 37)
        XCTAssertEqual(refreshedProject.lastDiscoveredAt, Date(timeIntervalSince1970: 1_770_000_300))
        XCTAssertEqual(refreshedProject.activeChatCount, 0)
        XCTAssertNil(refreshedProject.lastActiveChatAt)
        await viewModel.disconnect()
    }

    @MainActor
    func testEnsureSelectedServerConnectedIsIdempotent() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.ensureSelectedServerConnected() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        cursor = loadedList.nextCursor
        transport.receive(#"{"id":\#(loadedList.id),"result":{"data":[]}}"#)
        let scopedList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive(#"{"id":\#(scopedList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let lineCountAfterConnect = transport.sentLinesSnapshot.count
        await viewModel.ensureSelectedServerConnected()

        XCTAssertEqual(transport.sentLinesSnapshot.count, lineCountAfterConnect)
        await viewModel.disconnect()
    }

    @MainActor
    func testConnectedRefreshGroupsCodexWorktreeCountsUnderMainProject() async throws {
        let project = ProjectRecord(path: "/Users/mazdak/Code/resq/fullstack")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let discovered = [
            RemoteProject(
                path: "/Users/mazdak/Code/resq/fullstack",
                discoveredSessionCount: 205,
                lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300)
            )
        ]
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(
                appServer: CodexAppServerClient(transport: transport),
                discoveredProjectBatches: [discovered]
            )
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive("""
        {"id":\(initialList.id),"result":{"data":[],"nextCursor":null}}
        """)
        await connectTask.value

        cursor = transport.sentLinesSnapshot.count
        let refreshTask = Task { await viewModel.refreshProjects() }
        let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
        cursor = loadedList.nextCursor
        transport.receive("""
        {"id":\(loadedList.id),"result":{"data":["thread-main","thread-worktree-a","thread-worktree-b"]}}
        """)
        let mainSummary = try await respondToThreadSummary(
            threadID: "thread-main",
            preview: "Main",
            cwd: "/Users/mazdak/Code/resq/fullstack",
            updatedAt: 1_770_000_400,
            in: transport,
            after: cursor
        )
        cursor = mainSummary.nextCursor
        let worktreeASummary = try await respondToThreadSummary(
            threadID: "thread-worktree-a",
            preview: "A",
            cwd: "/Users/mazdak/.codex/worktrees/b717/fullstack",
            updatedAt: 1_770_000_500,
            in: transport,
            after: cursor
        )
        cursor = worktreeASummary.nextCursor
        _ = try await respondToThreadSummary(
            threadID: "thread-worktree-b",
            preview: "B",
            cwd: "/Users/mazdak/.codex/worktrees/c402/fullstack",
            updatedAt: 1_770_000_600,
            in: transport,
            after: cursor
        )
        await refreshTask.value

        let projects = try XCTUnwrap(viewModel.selectedServer?.projects)
        XCTAssertEqual(projects.map(\.path), ["/Users/mazdak/Code/resq/fullstack"])
        let refreshedProject = try XCTUnwrap(projects.first)
        XCTAssertEqual(refreshedProject.activeChatCount, 3)
        XCTAssertEqual(
            refreshedProject.sessionPaths,
            [
                "/Users/mazdak/Code/resq/fullstack",
                "/Users/mazdak/.codex/worktrees/c402/fullstack",
                "/Users/mazdak/.codex/worktrees/b717/fullstack",
            ]
        )
        XCTAssertEqual(refreshedProject.lastActiveChatAt, Date(timeIntervalSince1970: 1_770_000_600))
        await viewModel.disconnect()
    }

    @MainActor
    func testRefreshProjectsKeepsFavoriteStaleDiscoveredProject() async throws {
        let project = ProjectRecord(
            path: "/srv/app",
            displayName: "app",
            discovered: true,
            discoveredSessionCount: 3,
            lastDiscoveredAt: Date(timeIntervalSince1970: 1_770_000_300),
            isFavorite: true
        )
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(discoveredProjects: [])
        )

        await viewModel.refreshProjects()

        let refreshed = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(refreshed.path, "/srv/app")
        XCTAssertFalse(refreshed.discovered)
        XCTAssertEqual(refreshed.discoveredSessionCount, 0)
        XCTAssertNil(refreshed.lastDiscoveredAt)
        XCTAssertTrue(refreshed.isFavorite)
    }

    @MainActor
    func testSendComposerTextDiscardsStartedThreadWhenProjectChangesBeforeResponse() async throws {
        let projectOne = ProjectRecord(path: "/srv/one")
        let projectTwo = ProjectRecord(path: "/srv/two")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [projectOne, projectTwo]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive(#"{"id":\#(list.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor

        let renderTokenBeforeProjectChange = viewModel.conversationRenderToken
        viewModel.selectProject(projectTwo.id)
        XCTAssertGreaterThan(viewModel.conversationRenderToken, renderTokenBeforeProjectChange)
        XCTAssertEqual(viewModel.conversationRenderDigest, "")
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-old-project",
          "preview":"Start work",
          "cwd":"/srv/one",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await sendTask.value

        XCTAssertEqual(viewModel.selectedProjectID, projectTwo.id)
        XCTAssertNil(viewModel.selectedThreadID)
        XCTAssertNil(viewModel.selectedThread)
        XCTAssertTrue(viewModel.conversationSections.isEmpty)
        XCTAssertFalse(transport.sentLinesSnapshot.compactMap(methodName).contains("turn/start"))
        await viewModel.disconnect()
    }

    @MainActor
    func testComposerStartContinuesWhenThreadStartedEventSelectsNewSessionFirst() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        viewModel.selectedReasoningEffort = .high
        viewModel.selectedAccessMode = .readOnly
        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor

        transport.receive("""
        {"method":"thread/started","params":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        try await waitForSelectedThreadID("thread-new", in: viewModel)

        let notificationList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = notificationList.nextCursor
        transport.receive("""
        {"id":\(notificationList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        let params = try requestParams(for: startTurn, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-new")
        XCTAssertEqual(params["effort"] as? String, "high")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        let sandboxPolicy = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])
        XCTAssertEqual(sandboxPolicy["type"] as? String, "readOnly")
        let startInput = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(startInput.first?["text"] as? String, "Start work")
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value

        XCTAssertEqual(viewModel.selectedThreadID, "thread-new")
        try await waitForConversationSection(kind: .user, containing: "Start work", in: viewModel)

        await viewModel.disconnect()
    }

    @MainActor
    func testComposerStartHandlesCompletedTurnStartResponseWithoutCompletionNotification() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"completed",
          "items":[],
          "error":null,
          "startedAt":1770000300,
          "completedAt":1770000301,
          "durationMs":1000
        }}}
        """)

        let completedRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = completedRead.nextCursor
        transport.receive("""
        {"id":\(completedRead.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000301,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-1",
            "status":"completed",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]},
              {"type":"agentMessage","id":"item-agent","text":"Done"}
            ]
          }]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let postStartRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(postStartRead.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000301,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-1",
            "status":"completed",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]},
              {"type":"agentMessage","id":"item-agent","text":"Done"}
            ]
          }]
        }}}
        """)
        await sendTask.value

        XCTAssertEqual(viewModel.selectedThreadID, "thread-new")
        XCTAssertEqual(viewModel.selectedThread?.status.label, "Idle")
        XCTAssertFalse(viewModel.canInterruptActiveTurn)
        try await waitForConversationSection(kind: .user, containing: "Start work", in: viewModel)
        try await waitForConversationSection(kind: .assistant, containing: "Done", in: viewModel)

        await viewModel.disconnect()
    }

    @MainActor
    func testActiveTurnPollingHydratesCompletionWhenCompletionNotificationIsMissing() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            activeTurnRefreshIntervalNanoseconds: 100_000_000
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value
        XCTAssertTrue(viewModel.canInterruptActiveTurn)

        let pollRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(pollRead.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000302,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-1",
            "status":"completed",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]},
              {"type":"agentMessage","id":"item-agent","text":"Done from polling"}
            ]
          }]
        }}}
        """)

        try await waitForConversationSection(kind: .assistant, containing: "Done from polling", in: viewModel)
        XCTAssertFalse(viewModel.canInterruptActiveTurn)

        await viewModel.disconnect()
    }

    @MainActor
    func testDefaultComposerSendStartsTurnAfterHydratingStaleActiveSession() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-stale-active","preview":"Existing work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let initialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = initialRead.nextCursor
        transport.receive("""
        {"id":\(initialRead.id),"result":{"thread":{
          "id":"thread-stale-active",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value
        XCTAssertFalse(viewModel.canInterruptActiveTurn)

        let sendTask = Task { await viewModel.sendComposerText("Visible follow-up") }
        let freshnessRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = freshnessRead.nextCursor
        transport.receive("""
        {"id":\(freshnessRead.id),"result":{"thread":{
          "id":"thread-stale-active",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000301,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        let params = try requestParams(for: startTurn, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-stale-active")
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["text"] as? String, "Visible follow-up")
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-follow-up",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-follow-up","content":[{"type":"text","text":"Visible follow-up"}]}
          ]
        }}}
        """)

        let refreshList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(refreshList.id),"result":{"data":[
          {"id":"thread-stale-active","preview":"Visible follow-up","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000302,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value

        try await waitForConversationSection(kind: .user, containing: "Visible follow-up", in: viewModel)
        XCTAssertEqual(viewModel.queuedTurnInputCount, 0)
        await viewModel.disconnect()
    }

    @MainActor
    func testComposerCannotSendWhileSelectedSessionIsOpening() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive(#"{"id":\#(list.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value
        XCTAssertTrue(viewModel.canSendMessage)

        let thread = CodexThread(
            id: "thread-opening",
            preview: "Opening work",
            cwd: "/srv/app",
            status: .idle,
            updatedAt: Date(timeIntervalSince1970: 1_770_000_300),
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            turns: []
        )
        let openTask = Task { await viewModel.openThread(thread) }
        let read = try await waitForRequest(method: "thread/resume", in: transport, after: cursor)
        XCTAssertFalse(viewModel.canSendMessage)
        await viewModel.sendComposerText("Should not send yet")
        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "turn/start" })
        XCTAssertEqual(viewModel.statusMessage, "Wait for the session to finish loading before sending a message.")
        cursor = read.nextCursor
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-opening",
          "preview":"Opening work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await openTask.value

        XCTAssertTrue(viewModel.canSendMessage)
        await viewModel.disconnect()
    }

    @MainActor
    func testActiveTurnPollingAddsMissedItemsWhileThreadIsStillActive() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            activeTurnRefreshIntervalNanoseconds: 100_000_000
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value

        let pollRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(pollRead.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000302,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-1",
            "status":"inProgress",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]},
              {"type":"agentMessage","id":"item-agent","text":"Recovered from polling"}
            ]
          }]
        }}}
        """)

        try await waitForConversationSection(kind: .assistant, containing: "Recovered from polling", in: viewModel)
        XCTAssertTrue(viewModel.canInterruptActiveTurn)

        await viewModel.disconnect()
    }

    @MainActor
    func testActiveTurnPollingDoesNotReplaceLiveDeltasWithStaleActiveRead() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            activeTurnRefreshIntervalNanoseconds: 100_000_000
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value

        let pollRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        let renderTokenBeforeDelta = viewModel.conversationRenderToken
        let followTokenBeforeDelta = viewModel.conversationFollowToken
        transport.receive("""
        {"method":"item/agentMessage/delta","params":{
          "threadId":"thread-new",
          "itemId":"item-agent",
          "delta":"Streaming"
        }}
        """)
        try await waitForConversationSection(kind: .assistant, containing: "Streaming", in: viewModel)
        XCTAssertGreaterThan(viewModel.conversationRenderToken, renderTokenBeforeDelta)
        XCTAssertGreaterThan(viewModel.conversationFollowToken, followTokenBeforeDelta)
        XCTAssertTrue(viewModel.conversationRenderDigest.contains("Streaming"))

        transport.receive("""
        {"id":\(pollRead.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000301,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-1",
            "status":"inProgress",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
            ]
          }]
        }}}
        """)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.conversationSections.contains { section in
            section.kind == .assistant && section.body.contains("Streaming")
        })
        XCTAssertTrue(viewModel.canInterruptActiveTurn)
        let sendToken = viewModel.conversationSendToken
        viewModel.requestConversationSendScroll()
        XCTAssertEqual(viewModel.conversationSendToken, sendToken + 1)

        await viewModel.disconnect()
    }

    @MainActor
    func testDelayedThreadStartedDoesNotReplaceActiveComposerThread() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value

        transport.receive("""
        {"method":"thread/started","params":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let notificationList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(notificationList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        XCTAssertEqual(viewModel.selectedThreadID, "thread-new")
        XCTAssertTrue(viewModel.canInterruptActiveTurn)
        try await waitForConversationSection(kind: .user, containing: "Start work", in: viewModel)

        await viewModel.disconnect()
    }

    @MainActor
    func testComposerStartsSteersAndInterruptsThroughViewModel() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let startSendTask = Task { await viewModel.sendComposerText("Start work") }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        var params = try requestParams(for: startThread, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-new",
          "preview":"Start work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        params = try requestParams(for: startTurn, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-new")
        let startInput = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(startInput.first?["text"] as? String, "Start work")
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-1",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postStartList.nextCursor
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await startSendTask.value
        XCTAssertEqual(viewModel.selectedThreadID, "thread-new")
        try await waitForConversationSection(kind: .user, containing: "Start work", in: viewModel)

        let steerTask = Task { await viewModel.steerComposerText("Keep going") }
        let steer = try await waitForRequest(method: "turn/steer", in: transport, after: cursor)
        params = try requestParams(for: steer, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-new")
        XCTAssertEqual(params["expectedTurnId"] as? String, "turn-1")
        let steerInput = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(steerInput.first?["text"] as? String, "Keep going")
        cursor = steer.nextCursor
        transport.receive(#"{"id":\#(steer.id),"result":{}}"#)

        let postSteerList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = postSteerList.nextCursor
        transport.receive("""
        {"id":\(postSteerList.id),"result":{"data":[
          {"id":"thread-new","preview":"Start work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000302,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await steerTask.value
        transport.receive("""
        {"method":"item/agentMessage/delta","params":{
          "threadId":"thread-new",
          "itemId":"item-agent",
          "delta":"Working"
        }}
        """)
        try await waitForConversationSection(kind: .assistant, containing: "Working", in: viewModel)

        let interruptTask = Task { await viewModel.interruptActiveTurn() }
        let interrupt = try await waitForRequest(method: "turn/interrupt", in: transport, after: cursor)
        params = try requestParams(for: interrupt, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-new")
        XCTAssertEqual(params["turnId"] as? String, "turn-1")
        transport.receive(#"{"id":\#(interrupt.id),"result":{}}"#)
        await interruptTask.value

        await viewModel.disconnect()
    }

    @MainActor
    func testSteeringHydratesActiveSummaryBeforeSending() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport)),
            activeTurnRefreshIntervalNanoseconds: 60_000_000_000
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-active","preview":"Existing work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let pendingInitialRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = pendingInitialRead.nextCursor
        try await waitForSelectedThreadID("thread-active", in: viewModel)
        XCTAssertFalse(viewModel.canSendMessage)
        transport.receive("""
        {"id":\(pendingInitialRead.id),"result":{"thread":{
          "id":"thread-active",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value
        XCTAssertTrue(viewModel.canSendMessage)
        XCTAssertFalse(viewModel.canInterruptActiveTurn)

        let steerTask = Task { await viewModel.sendComposerText("Follow up", queueWhenActive: false) }
        let hydrateBeforeSteer = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = hydrateBeforeSteer.nextCursor
        transport.receive("""
        {"id":\(hydrateBeforeSteer.id),"result":{"thread":{
          "id":"thread-active",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-active",
            "status":"inProgress",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
            ]
          }]
        }}}
        """)

        let steer = try await waitForRequest(method: "turn/steer", in: transport, after: cursor)
        let params = try requestParams(for: steer, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-active")
        XCTAssertEqual(params["expectedTurnId"] as? String, "turn-active")
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["text"] as? String, "Follow up")
        cursor = steer.nextCursor
        transport.receive(#"{"id":\#(steer.id),"result":{}}"#)

        let refreshList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(refreshList.id),"result":{"data":[
          {"id":"thread-active","preview":"Existing work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await steerTask.value
        XCTAssertEqual(viewModel.queuedTurnInputCount, 0)
        XCTAssertTrue(viewModel.canInterruptActiveTurn)
        try await waitForConversationSection(kind: .user, containing: "Start work", in: viewModel)

        await viewModel.disconnect()
    }

    @MainActor
    func testComposerCanSendLocalImageInput() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let imagePath = "/Users/mazdak/Downloads/download-latest-macos-app-badge-2x.png"
        let remoteImagePath = "/tmp/mobidex-uploaded/download-latest-macos-app-badge-2x.png"
        let sendTask = Task {
            await viewModel.sendComposerInput(text: "Describe this image.", localImagePaths: [imagePath])
        }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-image",
          "preview":"Describe this image.",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)

        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        let params = try requestParams(for: startTurn, in: transport)
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "text")
        XCTAssertEqual(input[0]["text"] as? String, "Describe this image.")
        XCTAssertEqual(input[1]["type"] as? String, "localImage")
        XCTAssertEqual(input[1]["path"] as? String, remoteImagePath)
        XCTAssertEqual(sshService.stagedLocalPaths, [imagePath])
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-image",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[
              {"type":"text","text":"Describe this image."},
              {"type":"localImage","path":"\(remoteImagePath)"}
            ]}
          ]
        }}}
        """)

        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-image","preview":"Describe this image.","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value

        try await waitForConversationSection(kind: .user, containing: "download-latest-macos-app-badge-2x.png", in: viewModel)
        await viewModel.disconnect()
    }

    @MainActor
    func testComposerUploadBlocksConcurrentSendBeforeTurnRequest() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(
            appServer: CodexAppServerClient(transport: transport),
            stageDelayNanoseconds: 500_000_000
        )
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let sendTask = Task {
            await viewModel.sendComposerInput(
                text: "Describe this image.",
                localImagePaths: ["/Users/mazdak/Downloads/download-latest-macos-app-badge-2x.png"]
            )
        }
        try await waitForCannotSend(in: viewModel)
        await viewModel.sendComposerText("Second send")
        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "thread/start" })
        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "turn/start" })

        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        cursor = startThread.nextCursor
        transport.receive("""
        {"id":\(startThread.id),"result":{"thread":{
          "id":"thread-image",
          "preview":"Describe this image.",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        let startTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        cursor = startTurn.nextCursor
        transport.receive("""
        {"id":\(startTurn.id),"result":{"turn":{
          "id":"turn-image",
          "status":"inProgress",
          "items":[{"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Describe this image."}]}]
        }}}
        """)
        let postStartList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(postStartList.id),"result":{"data":[
          {"id":"thread-image","preview":"Describe this image.","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await sendTask.value
        await viewModel.disconnect()
    }

    @MainActor
    func testComposerSendFromExistingSessionDoesNotStartTurnIfSelectedThreadClearsDuringUpload() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(
            appServer: CodexAppServerClient(transport: transport),
            stageDelayNanoseconds: 200_000_000
        )
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-existing","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = read.nextCursor
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-existing",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        let sendTask = Task {
            await viewModel.sendComposerInput(
                text: "Use existing session",
                localImagePaths: ["/tmp/example.png"]
            )
        }
        try await waitForCannotSend(in: viewModel)
        let refreshTask = Task { await viewModel.refreshThreads() }
        let refreshList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = refreshList.nextCursor
        transport.receive(#"{"id":\#(refreshList.id),"result":{"data":[],"nextCursor":null}}"#)
        await refreshTask.value
        await sendTask.value

        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "thread/start" })
        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "turn/start" })
        XCTAssertEqual(viewModel.statusMessage, "The selected session changed before the message could be sent.")
    }

    @MainActor
    func testComposerSendUsesCurrentThreadStatusAfterUploadDelay() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let sshService = ScriptedSSHService(
            appServer: CodexAppServerClient(transport: transport),
            stageDelayNanoseconds: 200_000_000
        )
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: sshService
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-existing","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = read.nextCursor
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-existing",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        let sendTask = Task {
            await viewModel.sendComposerInput(
                text: "Use current status",
                localImagePaths: ["/tmp/example.png"]
            )
        }
        try await waitForCannotSend(in: viewModel)
        transport.receive("""
        {"method":"turn/started","params":{"threadId":"thread-existing","turn":{
          "id":"turn-active",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Already running"}]}
          ]
        }}}
        """)
        try await waitForCanInterrupt(in: viewModel)
        await sendTask.value

        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "thread/start" })
        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "turn/start" })
        XCTAssertEqual(viewModel.queuedTurnInputCount, 1)
        XCTAssertEqual(viewModel.statusMessage, "Queued message for after the current turn.")
    }

    @MainActor
    func testRefreshChangedFilesUsesSelectedProjectDiff() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let initialList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = initialList.nextCursor
        transport.receive(#"{"id":\#(initialList.id),"result":{"data":[],"nextCursor":null}}"#)
        await connectTask.value

        let refreshTask = Task { await viewModel.refreshChangedFilesForSelectedProject() }
        let diff = try await waitForRequest(method: "gitDiffToRemote", in: transport, after: cursor)
        let params = try requestParams(for: diff, in: transport)
        XCTAssertEqual(params["cwd"] as? String, "/srv/app")
        transport.receive("""
        {"id":\(diff.id),"result":{"sha":"abc123","diff":"diff --git a/Sources/App.swift b/Sources/App.swift\\n--- a/Sources/App.swift\\n+++ b/Sources/App.swift\\n@@\\n-old\\n+new\\ndiff --git a/Tests/AppTests.swift b/Tests/AppTests.swift\\n--- a/Tests/AppTests.swift\\n+++ b/Tests/AppTests.swift\\n@@\\n-old\\n+new\\n"}}
        """)

        let changedFiles = await refreshTask.value
        XCTAssertEqual(changedFiles, ["Sources/App.swift", "Tests/AppTests.swift"])
        XCTAssertEqual(viewModel.changedFiles, changedFiles)
        XCTAssertEqual(viewModel.diffSnapshot.sha, "abc123")
        XCTAssertEqual(viewModel.diffSnapshot.files.map(\.path), changedFiles)
        XCTAssertEqual(viewModel.diffSnapshot.files.first?.diff.contains("Sources/App.swift"), true)
        await viewModel.disconnect()
    }

    @MainActor
    func testQueuedComposerTextStartsAfterActiveTurnCompletes() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-active","preview":"Existing work","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = read.nextCursor
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-active",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-active",
            "status":"inProgress",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]}
            ]
          }]
        }}}
        """)
        await connectTask.value

        await viewModel.sendComposerText("Queued follow-up")
        XCTAssertEqual(viewModel.queuedTurnInputCount, 1)
        XCTAssertFalse(transport.sentLinesSnapshot[cursor...].contains { methodName($0) == "turn/start" })

        transport.receive("""
        {"method":"turn/completed","params":{"threadId":"thread-active","turn":{
          "id":"turn-active",
          "status":"completed",
          "items":[
            {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]},
            {"type":"agentMessage","id":"item-agent","text":"Done"}
          ]
        }}}
        """)

        let completionRead = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = completionRead.nextCursor
        transport.receive("""
        {"id":\(completionRead.id),"result":{"thread":{
          "id":"thread-active",
          "preview":"Existing work",
          "cwd":"/srv/app",
          "status":{"type":"idle"},
          "updatedAt":1770000301,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-active",
            "status":"completed",
            "items":[
              {"type":"userMessage","id":"item-user","content":[{"type":"text","text":"Start work"}]},
              {"type":"agentMessage","id":"item-agent","text":"Done"}
            ]
          }]
        }}}
        """)
        let completionList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = completionList.nextCursor
        transport.receive("""
        {"id":\(completionList.id),"result":{"data":[
          {"id":"thread-active","preview":"Existing work","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000301,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let queuedTurn = try await waitForRequest(method: "turn/start", in: transport, after: cursor)
        let params = try requestParams(for: queuedTurn, in: transport)
        XCTAssertEqual(params["threadId"] as? String, "thread-active")
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["text"] as? String, "Queued follow-up")
        XCTAssertEqual(viewModel.queuedTurnInputCount, 0)
        cursor = queuedTurn.nextCursor
        transport.receive("""
        {"id":\(queuedTurn.id),"result":{"turn":{
          "id":"turn-queued",
          "status":"inProgress",
          "items":[
            {"type":"userMessage","id":"item-queued","content":[{"type":"text","text":"Queued follow-up"}]}
          ]
        }}}
        """)
        let queuedList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(queuedList.id),"result":{"data":[
          {"id":"thread-active","preview":"Queued follow-up","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000302,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        try await waitForConversationSection(kind: .user, containing: "Queued follow-up", in: viewModel)
        await viewModel.disconnect()
    }

    @MainActor
    func testLoadThreadsSortsSessionsByUpdatedTime() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"idle-server-first","preview":"Idle server first","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000100,"createdAt":1770000001,"turns":[]},
          {"id":"active-server-first","preview":"Active server first","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000200,"createdAt":1770000002,"turns":[]},
          {"id":"active-server-second","preview":"Active server second","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000500,"createdAt":1770000003,"turns":[]},
          {"id":"idle-server-second","preview":"Idle server second","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000004,"turns":[]}
        ],"nextCursor":null}}
        """)

        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = read.nextCursor
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"active-server-second",
          "preview":"Active server second",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000500,
          "createdAt":1770000003,
          "turns":[]
        }}}
        """)
        await connectTask.value

        let newestFirstOrder = ["active-server-second", "idle-server-second", "active-server-first", "idle-server-first"]
        XCTAssertEqual(viewModel.threads.map(\.id), newestFirstOrder)
        XCTAssertEqual(viewModel.selectedThreadID, "active-server-second")

        cursor = transport.sentLinesSnapshot.count
        transport.receive(#"{"method":"thread/updated","params":{"threadId":"active-server-first"}}"#)
        let refreshList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        transport.receive("""
        {"id":\(refreshList.id),"result":{"data":[
          {"id":"idle-server-first","preview":"Idle server first","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000100,"createdAt":1770000001,"turns":[]},
          {"id":"active-server-first","preview":"Active server first","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000200,"createdAt":1770000002,"turns":[]},
          {"id":"active-server-second","preview":"Active server second","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000500,"createdAt":1770000003,"turns":[]},
          {"id":"idle-server-second","preview":"Idle server second","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000004,"turns":[]}
        ],"nextCursor":null}}
        """)
        try await waitForThreadIDs(newestFirstOrder, in: viewModel)

        await viewModel.disconnect()
	    }

    @MainActor
    func testPlanAndFileChangeEventsUpdateLiveConversation() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)

        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Build check","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Build check",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[{
            "id":"turn-1",
            "status":"inProgress",
            "items":[
              {"type":"plan","id":"item-plan","text":""},
              {"type":"fileChange","id":"item-file","status":"inProgress","changes":[]}
            ]
          }]
        }}}
        """)
        await connectTask.value

        transport.receive("""
        {"method":"item/plan/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-plan","delta":"Inspect the failure"}}
        """)
        try await waitForConversationSection(kind: .plan, containing: "Inspect the failure", in: viewModel)

        transport.receive("""
        {"method":"item/fileChange/patchUpdated","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-file","changes":[
          {"path":"Sources/App.swift","kind":{"type":"update","movePath":null},"diff":"@@\\n+fixed"}
        ]}}
        """)
        try await waitForConversationSection(kind: .fileChange, containing: "Sources/App.swift", in: viewModel)
        try await waitForConversationSection(kind: .fileChange, containing: "+fixed", in: viewModel)

        transport.receive("""
        {"method":"item/fileChange/outputDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-file","delta":"\\nlegacy patch output"}}
        """)
        try await waitForConversationSection(kind: .fileChange, containing: "legacy patch output", in: viewModel)

        transport.receive("""
        {"method":"turn/plan/updated","params":{"threadId":"thread-1","turnId":"turn-1","explanation":"Updated plan","plan":[
          {"step":"Read the logs","status":"completed"},
          {"step":"Patch the view model","status":"inProgress"}
        ]}}
        """)
        try await waitForConversationSection(kind: .plan, containing: "Updated plan", in: viewModel)
        try await waitForConversationSection(kind: .plan, containing: "[inProgress] Patch the view model", in: viewModel)

        transport.receive("""
        {"method":"turn/diff/updated","params":{"threadId":"thread-1","turnId":"turn-1","diff":"@@\\n+turn diff"}}
        """)
        try await waitForConversationSection(kind: .fileChange, containing: "+turn diff", in: viewModel)

        transport.receive("""
        {"method":"item/commandExecution/terminalInteraction","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-command","processId":"proc-1","stdin":"y\\n"}}
        """)
        try await waitForConversationSection(kind: .command, containing: "stdin: y", in: viewModel)

        transport.receive("""
        {"method":"item/mcpToolCall/progress","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-tool","message":"Fetched issue metadata"}}
        """)
        try await waitForConversationSection(kind: .tool, containing: "Fetched issue metadata", in: viewModel)

        await viewModel.disconnect()
    }

    @MainActor
    func testApprovalRequestsShowCurrentAndLegacyCommandShapes() async throws {
        let project = ProjectRecord(path: "/srv/app")
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .password,
            projects: [project]
        )
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)
        let transport = MockCodexLineTransport()
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: ScriptedSSHService(appServer: CodexAppServerClient(transport: transport))
        )

        let connectTask = Task { await viewModel.connectSelectedServer() }
        var cursor = 0
        let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
        cursor = initialize.nextCursor
        transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)

        let list = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        cursor = list.nextCursor
        transport.receive("""
        {"id":\(list.id),"result":{"data":[
          {"id":"thread-1","preview":"Build check","cwd":"/srv/app","status":{"type":"active","activeFlags":[]},"updatedAt":1770000300,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)

        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
        cursor = read.nextCursor
        transport.receive("""
        {"id":\(read.id),"result":{"thread":{
          "id":"thread-1",
          "preview":"Build check",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000300,
          "createdAt":1770000000,
          "turns":[]
        }}}
        """)
        await connectTask.value

        transport.receive("""
        {"method":"execCommandApproval","id":77,"params":{
          "conversationId":"thread-1",
          "callId":"call-1",
          "approvalId":"approval-1",
          "command":["bun","test"],
          "cwd":"/srv/app",
          "reason":"Needs approval",
          "parsedCmd":[{"type":"unknown","cmd":"bun test"}]
        }}
        """)

        let approval = try await waitForPendingApproval(method: "execCommandApproval", in: viewModel)
        XCTAssertEqual(approval.title, "Command approval")
        XCTAssertTrue(approval.detail.contains("bun test"))

        await viewModel.respond(to: approval, accept: true)
        let response = try await waitForResponse(id: 77, in: transport, after: cursor)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["decision"] as? String, "approved")
        XCTAssertTrue(viewModel.pendingApprovals.isEmpty)
        cursor = transport.sentLinesSnapshot.count

        transport.receive("""
        {"method":"item/commandExecution/requestApproval","id":78,"params":{
          "threadId":"thread-1",
          "turnId":"turn-1",
          "itemId":"item-command",
          "command":"swift test",
          "cwd":"/srv/app",
          "reason":"Needs current approval"
        }}
        """)

        let currentApproval = try await waitForPendingApproval(method: "item/commandExecution/requestApproval", in: viewModel)
        XCTAssertEqual(currentApproval.title, "Command approval")
        XCTAssertTrue(currentApproval.detail.contains("swift test"))

        await viewModel.respond(to: currentApproval, accept: false)
        let currentResponse = try await waitForResponse(id: 78, in: transport, after: cursor)
        let currentResult = try XCTUnwrap(currentResponse["result"] as? [String: Any])
        XCTAssertEqual(currentResult["decision"] as? String, "decline")
        XCTAssertTrue(viewModel.pendingApprovals.isEmpty)

        transport.receive("""
        {"method":"item/fileChange/requestApproval","id":79,"params":{
          "threadId":"thread-1",
          "turnId":"turn-1",
          "itemId":"item-file",
          "cwd":"/srv/app",
          "reason":"External resolution test"
        }}
        """)
        _ = try await waitForPendingApproval(method: "item/fileChange/requestApproval", in: viewModel)

        transport.receive("""
        {"method":"serverRequest/resolved","params":{"threadId":"thread-1","requestId":79}}
        """)
        try await waitForNoPendingApprovals(in: viewModel)
        cursor = transport.sentLinesSnapshot.count

        transport.receive("""
        {"method":"applyPatchApproval","id":80,"params":{
          "conversationId":"thread-1",
          "callId":"patch-1",
          "fileChanges":{},
          "reason":"Patch needs approval",
          "grantRoot":"/srv/app"
        }}
        """)

        let patchApproval = try await waitForPendingApproval(method: "applyPatchApproval", in: viewModel)
        XCTAssertEqual(patchApproval.title, "Patch approval")
        XCTAssertTrue(patchApproval.detail.contains("Grant root: /srv/app"))

        await viewModel.respond(to: patchApproval, accept: false)
        let patchResponse = try await waitForResponse(id: 80, in: transport, after: cursor)
        let patchResult = try XCTUnwrap(patchResponse["result"] as? [String: Any])
        XCTAssertEqual(patchResult["decision"] as? String, "denied")
        XCTAssertTrue(viewModel.pendingApprovals.isEmpty)

        await viewModel.disconnect()
    }
}

private enum TestError: Error {
    case persistence
    case credentialLoad
    case credentialSave
    case credentialDelete
    case discovery
    case unexpectedSSH
}

private final class FailingSaveServerRepository: ServerRepository, @unchecked Sendable {
    private var servers: [ServerRecord]
    private let failOnSaveNumber: Int?
    private var saveCount = 0
    private let lock = NSLock()

    init(servers: [ServerRecord], failOnSaveNumber: Int? = nil) {
        self.servers = servers
        self.failOnSaveNumber = failOnSaveNumber
    }

    func loadServers() throws -> [ServerRecord] {
        lock.withLock { servers }
    }

    func saveServers(_ servers: [ServerRecord]) throws {
        try lock.withLock {
            saveCount += 1
            if saveCount == failOnSaveNumber {
                throw TestError.persistence
            }
            self.servers = servers
        }
    }
}

private final class SpyCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [UUID: SSHCredential]
    private let loadError: Error?
    private let deleteError: Error?
    private let removeBeforeDeleteError: Bool
    private var deletedIDs: [UUID] = []
    private var savedIDs: [UUID] = []
    private let lock = NSLock()

    init(
        values: [UUID: SSHCredential] = [:],
        loadError: Error? = nil,
        deleteError: Error? = nil,
        removeBeforeDeleteError: Bool = false
    ) {
        self.values = values
        self.loadError = loadError
        self.deleteError = deleteError
        self.removeBeforeDeleteError = removeBeforeDeleteError
    }

    var deletedServerIDs: [UUID] {
        lock.withLock { deletedIDs }
    }

    var savedServerIDs: [UUID] {
        lock.withLock { savedIDs }
    }

    func loadCredential(serverID: UUID) throws -> SSHCredential {
        try lock.withLock {
            if let loadError {
                throw loadError
            }
            return values[serverID] ?? SSHCredential()
        }
    }

    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws {
        lock.withLock {
            savedIDs.append(serverID)
            values[serverID] = credential
        }
    }

    func deleteCredential(serverID: UUID) throws {
        try lock.withLock {
            deletedIDs.append(serverID)
            if removeBeforeDeleteError {
                _ = values.removeValue(forKey: serverID)
            }
            if let deleteError {
                throw deleteError
            }
            _ = values.removeValue(forKey: serverID)
        }
    }
}

private final class ThreadCheckingCredentialStore: CredentialStore, @unchecked Sendable {
    private let credential: SSHCredential
    private let lock = NSLock()
    private var loadMainThreadResults: [Bool] = []

    init(credential: SSHCredential) {
        self.credential = credential
    }

    var loadRanOnMainThread: Bool {
        lock.withLock { loadMainThreadResults.contains(true) }
    }

    func loadCredential(serverID: UUID) throws -> SSHCredential {
        lock.withLock {
            loadMainThreadResults.append(Thread.isMainThread)
        }
        return credential
    }

    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws {}

    func deleteCredential(serverID: UUID) throws {}
}

private final class FailingFirstSaveCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: SSHCredential
    private var saveCount = 0

    init(initialCredential: SSHCredential) {
        credential = initialCredential
    }

    func loadCredential(serverID: UUID) throws -> SSHCredential {
        lock.withLock { credential }
    }

    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws {
        try lock.withLock {
            saveCount += 1
            self.credential = credential
            if saveCount == 1 {
                throw TestError.credentialSave
            }
        }
    }

    func deleteCredential(serverID: UUID) throws {
        lock.withLock {
            credential = SSHCredential()
        }
    }
}

private final class BlockingSaveCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private let allowSave = DispatchSemaphore(value: 0)
    private var credential = SSHCredential()
    private var saveStarted = false

    var didStartSave: Bool {
        lock.withLock { saveStarted }
    }

    func releaseSave() {
        allowSave.signal()
    }

    func loadCredential(serverID: UUID) throws -> SSHCredential {
        lock.withLock { credential }
    }

    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws {
        lock.withLock {
            saveStarted = true
        }
        guard allowSave.wait(timeout: .now() + 5) == .success else {
            throw TestError.credentialSave
        }
        lock.withLock {
            self.credential = credential
        }
    }

    func deleteCredential(serverID: UUID) throws {
        lock.withLock {
            credential = SSHCredential()
        }
    }
}

private final class BlockingOpenSSHService: SSHService, @unchecked Sendable {
    private let appServer: CodexAppServerClient
    private let gate = AsyncGate()
    private let lock = NSLock()
    private var openStarted = false

    init(appServer: CodexAppServerClient = CodexAppServerClient(transport: MockCodexLineTransport())) {
        self.appServer = appServer
    }

    var didStartOpen: Bool {
        lock.withLock { openStarted }
    }

    func releaseOpen() {
        Task {
            await gate.open()
        }
    }

    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {}

    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] {
        []
    }

    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String] {
        localPaths.map { "/tmp/mobidex-uploaded/\(URL(fileURLWithPath: $0).lastPathComponent)" }
    }

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        lock.withLock {
            openStarted = true
        }
        await gate.wait()
        return appServer
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else {
            return
        }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private final class ScriptedSSHService: SSHService, @unchecked Sendable {
    private enum AppServerOpenResult {
        case client(CodexAppServerClient)
        case failure(Error)
    }

    private let testConnectionError: Error?
    private let stageDelayNanoseconds: UInt64
    private let lock = NSLock()
    private var appServerOpenResults: [AppServerOpenResult]
    private var discoveredProjectBatches: [[RemoteProject]]
    private var stagedLocalPathBatches: [[String]] = []
    private var openAppServerCalls = 0

    init(
        appServer: CodexAppServerClient,
        testConnectionError: Error? = nil,
        discoveredProjectBatches: [[RemoteProject]] = [[]],
        stageDelayNanoseconds: UInt64 = 0
    ) {
        self.appServerOpenResults = [.client(appServer)]
        self.testConnectionError = testConnectionError
        self.discoveredProjectBatches = discoveredProjectBatches
        self.stageDelayNanoseconds = stageDelayNanoseconds
    }

    init(
        appServers: [CodexAppServerClient],
        testConnectionError: Error? = nil,
        discoveredProjectBatches: [[RemoteProject]] = [[]],
        stageDelayNanoseconds: UInt64 = 0
    ) {
        self.appServerOpenResults = appServers.map(AppServerOpenResult.client)
        self.testConnectionError = testConnectionError
        self.discoveredProjectBatches = discoveredProjectBatches
        self.stageDelayNanoseconds = stageDelayNanoseconds
    }

    init(
        appServerOpenResults: [Result<CodexAppServerClient, Error>],
        testConnectionError: Error? = nil,
        discoveredProjectBatches: [[RemoteProject]] = [[]],
        stageDelayNanoseconds: UInt64 = 0
    ) {
        self.appServerOpenResults = appServerOpenResults.map { result in
            switch result {
            case .success(let appServer):
                .client(appServer)
            case .failure(let error):
                .failure(error)
            }
        }
        self.testConnectionError = testConnectionError
        self.discoveredProjectBatches = discoveredProjectBatches
        self.stageDelayNanoseconds = stageDelayNanoseconds
    }

    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {
        if let testConnectionError {
            throw testConnectionError
        }
    }

    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] {
        lock.withLock {
            guard !discoveredProjectBatches.isEmpty else {
                return []
            }
            if discoveredProjectBatches.count == 1 {
                return discoveredProjectBatches[0]
            }
            return discoveredProjectBatches.removeFirst()
        }
    }

    var stagedLocalPaths: [String] {
        lock.withLock { stagedLocalPathBatches.flatMap { $0 } }
    }

    var openAppServerCallCount: Int {
        lock.withLock { openAppServerCalls }
    }

    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String] {
        lock.withLock {
            stagedLocalPathBatches.append(localPaths)
        }
        if stageDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: stageDelayNanoseconds)
        }
        return localPaths.map { "/tmp/mobidex-uploaded/\(URL(fileURLWithPath: $0).lastPathComponent)" }
    }

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        let result = try lock.withLock {
            openAppServerCalls += 1
            guard !appServerOpenResults.isEmpty else {
                throw TestError.unexpectedSSH
            }
            if appServerOpenResults.count == 1 {
                return appServerOpenResults[0]
            }
            return appServerOpenResults.removeFirst()
        }
        switch result {
        case .client(let appServer):
            try await appServer.initialize()
            return appServer
        case .failure(let error):
            throw error
        }
    }
}

private final class StubSSHService: SSHService, @unchecked Sendable {
    private let discoveredProjects: [RemoteProject]
    private let discoverProjectsError: Error?
    private let testConnectionError: Error?
    private let openAppServerError: Error?
    private let openAppServerDelayNanoseconds: UInt64
    private let lock = NSLock()
    private var openAppServerCalls = 0

    init(
        discoveredProjects: [RemoteProject] = [],
        discoverProjectsError: Error? = nil,
        testConnectionError: Error? = nil,
        openAppServerError: Error? = nil,
        openAppServerDelayNanoseconds: UInt64 = 0
    ) {
        self.discoveredProjects = discoveredProjects
        self.discoverProjectsError = discoverProjectsError
        self.testConnectionError = testConnectionError
        self.openAppServerError = openAppServerError
        self.openAppServerDelayNanoseconds = openAppServerDelayNanoseconds
    }

    var openAppServerCallCount: Int {
        lock.withLock { openAppServerCalls }
    }

    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {
        if let testConnectionError {
            throw testConnectionError
        }
    }

    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] {
        if let discoverProjectsError {
            throw discoverProjectsError
        }
        return discoveredProjects
    }

    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String] {
        localPaths.map { "/tmp/mobidex-uploaded/\(URL(fileURLWithPath: $0).lastPathComponent)" }
    }

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        lock.withLock {
            openAppServerCalls += 1
        }
        if openAppServerDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: openAppServerDelayNanoseconds)
        }
        if let openAppServerError {
            throw openAppServerError
        }
        throw TestError.unexpectedSSH
    }
}

private struct CapturedRequest {
    var id: Int
    var nextCursor: Int
}

@MainActor
private func connectWithSingleOpenSession(in viewModel: AppViewModel, transport: MockCodexLineTransport) async throws {
    let connectTask = Task { await viewModel.connectSelectedServer(syncActiveChatCounts: true) }
    try await connectWithSingleOpenSessionAfterReconnect(in: viewModel, transport: transport)
    await connectTask.value
}

@MainActor
private func connectWithSingleOpenSessionAfterReconnect(in viewModel: AppViewModel, transport: MockCodexLineTransport) async throws {
    var cursor = 0
    let initialize = try await waitForRequest(method: "initialize", in: transport, after: cursor)
    cursor = initialize.nextCursor
    transport.receive(#"{"id":\#(initialize.id),"result":{}}"#)
    let loadedList = try await waitForRequest(method: "thread/loaded/list", in: transport, after: cursor)
    cursor = loadedList.nextCursor
    transport.receive("""
    {"id":\(loadedList.id),"result":{"data":["thread-open"]}}
    """)
    let summary = try await respondToThreadSummary(
        threadID: "thread-open",
        preview: "Open",
        cwd: "/srv/app",
        statusJSON: #"{"type":"active","activeFlags":[]}"#,
        updatedAt: 1_770_000_500,
        in: transport,
        after: cursor
    )
    cursor = summary.nextCursor
    let scopedList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
    transport.receive("""
    {"id":\(scopedList.id),"result":{"data":[],"nextCursor":null}}
    """)
}

@discardableResult
private func respondToThreadSummary(
    threadID: String,
    preview: String,
    cwd: String,
    statusJSON: String = #"{"type":"idle"}"#,
    updatedAt: Int,
    sourceJSON: String? = nil,
    in transport: MockCodexLineTransport,
    after cursor: Int
) async throws -> CapturedRequest {
    let request = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
    let params = try requestParams(for: request, in: transport)
    XCTAssertEqual(params["threadId"] as? String, threadID)
    XCTAssertEqual(params["includeTurns"] as? Bool, false)
    let sourceJSON = sourceJSON.map { ",\"source\":\($0)" } ?? ""
    transport.receive("""
    {"id":\(request.id),"result":{"thread":{"id":"\(threadID)","preview":"\(preview)","cwd":"\(cwd)","status":\(statusJSON),"updatedAt":\(updatedAt),"createdAt":1770000000\(sourceJSON),"turns":[]}}}
    """)
    return request
}

private func waitForRequest(method: String, in transport: MockCodexLineTransport, after cursor: Int) async throws -> CapturedRequest {
    for _ in 0..<200 {
        let lines = transport.sentLinesSnapshot
        for index in cursor..<lines.count {
            guard methodName(lines[index]) == method else {
                continue
            }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[index].utf8)) as? [String: Any])
            return CapturedRequest(id: try XCTUnwrap(object["id"] as? Int), nextCursor: index + 1)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return try XCTUnwrap(nil as CapturedRequest?, "Timed out waiting for \(method).")
}

private func requestParams(for request: CapturedRequest, in transport: MockCodexLineTransport) throws -> [String: Any] {
    let lines = transport.sentLinesSnapshot
    let line = try XCTUnwrap(lines[safe: request.nextCursor - 1])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    return try XCTUnwrap(object["params"] as? [String: Any])
}

private func methodName(_ line: String) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
        return nil
    }
    return object["method"] as? String
}

private func waitForResponse(id: Int, in transport: MockCodexLineTransport, after cursor: Int) async throws -> [String: Any] {
    for _ in 0..<200 {
        let lines = transport.sentLinesSnapshot
        for index in cursor..<lines.count {
            guard let object = try? JSONSerialization.jsonObject(with: Data(lines[index].utf8)) as? [String: Any],
                  object["id"] as? Int == id,
                  object["result"] != nil else {
                continue
            }
            return object
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return try XCTUnwrap(nil as [String: Any]?, "Timed out waiting for response \(id).")
}

@MainActor
private func waitForThreadIDs(_ expected: [String], in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.threads.map(\.id) == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for thread IDs \(expected).")
}

@MainActor
private func waitForContextUsageFraction(_ expected: Double, in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if let fraction = viewModel.contextUsageFraction, abs(fraction - expected) < 0.0001 {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for context usage \(expected).")
}

@MainActor
private func waitForConnectionState(_ expected: ServerConnectionState, in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.connectionState == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for connection state \(expected).")
}

@MainActor
private func waitForReconnectStatus(_ expected: AppServerReconnectStatus, in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.appServerReconnectStatus == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for reconnect status \(expected). Last: \(String(describing: viewModel.appServerReconnectStatus))")
}

@MainActor
private func waitForStatusMessage(_ expected: String, in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.statusMessage == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for status message \(expected). Last: \(viewModel.statusMessage ?? "<nil>")")
}

private func waitForCredentialSaveStart(_ store: BlockingSaveCredentialStore) async throws {
    for _ in 0..<200 {
        if store.didStartSave {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for credential save to start.")
}

private func waitForOpenAppServerStart(_ service: BlockingOpenSSHService) async throws {
    for _ in 0..<200 {
        if service.didStartOpen {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for app-server open to start.")
}

@MainActor
private func waitForSelectedThreadID(_ expected: String, in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.selectedThreadID == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for selected thread \(expected).")
}

@MainActor
private func waitForSelectedThreadStatus(_ expected: String, in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.selectedThread?.status.sessionLabel == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for selected thread status \(expected).")
}

@MainActor
private func waitForPendingApproval(method: String, in viewModel: AppViewModel) async throws -> PendingApproval {
    for _ in 0..<200 {
        if let approval = viewModel.pendingApprovals.first(where: { $0.method == method }) {
            return approval
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return try XCTUnwrap(nil as PendingApproval?, "Timed out waiting for pending approval \(method).")
}

@MainActor
private func waitForNoPendingApprovals(in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.pendingApprovals.isEmpty {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for pending approvals to clear.")
}

@MainActor
private func waitForCannotSend(in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if !viewModel.canSendMessage {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for composer send operation to start.")
}

@MainActor
private func waitForCanInterrupt(in viewModel: AppViewModel) async throws {
    for _ in 0..<200 {
        if viewModel.canInterruptActiveTurn {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for active turn state.")
}

@MainActor
private func waitForConversationSection(
    kind: ConversationSection.Kind,
    containing text: String,
    in viewModel: AppViewModel
) async throws {
    for _ in 0..<200 {
        if viewModel.conversationSections.contains(where: {
            $0.kind == kind && ($0.body.contains(text) || $0.title.contains(text) || ($0.detail?.contains(text) == true))
        }) {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for \(kind) conversation section containing \(text).")
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
