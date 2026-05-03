import Foundation

enum ServerAuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password: "Password"
        case .privateKey: "Private Key"
        }
    }
}

struct ServerRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var displayName: String
    var host: String
    var port: Int
    var username: String
    var codexPath: String
    var authMethod: ServerAuthMethod
    var projects: [ProjectRecord]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        port: Int = 22,
        username: String,
        codexPath: String = "codex",
        authMethod: ServerAuthMethod,
        projects: [ProjectRecord] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        self.codexPath = codexPath.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "codex"
        self.authMethod = authMethod
        self.projects = projects
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var endpointLabel: String {
        "\(username)@\(host):\(port)"
    }

    var appServerCommand: String {
        "\(codexPath.shellQuotedExecutablePath) app-server --listen stdio://"
    }
}

struct ProjectRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var path: String
    var displayName: String
    var discovered: Bool
    var threadCount: Int
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        path: String,
        displayName: String? = nil,
        discovered: Bool = false,
        threadCount: Int = 0,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent.nonEmpty ?? path
        self.discovered = discovered
        self.threadCount = threadCount
        self.lastSeenAt = lastSeenAt
    }
}

struct SSHCredential: Equatable {
    var password: String?
    var privateKeyPEM: String?
    var privateKeyPassphrase: String?
}

enum ServerConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed(let message): message
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    var shellQuotedExecutablePath: String {
        if self == "~" {
            return "\"${HOME}\""
        }
        if hasPrefix("~/") {
            return "\"${HOME}\"/\(String(dropFirst(2)).shellQuoted)"
        }
        return shellQuoted
    }
}
