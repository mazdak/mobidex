package mobidex.android.model

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertFalse

class ServerModelsTest {
    @Test
    fun appServerProxyCommandUsesSharedControlSocketLaunchShape() {
        val server = ServerRecord(
            displayName = "Server",
            host = "host",
            username = "user",
            codexPath = "~/.bun/bin/codex",
            authMethod = ServerAuthMethod.Password,
        )

        assertContains(server.appServerProxyCommand, "codex_bin=\"\${HOME}\"/'.bun/bin/codex'")
        assertContains(server.appServerProxyCommand, "app-server --listen \"unix://\$socket\"")
        assertContains(server.appServerProxyCommand, "app-server proxy --sock \"\$socket\"")
        assertFalse(server.appServerProxyCommand.contains("stdio://"))
    }
}
