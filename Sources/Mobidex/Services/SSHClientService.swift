import Foundation
@preconcurrency import Citadel
import Crypto
import NIOCore

struct RemoteProject: Identifiable, Codable, Equatable {
    var id: String { path }
    var path: String
    var sessionPaths: [String]
    var discoveredSessionCount: Int
    var lastDiscoveredAt: Date?

    private enum CodingKeys: String, CodingKey {
        case path
        case sessionPaths
        case discoveredSessionCount
        case lastDiscoveredAt
    }

    init(path: String, sessionPaths: [String]? = nil, discoveredSessionCount: Int, lastDiscoveredAt: Date?) {
        self.path = path
        self.sessionPaths = sessionPaths ?? [path]
        self.discoveredSessionCount = discoveredSessionCount
        self.lastDiscoveredAt = lastDiscoveredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        sessionPaths = try container.decodeIfPresent([String].self, forKey: .sessionPaths) ?? [path]
        discoveredSessionCount = try container.decode(Int.self, forKey: .discoveredSessionCount)
        lastDiscoveredAt = try container.decodeIfPresent(Date.self, forKey: .lastDiscoveredAt)
    }
}

protocol SSHService: Sendable {
    func testConnection(server: ServerRecord, credential: SSHCredential) async throws
    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject]
    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String]
    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient
}

enum SSHServiceError: LocalizedError {
    case missingPassword
    case missingPrivateKey
    case unsupportedPrivateKey(String)
    case invalidDiscoveryOutput(String?)
    case transportClosed
    case authenticationFailed
    case connectionTimedOut(String, Int)
    case hostUnreachable(String, Int)
    case connectionClosed(String)
    case appServerClosed(command: String, details: String?)
    case localFileNotReadable(String)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            "Enter the SSH password for this server."
        case .missingPrivateKey:
            "Paste an OpenSSH private key for this server."
        case .unsupportedPrivateKey(let type):
            "Unsupported private key type: \(type). RSA and Ed25519 OpenSSH keys are supported in this build."
        case .invalidDiscoveryOutput(let details):
            if let details, !details.isEmpty {
                "The server returned invalid Codex discovery data: \(details)"
            } else {
                "The server returned invalid Codex discovery data."
            }
        case .transportClosed:
            "The SSH app-server transport is closed."
        case .authenticationFailed:
            "SSH authentication failed. Check the username and saved password or private key."
        case .connectionTimedOut(let host, let port):
            "Timed out connecting to \(host):\(port). Check that SSH is reachable from this network."
        case .hostUnreachable(let host, let port):
            "Could not reach \(host):\(port). Check the host, port, and network connection."
        case .connectionClosed(let operation):
            "The SSH server closed the connection while \(operation). Check the server logs and SSH authentication settings."
        case .appServerClosed(let command, let details):
            if let details, !details.isEmpty {
                "SSH connected, but the server closed the app-server session while starting `\(command)`: \(details)"
            } else {
                "SSH connected, but the server closed the app-server session while starting `\(command)`. Check the Codex path and that Codex app-server can run on the server."
            }
        case .localFileNotReadable(let path):
            "Could not read the local file at \(path)."
        }
    }
}

