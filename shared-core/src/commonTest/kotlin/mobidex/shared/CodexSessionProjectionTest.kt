package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CodexSessionProjectionTest {
    @Test
    fun projectsConversationItemsIntoSections() {
        val sections = CodexSessionProjection.sections(
            listOf(
                CodexSessionItem.UserMessage(id = "user", text = "Run tests"),
                CodexSessionItem.AgentMessage(id = "agent", text = "Done"),
                CodexSessionItem.Reasoning(id = "reasoning", summary = listOf("Check logs"), content = listOf("Need compile")),
                CodexSessionItem.Command(id = "command", command = "bun test", cwd = "/srv/app", status = "completed", output = "ok"),
                CodexSessionItem.FileChange(
                    id = "file",
                    changes = listOf(CodexSessionFileChange(path = "src/app.ts", diff = "@@\n-old\n+new")),
                    status = "completed",
                ),
            )
        )

        assertEquals(listOf("You", "Codex", "Reasoning", "bun test", "File changes"), sections.map { it.title })
        assertEquals("Check logs\n\nNeed compile", sections[2].body)
        assertTrue(sections[3].isCollapsedByDefault)
        assertTrue(sections[3].usesCompactTypography)
        assertFalse(sections[3].rendersMarkdown)
        assertEquals("src/app.ts\n@@\n-old\n+new", sections[4].body)
    }

    @Test
    fun unknownItemsIncludeTurnContext() {
        val sections = CodexSessionProjection.sections(
            CodexSessionThread(
                turns = listOf(
                    CodexSessionTurn(
                        id = "turn-1",
                        status = "completed",
                        items = listOf(CodexSessionItem.Unknown(id = "unknown", type = "futureItem")),
                    )
                )
            )
        )

        assertEquals("futureItem", sections.single().title)
        assertEquals("Unsupported app-server item in turn turn-1.", sections.single().body)
    }
}
