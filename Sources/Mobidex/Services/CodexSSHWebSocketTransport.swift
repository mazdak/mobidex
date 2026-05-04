import Foundation
@preconcurrency import Citadel
import Crypto
import NIOCore
import NIOSSH

enum CodexSSHWebSocketTransportError: LocalizedError {
    case unsupportedURL
    case connectionClosed
    case invalidHandshake(String)
    case unsupportedFrame

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "Enter a ws:// app-server URL for SSH-tunneled WebSocket connections."
        case .connectionClosed:
            "The SSH app-server WebSocket connection closed."
        case .invalidHandshake(let response):
            "The app-server WebSocket handshake failed: \(response)"
        case .unsupportedFrame:
            "The app-server sent an unsupported WebSocket frame."
        }
    }
}

final class CodexSSHWebSocketTransport: CodexLineTransport, @unchecked Sendable {
    let inboundLines: AsyncThrowingStream<String, Error>

    private let client: SSHClient
    private let channel: Channel
    private let inboundContinuation: AsyncThrowingStream<String, Error>.Continuation
    private var receiveTask: Task<Void, Never>?

    private init(client: SSHClient, channel: Channel) {
        self.client = client
        self.channel = channel
        let stream = AsyncThrowingStream<String, Error>.makeStream()
        inboundLines = stream.stream
        inboundContinuation = stream.continuation
    }

    deinit {
        receiveTask?.cancel()
    }

    static func open(client: SSHClient, url: URL, bearerToken: String?) async throws -> CodexSSHWebSocketTransport {
        guard url.scheme?.lowercased() == "ws",
              let host = url.host
        else {
            throw CodexSSHWebSocketTransportError.unsupportedURL
        }
        let port = url.port ?? 80

        let byteQueue = SSHWebSocketByteQueue()
        let originatorAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        let channel = try await client.createDirectTCPIPChannel(
            using: SSHChannelType.DirectTCPIP(targetHost: host, targetPort: port, originatorAddress: originatorAddress)
        ) { channel in
            channel.pipeline.addHandler(SSHWebSocketByteHandler(queue: byteQueue))
        }

        do {
            let key = Self.webSocketKey()
            try await Self.write(
                Self.upgradeRequest(url: url, host: host, port: port, key: key, bearerToken: bearerToken),
                to: channel
            )
            let response = try await Self.readUpgradeResponse(from: byteQueue)
            try WebSocketHandshakeValidator.validate(response.headers, key: key)

            let transport = CodexSSHWebSocketTransport(client: client, channel: channel)
            transport.startReceiveLoop(byteQueue: byteQueue, initialData: response.leftover)
            return transport
        } catch {
            try? await channel.close().get()
            try? await client.close()
            await byteQueue.finish(throwing: error)
            throw error
        }
    }

    func sendLine(_ line: String) async throws {
        try await sendFrame(opcode: .text, payload: Data(line.utf8))
    }

    func close() async {
        receiveTask?.cancel()
        receiveTask = nil
        try? await sendFrame(opcode: .close, payload: Data())
        try? await channel.close().get()
        try? await client.close()
        inboundContinuation.finish()
    }

