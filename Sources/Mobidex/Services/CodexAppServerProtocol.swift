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

extension JSONValue {
    static func textInput(_ text: String) -> JSONValue {
        .array([
            .object([
                "type": .string("text"),
                "text": .string(text),
                "text_elements": .array([])
            ])
        ])
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The app-server returned an invalid response."
        case .appServer(let error):
            error.message
        case .disconnected:
            "The app-server connection closed."
        }
    }
}

actor CodexAppServerClient {
    nonisolated let events: AsyncStream<CodexAppServerEvent>

    private static let allThreadSourceKinds: JSONValue = .array([
        .string("cli"),
        .string("vscode"),
        .string("exec"),
        .string("appServer"),
        .string("subAgent"),
        .string("subAgentReview"),
        .string("subAgentCompact"),
        .string("subAgentThreadSpawn"),
        .string("subAgentOther"),
        .string("unknown")
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
        var params: [String: JSONValue] = [
            "limit": .int(limit),
            "sortKey": .string("updated_at"),
            "sortDirection": .string("desc"),
            "archived": .bool(false),
            "sourceKinds": Self.allThreadSourceKinds
        ]
        if let cwd, !cwd.isEmpty {
            params["cwd"] = .string(cwd)
        }
        let response = try await requestDecoded(ThreadListResponse.self, method: "thread/list", params: .object(params))
        guard let cwd, !cwd.isEmpty else {
            return response.data
        }
        return response.data.filter { $0.cwd == cwd }
    }

    func listLoadedThreadIDs(limit: Int = 200) async throws -> [String] {
        struct Response: Decodable {
            var data: [String]
        }
        let response = try await requestDecoded(Response.self, method: "thread/loaded/list", params: .object(["limit": .int(limit)]))
        return response.data
    }

    func readThread(threadID: String) async throws -> CodexThread {
        let response = try await requestDecoded(
            ThreadReadResponse.self,
            method: "thread/read",
            params: .object([
                "threadId": .string(threadID),
                "includeTurns": .bool(true)
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
        let response = try await requestDecoded(
            TurnStartResponse.self,
            method: "turn/start",
            params: .object([
                "threadId": .string(threadID),
                "input": .textInput(text)
            ])
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
        _ = try await request(
            method: "turn/steer",
            params: .object([
                "threadId": .string(threadID),
                "expectedTurnId": .string(expectedTurnID),
                "input": .textInput(text)
            ])
        )
    }

    func respondToServerRequest(id: JSONValue, result: JSONValue) async throws {
        try ensureOpenAndStartReadLoop()
        let response = CodexRPCResultResponse(id: id, result: result)
        do {
            try await transport.sendLine(encodeLine(response))
        } catch {
            await disconnect(error: error, message: error.localizedDescription, notify: true)
            throw error
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
        return try decoder.decode(T.self, from: data)
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
                    self.resolve(id: id, result: .failure(error))
                    await self.disconnect(error: error, message: error.localizedDescription, notify: true)
                }
            }
        }
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        try ensureOpenAndStartReadLoop()
        do {
            try await transport.sendLine(encodeLine(CodexRPCNotification(method: method, params: params)))
        } catch {
            await disconnect(error: error, message: error.localizedDescription, notify: true)
            throw error
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
                let envelope = try decoder.decode(CodexRPCInboundEnvelope.self, from: data)
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
            await disconnect(error: error, message: error.localizedDescription, notify: true)
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
