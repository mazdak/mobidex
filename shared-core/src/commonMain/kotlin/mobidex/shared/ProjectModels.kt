package mobidex.shared

data class RemoteProject(
    val path: String,
    val sessionPaths: List<String> = listOf(path),
    val discoveredSessionCount: Int,
    val lastDiscoveredAtEpochSeconds: Long? = null,
)

data class ProjectRecord(
    val path: String,
    val sessionPaths: List<String> = listOf(path),
    val displayName: String = defaultProjectDisplayName(path),
    val discovered: Boolean = false,
    val discoveredSessionCount: Int = 0,
    val activeChatCount: Int = 0,
    val lastDiscoveredAtEpochSeconds: Long? = null,
    val lastActiveChatAtEpochSeconds: Long? = null,
    val isFavorite: Boolean = false,
) {
    fun normalized(): ProjectRecord =
        copy(sessionPaths = normalizedSessionPaths(sessionPaths, path))

    companion object {
        fun normalizedSessionPaths(paths: List<String>, primaryPath: String): List<String> {
            val seen = linkedSetOf<String>()
            return (listOf(primaryPath) + paths).filter { path ->
                path.isNotEmpty() && seen.add(path)
            }
        }
    }
}

data class CodexThreadSummary(
    val id: String,
    val cwd: String,
    val updatedAtEpochSeconds: Long,
)

data class SessionListSection(
    val id: String,
    val title: String,
    val sessionIds: List<String>,
)


private fun defaultProjectDisplayName(path: String): String {
    val trimmed = path.trimEnd('/')
    return trimmed.substringAfterLast('/').ifEmpty { path }
}
