package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class RemoteCodexAppServerCommandTest {
    @Test
    fun launchConfigNormalizesSharedDefaults() {
        val defaultPath = RemoteServerLaunchDefaults.executionPath
        assertEquals(
            RemoteServerLaunchConfig(codexPath = "codex", executionPath = defaultPath),
            RemoteServerLaunchDefaults.normalize(codexPath = "  ", executionPath = ""),
        )
        assertEquals(
            RemoteServerLaunchConfig(codexPath = "~/.bun/bin/codex", executionPath = "\$HOME/bin:/usr/bin:\${PATH}"),
            RemoteServerLaunchDefaults.normalize(codexPath = " ~/.bun/bin/codex ", executionPath = " \$HOME/bin:/usr/bin:\${PATH} "),
        )
    }

    @Test
    fun stdioCommandUsesConfiguredExecutionPathAndCodexPath() {
        val command = RemoteCodexAppServerCommand.stdioCommand(
            codexPath = "/home/user/bin/codex'special",
            executionPath = "\$HOME/bin:/custom/bin:\$PATH",
        )

        assertEquals(
            "export PATH=\"\${HOME}\"/'bin':'/custom/bin':\"\$PATH\"; '/home/user/bin/codex'\"'\"'special' app-server --listen stdio://",
            command,
        )
    }

    @Test
    fun defaultStdioCommandResolvesCodexExecutable() {
        val command = RemoteCodexAppServerCommand.stdioCommand()

        assertContains(command, "command -v codex")
        assertContains(command, "export PATH=")
        assertContains(command, "\$HOME/.bun/bin/codex")
        assertContains(command, "\$HOME/.cargo/bin/codex")
        assertContains(command, "/opt/homebrew/opt/node@22/bin")
        assertContains(command, "app-server --listen stdio://")
        assertContains(command, "Set Execution Path or Codex Binary Path")
        assertFalse(command.contains("mobidex_shell_rc"))
        assertFalse(command.contains("zsh bash"))
    }

    @Test
    fun proxyCommandUsesDefaultUnixSocketProxyAndConfiguredExecutionPath() {
        val command = RemoteCodexAppServerCommand.proxyCommand(
            codexPath = "codex",
            executionPath = "~/bin:/usr/bin:\${PATH}",
        )

        assertContains(command, "export PATH=\"\${HOME}\"/'bin':'/usr/bin':\"\$PATH\"")
        assertContains(command, "command -v codex")
        assertContains(command, "app-server proxy --help")
        assertContains(command, "default_socket=\"\${CODEX_HOME:-\$HOME/.codex}/app-server-control/app-server-control.sock\"")
        assertContains(command, "app-server-control/app-server-control.sock")
        assertContains(command, "mkdir -p \"\$socket_dir\"")
        assertContains(command, "app-server --listen unix://")
        assertContains(command, "exec \"\$codex_bin\" app-server proxy")
        assertFalse(command.contains("proxy --sock"))
        assertFalse(command.contains("unix://\$socket"))
        assertFalse(command.contains("socket_probe_attempted"))
        assertFalse(command.contains("&;"))
        assertFalse(command.contains("stdio://"))
    }

    @Test
    fun proxyCommandQuotesHomeRelativeCodexPath() {
        val command = RemoteCodexAppServerCommand.proxyCommand(
            codexPath = "~/.bun/bin/codex",
            executionPath = "",
        )

        assertContains(command, "export PATH=")
        assertContains(command, "codex_bin=\"\${HOME}\"/'.bun/bin/codex'")
        assertContains(command, "\"\$codex_bin\" app-server --listen unix://")
        assertContains(command, "exec \"\$codex_bin\" app-server proxy")
        assertFalse(command.contains("mobidex_shell_rc"))
        assertFalse(command.contains("proxy --sock"))
    }
}
