package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RemoteCodexDiscoveryTest {
    @Test
    fun shellCommandWrapsPythonDiscoveryScript() {
        val command = RemoteCodexDiscovery.shellCommand

        assertTrue(command.startsWith("mobidex_shell_rc=\"\${HOME}\"/'.zshrc';"))
        assertTrue(command.contains("python3 - <<'PY'\n"))
        assertTrue(command.endsWith("\nPY\nmobidex_status=${'$'}?;exit ${'$'}mobidex_status"))
        assertTrue((command + ";exit\n").contains("\nPY\nmobidex_status=${'$'}?;exit ${'$'}mobidex_status;exit\n"))
        assertFalse((command + ";exit\n").contains("\nPY;exit"))
        assertFalse((command + ";exit\n").contains("\n;exit"))
        assertTrue(command.contains("CODEX_HOME"))
        assertFalse(command.contains("archived_sessions"))
        assertFalse(command.contains("rollout-"))
        assertTrue(command.contains("state_5.sqlite"))
        assertTrue(command.contains("thread-workspace-root-hints"))
        assertTrue(command.contains("os.path.isdir"))
    }

    @Test
    fun shellCommandUsesConfiguredLaunchEnvironment() {
        val command = RemoteCodexDiscovery.shellCommand(targetShellRCFile = "~/custom rc")

        assertTrue(command.startsWith("mobidex_shell_rc=\"\${HOME}\"/'custom rc';"), command)
        assertTrue(command.contains("export PATH="), command)
        assertTrue(command.contains("python3 - <<'PY'\n"), command)
    }

    @Test
    fun decodeProjectsUsesSecondsSinceEpochDates() {
        val projects = RemoteCodexDiscovery.decodeProjects(
            """[{"path":"/srv/app","discoveredSessionCount":2,"lastDiscoveredAt":1770000300}]"""
        )

        assertEquals(
            listOf(
                RemoteProject(
                    path = "/srv/app",
                    sessionPaths = listOf("/srv/app"),
                    discoveredSessionCount = 2,
                    lastDiscoveredAtEpochSeconds = 1_770_000_300,
                )
            ),
            projects,
        )
    }

    @Test
    fun decodeProjectsFailureIncludesDiscoveryContext() {
        val error = assertFailsWith<RemoteCodexDiscoveryException> {
            RemoteCodexDiscovery.decodeProjects("python3: command not found")
        }

        assertTrue(error.message.orEmpty().contains("Output: python3: command not found"), error.message)
    }
}