final class CitadelSSHService: SSHService {
    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {
        try await withClient(server: server, credential: credential) { client in
            _ = try await client.executeCommand("printf mobidex-ready", maxResponseSize: 1_024, mergeStreams: true)
        }
    }

    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] {
        try await withClient(server: server, credential: credential) { client in
            let output = try await client.executeCommand(
                RemoteCodexDiscovery.shellCommand,
                maxResponseSize: 2_000_000,
                mergeStreams: true,
                inShell: true
            )
            return try RemoteCodexDiscovery.decodeProjects(from: String(buffer: output))
        }
    }

    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String] {
        guard !localPaths.isEmpty else {
            return []
        }
        return try await withClient(server: server, credential: credential) { client in
            let directoryOutput = try await client.executeCommand(
                #"mkdir -p "$HOME/.mobidex/uploads" && mktemp -d "$HOME/.mobidex/uploads/mobidex.XXXXXX""#,
                maxResponseSize: 4_096,
                mergeStreams: true,
                inShell: true
            )
            let remoteDirectory = String(buffer: directoryOutput).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteDirectory.isEmpty else {
                throw SSHServiceError.connectionClosed("creating a remote upload directory")
            }

            let sftp = try await client.openSFTP()
            do {
                var remotePaths: [String] = []
                for localPath in localPaths {
                    let localURL = URL(fileURLWithPath: localPath)
                    let data: Data
                    do {
                        data = try Data(contentsOf: localURL)
                    } catch {
                        throw SSHServiceError.localFileNotReadable(localPath)
                    }
                    let remotePath = "\(remoteDirectory)/\(UUID().uuidString)-\(sanitizedFilename(localURL.lastPathComponent))"
                    try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
                        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                        buffer.writeBytes(data)
                        try await file.write(buffer)
                    }
                    remotePaths.append(remotePath)
                }
                try? await sftp.close()
                return remotePaths
            } catch {
                try? await sftp.close()
                throw error
            }
        }
    }

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        let command = server.appServerProxyCommand
        let client = try await connect(server: server, credential: credential)
        do {
            let transport = try await CodexSSHAppServerProxyTransport.open(client: client, command: command)
            let appServer = CodexAppServerClient(transport: transport)
            do {
                try await appServer.initialize()
                return appServer
            } catch {
                await appServer.close()
                throw error
            }
        } catch {
            try? await client.close()
            throw mapSSHError(error, server: server, operation: .appServer(command: command))
        }
    }

    private func withClient<T>(
        server: ServerRecord,
        credential: SSHCredential,
        operation: (SSHClient) async throws -> T
    ) async throws -> T {
        let client = try await connect(server: server, credential: credential)
        do {
            let result = try await operation(client)
            try? await client.close()
            return result
        } catch {
            try? await client.close()
            throw mapSSHError(error, server: server, operation: .command)
        }
    }

    private func connect(server: ServerRecord, credential: SSHCredential) async throws -> SSHClient {
        do {
            return try await SSHClient.connect(
                host: server.host,
                port: server.port,
                authenticationMethod: authenticationMethod(server: server, credential: credential),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )
        } catch {
            throw mapSSHError(error, server: server, operation: .connect)
        }
    }

    private func authenticationMethod(server: ServerRecord, credential: SSHCredential) throws -> SSHAuthenticationMethod {
        switch server.authMethod {
        case .password:
            guard let password = credential.password, !password.isEmpty else {
                throw SSHServiceError.missingPassword
            }
            return .passwordBased(username: server.username, password: password)
        case .privateKey:
            guard let key = credential.privateKeyPEM, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SSHServiceError.missingPrivateKey
            }
            let decryptionKey = credential.privateKeyPassphrase?.data(using: .utf8)
            let keyType = try SSHKeyDetection.detectPrivateKeyType(from: key)
            switch keyType {
            case .ed25519:
                return try .ed25519(
                    username: server.username,
                    privateKey: Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: decryptionKey)
                )
            case .rsa:
                return try .rsa(
                    username: server.username,
                    privateKey: Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: decryptionKey)
                )
            default:
                throw SSHServiceError.unsupportedPrivateKey(keyType.description)
            }
        }
    }

}

private func sanitizedFilename(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let scalars = value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "_"
    }
    let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    return sanitized.isEmpty ? "attachment" : sanitized
}

private enum SSHOperationContext {
    case connect
    case command
    case appServer(command: String)
}

private func mapSSHError(_ error: Error, server: ServerRecord, operation: SSHOperationContext) -> Error {
    if error is SSHServiceError {
        return error
    }
    if error is AuthenticationFailed {
        return SSHServiceError.authenticationFailed
    }
    if let clientError = error as? SSHClientError {
        switch clientError {
        case .allAuthenticationOptionsFailed, .unsupportedPasswordAuthentication, .unsupportedPrivateKeyAuthentication:
            return SSHServiceError.authenticationFailed
        case .channelCreationFailed, .unsupportedHostBasedAuthentication:
            return closedError(for: operation)
        }
    }
    if let channelError = error as? ChannelError {
        switch channelError {
        case .connectTimeout:
            return SSHServiceError.connectionTimedOut(server.host, server.port)
        case .writeHostUnreachable:
            return SSHServiceError.hostUnreachable(server.host, server.port)
        case .inputClosed, .outputClosed, .ioOnClosedChannel, .alreadyClosed, .eof:
            return closedError(for: operation)
        case .connectPending, .operationUnsupported, .writeMessageTooLarge, .unknownLocalAddress,
                .badMulticastGroupAddressFamily, .badInterfaceAddressFamily, .illegalMulticastAddress,
                .inappropriateOperationForState, .unremovableHandler:
            break
        #if !os(WASI)
        case .multicastNotSupported:
            break
        #endif
        }
    }
    return error
}

