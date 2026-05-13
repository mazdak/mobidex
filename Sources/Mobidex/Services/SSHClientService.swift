import Foundation
@preconcurrency import Citadel
import Crypto
import Darwin
import NIOCore
import NIOPosix
import NIOSSH

struct RemoteProject: Identifiable, Codable, Equatable {
    var id: String { path }
    var path: String
    var sessionPaths: [String]
    var discoveredSessionCount: Int
    var archivedSessionCount: Int
    var lastDiscoveredAt: Date?

    private enum CodingKeys: String, CodingKey {
        case path
        case sessionPaths
        case discoveredSessionCount
        case archivedSessionCount
        case lastDiscoveredAt
    }

    init(path: String, sessionPaths: [String]? = nil, discoveredSessionCount: Int, archivedSessionCount: Int = 0, lastDiscoveredAt: Date?) {
        self.path = path
        self.sessionPaths = sessionPaths ?? [path]
        self.discoveredSessionCount = discoveredSessionCount
        self.archivedSessionCount = archivedSessionCount
        self.lastDiscoveredAt = lastDiscoveredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        sessionPaths = try container.decodeIfPresent([String].self, forKey: .sessionPaths) ?? [path]
        discoveredSessionCount = try container.decode(Int.self, forKey: .discoveredSessionCount)
        archivedSessionCount = try container.decodeIfPresent(Int.self, forKey: .archivedSessionCount) ?? 0
        lastDiscoveredAt = try container.decodeIfPresent(Date.self, forKey: .lastDiscoveredAt)
    }
}

struct RemoteDirectoryEntry: Identifiable, Codable, Equatable {
    var id: String { path }
    var name: String
    var path: String
}

struct RemoteDirectoryListing: Codable, Equatable {
    var path: String
    var entries: [RemoteDirectoryEntry]
}

struct SSHDiagnosticTCPResult: Identifiable, Equatable {
    var id: String { address }
    var address: String
    var result: String
}

struct SSHDiagnosticReport: Equatable {
    var host: String
    var resolvedAddresses: [String]
    var tcpResults: [SSHDiagnosticTCPResult]
    var hostKeyFingerprint: String?
    var authMethod: String
    var failureStage: String?
    var rawUnderlyingErrorType: String?
    var rawUnderlyingError: String?
    var remoteCommandResult: String?
    var appServerResult: String?

    var summary: String {
        if let failureStage {
            return "Failed at \(failureStage)"
        }
        return "Diagnostics passed"
    }
}

protocol SSHService: Sendable {
    func testConnection(server: ServerRecord, credential: SSHCredential) async throws
    func diagnoseConnection(server: ServerRecord, credential: SSHCredential) async -> SSHDiagnosticReport
    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject]
    func listDirectories(path: String, server: ServerRecord, credential: SSHCredential) async throws -> RemoteDirectoryListing
    func stageLocalFiles(localPaths: [String], server: ServerRecord, credential: SSHCredential) async throws -> [String]
    func openAppServer(server: ServerRecord, credential: SSHCredential) async throws -> CodexAppServerClient
}

protocol RemoteTerminalSession: AnyObject, Sendable {
    var output: AsyncThrowingStream<Data, Error> { get }
    func write(_ data: Data) async throws
    func resize(columns: Int, rows: Int) async throws
    func close() async
}