    private func startReceiveLoop(byteQueue: SSHWebSocketByteQueue, initialData: Data) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(byteQueue: byteQueue, initialData: initialData)
        }
    }

    private func receiveLoop(byteQueue: SSHWebSocketByteQueue, initialData: Data) async {
        var parser = WebSocketFrameParser(buffer: initialData)
        var assembler = WebSocketMessageAssembler()
        do {
            while !Task.isCancelled {
                while let frame = try parser.nextFrame() {
                    switch frame.opcode {
                    case .text, .binary, .continuation:
                        if let message = try assembler.append(frame), let text = String(data: message, encoding: .utf8) {
                            inboundContinuation.yield(text)
                        }
                    case .ping:
                        try await sendFrame(opcode: .pong, payload: frame.payload)
                    case .pong:
                        continue
                    case .close:
                        inboundContinuation.finish()
                        try? await channel.close().get()
                        return
                    }
                }

                guard let chunk = try await byteQueue.next() else {
                    inboundContinuation.finish()
                    return
                }
                parser.append(chunk)
            }
        } catch {
            if !Task.isCancelled {
                inboundContinuation.finish(throwing: error)
            }
        }
    }

    private func sendFrame(opcode: WebSocketOpcode, payload: Data) async throws {
        try await Self.write(WebSocketFrameEncoder.frame(opcode: opcode, payload: payload), to: channel)
    }

    private static func write(_ data: Data, to channel: Channel) async throws {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(buffer).get()
    }

    private static func upgradeRequest(
        url: URL,
        host: String,
        port: Int,
        key: String,
        bearerToken: String?
    ) -> Data {
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path += "?\(query)"
        }
        var lines = [
            "GET \(path) HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13"
        ]
        if let bearerToken, !bearerToken.isEmpty {
            lines.append("Authorization: Bearer \(bearerToken)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private static func readUpgradeResponse(
        from byteQueue: SSHWebSocketByteQueue
    ) async throws -> (headers: String, leftover: Data) {
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                await byteQueue.finish(
                    throwing: CodexSSHWebSocketTransportError.invalidHandshake(
                        "timed out waiting for websocket upgrade response"
                    )
                )
            } catch {}
        }
        defer { timeoutTask.cancel() }
        return try await readUpgradeResponseBytes(from: byteQueue)
    }

    private static func readUpgradeResponseBytes(
        from byteQueue: SSHWebSocketByteQueue
    ) async throws -> (headers: String, leftover: Data) {
        let separator = Data([13, 10, 13, 10])
        var buffer = Data()
        while let chunk = try await byteQueue.next() {
            buffer.append(chunk)
            guard let range = buffer.range(of: separator) else {
                if buffer.count > 65_536 {
                    throw CodexSSHWebSocketTransportError.invalidHandshake("response headers were too large")
                }
                continue
            }
            let headerData = buffer[..<range.upperBound]
            let leftover = buffer[range.upperBound...]
            guard let headers = String(data: headerData, encoding: .utf8) else {
                throw CodexSSHWebSocketTransportError.invalidHandshake("response headers were not UTF-8")
            }
            return (headers, Data(leftover))
        }
        throw CodexSSHWebSocketTransportError.connectionClosed
    }

    private static func validateUpgradeResponse(_ headers: String) throws {
        let firstLine = headers.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard firstLine.contains(" 101 ") || firstLine.hasSuffix(" 101") || firstLine.contains(" 101\r") else {
            throw CodexSSHWebSocketTransportError.invalidHandshake(firstLine.isEmpty ? "missing status line" : firstLine)
        }
    }

    private static func webSocketKey() -> String {
        Data((0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }).base64EncodedString()
    }
}

final class CodexSSHAppServerProxyTransport: CodexLineTransport, @unchecked Sendable {
    let inboundLines: AsyncThrowingStream<String, Error>

    private let client: SSHClient
    private let command: String
    private let byteQueue = SSHWebSocketByteQueue()
    private let inboundContinuation: AsyncThrowingStream<String, Error>.Continuation
    private let outboundBytes: AsyncStream<Data>
    private let outboundContinuation: AsyncStream<Data>.Continuation
    private let ready = WebSocketProxyReadySignal()
    private var processTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private init(client: SSHClient, command: String) {
        self.client = client
        self.command = command
        let inbound = AsyncThrowingStream<String, Error>.makeStream()
        inboundLines = inbound.stream
        inboundContinuation = inbound.continuation

        let outbound = AsyncStream<Data>.makeStream()
        outboundBytes = outbound.stream
        outboundContinuation = outbound.continuation
    }

    deinit {
        processTask?.cancel()
        receiveTask?.cancel()
    }

    static func open(client: SSHClient, command: String) async throws -> CodexSSHAppServerProxyTransport {
        let transport = CodexSSHAppServerProxyTransport(client: client, command: command)
        transport.startProxyProcess()
        do {
            try await transport.ready.wait()
            let key = Self.webSocketKey()
            try await transport.writeBytes(Self.upgradeRequest(key: key))
            let response = try await Self.readUpgradeResponse(from: transport.byteQueue)
            try WebSocketHandshakeValidator.validate(response.headers, key: key)
            transport.startReceiveLoop(initialData: response.leftover)
            return transport
        } catch {
            await transport.close()
            throw error
        }
    }

