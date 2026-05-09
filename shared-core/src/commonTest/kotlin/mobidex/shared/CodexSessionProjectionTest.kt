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

    @Test
    fun duplicateItemIDsStillProduceUniqueSectionIDs() {
        val sections = CodexSessionProjection.sections(
            listOf(
                CodexSessionItem.AgentMessage(id = "agent", text = "First"),
                CodexSessionItem.AgentMessage(id = "agent#2", text = "Existing suffix"),
                CodexSessionItem.AgentMessage(id = "agent", text = "Second"),
                CodexSessionItem.Plan(id = "plan", text = "Plan"),
                CodexSessionItem.Plan(id = "plan", text = "Updated plan"),
            )
        )

        assertEquals(listOf("agent", "agent#2", "agent#3", "plan", "plan#2"), sections.map { it.id })
        assertEquals(listOf("First", "Existing suffix", "Second", "Plan", "Updated plan"), sections.map { it.body })
    }
}
