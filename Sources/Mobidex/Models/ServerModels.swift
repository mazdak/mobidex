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
        codexPath: String = "codex",
        targetShellRCFile: String = "$HOME/.zshrc",
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
        self.targetShellRCFile = targetShellRCFile.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "$HOME/.zshrc"
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
        codexPath = try container.decodeIfPresent(String.self, forKey: .codexPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "codex"
        targetShellRCFile = try container.decodeIfPresent(String.self, forKey: .targetShellRCFile)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "$HOME/.zshrc"
        authMethod = try container.decode(ServerAuthMethod.self, forKey: .authMethod)
        projects = try container.decodeIfPresent([ProjectRecord].self, forKey: .projects) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var endpointLabel: String {
        "\(username)@\(host):\(port)"
    }

    var appServerCommand: String {
        if codexPath == "codex" {
            return defaultCodexAppServerCommand
        }
        return [
            shellEnvironmentBootstrapCommand,
            "\(codexPath.shellQuotedExecutablePath) app-server --listen stdio://"
        ].joined(separator: "; ")
    }

    var appServerProxyCommand: String {
        if codexPath == "codex" {
            return defaultCodexAppServerProxyCommand
        }
        return appServerProxyCommand(codexExecutable: codexPath.shellQuotedExecutablePath)
    }

    private var defaultCodexAppServerCommand: String {
        let candidates = [
            "$HOME/.bun/bin/codex",
            "$HOME/.local/bin/codex",
            "$HOME/.npm-global/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        let candidateList = candidates.map { "\"\($0)\"" }.joined(separator: " ")
        return [
            shellEnvironmentBootstrapCommand,
            "if command -v codex >/dev/null 2>&1; then exec codex app-server --listen stdio://; fi",
            "for candidate in \(candidateList); do if [ -x \"$candidate\" ]; then exec \"$candidate\" app-server --listen stdio://; fi; done",
            "for shell in zsh bash; do if command -v \"$shell\" >/dev/null 2>&1; then resolved=\"$(\"$shell\" -lc 'command -v codex' 2>/dev/null || true)\"; if [ -n \"$resolved\" ] && [ -x \"$resolved\" ]; then exec \"$resolved\" app-server --listen stdio://; fi; fi; done",
            "echo 'codex executable not found. Set Codex Binary Path to the full remote codex executable, for example ~/.bun/bin/codex.' >&2",
            "exit 127"
        ].joined(separator: "; ")
    }

    private var defaultCodexAppServerProxyCommand: String {
        [
            shellEnvironmentBootstrapCommand,
            codexResolutionCommand,
            appServerProxyScript(codexExecutable: "\"$codex_bin\"")
        ].joined(separator: "; ")
    }

    private func appServerProxyCommand(codexExecutable: String) -> String {
        [
            shellEnvironmentBootstrapCommand,
            "codex_bin=\(codexExecutable)",
            appServerProxyScript(codexExecutable: "\"$codex_bin\"")
        ].joined(separator: "; ")
    }

    private var codexResolutionCommand: String {
        let candidates = [
            "$HOME/.bun/bin/codex",
            "$HOME/.local/bin/codex",
            "$HOME/.npm-global/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        let candidateList = candidates.map { "\"\($0)\"" }.joined(separator: " ")
        return [
            "codex_bin=\"\"",
            "if command -v codex >/dev/null 2>&1; then codex_bin=\"$(command -v codex)\"; fi",
            "if [ -z \"$codex_bin\" ]; then for candidate in \(candidateList); do if [ -x \"$candidate\" ]; then codex_bin=\"$candidate\"; break; fi; done; fi",
            "if [ -z \"$codex_bin\" ]; then for shell in zsh bash; do if command -v \"$shell\" >/dev/null 2>&1; then resolved=\"$(\"$shell\" -lc 'command -v codex' 2>/dev/null || true)\"; if [ -n \"$resolved\" ] && [ -x \"$resolved\" ]; then codex_bin=\"$resolved\"; break; fi; fi; done; fi",
            "if [ -z \"$codex_bin\" ]; then echo 'codex executable not found. Set Codex Binary Path to the full remote codex executable, for example ~/.bun/bin/codex.' >&2; exit 127; fi"
        ].joined(separator: "; ")
    }

    private func appServerProxyScript(codexExecutable: String) -> String {
        [
            "socket_root=\"${CODEX_HOME:-$HOME/.codex}\"",
            "socket=\"${CODEX_APP_SERVER_SOCK:-$socket_root/app-server-control/app-server-control.sock}\"",
            "socket_dir=\"$(dirname \"$socket\")\"",
            "mkdir -p \"$socket_dir\"",
            "if [ -S \"$socket\" ]; then socket_probe_attempted=0; socket_probe_status=0; if command -v python3 >/dev/null 2>&1; then socket_probe_attempted=1; python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1]); s.close()' \"$socket\" 2>/dev/null; socket_probe_status=$?; elif command -v python >/dev/null 2>&1; then socket_probe_attempted=1; python -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1]); s.close()' \"$socket\" 2>/dev/null; socket_probe_status=$?; elif command -v ruby >/dev/null 2>&1; then socket_probe_attempted=1; ruby -rsocket -e 'UNIXSocket.open(ARGV[0]).close' \"$socket\" 2>/dev/null; socket_probe_status=$?; elif command -v perl >/dev/null 2>&1; then socket_probe_attempted=1; perl -MIO::Socket::UNIX -e 'IO::Socket::UNIX->new(Peer => shift) or exit 1' \"$socket\" 2>/dev/null; socket_probe_status=$?; fi; if [ \"$socket_probe_attempted\" -eq 1 ] && [ \"$socket_probe_status\" -ne 0 ]; then rm -f \"$socket\"; fi; fi",
            "if [ ! -S \"$socket\" ]; then nohup \(codexExecutable) app-server --listen \"unix://$socket\" >>\"$socket_dir/app-server.log\" 2>&1 < /dev/null & i=0; while [ \"$i\" -lt 50 ] && [ ! -S \"$socket\" ]; do i=$((i + 1)); sleep 0.1; done; fi",
            "if [ ! -S \"$socket\" ]; then echo \"codex app-server control socket was not created at $socket\" >&2; exit 127; fi",
            "exec \(codexExecutable) app-server proxy --sock \"$socket\""
        ].joined(separator: "; ")
    }

    private var shellEnvironmentBootstrapCommand: String {
        [
            targetShellRCBootstrapCommand,
            remotePathBootstrapCommand
        ].joined(separator: "; ")
    }

    private var targetShellRCBootstrapCommand: String {
        let rcFile = targetShellRCFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rcFile.isEmpty else {
            return "true"
        }
        return "mobidex_shell_rc=\(rcFile.shellQuotedRemotePath); if [ -f \"$mobidex_shell_rc\" ]; then . \"$mobidex_shell_rc\" 1>&2; fi"
    }

    private var remotePathBootstrapCommand: String {
        "export PATH=\"$HOME/.bun/bin:$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\""
    }
}

