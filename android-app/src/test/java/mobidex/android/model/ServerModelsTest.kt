package mobidex.android.model

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlinx.serialization.json.Json
import mobidex.shared.RemoteAcpCommand
import mobidex.shared.RemoteServerLaunchDefaults

class ServerModelsTest {
    @Test
    fun backendTypeDecodesLegacyAcpGrokStoredValue() {
        // Pre-rename builds persisted "AcpGrok"; the same Json config the repository uses
        // must keep decoding those saved servers as the Acp backend.
        val json = Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
        }
        val legacy = json.decodeFromString<ServerRecord>(
            """{"displayName":"dev","host":"h","username":"u","authMethod":"Password","backendType":"AcpGrok"}"""
        )
        assertEquals(BackendType.Acp, legacy.backendType)
        val current = json.decodeFromString<ServerRecord>(
            """{"displayName":"dev","host":"h","username":"u","authMethod":"Password","backendType":"Acp"}"""
        )
        assertEquals(BackendType.Acp, current.backendType)
        // Unknown values (e.g. written by a newer build) coerce to the default instead of
        // failing the whole saved-server list (parity with iOS decoding).
        val unknown = json.decodeFromString<ServerRecord>(
            """{"displayName":"dev","host":"h","username":"u","authMethod":"Password","backendType":"FutureBackend"}"""
        )
        assertEquals(BackendType.CodexAppServer, unknown.backendType)
        // Records re-encode with the new name only.
        assertContains(json.encodeToString(ServerRecord.serializer(), legacy), "\"backendType\":\"Acp\"")
    }

    @Test
    fun serverRecordNormalizationUsesSharedLaunchDefaults() {
        val server = ServerRecord(
            displayName = "  ",
            host = " build.example.com ",
            username = " mazdak ",
            codexPath = " ",
            executionPath = " \$HOME/bin:/usr/bin:\$PATH ",
            authMethod = ServerAuthMethod.Password,
        ).normalized

        assertEquals("build.example.com", server.displayName)
        assertEquals("build.example.com", server.host)
        assertEquals("mazdak", server.username)
        assertEquals("codex", server.codexPath)
        assertEquals("\$HOME/bin:/usr/bin:\$PATH", server.executionPath)
        assertEquals(RemoteAcpCommand.defaultLaunchCommand, server.acpLaunchCommand)
        assertEquals(RemoteServerLaunchDefaults.executionPath, server.copy(executionPath = "").normalized.executionPath)
        assertEquals(RemoteAcpCommand.defaultLaunchCommand, server.copy(acpLaunchCommand = " ").normalized.acpLaunchCommand)
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
