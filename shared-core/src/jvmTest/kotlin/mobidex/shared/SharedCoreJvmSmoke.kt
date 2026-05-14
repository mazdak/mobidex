package mobidex.shared

private fun assertEquals(expected: Any?, actual: Any?) {
    check(expected == actual) { "Expected <$expected>, got <$actual>" }
}

private fun assertTrue(value: Boolean) {
    check(value) { "Expected condition to be true" }
}

fun main() {
    separatesAddedFromActiveDiscoveredProjects()
    searchFindsInactiveDiscoveredProjects()
    appServerLoadedProjectsAreVisibleAndSortedBeforeHistoricalDiscovery()
    projectCatalogAppliesOpenSessionCounts()
    projectCatalogGroupsCodexWorktreesFromAppServerSessions()
    diffParserBuildsFileDiffs()
    diffParserIncludesDeletedAndQuotedPaths()
    println("shared-core parity smoke passed")
}

private fun separatesAddedFromActiveDiscoveredProjects() {
    val addedWithoutChats = ProjectRecord(path = "/srv/added", discovered = false, isAdded = true)
    val activeDiscovered = ProjectRecord(path = "/srv/active", discovered = true, discoveredSessionCount = 2)
    val inactiveDiscovered = ProjectRecord(path = "/srv/inactive", discovered = true)

    val sections = ProjectListSections.from(
        projects = listOf(inactiveDiscovered, activeDiscovered, addedWithoutChats),
        searchText = "",
        showInactiveDiscoveredProjects = false,
    )

    assertEquals(listOf("/srv/added"), sections.projects.map { it.path })
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

    assertTrue(sections.projects.isEmpty())
    assertEquals(listOf("/srv/inactive-match"), sections.discovered.map { it.path })
}

private fun appServerLoadedProjectsAreVisibleAndSortedBeforeHistoricalDiscovery() {
    val loaded = ProjectRecord(path = "/srv/loaded", discovered = true, activeChatCount = 1)
    val historical = ProjectRecord(path = "/srv/historical", discovered = true, discoveredSessionCount = 10)
    val inactive = ProjectRecord(path = "/srv/inactive", discovered = true)

    val sections = ProjectListSections.from(
        projects = listOf(inactive, historical, loaded),
        searchText = "",
        showInactiveDiscoveredProjects = false,
    )

    assertEquals(listOf("/srv/loaded", "/srv/historical"), sections.discovered.map { it.path })
    assertTrue(sections.showInactiveDiscoveredFilter)
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

private fun projectCatalogGroupsCodexWorktreesFromAppServerSessions() {
    val refreshed = ProjectCatalog.refreshedProjects(
        existingProjects = emptyList(),
        discoveredProjects = emptyList(),
        openSessions = listOf(
            CodexThreadSummary(id = "main", cwd = "/Users/me/Code/codex-rs", updatedAtEpochSeconds = 10),
            CodexThreadSummary(id = "worktree", cwd = "/Users/me/.codex/worktrees/abc/codex-rs", updatedAtEpochSeconds = 20),
        ),
    )

    assertEquals(listOf("/Users/me/Code/codex-rs"), refreshed.map { it.path })
    assertEquals(2, refreshed.single().activeChatCount)
    assertEquals(
        listOf("/Users/me/Code/codex-rs", "/Users/me/.codex/worktrees/abc/codex-rs"),
        refreshed.single().sessionPaths,
    )
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