struct ProjectRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var path: String
    var sessionPaths: [String]
    var displayName: String
    var discovered: Bool
    var discoveredSessionCount: Int
    var activeChatCount: Int
    var lastDiscoveredAt: Date?
    var lastActiveChatAt: Date?
    var isFavorite: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case sessionPaths
        case displayName
        case discovered
        case discoveredSessionCount
        case activeChatCount
        case lastDiscoveredAt
        case lastActiveChatAt
        case isFavorite
    }

    init(
        id: UUID = UUID(),
        path: String,
        sessionPaths: [String]? = nil,
        displayName: String? = nil,
        discovered: Bool = false,
        discoveredSessionCount: Int = 0,
        activeChatCount: Int = 0,
        lastDiscoveredAt: Date? = nil,
        lastActiveChatAt: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.path = path
        self.sessionPaths = ProjectRecord.normalizedSessionPaths(sessionPaths ?? [path], primaryPath: path)
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent.nonEmpty ?? path
        self.discovered = discovered
        self.discoveredSessionCount = discoveredSessionCount
        self.activeChatCount = activeChatCount
        self.lastDiscoveredAt = lastDiscoveredAt
        self.lastActiveChatAt = lastActiveChatAt
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
        discoveredSessionCount = try container.decode(Int.self, forKey: .discoveredSessionCount)
        activeChatCount = try container.decode(Int.self, forKey: .activeChatCount)
        lastDiscoveredAt = try container.decodeIfPresent(Date.self, forKey: .lastDiscoveredAt)
        lastActiveChatAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveChatAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    static func normalizedSessionPaths(_ paths: [String], primaryPath: String) -> [String] {
        SharedKMPBridge.normalizedSessionPaths(paths, primaryPath: primaryPath)
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

    var shellQuotedRemotePath: String {
        if self == "$HOME" || self == "${HOME}" || self == "~" {
            return "\"${HOME}\""
        }
        if hasPrefix("$HOME/") {
            return "\"${HOME}\"/\(String(dropFirst(6)).shellQuoted)"
        }
        if hasPrefix("${HOME}/") {
            return "\"${HOME}\"/\(String(dropFirst(8)).shellQuoted)"
        }
        if hasPrefix("~/") {
            return "\"${HOME}\"/\(String(dropFirst(2)).shellQuoted)"
        }
        return shellQuoted
    }
}
