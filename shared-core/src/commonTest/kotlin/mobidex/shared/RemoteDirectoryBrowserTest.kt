package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class RemoteDirectoryBrowserTest {
    @Test
    fun shellCommandEmbedsRequestedPathAsJson() {
        val command = RemoteDirectoryBrowser.shellCommand("/tmp/Project \"A\"")

        assertTrue(command.contains("requested_path = \"/tmp/Project \\\"A\\\"\""), command)
        assertTrue(command.contains("os.scandir(current_path)"), command)
        assertTrue(command.contains("entry.is_dir(follow_symlinks=True)"), command)
        assertTrue(command.contains("mobidex_status=${'$'}?;exit ${'$'}mobidex_status"), command)
    }

    @Test
    fun decodeListingReadsFolders() {
        val listing = RemoteDirectoryBrowser.decodeListing(
            """{"path":"/","entries":[{"name":"Users","path":"/Users"}]}"""
        )

        assertEquals(
            RemoteDirectoryListing(
                path = "/",
                entries = listOf(RemoteDirectoryEntry(name = "Users", path = "/Users")),
            ),
            listing,
        )
    }

    @Test
    fun decodeListingToleratesMergedShellNoiseAroundJson() {
        val listing = RemoteDirectoryBrowser.decodeListing(
            """
            /Users/mazdak/.zprofile:44: command not found: starship
            {"path":"/Users","entries":[{"name":"mazdak","path":"/Users/mazdak"}]}
            shell warning after command
            """.trimIndent()
        )

        assertEquals(
            RemoteDirectoryListing(
                path = "/Users",
                entries = listOf(RemoteDirectoryEntry(name = "mazdak", path = "/Users/mazdak")),
            ),
            listing,
        )
    }

    @Test
    fun decodeListingSurfacesRemoteError() {
        val error = assertFailsWith<RemoteDirectoryBrowserException> {
            RemoteDirectoryBrowser.decodeListing("""{"path":"/missing","entries":[],"error":"No such file"}""")
        }

        assertEquals("No such file", error.message)
    }
}
