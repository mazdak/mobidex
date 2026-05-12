package mobidex.android.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import mobidex.shared.RemoteCodexAppServerCommand
import mobidex.shared.RemoteServerLaunchDefaults

@Serializable
enum class ServerAuthMethod(val label: String) {
    Password("Password"),
    PrivateKey("Private Key"),
}

@Serializable
data class ServerRecord(
    val id: String = UUID.randomUUID().toString(),
    val displayName: String,
    val host: String,
    val port: Int = 22,
    val username: String,
    val codexPath: String = RemoteServerLaunchDefaults.codexPath,
    val targetShellRCFile: String = RemoteServerLaunchDefaults.targetShellRCFile,
    val authMethod: ServerAuthMethod,
    val projects: List<ProjectRecord> = emptyList(),
    val createdAtEpochSeconds: Long = Instant.now().epochSecond,
    val updatedAtEpochSeconds: Long = Instant.now().epochSecond,
) {
    val endpointLabel: String
        get() = "$username@$host:$port"

    val normalized: ServerRecord
        get() {
            val launchConfig = RemoteServerLaunchDefaults.normalize(codexPath, targetShellRCFile)
            return copy(
                displayName = displayName.trim().ifEmpty { host.trim() },
                host = host.trim(),
                username = username.trim(),
                codexPath = launchConfig.codexPath,
                targetShellRCFile = launchConfig.targetShellRCFile,
                updatedAtEpochSeconds = Instant.now().epochSecond,
            )
        }

    val appServerProxyCommand: String
        get() = RemoteCodexAppServerCommand.proxyCommand(
            codexPath = codexPath,
            targetShellRCFile = targetShellRCFile,
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
    val isFavorite: Boolean = false,
) {
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
    Disconnected("App-server disconnected"),
    Connecting("Connecting app-server"),
    Connected("App-server connected"),
    Failed("Connection failed"),
}
