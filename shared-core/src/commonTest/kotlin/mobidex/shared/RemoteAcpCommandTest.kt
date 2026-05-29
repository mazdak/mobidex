package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class RemoteAcpCommandTest {
    @Test
    fun launchConfigNormalizesSharedDefaults() {
        val defaultPath = RemoteAcpDefaults.executionPath
        assertEquals(
            RemoteAcpLaunchConfig(acpPath = "grok", executionPath = defaultPath),
            RemoteAcpDefaults.normalize(acpPath = "  ", executionPath = ""),
        )
    }

    @Test
    fun stdioCommandWithExplicitGrokPathUsesItDirectly() {
        val command = RemoteAcpCommand.stdioCommand(
            acpPath = "/home/user/bin/grok-special",
            executionPath = "\$HOME/bin:/custom/bin:\$PATH",
            model = "grok-build",
        )

        // Custom acpPath + executionPath quoting still honored (auth fallback block is now inserted for no-key case but does not change the exec line)
        assertContains(command, "export PATH=")
        assertContains(command, "'/custom/bin'")
        assertContains(command, "exec '/home/user/bin/grok-special' agent stdio --model 'grok-build'")
        assertFalse(command.contains("command -v grok")) // explicit path skips the default resolution dance
    }

    @Test
    fun defaultStdioCommandResolvesGrokExecutableAndIncludesModel() {
        val command = RemoteAcpCommand.stdioCommand(model = "grok-build")

        assertContains(command, "export PATH=")
        assertContains(command, "command -v grok")
        assertContains(command, "\$HOME/.bun/bin/grok")
        assertContains(command, "\$HOME/.cargo/bin/grok")
        assertContains(command, "/opt/homebrew/bin/grok")
        assertContains(command, "agent stdio --model 'grok-build'")
        assertContains(command, "grok executable not found")
        assertContains(command, "Set Execution Path or Grok Binary Path")
        assertFalse(command.contains("app-server"))
        assertFalse(command.contains("nohup"))
        assertFalse(command.contains("unix://"))
        assertFalse(command.contains("proxy"))
    }

    @Test
    fun stdioCommandSupportsExtraArgs() {
        val command = RemoteAcpCommand.stdioCommand(
            acpPath = "grok",
            model = "grok-build",
            extraArgs = listOf("--verbose", "--log-level", "debug"),
        )

        // extraArgs are individually shell-quoted (consistent with codex quoting behavior)
        assertContains(command, "agent stdio --model 'grok-build' '--verbose' '--log-level' 'debug'")
    }

    @Test
    fun stdioCommandQuotesExtraArgsContainingSpecialChars() {
        val command = RemoteAcpCommand.stdioCommand(
            acpPath = "/usr/local/bin/grok",
            model = "grok-build",
            extraArgs = listOf("--note", "it's a test with spaces"),
        )

        assertContains(command, "'--note' 'it'\"'\"'s a test with spaces'")
    }

    @Test
    fun stdioCommandQuotesHomeRelativePath() {
        val command = RemoteAcpCommand.stdioCommand(
            acpPath = "~/.bun/bin/grok",
            executionPath = "",
            model = "grok-build",
        )

        assertContains(command, "export PATH=")
        assertContains(command, "\"\${HOME}\"/'.bun/bin/grok' agent stdio --model 'grok-build'")
    }

    @Test
    fun stdioCommandWithXaiApiKeyInjectsEnvPrefix() {
        val command = RemoteAcpCommand.stdioCommand(
            model = "grok-build",
            xaiApiKey = "sk-test-123",
        )

        assertContains(command, "XAI_API_KEY='sk-test-123' ")
        assertContains(command, "grok agent stdio --model 'grok-build'")
    }

    @Test
    fun stdioCommandWithoutKeyIncludesRemoteAuthJsonFallback() {
        val command = RemoteAcpCommand.stdioCommand(model = "grok-build")

        // Fallback bootstrap (only when no explicit key) attempts ~/.grok/auth.json parse
        assertContains(command, "cat ~/.grok/auth.json")
        assertContains(command, "python3 -c")
        assertContains(command, "apiKey")
        assertContains(command, "export \$XAI_API_KEY")
        // Still contains the grok launch (fallback runs before it)
        assertContains(command, "grok agent stdio --model 'grok-build'")
    }
}
