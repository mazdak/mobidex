package mobidex.shared

object CodexFolderlessPaths {
    fun isFolderlessCwd(cwd: String): Boolean =
        cwd.isBlank() || folderlessCodexRoot(cwd) != null

    fun folderlessCodexRoot(cwd: String): String? {
        val trimmed = cwd.trim().trimEnd('/', '\\')
        if (trimmed.isEmpty()) return null
        val parts = trimmed
            .replace('\\', '/')
            .split('/')
            .filter { it.isNotEmpty() }
        val documentsIndex = parts.indexOfLast { it == "Documents" }
        if (documentsIndex <= 0 || documentsIndex + 1 >= parts.size) return null
        if (parts[documentsIndex + 1] != "Codex") return null
        val codexIndex = documentsIndex + 1
        if (codexIndex + 1 < parts.size &&
            (!parts[codexIndex + 1].isCodexChatDateFolder() || codexIndex + 2 >= parts.size)
        ) {
            return null
        }
        val prefix = if (trimmed.startsWith("/")) "/" else ""
        return prefix + parts.take(codexIndex + 1).joinToString("/")
    }

    private fun String.isCodexChatDateFolder(): Boolean =
        length == 10 &&
            this[4] == '-' &&
            this[7] == '-' &&
            take(4).all(Char::isDigit) &&
            substring(5, 7).all(Char::isDigit) &&
            substring(8, 10).all(Char::isDigit)
}
