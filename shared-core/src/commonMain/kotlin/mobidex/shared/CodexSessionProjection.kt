package mobidex.shared

data class ConversationSection(
    val id: String,
    val kind: ConversationSectionKind,
    val title: String,
    val body: String,
    val detail: String? = null,
    val status: String? = null,
) {
    val isCollapsedByDefault: Boolean
        get() = when (kind) {
            ConversationSectionKind.Command,
            ConversationSectionKind.FileChange,
            ConversationSectionKind.Tool,
            ConversationSectionKind.Agent -> true
            ConversationSectionKind.User,
            ConversationSectionKind.Assistant,
            ConversationSectionKind.Reasoning,
            ConversationSectionKind.Plan,
            ConversationSectionKind.Search,
            ConversationSectionKind.Media,
            ConversationSectionKind.Review,
            ConversationSectionKind.System -> false
        }

    val rendersMarkdown: Boolean
        get() = when (kind) {
            ConversationSectionKind.Assistant,
            ConversationSectionKind.Reasoning,
            ConversationSectionKind.Plan,
            ConversationSectionKind.Review,
            ConversationSectionKind.System -> true
            ConversationSectionKind.User,
            ConversationSectionKind.Command,
            ConversationSectionKind.FileChange,
            ConversationSectionKind.Tool,
            ConversationSectionKind.Agent,
            ConversationSectionKind.Search,
            ConversationSectionKind.Media -> false
        }

    val usesCompactTypography: Boolean
        get() = when (kind) {
            ConversationSectionKind.Command,
            ConversationSectionKind.FileChange,
            ConversationSectionKind.Tool,
            ConversationSectionKind.Agent -> true
            ConversationSectionKind.User,
            ConversationSectionKind.Assistant,
            ConversationSectionKind.Reasoning,
            ConversationSectionKind.Plan,
            ConversationSectionKind.Search,
            ConversationSectionKind.Media,
            ConversationSectionKind.Review,
            ConversationSectionKind.System -> false
        }
}

enum class ConversationSectionKind {
    User,
    Assistant,
    Reasoning,
    Plan,
    Command,
    FileChange,
    Tool,
    Agent,
    Search,
    Media,
    Review,
    System,
}

data class CodexSessionThread(
    val turns: List<CodexSessionTurn>,
)

data class CodexSessionTurn(
    val id: String,
    val items: List<CodexSessionItem>,
    val status: String,
)

data class CodexSessionFileChange(
    val path: String,
    val diff: String,
)

sealed interface CodexSessionItem {
    val id: String

    data class UserMessage(override val id: String, val text: String) : CodexSessionItem
    data class AgentMessage(override val id: String, val text: String) : CodexSessionItem
    data class Reasoning(override val id: String, val summary: List<String>, val content: List<String>) : CodexSessionItem
    data class Plan(override val id: String, val text: String) : CodexSessionItem
    data class Command(
        override val id: String,
        val command: String,
        val cwd: String,
        val status: String,
        val output: String?,
    ) : CodexSessionItem
    data class FileChange(
        override val id: String,
        val changes: List<CodexSessionFileChange>,
        val status: String,
    ) : CodexSessionItem
    data class ToolCall(override val id: String, val label: String, val status: String, val detail: String?) : CodexSessionItem
    data class AgentEvent(override val id: String, val label: String, val status: String, val detail: String?) : CodexSessionItem
    data class WebSearch(override val id: String, val query: String) : CodexSessionItem
    data class Image(override val id: String, val label: String) : CodexSessionItem
    data class Review(override val id: String, val label: String) : CodexSessionItem
    data class ContextCompaction(override val id: String) : CodexSessionItem
    data class Unknown(override val id: String, val type: String) : CodexSessionItem
}

object CodexSessionProjection {
    fun sections(thread: CodexSessionThread): List<ConversationSection> =
        thread.turns.flatMap { turn ->
            turn.items.map { item -> section(item, turn.id) }
        }

    fun sections(items: List<CodexSessionItem>): List<ConversationSection> =
        items.map { item -> section(item, "live") }

    private fun section(item: CodexSessionItem, turnId: String): ConversationSection =
        when (item) {
            is CodexSessionItem.UserMessage -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.User,
                title = "You",
                body = item.text,
            )
            is CodexSessionItem.AgentMessage -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Assistant,
                title = "Codex",
                body = item.text,
            )
            is CodexSessionItem.Reasoning -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Reasoning,
                title = "Reasoning",
                body = (item.summary + item.content).joinToString("\n\n"),
            )
            is CodexSessionItem.Plan -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Plan,
                title = "Plan",
                body = item.text,
            )
            is CodexSessionItem.Command -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Command,
                title = item.command,
                body = item.output ?: "",
                detail = item.cwd,
                status = item.status,
            )
            is CodexSessionItem.FileChange -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.FileChange,
                title = "File changes",
                body = item.changes.joinToString("\n\n") { change ->
                    listOf(change.path, change.diff).filter { it.isNotEmpty() }.joinToString("\n")
                },
                status = item.status,
            )
            is CodexSessionItem.ToolCall -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Tool,
                title = item.label,
                body = item.detail ?: "",
                status = item.status,
            )
            is CodexSessionItem.AgentEvent -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Agent,
                title = item.label,
                body = item.detail ?: "",
                status = item.status,
            )
            is CodexSessionItem.WebSearch -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Search,
                title = "Web search",
                body = item.query,
            )
            is CodexSessionItem.Image -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Media,
                title = "Image",
                body = item.label,
            )
            is CodexSessionItem.Review -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.Review,
                title = "Review",
                body = item.label,
            )
            is CodexSessionItem.ContextCompaction -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.System,
                title = "Compaction",
                body = "Context was compacted.",
            )
            is CodexSessionItem.Unknown -> ConversationSection(
                id = item.id,
                kind = ConversationSectionKind.System,
                title = item.type,
                body = "Unsupported app-server item in turn $turnId.",
            )
        }
}
