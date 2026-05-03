import XCTest
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
    func testStartNewThreadRequiresAppServerConnection() async throws {
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
        await viewModel.startNewThread()

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
    func testConnectMapsClosedChannelToAppServerMessage() async throws {
        let server = ServerRecord(displayName: "Build Box", host: "build.example.com", username: "mazdak", authMethod: .password)
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = SpyCredentialStore(values: [server.id: SSHCredential(password: "secret")])
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: StubSSHService(openAppServerError: SSHServiceError.appServerClosed("codex app-server --listen stdio://"))
        )

        await viewModel.connectSelectedServer()

        XCTAssertEqual(
            viewModel.statusMessage,
            "SSH connected, but the server closed the app-server session while starting `codex app-server --listen stdio://`. Check the Codex path and that `codex app-server --listen stdio://` can run on the server."
        )
    }

    func testProjectRecordDecodesMissingFavoriteAndSessionPathsWithDefaults() throws {
        let data = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "path": "/srv/app",
          "displayName": "app",
          "discovered": true,
          "threadCount": 2,
          "lastSeenAt": 1770000300
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

    func testProjectSectionsSeparateFavoritesFromActiveDiscoveredProjects() throws {
        let favoriteWithoutChats = ProjectRecord(path: "/srv/favorite", discovered: false, threadCount: 0, isFavorite: true)
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, threadCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive", discovered: true, threadCount: 0)

        let sections = ProjectSections(
            projects: [inactiveDiscovered, activeDiscovered, favoriteWithoutChats],
            searchText: "",
            showInactiveDiscoveredProjects: false
        )

        XCTAssertEqual(sections.favorites.map(\.path), ["/srv/favorite"])
        XCTAssertEqual(sections.discovered.map(\.path), ["/srv/active"])
        XCTAssertTrue(sections.showFilter)
        XCTAssertEqual(sections.discoveredTitle, "Discovered")
    }

    func testProjectSectionsCanIncludeInactiveDiscoveredProjects() throws {
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, threadCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive", discovered: true, threadCount: 0)

        let sections = ProjectSections(
            projects: [inactiveDiscovered, activeDiscovered],
            searchText: "",
            showInactiveDiscoveredProjects: true
        )

        XCTAssertEqual(sections.discovered.map(\.path), ["/srv/active", "/srv/inactive"])
        XCTAssertEqual(sections.discoveredTitle, "Discovered")
    }

    func testProjectSectionsSearchFindsInactiveDiscoveredProjects() throws {
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, threadCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive-match", displayName: "inactive-match", discovered: true, threadCount: 0)

        let sections = ProjectSections(
            projects: [activeDiscovered, inactiveDiscovered],
            searchText: "match",
            showInactiveDiscoveredProjects: false
        )

        XCTAssertTrue(sections.favorites.isEmpty)
        XCTAssertEqual(sections.discovered.map(\.path), ["/srv/inactive-match"])
        XCTAssertEqual(sections.discoveredTitle, "Discovered")
    }

    func testProjectSectionsKeepManualProjectsVisibleAndSearchable() throws {
        let manualProject = ProjectRecord(path: "/srv/manual", discovered: false, threadCount: 0)
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, threadCount: 2)

        let defaultSections = ProjectSections(
            projects: [manualProject, activeDiscovered],
            searchText: "",
            showInactiveDiscoveredProjects: false
        )
        XCTAssertEqual(defaultSections.added.map(\.path), ["/srv/manual"])

        let searchSections = ProjectSections(
            projects: [manualProject, activeDiscovered],
            searchText: "manual",
            showInactiveDiscoveredProjects: false
        )
        XCTAssertEqual(searchSections.added.map(\.path), ["/srv/manual"])
        XCTAssertTrue(searchSections.discovered.isEmpty)
    }

    @MainActor
    func testStartNewThreadCreatesAndSelectsThreadWhenConnected() async throws {
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
        let newThreadTask = Task { await viewModel.startNewThread() }
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
        await newThreadTask.value

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
        XCTAssertFalse(viewModel.isSelectedThreadLoading)

        let thread = try XCTUnwrap(viewModel.threads.first)
        let openTask = Task { await viewModel.openThread(thread) }
        let read = try await waitForRequest(method: "thread/read", in: transport, after: cursor)
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
                    [RemoteProject(path: "/srv/old", threadCount: 1, lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300))],
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
    func testStartNewThreadIgnoresSecondTapWhileBusy() async throws {
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
                    [RemoteProject(path: "/srv/old", threadCount: 1, lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300))],
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
        let firstTap = Task { await viewModel.startNewThread() }
        let startThread = try await waitForRequest(method: "thread/start", in: transport, after: cursor)
        await viewModel.startNewThread()
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
    func testRefreshProjectsStoresDiscoveredThreadCounts() async throws {
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
                    threadCount: 3,
                    lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300)
                )
            ])
        )

        await viewModel.refreshProjects()

        let project = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(project.path, "/srv/app")
        XCTAssertEqual(project.sessionPaths, ["/srv/app"])
        XCTAssertTrue(project.discovered)
        XCTAssertEqual(project.threadCount, 3)
        XCTAssertEqual(project.lastSeenAt, Date(timeIntervalSince1970: 1_770_000_300))
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
                    threadCount: 5,
                    lastSeenAt: Date(timeIntervalSince1970: 1_770_000_500)
                )
            ])
        )

        await viewModel.refreshProjects()

        let project = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(project.path, "/srv/fullstack")
        XCTAssertEqual(project.sessionPaths, ["/srv/fullstack", "/srv/.codex/worktrees/a/fullstack"])
        XCTAssertEqual(project.threadCount, 5)
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
                RemoteProject(path: "/srv/app", threadCount: 4, lastSeenAt: Date(timeIntervalSince1970: 1_770_000_400))
            ])
        )

        XCTAssertTrue(viewModel.setProjectFavorite(project, isFavorite: true))
        var savedProject = try XCTUnwrap(try repository.loadServers().first?.projects.first)
        XCTAssertTrue(savedProject.isFavorite)

        await viewModel.refreshProjects()

        savedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertTrue(savedProject.isFavorite)
        XCTAssertEqual(savedProject.threadCount, 4)
    }

    @MainActor
    func testRefreshProjectsRemovesStaleDiscoveredProjects() async throws {
        let project = ProjectRecord(
            path: "/srv/app",
            displayName: "app",
            discovered: true,
            threadCount: 3,
            lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300)
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
        let project = ProjectRecord(path: "/srv/old", discovered: true, threadCount: 1)
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
                    [RemoteProject(path: "/srv/old", threadCount: 1, lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300))],
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
        let activeList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        let params = try requestParams(for: activeList, in: transport)
        XCTAssertNil(params["cwd"])
        XCTAssertEqual(params["archived"] as? Bool, false)
        transport.receive("""
        {"id":\(activeList.id),"result":{"data":[],"nextCursor":null}}
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
    func testConnectedRefreshReplacesDiscoveryCountsWithActiveThreadCounts() async throws {
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
            RemoteProject(path: "/srv/app", threadCount: 37, lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300))
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
        XCTAssertEqual(viewModel.selectedServer?.projects.first?.threadCount, 37)

        cursor = transport.sentLinesSnapshot.count
        let refreshTask = Task { await viewModel.refreshProjects() }
        let activeList = try await waitForRequest(method: "thread/list", in: transport, after: cursor)
        params = try requestParams(for: activeList, in: transport)
        XCTAssertNil(params["cwd"])
        XCTAssertEqual(params["archived"] as? Bool, false)
        transport.receive("""
        {"id":\(activeList.id),"result":{"data":[
          {"id":"thread-active-1","preview":"One","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000400,"createdAt":1770000000,"turns":[]},
          {"id":"thread-active-2","preview":"Two","cwd":"/srv/app","status":{"type":"idle"},"updatedAt":1770000500,"createdAt":1770000000,"turns":[]}
        ],"nextCursor":null}}
        """)
        await refreshTask.value

        let refreshedProject = try XCTUnwrap(viewModel.selectedServer?.projects.first)
        XCTAssertEqual(refreshedProject.threadCount, 2)
        XCTAssertEqual(refreshedProject.lastSeenAt, Date(timeIntervalSince1970: 1_770_000_500))
        await viewModel.disconnect()
    }

    @MainActor
    func testRefreshProjectsKeepsFavoriteStaleDiscoveredProject() async throws {
        let project = ProjectRecord(
            path: "/srv/app",
            displayName: "app",
            discovered: true,
            threadCount: 3,
            lastSeenAt: Date(timeIntervalSince1970: 1_770_000_300),
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
        XCTAssertEqual(refreshed.threadCount, 0)
        XCTAssertNil(refreshed.lastSeenAt)
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

        viewModel.selectProject(projectTwo.id)
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
    func testComposerStartContinuesWhenThreadStartedEventSelectsNewThreadFirst() async throws {
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
        var params = try requestParams(for: startTurn, in: transport)
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
        transport.receive("""
        {"method":"item/agentMessage/delta","params":{
          "threadId":"thread-new",
          "itemId":"item-agent",
          "delta":"Streaming"
        }}
        """)
        try await waitForConversationSection(kind: .assistant, containing: "Streaming", in: viewModel)

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

        let steerTask = Task { await viewModel.sendComposerText("Keep going") }
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
    func testLoadThreadsPrioritizesActiveSessions() async throws {
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
          "id":"active-server-first",
          "preview":"Active server first",
          "cwd":"/srv/app",
          "status":{"type":"active","activeFlags":[]},
          "updatedAt":1770000200,
          "createdAt":1770000002,
          "turns":[]
        }}}
        """)
        await connectTask.value

        let activeFirstOrder = ["active-server-first", "active-server-second", "idle-server-first", "idle-server-second"]
        XCTAssertEqual(viewModel.threads.map(\.id), activeFirstOrder)
        XCTAssertEqual(viewModel.selectedThreadID, "active-server-first")

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
        try await waitForThreadIDs(activeFirstOrder, in: viewModel)

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
    case credentialDelete
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

private final class ScriptedSSHService: SSHService, @unchecked Sendable {
    private let appServer: CodexAppServerClient
    private let lock = NSLock()
    private var discoveredProjectBatches: [[RemoteProject]]

    init(appServer: CodexAppServerClient, discoveredProjectBatches: [[RemoteProject]] = [[]]) {
        self.appServer = appServer
        self.discoveredProjectBatches = discoveredProjectBatches
    }

    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {}

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

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        try await appServer.initialize()
        return appServer
    }
}

private final class StubSSHService: SSHService, @unchecked Sendable {
    private let discoveredProjects: [RemoteProject]
    private let testConnectionError: Error?
    private let openAppServerError: Error?

    init(
        discoveredProjects: [RemoteProject] = [],
        testConnectionError: Error? = nil,
        openAppServerError: Error? = nil
    ) {
        self.discoveredProjects = discoveredProjects
        self.testConnectionError = testConnectionError
        self.openAppServerError = openAppServerError
    }

    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {
        if let testConnectionError {
            throw testConnectionError
        }
    }

    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] {
        discoveredProjects
    }

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
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
