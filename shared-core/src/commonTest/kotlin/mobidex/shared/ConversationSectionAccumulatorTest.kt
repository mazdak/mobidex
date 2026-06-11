package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ConversationSectionAccumulatorTest {
    private fun message(id: String, text: String): CodexSessionItem = CodexSessionItem.AgentMessage(id, text)
    private fun reasoning(id: String, content: String): CodexSessionItem =
        CodexSessionItem.Reasoning(id, summary = emptyList(), content = listOf(content))
    private fun tool(id: String, status: String): CodexSessionItem =
        CodexSessionItem.ToolCall(id, label = "tool-$id", status = status, detail = null)

    private fun assertInvariant(accumulator: ConversationSectionAccumulator, items: List<CodexSessionItem>) {
        assertEquals(CodexSessionProjection.sections(items), accumulator.sections)
    }

    @Test
    fun incrementalOpsMatchFullProjectionIncludingDedupSuffixes() {
        val accumulator = ConversationSectionAccumulator()
        val items = mutableListOf<CodexSessionItem>()

        fun append(item: CodexSessionItem) {
            items.add(item)
            accumulator.append(item)
            assertInvariant(accumulator, items)
        }

        fun updateAt(index: Int, item: CodexSessionItem) {
            items[index] = item
            assertTrue(accumulator.updateAt(index, item))
            assertInvariant(accumulator, items)
        }

        append(CodexSessionItem.UserMessage("u1", "hello"))
        append(message("acp-message", "Hel"))
        updateAt(1, message("acp-message", "Hello"))
        append(tool("call_1", "pending"))
        updateAt(2, tool("call_1", "completed"))
        // Duplicate stable ids — projection suffixes #2/#3; the accumulator must match.
        append(message("acp-message", "Second bubble"))
        append(message("acp-message", "Third bubble"))
        append(reasoning("acp-thought", "thinking"))
        updateAt(4, message("acp-message", "Third bubble, edited"))
        updateAt(5, reasoning("acp-thought", "thinking harder"))

        val ids = accumulator.sections.map { it.id }
        assertEquals(listOf("u1", "acp-message", "call_1", "acp-message#2", "acp-message#3", "acp-thought"), ids)
    }

    @Test
    fun updatePreservesAllocatedIdSoRowIdentityIsStable() {
        val accumulator = ConversationSectionAccumulator()
        accumulator.append(message("m", "a"))
        accumulator.append(message("m", "b"))
        val suffixed = accumulator.sections[1].id
        assertEquals("m#2", suffixed)
        assertTrue(accumulator.updateAt(1, message("m", "b + delta")))
        assertEquals(suffixed, accumulator.sections[1].id)
        assertEquals("b + delta", accumulator.sections[1].body)
    }

    @Test
    fun resetWithPrebuiltSectionsAdoptsThemAndContinuesDedupCorrectly() {
        val items = listOf<CodexSessionItem>(
            CodexSessionItem.UserMessage("u1", "hi"),
            message("m", "one"),
            message("m", "two"),
        )
        val prebuilt = CodexSessionProjection.sections(items)
        val accumulator = ConversationSectionAccumulator()
        accumulator.reset(items, prebuilt)
        assertEquals(prebuilt, accumulator.sections)

        // Appends after a prebuilt reset must keep suffixing where the baseline left off.
        accumulator.append(message("m", "three"))
        assertEquals("m#3", accumulator.sections.last().id)
        assertEquals(CodexSessionProjection.sections(items + message("m", "three")), accumulator.sections)
    }

    @Test
    fun resetWithoutPrebuiltProjectsFromItems() {
        val items = listOf(message("a", "x"), tool("t", "running"), message("a", "y"))
        val accumulator = ConversationSectionAccumulator()
        accumulator.reset(items)
        assertInvariant(accumulator, items)
        assertEquals(listOf("a", "t", "a#2"), accumulator.sections.map { it.id })
    }

    @Test
    fun updateOutOfRangeReportsFailureForFallback() {
        val accumulator = ConversationSectionAccumulator()
        assertFalse(accumulator.updateAt(0, message("m", "x")))
        assertFalse(accumulator.updateLast(message("m", "x")))
        accumulator.append(message("m", "x"))
        assertFalse(accumulator.updateAt(1, message("m", "y")))
    }
}
