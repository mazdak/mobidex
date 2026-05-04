import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self {
            return object[key]
        }
        return nil
    }
}

enum CodexInputItem: Equatable, Sendable {
    case text(String)
    case imageURL(String)
    case localImage(path: String)
    case skill(name: String, path: String)
    case mention(name: String, path: String)

    var jsonValue: JSONValue {
        switch self {
        case .text(let text):
            .object([
                "type": .string("text"),
                "text": .string(text),
                "text_elements": .array([])
            ])
        case .imageURL(let url):
            .object([
                "type": .string("image"),
                "url": .string(url)
            ])
        case .localImage(let path):
            .object([
                "type": .string("localImage"),
                "path": .string(path)
            ])
        case .skill(let name, let path):
            .object([
                "type": .string("skill"),
                "name": .string(name),
                "path": .string(path)
            ])
        case .mention(let name, let path):
            .object([
                "type": .string("mention"),
                "name": .string(name),
                "path": .string(path)
            ])
        }
    }
}

enum CodexReasoningEffortOption: String, CaseIterable, Identifiable, Equatable, Sendable {
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        }
    }
}

enum CodexAccessMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case fullAccess
    case workspaceWrite
    case readOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullAccess: "Full access"
        case .workspaceWrite: "Workspace"
        case .readOnly: "Read only"
        }
    }

    var systemImage: String {
        switch self {
        case .fullAccess: "exclamationmark.shield"
        case .workspaceWrite: "folder.badge.gearshape"
        case .readOnly: "lock.shield"
        }
    }
}

struct CodexTurnOptions: Equatable, Sendable {
    var reasoningEffort: CodexReasoningEffortOption?
    var accessMode: CodexAccessMode?
    var cwd: String?

    static let `default` = CodexTurnOptions(reasoningEffort: nil, accessMode: nil, cwd: nil)

    var jsonFields: [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        if let reasoningEffort {
            fields["effort"] = .string(reasoningEffort.rawValue)
        }
        switch accessMode {
        case .fullAccess:
            fields["approvalPolicy"] = .string("never")
            fields["sandboxPolicy"] = .object(["type": .string("dangerFullAccess")])
        case .workspaceWrite:
            fields["approvalPolicy"] = .string("on-request")
            fields["sandboxPolicy"] = .object([
                "type": .string("workspaceWrite"),
                "writableRoots": .array(cwd.map { [.string($0)] } ?? []),
                "networkAccess": .bool(true),
                "excludeTmpdirEnvVar": .bool(false),
                "excludeSlashTmp": .bool(false)
            ])
        case .readOnly:
            fields["approvalPolicy"] = .string("on-request")
            fields["sandboxPolicy"] = .object([
                "type": .string("readOnly"),
                "networkAccess": .bool(false)
            ])
        case nil:
            break
        }
        return fields
    }
}

extension JSONValue {
    static func textInput(_ text: String) -> JSONValue {
        inputItems([.text(text)])
    }

    static func inputItems(_ items: [CodexInputItem]) -> JSONValue {
        .array(items.map(\.jsonValue))
    }
}

struct CodexRPCRequest: Encodable, Sendable {
    var jsonrpc = "2.0"
    var id: Int
    var method: String
    var params: JSONValue?
}

struct CodexRPCNotification: Encodable, Sendable {
    var jsonrpc = "2.0"
    var method: String
    var params: JSONValue?
}

struct CodexRPCResultResponse: Encodable, Sendable {
    var jsonrpc = "2.0"
    var id: JSONValue
    var result: JSONValue
}

struct CodexRPCErrorInfo: Decodable, Error, Equatable, Sendable {
    var code: Int
    var message: String
}

extension CodexRPCErrorInfo {
    var canIgnoreForLoadedThreadSummary: Bool {
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("not found")
            || normalizedMessage.contains("not loaded")
            || normalizedMessage.contains("unknown thread")
            || normalizedMessage.contains("no such thread")
    }
}

struct CodexRPCInboundEnvelope: Decodable, Sendable {
    var id: JSONValue?
    var method: String?
    var params: JSONValue?
    var result: JSONValue?
    var error: CodexRPCErrorInfo?
}

enum CodexAppServerEvent: Equatable, Sendable {
    case notification(method: String, params: JSONValue?)
    case serverRequest(id: JSONValue, method: String, params: JSONValue?)
    case disconnected(String)
}

struct GitDiffToRemoteResponse: Decodable, Equatable, Sendable {
    var sha: String
    var diff: String
}