    func sendLine(_ line: String) async throws {
        try await sendFrame(opcode: .text, payload: Data(line.utf8))
    }

    func close() async {
        receiveTask?.cancel()
        receiveTask = nil
        try? await sendFrame(opcode: .close, payload: Data())
        outboundContinuation.finish()
        processTask?.cancel()
        processTask = nil
        await byteQueue.finish()
        try? await client.close()
        inboundContinuation.finish()
    }

    private func startProxyProcess() {
        let client = client
        let command = command
        let outboundBytes = outboundBytes
        let outboundContinuation = outboundContinuation
        let ready = ready
        let byteQueue = byteQueue
        let inboundContinuation = inboundContinuation
        processTask = Task {
            var stderrTail = ""
            func rememberStderr(_ buffer: ByteBuffer) {
                stderrTail.append(String(buffer: buffer))
                if stderrTail.count > 4_000 {
                    stderrTail = String(stderrTail.suffix(4_000))
                }
            }

            func proxyExitError(fallback: Error? = nil) -> Error {
                let details = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !details.isEmpty {
                    return SSHServiceError.appServerClosed(command: command, details: details)
                }
                return fallback ?? SSHServiceError.appServerClosed(command: command, details: nil)
            }

            do {
                try await client.withExec(command) { inbound, outbound in
                    await ready.succeed()
                    let writer = Task {
                        do {
                            for await data in outboundBytes {
                                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                                buffer.writeBytes(data)
                                try await outbound.write(buffer)
                            }
                        } catch {
                            outboundContinuation.finish()
                            await byteQueue.finish(throwing: error)
                            inboundContinuation.finish(throwing: error)
                        }
                    }
                    defer { writer.cancel() }

                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer):
                            var buffer = buffer
                            if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
                                await byteQueue.append(Data(bytes))
                            }
                        case .stderr(let buffer):
                            rememberStderr(buffer)
                        }
                    }
                    outboundContinuation.finish()
                    let error = proxyExitError()
                    await byteQueue.finish(throwing: error)
                    inboundContinuation.finish(throwing: error)
                }
            } catch {
                let exitError = proxyExitError(fallback: error)
                await ready.fail(exitError)
                outboundContinuation.finish()
                await byteQueue.finish(throwing: exitError)
                inboundContinuation.finish(throwing: exitError)
            }
            try? await client.close()
        }
    }

    private func startReceiveLoop(initialData: Data) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(initialData: initialData)
        }
    }

    private func receiveLoop(initialData: Data) async {
        var parser = WebSocketFrameParser(buffer: initialData)
        var assembler = WebSocketMessageAssembler()
        do {
            while !Task.isCancelled {
                while let frame = try parser.nextFrame() {
                    switch frame.opcode {
                    case .text, .binary, .continuation:
                        if let message = try assembler.append(frame), let text = String(data: message, encoding: .utf8) {
                            inboundContinuation.yield(text)
                        }
                    case .ping:
                        try await sendFrame(opcode: .pong, payload: frame.payload)
                    case .pong:
                        continue
                    case .close:
                        inboundContinuation.finish()
                        return
                    }
                }

                guard let chunk = try await byteQueue.next() else {
                    inboundContinuation.finish()
                    return
                }
                parser.append(chunk)
            }
        } catch {
            if !Task.isCancelled {
                inboundContinuation.finish(throwing: error)
            }
        }
    }

    private func sendFrame(opcode: WebSocketOpcode, payload: Data) async throws {
        try await writeBytes(WebSocketFrameEncoder.frame(opcode: opcode, payload: payload))
    }

    private func writeBytes(_ data: Data) async throws {
        switch outboundContinuation.yield(data) {
        case .enqueued:
            return
        case .dropped, .terminated:
            throw SSHServiceError.transportClosed
        @unknown default:
            throw SSHServiceError.transportClosed
        }
    }

    private static func upgradeRequest(key: String) -> Data {
        Data([
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            ""
        ].joined(separator: "\r\n").utf8)
    }

    private static func readUpgradeResponse(
        from byteQueue: SSHWebSocketByteQueue
    ) async throws -> (headers: String, leftover: Data) {
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                await byteQueue.finish(
                    throwing: CodexSSHWebSocketTransportError.invalidHandshake(
                        "timed out waiting for websocket upgrade response"
                    )
                )
            } catch {}
        }
        defer { timeoutTask.cancel() }
        return try await readUpgradeResponseBytes(from: byteQueue)
    }

    private static func readUpgradeResponseBytes(
        from byteQueue: SSHWebSocketByteQueue
    ) async throws -> (headers: String, leftover: Data) {
        let separator = Data([13, 10, 13, 10])
        var buffer = Data()
        while let chunk = try await byteQueue.next() {
            buffer.append(chunk)
            guard let range = buffer.range(of: separator) else {
                if buffer.count > 65_536 {
                    throw CodexSSHWebSocketTransportError.invalidHandshake("response headers were too large")
                }
                continue
            }
            let headerData = buffer[..<range.upperBound]
            let leftover = buffer[range.upperBound...]
            guard let headers = String(data: headerData, encoding: .utf8) else {
                throw CodexSSHWebSocketTransportError.invalidHandshake("response headers were not UTF-8")
            }
            return (headers, Data(leftover))
        }
        throw CodexSSHWebSocketTransportError.connectionClosed
    }

    private static func validateUpgradeResponse(_ headers: String) throws {
        let firstLine = headers.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard firstLine.contains(" 101 ") || firstLine.hasSuffix(" 101") || firstLine.contains(" 101\r") else {
            throw CodexSSHWebSocketTransportError.invalidHandshake(firstLine.isEmpty ? "missing status line" : firstLine)
        }
    }

    private static func webSocketKey() -> String {
        Data((0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }).base64EncodedString()
    }
}

