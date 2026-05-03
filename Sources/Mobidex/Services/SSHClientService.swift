import Foundation
@preconcurrency import Citadel
import Crypto
import NIOCore

struct RemoteProject: Identifiable, Codable, Equatable {
    var id: String { path }
    var path: String
    var threadCount: Int
    var lastSeenAt: Date?
}

protocol SSHService: Sendable {
    func testConnection(server: ServerRecord, credential: SSHCredential) async throws
    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject]
    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient
}

enum SSHServiceError: LocalizedError {
    case missingPassword
    case missingPrivateKey
    case unsupportedPrivateKey(String)
    case invalidDiscoveryOutput
    case transportClosed

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            "Enter the SSH password for this server."
        case .missingPrivateKey:
            "Paste an OpenSSH private key for this server."
        case .unsupportedPrivateKey(let type):
            "Unsupported private key type: \(type). RSA and Ed25519 OpenSSH keys are supported in this build."
        case .invalidDiscoveryOutput:
            "The server returned invalid Codex discovery data."
        case .transportClosed:
            "The SSH app-server transport is closed."
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

    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient {
        let client = try await connect(server: server, credential: credential)
        do {
            let transport = try await SSHAppServerProcessTransport.open(client: client, command: server.appServerCommand)
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
            throw error
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
            throw error
        }
    }

    private func connect(server: ServerRecord, credential: SSHCredential) async throws -> SSHClient {
        try await SSHClient.connect(
            host: server.host,
            port: server.port,
            authenticationMethod: authenticationMethod(server: server, credential: credential),
            hostKeyValidator: .acceptAnything(),
            reconnect: .never,
            algorithms: .all
        )
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

private final class SSHAppServerProcessTransport: CodexLineTransport, @unchecked Sendable {
    let inboundLines: AsyncThrowingStream<String, Error>

    private let client: SSHClient
    private let inboundContinuation: AsyncThrowingStream<String, Error>.Continuation
    private let outboundLines: AsyncStream<String>
    private let outboundContinuation: AsyncStream<String>.Continuation
    private let ready = ReadySignal()
    private var task: Task<Void, Never>?

    private init(client: SSHClient) {
        self.client = client
        let inbound = AsyncThrowingStream<String, Error>.makeStream()
        inboundLines = inbound.stream
        inboundContinuation = inbound.continuation

        let outbound = AsyncStream<String>.makeStream()
        outboundLines = outbound.stream
        outboundContinuation = outbound.continuation
    }

    static func open(client: SSHClient, command: String) async throws -> SSHAppServerProcessTransport {
        let transport = SSHAppServerProcessTransport(client: client)
        let ready = transport.ready
        let outboundLines = transport.outboundLines
        let outboundContinuation = transport.outboundContinuation
        let inboundContinuation = transport.inboundContinuation
        transport.task = Task {
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
                        case .stderr:
                            continue
                        }
                    }
                    if !pending.isEmpty {
                        inboundContinuation.yield(pending)
                    }
                    outboundContinuation.finish()
                    inboundContinuation.finish()
                }
            } catch {
                await ready.fail(error)
                outboundContinuation.finish()
                inboundContinuation.finish(throwing: error)
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
