import Foundation

struct CodexThread: Identifiable, Decodable, Equatable, Sendable {
    var id: String
    var preview: String
    var cwd: String
    var status: CodexThreadStatus
    var updatedAt: Date
    var createdAt: Date
    var name: String?
    var sourceKind: String?
    var turns: [CodexTurn]

    enum CodingKeys: String, CodingKey {
        case id
        case preview
        case cwd
        case status
        case updatedAt
        case createdAt
        case name
        case sourceKind
        case source
        case turns
    }

    init(
        id: String,
        preview: String,
        cwd: String,
        status: CodexThreadStatus,
        updatedAt: Date,
        createdAt: Date,
        name: String? = nil,
        sourceKind: String? = nil,
        turns: [CodexTurn] = []
    ) {
        self.id = id
        self.preview = preview
        self.cwd = cwd
        self.status = status
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.name = name
        self.sourceKind = sourceKind
        self.turns = turns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        cwd = try container.decode(String.self, forKey: .cwd)
        status = try container.decode(CodexThreadStatus.self, forKey: .status)
        updatedAt = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .updatedAt)))
        createdAt = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .createdAt)))
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sourceKind = try Self.decodeSourceKind(from: container)
        turns = try container.decodeIfPresent([CodexTurn].self, forKey: .turns) ?? []
    }

    private static func decodeSourceKind(from container: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        if let sourceKind = try container.decodeIfPresent(String.self, forKey: .sourceKind) {
            return sourceKind
        }
        guard container.contains(.source) else {
            return nil
        }
        if let source = try? container.decodeIfPresent(String.self, forKey: .source) {
            return source
        }
        if let source = try? container.decodeIfPresent(JSONValue.self, forKey: .source) {
            return source.normalizedThreadSourceKind
        }
        return nil
    }

    var title: String {
        name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? preview.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? URL(fileURLWithPath: cwd).lastPathComponent.nonEmpty
            ?? id
    }

    var isUserFacingSession: Bool {
        guard let sourceKind else {
            return true
        }
        return !sourceKind.hasPrefix("subAgent")
    }
}

private extension JSONValue {
    var normalizedThreadSourceKind: String? {
        switch self {
        case .string(let value):
            return value
        case .object(let object):
            return object["subagent"] == nil ? nil : "subAgent"
        default:
            return nil
        }
    }
}

enum CodexThreadStatusIndicator: Equatable, Sendable {
    case active
    case inactive
    case needsAttention
}

enum CodexThreadStatus: Equatable, Decodable, Sendable {
    case notLoaded
    case idle
    case active(flags: [String])
    case systemError
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "notLoaded":
            self = .notLoaded
        case "idle":
            self = .idle
        case "active":
            self = .active(flags: try container.decodeIfPresent([String].self, forKey: .activeFlags) ?? [])
        case "systemError":
            self = .systemError
        default:
            self = .unknown(type)
        }
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var indicator: CodexThreadStatusIndicator {
        switch self {
        case .active:
            return .active
        case .systemError:
            return .needsAttention
        case .unknown(let value):
            let normalized = value.lowercased()
            return normalized.contains("error") || normalized.contains("fail")
                ? .needsAttention
                : .inactive
        case .idle, .notLoaded:
            return .inactive
        }
    }

    var label: String {
        switch self {
        case .notLoaded: "Not Loaded"
        case .idle: "Idle"
        case .active(let flags): flags.isEmpty ? "Active" : "Active: \(flags.joined(separator: ", "))"
        case .systemError: "System Error"
        case .unknown(let value): value
        }
    }

    var sessionLabel: String {
        switch self {
        case .active(let flags): flags.isEmpty ? "Working" : "Working: \(flags.joined(separator: ", "))"
        case .idle: "Ready"
        case .notLoaded: "Loading"
        case .systemError: "Needs Attention"
        case .unknown(let value): value
        }
    }
}

struct CodexTokenUsage: Decodable, Equatable, Sendable {
    var total: CodexTokenUsageBreakdown
    var last: CodexTokenUsageBreakdown
    var modelContextWindow: Int?

    var contextFraction: Double? {
        guard let modelContextWindow, modelContextWindow > 0 else {
            return nil
        }
        return min(max(Double(total.totalTokens) / Double(modelContextWindow), 0), 1)
    }
}

struct CodexTokenUsageBreakdown: Decodable, Equatable, Sendable {
    var totalTokens: Int
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
}

struct CodexTurn: Identifiable, Decodable, Equatable, Sendable {
    var id: String
    var items: [CodexThreadItem]
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case items
        case status
    }
}

enum CodexUserInput: Decodable, Equatable, Sendable {
    case text(String)
    case attachment(kind: String, label: String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case url
        case path
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        default:
            let label = try container.decodeIfPresent(String.self, forKey: .name)
                ?? container.decodeIfPresent(String.self, forKey: .path)
                ?? container.decodeIfPresent(String.self, forKey: .url)
                ?? type
            self = .attachment(kind: type, label: label)
        }
    }
}

