package mobidex.shared

object SessionListSections {
    fun from(
        sessions: List<CodexThreadSummary>,
        projects: List<ProjectRecord>,
    ): List<SessionListSection> {
        val projectByPath = projects.associateBy { it.path }
        val projectPathBySessionPath = mutableMapOf<String, String>()
        val projectPathByCodexWorktreeName = mutableMapOf<String, String>()
        val ambiguousCodexWorktreeNames = mutableSetOf<String>()

        for (project in projects) {
            for (sessionPath in ProjectRecord.normalizedSessionPaths(project.sessionPaths, project.path)) {
                projectPathBySessionPath[sessionPath] = project.path
            }
            if (isCodexWorktreePath(project.path)) continue
            val name = project.path.substringAfterLast('/')
            if (name in projectPathByCodexWorktreeName) {
                ambiguousCodexWorktreeNames.add(name)
            } else {
                projectPathByCodexWorktreeName[name] = project.path
            }
        }
        for (name in ambiguousCodexWorktreeNames) {
            projectPathByCodexWorktreeName.remove(name)
        }

        val sessionsBySectionId = linkedMapOf<String, MutableList<CodexThreadSummary>>()
        for (session in sessions) {
            val sectionId = projectPathBySessionPath[session.cwd]
                ?: codexWorktreeMainProjectPath(session.cwd, projectPathByCodexWorktreeName)
                ?: session.cwd
            sessionsBySectionId.getOrPut(sectionId) { mutableListOf() }.add(session)
        }

        return sessionsBySectionId.map { (sectionId, sectionSessions) ->
            val sortedSessions = sectionSessions.sortedWith(sessionComparator)
            SessionListSection(
                id = sectionId,
                title = projectByPath[sectionId]?.displayName ?: sectionId,
                sessionIds = sortedSessions.map { it.id },
            )
        }.sortedWith(
            compareByDescending<SessionListSection> { section ->
                section.sessionIds
                    .mapNotNull { id -> sessions.firstOrNull { it.id == id }?.updatedAtEpochSeconds }
                    .maxOrNull() ?: Long.MIN_VALUE
            }.thenBy { it.title.lowercase() }
                .thenBy { it.id }
        )
    }

    private val sessionComparator = compareByDescending<CodexThreadSummary> { it.updatedAtEpochSeconds }
        .thenBy { it.id }

    private fun codexWorktreeMainProjectPath(cwd: String, candidates: Map<String, String>): String? {
        if (!isCodexWorktreePath(cwd)) return null
        return candidates[cwd.substringAfterLast('/')]
    }

    private fun isCodexWorktreePath(path: String): Boolean {
        val components = path.split('/').filter { it.isNotEmpty() }
        val codexIndex = components.lastIndexOf(".codex")
        val worktreesIndex = codexIndex + 1
        val hashIndex = codexIndex + 2
        val projectIndex = codexIndex + 3
        return codexIndex >= 0 &&
            projectIndex in components.indices &&
            hashIndex in components.indices &&
            worktreesIndex in components.indices &&
            components[worktreesIndex] == "worktrees" &&
            components[hashIndex].isNotEmpty() &&
            components[projectIndex].isNotEmpty()
    }
}
