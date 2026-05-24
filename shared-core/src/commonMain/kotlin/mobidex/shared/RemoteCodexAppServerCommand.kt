package mobidex.shared

data class RemoteServerLaunchConfig(
    val codexPath: String = RemoteServerLaunchDefaults.codexPath,
    val executionPath: String = RemoteServerLaunchDefaults.executionPath,
)

object RemoteServerLaunchDefaults {
    const val codexPath: String = "codex"
    const val executionPath: String = "\$HOME/.bun/bin:\$HOME/.cargo/bin:\$HOME/.local/bin:\$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"

    fun normalize(codexPath: String?, executionPath: String?): RemoteServerLaunchConfig =
        RemoteServerLaunchConfig(
            codexPath = codexPath?.trim().orEmpty().ifEmpty { this.codexPath },
            executionPath = executionPath?.trim().orEmpty().ifEmpty { this.executionPath },
        )
}

object RemoteCodexAppServerCommand {
    fun environmentBootstrapCommand(executionPath: String = RemoteServerLaunchDefaults.executionPath): String =
        shellEnvironmentBootstrapCommand(
            RemoteServerLaunchDefaults.normalize(
                codexPath = null,
                executionPath = executionPath,
            ).executionPath
        )

    fun stdioCommand(codexPath: String = RemoteServerLaunchDefaults.codexPath, executionPath: String = RemoteServerLaunchDefaults.executionPath): String {
        val config = RemoteServerLaunchDefaults.normalize(codexPath, executionPath)
        return if (config.codexPath == RemoteServerLaunchDefaults.codexPath) {
            listOf(
                shellEnvironmentBootstrapCommand(config.executionPath),
                defaultStdioCommand(),
            ).joinToString("; ")
        } else {
            listOf(
                shellEnvironmentBootstrapCommand(config.executionPath),
                "${config.codexPath.shellQuotedExecutablePath()} app-server --listen stdio://",
            ).joinToString("; ")
        }
    }

    fun proxyCommand(codexPath: String = RemoteServerLaunchDefaults.codexPath, executionPath: String = RemoteServerLaunchDefaults.executionPath): String {
        val config = RemoteServerLaunchDefaults.normalize(codexPath, executionPath)
        return if (config.codexPath == RemoteServerLaunchDefaults.codexPath) {
            listOf(
                shellEnvironmentBootstrapCommand(config.executionPath),
                codexResolutionCommand(),
                appServerProxyScript(codexExecutable = "\"\$codex_bin\""),
            ).joinToString("; ")
        } else {
            listOf(
                shellEnvironmentBootstrapCommand(config.executionPath),
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
            "echo 'codex executable not found. Set Execution Path or Codex Binary Path to the remote codex executable location.' >&2",
            "exit 127",
        ).joinToString("; ")
    }

    private fun codexResolutionCommand(): String {
        val candidateList = codexCandidates.joinToString(" ") { "\"$it\"" }
        return listOf(
            "codex_bin=\"\"",
            "if command -v codex >/dev/null 2>&1; then codex_bin=\"\$(command -v codex)\"; fi",
            "if [ -z \"\$codex_bin\" ]; then for candidate in $candidateList; do if [ -x \"\$candidate\" ]; then codex_bin=\"\$candidate\"; break; fi; done; fi",
            "if [ -z \"\$codex_bin\" ]; then echo 'codex executable not found. Set Execution Path or Codex Binary Path to the remote codex executable location.' >&2; exit 127; fi",
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

    private fun shellEnvironmentBootstrapCommand(executionPath: String): String =
        "export PATH=${executionPath.shellQuotedPathList()}"

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
