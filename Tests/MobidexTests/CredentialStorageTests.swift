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
        try credentials.saveCredential(SSHCredential(password: "secret", privateKeyPEM: nil, privateKeyPassphrase: nil), serverID: server.id)

        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertEqual(try credentials.loadCredential(serverID: server.id).password, "secret")
    }

    func testServerRecordBuildsQuotedAppServerCommand() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            codexPath: "/home/user/bin/codex'special",
            authMethod: .password
        )

        XCTAssertEqual(server.appServerCommand, "'/home/user/bin/codex'\"'\"'special' app-server --listen stdio://")
    }

    func testServerRecordAppServerCommandAllowsRemoteHomeRelativeCodexPath() {
        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            codexPath: "~/.bun/bin/codex",
            authMethod: .password
        )

        XCTAssertEqual(server.appServerCommand, "\"${HOME}\"/'.bun/bin/codex' app-server --listen stdio://")
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
        let v2StoragePayload = Data("""
        [{
          "id": "00000000-0000-0000-0000-000000000003",
          "displayName": "Old V2 Server",
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
        defaults.set(v2StoragePayload, forKey: "mobidex.servers.v2")

        let repository = UserDefaultsServerRepository(defaults: defaults)

        XCTAssertEqual(try repository.loadServers(), [])

        let server = ServerRecord(
            displayName: "Server",
            host: "host",
            username: "user",
            authMethod: .password,
            projects: [ProjectRecord(path: "/srv/app", discovered: true, threadCount: 2)]
        )
        try repository.saveServers([server])

        XCTAssertEqual(defaults.data(forKey: "mobidex.servers.v1"), v1StoragePayload)
        XCTAssertEqual(defaults.data(forKey: "mobidex.servers.v2"), v2StoragePayload)
        XCTAssertEqual(try repository.loadServers(), [server])
        XCTAssertNotNil(defaults.data(forKey: "mobidex.servers.v3"))
    }
}
