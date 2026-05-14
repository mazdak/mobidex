package mobidex.shared

data class RemoteServerLaunchConfig(
    val codexPath: String = RemoteServerLaunchDefaults.codexPath,
    val targetShellRCFile: String = RemoteServerLaunchDefaults.targetShellRCFile,
)

object RemoteServerLaunchDefaults {
    const val codexPath: String = "codex"
    const val targetShellRCFile: String = "\$HOME/.zshrc"

    fun normalize(codexPath: String?, targetShellRCFile: String?): RemoteServerLaunchConfig =
        RemoteServerLaunchConfig(
            codexPath = codexPath?.trim().orEmpty().ifEmpty { this.codexPath },
            targetShellRCFile = targetShellRCFile?.trim().orEmpty().ifEmpty { this.targetShellRCFile },
        )
}

object RemoteCodexAppServerCommand {
    fun environmentBootstrapCommand(targetShellRCFile: String = RemoteServerLaunchDefaults.targetShellRCFile): String =
        shellEnvironmentBootstrapCommand(
            RemoteServerLaunchDefaults.normalize(
                codexPath = null,
                targetShellRCFile = targetShellRCFile,
            ).targetShellRCFile
        )

    fun stdioCommand(codexPath: String = RemoteServerLaunchDefaults.codexPath, targetShellRCFile: String = RemoteServerLaunchDefaults.targetShellRCFile): String {
        val config = RemoteServerLaunchDefaults.normalize(codexPath, targetShellRCFile)
        return if (config.codexPath == RemoteServerLaunchDefaults.codexPath) {
            listOf(
                shellEnvironmentBootstrapCommand(config.targetShellRCFile),
                defaultStdioCommand(),
            ).joinToString("; ")
        } else {
            listOf(
                shellEnvironmentBootstrapCommand(config.targetShellRCFile),
                "${config.codexPath.shellQuotedExecutablePath()} app-server --listen stdio://",
            ).joinToString("; ")
        }
    }

    fun proxyCommand(codexPath: String = RemoteServerLaunchDefaults.codexPath, targetShellRCFile: String = RemoteServerLaunchDefaults.targetShellRCFile): String {
        val config = RemoteServerLaunchDefaults.normalize(codexPath, targetShellRCFile)
        return if (config.codexPath == RemoteServerLaunchDefaults.codexPath) {
            listOf(
                shellEnvironmentBootstrapCommand(config.targetShellRCFile),
                codexResolutionCommand(),
                appServerProxyScript(codexExecutable = "\"\$codex_bin\""),
            ).joinToString("; ")
        } else {
            listOf(
                shellEnvironmentBootstrapCommand(config.targetShellRCFile),
                "codex_bin=${config.codexPath.shellQuotedExecutablePath()}",
                appServerProxyScript(codexExecutable = "\"\$codex_bin\""),
            ).joinToString("; ")
        }
    }

    private fun defaultStdioCommand(): String {
        val candidateList = codexCandidates.joinToString(" ") { "\"$it\"" }
        return listOf(
            "if command -v codex >/dev/null 2>&1; then exec codex app-server --listen stdio://; fi",
            "for candidate in $candidateList; do if [ -x \"\$candidate\" ]; then exec \"\$candidate\" app-server --listen stdio://; fi; done",
            "for shell in zsh bash; do if command -v \"\$shell\" >/dev/null 2>&1; then resolved=\"\$(\"\$shell\" -lc 'command -v codex' 2>/dev/null || true)\"; if [ -n \"\$resolved\" ] && [ -x \"\$resolved\" ]; then exec \"\$resolved\" app-server --listen stdio://; fi; fi; done",
            "echo 'codex executable not found. Set Codex Binary Path to the full remote codex executable, for example ~/.bun/bin/codex.' >&2",
            "exit 127",
        ).joinToString("; ")
    }

    private fun codexResolutionCommand(): String {
        val candidateList = codexCandidates.joinToString(" ") { "\"$it\"" }
        return listOf(
            "codex_bin=\"\"",
            "if command -v codex >/dev/null 2>&1; then codex_bin=\"\$(command -v codex)\"; fi",
            "if [ -z \"\$codex_bin\" ]; then for candidate in $candidateList; do if [ -x \"\$candidate\" ]; then codex_bin=\"\$candidate\"; break; fi; done; fi",
            "if [ -z \"\$codex_bin\" ]; then for shell in zsh bash; do if command -v \"\$shell\" >/dev/null 2>&1; then resolved=\"\$(\"\$shell\" -lc 'command -v codex' 2>/dev/null || true)\"; if [ -n \"\$resolved\" ] && [ -x \"\$resolved\" ]; then codex_bin=\"\$resolved\"; break; fi; fi; done; fi",
            "if [ -z \"\$codex_bin\" ]; then echo 'codex executable not found. Set Codex Binary Path to the full remote codex executable, for example ~/.bun/bin/codex.' >&2; exit 127; fi",
        ).joinToString("; ")
    }

    private fun appServerProxyScript(codexExecutable: String): String =
        listOf(
            "if ! $codexExecutable app-server proxy --help >/dev/null 2>&1; then echo 'codex app-server proxy is not supported by the configured Codex executable.' >&2; exit 127; fi",
            "default_socket=\"\${CODEX_HOME:-\$HOME/.codex}/app-server-control/app-server-control.sock\"",
            "socket_dir=\"\$(dirname \"\$default_socket\")\"",
            "log_path=\"\${TMPDIR:-/tmp}/mobidex-codex-app-server-unix.log\"",
            "mkdir -p \"\$socket_dir\"",
            "nohup $codexExecutable app-server --listen unix:// >>\"\$log_path\" 2>&1 < /dev/null & i=0; while [ \"\$i\" -lt 50 ] && [ ! -S \"\$default_socket\" ]; do i=\$((i + 1)); sleep 0.1; done",
            "if [ ! -S \"\$default_socket\" ]; then echo \"codex app-server default control socket was not created at \$default_socket; see \$log_path\" >&2; exit 127; fi",
            "exec $codexExecutable app-server proxy",
        ).joinToString("; ")

    private fun shellEnvironmentBootstrapCommand(targetShellRCFile: String): String =
        listOf(
            targetShellRCBootstrapCommand(targetShellRCFile),
            "export PATH=\"\$HOME/.bun/bin:\$HOME/.cargo/bin:\$HOME/.local/bin:\$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH\"",
        ).joinToString("; ")

    private fun targetShellRCBootstrapCommand(targetShellRCFile: String): String {
        val rcFile = targetShellRCFile.trim()
        if (rcFile.isEmpty()) return "true"
        return "mobidex_shell_rc=${rcFile.shellQuotedRemotePath()}; if [ -f \"\$mobidex_shell_rc\" ]; then . \"\$mobidex_shell_rc\" 1>&2; fi"
    }

    private val codexCandidates = listOf(
        "\$HOME/.bun/bin/codex",
        "\$HOME/.cargo/bin/codex",
        "\$HOME/.local/bin/codex",
        "\$HOME/.npm-global/bin/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "/usr/bin/codex",
    )
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
