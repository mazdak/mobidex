package mobidex.shared

/**
 * Generates shell one-liners to launch ACP-speaking agents over stdio (e.g. `grok agent stdio`).
 *
 * This is deliberately separate from RemoteCodexAppServerCommand to keep concerns clean
 * and to avoid any coupling to the Codex app-server launch/proxy logic.
 */
object RemoteAcpCommand {
    const val defaultLaunchCommand: String = "grok agent stdio --model grok-build"

    fun stdioCommand(
        acpPath: String = RemoteAcpDefaults.acpPath,
        executionPath: String = RemoteAcpDefaults.executionPath,
        model: String = "grok-build",
        extraArgs: List<String> = emptyList(),
    ): String {
        val config = RemoteAcpDefaults.normalize(acpPath, executionPath)
        val modelArg = "--model ${model.shellQuoted()}"
        val extra = if (extraArgs.isEmpty()) "" else " " + extraArgs.joinToString(" ") { it.shellQuoted() }

        // No mobile-side auth injection. Once SSH-authenticated as the target user,
        // the launched `grok agent stdio` inherits the remote environment and home
        // directory exactly as `codex` does today (via ~/.grok/*, shell profile, etc.).
        return if (config.acpPath == RemoteAcpDefaults.acpPath) {
            listOf(
                shellEnvironmentBootstrapCommand(config.executionPath),
                defaultStdioCommand(modelArg = modelArg, extra = extra),
            ).joinToString("; ")
        } else {
            listOf(
                shellEnvironmentBootstrapCommand(config.executionPath),
                "exec ${config.acpPath.shellQuotedExecutablePath()} agent stdio $modelArg$extra",
            ).joinToString("; ")
        }
    }

    fun shellCommand(
        launchCommand: String = defaultLaunchCommand,
        executionPath: String = RemoteAcpDefaults.executionPath,
    ): String {
        val command = launchCommand.trim().ifEmpty { defaultLaunchCommand }
        val config = RemoteAcpDefaults.normalize(acpPath = RemoteAcpDefaults.acpPath, executionPath = executionPath)
        return listOf(
            shellEnvironmentBootstrapCommand(config.executionPath),
            "exec $command",
        ).joinToString("; ")
    }

    private fun defaultStdioCommand(modelArg: String, extra: String): String {
        val candidateList = acpCandidates.joinToString(" ") { "\"$it\"" }
        return listOf(
            "if command -v grok >/dev/null 2>&1; then exec grok agent stdio $modelArg$extra; fi",
            "for candidate in $candidateList; do if [ -x \"\$candidate\" ]; then exec \"\$candidate\" agent stdio $modelArg$extra; fi; done",
            "echo 'grok executable not found. Set Execution Path or Grok Binary Path to the remote grok location.' >&2",
            "exit 127",
        ).joinToString("; ")
    }

    private fun shellEnvironmentBootstrapCommand(executionPath: String): String =
        "export PATH=${executionPath.shellQuotedPathList()}"
}

object RemoteAcpDefaults {
    const val acpPath: String = "grok"
    const val executionPath: String = RemoteServerLaunchDefaults.executionPath

    fun normalize(acpPath: String?, executionPath: String?): RemoteAcpLaunchConfig =
        RemoteAcpLaunchConfig(
            acpPath = acpPath?.trim().orEmpty().ifEmpty { this.acpPath },
            executionPath = executionPath?.trim().orEmpty().ifEmpty { this.executionPath },
        )
}

data class RemoteAcpLaunchConfig(
    val acpPath: String = RemoteAcpDefaults.acpPath,
    val executionPath: String = RemoteAcpDefaults.executionPath,
)

private val acpCandidates = listOf(
    "\$HOME/.bun/bin/grok",
    "\$HOME/.cargo/bin/grok",
    "\$HOME/.local/bin/grok",
    "\$HOME/.npm-global/bin/grok",
    "/opt/homebrew/bin/grok",
    "/usr/local/bin/grok",
    "/usr/bin/grok",
)

// --- Minimal shell quoting helpers (duplicated from codex command for clean separation in v1 sketch) ---

private fun String.shellQuoted(): String = "'${replace("'", "'\"'\"'")}'"

private fun String.shellQuotedExecutablePath(): String =
    when {
        this == "~" -> "\"\${HOME}\""
        startsWith("~/") -> "\"\${HOME}\"/${drop(2).shellQuoted()}"
        else -> shellQuoted()
    }

private fun String.shellQuotedPathList(): String =
    split(':').joinToString(":") { segment ->
        when {
            segment == "\$PATH" || segment == "\${PATH}" -> "\"\$PATH\""
            segment == "\$HOME" || segment == "\${HOME}" || segment == "~" -> "\"\${HOME}\""
            segment.startsWith("\$HOME/") -> "\"\${HOME}\"/${segment.drop(6).shellQuoted()}"
            segment.startsWith("\${HOME}/") -> "\"\${HOME}\"/${segment.drop(8).shellQuoted()}"
            segment.startsWith("~/") -> "\"\${HOME}\"/${segment.drop(2).shellQuoted()}"
            else -> segment.shellQuoted()
        }
    }
