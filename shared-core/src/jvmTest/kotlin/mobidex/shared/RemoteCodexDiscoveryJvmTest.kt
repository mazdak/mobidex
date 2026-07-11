package mobidex.shared

import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals

class RemoteCodexDiscoveryJvmTest {
    @Test
    fun discoveryKeepsInteractiveAndAppServerRowsButExcludesExec() {
        val temp = Files.createTempDirectory("mobidex-codex-discovery").toFile()
        try {
            val home = File(temp, "codex-home").also { it.mkdirs() }
            val cliProject = File(temp, "cli-project").also { it.mkdirs() }
            val appServerProject = File(temp, "app-server-project").also { it.mkdirs() }
            val execProject = File(temp, "exec-project").also { it.mkdirs() }
            val database = File(home, "state_5.sqlite")

            runPython(
                """
                import sqlite3
                import sys

                connection = sqlite3.connect(sys.argv[1])
                connection.execute(
                    "create table threads (id text, cwd text, title text, updated_at integer, archived integer, source text)"
                )
                connection.executemany(
                    "insert into threads values (?, ?, ?, ?, ?, ?)",
                    [
                        ("cli-thread", sys.argv[2], "CLI", 30, 0, "cli"),
                        ("app-server-thread", sys.argv[3], "App Server", 20, 0, "appServer"),
                        ("exec-thread", sys.argv[4], "Exec", 10, 0, "exec"),
                    ],
                )
                connection.commit()
                """.trimIndent(),
                database.absolutePath,
                cliProject.absolutePath,
                appServerProject.absolutePath,
                execProject.absolutePath,
            )

            val output = runPython(
                RemoteCodexDiscovery.pythonSource,
                environment = mapOf("CODEX_HOME" to home.absolutePath),
            )
            val projects = RemoteCodexDiscovery.decodeProjects(output)

            assertEquals(
                setOf(cliProject.canonicalPath, appServerProject.canonicalPath),
                projects.map { File(it.path).canonicalPath }.toSet(),
            )
            assertEquals(setOf(1), projects.map { it.discoveredSessionCount }.toSet())
        } finally {
            temp.deleteRecursively()
        }
    }

    private fun runPython(
        source: String,
        vararg arguments: String,
        environment: Map<String, String> = emptyMap(),
    ): String {
        val process = ProcessBuilder(listOf("python3", "-c", source) + arguments)
            .redirectErrorStream(true)
            .apply { environment().putAll(environment) }
            .start()
        val output = process.inputStream.bufferedReader().readText()
        val exitCode = process.waitFor()
        assertEquals(0, exitCode, output)
        return output
    }
}
