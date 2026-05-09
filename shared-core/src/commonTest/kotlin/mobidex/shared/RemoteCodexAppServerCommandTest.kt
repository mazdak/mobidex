package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFalse

class RemoteCodexAppServerCommandTest {
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
