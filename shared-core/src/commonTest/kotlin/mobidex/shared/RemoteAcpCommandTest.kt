package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class RemoteAcpCommandTest {
    @Test
    fun shellCommandUsesGenericAcpLaunchCommandWithPathBootstrap() {
        val command = RemoteAcpCommand.shellCommand(
            launchCommand = "my-agent --stdio --profile work",
            executionPath = "\$HOME/bin:/usr/bin:\$PATH",
        )

        assertContains(command, "export PATH=")
        assertContains(command, "\"\${HOME}\"/'bin'")
        assertContains(command, "'/usr/bin'")
        assertContains(command, "exec my-agent --stdio --profile work")
    }

    @Test
    fun shellCommandFallsBackToDefaultAcpLaunchCommand() {
        assertContains(RemoteAcpCommand.shellCommand(launchCommand = " "), RemoteAcpCommand.defaultLaunchCommand)
    }

    @Test
    fun shellCommandFallsBackToDefaultExecutionPath() {
        val command = RemoteAcpCommand.shellCommand(launchCommand = "grok agent stdio", executionPath = "  ")
        assertContains(command, "export PATH=")
        assertContains(command, "\"\${HOME}\"/'.bun/bin'")
        assertContains(command, "\"\$PATH\"")
    }

    @Test
    fun presetsAreCompleteLaunchCommands() {
        assertEquals("grok agent stdio --model grok-build", RemoteAcpCommand.grokLaunchCommand)
        assertEquals("bunx @zed-industries/claude-code-acp", RemoteAcpCommand.claudeLaunchCommand)
        assertEquals(RemoteAcpCommand.grokLaunchCommand, RemoteAcpCommand.defaultLaunchCommand)

        val claude = RemoteAcpCommand.shellCommand(launchCommand = RemoteAcpCommand.claudeLaunchCommand)
        assertContains(claude, "exec bunx @zed-industries/claude-code-acp")
    }

    @Test
    fun shellCommandNeverContainsMobileAuthInjection() {
        // Design: SSH authentication is the only mobile concern (matches Codex exactly).
        // The remote agent process uses whatever auth the logged-in user has on the host.
        for (launch in listOf(RemoteAcpCommand.grokLaunchCommand, RemoteAcpCommand.claudeLaunchCommand)) {
            val command = RemoteAcpCommand.shellCommand(launchCommand = launch)
            assertFalse(command.contains("API_KEY", ignoreCase = true))
            assertFalse(command.contains("auth.json"))
        }
    }
}
