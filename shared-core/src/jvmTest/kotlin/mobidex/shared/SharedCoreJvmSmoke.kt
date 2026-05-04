package mobidex.shared

private fun assertEquals(expected: Any?, actual: Any?) {
    check(expected == actual) { "Expected <$expected>, got <$actual>" }
}

private fun assertTrue(value: Boolean) {
    check(value) { "Expected condition to be true" }
}

fun main() {
    separatesFavoritesFromActiveDiscoveredProjects()
    searchFindsInactiveDiscoveredProjects()
    projectCatalogAppliesOpenSessionCounts()
    diffParserBuildsFileDiffs()
    diffParserIncludesDeletedAndQuotedPaths()
    println("shared-core parity smoke passed")
}

private fun separatesFavoritesFromActiveDiscoveredProjects() {
    val favoriteWithoutChats = ProjectRecord(path = "/srv/favorite", discovered = false, isFavorite = true)
    val activeDiscovered = ProjectRecord(path = "/srv/active", discovered = true, discoveredSessionCount = 2)
    val inactiveDiscovered = ProjectRecord(path = "/srv/inactive", discovered = true)

    val sections = ProjectListSections.from(
        projects = listOf(inactiveDiscovered, activeDiscovered, favoriteWithoutChats),
        searchText = "",
        showInactiveDiscoveredProjects = false,
    )

    assertEquals(listOf("/srv/favorite"), sections.favorites.map { it.path })
    assertEquals(listOf("/srv/active"), sections.discovered.map { it.path })
    assertTrue(sections.showInactiveDiscoveredFilter)
    assertEquals("Discovered", sections.discoveredTitle)
}

private fun searchFindsInactiveDiscoveredProjects() {
    val activeDiscovered = ProjectRecord(path = "/srv/active", discovered = true, discoveredSessionCount = 2)
    val inactiveDiscovered = ProjectRecord(path = "/srv/inactive-match", displayName = "inactive-match", discovered = true)

    val sections = ProjectListSections.from(
        projects = listOf(activeDiscovered, inactiveDiscovered),
        searchText = "match",
        showInactiveDiscoveredProjects = false,
    )

    assertTrue(sections.favorites.isEmpty())
    assertEquals(listOf("/srv/inactive-match"), sections.discovered.map { it.path })
}

private fun projectCatalogAppliesOpenSessionCounts() {
    val existing = listOf(ProjectRecord(path = "/srv/app", discovered = true, discoveredSessionCount = 1))
    val sessions = listOf(CodexThreadSummary(id = "thread-1", cwd = "/srv/app", updatedAtEpochSeconds = 42))

    val refreshed = ProjectCatalog.refreshedProjects(
        existingProjects = existing,
        discoveredProjects = listOf(RemoteProject(path = "/srv/app", discoveredSessionCount = 1)),
        openSessions = sessions,
    )

    assertEquals(1, refreshed.single().activeChatCount)
    assertEquals(42L, refreshed.single().lastActiveChatAtEpochSeconds)
}

private fun diffParserBuildsFileDiffs() {
    val diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 111..222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1 @@
        -old
        +new
        diff --git a/Tests/AppTests.swift b/Tests/AppTests.swift
        index 333..444 100644
        --- a/Tests/AppTests.swift
        +++ b/Tests/AppTests.swift
        @@ -1 +1 @@
        -old
        +new
    """.trimIndent()

    val files = GitDiffFileParser.files(diff)

    assertEquals(listOf("Sources/App.swift", "Tests/AppTests.swift"), files.map { it.path })
}

private fun diffParserIncludesDeletedAndQuotedPaths() {
    val deleted = """
        diff --git a/Removed.swift b/Removed.swift
        deleted file mode 100644
        --- a/Removed.swift
        +++ /dev/null
    """.trimIndent()

    val quoted = """
        diff --git "a/My File.swift" "b/My File.swift"
        --- "a/My File.swift"
        +++ "b/My File.swift"
    """.trimIndent()

    val unquotedWithSpaces = """
        diff --git a/My File.swift b/My File.swift
        --- a/My File.swift
        +++ b/My File.swift
    """.trimIndent()

    assertEquals(listOf("Removed.swift"), GitDiffChangedFileParser.paths(deleted))
    assertEquals(listOf("My File.swift"), GitDiffChangedFileParser.paths(quoted))
    assertEquals(listOf("My File.swift"), GitDiffChangedFileParser.paths(unquotedWithSpaces))
}
