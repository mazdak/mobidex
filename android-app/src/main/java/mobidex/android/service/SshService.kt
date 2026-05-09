package mobidex.android.service

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.StringReader
import java.security.MessageDigest
import java.security.PublicKey
import java.security.SecureRandom
import java.security.Security
import java.util.Base64
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.withContext
import mobidex.android.data.HostKeyStore
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerRecord
import mobidex.shared.RemoteCodexDiscovery
import mobidex.shared.RemoteDirectoryBrowser
import mobidex.shared.RemoteDirectoryListing
import mobidex.shared.RemoteProject
import mobidex.shared.WebSocketFrameCodec
import mobidex.shared.WebSocketFrameParser
import mobidex.shared.WebSocketMessageAssembler
import mobidex.shared.WebSocketOpcode
import net.schmizz.sshj.AndroidConfig
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.common.IOUtils
import net.schmizz.sshj.connection.channel.direct.PTYMode
import net.schmizz.sshj.connection.channel.direct.Session
import net.schmizz.sshj.transport.verification.HostKeyVerifier
import net.schmizz.sshj.userauth.keyprovider.OpenSSHKeyFile
import net.schmizz.sshj.userauth.password.PasswordUtils
import org.bouncycastle.jce.provider.BouncyCastleProvider

interface MobidexSshService {
    suspend fun testConnection(server: ServerRecord, credential: SSHCredential)
    suspend fun discoverProjects(server: ServerRecord, credential: SSHCredential): List<RemoteProject>
    suspend fun listDirectories(path: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing
    suspend fun stageLocalFiles(localPaths: List<String>, server: ServerRecord, credential: SSHCredential): List<String>
    suspend fun openAppServer(server: ServerRecord, credential: SSHCredential): CodexAppServerClient
    suspend fun openTerminal(cwd: String?, columns: Int, rows: Int, server: ServerRecord, credential: SSHCredential): RemoteTerminalSession
}

interface RemoteTerminalSession {
    val output: Flow<String>
    suspend fun write(text: String)
    suspend fun resize(columns: Int, rows: Int)
    suspend fun close()
}

class SshjMobidexSshService(private val hostKeyStore: HostKeyStore) : MobidexSshService {
    override suspend fun testConnection(server: ServerRecord, credential: SSHCredential) {
        withClient(server, credential) { client ->
            client.execString("printf mobidex-ready")
        }
    }

    override suspend fun discoverProjects(server: ServerRecord, credential: SSHCredential): List<RemoteProject> =
        withClient(server, credential) { client ->
            RemoteCodexDiscovery.decodeProjects(
                client.execString(RemoteCodexDiscovery.shellCommand(targetShellRCFile = server.targetShellRCFile))
            )
        }

    override suspend fun listDirectories(path: String, server: ServerRecord, credential: SSHCredential): RemoteDirectoryListing =
        withClient(server, credential) { client ->
            RemoteDirectoryBrowser.decodeListing(client.execString(RemoteDirectoryBrowser.shellCommand(path)))
        }

