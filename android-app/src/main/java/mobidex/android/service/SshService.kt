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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.withContext
import mobidex.android.data.HostKeyStore
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerRecord
import net.schmizz.sshj.AndroidConfig
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.common.IOUtils
import net.schmizz.sshj.connection.channel.direct.Session
import net.schmizz.sshj.transport.verification.HostKeyVerifier
import net.schmizz.sshj.userauth.keyprovider.OpenSSHKeyFile
import net.schmizz.sshj.userauth.password.PasswordUtils
import org.bouncycastle.jce.provider.BouncyCastleProvider

interface MobidexSshService {
    suspend fun testConnection(server: ServerRecord, credential: SSHCredential)
    suspend fun stageLocalFiles(localPaths: List<String>, server: ServerRecord, credential: SSHCredential): List<String>
    suspend fun openAppServer(server: ServerRecord, credential: SSHCredential): CodexAppServerClient
}

class SshjMobidexSshService(private val hostKeyStore: HostKeyStore) : MobidexSshService {
    override suspend fun testConnection(server: ServerRecord, credential: SSHCredential) {
        withClient(server, credential) { client ->
            client.execString("printf mobidex-ready")
        }
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
        private const val opcodeContinuation = 0x0
        private const val opcodeText = 0x1
        private const val opcodeBinary = 0x2
        private const val opcodeClose = 0x8
        private const val opcodePing = 0x9
        private const val opcodePong = 0xA
    }

    private fun startReader(initialData: ByteArray) {
        Thread {
            var buffer = initialData
            var fragmentedPayload: ByteArrayOutputStream? = null
            try {
                while (true) {
                    val chunk = ByteArray(8_192)
                    val read = command.inputStream.read(chunk)
                    if (read < 0) break
                    buffer += chunk.copyOf(read)
                    while (true) {
                        val result = parseWebSocketFrame(buffer) ?: break
                        buffer = result.remaining
                        when (result.frame.opcode) {
                            opcodeText, opcodeBinary -> {
                                if (result.frame.fin) {
                                    inboundChannel.trySend(String(result.frame.payload, Charsets.UTF_8))
                                } else {
                                    fragmentedPayload = ByteArrayOutputStream().apply { write(result.frame.payload) }
                                }
                            }
                            opcodeContinuation -> {
                                val payload = fragmentedPayload ?: error("Received websocket continuation without an initial frame.")
                                payload.write(result.frame.payload)
                                if (result.frame.fin) {
                                    inboundChannel.trySend(String(payload.toByteArray(), Charsets.UTF_8))
                                    fragmentedPayload = null
                                }
                            }
                            opcodePing -> writeFrame(opcodePong, result.frame.payload)
                            opcodePong -> Unit
                            opcodeClose -> {
                                inboundChannel.close()
                                return@Thread
                            }
                            else -> error("Received unsupported websocket opcode ${result.frame.opcode}.")
                        }
                    }
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
        writeFrame(opcodeText, line.toByteArray(Charsets.UTF_8))
    }

    override suspend fun close(): Unit = withContext(Dispatchers.IO) {
        runCatching { writeFrame(opcodeClose, ByteArray(0)) }
        closeBlocking()
        Unit
    }

    private fun writeFrame(opcode: Int, payload: ByteArray) {
        val frame = encodeWebSocketFrame(opcode, payload)
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

private data class UpgradeResponse(val headers: String, val leftover: ByteArray)

internal data class WebSocketFrame(val fin: Boolean, val opcode: Int, val payload: ByteArray)

internal data class WebSocketFrameParseResult(val frame: WebSocketFrame, val remaining: ByteArray)

internal fun parseWebSocketFrame(buffer: ByteArray): WebSocketFrameParseResult? {
    if (buffer.size < 2) return null
    val first = buffer[0].toInt() and 0xFF
    val second = buffer[1].toInt() and 0xFF
    val fin = first and 0x80 != 0
    val opcode = first and 0x0F
    var offset = 2
    var length = second and 0x7F
    if (length == 126) {
        if (buffer.size < 4) return null
        length = ((buffer[2].toInt() and 0xFF) shl 8) or (buffer[3].toInt() and 0xFF)
        offset = 4
    } else if (length == 127) {
        if (buffer.size < 10) return null
        var length64 = 0L
        for (index in 0 until 8) {
            length64 = (length64 shl 8) or (buffer[2 + index].toLong() and 0xFF)
        }
        require(length64 <= Int.MAX_VALUE) { "Websocket frame payload is too large." }
        length = length64.toInt()
        offset = 10
    }
    val masked = second and 0x80 != 0
    val mask = if (masked) {
        if (buffer.size < offset + 4) return null
        buffer.copyOfRange(offset, offset + 4).also { offset += 4 }
    } else {
        ByteArray(0)
    }
    if (buffer.size < offset + length) return null
    val payload = buffer.copyOfRange(offset, offset + length)
    if (masked) {
        for (index in payload.indices) {
            payload[index] = ((payload[index].toInt() and 0xFF) xor (mask[index % 4].toInt() and 0xFF)).toByte()
        }
    }
    return WebSocketFrameParseResult(
        frame = WebSocketFrame(fin = fin, opcode = opcode, payload = payload),
        remaining = buffer.copyOfRange(offset + length, buffer.size),
    )
}

internal fun encodeWebSocketFrame(opcode: Int, payload: ByteArray): ByteArray {
    val output = ByteArrayOutputStream()
    output.write(0x80 or opcode)
    val mask = ByteArray(4)
    frameMaskRandom.nextBytes(mask)
    when {
        payload.size < 126 -> output.write(0x80 or payload.size)
        payload.size <= UShort.MAX_VALUE.toInt() -> {
            output.write(0x80 or 126)
            output.write((payload.size shr 8) and 0xFF)
            output.write(payload.size and 0xFF)
        }
        else -> {
            output.write(0x80 or 127)
            val length = payload.size.toLong()
            for (shift in 56 downTo 0 step 8) {
                output.write(((length shr shift) and 0xFF).toInt())
            }
        }
    }
    output.write(mask)
    payload.forEachIndexed { index, byte ->
        output.write((byte.toInt() and 0xFF) xor (mask[index % 4].toInt() and 0xFF))
    }
    return output.toByteArray()
}

private fun ByteArray.endsWith(suffix: ByteArray): Boolean {
    if (size < suffix.size) return false
    return suffix.indices.all { index -> this[size - suffix.size + index] == suffix[index] }
}

private val frameMaskRandom = SecureRandom()

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
