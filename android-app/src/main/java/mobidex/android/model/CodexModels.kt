package mobidex.android.model

import java.time.Instant
import mobidex.shared.CodexSessionFileChange
import mobidex.shared.CodexSessionItem
import mobidex.shared.CodexSessionProjection
import mobidex.shared.CodexSessionThread
import mobidex.shared.CodexSessionTurn
import mobidex.shared.ConversationSection

data class CodexThread(
    val id: String,
    val preview: String,
    val cwd: String,
    val status: CodexThreadStatus,
    val updatedAtEpochSeconds: Long,
    val createdAtEpochSeconds: Long,
    val name: String? = null,
    val sourceKind: String? = null,
    val turns: List<CodexTurn> = emptyList(),
) {
    val title: String
        get() = name?.trim()?.ifEmpty { null }
            ?: preview.trim().ifEmpty { null }
            ?: cwd.trimEnd('/').substringAfterLast('/').ifEmpty { id }

    val updatedAt: Instant
        get() = Instant.ofEpochSecond(updatedAtEpochSeconds)

    val isUserFacingSession: Boolean
        get() = sourceKind?.startsWith("subAgent") != true
}

data class CodexThreadStatus(
    val type: String,
    val activeFlags: List<String> = emptyList(),
) {
    val isActive: Boolean
        get() = type == "active"

    val sessionLabel: String
        get() = when (type) {
            "active" -> if (activeFlags.isEmpty()) "Working" else "Working: ${activeFlags.joinToString()}"
            "idle" -> "Ready"
            "notLoaded" -> "Loading"
            "systemError" -> "Needs Attention"
            else -> type
        }
}

data class CodexTokenUsage(
    val contextFraction: Double?,
    val contextPercent: Int?,
)

data class CodexTurn(
    val id: String,
    val items: List<CodexThreadItem>,
    val status: String,
)

data class CodexFileChange(
    val path: String,
    val diff: String,
)

sealed interface CodexThreadItem {
    val id: String

    data class UserMessage(override val id: String, val text: String) : CodexThreadItem
    data class AgentMessage(override val id: String, val text: String) : CodexThreadItem
    data class Reasoning(override val id: String, val summary: List<String>, val content: List<String>) : CodexThreadItem
    data class Plan(override val id: String, val text: String) : CodexThreadItem
    data class Command(override val id: String, val command: String, val cwd: String, val status: String, val output: String?) : CodexThreadItem
    data class FileChange(override val id: String, val changes: List<CodexFileChange>, val status: String) : CodexThreadItem
    data class ToolCall(override val id: String, val label: String, val status: String, val detail: String?) : CodexThreadItem
    data class AgentEvent(override val id: String, val label: String, val status: String, val detail: String?) : CodexThreadItem
    data class WebSearch(override val id: String, val query: String) : CodexThreadItem
    data class Image(override val id: String, val label: String) : CodexThreadItem
    data class Review(override val id: String, val label: String) : CodexThreadItem
    data class ContextCompaction(override val id: String) : CodexThreadItem
    data class Unknown(override val id: String, val type: String) : CodexThreadItem
}

fun CodexThread.conversationSections(): List<ConversationSection> =
    CodexSessionProjection.sections(
        CodexSessionThread(
            turns = turns.map { turn ->
                CodexSessionTurn(
                    id = turn.id,
                    status = turn.status,
                    items = turn.items.map { it.toSharedItem() },
                )
            }
        )
    )

fun List<CodexThreadItem>.conversationSectionsFromItems(): List<ConversationSection> =
    CodexSessionProjection.sections(map { it.toSharedItem() })

private fun CodexThreadItem.toSharedItem(): CodexSessionItem =
    when (this) {
        is CodexThreadItem.UserMessage -> CodexSessionItem.UserMessage(id, text)
        is CodexThreadItem.AgentMessage -> CodexSessionItem.AgentMessage(id, text)
        is CodexThreadItem.Reasoning -> CodexSessionItem.Reasoning(id, summary, content)
        is CodexThreadItem.Plan -> CodexSessionItem.Plan(id, text)
        is CodexThreadItem.Command -> CodexSessionItem.Command(id, command, cwd, status, output)
        is CodexThreadItem.FileChange -> CodexSessionItem.FileChange(id, changes.map { CodexSessionFileChange(it.path, it.diff) }, status)
        is CodexThreadItem.ToolCall -> CodexSessionItem.ToolCall(id, label, status, detail)
        is CodexThreadItem.AgentEvent -> CodexSessionItem.AgentEvent(id, label, status, detail)
        is CodexThreadItem.WebSearch -> CodexSessionItem.WebSearch(id, query)
        is CodexThreadItem.Image -> CodexSessionItem.Image(id, label)
        is CodexThreadItem.Review -> CodexSessionItem.Review(id, label)
        is CodexThreadItem.ContextCompaction -> CodexSessionItem.ContextCompaction(id)
        is CodexThreadItem.Unknown -> CodexSessionItem.Unknown(id, type)
    }

data class PendingApproval(
    val id: String,
    val requestId: kotlinx.serialization.json.JsonElement,
    val method: String,
    val params: kotlinx.serialization.json.JsonElement?,
    val title: String,
    val detail: String,
)
