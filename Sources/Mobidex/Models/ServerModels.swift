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
    var targetShellRCFile: String
    var authMethod: ServerAuthMethod
    var projects: [ProjectRecord]
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case host
        case port
        case username
        case codexPath
        case targetShellRCFile
        case authMethod
        case projects
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        port: Int = 22,
        username: String,
        codexPath: String = SharedKMPBridge.defaultCodexPath,
        targetShellRCFile: String = SharedKMPBridge.defaultTargetShellRCFile,
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
        let launchConfig = SharedKMPBridge.normalizedRemoteLaunchConfig(
            codexPath: codexPath,
            targetShellRCFile: targetShellRCFile
        )
        self.codexPath = launchConfig.codexPath
        self.targetShellRCFile = launchConfig.targetShellRCFile
        self.authMethod = authMethod
        self.projects = projects
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        let launchConfig = SharedKMPBridge.normalizedRemoteLaunchConfig(
            codexPath: try container.decodeIfPresent(String.self, forKey: .codexPath),
            targetShellRCFile: try container.decodeIfPresent(String.self, forKey: .targetShellRCFile)
        )
        codexPath = launchConfig.codexPath
        targetShellRCFile = launchConfig.targetShellRCFile
        authMethod = try container.decode(ServerAuthMethod.self, forKey: .authMethod)
        projects = try container.decodeIfPresent([ProjectRecord].self, forKey: .projects) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var endpointLabel: String {
        "\(username)@\(host):\(port)"
    }

    var appServerCommand: String {
        SharedKMPBridge.appServerCommand(codexPath: codexPath, targetShellRCFile: targetShellRCFile)
    }

    var appServerProxyCommand: String {
        SharedKMPBridge.appServerProxyCommand(codexPath: codexPath, targetShellRCFile: targetShellRCFile)
    }
}

struct ProjectRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var path: String
    var sessionPaths: [String]
    var displayName: String
    var discovered: Bool
    var discoveredSessionCount: Int
    var archivedSessionCount: Int
    var activeChatCount: Int
    var lastDiscoveredAt: Date?
    var lastActiveChatAt: Date?
    var isAdded: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case sessionPaths
        case displayName
        case discovered
        case discoveredSessionCount
        case archivedSessionCount
        case activeChatCount
        case lastDiscoveredAt
        case lastActiveChatAt
        case isAdded
    }

    init(
        id: UUID = UUID(),
        path: String,
        sessionPaths: [String]? = nil,
        displayName: String? = nil,
        discovered: Bool = false,
        discoveredSessionCount: Int = 0,
        archivedSessionCount: Int = 0,
        activeChatCount: Int = 0,
        lastDiscoveredAt: Date? = nil,
        lastActiveChatAt: Date? = nil,
        isAdded: Bool = false
    ) {
        self.id = id
        self.path = path
        self.sessionPaths = ProjectRecord.normalizedSessionPaths(sessionPaths ?? [path], primaryPath: path)
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent.nonEmpty ?? path
        self.discovered = discovered
        self.discoveredSessionCount = discoveredSessionCount
        self.archivedSessionCount = archivedSessionCount
        self.activeChatCount = activeChatCount
        self.lastDiscoveredAt = lastDiscoveredAt
        self.lastActiveChatAt = lastActiveChatAt
        self.isAdded = isAdded
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
        discoveredSessionCount = try container.decode(Int.self, forKey: .discoveredSessionCount)
        archivedSessionCount = try container.decodeIfPresent(Int.self, forKey: .archivedSessionCount) ?? 0
        activeChatCount = try container.decode(Int.self, forKey: .activeChatCount)
        lastDiscoveredAt = try container.decodeIfPresent(Date.self, forKey: .lastDiscoveredAt)
        lastActiveChatAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveChatAt)
        isAdded = try container.decodeIfPresent(Bool.self, forKey: .isAdded) ?? false
    }

    static func normalizedSessionPaths(_ paths: [String], primaryPath: String) -> [String] {
        SharedKMPBridge.normalizedSessionPaths(paths, primaryPath: primaryPath)
    }

    var macOSPrivacyWarning: String? {
        Self.macOSPrivacyWarning(for: [path] + sessionPaths)
    }

    static func macOSPrivacyWarning(for paths: [String]) -> String? {
        paths.contains(where: isLikelyMacOSPrivacyProtectedPath)
            ? "macOS may block SSH access to this protected location. Move it outside protected folders or grant Full Disk Access to the SSH/Remote Login service."
            : nil
    }

    private static func isLikelyMacOSPrivacyProtectedPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if components.first == "Volumes" {
            return true
        }
        guard components.count >= 3, components[0] == "Users" else {
            return false
        }
        if ["Desktop", "Documents", "Downloads"].contains(String(components[2])) {
            return true
        }
        return components.count >= 4 &&
            components[2] == "Library" &&
            components[3] == "Mobile Documents"
    }
}

extension ProjectRecord {
    var isAddedToProjectList: Bool {
        isAdded
    }
}

extension [ProjectRecord] {
    var firstAddedProjectID: UUID? {
        first(where: \.isAddedToProjectList)?.id
    }

    var remoteDiscoverySnapshot: [RemoteProject] {
        filter(\.discovered).map {
            RemoteProject(
                path: $0.path,
                sessionPaths: $0.sessionPaths,
                discoveredSessionCount: $0.discoveredSessionCount,
                archivedSessionCount: $0.archivedSessionCount,
                lastDiscoveredAt: $0.lastDiscoveredAt
            )
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
        case .disconnected: "Server disconnected"
        case .connecting: "Connecting server"
        case .connected: "Server connected"
        case .failed(let message): message
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