private actor WebSocketProxyReadySignal {
    private var completed: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        if let completed {
            return try completed.get()
        }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func succeed() {
        finish(.success(()))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard completed == nil else { return }
        completed = result
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume(with: result)
        }
    }
}

private enum WebSocketHandshakeValidator {
    static func validate(_ headers: String, key: String) throws {
        let lines = headers
            .split(separator: "\r\n", omittingEmptySubsequences: false)
            .map(String.init)
        let statusLine = lines.first ?? ""
        guard statusLine.contains(" 101 ") || statusLine.hasSuffix(" 101") else {
            throw CodexSSHWebSocketTransportError.invalidHandshake(statusLine.isEmpty ? "missing status line" : statusLine)
        }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            fields[name] = value
        }

        let upgrade = fields["upgrade"]?.lowercased()
        guard upgrade == "websocket" else {
            throw CodexSSHWebSocketTransportError.invalidHandshake("missing websocket upgrade header")
        }

        let connectionValues = fields["connection"]?
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        guard connectionValues.contains("upgrade") else {
            throw CodexSSHWebSocketTransportError.invalidHandshake("missing connection upgrade header")
        }

        guard fields["sec-websocket-accept"] == expectedAccept(for: key) else {
            throw CodexSSHWebSocketTransportError.invalidHandshake("invalid Sec-WebSocket-Accept header")
        }
    }

    private static func expectedAccept(for key: String) -> String {
        let seed = Data("\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".utf8)
        let digest = Insecure.SHA1.hash(data: seed)
        return Data(digest).base64EncodedString()
    }
}

private final class SSHWebSocketByteHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let queue: SSHWebSocketByteQueue

    init(queue: SSHWebSocketByteQueue) {
        self.queue = queue
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
            let queue = queue
            Task {
                await queue.append(Data(bytes))
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let queue = queue
        Task {
            await queue.finish(throwing: error)
        }
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        let queue = queue
        Task {
            await queue.finish()
        }
    }
}

