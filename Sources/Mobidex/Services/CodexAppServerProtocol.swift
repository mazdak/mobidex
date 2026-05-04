import Foundation
import NIOCore

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

protocol CodexLineTransport: Sendable {
    var inboundLines: AsyncThrowingStream<String, Error> { get }
    func sendLine(_ line: String) async throws
    func close() async
}

enum CodexAppServerClientError: LocalizedError, Sendable {
    case invalidResponse
    case appServer(CodexRPCErrorInfo)
    case disconnected
    case transportClosed(String)
    case messageDecodeFailed(String)
    case responseDecodeFailed(method: String, details: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The app-server returned an invalid response."
        case .appServer(let error):
            error.message
        case .disconnected:
            "The app-server connection closed."
        case .transportClosed(let message):
            message
        case .messageDecodeFailed(let details):
            "Could not decode an app-server message: \(details)"
        case .responseDecodeFailed(let method, let details):
            "Could not decode the app-server `\(method)` response: \(details)"
        }
    }
}

enum DecodeFailureFormatter {
    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing key `\(key.stringValue)` at \(codingPath(context.codingPath)); \(context.debugDescription)"
        case DecodingError.typeMismatch(let type, let context):
            return "expected \(type) at \(codingPath(context.codingPath)); \(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context):
            return "missing \(type) value at \(codingPath(context.codingPath)); \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "data corrupted at \(codingPath(context.codingPath)); \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    static func preview(_ value: String, limit: Int = 320) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > limit else {
            return trimmed
        }
        return "\(trimmed.prefix(limit))..."
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else {
            return "root"
        }
        return path.map(\.stringValue).joined(separator: ".")
    }
}

struct GitDiffToRemoteResponse: Decodable, Equatable, Sendable {
    var sha: String
    var diff: String
}

enum GitDiffChangedFileParser {
    static func paths(from diff: String) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        var pendingOldPath: String?

        func append(_ path: String?) {
            guard let path,
                  !path.isEmpty,
                  path != "/dev/null",
                  seen.insert(path).inserted
            else {
                return
            }
            paths.append(path)
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                append(diffGitDestinationPath(from: line))
                pendingOldPath = nil
            } else if line.hasPrefix("--- ") {
                pendingOldPath = normalizedDiffPath(String(line.dropFirst(4)))
            } else if line.hasPrefix("+++ ") {
                let nextPath = normalizedDiffPath(String(line.dropFirst(4)))
                append(nextPath == nil ? pendingOldPath : nextPath)
                pendingOldPath = nil
            } else if line.hasPrefix("rename to ") {
                append(String(line.dropFirst("rename to ".count)))
            }
        }

        return paths
    }

    private static func diffGitDestinationPath(from line: String) -> String? {
        let payload = String(line.dropFirst("diff --git ".count))
        if let unquotedPath = unquotedDiffGitDestinationPath(from: payload) {
            return unquotedPath
        }
        let pathTokens = parseDiffPathTokens(payload)
        guard pathTokens.count >= 2 else {
            return nil
        }
        return normalizedDiffPath(pathTokens[1])
    }

    private static func unquotedDiffGitDestinationPath(from value: String) -> String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\""),
              let separator = value.range(of: " b/", options: .backwards)
        else {
            return nil
        }
        let destinationStart = value.index(after: separator.lowerBound)
        return normalizedDiffPath(String(value[destinationStart...]))
    }

    private static func parseDiffPathTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var index = value.startIndex

        func advancePastWhitespace() {
            while index < value.endIndex, value[index].isWhitespace {
                index = value.index(after: index)
            }
        }

        while index < value.endIndex {
            advancePastWhitespace()
            guard index < value.endIndex else {
                break
            }

            if value[index] == "\"" {
                index = value.index(after: index)
                var token = ""
                var isEscaped = false
                while index < value.endIndex {
                    let character = value[index]
                    index = value.index(after: index)
                    if isEscaped {
                        token.append(unescapedGitQuotedCharacter(character))
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        break
                    } else {
                        token.append(character)
                    }
                }
                tokens.append(token)
            } else {
                let start = index
                while index < value.endIndex, !value[index].isWhitespace {
                    index = value.index(after: index)
                }
                tokens.append(String(value[start..<index]))
            }
        }

        return tokens
    }

    private static func normalizedDiffPath(_ path: String) -> String? {
        let trimmed = unquotedGitPath(path).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "/dev/null" else {
            return nil
        }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unquotedGitPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
            return trimmed
        }
        return parseDiffPathTokens(trimmed).first ?? trimmed
    }

    private static func unescapedGitQuotedCharacter(_ character: Character) -> Character {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        default: character
        }
    }
}

