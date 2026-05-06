package mobidex.android.service

import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import mobidex.android.model.CodexFileChange
import mobidex.android.model.CodexThread
import mobidex.android.model.CodexThreadItem
import mobidex.android.model.CodexThreadStatus
import mobidex.android.model.CodexTokenUsage
import mobidex.android.model.CodexTurn
import mobidex.shared.JsonValue
import mobidex.shared.jsonArray
import mobidex.shared.jsonBool
import mobidex.shared.jsonDouble
import mobidex.shared.jsonInt
import mobidex.shared.jsonNull
import mobidex.shared.jsonObject
import mobidex.shared.jsonString

internal val AppJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
}

internal fun JsonElement.toSharedJsonValue(): JsonValue =
    when (this) {
        JsonNull -> jsonNull()
        is JsonObject -> jsonObject(mapValues { it.value.toSharedJsonValue() })
        is JsonArray -> jsonArray(map { it.toSharedJsonValue() })
        is JsonPrimitive -> when {
            isString -> jsonString(content)
            booleanOrNull != null -> jsonBool(booleanOrNull!!)
            longOrNull != null -> jsonInt(longOrNull!!)
            doubleOrNull != null -> jsonDouble(doubleOrNull!!)
            else -> jsonString(content)
        }
    }

internal fun JsonValue.toJsonElement(): JsonElement =
    when (this) {
        JsonValue.Null -> JsonNull
        is JsonValue.BoolValue -> JsonPrimitive(value)
        is JsonValue.IntValue -> JsonPrimitive(value)
        is JsonValue.DoubleValue -> JsonPrimitive(value)
        is JsonValue.StringValue -> JsonPrimitive(value)
        is JsonValue.ArrayValue -> JsonArray(value.map { it.toJsonElement() })
        is JsonValue.ObjectValue -> JsonObject(value.mapValues { it.value.toJsonElement() })
    }

internal fun JsonElement?.string(key: String): String? =
    (this as? JsonObject)?.get(key)?.jsonPrimitive?.contentOrNull

internal fun JsonElement?.long(key: String): Long? =
    (this as? JsonObject)?.get(key)?.jsonPrimitive?.contentOrNull?.toLongOrNull()

internal fun JsonElement?.obj(key: String): JsonObject? =
    (this as? JsonObject)?.get(key) as? JsonObject

internal fun JsonElement?.array(key: String): JsonArray? =
    (this as? JsonObject)?.get(key) as? JsonArray

internal fun parseThread(element: JsonElement): CodexThread {
    val source = element.obj("source")
    val sourceKind = element.string("sourceKind")
        ?: element.string("source")
        ?: source?.let { if (it.containsKey("subagent")) "subAgent" else null }
    return CodexThread(
        id = element.string("id") ?: UUID.randomUUID().toString(),
        preview = element.string("preview") ?: "",
        cwd = element.string("cwd") ?: "",
        status = parseStatus(element.obj("status")),
        updatedAtEpochSeconds = element.long("updatedAt") ?: 0,
        createdAtEpochSeconds = element.long("createdAt") ?: 0,
        name = element.string("name"),
        sourceKind = sourceKind,
        turns = element.array("turns")?.map(::parseTurn) ?: emptyList(),
    )
}

internal fun parseStatus(element: JsonObject?): CodexThreadStatus =
    CodexThreadStatus(
        type = element.string("type") ?: "unknown",
        activeFlags = element.array("activeFlags")?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: emptyList(),
    )

internal fun parseTurn(element: JsonElement): CodexTurn =
    CodexTurn(
        id = element.string("id") ?: UUID.randomUUID().toString(),
        items = element.array("items")?.map(::parseItem) ?: emptyList(),
        status = element.string("status") ?: "",
    )

internal fun parseItem(element: JsonElement): CodexThreadItem {
    val type = element.string("type") ?: "unknown"
    val id = element.string("id") ?: UUID.randomUUID().toString()
    return when (type) {
        "userMessage" -> CodexThreadItem.UserMessage(
            id = id,
            text = element.array("content")
                ?.map { parseUserInput(it) }
                ?.joinToString("\n")
                ?: "",
        )
        "agentMessage" -> CodexThreadItem.AgentMessage(id, element.string("text") ?: "")
        "reasoning" -> CodexThreadItem.Reasoning(
            id = id,
            summary = element.array("summary")?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: emptyList(),
            content = element.array("content")?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: emptyList(),
        )
        "plan" -> CodexThreadItem.Plan(id, element.string("text") ?: "")
        "commandExecution" -> CodexThreadItem.Command(
            id = id,
            command = element.string("command") ?: "",
            cwd = element.string("cwd") ?: "",
            status = element.string("status") ?: "",
            output = element.string("aggregatedOutput"),
        )
        "fileChange" -> CodexThreadItem.FileChange(
            id = id,
            changes = element.array("changes")?.map(::parseFileChange) ?: emptyList(),
            status = element.string("status") ?: "",
        )
        "mcpToolCall" -> CodexThreadItem.ToolCall(
            id = id,
            label = listOfNotNull(element.string("server"), element.string("tool") ?: "MCP tool").joinToString(" / "),
            status = element.string("status") ?: "",
            detail = null,
        )
        "dynamicToolCall" -> CodexThreadItem.ToolCall(
            id = id,
            label = listOfNotNull(element.string("namespace"), element.string("tool") ?: "Dynamic tool").joinToString(" / "),
            status = element.string("status") ?: "",
            detail = null,
        )
        "collabAgentToolCall" -> CodexThreadItem.AgentEvent(
            id = id,
            label = element.string("tool") ?: "Agent",
            status = element.string("status") ?: "",
            detail = element.string("prompt"),
        )
        "webSearch" -> CodexThreadItem.WebSearch(id, element.string("query") ?: "")
        "imageView" -> CodexThreadItem.Image(id, element.string("path") ?: "Image")
        "imageGeneration" -> CodexThreadItem.Image(id, element.string("result") ?: "Generated image")
        "enteredReviewMode", "exitedReviewMode" -> CodexThreadItem.Review(id, element.string("review") ?: type)
        "contextCompaction" -> CodexThreadItem.ContextCompaction(id)
        else -> CodexThreadItem.Unknown(id, type)
    }
}

private fun parseUserInput(element: JsonElement): String {
    val type = element.string("type") ?: return ""
    return when (type) {
        "text" -> element.string("text") ?: ""
        else -> "[${type}: ${element.string("name") ?: element.string("path") ?: element.string("url") ?: type}]"
    }
}

internal fun parseFileChange(element: JsonElement): CodexFileChange =
    CodexFileChange(
        path = element.string("path") ?: "",
        diff = element.string("diff") ?: "",
    )

internal fun parseTokenUsage(element: JsonElement?): CodexTokenUsage? {
    val totalTokens = element.obj("total")?.long("totalTokens") ?: return null
    val context = element.long("modelContextWindow")?.takeIf { it > 0 } ?: return CodexTokenUsage(null, null)
    val fraction = (totalTokens.toDouble() / context.toDouble()).coerceIn(0.0, 1.0)
    return CodexTokenUsage(fraction, (fraction * 100).toInt().coerceIn(0, 100))
}
