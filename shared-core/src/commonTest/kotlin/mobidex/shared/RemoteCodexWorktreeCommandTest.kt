package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFalse

class RemoteCodexWorktreeCommandTest {
    @Test
    fun shellCommandAllocatesUniqueWorktreeDirectoryWithoutUuidgenFallback() {
        val command = RemoteCodexWorktreeCommand.shellCommand("/srv/Project 'A'")

        assertContains(command, "git -C ")
        assertContains(command, "/srv/Project ")
        assertContains(command, "'\"'\"'")
        assertContains(command, " rev-parse --show-toplevel")
        assertContains(command, "parent=\"\$HOME/.codex/worktrees\"")
        assertContains(command, "mktemp -d \"\$parent/XXXXXX\"")
        assertContains(command, "target=\"\$base/\$name\"")
        assertFalse(command.contains("uuidgen"))
        assertFalse(command.contains("date +%s"))
    }
}
