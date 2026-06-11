package mobidex.shared

/**
 * Generates shell one-liners to launch ACP-speaking agents over stdio
 * (e.g. `grok agent stdio`, `bunx @zed-industries/claude-code-acp`).
 *
 * This is deliberately separate from RemoteCodexAppServerCommand to keep concerns clean
 * and to avoid any coupling to the Codex app-server launch/proxy logic.
 *
 * No mobile-side auth injection: once SSH-authenticated as the target user, the launched
 * agent inherits the remote environment and home directory exactly as `codex` does today
 * (auth files, shell profile, etc.).
 */
object RemoteAcpCommand {
    /** Preset: xAI Grok CLI in ACP stdio mode. */
    const val grokLaunchCommand: String = "grok agent stdio --model grok-build"

    /** Preset: Claude Code via Zed's ACP adapter (requires bun on the host). */
    const val claudeLaunchCommand: String = "bunx @zed-industries/claude-code-acp"

    const val defaultLaunchCommand: String = grokLaunchCommand

    /**
     * Final remote shell line: bootstrap PATH from [executionPath] (a PATH list, not a working
     * directory — the session cwd travels in ACP `session/new`), then exec the agent command.
     */
    fun shellCommand(
        launchCommand: String = defaultLaunchCommand,
        executionPath: String = RemoteServerLaunchDefaults.executionPath,
    ): String {
        val command = launchCommand.trim().ifEmpty { defaultLaunchCommand }
        val path = executionPath.trim().ifEmpty { RemoteServerLaunchDefaults.executionPath }
        return listOf(
            "export PATH=${path.shellQuotedPathList()}",
            "exec $command",
        ).joinToString("; ")
    }
}

// --- Minimal shell quoting helpers (duplicated from codex command for clean separation) ---

private fun String.shellQuoted(): String = "'${replace("'", "'\"'\"'")}'"

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
