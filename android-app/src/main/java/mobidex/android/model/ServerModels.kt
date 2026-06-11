package mobidex.android.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames
import mobidex.shared.RemoteAcpCommand
import mobidex.shared.RemoteCodexAppServerCommand
import mobidex.shared.RemoteServerLaunchDefaults

@Serializable
enum class ServerAuthMethod(val label: String) {
    Password("Password"),
    PrivateKey("Private Key"),
}

@OptIn(ExperimentalSerializationApi::class)
@Serializable
enum class BackendType(val label: String, val detail: String) {
    CodexAppServer("Codex", "Uses codex app-server for Codex sessions."),
    // "AcpGrok" is the legacy stored value from pre-rename builds.
    @JsonNames("AcpGrok")
    Acp("ACP Agent", "Uses any ACP-compatible stdio agent command (Grok, Claude, ...)."),
}

@Serializable
data class ServerRecord(
    val id: String = UUID.randomUUID().toString(),
    val displayName: String,
    val host: String,
    val port: Int = 22,
    val username: String,
    val codexPath: String = RemoteServerLaunchDefaults.codexPath,
    val executionPath: String = RemoteServerLaunchDefaults.executionPath,
    val acpLaunchCommand: String = RemoteAcpCommand.defaultLaunchCommand,
    val authMethod: ServerAuthMethod,
    val projects: List<ProjectRecord> = emptyList(),
    val createdAtEpochSeconds: Long = Instant.now().epochSecond,
    val updatedAtEpochSeconds: Long = Instant.now().epochSecond,
    val backendType: BackendType = BackendType.CodexAppServer,
) {
    val endpointLabel: String
        get() = "$username@$host:$port"

    val normalized: ServerRecord
        get() {
            val launchConfig = RemoteServerLaunchDefaults.normalize(codexPath, executionPath)
            return copy(
                displayName = displayName.trim().ifEmpty { host.trim() },
                host = host.trim(),
                username = username.trim(),
                codexPath = launchConfig.codexPath,
                executionPath = launchConfig.executionPath,
                acpLaunchCommand = acpLaunchCommand.trim().ifEmpty { RemoteAcpCommand.defaultLaunchCommand },
                updatedAtEpochSeconds = Instant.now().epochSecond,
                backendType = backendType,
            )
        }

    val appServerProxyCommand: String
        get() = RemoteCodexAppServerCommand.proxyCommand(
            codexPath = codexPath,
            executionPath = executionPath,
        )
}

@Serializable
data class ProjectRecord(
    val id: String = UUID.randomUUID().toString(),
    val path: String,
    val sessionPaths: List<String> = listOf(path),
    val displayName: String = path.trimEnd('/').substringAfterLast('/').ifEmpty { path },
    val discovered: Boolean = false,
    val discoveredSessionCount: Int = 0,
    val archivedSessionCount: Int = 0,
    val activeChatCount: Int = 0,
    val lastDiscoveredAtEpochSeconds: Long? = null,
    val lastActiveChatAtEpochSeconds: Long? = null,
    val isAdded: Boolean = false,
) {
    val isSavedProject: Boolean
        get() = isAdded || !discovered

    val normalized: ProjectRecord
        get() = copy(sessionPaths = normalizedSessionPaths(sessionPaths, path))

    val macOSPrivacyWarning: String?
        get() = macOSPrivacyWarning(listOf(path) + sessionPaths)

    companion object {
        fun normalizedSessionPaths(paths: List<String>, primaryPath: String): List<String> =
            mobidex.shared.ProjectRecord.Companion.normalizedSessionPaths(paths, primaryPath)

        fun macOSPrivacyWarning(paths: List<String>): String? =
            if (paths.any(::isLikelyMacOSPrivacyProtectedPath)) {
                "macOS may block SSH access to this protected location. Move it outside protected folders or grant Full Disk Access to the SSH/Remote Login service."
            } else {
                null
            }

        private fun isLikelyMacOSPrivacyProtectedPath(path: String): Boolean {
            val components = path.split('/').filter { it.isNotEmpty() }
            if (components.firstOrNull() == "Volumes") return true
            if (components.size < 3 || components[0] != "Users") return false
            if (components[2] in setOf("Desktop", "Documents", "Downloads")) return true
            return components.size >= 4 &&
                components[2] == "Library" &&
                components[3] == "Mobile Documents"
        }
    }
}

data class SSHCredential(
    val password: String? = null,
    val privateKeyPEM: String? = null,
    val privateKeyPassphrase: String? = null,
)

enum class ServerConnectionState(val label: String) {
    Disconnected("Server disconnected"),
    Connecting("Connecting server"),
    Connected("Server connected"),
    Failed("Connection failed"),
}
