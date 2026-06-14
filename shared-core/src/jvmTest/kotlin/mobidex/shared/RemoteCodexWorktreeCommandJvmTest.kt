package mobidex.shared

import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class RemoteCodexWorktreeCommandJvmTest {
    @Test
    fun shellCommandCreatesDistinctWorktreesWhenUuidgenUnavailableAndDateRepeats() {
        val temp = Files.createTempDirectory("mobidex-worktree-command").toFile()
        try {
            val home = File(temp, "home").also { it.mkdirs() }
            val fakeBin = File(temp, "bin").also { it.mkdirs() }
            val repo = File(temp, "Project 'A").also { it.mkdirs() }
            fakeExecutable(fakeBin, "uuidgen", "exit 127")
            fakeExecutable(fakeBin, "date", "printf '1234567890\\n'")
            runShell("git init", repo)
            File(repo, "README.md").writeText("hello\n")
            runShell("git add README.md", repo)
            runShell("git -c user.email=test@example.com -c user.name=Test commit -m initial", repo)

            val environment = mapOf(
                "HOME" to home.absolutePath,
                "PATH" to "${fakeBin.absolutePath}${File.pathSeparator}${System.getenv("PATH").orEmpty()}",
            )

            val first = runShell(RemoteCodexWorktreeCommand.shellCommand(repo.absolutePath), temp, environment).trim()
            val second = runShell(RemoteCodexWorktreeCommand.shellCommand(repo.absolutePath), temp, environment).trim()

            assertNotEquals(first, second)
            assertWorktreePath(home, first)
            assertWorktreePath(home, second)
        } finally {
            temp.deleteRecursively()
        }
    }

    private fun fakeExecutable(directory: File, name: String, body: String) {
        File(directory, name).apply {
            writeText("#!/bin/sh\n$body\n")
            setExecutable(true)
        }
    }

    private fun assertWorktreePath(home: File, path: String) {
        val worktreesRoot = File(home, ".codex/worktrees").absolutePath
        val worktree = File(path)
        assertTrue(path.startsWith("$worktreesRoot/"), path)
        assertTrue(worktree.isDirectory, path)
        val gitRoot = File(runShell("git rev-parse --show-toplevel", worktree).trim())
        assertEquals(worktree.canonicalPath, gitRoot.canonicalPath)
    }

    private fun runShell(
        command: String,
        workingDirectory: File,
        environment: Map<String, String> = emptyMap(),
    ): String {
        val process = ProcessBuilder("/bin/sh", "-c", command)
            .directory(workingDirectory)
            .redirectErrorStream(true)
            .apply { environment().putAll(environment) }
            .start()
        val output = process.inputStream.bufferedReader().readText()
        val exitCode = process.waitFor()
        assertEquals(0, exitCode, output)
        return output
    }
}
