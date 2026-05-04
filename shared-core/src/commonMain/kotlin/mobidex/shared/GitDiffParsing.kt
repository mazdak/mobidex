package mobidex.shared

data class ChangedFileDiff(
    val path: String,
    val diff: String,
)

data class GitDiffSnapshot(
    val sha: String,
    val diff: String,
    val files: List<ChangedFileDiff>,
) {
    val isEmpty: Boolean
        get() = diff.trim().isEmpty() || files.isEmpty()

    companion object {
        val Empty = GitDiffSnapshot(sha = "", diff = "", files = emptyList())
    }
}

object GitDiffChangedFileParser {
    fun paths(diff: String): List<String> {
        val paths = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        var pendingOldPath: String? = null

        fun append(path: String?) {
            if (path.isNullOrEmpty() || path == "/dev/null" || !seen.add(path)) return
            paths.add(path)
        }

        for (line in diff.split('\n')) {
            when {
                line.startsWith("diff --git ") -> {
                    append(diffGitDestinationPath(line))
                    pendingOldPath = null
                }
                line.startsWith("--- ") -> {
                    pendingOldPath = normalizedDiffPath(line.drop(4))
                }
                line.startsWith("+++ ") -> {
                    val nextPath = normalizedDiffPath(line.drop(4))
                    append(nextPath ?: pendingOldPath)
                    pendingOldPath = null
                }
                line.startsWith("rename to ") -> {
                    append(line.drop("rename to ".length))
                }
            }
        }

        return paths
    }

    private fun diffGitDestinationPath(line: String): String? {
        val payload = line.drop("diff --git ".length)
        unquotedDiffGitDestinationPath(payload)?.let { return it }
        val pathTokens = parseDiffPathTokens(payload)
        if (pathTokens.size < 2) return null
        return normalizedDiffPath(pathTokens[1])
    }

    private fun unquotedDiffGitDestinationPath(value: String): String? {
        val trimmed = value.trim()
        if (trimmed.startsWith("\"")) return null
        val separator = value.lastIndexOf(" b/")
        if (separator < 0) return null
        return normalizedDiffPath(value.substring(separator + 1))
    }

    private fun parseDiffPathTokens(value: String): List<String> {
        val tokens = mutableListOf<String>()
        var index = 0

        fun advancePastWhitespace() {
            while (index < value.length && value[index].isWhitespace()) {
                index += 1
            }
        }

        while (index < value.length) {
            advancePastWhitespace()
            if (index >= value.length) break

            if (value[index] == '"') {
                index += 1
                val token = StringBuilder()
                var isEscaped = false
                while (index < value.length) {
                    val character = value[index]
                    index += 1
                    when {
                        isEscaped -> {
                            token.append(unescapedGitQuotedCharacter(character))
                            isEscaped = false
                        }
                        character == '\\' -> isEscaped = true
                        character == '"' -> break
                        else -> token.append(character)
                    }
                }
                tokens.add(token.toString())
            } else {
                val start = index
                while (index < value.length && !value[index].isWhitespace()) {
                    index += 1
                }
                tokens.add(value.substring(start, index))
            }
        }

        return tokens
    }

    private fun normalizedDiffPath(path: String): String? {
        val trimmed = unquotedGitPath(path).trim()
        if (trimmed == "/dev/null") return null
        val normalized = if (trimmed.startsWith("a/") || trimmed.startsWith("b/")) {
            trimmed.drop(2)
        } else {
            trimmed
        }
        return normalized.ifEmpty { null }
    }

    private fun unquotedGitPath(path: String): String {
        val trimmed = path.trim()
        if (!trimmed.startsWith("\"") || !trimmed.endsWith("\"")) return trimmed
        return parseDiffPathTokens(trimmed).firstOrNull() ?: trimmed
    }

    private fun unescapedGitQuotedCharacter(character: Char): Char =
        when (character) {
            'n' -> '\n'
            't' -> '\t'
            'r' -> '\r'
            else -> character
        }
}

object GitDiffFileParser {
    fun files(diff: String): List<ChangedFileDiff> {
        val lines = diff.split('\n')
        if (lines.none { it.startsWith("diff --git ") }) {
            return if (diff.trim().isEmpty()) {
                emptyList()
            } else {
                listOf(ChangedFileDiff(path = "Working Tree", diff = diff))
            }
        }

        val files = mutableListOf<ChangedFileDiff>()
        val currentLines = mutableListOf<String>()

        fun flush() {
            if (currentLines.isEmpty()) return
            val fileDiff = currentLines.joinToString("\n")
            val path = GitDiffChangedFileParser.paths(fileDiff).firstOrNull() ?: "Changed File"
            files.add(ChangedFileDiff(path = path, diff = fileDiff))
            currentLines.clear()
        }

        for (line in lines) {
            if (line.startsWith("diff --git ")) {
                flush()
            }
            currentLines.add(line)
        }
        flush()

        return files
    }
}
