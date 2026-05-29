package mobidex.shared

/**
 * Generates shell one-liners to launch ACP-speaking agents over stdio (e.g. `grok agent stdio`).
 *
 * This is deliberately separate from RemoteCodexAppServerCommand to keep concerns clean
 * and to avoid any coupling to the Codex app-server launch/proxy logic.
 */
object RemoteAcpCommand {
    fun stdioCommand(
        acpPath: String = RemoteAcpDefaults.acpPath,
        executionPath: String = RemoteAcpDefaults.executionPath,
        model: String = "grok-build",
        extraArgs: List<String> = emptyList(),
        xaiApiKey: String? = null,
    ): String {
        val config = RemoteAcpDefaults.normalize(acpPath, executionPath)
        val modelArg = "--model ${model.shellQuoted()}"
        val extra = if (extraArgs.isEmpty()) "" else " " + extraArgs.joinToString(" ") { it.shellQuoted() }
        val envPrefix = xaiApiKey?.let { "XAI_API_KEY=${it.shellQuoted()} " } ?: ""
        // Minimal remote fallback (only when no explicit key passed from client credential store):
        // best-effort cat + parse of ~/.grok/auth.json for common shapes (apiKey / xai.apiKey).
        // The guard [ -z "$XAI_API_KEY" ] makes it a no-op if the explicit prefix already set it.
        // Uses python3 (common on dev hosts); silent on failure (no key → grok will error naturally).
        val xaiFallback = if (xaiApiKey == null) {
            val D = "\$"
            "[ -z \"${D}XAI_API_KEY\" ] && XAI_API_KEY=$(cat ~/.grok/auth.json 2>/dev/null | python3 -c '\n" +
                "import json,sys\n" +
                "try:\n" +
                " d=json.load(sys.stdin)\n" +
                " k = d.get(\"apiKey\") or (d.get(\"xai\") or {}).get(\"apiKey\") or d.get(\"key\") or \"\"\n" +
                " print(k)\n" +
                "except Exception:\n" +
                " print(\"\")\n" +
                "' 2>/dev/null || echo ''); [ -n \"${D}XAI_API_KEY\" ] && export ${D}XAI_API_KEY || true"
        } else {
            ""
        }

        return if (config.acpPath == RemoteAcpDefaults.acpPath) {
            val parts = mutableListOf(shellEnvironmentBootstrapCommand(config.executionPath))
            if (xaiFallback.isNotEmpty()) parts += xaiFallback
            parts += envPrefix + defaultStdioCommand(modelArg = modelArg, extra = extra)
            parts.joinToString("; ")
        } else {
            val parts = mutableListOf(shellEnvironmentBootstrapCommand(config.executionPath))
            if (xaiFallback.isNotEmpty()) parts += xaiFallback
            parts += "${envPrefix}exec ${config.acpPath.shellQuotedExecutablePath()} agent stdio $modelArg$extra"
            parts.joinToString("; ")
        }
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
