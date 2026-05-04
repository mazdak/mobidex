package mobidex.shared

data class ProjectListSections(
    val favorites: List<ProjectRecord>,
    val discovered: List<ProjectRecord>,
    val added: List<ProjectRecord>,
    val showInactiveDiscoveredFilter: Boolean,
    val discoveredTitle: String = "Discovered",
) {
    val isEmpty: Boolean
        get() = favorites.isEmpty() && discovered.isEmpty() && added.isEmpty()

    companion object {
        fun from(
            projects: List<ProjectRecord>,
            searchText: String,
            showInactiveDiscoveredProjects: Boolean,
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
                    project.discovered &&
                        !project.isFavorite &&
                        (project.discoveredSessionCount > 0 || showInactiveDiscoveredProjects || searching)
                },
                added = sorted.filter { !it.discovered && !it.isFavorite },
                showInactiveDiscoveredFilter = projects.any {
                    it.discovered && !it.isFavorite && it.discoveredSessionCount == 0
                },
            )
        }

        private val projectListComparator = Comparator<ProjectRecord> { lhs, rhs ->
            compareByDescending<ProjectRecord> { it.isFavorite }
                .thenByDescending { it.discoveredSessionCount }
                .thenByDescending { it.activeChatCount }
                .thenByDescending { it.lastActiveChatAtEpochSeconds ?: it.lastDiscoveredAtEpochSeconds ?: Long.MIN_VALUE }
                .thenComparator { left, right -> left.displayName.lowercase().compareTo(right.displayName.lowercase()) }
                .compare(lhs, rhs)
        }
    }
}