struct CodexFileChange: Decodable, Equatable, Sendable {
    var path: String
    var diff: String
}

enum CodexThreadItem: Decodable, Equatable, Identifiable, Sendable {
    case userMessage(id: String, text: String)
    case agentMessage(id: String, text: String)
    case reasoning(id: String, summary: [String], content: [String])
    case plan(id: String, text: String)
    case command(id: String, command: String, cwd: String, status: String, output: String?)
    case fileChange(id: String, changes: [CodexFileChange], status: String)
    case toolCall(id: String, label: String, status: String, detail: String?)
    case agentEvent(id: String, label: String, status: String, detail: String?)
    case webSearch(id: String, query: String)
    case image(id: String, label: String)
    case review(id: String, label: String)
    case contextCompaction(id: String)
    case unknown(id: String, type: String)

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case content
        case text
        case summary
        case command
        case cwd
        case status
        case aggregatedOutput
        case changes
        case server
        case tool
        case namespace
        case arguments
        case query
        case path
        case result
        case prompt
        case receiverThreadIds
        case review
    }

    var id: String {
        switch self {
        case .userMessage(let id, _),
             .agentMessage(let id, _),
             .reasoning(let id, _, _),
             .plan(let id, _),
             .command(let id, _, _, _, _),
             .fileChange(let id, _, _),
             .toolCall(let id, _, _, _),
             .agentEvent(let id, _, _, _),
             .webSearch(let id, _),
             .image(let id, _),
             .review(let id, _),
             .contextCompaction(let id),
             .unknown(let id, _):
            id
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString

        switch type {
        case "userMessage":
            let input = try container.decodeIfPresent([CodexUserInput].self, forKey: .content) ?? []
            let text = input.map(\.displayText).joined(separator: "\n")
            self = .userMessage(id: id, text: text)
        case "agentMessage":
            self = .agentMessage(id: id, text: try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "reasoning":
            self = .reasoning(
                id: id,
                summary: try container.decodeIfPresent([String].self, forKey: .summary) ?? [],
                content: try container.decodeIfPresent([String].self, forKey: .content) ?? []
            )
        case "plan":
            self = .plan(id: id, text: try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "commandExecution":
            self = .command(
                id: id,
                command: try container.decodeIfPresent(String.self, forKey: .command) ?? "",
                cwd: try container.decodeIfPresent(String.self, forKey: .cwd) ?? "",
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
                output: try container.decodeIfPresent(String.self, forKey: .aggregatedOutput)
            )
        case "fileChange":
            self = .fileChange(
                id: id,
                changes: try container.decodeIfPresent([CodexFileChange].self, forKey: .changes) ?? [],
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? ""
            )
        case "mcpToolCall":
            let server = try container.decodeIfPresent(String.self, forKey: .server)
            let tool = try container.decodeIfPresent(String.self, forKey: .tool) ?? "MCP tool"
            self = .toolCall(
                id: id,
                label: [server, tool].compactMap { $0 }.joined(separator: " / "),
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
                detail: nil
            )
        case "dynamicToolCall":
            let namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
            let tool = try container.decodeIfPresent(String.self, forKey: .tool) ?? "Dynamic tool"
            self = .toolCall(
                id: id,
                label: [namespace, tool].compactMap { $0 }.joined(separator: " / "),
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
                detail: nil
            )
        case "collabAgentToolCall":
            let tool = try container.decodeIfPresent(String.self, forKey: .tool) ?? "Agent"
            self = .agentEvent(
                id: id,
                label: tool,
                status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
                detail: try container.decodeIfPresent(String.self, forKey: .prompt)
            )
        case "webSearch":
            self = .webSearch(id: id, query: try container.decodeIfPresent(String.self, forKey: .query) ?? "")
        case "imageView":
            self = .image(id: id, label: try container.decodeIfPresent(String.self, forKey: .path) ?? "Image")
        case "imageGeneration":
            self = .image(id: id, label: try container.decodeIfPresent(String.self, forKey: .result) ?? "Generated image")
        case "enteredReviewMode", "exitedReviewMode":
            self = .review(id: id, label: try container.decodeIfPresent(String.self, forKey: .review) ?? type)
        case "contextCompaction":
            self = .contextCompaction(id: id)
        default:
            self = .unknown(id: id, type: type)
        }
    }
}

struct ThreadListResponse: Decodable, Sendable {
    var data: [CodexThread]
    var nextCursor: String?
}

struct ThreadReadResponse: Decodable, Sendable {
    var thread: CodexThread
}

struct TurnStartResponse: Decodable, Sendable {
    var turn: CodexTurn
}

private extension CodexUserInput {
    var displayText: String {
        switch self {
        case .text(let text): text
        case .attachment(let kind, let label): "[\(kind): \(label)]"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
