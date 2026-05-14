package mobidex.android.model

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class ServerModelsTest {
    @Test
    fun serverRecordNormalizationUsesSharedLaunchDefaults() {
        val server = ServerRecord(
            displayName = "  ",
            host = " build.example.com ",
            username = " mazdak ",
            codexPath = " ",
            targetShellRCFile = "",
            authMethod = ServerAuthMethod.Password,
        ).normalized

        assertEquals("build.example.com", server.displayName)
        assertEquals("build.example.com", server.host)
        assertEquals("mazdak", server.username)
        assertEquals("codex", server.codexPath)
        assertEquals("\$HOME/.zshrc", server.targetShellRCFile)
    }

    @Test
    fun appServerProxyCommandUsesSharedDefaultUnixSocketProxyLaunchShape() {
        val server = ServerRecord(
            displayName = "Server",
            host = "host",
            username = "user",
            codexPath = "~/.bun/bin/codex",
            authMethod = ServerAuthMethod.Password,
        )

        assertContains(server.appServerProxyCommand, "codex_bin=\"\${HOME}\"/'.bun/bin/codex'")
        assertContains(server.appServerProxyCommand, "app-server proxy --help")
        assertContains(server.appServerProxyCommand, "app-server --listen unix://")
        assertContains(server.appServerProxyCommand, "exec \"\$codex_bin\" app-server proxy")
        assertFalse(server.appServerProxyCommand.contains("proxy --sock"))
        assertFalse(server.appServerProxyCommand.contains("stdio://"))
    }
}
