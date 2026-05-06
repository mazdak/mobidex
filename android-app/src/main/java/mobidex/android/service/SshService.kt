package mobidex.android.service

import java.io.BufferedReader
import java.io.File
import java.io.StringReader
import java.security.MessageDigest
import java.security.PublicKey
import java.security.Security
import java.util.EnumSet
import java.util.Base64
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
import net.schmizz.sshj.sftp.OpenMode
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
                val command = session.exec(server.appServerCommand)
                val transport = SshjLineTransport(client, session, command)
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

private class SshjLineTransport(
    private val client: SSHClient,
    private val session: Session,
    private val command: Session.Command,
) : CodexLineTransport {
    private val inboundChannel = Channel<String>(Channel.BUFFERED)

    override val inboundLines: Flow<String> = inboundChannel.receiveAsFlow()

    init {
        Thread {
            try {
                BufferedReader(command.inputStream.reader()).useLines { lines ->
                    lines.forEach { inboundChannel.trySend(it) }
                }
            } catch (error: Throwable) {
                inboundChannel.close(error)
                return@Thread
            }
            inboundChannel.close()
        }.apply {
            name = "mobidex-app-server-reader"
            isDaemon = true
            start()
        }
        Thread {
            runCatching { IOUtils.readFully(command.errorStream) }
        }.apply {
            name = "mobidex-app-server-stderr-drainer"
            isDaemon = true
            start()
        }
    }

    override suspend fun sendLine(line: String) = withContext(Dispatchers.IO) {
        command.outputStream.write(line.toByteArray(Charsets.UTF_8))
        command.outputStream.write('\n'.code)
        command.outputStream.flush()
    }

    override suspend fun close(): Unit = withContext(Dispatchers.IO) {
        runCatching { command.close() }
        runCatching { command.join(1, TimeUnit.SECONDS) }
        runCatching { session.close() }
        runCatching { client.close() }
        inboundChannel.close()
        Unit
    }
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