protocol TerminalSSHService: SSHService {
    func openTerminal(cwd: String?, columns: Int, rows: Int, server: ServerRecord, credential: SSHCredential) async throws -> RemoteTerminalSession
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
    case localNetworkPermissionDenied(String, Int, String)
    case connectionFailed(String, Int, String)
    case connectionClosed(String)
    case appServerClosed(command: String, details: String?)
    case remoteDirectoryBrowseFailed(String)
    case localFileNotReadable(String)
    case hostKeyChanged(String, Int)

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
        case .localNetworkPermissionDenied(let host, let port, let details):
            "iOS may be blocking local-network access to \(host):\(port). Allow Local Network access for Mobidex in Settings, then try again. Underlying failure: \(details)"
        case .connectionFailed(let host, let port, let details):
            "Could not connect to \(host):\(port): \(details)"
        case .connectionClosed(let operation):
            "The SSH server closed the connection while \(operation). Check the server logs and SSH authentication settings."
        case .appServerClosed(let command, let details):
            if let details, !details.isEmpty {
                "SSH connected, but the server closed the app-server session while starting `\(command)`: \(details)"
            } else {
                "SSH connected, but the server closed the app-server session while starting `\(command)`. Check the Codex path and that Codex app-server can run on the server."
            }
        case .remoteDirectoryBrowseFailed(let details):
            "Could not browse remote folders: \(details)"
        case .localFileNotReadable(let path):
            "Could not read the local file at \(path)."
        case .hostKeyChanged(let host, let port):
            "The SSH host key for \(host):\(port) changed. Remove and re-add the server if this change was expected."
        }
    }
}

final class CitadelSSHService: TerminalSSHService {
    func testConnection(server: ServerRecord, credential: SSHCredential) async throws {
        try await withClient(server: server, credential: credential) { client in
            _ = try await client.executeCommand("printf mobidex-ready", maxResponseSize: 1_024, mergeStreams: true)
        }
    }

    func diagnoseConnection(server: ServerRecord, credential: SSHCredential) async -> SSHDiagnosticReport {
        let authLabel = switch server.authMethod {
        case .password: "password"
        case .privateKey: "private key"
        }
        var report = SSHDiagnosticReport(
            host: "\(server.host):\(server.port)",
            resolvedAddresses: [],
            tcpResults: [],
            hostKeyFingerprint: nil,
            authMethod: authLabel,
            failureStage: nil,
            rawUnderlyingErrorType: nil,
            rawUnderlyingError: nil,
            remoteCommandResult: nil,
            appServerResult: nil
        )

        do {
            let addresses = try await Task.detached(priority: .userInitiated) {
                try resolveAddresses(host: server.host, port: server.port)
            }.value
            report.resolvedAddresses = addresses
            report.tcpResults = await Task.detached(priority: .userInitiated) {
                addresses.map { address in
                    SSHDiagnosticTCPResult(
                        address: address,
                        result: tcpProbe(address: address, port: server.port, timeoutMilliseconds: 2_000)
                    )
                }
            }.value
        } catch {
            report.failureStage = "DNS"
            report.rawUnderlyingErrorType = String(reflecting: type(of: error))
            report.rawUnderlyingError = String(describing: error)
            return report
        }

        let hostKeyCapture = HostKeyFingerprintCapture()
        do {
            let client = try await SSHClient.connect(
                host: server.host,
                port: server.port,
                authenticationMethod: authenticationMethod(server: server, credential: credential),
                hostKeyValidator: .custom(DiagnosticHostKeyValidator(server: server, capture: hostKeyCapture)),
                reconnect: .never,
                algorithms: .all
            )
            report.hostKeyFingerprint = hostKeyCapture.fingerprint
            do {
                let output = try await client.executeCommand("printf mobidex-ready", maxResponseSize: 1_024, mergeStreams: true)
                report.remoteCommandResult = String(buffer: output).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                report.failureStage = "remote command"
                report.rawUnderlyingErrorType = String(reflecting: type(of: error))
                report.rawUnderlyingError = String(describing: error)
                try? await client.close()
                return report
            }
            try? await client.close()
        } catch {
            report.hostKeyFingerprint = hostKeyCapture.fingerprint
            let mapped = mapSSHError(error, server: server, operation: .connect)
            report.failureStage = diagnosticStage(for: mapped, fallback: error)
            report.rawUnderlyingErrorType = String(reflecting: type(of: error))
            report.rawUnderlyingError = String(describing: error)
            return report
        }

        do {
            let appServer = try await openAppServer(server: server, credential: credential)
            report.appServerResult = "initialized"
            await appServer.close()
        } catch {
            report.failureStage = "app-server"
            report.rawUnderlyingErrorType = String(reflecting: type(of: error))
            report.rawUnderlyingError = String(describing: error)
            return report
        }

        return report
    }

