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
            SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil, appServerAuthToken: "token"),
            serverID: server.id
        )

        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id).password, "secret")
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id).appServerAuthToken, "token")
    }

    func testServerRecordStoresWebSocketEndpointWithoutAuthToken() throws {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            appServerWebSocketURL: " ws://host:3030 ",
            authMethod: .password
        )

        XCTAssertEqual(server.appServerWebSocketURL, "ws://host:3030")
        XCTAssertEqual(server.appServerWebSocketEndpoint?.absoluteString, "ws://host:3030")

        let data = try JSONEncoder().encode(server)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(ServerRecord.self, from: data)
        XCTAssertEqual(decoded.appServerWebSocketURL, "ws://host:3030")
        XCTAssertFalse(encoded.contains("token"))
    }

    func testServerRecordRejectsNonWebSocketEndpoint() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            appServerWebSocketURL: "not-a-websocket-endpoint",
            authMethod: .password
        )

        XCTAssertEqual(server.appServerWebSocketURL, "not-a-websocket-endpoint")
        XCTAssertNil(server.appServerWebSocketEndpoint)

        let tlsServer = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            appServerWebSocketURL: "wss://host:3030",
            authMethod: .password
        )
        XCTAssertNil(tlsServer.appServerWebSocketEndpoint)
    }

    func testServerRecordBuildsQuotedAppServerCommand() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            codexPath: "/home/user/bin/codex'special",
            authMethod: .password
        )

        XCTAssertEqual(
            server.appServerCommand,
            "export PATH=\"$HOME/.bun/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"; '/home/user/bin/codex'\"'\"'special' app-server --listen stdio://"
        )
    }

    func testServerRecordDefaultAppServerCommandResolvesCodexExecutable() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            authMethod: .password
        )

        XCTAssertTrue(server.appServerCommand.contains("command -v codex"))
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
        XCTAssertTrue(server.appServerProxyCommand.contains("socket_root=\"${CODEX_HOME:-$HOME/.codex}\""))
        XCTAssertTrue(server.appServerProxyCommand.contains("app-server-control/app-server-control.sock"))
        XCTAssertTrue(server.appServerProxyCommand.contains("app-server --listen \"unix://$socket\""))
        XCTAssertTrue(server.appServerProxyCommand.contains("app-server proxy --sock \"$socket\""))
        XCTAssertTrue(server.appServerProxyCommand.contains("socket_probe_attempted=0"))
        XCTAssertTrue(server.appServerProxyCommand.contains("[ \"$socket_probe_attempted\" -eq 1 ]"))
        XCTAssertTrue(server.appServerProxyCommand.contains("python3 -c"))
        XCTAssertTrue(server.appServerProxyCommand.contains("ruby -rsocket"))
        XCTAssertTrue(server.appServerProxyCommand.contains("perl -MIO::Socket::UNIX"))
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
            "export PATH=\"$HOME/.bun/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"; \"${HOME}\"/'.bun/bin/codex' app-server --listen stdio://"
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
        XCTAssertTrue(server.appServerProxyCommand.contains("\"$codex_bin\" app-server --listen \"unix://$socket\""))
        XCTAssertTrue(server.appServerProxyCommand.contains("exec \"$codex_bin\" app-server proxy --sock \"$socket\""))
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
