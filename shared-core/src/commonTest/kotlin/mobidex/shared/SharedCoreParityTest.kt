package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SharedCoreParityTest {
    @Test
    fun separatesAddedFromActiveDiscoveredProjects() {
        val addedWithoutChats = ProjectRecord(path = "/srv/added", discovered = false, isAdded = true)
        val activeDiscovered = ProjectRecord(path = "/srv/active", discovered = true, discoveredSessionCount = 2)
        val inactiveDiscovered = ProjectRecord(path = "/srv/inactive", discovered = true)

        val sections = ProjectListSections.from(
            projects = listOf(inactiveDiscovered, activeDiscovered, addedWithoutChats),
            searchText = "",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = false,
        )

        assertEquals(listOf("/srv/added"), sections.projects.map { it.path })
        assertEquals(listOf("/srv/active"), sections.discovered.map { it.path })
        assertTrue(sections.showInactiveDiscoveredFilter)
        assertEquals("Discovered", sections.discoveredTitle)
    }

    @Test
    fun searchFindsInactiveDiscoveredProjects() {
        val activeDiscovered = ProjectRecord(path = "/srv/active", discovered = true, discoveredSessionCount = 2)
        val inactiveDiscovered = ProjectRecord(path = "/srv/inactive-match", displayName = "inactive-match", discovered = true)

        val sections = ProjectListSections.from(
            projects = listOf(activeDiscovered, inactiveDiscovered),
            searchText = "match",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = false,
        )

        assertTrue(sections.projects.isEmpty())
        assertEquals(listOf("/srv/inactive-match"), sections.discovered.map { it.path })
    }

    @Test
    fun appServerLoadedProjectsAreVisibleAndSortedBeforeHistoricalDiscovery() {
        val loaded = ProjectRecord(path = "/srv/loaded", discovered = true, activeChatCount = 1)
        val historical = ProjectRecord(path = "/srv/historical", discovered = true, discoveredSessionCount = 10)
        val inactive = ProjectRecord(path = "/srv/inactive", discovered = true)

        val sections = ProjectListSections.from(
            projects = listOf(inactive, historical, loaded),
            searchText = "",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = false,
        )

        assertEquals(listOf("/srv/loaded", "/srv/historical"), sections.discovered.map { it.path })
        assertTrue(sections.showInactiveDiscoveredFilter)
    }

    @Test
    fun archivedSessionProjectsStayHiddenUntilRequested() {
        val archived = ProjectRecord(path = "/srv/archive", discovered = true, archivedSessionCount = 4)
        val active = ProjectRecord(path = "/srv/active", discovered = true, discoveredSessionCount = 1)

        val hidden = ProjectListSections.from(
            projects = listOf(archived, active),
            searchText = "",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = false,
        )

        assertEquals(listOf("/srv/active"), hidden.discovered.map { it.path })
        assertTrue(hidden.showArchivedSessionFilter)

        val shown = ProjectListSections.from(
            projects = listOf(archived, active),
            searchText = "",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = true,
        )

        assertEquals(listOf("/srv/active", "/srv/archive"), shown.discovered.map { it.path })
    }

    @Test
    fun searchDoesNotRevealArchivedOnlyProjectsUntilRequested() {
        val archived = ProjectRecord(path = "/srv/archive-match", displayName = "archive-match", discovered = true, archivedSessionCount = 4)
        val inactive = ProjectRecord(path = "/srv/inactive-match", displayName = "inactive-match", discovered = true)

        val hidden = ProjectListSections.from(
            projects = listOf(archived, inactive),
            searchText = "match",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = false,
        )

        assertEquals(listOf("/srv/inactive-match"), hidden.discovered.map { it.path })

        val shown = ProjectListSections.from(
            projects = listOf(archived, inactive),
            searchText = "match",
            showInactiveDiscoveredProjects = false,
            showArchivedSessionProjects = true,
        )

        assertEquals(listOf("/srv/archive-match", "/srv/inactive-match"), shown.discovered.map { it.path })
    }

    @Test
    fun projectDisplayNameTrimsTrailingSlashLikeSwift() {
        assertEquals("app", ProjectRecord(path = "/srv/app/").displayName)
    }

    @Test
    fun projectCatalogAppliesOpenSessionCounts() {
        val existing = listOf(ProjectRecord(path = "/srv/app", discovered = true, discoveredSessionCount = 1))
        val sessions = listOf(CodexThreadSummary(id = "thread-1", cwd = "/srv/app", updatedAtEpochSeconds = 42))

        val refreshed = ProjectCatalog.refreshedProjects(
            existingProjects = existing,
            discoveredProjects = listOf(RemoteProject(path = "/srv/app", discoveredSessionCount = 1)),
            openSessions = sessions,
        )

        assertEquals(1, refreshed.single().activeChatCount)
        assertEquals(42, refreshed.single().lastActiveChatAtEpochSeconds)
    }

    @Test
    fun projectCatalogKeepsManualProjectSavedWhenDiscoveryMatchesIt() {
        val existing = listOf(ProjectRecord(path = "/srv/app"))

        val refreshed = ProjectCatalog.refreshedProjects(
            existingProjects = existing,
            discoveredProjects = listOf(
                RemoteProject(
                    path = "/srv/app",
                    discoveredSessionCount = 37,
                    lastDiscoveredAtEpochSeconds = 1_770_000_300,
                )
            ),
            openSessions = null,
        )

        assertTrue(refreshed.single().isSavedProject)
        assertEquals(37, refreshed.single().discoveredSessionCount)
        assertEquals(1_770_000_300, refreshed.single().lastDiscoveredAtEpochSeconds)
    }

    @Test
    fun projectCatalogDoesNotPromoteNewRemoteDiscoveriesToSavedProjects() {
        val refreshed = ProjectCatalog.refreshedProjects(
            existingProjects = emptyList(),
            discoveredProjects = listOf(RemoteProject(path = "/srv/discovered", discoveredSessionCount = 3)),
            openSessions = null,
        )

        assertFalse(refreshed.single().isSavedProject)
        assertEquals(3, refreshed.single().discoveredSessionCount)
    }

    @Test
    fun projectCatalogGroupsCodexWorktreesFromAppServerSessions() {
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

    @Test
    fun projectCatalogIgnoresNoFolderSessionsForProjects() {
        val refreshed = ProjectCatalog.refreshedProjects(
            existingProjects = emptyList(),
            discoveredProjects = emptyList(),
            openSessions = listOf(
                CodexThreadSummary(id = "no-folder", cwd = "", updatedAtEpochSeconds = 30),
                CodexThreadSummary(id = "unscoped", cwd = "/home/me", updatedAtEpochSeconds = 40, isUnscoped = true),
                CodexThreadSummary(id = "regular-docs", cwd = "/Users/me/Documents/Codex/2026-06-12/example-chat", updatedAtEpochSeconds = 50),
            ),
        )

        assertEquals(listOf("/Users/me/Documents/Codex/2026-06-12/example-chat"), refreshed.map { it.path })
    }

    @Test
    fun sessionListSectionsGroupByProjectAndSortByRecentActivity() {
        val projects = listOf(
            ProjectRecord(path = "/srv/app", sessionPaths = listOf("/srv/app", "/srv/.codex/worktrees/a/app")),
            ProjectRecord(path = "/srv/tools"),
        )
        val sections = SessionListSections.from(
            sessions = listOf(
                CodexThreadSummary(id = "tools-old", cwd = "/srv/tools", updatedAtEpochSeconds = 10),
                CodexThreadSummary(id = "app-worktree-new", cwd = "/srv/.codex/worktrees/a/app", updatedAtEpochSeconds = 40),
                CodexThreadSummary(id = "unknown", cwd = "/tmp/loose", updatedAtEpochSeconds = 30),
                CodexThreadSummary(id = "app-main-old", cwd = "/srv/app", updatedAtEpochSeconds = 20),
            ),
            projects = projects,
        )

        assertEquals(listOf("app", "/tmp/loose", "tools"), sections.map { it.title })
        assertEquals(listOf("app-worktree-new", "app-main-old"), sections.first().sessionIds)
        assertEquals(
            listOf("app-worktree-new", "app-main-old"),
            SessionListSections.sessionIdsForProject(
                sessions = listOf(
                    CodexThreadSummary(id = "tools-old", cwd = "/srv/tools", updatedAtEpochSeconds = 10),
                    CodexThreadSummary(id = "app-worktree-new", cwd = "/srv/.codex/worktrees/a/app", updatedAtEpochSeconds = 40),
                    CodexThreadSummary(id = "unknown", cwd = "/tmp/loose", updatedAtEpochSeconds = 30),
                    CodexThreadSummary(id = "app-main-old", cwd = "/srv/app", updatedAtEpochSeconds = 20),
                ),
                projects = projects,
                projectPath = "/srv/app",
            ),
        )
    }

    @Test
    fun sessionListSectionsGroupNoFolderSessions() {
        val sections = SessionListSections.from(
            sessions = listOf(
                CodexThreadSummary(id = "folder", cwd = "/srv/app", updatedAtEpochSeconds = 20),
                CodexThreadSummary(id = "unscoped-home", cwd = "/home/me", updatedAtEpochSeconds = 50, isUnscoped = true),
                CodexThreadSummary(id = "no-folder-new", cwd = "", updatedAtEpochSeconds = 40),
                CodexThreadSummary(id = "no-folder-old", cwd = " ", updatedAtEpochSeconds = 10),
            ),
            projects = listOf(ProjectRecord(path = "/srv/app")),
        )

        assertEquals(listOf("No Folder", "app"), sections.map { it.title })
        assertEquals(listOf("unscoped-home", "no-folder-new", "no-folder-old"), sections.first().sessionIds)
        assertEquals(
            emptyList(),
            SessionListSections.sessionIdsForProject(
                sessions = listOf(
                    CodexThreadSummary(id = "no-folder", cwd = "", updatedAtEpochSeconds = 40),
                    CodexThreadSummary(id = "unscoped", cwd = "/srv/app", updatedAtEpochSeconds = 50, isUnscoped = true),
                ),
                projects = listOf(ProjectRecord(path = "/srv/app")),
                projectPath = "/srv/app",
            ),
        )
    }

    @Test
    fun sessionListSectionsGroupUntrackedCodexWorktreesWithExactProjectSessions() {
        val project = ProjectRecord(path = "/Users/me/Code/cheetah")
        val sections = SessionListSections.from(
            sessions = listOf(
                CodexThreadSummary(id = "cheetah-main", cwd = "/Users/me/Code/cheetah", updatedAtEpochSeconds = 20),
                CodexThreadSummary(id = "cheetah-worktree", cwd = "/Users/me/.codex/worktrees/4845/cheetah", updatedAtEpochSeconds = 40),
            ),
            projects = listOf(project),
        )

        assertEquals(listOf("/Users/me/Code/cheetah"), sections.map { it.id })
        assertEquals(listOf("cheetah-worktree", "cheetah-main"), sections.single().sessionIds)
        assertEquals(
            listOf("cheetah-worktree", "cheetah-main"),
            SessionListSections.sessionIdsForProject(
                sessions = listOf(
                    CodexThreadSummary(id = "cheetah-main", cwd = "/Users/me/Code/cheetah", updatedAtEpochSeconds = 20),
                    CodexThreadSummary(id = "cheetah-worktree", cwd = "/Users/me/.codex/worktrees/4845/cheetah", updatedAtEpochSeconds = 40),
                ),
                projects = listOf(project),
                projectPath = "/Users/me/Code/cheetah",
            ),
        )
    }

    @Test
    fun diffParserBuildsFileDiffs() {
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

    @Test
    fun diffParserIncludesDeletedAndQuotedPaths() {
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
}