    func discoverProjects(server: ServerRecord, credential: SSHCredential) async throws -> [RemoteProject] {
        try await withClient(server: server, credential: credential) { client in
            let output = try await client.executeCommand(
                RemoteCodexDiscovery.shellCommand(targetShellRCFile: server.targetShellRCFile),
                maxResponseSize: 2_000_000,
                mergeStreams: false,
                inShell: true
            )
            return try RemoteCodexDiscovery.decodeProjects(from: String(buffer: output))
        }
    }

    func listDirectories(path: String, server: ServerRecord, credential: SSHCredential) async throws -> RemoteDirectoryListing {
        try await withClient(server: server, credential: credential) { client in
            let output = try await client.executeCommand(
                SharedKMPBridge.remoteDirectoryBrowserShellCommand(path: path),
                maxResponseSize: 1_000_000,
                mergeStreams: false,
                inShell: true
            )
            return try SharedKMPBridge.decodeRemoteDirectoryListing(from: String(buffer: output))
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
                    do {
                        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
                            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                            buffer.writeBytes(data)
                            try await file.write(buffer)
                        }
                    } catch {
                        try await uploadViaShell(data: data, remotePath: remotePath, client: client)
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

    func openTerminal(cwd: String?, columns: Int, rows: Int, server: ServerRecord, credential: SSHCredential) async throws -> RemoteTerminalSession {
        let client = try await connect(server: server, credential: credential)
        do {
            return try await CitadelTerminalSession.open(client: client, cwd: cwd, columns: columns, rows: rows)
        } catch {
            try? await client.close()
            throw mapSSHError(error, server: server, operation: .command)
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
                hostKeyValidator: .custom(PinnedHostKeyValidator(server: server)),
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

private final class HostKeyFingerprintCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: String?

    var fingerprint: String? {
        lock.withLock { captured }
    }

    func save(_ fingerprint: String) {
        lock.withLock {
            captured = fingerprint
        }
    }
}

private final class DiagnosticHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let server: ServerRecord
    private let capture: HostKeyFingerprintCapture

    init(server: ServerRecord, capture: HostKeyFingerprintCapture) {
        self.server = server
        self.capture = capture
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = sshHostKeyFingerprint(hostKey)
        capture.save(fingerprint)
        if let pinned = SSHHostKeyPinStore.fingerprint(serverID: server.id, legacyHost: server.host, legacyPort: server.port),
           pinned != fingerprint {
            validationCompletePromise.fail(SSHServiceError.hostKeyChanged(server.host, server.port))
            return
        }
        validationCompletePromise.succeed(())
    }
}

private func uploadViaShell(data: Data, remotePath: String, client: SSHClient) async throws {
    let encoded = data.base64EncodedString()
    let command = "printf %s \(encoded.shellQuotedForRemoteCommand()) | base64 -d > \(remotePath.shellQuotedForRemoteCommand())"
    let result = try await client.executeCommand(command, maxResponseSize: 16_384, mergeStreams: true, inShell: true)
    let output = String(buffer: result).trimmingCharacters(in: .whitespacesAndNewlines)
    if !output.isEmpty {
        throw SSHServiceError.connectionClosed("uploading an attachment: \(output)")
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    func shellQuotedForRemoteCommand() -> String {
        "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private struct TerminalSize: Sendable {
    var columns: Int
    var rows: Int
}

private final class CitadelTerminalSession: RemoteTerminalSession, @unchecked Sendable {
    let output: AsyncThrowingStream<Data, Error>

    private let client: SSHClient
    private let ready = ReadySignal()
    private let outputContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let inputBytes: AsyncStream<Data>
    private let inputContinuation: AsyncStream<Data>.Continuation
    private let resizeRequests: AsyncStream<TerminalSize>
    private let resizeContinuation: AsyncStream<TerminalSize>.Continuation
    private var task: Task<Void, Never>?

    private init(client: SSHClient) {
        self.client = client

        let output = AsyncThrowingStream<Data, Error>.makeStream()
        self.output = output.stream
        outputContinuation = output.continuation

        let input = AsyncStream<Data>.makeStream()
        inputBytes = input.stream
        inputContinuation = input.continuation

        let resize = AsyncStream<TerminalSize>.makeStream()
        resizeRequests = resize.stream
        resizeContinuation = resize.continuation
    }

    static func open(client: SSHClient, cwd: String?, columns: Int, rows: Int) async throws -> CitadelTerminalSession {
        let session = CitadelTerminalSession(client: client)
        let ready = session.ready
        let outputContinuation = session.outputContinuation
        let inputBytes = session.inputBytes
        let inputContinuation = session.inputContinuation
        let resizeRequests = session.resizeRequests
        let resizeContinuation = session.resizeContinuation

        session.task = Task {
            do {
                try await client.withPTY(
                    SSHChannelRequestEvent.PseudoTerminalRequest(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: columns,
                        terminalRowHeight: rows,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: .init([.ECHO: 1])
                    )
                ) { inbound, outbound in
                    await ready.succeed()
                    if let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                        try await outbound.write(ByteBuffer(string: "cd \(cwd.shellQuotedForRemoteCommand())\n"))
                    }

                    let writer = Task {
                        do {
                            for await data in inputBytes {
                                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                                buffer.writeBytes(data)
                                try await outbound.write(buffer)
                            }
                        } catch {
                            inputContinuation.finish()
                            outputContinuation.finish(throwing: error)
                        }
                    }
                    let resizer = Task {
                        do {
                            for await size in resizeRequests {
                                try await outbound.changeSize(cols: size.columns, rows: size.rows, pixelWidth: 0, pixelHeight: 0)
                            }
                        } catch {
                            resizeContinuation.finish()
                        }
                    }
                    defer {
                        writer.cancel()
                        resizer.cancel()
                    }

                    for try await output in inbound {
                        var buffer: ByteBuffer
                        switch output {
                        case .stdout(let stdout):
                            buffer = stdout
                        case .stderr(let stderr):
                            buffer = stderr
                        }
                        if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
                            outputContinuation.yield(Data(bytes))
                        }
                    }
                    inputContinuation.finish()
                    resizeContinuation.finish()
                    outputContinuation.finish()
                }
            } catch {
                await ready.fail(error)
                inputContinuation.finish()
                resizeContinuation.finish()
                outputContinuation.finish(throwing: error)
            }
            try? await client.close()
        }

        do {
            try await withTaskCancellationHandler {
                try await session.ready.wait()
            } onCancel: {
                Task {
                    await session.close()
                }
            }
        } catch {
            await session.close()
            throw error
        }
        return session
    }

    func write(_ data: Data) async throws {
        inputContinuation.yield(data)
    }

    func resize(columns: Int, rows: Int) async throws {
        resizeContinuation.yield(TerminalSize(columns: columns, rows: rows))
    }

    func close() async {
        inputContinuation.finish()
        resizeContinuation.finish()
        task?.cancel()
        try? await client.close()
        outputContinuation.finish()
    }
}

private final class PinnedHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let serverID: UUID
    private let host: String
    private let port: Int

    init(server: ServerRecord) {
        serverID = server.id
        host = server.host
        port = server.port
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = sshHostKeyFingerprint(hostKey)
        if let pinned = SSHHostKeyPinStore.fingerprint(serverID: serverID, legacyHost: host, legacyPort: port) {
            if pinned == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(SSHServiceError.hostKeyChanged(host, port))
            }
            return
        }

        SSHHostKeyPinStore.save(fingerprint, serverID: serverID)
        validationCompletePromise.succeed(())
    }
}

enum SSHHostKeyPinStore {
    private static let lock = NSLock()