    override suspend fun stageLocalFiles(localPaths: List<String>, server: ServerRecord, credential: SSHCredential): List<String> =
        withClient(server, credential) { client ->
            if (localPaths.isEmpty()) return@withClient emptyList()
            val remoteDirectory = client.execString("""mkdir -p "${'$'}HOME/.mobidex/uploads" && mktemp -d "${'$'}HOME/.mobidex/uploads/mobidex.XXXXXX"""")
                .trim()
                .ifEmpty { error("Could not create remote upload directory.") }
            client.newSFTPClient().use { sftp ->
                localPaths.map { localPath ->
                    val localFile = File(localPath)
                    require(localFile.canRead()) { "Could not read ${localFile.path}." }
                    val remotePath = "$remoteDirectory/${UUID.randomUUID()}-${localFile.name.sanitizedFilename()}"
                    sftp.put(localFile.absolutePath, remotePath)
                    remotePath
                }
            }
        }

    override suspend fun openAppServer(server: ServerRecord, credential: SSHCredential): CodexAppServerClient =
        withContext(Dispatchers.IO) {
            val client = connect(server, credential)
            try {
                val session = client.startSession()
                val command = session.exec(server.appServerProxyCommand)
                val transport = SshjWebSocketProxyTransport.open(client, session, command)
                CodexAppServerClient(transport).also { it.initialize() }
            } catch (error: Throwable) {
                client.close()
                throw error
            }
        }

    override suspend fun openTerminal(cwd: String?, columns: Int, rows: Int, server: ServerRecord, credential: SSHCredential): RemoteTerminalSession {
        val openedTerminal = AtomicReference<SshjRemoteTerminalSession?>()
        return try {
            val terminal = withContext(Dispatchers.IO) {
                var client: SSHClient? = null
                var session: Session? = null
                try {
                    currentCoroutineContext().ensureActive()
                    val connectedClient = connect(server, credential)
                    client = connectedClient
                    currentCoroutineContext().ensureActive()
                    val sshSession = connectedClient.startSession()
                    session = sshSession
                    sshSession.allocatePTY("xterm-256color", columns, rows, 0, 0, emptyMap<PTYMode, Int>())
                    currentCoroutineContext().ensureActive()
                    val shell = sshSession.startShell()
                    currentCoroutineContext().ensureActive()
                    val terminal = SshjRemoteTerminalSession(connectedClient, sshSession, shell)
                    openedTerminal.set(terminal)
                    cwd?.trim()?.takeIf { it.isNotEmpty() }?.let {
                        terminal.write("cd ${it.shellQuoted()}\n")
                    }
                    currentCoroutineContext().ensureActive()
                    session = null
                    client = null
                    terminal
                } catch (error: Throwable) {
                    openedTerminal.getAndSet(null)?.closeBlocking()
                        ?: run {
                            runCatching { session?.close() }
                            runCatching { client?.close() }
                        }
                    throw error
                }
            }
            openedTerminal.set(null)
            terminal
        } catch (error: Throwable) {
            openedTerminal.getAndSet(null)?.closeBlocking()
            throw error
        }
    }

    private suspend fun <T> withClient(
        server: ServerRecord,
        credential: SSHCredential,
        block: (SSHClient) -> T,
    ): T = withContext(Dispatchers.IO) {
        connect(server, credential).use { block(it) }
    }

    private fun connect(server: ServerRecord, credential: SSHCredential): SSHClient {
        installBouncyCastleProvider()
        val client = SSHClient(androidCompatibleSshConfig())
        try {
            client.addHostKeyVerifier(PinnedHostKeyVerifier(server, hostKeyStore))
            client.connect(server.host, server.port)
            when (server.authMethod) {
                ServerAuthMethod.Password -> {
                    val password = credential.password?.takeIf { it.isNotEmpty() } ?: error("Enter the SSH password for this server.")
                    client.authPassword(server.username, password)
                }
                ServerAuthMethod.PrivateKey -> {
                    val key = credential.privateKeyPEM?.takeIf { it.isNotBlank() } ?: error("Paste an OpenSSH private key for this server.")
                    val keyFile = OpenSSHKeyFile()
                    val passphrase = credential.privateKeyPassphrase?.takeIf { it.isNotEmpty() }
                    StringReader(key).use { reader ->
                        keyFile.init(reader, null, passphrase?.let { PasswordUtils.createOneOff(it.toCharArray()) })
                    }
                    client.authPublickey(server.username, keyFile)
                }
            }
            return client
        } catch (error: Throwable) {
            runCatching { client.close() }
            throw error
        }
    }

    private fun androidCompatibleSshConfig(): AndroidConfig =
        AndroidConfig().apply {
            keyExchangeFactories = keyExchangeFactories.filterNot { factory ->
                factory.name.contains("sntrup", ignoreCase = true)
            }
        }
}

private val bouncyCastleInstallLock = Any()

private fun installBouncyCastleProvider() {
    synchronized(bouncyCastleInstallLock) {
        val providerName = BouncyCastleProvider.PROVIDER_NAME
        val provider = Security.getProvider(providerName)
        if (provider?.javaClass?.name == BouncyCastleProvider::class.java.name) {
            return
        }

        val position = Security.getProviders().indexOfFirst { it.name == providerName }
            .takeIf { it >= 0 }
            ?.plus(1)
            ?: Security.getProviders().size.plus(1)
        if (provider != null) {
            Security.removeProvider(providerName)
        }
        Security.insertProviderAt(BouncyCastleProvider(), position)
    }
}

private class PinnedHostKeyVerifier(
    private val server: ServerRecord,
    private val hostKeyStore: HostKeyStore,
) : HostKeyVerifier {
    override fun verify(hostname: String, port: Int, key: PublicKey): Boolean {
        val fingerprint = key.sha256Fingerprint()
        val trusted = hostKeyStore.loadHostKeyFingerprint(server.id)
        if (trusted == null) {
            hostKeyStore.saveHostKeyFingerprint(server.id, hostname, port, fingerprint)
            return true
        }
        if (trusted == fingerprint) return true
        throw IllegalStateException(
            "SSH host key for ${server.host}:${server.port} changed. Remove and re-add the server if this change is expected.",
        )
    }

    override fun findExistingAlgorithms(hostname: String, port: Int): List<String> = emptyList()
}

private fun PublicKey.sha256Fingerprint(): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(encoded)
    return "SHA256:${Base64.getEncoder().withoutPadding().encodeToString(digest)}"
}

private class SshjWebSocketProxyTransport private constructor(
    private val client: SSHClient,
    private val session: Session,
    private val command: Session.Command,
) : CodexLineTransport {
    private val inboundChannel = Channel<String>(Channel.BUFFERED)

    override val inboundLines: Flow<String> = inboundChannel.receiveAsFlow()

    companion object {
        fun open(client: SSHClient, session: Session, command: Session.Command): SshjWebSocketProxyTransport {
            val transport = SshjWebSocketProxyTransport(client, session, command)
            transport.startStderrDrainer()
            try {
                val key = webSocketKey()
                command.outputStream.write(upgradeRequest(key))
                command.outputStream.flush()
                val response = CompletableFuture.supplyAsync { readUpgradeResponse(command.inputStream) }
                    .get(15, TimeUnit.SECONDS)
                validateUpgradeResponse(response.headers, key)
                transport.startReader(response.leftover)
                return transport
            } catch (error: Throwable) {
                transport.closeBlocking()
                throw error
            }
        }

        private fun upgradeRequest(key: String): ByteArray =
            listOf(
                "GET / HTTP/1.1",
                "Host: localhost",
                "Upgrade: websocket",
                "Connection: Upgrade",
                "Sec-WebSocket-Key: $key",
                "Sec-WebSocket-Version: 13",
                "",
                "",
            ).joinToString("\r\n").toByteArray(Charsets.UTF_8)

        private fun webSocketKey(): String {
            val bytes = ByteArray(16)
            secureRandom.nextBytes(bytes)
            return Base64.getEncoder().encodeToString(bytes)
        }

        private fun readUpgradeResponse(input: InputStream): UpgradeResponse {
            val buffer = ByteArrayOutputStream()
            while (true) {
                val next = input.read()
                if (next < 0) error("The app-server proxy closed before websocket upgrade completed.")
                buffer.write(next)
                val bytes = buffer.toByteArray()
                if (bytes.endsWith(httpHeaderSeparator)) {
                    return UpgradeResponse(String(bytes, Charsets.UTF_8), ByteArray(0))
                }
                if (bytes.size > 65_536) error("The app-server websocket upgrade response was too large.")
            }
        }

        private fun validateUpgradeResponse(headers: String, key: String) {
            val lines = headers.split("\r\n")
            val statusLine = lines.firstOrNull().orEmpty()
            require(statusLine.contains(" 101 ") || statusLine.endsWith(" 101")) {
                "The app-server websocket upgrade failed: ${statusLine.ifEmpty { "missing status line" }}"
            }
            val fields = lines.drop(1)
                .mapNotNull { line ->
                    val separator = line.indexOf(':')
                    if (separator < 0) return@mapNotNull null
                    line.substring(0, separator).trim().lowercase(Locale.US) to line.substring(separator + 1).trim()
                }
                .toMap()
            require(fields["upgrade"]?.lowercase(Locale.US) == "websocket") {
                "The app-server websocket upgrade response was missing the Upgrade header."
            }
            val connectionValues = fields["connection"]
                ?.lowercase(Locale.US)
                ?.split(',')
                ?.map { it.trim() }
                .orEmpty()
            require("upgrade" in connectionValues) {
                "The app-server websocket upgrade response was missing the Connection header."
            }
            require(fields["sec-websocket-accept"] == expectedAccept(key)) {
                "The app-server websocket upgrade response had an invalid Sec-WebSocket-Accept header."
            }
        }

        private fun expectedAccept(key: String): String {
            val digest = MessageDigest.getInstance("SHA-1")
                .digest("$key$webSocketGuid".toByteArray(Charsets.UTF_8))
            return Base64.getEncoder().encodeToString(digest)
        }

        private val secureRandom = SecureRandom()
        private val httpHeaderSeparator = byteArrayOf(13, 10, 13, 10)
        private const val webSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    }

    private fun startReader(initialData: ByteArray) {
        Thread {
            val parser = WebSocketFrameParser(requireUnmasked = true)
            val assembler = WebSocketMessageAssembler()
            try {
                parser.append(initialData)
                while (true) {
                    while (true) {
                        val frame = parser.nextFrame() ?: break
                        when (frame.opcode) {
                            WebSocketOpcode.Text, WebSocketOpcode.Binary, WebSocketOpcode.Continuation -> {
                                assembler.append(frame)?.let { message ->
                                    inboundChannel.trySend(String(message, Charsets.UTF_8))
                                }
                            }
                            WebSocketOpcode.Ping -> writeFrame(WebSocketOpcode.Pong, frame.payload)
                            WebSocketOpcode.Pong -> Unit
                            WebSocketOpcode.Close -> {
                                inboundChannel.close()
                                return@Thread
                            }
                            else -> error("Received unsupported websocket opcode ${frame.opcode}.")
                        }
                    }
                    val chunk = ByteArray(8_192)
                    val read = command.inputStream.read(chunk)
                    if (read < 0) break
                    parser.append(chunk.copyOf(read))
                }
            } catch (error: Throwable) {
                inboundChannel.close(error)
                return@Thread
            }
            inboundChannel.close()
        }.apply {
            name = "mobidex-app-server-websocket-reader"
            isDaemon = true
            start()
        }
    }

    private fun startStderrDrainer() {
        Thread {
            runCatching { IOUtils.readFully(command.errorStream) }
        }.apply {
            name = "mobidex-app-server-stderr-drainer"
            isDaemon = true
            start()
        }
    }

    override suspend fun sendLine(line: String) = withContext(Dispatchers.IO) {
        writeFrame(WebSocketOpcode.Text, line.toByteArray(Charsets.UTF_8))
    }

    override suspend fun close(): Unit = withContext(Dispatchers.IO) {
        runCatching { writeFrame(WebSocketOpcode.Close, ByteArray(0)) }
        closeBlocking()
        Unit
    }

    private fun writeFrame(opcode: Int, payload: ByteArray) {
        val mask = ByteArray(4)
        secureRandom.nextBytes(mask)
        val frame = WebSocketFrameCodec.encodeClientFrame(opcode, payload, mask)
        synchronized(command.outputStream) {
            command.outputStream.write(frame)
            command.outputStream.flush()
        }
    }

    private fun closeBlocking() {
        runCatching { command.close() }
        runCatching { command.join(1, TimeUnit.SECONDS) }
        runCatching { session.close() }
        runCatching { client.close() }
        inboundChannel.close()
    }
}

private class SshjRemoteTerminalSession(
    private val client: SSHClient,
    private val session: Session,
    private val shell: Session.Shell,
) : RemoteTerminalSession {
    private val outputChannel = Channel<String>(Channel.BUFFERED)
    private val readersRemaining = AtomicInteger(2)

    override val output: Flow<String> = outputChannel.receiveAsFlow()

    init {
        startReader(shell.inputStream, "mobidex-terminal-stdout")
        startReader(shell.errorStream, "mobidex-terminal-stderr")
    }

    override suspend fun write(text: String): Unit = withContext(Dispatchers.IO) {
        synchronized(shell.outputStream) {
            shell.outputStream.write(text.toByteArray(Charsets.UTF_8))
            shell.outputStream.flush()
        }
    }

    override suspend fun resize(columns: Int, rows: Int): Unit = withContext(Dispatchers.IO) {
        shell.changeWindowDimensions(columns, rows, 0, 0)
    }

    override suspend fun close(): Unit = withContext(Dispatchers.IO) {
        closeBlocking()
    }

    private fun startReader(input: InputStream, name: String) {
        Thread {
            val buffer = ByteArray(8_192)
            try {
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read > 0) {
                        outputChannel.trySend(String(buffer, 0, read, Charsets.UTF_8))
                    }
                }
            } catch (error: Throwable) {
                outputChannel.close(error)
                return@Thread
            }
            if (readersRemaining.decrementAndGet() == 0) {
                outputChannel.close()
            }
        }.apply {
            this.name = name
            isDaemon = true
            start()
        }
    }

    fun closeBlocking() {
        runCatching { shell.close() }
        runCatching { shell.join(1, TimeUnit.SECONDS) }
        runCatching { session.close() }
        runCatching { client.close() }
        outputChannel.close()
    }
}

