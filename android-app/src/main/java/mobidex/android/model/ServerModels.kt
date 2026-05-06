package mobidex.android.model

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable

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
    val codexPath: String = "codex",
    val targetShellRCFile: String = "\$HOME/.zshrc",
    val authMethod: ServerAuthMethod,
    val projects: List<ProjectRecord> = emptyList(),
    val createdAtEpochSeconds: Long = Instant.now().epochSecond,
    val updatedAtEpochSeconds: Long = Instant.now().epochSecond,
) {
    val endpointLabel: String
        get() = "$username@$host:$port"

    val normalized: ServerRecord
        get() = copy(
            displayName = displayName.trim().ifEmpty { host.trim() },
            host = host.trim(),
            username = username.trim(),
            codexPath = codexPath.trim().ifEmpty { "codex" },
            targetShellRCFile = targetShellRCFile.trim().ifEmpty { "\$HOME/.zshrc" },
            updatedAtEpochSeconds = Instant.now().epochSecond,
        )

    val appServerCommand: String
        get() {
            val executable = if (codexPath.trim() == "codex") "codex" else codexPath.shellQuotedExecutablePath()
            return listOf(
                shellEnvironmentBootstrapCommand(),
                "exec $executable app-server --listen stdio://",
            ).joinToString("; ")
        }
}

@Serializable
data class ProjectRecord(
    val id: String = UUID.randomUUID().toString(),
    val path: String,
    val sessionPaths: List<String> = listOf(path),
    val displayName: String = path.trimEnd('/').substringAfterLast('/').ifEmpty { path },
    val discovered: Boolean = false,
    val discoveredSessionCount: Int = 0,
    val activeChatCount: Int = 0,
    val lastDiscoveredAtEpochSeconds: Long? = null,
    val lastActiveChatAtEpochSeconds: Long? = null,
    val isFavorite: Boolean = false,
) {
    val normalized: ProjectRecord
        get() = copy(sessionPaths = normalizedSessionPaths(sessionPaths, path))

    companion object {
        fun normalizedSessionPaths(paths: List<String>, primaryPath: String): List<String> =
            mobidex.shared.ProjectRecord.Companion.normalizedSessionPaths(paths, primaryPath)
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

private fun ServerRecord.shellEnvironmentBootstrapCommand(): String =
    listOf(
        targetShellRCBootstrapCommand(),
        "export PATH=\"${'$'}HOME/.bun/bin:${'$'}HOME/.local/bin:${'$'}HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${'$'}PATH\"",
    ).joinToString("; ")

private fun ServerRecord.targetShellRCBootstrapCommand(): String {
    val rcFile = targetShellRCFile.trim()
    if (rcFile.isEmpty()) return "true"
    return "mobidex_shell_rc=${rcFile.shellQuotedRemotePath()}; if [ -f \"${'$'}mobidex_shell_rc\" ]; then . \"${'$'}mobidex_shell_rc\" 1>&2; fi"
}

private fun String.shellQuoted(): String = "'${replace("'", "'\"'\"'")}'"

private fun String.shellQuotedExecutablePath(): String =
    when {
        this == "~" -> "\"\${HOME}\""
        startsWith("~/") -> "\"\${HOME}\"/${drop(2).shellQuoted()}"
        else -> shellQuoted()
    }

private fun String.shellQuotedRemotePath(): String =
    when {
        this == "\$HOME" || this == "\${HOME}" || this == "~" -> "\"\${HOME}\""
        startsWith("\$HOME/") -> "\"\${HOME}\"/${drop(6).shellQuoted()}"
        startsWith("\${HOME}/") -> "\"\${HOME}\"/${drop(8).shellQuoted()}"
        startsWith("~/") -> "\"\${HOME}\"/${drop(2).shellQuoted()}"
        else -> shellQuoted()
    }