    static func fingerprint(serverID: UUID, legacyHost: String, legacyPort: Int) -> String? {
        let key = pinKey(serverID: serverID)
        let legacyKey = legacyPinKey(serverID: serverID, host: legacyHost, port: legacyPort)
        return lock.withLock { () -> String? in
            if let fingerprint = UserDefaults.standard.string(forKey: key) {
                return fingerprint
            }
            guard let fingerprint = UserDefaults.standard.string(forKey: legacyKey) else {
                return nil
            }
            UserDefaults.standard.set(fingerprint, forKey: key)
            return fingerprint
        }
    }

    static func save(_ fingerprint: String, serverID: UUID) {
        lock.withLock {
            UserDefaults.standard.set(fingerprint, forKey: pinKey(serverID: serverID))
        }
    }

    static func migrateLegacyEndpointPin(serverID: UUID, host: String, port: Int) {
        let key = pinKey(serverID: serverID)
        let legacyKey = legacyPinKey(serverID: serverID, host: host, port: port)
        lock.withLock {
            guard UserDefaults.standard.string(forKey: key) == nil,
                  let fingerprint = UserDefaults.standard.string(forKey: legacyKey)
            else {
                return
            }
            UserDefaults.standard.set(fingerprint, forKey: key)
        }
    }

    static func clear(serverID: UUID, legacyHost: String? = nil, legacyPort: Int? = nil) {
        lock.withLock {
            UserDefaults.standard.removeObject(forKey: pinKey(serverID: serverID))
            if let legacyHost, let legacyPort {
                UserDefaults.standard.removeObject(
                    forKey: legacyPinKey(serverID: serverID, host: legacyHost, port: legacyPort)
                )
            }
        }
    }