private actor SSHWebSocketByteQueue {
    private var chunks: [Data] = []
    private var waiters: [CheckedContinuation<Data?, Error>] = []
    private var completion: Error?
    private var isFinished = false

    func append(_ data: Data) {
        guard !isFinished else { return }
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: data)
        } else {
            chunks.append(data)
        }
    }

    func finish(throwing error: Error? = nil) {
        guard !isFinished else { return }
        isFinished = true
        completion = error
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume(returning: nil)
            }
        }
    }

    func next() async throws -> Data? {
        if !chunks.isEmpty {
            return chunks.removeFirst()
        }
        if isFinished {
            if let completion {
                throw completion
            }
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

private struct WebSocketFrame {
    var fin: Bool
    var opcode: WebSocketOpcode
    var payload: Data
}

private struct WebSocketFrameParser {
    var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func nextFrame() throws -> WebSocketFrame? {
        guard buffer.count >= 2 else { return nil }
        let first = byte(at: 0)
        let second = byte(at: 1)
        let fin = (first & 0x80) != 0
        guard let opcode = WebSocketOpcode(rawValue: first & 0x0F) else {
            throw CodexSSHWebSocketTransportError.unsupportedFrame
        }

        var offset = 2
        var length = Int(second & 0x7F)
        if length == 126 {
            guard buffer.count >= 4 else { return nil }
            length = (Int(byte(at: 2)) << 8) | Int(byte(at: 3))
            offset = 4
        } else if length == 127 {
            guard buffer.count >= 10 else { return nil }
            let length64 = (0..<8).reduce(UInt64(0)) { value, index in
                (value << 8) | UInt64(byte(at: 2 + index))
            }
            guard length64 <= UInt64(Int.max) else {
                throw CodexSSHWebSocketTransportError.unsupportedFrame
            }
            length = Int(length64)
            offset = 10
        }

        let isMasked = (second & 0x80) != 0
        var mask: [UInt8] = []
        if isMasked {
            guard buffer.count >= offset + 4 else { return nil }
            mask = (0..<4).map { byte(at: offset + $0) }
            offset += 4
        }

        guard buffer.count >= offset + length else { return nil }
        var payload = Array(buffer[offset..<(offset + length)])
        if isMasked {
            for index in payload.indices {
                payload[index] ^= mask[index % 4]
            }
        }
        buffer.removeSubrange(0..<(offset + length))
        return WebSocketFrame(fin: fin, opcode: opcode, payload: Data(payload))
    }

    private func byte(at offset: Int) -> UInt8 {
        buffer[buffer.index(buffer.startIndex, offsetBy: offset)]
    }
}

private struct WebSocketMessageAssembler {
    private var fragmentedOpcode: WebSocketOpcode?
    private var fragmentedPayload = Data()

    mutating func append(_ frame: WebSocketFrame) throws -> Data? {
        switch frame.opcode {
        case .text, .binary:
            guard frame.fin else {
                fragmentedOpcode = frame.opcode
                fragmentedPayload = frame.payload
                return nil
            }
            return frame.payload
        case .continuation:
            guard fragmentedOpcode != nil else {
                throw CodexSSHWebSocketTransportError.unsupportedFrame
            }
            fragmentedPayload.append(frame.payload)
            guard frame.fin else {
                return nil
            }
            let payload = fragmentedPayload
            fragmentedOpcode = nil
            fragmentedPayload = Data()
            return payload
        case .close, .ping, .pong:
            return nil
        }
    }
}

private enum WebSocketFrameEncoder {
    static func frame(opcode: WebSocketOpcode, payload: Data) -> Data {
        var bytes = Data()
        bytes.append(0x80 | opcode.rawValue)
        let maskKey = (0..<4).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        let count = payload.count
        if count < 126 {
            bytes.append(0x80 | UInt8(count))
        } else if count <= UInt16.max {
            bytes.append(0x80 | 126)
            bytes.append(UInt8((count >> 8) & 0xFF))
            bytes.append(UInt8(count & 0xFF))
        } else {
            bytes.append(0x80 | 127)
            let length = UInt64(count)
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }
        bytes.append(contentsOf: maskKey)
        let payloadBytes = Array(payload)
        for index in payloadBytes.indices {
            bytes.append(payloadBytes[index] ^ maskKey[index % 4])
        }
        return bytes
    }
}