private func closedError(for operation: SSHOperationContext) -> SSHServiceError {
    switch operation {
    case .connect:
        .connectionClosed("connecting or authenticating")
    case .command:
        .connectionClosed("running a remote command")
    case .appServer(let command):
        .appServerClosed(command: command, details: nil)
    }
}

private final class SSHAppServerProcessTransport: CodexLineTransport, @unchecked Sendable {
    let inboundLines: AsyncThrowingStream<String, Error>

    private let client: SSHClient
    private let command: String
    private let inboundContinuation: AsyncThrowingStream<String, Error>.Continuation
    private let outboundLines: AsyncStream<String>
    private let outboundContinuation: AsyncStream<String>.Continuation
    private let ready = ReadySignal()
    private var task: Task<Void, Never>?

    private init(client: SSHClient, command: String) {
        self.client = client
        self.command = command
        let inbound = AsyncThrowingStream<String, Error>.makeStream()
        inboundLines = inbound.stream
        inboundContinuation = inbound.continuation

        let outbound = AsyncStream<String>.makeStream()
        outboundLines = outbound.stream
        outboundContinuation = outbound.continuation
    }

    static func open(client: SSHClient, command: String) async throws -> SSHAppServerProcessTransport {
        let transport = SSHAppServerProcessTransport(client: client, command: command)
        let ready = transport.ready
        let command = transport.command
        let outboundLines = transport.outboundLines
        let outboundContinuation = transport.outboundContinuation
        let inboundContinuation = transport.inboundContinuation
        transport.task = Task {
            var stderrTail = ""
            func rememberStderr(_ buffer: ByteBuffer) {
                stderrTail.append(String(buffer: buffer))
                if stderrTail.count > 4_000 {
                    stderrTail = String(stderrTail.suffix(4_000))
                }
            }

            func appServerExitError(fallback: Error? = nil) -> Error {
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
                            for await line in outboundLines {
                                try await outbound.write(ByteBuffer(string: "\(line)\n"))
                            }
                        } catch {
                            outboundContinuation.finish()
                            inboundContinuation.finish(throwing: error)
                        }
                    }
                    defer { writer.cancel() }

                    var pending = ""
                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer):
                            pending.append(String(buffer: buffer))
                            let parts = pending.split(separator: "\n", omittingEmptySubsequences: false)
                            pending = parts.last.map(String.init) ?? ""
                            for line in parts.dropLast() where !line.isEmpty {
                                inboundContinuation.yield(String(line))
                            }
                        case .stderr(let buffer):
                            rememberStderr(buffer)
                        }
                    }
                    if !pending.isEmpty {
                        inboundContinuation.yield(pending)
                    }
                    outboundContinuation.finish()
                    inboundContinuation.finish(throwing: appServerExitError())
                }
            } catch {
                let exitError = appServerExitError(fallback: error)
                await ready.fail(exitError)
                outboundContinuation.finish()
                inboundContinuation.finish(throwing: exitError)
            }
            try? await client.close()
        }
        try await transport.ready.wait()
        return transport
    }

    func sendLine(_ line: String) async throws {
        switch outboundContinuation.yield(line) {
        case .enqueued:
            return
        case .dropped, .terminated:
            throw SSHServiceError.transportClosed
        @unknown default:
            throw SSHServiceError.transportClosed
        }
    }

    func close() async {
        let runningTask = task
        task = nil
        outboundContinuation.finish()
        runningTask?.cancel()
        try? await client.close()
        inboundContinuation.finish()
    }
}

private actor ReadySignal {
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
        guard completed == nil else {
            return
        }
        completed = result
        let current = waiters
        waiters.removeAll()
        for waiter in current {
            waiter.resume(with: result)
        }
    }
}
