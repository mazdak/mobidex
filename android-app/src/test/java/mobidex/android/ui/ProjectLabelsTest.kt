package mobidex.android.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import mobidex.android.AndroidProjectListSections
import mobidex.android.MobidexUiState
import mobidex.android.model.ProjectRecord
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerRecord

class ProjectLabelsTest {
    @Test
    fun loadedAppServerCountIsNotConfusedWithDiscoveredSessionCount() {
        val project = ProjectRecord(
            path = "/srv/app",
            discovered = true,
            discoveredSessionCount = 60,
            activeChatCount = 2,
            sessionPaths = listOf("/srv/app", "/srv/app/.codex/worktrees/abc/app"),
        )

        assertEquals(
            listOf("2 loaded in app-server", "60 discovered sessions", "2 worktree paths grouped"),
            projectSupportingLabels(project),
        )
    }

    @Test
    fun macOSProtectedProjectsDoNotShowPrivacyWarningInRows() {
        val project = ProjectRecord(
            path = "/Users/yesh/Documents/work/ResQlaw",
            discovered = true,
            discoveredSessionCount = 1,
        )

        assertEquals(listOf("1 discovered session"), projectSupportingLabels(project))
    }

    @Test
    fun macOSProtectedWarningIncludesICloudAndVolumes() {
        assertEquals(
            "macOS may block SSH access to this protected location. Move it outside protected folders or grant Full Disk Access to the SSH/Remote Login service.",
            ProjectRecord.macOSPrivacyWarning(
                listOf("/Users/yesh/Library/Mobile Documents/com~apple~CloudDocs/ResQlaw")
            ),
        )
        assertEquals(
            "macOS may block SSH access to this protected location. Move it outside protected folders or grant Full Disk Access to the SSH/Remote Login service.",
            ProjectRecord.macOSPrivacyWarning(listOf("/Volumes/External/ResQlaw")),
        )
    }

    @Test
    fun discoveredSessionCountIsNeverRenderedAsActiveSessions() {
        val project = ProjectRecord(
            path = "/srv/app",
            discovered = true,
            discoveredSessionCount = 60,
        )

        assertEquals(listOf("60 discovered sessions"), projectSupportingLabels(project))
    }

    @Test
    fun archivedSessionCountIsRenderedAsHistoricalContext() {
        val project = ProjectRecord(
            path = "/srv/archive",
            discovered = true,
            archivedSessionCount = 3,
        )

        assertEquals(listOf("3 archived sessions"), projectSupportingLabels(project))
    }

    @Test
    fun sessionEmptyTitleShowsLoadingBeforeFinalEmptyState() {
        val loading = MobidexUiState(
            connectionState = ServerConnectionState.Connected,
            isRefreshingSessions = true,
        )
        val connected = MobidexUiState(connectionState = ServerConnectionState.Connected)
        val disconnected = MobidexUiState(connectionState = ServerConnectionState.Disconnected)

        assertEquals("Loading Sessions", sessionEmptyTitle(loading))
        assertEquals("No Sessions", sessionEmptyTitle(connected))
        assertEquals("Connect to Load Sessions", sessionEmptyTitle(disconnected))
    }

    @Test
    fun projectEmptyTitleUsesConnectionInsteadOfCreateAvailability() {
        val busyConnected = MobidexUiState(
            connectionState = ServerConnectionState.Connected,
            isBusy = true,
        )
        val loading = busyConnected.copy(isRefreshingSessions = true)

        assertEquals("No Sessions", projectSessionEmptyTitle(busyConnected))
        assertEquals("Loading Sessions", projectSessionEmptyTitle(loading))
    }

    @Test
    fun projectEmptyTitleUsesDedicatedProjectDiscoveryState() {
        val sections = AndroidProjectListSections(
            favorites = emptyList(),
            discovered = emptyList(),
            added = emptyList(),
            showInactiveDiscoveredFilter = false,
            showArchivedSessionFilter = false,
            discoveredTitle = "Discovered",
        )
        val addingProject = MobidexUiState(
            isBusy = true,
            statusMessage = "Adding project",
        )
        val loadingProjects = addingProject.copy(isDiscoveringProjects = true)

        assertEquals("No Projects", projectEmptyTitle(addingProject, sections, ""))
        assertEquals("Loading Projects", projectEmptyTitle(loadingProjects, sections, ""))
    }

    @Test
    fun projectEmptyTitleNamesHiddenArchivedOnlyProjects() {
        val sections = AndroidProjectListSections(
            favorites = emptyList(),
            discovered = emptyList(),
            added = emptyList(),
            showInactiveDiscoveredFilter = false,
            showArchivedSessionFilter = true,
            discoveredTitle = "Discovered",
        )
        val archivedOnlyServer = ServerRecord(
            displayName = "Devbox",
            host = "example.com",
            username = "ubuntu",
            authMethod = ServerAuthMethod.Password,
            projects = listOf(ProjectRecord(path = "/srv/archive", discovered = true, archivedSessionCount = 2)),
        )

        assertEquals(
            "No Active Projects",
            projectEmptyTitle(MobidexUiState(selectedServerID = archivedOnlyServer.id, servers = listOf(archivedOnlyServer)), sections, ""),
        )
    }
}