private data class UpgradeResponse(val headers: String, val leftover: ByteArray)

private fun ByteArray.endsWith(suffix: ByteArray): Boolean {
    if (size < suffix.size) return false
    return suffix.indices.all { index -> this[size - suffix.size + index] == suffix[index] }
}

private fun SSHClient.execString(command: String): String =
    startSession().use { session ->
        val cmd = session.exec(command)
        val output = cmd.inputStream.readFullyAsync()
        val error = cmd.errorStream.readFullyAsync()
        cmd.join(45, TimeUnit.SECONDS)
        if (cmd.isOpen) {
            runCatching { cmd.close() }
            throw IllegalStateException("Remote command timed out after 45 seconds.")
        }
        val outputText = output.get(2, TimeUnit.SECONDS)
        val errorText = error.get(2, TimeUnit.SECONDS)
        if (cmd.exitStatus != 0) {
            throw IllegalStateException(errorText.ifBlank { "Remote command failed with exit ${cmd.exitStatus}." })
        }
        outputText
    }

private fun java.io.InputStream.readFullyAsync(): CompletableFuture<String> =
    CompletableFuture.supplyAsync { IOUtils.readFully(this).toString(Charsets.UTF_8) }

private fun String.sanitizedFilename(): String {
    val sanitized = map { if (it.isLetterOrDigit() || it in "._-") it else '_' }.joinToString("")
        .trim('.', '_', '-')
    return sanitized.ifEmpty { "attachment" }
}

private fun String.shellQuoted(): String =
    "'${replace("'", "'\"'\"'")}'"
