import XCTest
@testable import Mobidex

final class CredentialStorageTests: XCTestCase {
    func testServerRecordDoesNotEncodeCredentialSecrets() throws {
        let server = ServerRecord(
            displayName: "Build Box",
            host: "build.example.com",
            username: "mazdak",
            authMethod: .privateKey
        )

        let data = try JSONEncoder().encode(server)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(encoded.contains("password"))
        XCTAssertFalse(encoded.contains("BEGIN OPENSSH PRIVATE KEY"))
        XCTAssertTrue(encoded.contains("build.example.com"))
    }

    func testCredentialStoreIsSeparateFromServerRepository() throws {
        let server = ServerRecord(displayName: "Server", host: "host", username: "user", authMethod: .password)
        let repository = InMemoryServerRepository()
        let credentials = InMemoryCredentialStore()

        try repository.saveServers([server])
        try credentials.saveCredential(
            SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil),
            serverID: server.id
        )

        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id).password, "secret")
    }

    func testHostKeyPinStoreMigratesLegacyEndpointPin() {
        let serverID = UUID()
        let fingerprint = "SHA256:same-machine"
        defer { SSHHostKeyPinStore.clear(serverID: serverID, legacyHost: "192.168.1.239", legacyPort: 22) }
        SSHHostKeyPinStore.clear(serverID: serverID, legacyHost: "192.168.1.239", legacyPort: 22)
        UserDefaults.standard.set(fingerprint, forKey: legacyHostKeyPinKey(serverID: serverID, host: "192.168.1.239", port: 22))

        XCTAssertEqual(
            SSHHostKeyPinStore.fingerprint(serverID: serverID, legacyHost: "192.168.1.239", legacyPort: 22),
            fingerprint
        )
        XCTAssertEqual(
            SSHHostKeyPinStore.fingerprint(serverID: serverID, legacyHost: "them4maxmacbookpro.tail866988.ts.net", legacyPort: 22),
            fingerprint
        )
    }

    @MainActor
    func testSavingEditedServerMigratesLegacyEndpointHostKeyPin() async throws {
        let server = ServerRecord(displayName: "MacBook", host: "192.168.1.239", username: "mazdak", authMethod: .password)
        let fingerprint = "SHA256:same-machine"
        let repository = InMemoryServerRepository(servers: [server])
        let credentials = InMemoryCredentialStore()
        try credentials.saveCredential(SSHCredential(password: "secret"), serverID: server.id)
        defer { SSHHostKeyPinStore.clear(serverID: server.id, legacyHost: server.host, legacyPort: server.port) }
        SSHHostKeyPinStore.clear(serverID: server.id, legacyHost: server.host, legacyPort: server.port)
        UserDefaults.standard.set(fingerprint, forKey: legacyHostKeyPinKey(serverID: server.id, host: server.host, port: server.port))
        var edited = server
        edited.host = "them4maxmacbookpro.tail866988.ts.net"
        let viewModel = AppViewModel(
            repository: repository,
            credentialStore: credentials,
            sshService: CredentialStorageStubSSHService()
        )

        let saved = await viewModel.saveServer(edited, credential: SSHCredential(password: "secret"))

        XCTAssertTrue(saved)
        XCTAssertEqual(
            SSHHostKeyPinStore.fingerprint(serverID: server.id, legacyHost: edited.host, legacyPort: edited.port),
            fingerprint
        )
    }

    func testServerRecordBuildsQuotedAppServerCommand() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            codexPath: "/home/user/bin/codex'special",
            targetShellRCFile: "/home/user/.config/zsh/env file",
            authMethod: .password
        )

        XCTAssertEqual(
            server.appServerCommand,
            "mobidex_shell_rc='/home/user/.config/zsh/env file'; if [ -f \"$mobidex_shell_rc\" ]; then . \"$mobidex_shell_rc\" 1>&2; fi; export PATH=\"$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"; '/home/user/bin/codex'\"'\"'special' app-server --listen stdio://"
        )
    }

    func testServerRecordDefaultsAndDecodesTargetShellRCFile() throws {
        let server = ServerRecord(displayName: "Server", host: "host", username: "user", authMethod: .password)
        XCTAssertEqual(server.targetShellRCFile, "$HOME/.zshrc")
        XCTAssertTrue(server.appServerProxyCommand.hasPrefix("mobidex_shell_rc=\"${HOME}\"/'.zshrc'; if [ -f \"$mobidex_shell_rc\" ]; then . \"$mobidex_shell_rc\" 1>&2; fi;"))

        let legacyPayload = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "displayName": "Legacy",
          "host": "host",
          "port": 22,
          "username": "user",
          "codexPath": "codex",
          "appServerWebSocketURL": "ws://legacy:3030",
          "authMethod": "password",
          "projects": [],
          "createdAt": 1770000000,
          "updatedAt": 1770000000
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(ServerRecord.self, from: legacyPayload)
        XCTAssertEqual(decoded.targetShellRCFile, "$HOME/.zshrc")
    }

    func testServerRecordDefaultAppServerCommandResolvesCodexExecutable() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            authMethod: .password
        )

        XCTAssertTrue(server.appServerCommand.contains("command -v codex"))
        XCTAssertTrue(server.appServerCommand.contains("mobidex_shell_rc=\"${HOME}\"/'.zshrc'"))
        XCTAssertTrue(server.appServerCommand.contains("$HOME/.bun/bin/codex"))
        XCTAssertTrue(server.appServerCommand.contains("/opt/homebrew/opt/node@22/bin"))
        XCTAssertTrue(server.appServerCommand.contains("zsh bash"))
        XCTAssertTrue(server.appServerCommand.contains("app-server --listen stdio://"))
        XCTAssertTrue(server.appServerCommand.contains("Set Codex Binary Path"))
    }

    func testServerRecordDefaultProxyCommandUsesOfficialControlSocket() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            authMethod: .password
        )

        XCTAssertTrue(server.appServerProxyCommand.contains("command -v codex"))
        XCTAssertTrue(server.appServerProxyCommand.contains("mobidex_shell_rc=\"${HOME}\"/'.zshrc'"))
        XCTAssertTrue(server.appServerProxyCommand.contains("app-server proxy --help"))
        XCTAssertTrue(server.appServerProxyCommand.contains("default_socket=\"${CODEX_HOME:-$HOME/.codex}/app-server-control/app-server-control.sock\""))
        XCTAssertTrue(server.appServerProxyCommand.contains("app-server-control/app-server-control.sock"))
        XCTAssertTrue(server.appServerProxyCommand.contains("mkdir -p \"$socket_dir\""))
        XCTAssertTrue(server.appServerProxyCommand.contains("app-server --listen unix://"))
        XCTAssertTrue(server.appServerProxyCommand.contains("exec \"$codex_bin\" app-server proxy"))
        XCTAssertFalse(server.appServerProxyCommand.contains("proxy --sock"))
        XCTAssertFalse(server.appServerProxyCommand.contains("unix://$socket"))
        XCTAssertFalse(server.appServerProxyCommand.contains("socket_probe_attempted"))
        XCTAssertFalse(server.appServerProxyCommand.contains("stdio://"))
    }

    func testServerRecordAppServerCommandAllowsRemoteHomeRelativeCodexPath() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            codexPath: "~/.bun/bin/codex",
            authMethod: .password
        )

        XCTAssertEqual(
            server.appServerCommand,
            "mobidex_shell_rc=\"${HOME}\"/'.zshrc'; if [ -f \"$mobidex_shell_rc\" ]; then . \"$mobidex_shell_rc\" 1>&2; fi; export PATH=\"$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"; \"${HOME}\"/'.bun/bin/codex' app-server --listen stdio://"
        )
    }

    func testServerRecordProxyCommandAllowsRemoteHomeRelativeCodexPath() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            codexPath: "~/.bun/bin/codex",
            authMethod: .password
        )

        XCTAssertTrue(server.appServerProxyCommand.contains("codex_bin=\"${HOME}\"/'.bun/bin/codex'"))
        XCTAssertTrue(server.appServerProxyCommand.contains("\"$codex_bin\" app-server --listen unix://"))
        XCTAssertTrue(server.appServerProxyCommand.contains("exec \"$codex_bin\" app-server proxy"))
        XCTAssertFalse(server.appServerProxyCommand.contains("proxy --sock"))
    }

    func testUserDefaultsRepositoryUsesCurrentStorageKey() throws {
        let suiteName = "mobidex.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let v1StoragePayload = Data("""
        [{
          "id": "00000000-0000-0000-0000-000000000001",
          "displayName": "Old Server",
          "host": "old.example.com",
          "port": 22,
          "username": "user",
          "authMethod": "password",
          "projects": [{
            "id": "00000000-0000-0000-0000-000000000002",
            "path": "/srv/old",
            "displayName": "old",
            "discovered": true,
            "lastSeenAt": 1770000300
          }],
          "createdAt": 1770000000,
          "updatedAt": 1770000000
        }]
        """.utf8)
        let v3StoragePayload = Data("""
        [{
          "id": "00000000-0000-0000-0000-000000000003",
          "displayName": "Old V3 Server",
          "host": "old-v2.example.com",
          "port": 22,
          "username": "user",
          "authMethod": "password",
          "projects": [{
            "id": "00000000-0000-0000-0000-000000000004",
            "path": "/srv/old-v2",
            "displayName": "old-v2",
            "discovered": true,
            "threadCount": 2,
            "lastSeenAt": 1770000300
          }],
          "createdAt": 1770000000,
          "updatedAt": 1770000000
        }]
        """.utf8)
        defaults.set(v1StoragePayload, forKey: "mobidex.servers.v1")
        defaults.set(v3StoragePayload, forKey: "mobidex.servers.v3")

        let repository = UserDefaultsServerRepository(defaults: defaults)

        XCTAssertEqual(try repository.loadServers(), [])

        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            authMethod: .password,
            projects: [ProjectRecord(path: "/srv/app", discovered: true, discoveredSessionCount: 2)]
        )
        try repository.saveServers([server])

        XCTAssertEqual(defaults.data(forKey: "mobidex.servers.v1"), v1StoragePayload)
        XCTAssertEqual(defaults.data(forKey: "mobidex.servers.v3"), v3StoragePayload)
        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertNotNil(defaults.data(forKey: "mobidex.servers.v4"))
    }
}

private func legacyHostKeyPinKey(serverID: UUID, host: String, port: Int) -> String {
    "mobidex.sshHostKey.\(serverID.uuidString).\(host).\(port)"
}

private struct CredentialStorageStubSSHService: SSHService {
    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {}
    func diagnoseConnection(server: ServerRecord, credential: SSHCredential) async -> SSHDiagnosticReport {
        SSHDiagnosticReport(
            host: server.endpointLabel,
            resolvedAddresses: [],
            tcpResults: [],
            hostKeyFingerprint: nil,
            pinnedHostKeyFingerprint: nil,
            authMethod: server.authMethod.label.lowercased(),
            failureStage: nil,
            rawUnderlyingErrorType: nil,
            rawUnderlyingError: nil,
            remoteCommandResult: nil,
            appServerResult: nil
        )
    }
    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] { [] }
    func listDirectories(path: String, server: ServerRecord, credential: SSHCredential) async throws -> RemoteDirectoryListing {
        RemoteDirectoryListing(path: path, entries: [])
    }
    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String] { [] }
    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        throw SSHServiceError.authenticationFailed
    }
}