    private static func pinKey(serverID: UUID) -> String {
        "mobidex.sshHostKey.\(serverID.uuidString)"
    }

    private static func legacyPinKey(serverID: UUID, host: String, port: Int) -> String {
        "mobidex.sshHostKey.\(serverID.uuidString).\(host).\(port)"
    }
}

private func sshHostKeyFingerprint(_ hostKey: NIOSSHPublicKey) -> String {
    var buffer = ByteBufferAllocator().buffer(capacity: 512)
    hostKey.write(to: &buffer)
    let digest = SHA256.hash(data: Data(buffer.readableBytesView))
    return "SHA256:" + Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
}

private func sanitizedFilename(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let scalars = value.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "_"
    }
    let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    return sanitized.isEmpty ? "attachment" : sanitized
}

private func resolveAddresses(host: String, port: Int) throws -> [String] {
    var hints = addrinfo(
        ai_flags: AI_ADDRCONFIG,
        ai_family: AF_UNSPEC,
        ai_socktype: SOCK_STREAM,
        ai_protocol: IPPROTO_TCP,
        ai_addrlen: 0,
        ai_canonname: nil,
        ai_addr: nil,
        ai_next: nil
    )
    var info: UnsafeMutablePointer<addrinfo>?
    let code = getaddrinfo(host, "\(port)", &hints, &info)
    guard code == 0, let info else {
        throw POSIXError(POSIXErrorCode(rawValue: code == EAI_SYSTEM ? errno : code) ?? .EIO)
    }
    defer { freeaddrinfo(info) }

    var addresses: [String] = []
    var cursor: UnsafeMutablePointer<addrinfo>? = info
    while let current = cursor {
        if let address = numericAddress(from: current.pointee.ai_addr) {
            addresses.append(address)
        }
        cursor = current.pointee.ai_next
    }
    return Array(NSOrderedSet(array: addresses)) as? [String] ?? addresses
}

