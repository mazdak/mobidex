package mobidex.shared

object ProjectCatalog {
    fun refreshedProjects(
        existingProjects: List<ProjectRecord>,
        discoveredProjects: List<RemoteProject>,
        openSessions: List<CodexThreadSummary>?,
    ): List<ProjectRecord> {
        val recordsByPath = existingProjects.associateBy { it.path }.toMutableMap()
        val discoveredPaths = discoveredProjects.mapTo(mutableSetOf()) { it.path }

        for (path in recordsByPath.keys.toList()) {
            val record = recordsByPath[path] ?: continue
            if (!record.discovered || path in discoveredPaths) continue
            if (record.isFavorite) {
                recordsByPath[path] = record.copy(
                    discovered = false,
                    sessionPaths = listOf(record.path),
                    discoveredSessionCount = 0,
                    archivedSessionCount = 0,
                    lastDiscoveredAtEpochSeconds = null,
                )
            } else {
                recordsByPath.remove(path)
            }
        }

        for (project in discoveredProjects) {
            val record = recordsByPath[project.path] ?: ProjectRecord(path = project.path)
            recordsByPath[project.path] = record.copy(
                discovered = true,
                sessionPaths = ProjectRecord.normalizedSessionPaths(project.sessionPaths, project.path),
                discoveredSessionCount = project.discoveredSessionCount,
                archivedSessionCount = project.archivedSessionCount,
                lastDiscoveredAtEpochSeconds = project.lastDiscoveredAtEpochSeconds,
            )
        }

        if (openSessions != null) {
            applyOpenSessionCounts(openSessions, recordsByPath)
        }

        return recordsByPath.values.sortedWith(projectCatalogComparator)
    }

    private fun applyOpenSessionCounts(
        sessions: List<CodexThreadSummary>,
        projects: MutableMap<String, ProjectRecord>,
    ) {
        for ((path, record) in projects.toMap()) {
            projects[path] = record.copy(activeChatCount = 0, lastActiveChatAtEpochSeconds = null)
        }

        val projectPathBySessionPath = mutableMapOf<String, String>()
        val projectPathByCodexWorktreeName = mutableMapOf<String, String>()
        val ambiguousCodexWorktreeNames = mutableSetOf<String>()

        fun addCodexWorktreeCandidate(path: String) {
            if (isCodexWorktreePath(path)) return
            val name = path.substringAfterLast('/')
            if (name in projectPathByCodexWorktreeName && projectPathByCodexWorktreeName[name] != path) {
                ambiguousCodexWorktreeNames.add(name)
            } else {
                projectPathByCodexWorktreeName[name] = path
            }
        }

        for ((path, record) in projects) {
            for (sessionPath in ProjectRecord.normalizedSessionPaths(record.sessionPaths, record.path)) {
                projectPathBySessionPath[sessionPath] = path
            }
            addCodexWorktreeCandidate(record.path)
        }
        for (session in sessions) {
            addCodexWorktreeCandidate(session.cwd)
        }
        for (name in ambiguousCodexWorktreeNames) {
            projectPathByCodexWorktreeName.remove(name)
        }

        for (session in sessions) {
            val projectPath = projectPathBySessionPath[session.cwd]
                ?: codexWorktreeMainProjectPath(session.cwd, projectPathByCodexWorktreeName)
                ?: session.cwd
            val record = projects[projectPath] ?: ProjectRecord(path = projectPath, discovered = true)
            projects[projectPath] = record.copy(
                discovered = true,
                sessionPaths = ProjectRecord.normalizedSessionPaths(record.sessionPaths + session.cwd, record.path),
                activeChatCount = record.activeChatCount + 1,
                lastActiveChatAtEpochSeconds = maxOf(record.lastActiveChatAtEpochSeconds ?: Long.MIN_VALUE, session.updatedAtEpochSeconds),
            )
        }
    }

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

    private val projectCatalogComparator = Comparator<ProjectRecord> { lhs, rhs ->
        compareByDescending<ProjectRecord> { it.discoveredSessionCount }
            .thenByDescending { it.activeChatCount }
            .thenByDescending { it.archivedSessionCount }
            .thenByDescending { it.lastActiveChatAtEpochSeconds ?: it.lastDiscoveredAtEpochSeconds ?: Long.MIN_VALUE }
            .compare(lhs, rhs)
    }
}
