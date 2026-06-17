package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFalse

class RemoteCodexWorktreeCommandTest {
    @Test
    fun shellCommandAllocatesFourHexWorktreeDirectoryWithoutUuidgenFallback() {
        val command = RemoteCodexWorktreeCommand.shellCommand("/srv/Project 'A'")

        assertContains(command, "git -C ")
        assertContains(command, "/srv/Project ")
        assertContains(command, "'\"'\"'")
        assertContains(command, " rev-parse --show-toplevel")
        assertContains(command, "parent=\"\$HOME/.codex/worktrees\"")
        assertContains(command, "od -An -N2 -tx1 /dev/urandom")
        assertContains(command, "base=\"\$parent/\$suffix\"")
        assertContains(command, "target=\"\$base/\$name\"")
        assertContains(command, "timeout=120")
        assertContains(command, "git worktree add timed out after %s seconds")
        assertFalse(command.contains("uuidgen"))
        assertFalse(command.contains("date +%s"))
    }
}
