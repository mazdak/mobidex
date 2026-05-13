package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class RemoteCodexAppServerCommandTest {
    @Test
    fun launchConfigNormalizesSharedDefaults() {
        assertEquals(
            RemoteServerLaunchConfig(codexPath = "codex", targetShellRCFile = "\$HOME/.zshrc"),
            RemoteServerLaunchDefaults.normalize(codexPath = "  ", targetShellRCFile = ""),
        )
        assertEquals(
            RemoteServerLaunchConfig(codexPath = "~/.bun/bin/codex", targetShellRCFile = "~/.zprofile"),
            RemoteServerLaunchDefaults.normalize(codexPath = " ~/.bun/bin/codex ", targetShellRCFile = " ~/.zprofile "),
        )
    }

    @Test
    fun stdioCommandUsesConfiguredShellRCAndCodexPath() {
        val command = RemoteCodexAppServerCommand.stdioCommand(
            codexPath = "/home/user/bin/codex'special",
            targetShellRCFile = "/home/user/.config/zsh/env file",
        )

        assertEquals(
            "mobidex_shell_rc='/home/user/.config/zsh/env file'; if [ -f \"\$mobidex_shell_rc\" ]; then . \"\$mobidex_shell_rc\" 1>&2; fi; export PATH=\"\$HOME/.bun/bin:\$HOME/.cargo/bin:\$HOME/.local/bin:\$HOME/.npm-global/bin:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH\"; '/home/user/bin/codex'\"'\"'special' app-server --listen stdio://",
            command,
        )
    }

    @Test
    fun defaultStdioCommandResolvesCodexExecutable() {
        val command = RemoteCodexAppServerCommand.stdioCommand()

        assertContains(command, "command -v codex")
        assertContains(command, "mobidex_shell_rc=\"\${HOME}\"/'.zshrc'")
        assertContains(command, "\$HOME/.bun/bin/codex")
        assertContains(command, "\$HOME/.cargo/bin/codex")
        assertContains(command, "/opt/homebrew/opt/node@22/bin")
        assertContains(command, "zsh bash")
        assertContains(command, "app-server --listen stdio://")
        assertContains(command, "Set Codex Binary Path")
    }

    @Test
    fun proxyCommandUsesControlSocketAndConfiguredShellRC() {
        val command = RemoteCodexAppServerCommand.proxyCommand(
            codexPath = "codex",
            targetShellRCFile = "\$HOME/.zshrc",
        )

        assertContains(command, "mobidex_shell_rc=\"\${HOME}\"/'.zshrc'")
        assertContains(command, "command -v codex")
        assertContains(command, "app-server-control/app-server-control.sock")
        assertContains(command, "app-server --listen \"unix://\$socket\"")
        assertContains(command, "app-server proxy --sock \"\$socket\"")
        assertContains(command, "socket_probe_attempted=0")
        assertContains(command, "python3 -c")
        assertFalse(command.contains("stdio://"))
    }

    @Test
    fun proxyCommandQuotesHomeRelativeCodexPath() {
        val command = RemoteCodexAppServerCommand.proxyCommand(
            codexPath = "~/.bun/bin/codex",
            targetShellRCFile = "\$HOME/.zshrc",
        )

        assertContains(command, "codex_bin=\"\${HOME}\"/'.bun/bin/codex'")
        assertContains(command, "\"\$codex_bin\" app-server --listen \"unix://\$socket\"")
        assertContains(command, "exec \"\$codex_bin\" app-server proxy --sock \"\$socket\"")
    }
}
