package mobidex.android

import kotlin.test.Test
import kotlin.test.assertEquals
import mobidex.shared.CodexSessionItem
import mobidex.shared.CodexSessionProjection
import mobidex.shared.ConversationSectionAccumulator
import mobidex.shared.appendingAcpSessionItem

/**
 * Covers the ACP diff-detection helper (`applyItemsChange`): after any operation the
 * accumulator's sections must equal `CodexSessionProjection.sections(items)` exactly,
 * including `#n` dedup suffixes — the audit-B1 invariant.
 */
class ConversationSectionAccumulatorSyncTest {

    private fun ConversationSectionAccumulator.assertMatchesFullProjection(items: List<CodexSessionItem>) {
        assertEquals(CodexSessionProjection.sections(items), sections)
    }

    private fun ConversationSectionAccumulator.applyAndCheck(
        previous: List<CodexSessionItem>,
        next: List<CodexSessionItem>,
    ): List<CodexSessionItem> {
        applyItemsChange(previous, next)
        assertMatchesFullProjection(next)
        return next
    }

    @Test
    fun appendAndMergeStreamedMessagesStayEqualToFullProjection() {
        val accumulator = ConversationSectionAccumulator()
        var items = emptyList<CodexSessionItem>()
        items = accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.UserMessage("local-1", "hi")))
        items = accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.AgentMessage("acp-message", "Hel")))
        // Consecutive chunks merge into the last item: a single-index update.
        items = accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.AgentMessage("acp-message", "lo")))
        items = accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.ToolCall("tool-1", "read", "pending", null)))
        // A second bubble reuses the "acp-message" id: the dedup suffix must match the full projection.
        items = accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.AgentMessage("acp-message", "More")))
        accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.AgentMessage("acp-message", " text")))
    }

    @Test
    fun toolCallUpdateInTheMiddleIsMappedAsSingleIndexUpdate() {
        val accumulator = ConversationSectionAccumulator()
        val items = listOf<CodexSessionItem>(
            CodexSessionItem.ToolCall("tool-1", "read", "running", null),
            CodexSessionItem.AgentMessage("acp-message", "working"),
        )
        accumulator.reset(items)
        accumulator.assertMatchesFullProjection(items)
        accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.ToolCall("tool-1", "read", "completed", "done")))
    }

    @Test
    fun planReplacementKeepsProjectionEqual() {
        val accumulator = ConversationSectionAccumulator()
        val items = listOf<CodexSessionItem>(
            CodexSessionItem.Plan("acp-plan", "v1"),
            CodexSessionItem.AgentMessage("acp-message", "text"),
        )
        accumulator.reset(items)
        accumulator.applyAndCheck(items, items.appendingAcpSessionItem(CodexSessionItem.Plan("acp-plan", "v2")))
    }

    @Test
    fun changedItemIdAtSameIndexFallsBackToFullReset() {
        val accumulator = ConversationSectionAccumulator()
        val previous = listOf<CodexSessionItem>(CodexSessionItem.UserMessage("a", "one"))
        accumulator.reset(previous)
        // Same index, different item id: row identity changed, so updateAt would be wrong.
        accumulator.applyAndCheck(previous, listOf(CodexSessionItem.UserMessage("b", "one")))
    }

    @Test
    fun multiIndexChangeFallsBackToFullReset() {
        val accumulator = ConversationSectionAccumulator()
        val previous = listOf<CodexSessionItem>(
            CodexSessionItem.UserMessage("a", "one"),
            CodexSessionItem.AgentMessage("b", "two"),
        )
        accumulator.reset(previous)
        accumulator.applyAndCheck(
            previous,
            listOf(
                CodexSessionItem.UserMessage("a", "one!"),
                CodexSessionItem.AgentMessage("b", "two!"),
            ),
        )
    }

    @Test
    fun removalFallsBackToFullReset() {
        val accumulator = ConversationSectionAccumulator()
        val previous = listOf<CodexSessionItem>(
            CodexSessionItem.UserMessage("a", "one"),
            CodexSessionItem.AgentMessage("b", "two"),
        )
        accumulator.reset(previous)
        accumulator.applyAndCheck(previous, previous.dropLast(1))
    }

    @Test
    fun outOfSyncAccumulatorResetsFromNext() {
        // The accumulator is empty but `previous` claims one item: structural mismatch.
        val accumulator = ConversationSectionAccumulator()
        val previous = listOf<CodexSessionItem>(CodexSessionItem.UserMessage("a", "one"))
        accumulator.applyAndCheck(previous, previous + CodexSessionItem.AgentMessage("acp-message", "x"))
    }

    @Test
    fun unchangedListIsANoOp() {
        val accumulator = ConversationSectionAccumulator()
        val items = listOf<CodexSessionItem>(
            CodexSessionItem.UserMessage("a", "one"),
            CodexSessionItem.AgentMessage("acp-message", "two"),
        )
        accumulator.reset(items)
        accumulator.applyAndCheck(items, items)
    }
}
