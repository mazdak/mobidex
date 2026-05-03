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
    var sessionPaths: [String]
    var displayName: String
    var discovered: Bool
    var threadCount: Int
    var lastSeenAt: Date?
    var isFavorite: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case sessionPaths
        case displayName
        case discovered
        case threadCount
        case lastSeenAt
        case isFavorite
    }

    init(
        id: UUID = UUID(),
        path: String,
        sessionPaths: [String]? = nil,
        displayName: String? = nil,
        discovered: Bool = false,
        threadCount: Int = 0,
        lastSeenAt: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.path = path
        self.sessionPaths = ProjectRecord.normalizedSessionPaths(sessionPaths ?? [path], primaryPath: path)
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent.nonEmpty ?? path
        self.discovered = discovered
        self.threadCount = threadCount
        self.lastSeenAt = lastSeenAt
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        sessionPaths = ProjectRecord.normalizedSessionPaths(
            try container.decodeIfPresent([String].self, forKey: .sessionPaths) ?? [path],
            primaryPath: path
        )
        displayName = try container.decode(String.self, forKey: .displayName)
        discovered = try container.decode(Bool.self, forKey: .discovered)
        threadCount = try container.decode(Int.self, forKey: .threadCount)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    static func normalizedSessionPaths(_ paths: [String], primaryPath: String) -> [String] {
        var seen = Set<String>()
        return ([primaryPath] + paths).filter { path in
            guard !path.isEmpty, !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
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
        case .disconnected: "App-server disconnected"
        case .connecting: "Connecting app-server"
        case .connected: "App-server connected"
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