enum GitDiffFileParser {
    static func files(from diff: String) -> [ChangedFileDiff] {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.contains(where: { $0.hasPrefix("diff --git ") }) else {
            let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [ChangedFileDiff(path: "Working Tree", diff: diff)]
        }

        var files: [ChangedFileDiff] = []
        var currentLines: [String] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            let fileDiff = currentLines.joined(separator: "\n")
            let path = GitDiffChangedFileParser.paths(from: fileDiff).first ?? "Changed File"
            files.append(ChangedFileDiff(path: path, diff: fileDiff))
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
            }
            currentLines.append(line)
        }
        flush()

        return files
    }
}

actor CodexAppServerClient {
    nonisolated let events: AsyncStream<CodexAppServerEvent>

    private static let userFacingThreadSourceKinds: JSONValue = .array([
        .string("cli"),
        .string("vscode"),
        .string("exec"),
        .string("appServer")
    ])

    private let transport: CodexLineTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private let eventContinuation: AsyncStream<CodexAppServerEvent>.Continuation
    private var readTask: Task<Void, Never>?
    private var isClosed = false

    init(transport: CodexLineTransport) {
        self.transport = transport
        let stream = AsyncStream<CodexAppServerEvent>.makeStream()
        events = stream.stream
        eventContinuation = stream.continuation
    }

    deinit {
        readTask?.cancel()
    }

    func initialize() async throws {
        _ = try await request(
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string("mobidex"),
                    "title": .string("Mobidex"),
                    "version": .string("0.1.0")
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(true)
                ])
            ])
        )
        try await sendNotification(method: "initialized", params: nil)
    }

    func listThreads(cwd: String? = nil, limit: Int = 80) async throws -> [CodexThread] {
        var cursor: String?
        var threads: [CodexThread] = []
        repeat {
            var params: [String: JSONValue] = [
                "limit": .int(limit),
                "sortKey": .string("updated_at"),
                "sortDirection": .string("desc"),
                "archived": .bool(false),
                "sourceKinds": Self.userFacingThreadSourceKinds
            ]
            if let cwd, !cwd.isEmpty {
                params["cwd"] = .string(cwd)
            }
            if let cursor {
                params["cursor"] = .string(cursor)
            }
            let response = try await requestDecoded(ThreadListResponse.self, method: "thread/list", params: .object(params))
            threads.append(contentsOf: response.data.filter(\.isUserFacingSession))
            cursor = response.nextCursor
        } while cursor != nil

        guard let cwd, !cwd.isEmpty else {
            return threads
        }
        return threads.filter { $0.cwd == cwd }
    }

    func listLoadedThreadIDs(limit: Int = 200) async throws -> [String] {
        struct Response: Decodable {
            var data: [String]
        }
        let response = try await requestDecoded(Response.self, method: "thread/loaded/list", params: .object(["limit": .int(limit)]))
        return response.data
    }

    func readThread(threadID: String) async throws -> CodexThread {
        try await readThread(threadID: threadID, includeTurns: true)
    }

    func readThreadSummary(threadID: String) async throws -> CodexThread {
        try await readThread(threadID: threadID, includeTurns: false)
    }

    private func readThread(threadID: String, includeTurns: Bool) async throws -> CodexThread {
        let response = try await requestDecoded(
            ThreadReadResponse.self,
            method: "thread/read",
            params: .object([
                "threadId": .string(threadID),
                "includeTurns": .bool(includeTurns)
            ])
        )
        return response.thread
    }

    func resumeThread(threadID: String) async throws -> CodexThread {
        let response = try await requestDecoded(
            ThreadReadResponse.self,
            method: "thread/resume",
            params: .object(["threadId": .string(threadID)])
        )
        return response.thread
    }

    func startThread(cwd: String?) async throws -> CodexThread {
        let params: JSONValue = cwd.map { .object(["cwd": .string($0)]) } ?? .object([:])
        let response = try await requestDecoded(ThreadReadResponse.self, method: "thread/start", params: params)
        return response.thread
    }

    func startTurn(threadID: String, text: String) async throws -> CodexTurn {
        try await startTurn(threadID: threadID, input: [.text(text)])
    }

    func startTurn(
        threadID: String,
        input: [CodexInputItem],
        options: CodexTurnOptions = .default
    ) async throws -> CodexTurn {
        var params = options.jsonFields
        params["threadId"] = .string(threadID)
        params["input"] = .inputItems(input)
        let response = try await requestDecoded(
            TurnStartResponse.self,
            method: "turn/start",
            params: .object(params)
        )
        return response.turn
    }

    func interrupt(threadID: String, turnID: String) async throws {
        _ = try await request(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(threadID),
                "turnId": .string(turnID)
            ])
        )
    }

    func steer(threadID: String, expectedTurnID: String, text: String) async throws {
        try await steer(threadID: threadID, expectedTurnID: expectedTurnID, input: [.text(text)])
    }

    func steer(threadID: String, expectedTurnID: String, input: [CodexInputItem]) async throws {
        _ = try await request(
            method: "turn/steer",
            params: .object([
                "threadId": .string(threadID),
                "expectedTurnId": .string(expectedTurnID),
                "input": .inputItems(input)
            ])
        )
    }

    func gitDiffToRemote(cwd: String) async throws -> GitDiffToRemoteResponse {
        try await requestDecoded(
            GitDiffToRemoteResponse.self,
            method: "gitDiffToRemote",
            params: .object(["cwd": .string(cwd)])
        )
    }

    func changedFiles(cwd: String) async throws -> [String] {
        let response = try await gitDiffToRemote(cwd: cwd)
        return GitDiffChangedFileParser.paths(from: response.diff)
    }

    func diffSnapshot(cwd: String) async throws -> GitDiffSnapshot {
        let response = try await gitDiffToRemote(cwd: cwd)
        return GitDiffSnapshot(
            sha: response.sha,
            diff: response.diff,
            files: GitDiffFileParser.files(from: response.diff)
        )
    }

    func respondToServerRequest(id: JSONValue, result: JSONValue) async throws {
        try ensureOpenAndStartReadLoop()
        let response = CodexRPCResultResponse(id: id, result: result)
        do {
            try await transport.sendLine(encodeLine(response))
        } catch {
            let clientError = clientFacingError(error)
            await disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
            throw clientError
        }
    }

    func close() async {
        guard !isClosed else {
            return
        }
        isClosed = true
        readTask?.cancel()
        readTask = nil
        await transport.close()
        failPending(CodexAppServerClientError.disconnected)
        eventContinuation.finish()
    }

    private func requestDecoded<T: Decodable>(_ type: T.Type, method: String, params: JSONValue?) async throws -> T {
        let result = try await request(method: method, params: params)
        let data = try encoder.encode(result)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CodexAppServerClientError.responseDecodeFailed(
                method: method,
                details: DecodeFailureFormatter.describe(error)
            )
        }
    }

    private func request(method: String, params: JSONValue?) async throws -> JSONValue {
        try ensureOpenAndStartReadLoop()
        let id = nextID
        nextID += 1
        let request = CodexRPCRequest(id: id, method: method, params: params)
        let line = try encodeLine(request)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await transport.sendLine(line)
                } catch {
                    let clientError = clientFacingError(error)
                    self.resolve(id: id, result: .failure(clientError))
                    await self.disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
                }
            }
        }
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        try ensureOpenAndStartReadLoop()
        do {
            try await transport.sendLine(encodeLine(CodexRPCNotification(method: method, params: params)))
        } catch {
            let clientError = clientFacingError(error)
            await disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
            throw clientError
        }
    }

    private func ensureOpenAndStartReadLoop() throws {
        guard !isClosed else {
            throw CodexAppServerClientError.disconnected
        }
        startReadLoopIfNeeded()
    }

    private func startReadLoopIfNeeded() {
        guard readTask == nil else {
            return
        }
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func readLoop() async {
        do {
            for try await line in transport.inboundLines {
                guard let data = line.data(using: .utf8), !data.isEmpty else {
                    continue
                }
                let envelope: CodexRPCInboundEnvelope
                do {
                    envelope = try decoder.decode(CodexRPCInboundEnvelope.self, from: data)
                } catch {
                    throw CodexAppServerClientError.messageDecodeFailed(
                        "\(DecodeFailureFormatter.describe(error)). Line: \(DecodeFailureFormatter.preview(line))"
                    )
                }
                if let id = envelope.id?.intValue, let error = envelope.error {
                    resolve(id: id, result: .failure(CodexAppServerClientError.appServer(error)))
                } else if let id = envelope.id?.intValue, let result = envelope.result {
                    resolve(id: id, result: .success(result))
                } else if let id = envelope.id, let method = envelope.method {
                    eventContinuation.yield(.serverRequest(id: id, method: method, params: envelope.params))
                } else if let method = envelope.method {
                    eventContinuation.yield(.notification(method: method, params: envelope.params))
                }
            }
            await disconnect(error: CodexAppServerClientError.disconnected, message: "The app-server stream ended.", notify: true)
        } catch {
            let clientError = clientFacingError(error)
            await disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
        }
    }

    private func disconnect(error: Error, message: String, notify: Bool) async {
        guard !isClosed else {
            return
        }
        isClosed = true
        readTask = nil
        await transport.close()
        failPending(error)
        if notify {
            eventContinuation.yield(.disconnected(message))
        }
        eventContinuation.finish()
    }

    private func resolve(id: Int, result: Result<JSONValue, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }
        continuation.resume(with: result)
    }

    private func failPending(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func encodeLine<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CodexAppServerClientError.invalidResponse
        }
        return line
    }
}