private func numericAddress(from sockaddrPointer: UnsafeMutablePointer<sockaddr>?) -> String? {
    guard let sockaddrPointer else { return nil }
    let family = Int32(sockaddrPointer.pointee.sa_family)
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let result = getnameinfo(
        sockaddrPointer,
        socklen_t(sockaddrPointer.pointee.sa_len),
        &host,
        socklen_t(host.count),
        nil,
        0,
        NI_NUMERICHOST
    )
    guard result == 0 else { return nil }
    let value = host.withUnsafeBufferPointer { buffer in
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    return family == AF_INET6 ? "[\(value)]" : value
}

private func tcpProbe(address: String, port: Int, timeoutMilliseconds: Int32) -> String {
    let host = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    var hints = addrinfo(
        ai_flags: AI_NUMERICHOST,
        ai_family: AF_UNSPEC,
        ai_socktype: SOCK_STREAM,
        ai_protocol: IPPROTO_TCP,
        ai_addrlen: 0,
        ai_canonname: nil,
        ai_addr: nil,
        ai_next: nil
    )
    var info: UnsafeMutablePointer<addrinfo>?
    let lookup = getaddrinfo(host, "\(port)", &hints, &info)
    guard lookup == 0, let info else {
        return "address parse failed: \(lookup)"
    }
    defer { freeaddrinfo(info) }

    let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
    guard fd >= 0 else {
        return "socket failed: errno \(errno)"
    }
    defer { close(fd) }

    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    let connectResult = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
    if connectResult == 0 {
        return "connected"
    }
    guard errno == EINPROGRESS else {
        return "connect failed: errno \(errno)"
    }

    var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    let selected = poll(&pollDescriptor, 1, timeoutMilliseconds)
    if selected == 0 {
        return "timed out"
    }
    if selected < 0 {
        return "poll failed: errno \(errno)"
    }

    var socketError: Int32 = 0
    var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
    guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength) == 0 else {
        return "getsockopt failed: errno \(errno)"
    }
    return socketError == 0 ? "connected" : "connect failed: errno \(socketError)"
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
    if let connectionError = error as? NIOConnectionError {
        let details = connectionFailureDetails(connectionError)
        if details.localizedCaseInsensitiveContains("operation not permitted")
            || details.localizedCaseInsensitiveContains("errno: 1")
            || details.localizedCaseInsensitiveContains("error 1") {
            return SSHServiceError.localNetworkPermissionDenied(server.host, server.port, details)
        }
        return SSHServiceError.connectionFailed(server.host, server.port, details)
    }
    return error
}

private func connectionFailureDetails(_ error: NIOConnectionError) -> String {
    if !error.connectionErrors.isEmpty {
        return error.connectionErrors
            .map { "\($0.target): \(String(describing: $0.error))" }
            .joined(separator: "; ")
    }
    if let dnsAError = error.dnsAError, let dnsAAAAError = error.dnsAAAAError {
        return "DNS lookup failed: A \(String(describing: dnsAError)); AAAA \(String(describing: dnsAAAAError))"
    }
    if let dnsError = error.dnsAError ?? error.dnsAAAAError {
        return "DNS lookup failed: \(String(describing: dnsError))"
    }
    return String(describing: error)
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

private func diagnosticStage(for mapped: Error, fallback: Error) -> String {
    if mapped is AuthenticationFailed {
        return "auth"
    }
    if let serviceError = mapped as? SSHServiceError {
        switch serviceError {
        case .authenticationFailed, .missingPassword, .missingPrivateKey, .unsupportedPrivateKey:
            return "auth"
        case .connectionTimedOut, .hostUnreachable, .localNetworkPermissionDenied, .connectionFailed:
            return "TCP"
        case .hostKeyChanged:
            return "SSH handshake"
        case .connectionClosed:
            return "SSH handshake"
        case .appServerClosed:
            return "app-server"
        case .transportClosed, .invalidDiscoveryOutput, .remoteDirectoryBrowseFailed, .localFileNotReadable:
            return "remote command"
        }
    }
    if fallback is NIOConnectionError {
        return "TCP"
    }
    if fallback is SSHClientError {
        return "auth"
    }
    return "SSH handshake"
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
