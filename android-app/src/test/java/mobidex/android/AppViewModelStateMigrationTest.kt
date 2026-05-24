package mobidex.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import mobidex.android.model.ProjectRecord
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerRecord

class AppViewModelStateMigrationTest {
    @Test
    fun loadedServerStateMigratesZshRcAndClearsOpenSessionCounts() {
        val server = ServerRecord(
            displayName = "Mac Home",
            host = "192.168.1.239",
            username = "mazdak",
            targetShellRCFile = "~/.zshrc",
            authMethod = ServerAuthMethod.Password,
            projects = listOf(
                ProjectRecord(
                    path = "/Users/mazdak/Code/qlaw",
                    activeChatCount = 2,
                    lastActiveChatAtEpochSeconds = 1_770_000_300,
                )
            ),
        )

        val migrated = listOf(server).clearingAppServerProjectState().single()

        assertEquals("~/.zprofile", migrated.targetShellRCFile)
        assertEquals("codex", migrated.codexPath)
        assertEquals(0, migrated.projects.single().activeChatCount)
        assertNull(migrated.projects.single().lastActiveChatAtEpochSeconds)
    }
}
