import Foundation
import NIOCore

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


actor CodexAppServerClient {
    nonisolated let events: AsyncStream<CodexAppServerEvent>

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
            params: SharedKMPBridge.initializeParams()
        )
        try await sendNotification(method: "initialized", params: nil)
    }

    func listThreads(cwd: String? = nil, limit: Int = 80) async throws -> [CodexThread] {
        var cursor: String?
        var threads: [CodexThread] = []
        repeat {
            let response = try await requestDecoded(
                ThreadListResponse.self,
                method: "thread/list",
                params: SharedKMPBridge.threadListParams(cwd: cwd, limit: limit, cursor: cursor)
            )
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
        let response = try await requestDecoded(
            Response.self,
            method: "thread/loaded/list",
            params: SharedKMPBridge.loadedThreadListParams(limit: limit)
        )
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
            params: SharedKMPBridge.readThreadParams(threadID: threadID, includeTurns: includeTurns)
        )
        return response.thread
    }

    func resumeThread(threadID: String) async throws -> CodexThread {
        let response = try await requestDecoded(
            ThreadReadResponse.self,
            method: "thread/resume",
            params: SharedKMPBridge.resumeThreadParams(threadID: threadID)
        )
        return response.thread
    }

    func startThread(cwd: String?) async throws -> CodexThread {
        let response = try await requestDecoded(
            ThreadReadResponse.self,
            method: "thread/start",
            params: SharedKMPBridge.startThreadParams(cwd: cwd)
        )
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
        let response = try await requestDecoded(
            TurnStartResponse.self,
            method: "turn/start",
            params: SharedKMPBridge.startTurnParams(threadID: threadID, input: input, options: options)
        )
        return response.turn
    }

    func interrupt(threadID: String, turnID: String) async throws {
        _ = try await request(
            method: "turn/interrupt",
            params: SharedKMPBridge.interruptTurnParams(threadID: threadID, turnID: turnID)
        )
    }

    func steer(threadID: String, expectedTurnID: String, text: String) async throws {
        try await steer(threadID: threadID, expectedTurnID: expectedTurnID, input: [.text(text)])
    }

    func steer(threadID: String, expectedTurnID: String, input: [CodexInputItem]) async throws {
        _ = try await request(
            method: "turn/steer",
            params: SharedKMPBridge.steerTurnParams(threadID: threadID, expectedTurnID: expectedTurnID, input: input)
        )
    }

    func gitDiffToRemote(cwd: String) async throws -> GitDiffToRemoteResponse {
        try await requestDecoded(
            GitDiffToRemoteResponse.self,
            method: "gitDiffToRemote",
            params: SharedKMPBridge.gitDiffToRemoteParams(cwd: cwd)
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
        if let request = value as? CodexRPCRequest {
            return SharedKMPBridge.encode(request)
        }
        if let notification = value as? CodexRPCNotification {
            return SharedKMPBridge.encode(notification)
        }
        if let response = value as? CodexRPCResultResponse {
            return SharedKMPBridge.encode(response)
        }
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
