package mobidex.shared

data class ProjectListSections(
    val favorites: List<ProjectRecord>,
    val discovered: List<ProjectRecord>,
    val added: List<ProjectRecord>,
    val showInactiveDiscoveredFilter: Boolean,
    val showArchivedSessionFilter: Boolean,
    val discoveredTitle: String = "Discovered",
) {
    val isEmpty: Boolean
        get() = favorites.isEmpty() && discovered.isEmpty() && added.isEmpty()

    companion object {
        fun from(
            projects: List<ProjectRecord>,
            searchText: String,
            showInactiveDiscoveredProjects: Boolean,
            showArchivedSessionProjects: Boolean = false,
        ): ProjectListSections {
            val trimmedSearch = searchText.trim()
            val searching = trimmedSearch.isNotEmpty()
            val matching = projects.filter { project ->
                !searching ||
                    project.displayName.contains(trimmedSearch, ignoreCase = true) ||
                    project.path.contains(trimmedSearch, ignoreCase = true)
            }
            val sorted = matching.sortedWith(projectListComparator)

            return ProjectListSections(
                favorites = sorted.filter { it.isFavorite },
                discovered = sorted.filter { project ->
                    val hasVisibleSessions = project.activeChatCount > 0 ||
                        project.discoveredSessionCount > 0 ||
                        (project.archivedSessionCount > 0 && showArchivedSessionProjects)
                    val canSearchHiddenProject = searching &&
                        (
                            project.archivedSessionCount == 0 ||
                                showArchivedSessionProjects ||
                                project.activeChatCount > 0 ||
                                project.discoveredSessionCount > 0
                            )
                    project.discovered &&
                        !project.isFavorite &&
                        (
                            hasVisibleSessions ||
                                showInactiveDiscoveredProjects ||
                                canSearchHiddenProject
                            )
                },
                added = sorted.filter { !it.discovered && !it.isFavorite },
                showInactiveDiscoveredFilter = projects.any {
                    it.discovered &&
                        !it.isFavorite &&
                        it.activeChatCount == 0 &&
                        it.discoveredSessionCount == 0 &&
                        it.archivedSessionCount == 0
                },
                showArchivedSessionFilter = projects.any {
                    it.discovered && !it.isFavorite && it.archivedSessionCount > 0
                },
            )
        }

        private val projectListComparator = Comparator<ProjectRecord> { lhs, rhs ->
            compareByDescending<ProjectRecord> { it.isFavorite }
                .thenByDescending { it.activeChatCount }
                .thenByDescending { it.discoveredSessionCount }
                .thenByDescending { it.archivedSessionCount }
                .thenByDescending { it.lastActiveChatAtEpochSeconds ?: it.lastDiscoveredAtEpochSeconds ?: Long.MIN_VALUE }
                .thenComparator { left, right -> left.displayName.lowercase().compareTo(right.displayName.lowercase()) }
                .compare(lhs, rhs)
        }
    }
}