private func clientFacingError(_ error: Error) -> Error {
    if error is CodexAppServerClientError {
        return error
    }
    if let channelError = error as? ChannelError {
        return CodexAppServerClientError.transportClosed(clientFacingChannelErrorMessage(channelError))
    }
    return error
}

private func clientFacingChannelErrorMessage(_ error: ChannelError) -> String {
    switch error {
    case .connectTimeout:
        "Timed out waiting for the app-server SSH channel."
    case .writeHostUnreachable:
        "Could not reach the app-server SSH channel."
    case .inputClosed, .outputClosed, .ioOnClosedChannel, .alreadyClosed, .eof:
        "The app-server SSH channel closed."
    default:
        "The app-server SSH channel failed: \(error.description)."
    }
}

final class MockCodexLineTransport: CodexLineTransport, @unchecked Sendable {
    let inboundLines: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private(set) var sentLines: [String] = []
    private let lock = NSLock()

    init() {
        let stream = AsyncThrowingStream<String, Error>.makeStream()
        inboundLines = stream.stream
        continuation = stream.continuation
    }

    func sendLine(_ line: String) async throws {
        lock.withLock {
            sentLines.append(line)
        }
    }

    var sentLinesSnapshot: [String] {
        lock.withLock { sentLines }
    }

    func close() async {
        continuation.finish()
    }

    func receive(_ line: String) {
        continuation.yield(line)
    }

    func finishInbound(throwing error: Error? = nil) {
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
