package mobidex.shared

object RemoteCodexAppServerCommand {
    fun proxyCommand(codexPath: String = "codex", targetShellRCFile: String = "\$HOME/.zshrc"): String {
        val normalizedCodexPath = codexPath.trim().ifEmpty { "codex" }
        return if (normalizedCodexPath == "codex") {
            listOf(
                shellEnvironmentBootstrapCommand(targetShellRCFile),
                codexResolutionCommand(),
                appServerProxyScript(codexExecutable = "\"\$codex_bin\""),
            ).joinToString("; ")
        } else {
            listOf(
                shellEnvironmentBootstrapCommand(targetShellRCFile),
                "codex_bin=${normalizedCodexPath.shellQuotedExecutablePath()}",
                appServerProxyScript(codexExecutable = "\"\$codex_bin\""),
            ).joinToString("; ")
        }
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
            "socket_root=\"\${CODEX_HOME:-\$HOME/.codex}\"",
            "socket=\"\${CODEX_APP_SERVER_SOCK:-\$socket_root/app-server-control/app-server-control.sock}\"",
            "socket_dir=\"\$(dirname \"\$socket\")\"",
            "mkdir -p \"\$socket_dir\"",
            "if [ -S \"\$socket\" ]; then socket_probe_attempted=0; socket_probe_status=0; if command -v python3 >/dev/null 2>&1; then socket_probe_attempted=1; python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1]); s.close()' \"\$socket\" 2>/dev/null; socket_probe_status=\$?; elif command -v python >/dev/null 2>&1; then socket_probe_attempted=1; python -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.settimeout(0.5); s.connect(sys.argv[1]); s.close()' \"\$socket\" 2>/dev/null; socket_probe_status=\$?; elif command -v ruby >/dev/null 2>&1; then socket_probe_attempted=1; ruby -rsocket -e 'UNIXSocket.open(ARGV[0]).close' \"\$socket\" 2>/dev/null; socket_probe_status=\$?; elif command -v perl >/dev/null 2>&1; then socket_probe_attempted=1; perl -MIO::Socket::UNIX -e 'IO::Socket::UNIX->new(Peer => shift) or exit 1' \"\$socket\" 2>/dev/null; socket_probe_status=\$?; fi; if [ \"\$socket_probe_attempted\" -eq 1 ] && [ \"\$socket_probe_status\" -ne 0 ]; then rm -f \"\$socket\"; fi; fi",
            "if [ ! -S \"\$socket\" ]; then nohup $codexExecutable app-server --listen \"unix://\$socket\" >>\"\$socket_dir/app-server.log\" 2>&1 < /dev/null & i=0; while [ \"\$i\" -lt 50 ] && [ ! -S \"\$socket\" ]; do i=\$((i + 1)); sleep 0.1; done; fi",
            "if [ ! -S \"\$socket\" ]; then echo \"codex app-server control socket was not created at \$socket\" >&2; exit 127; fi",
            "exec $codexExecutable app-server proxy --sock \"\$socket\"",
        ).joinToString("; ")

    private fun shellEnvironmentBootstrapCommand(targetShellRCFile: String): String =
        listOf(
            targetShellRCBootstrapCommand(targetShellRCFile),
            "export PATH=\"\$HOME/.bun/bin:\$HOME/.local/bin:\$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH\"",
        ).joinToString("; ")

    private fun targetShellRCBootstrapCommand(targetShellRCFile: String): String {
        val rcFile = targetShellRCFile.trim()
        if (rcFile.isEmpty()) return "true"
        return "mobidex_shell_rc=${rcFile.shellQuotedRemotePath()}; if [ -f \"\$mobidex_shell_rc\" ]; then . \"\$mobidex_shell_rc\" 1>&2; fi"
    }

    private val codexCandidates = listOf(
        "\$HOME/.bun/bin/codex",
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
