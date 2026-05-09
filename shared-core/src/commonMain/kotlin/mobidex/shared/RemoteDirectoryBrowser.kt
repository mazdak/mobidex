package mobidex.shared

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class RemoteDirectoryBrowserException(message: String) : Exception(message)

@Serializable
data class RemoteDirectoryEntry(
    val name: String,
    val path: String,
)

@Serializable
data class RemoteDirectoryListing(
    val path: String,
    val entries: List<RemoteDirectoryEntry>,
)

object RemoteDirectoryBrowser {
    fun shellCommand(path: String): String {
        val encodedPath = JsonValueCodec.encode(jsonString(path))
        return """
python3 - <<'PY'
import json
import os

requested_path = $encodedPath
try:
    current_path = os.path.realpath(os.path.expanduser(requested_path))
    entries = []
    with os.scandir(current_path) as iterator:
        for entry in iterator:
            try:
                if entry.is_dir(follow_symlinks=True):
                    entries.append({
                        "name": entry.name,
                        "path": os.path.realpath(entry.path),
                    })
            except OSError:
                pass
    entries.sort(key=lambda item: item["name"].lower())
    print(json.dumps({"path": current_path, "entries": entries}))
except Exception as error:
    print(json.dumps({"path": requested_path, "entries": [], "error": str(error)}))
PY
        """.trimIndent()
    }

    @Throws(RemoteDirectoryBrowserException::class)
    fun decodeListing(output: String): RemoteDirectoryListing {
        try {
            val wire = directoryJson.decodeFromString<RemoteDirectoryListingWire>(output.trim())
            val error = wire.error
            if (!error.isNullOrBlank()) {
                throw RemoteDirectoryBrowserException(error)
            }
            return RemoteDirectoryListing(path = wire.path, entries = wire.entries)
        } catch (error: RemoteDirectoryBrowserException) {
            throw error
        } catch (error: Throwable) {
            val preview = decodePreview(output)
            throw RemoteDirectoryBrowserException(preview.ifBlank { error.message ?: "output was not valid directory JSON" })
        }
    }

    private val directoryJson = Json {
        ignoreUnknownKeys = true
    }

    private fun decodePreview(value: String, limit: Int = 320): String {
        val trimmed = value.trim().replace('\n', ' ')
        return if (trimmed.length <= limit) trimmed else "${trimmed.take(limit)}..."
    }
}

@Serializable
private data class RemoteDirectoryListingWire(
    val path: String,
    val entries: List<RemoteDirectoryEntry>,
    val error: String? = null,
)
