package mobidex.android.service

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlinx.serialization.json.Json

class JsonParsingTest {
    @Test
    fun currentSubAgentSourceIsNotUserFacing() {
        val thread = parseThread(
            Json.parseToJsonElement(
                """
                {
                  "id": "thread-subagent",
                  "preview": "Review worker",
                  "cwd": "/srv/app",
                  "source": {"subAgent": "review"},
                  "status": {"type": "idle"},
                  "updatedAt": 1770000400,
                  "createdAt": 1770000000,
                  "turns": []
                }
                """.trimIndent()
            )
        )

        assertEquals("subAgent", thread.sourceKind)
        assertFalse(thread.isUserFacingSession)
    }
}
