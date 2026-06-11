import Foundation
import NIOCore

/// Thin ACP client for driving spec-compliant stdio agents (`grok agent stdio`,
/// `bunx @zed-industries/claude-code-acp`, ...) over a raw line transport on iOS.
///
/// Reuses `CodexLineTransport` (SSHRawExecTransport via `sshService.openRawExec` +
/// `SharedKMPBridge.acpShellCommand`).
///
/// `session/update` chunks are classified via bridged `AcpProtocolCore` and mapped (via
/// `acpClassificationToSessionItems`) into the exact `CodexThreadItem` model (reasoning, agentMessage,
/// toolCall, plan, agentEvent) already used by the conversation UI, so ACP responses render in
/// `ConversationView` / `ConversationSection` with zero new UI code.
///
/// Codex app-server path and all Codex launch/WS code remain 100% untouched.
actor AcpClient {
    nonisolated let events: AsyncStream<CodexAppServerEvent>
    nonisolated let sessionItems: AsyncStream<CodexThreadItem>  // The primary UI translation surface (mapper output)

    private let transport: CodexLineTransport
    private let rpcCore = SharedKMPBridge.makeRPCClientCore()
    private let acpCore = SharedKMPBridge.makeAcpProtocolCore()
    private let requestTimeoutSeconds: Int
    private let requestTimeoutNanoseconds: UInt64
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingTimeouts: [Int: Task<Void, Never>] = [:]
    private var isClosed = false
    private var readTask: Task<Void, Never>?
    private var currentSessionId: String?
    private var authMethodIds: [String] = []

    private let eventContinuation: AsyncStream<CodexAppServerEvent>.Continuation
    private let itemContinuation: AsyncStream<CodexThreadItem>.Continuation

    // Generous default: a cold `bunx @zed-industries/claude-code-acp` may download the package
    // on the host before answering initialize.
    init(transport: CodexLineTransport, requestTimeoutSeconds: Double = 120) {
        self.transport = transport
        self.requestTimeoutSeconds = max(1, Int(ceil(requestTimeoutSeconds)))
        self.requestTimeoutNanoseconds = UInt64(self.requestTimeoutSeconds) * 1_000_000_000

        let evStream = AsyncStream<CodexAppServerEvent>.makeStream()
        events = evStream.stream
        eventContinuation = evStream.continuation

        let itemStream = AsyncStream<CodexThreadItem>.makeStream()
        sessionItems = itemStream.stream
        itemContinuation = itemStream.continuation
    }

    deinit {
        readTask?.cancel()
    }

    func initialize() async throws {
        guard !isClosed else { throw CodexAppServerClientError.disconnected }
        let result = try await request(
            method: "initialize",
            params: SharedKMPBridge.acpInitializeParams()
        )
        // Remember the advertised auth methods for the auth_required retry in createSession.
        // (No "initialized" notification: ACP has none; spec agents log a decode error for it.)
        authMethodIds = SharedKMPBridge.acpAuthMethodIds(initializeResult: result)
    }

    /// Creates a new ACP session. When the agent answers auth_required (some agents, e.g. grok,
    /// require an explicit `authenticate` even when logged in on the host), authenticates with the
    /// first advertised method and retries once.
    func createSession(cwd: String, title: String? = nil) async throws -> String {
        guard !isClosed else { throw CodexAppServerClientError.disconnected }
        let params = SharedKMPBridge.acpSessionNewParams(cwd: cwd, title: title)
        let result: JSONValue
        do {
            result = try await request(method: "session/new", params: params)
        } catch let error as CodexAppServerClientError {
            guard case .appServer(let info) = error,
                  info.code == SharedKMPBridge.acpAuthRequiredErrorCode,
                  let methodId = authMethodIds.first
            else { throw error }
            _ = try await request(method: "authenticate", params: SharedKMPBridge.acpAuthenticateParams(methodId: methodId))
            result = try await request(method: "session/new", params: params)
        }
        // ACP typically returns { "sessionId": "..." } or the id directly; be tolerant
        let sid: String = {
            if case .object(let obj) = result, case .string(let s)? = obj["sessionId"] { return s }
            if case .string(let s) = result { return s }
            return "acp-\(UUID().uuidString.prefix(8))"
        }()
        currentSessionId = sid
        return sid
    }

    func sendPrompt(sessionId: String, text: String) async throws {
        guard !isClosed else { throw CodexAppServerClientError.disconnected }
        // Fire-and-forget prompt; streaming chunks arrive as session/update notifications
        let req = SharedKMPBridge.nextRequestLine(
            core: rpcCore,
            method: "session/prompt",
            params: SharedKMPBridge.acpSessionPromptParams(sessionId: sessionId, prompt: text)
        )
        try await transport.sendLine(req.line)
        // Do not await a result for the prompt itself in basic ACP; updates come asynchronously
    }

    /// Spec cancellation: `session/cancel` notification (the agent answers the prompt with stopReason=cancelled).
    func cancel(sessionId: String) async throws {
        guard !isClosed else { throw CodexAppServerClientError.disconnected }
        try await sendNotification(method: "session/cancel", params: SharedKMPBridge.acpSessionCancelParams(sessionId: sessionId))
    }

    /// Answers an agent -> client request (e.g. a `session/request_permission` outcome).
    func respondToServerRequest(id: JSONValue, result: JSONValue) async throws {
        try ensureOpenAndStartReadLoop()
        do {
            try await transport.sendLine(SharedKMPBridge.resultLine(core: rpcCore, id: id, result: result))
        } catch {
            let clientError = clientFacingError(error)
            await disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
            throw clientError
        }
    }

    func close() async {
        if isClosed { return }
        isClosed = true
        readTask?.cancel()
        readTask = nil
        await transport.close()
        failPending(CodexAppServerClientError.disconnected)
        eventContinuation.finish()
        itemContinuation.finish()
    }

    // MARK: - Internal request / notification / read loop (modeled exactly on CodexAppServerClient)

    private func ensureOpenAndStartReadLoop() throws {
        guard !isClosed else {
            throw CodexAppServerClientError.disconnected
        }
        startReadLoopIfNeeded()
    }

    private func startReadLoopIfNeeded() {
        guard readTask == nil else { return }
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func request(method: String, params: JSONValue?) async throws -> JSONValue {
        try ensureOpenAndStartReadLoop()
        let request = SharedKMPBridge.nextRequestLine(core: rpcCore, method: method, params: params)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[request.id] = continuation
                pendingTimeouts[request.id] = Task { [requestID = request.id, method, timeout = requestTimeoutNanoseconds] in
                    do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                    self.timeoutRequest(id: requestID, method: method)
                }
                Task {
                    do {
                        try await transport.sendLine(request.line)
                    } catch {
                        let clientError = clientFacingError(error)
                        self.resolve(id: request.id, result: .failure(clientError))
                        Task { await self.disconnect(error: clientError, message: clientError.localizedDescription, notify: true) }
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(id: request.id) }
        }
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        try ensureOpenAndStartReadLoop()
        do {
            try await transport.sendLine(SharedKMPBridge.notificationLine(core: rpcCore, method: method, params: params))
        } catch {
            let clientError = clientFacingError(error)
            await disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
            throw clientError
        }
    }

    private func readLoop() async {
        do {
            for try await line in transport.inboundLines {
                guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                let envelope: CodexRPCInboundEnvelope
                do {
                    envelope = try JSONDecoder().decode(CodexRPCInboundEnvelope.self, from: data)
                } catch {
                    throw CodexAppServerClientError.messageDecodeFailed(
                        "\(DecodeFailureFormatter.describe(error)). Line: \(DecodeFailureFormatter.preview(line))"
                    )
                }

                switch SharedKMPBridge.acpClassifyInbound(core: acpCore, envelope: (
                    id: envelope.id,
                    method: envelope.method,
                    params: envelope.params,
                    result: envelope.result,
                    error: envelope.error.map { CodexRPCErrorInfo(code: Int($0.code), message: $0.message) }
                )) {
                case .errorResponse(let id, let error):
                    let readable = CodexRPCErrorInfo(
                        code: error.code,
                        message: SharedKMPBridge.acpReadableError(code: error.code, message: error.message)
                    )
                    resolve(id: id, result: .failure(CodexAppServerClientError.appServer(readable)))
                case .resultResponse(let id, let result):
                    resolve(id: id, result: .success(result))
                case .serverRequest(let id, let method, let params):
                    eventContinuation.yield(.serverRequest(id: id, method: method, params: params))
                case .notification(let method, let params):
                    eventContinuation.yield(.notification(method: method, params: params))
                case .sessionUpdate(let classification):
                    let items = SharedKMPBridge.acpClassificationToSessionItems(classification)
                    for item in items {
                        itemContinuation.yield(item)
                    }
                case nil:
                    continue
                }
            }
            await disconnect(error: CodexAppServerClientError.disconnected, message: "ACP transport ended.", notify: true)
        } catch {
            let clientError = clientFacingError(error)
            await disconnect(error: clientError, message: clientError.localizedDescription, notify: true)
        }
    }

    private func disconnect(error: Error, message: String, notify: Bool) async {
        guard !isClosed else { return }
        isClosed = true
        readTask = nil
        await transport.close()
        failPending(error)
        if notify {
            eventContinuation.yield(.disconnected(message))
        }
        eventContinuation.finish()
        itemContinuation.finish()
    }

    private func resolve(id: Int, result: Result<JSONValue, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        pendingTimeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(with: result)
    }

    private func timeoutRequest(id: Int, method: String) {
        resolve(id: id, result: .failure(CodexAppServerClientError.requestTimedOut(method: method, seconds: requestTimeoutSeconds)))
    }

    private func cancelRequest(id: Int) {
        resolve(id: id, result: .failure(CancellationError()))
    }

    private func failPending(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        let timeouts = pendingTimeouts.values
        pendingTimeouts.removeAll()
        for t in timeouts { t.cancel() }
        for c in continuations { c.resume(throwing: error) }
    }

    private func clientFacingError(_ error: Error) -> Error {
        if error is CodexAppServerClientError { return error }
        if let ch = error as? ChannelError {
            return CodexAppServerClientError.transportClosed("ACP transport: \(ch)")
        }
        return error
    }
}

// MARK: - Debug conveniences (smoke / unit tests)
#if DEBUG
extension AcpClient {
    static func makeStub(transport: CodexLineTransport) -> AcpClient {
        AcpClient(transport: transport)
    }
}
#endif