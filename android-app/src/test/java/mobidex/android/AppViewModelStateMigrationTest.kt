package mobidex.android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import mobidex.android.model.ProjectRecord
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerRecord

class AppViewModelStateMigrationTest {
    @Test
    fun loadedServerStateNormalizesExecutionPathAndClearsOpenSessionCounts() {
        val server = ServerRecord(
            displayName = "Mac Home",
            host = "192.168.1.239",
            username = "mazdak",
            executionPath = " ~/bin:/usr/bin:\$PATH ",
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

        assertEquals("~/bin:/usr/bin:\$PATH", migrated.executionPath)
        assertEquals("codex", migrated.codexPath)
        assertEquals(0, migrated.projects.single().activeChatCount)
        assertNull(migrated.projects.single().lastActiveChatAtEpochSeconds)
    }
}
