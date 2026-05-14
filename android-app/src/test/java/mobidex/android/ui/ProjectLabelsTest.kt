package mobidex.android.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import mobidex.android.AndroidProjectListSections
import mobidex.android.MobidexUiState
import mobidex.android.model.CodexThread
import mobidex.android.model.CodexThreadStatus
import mobidex.android.model.ProjectRecord
import mobidex.android.model.ServerConnectionState
import mobidex.android.model.ServerAuthMethod
import mobidex.android.model.ServerRecord

class ProjectLabelsTest {
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
    fun sessionEmptyTitleShowsLoadingBeforeFinalEmptyState() {
        val loading = MobidexUiState(
            connectionState = ServerConnectionState.Connected,
            isRefreshingSessions = true,
        )
        val connected = MobidexUiState(connectionState = ServerConnectionState.Connected)
        val disconnected = MobidexUiState(connectionState = ServerConnectionState.Disconnected)

        assertEquals("Loading Sessions...", sessionEmptyTitle(loading))
        assertEquals("No Sessions Yet", sessionEmptyTitle(connected))
        assertEquals("Connect to Load Sessions", sessionEmptyTitle(disconnected))
    }

    @Test
    fun projectEmptyTitleUsesConnectionInsteadOfCreateAvailability() {
        val busyConnected = MobidexUiState(
            connectionState = ServerConnectionState.Connected,
            isBusy = true,
        )
        val loading = busyConnected.copy(isRefreshingSessions = true)

        assertEquals("No Sessions Yet", projectSessionEmptyTitle(busyConnected))
        assertEquals("Loading Sessions...", projectSessionEmptyTitle(loading))
    }

    @Test
    fun projectCanStartNewSessionWhenExistingSessionIsSelected() {
        val project = ProjectRecord(path = "/srv/app")
        val server = ServerRecord(
            displayName = "Devbox",
            host = "example.com",
            username = "ubuntu",
            authMethod = ServerAuthMethod.Password,
            projects = listOf(project),
        )
        val thread = CodexThread(
            id = "thread-1",
            preview = "Existing work",
            cwd = project.path,
            status = CodexThreadStatus("idle"),
            updatedAtEpochSeconds = 1770000300,
            createdAtEpochSeconds = 1770000000,
        )
        val state = MobidexUiState(
            servers = listOf(server),
            selectedServerID = server.id,
            selectedProjectID = project.id,
            selectedThreadID = thread.id,
            selectedThread = thread,
            connectionState = ServerConnectionState.Connected,
        )

        assertEquals(true, state.canCreateSession)
    }

    @Test
    fun projectEmptyTitleUsesDedicatedProjectDiscoveryState() {
        val sections = AndroidProjectListSections(
            projects = emptyList(),
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
    fun projectEmptyTitleIgnoresHiddenArchivedOnlyProjects() {
        val sections = AndroidProjectListSections(
            projects = emptyList(),
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
            "No Projects",
            projectEmptyTitle(MobidexUiState(selectedServerID = archivedOnlyServer.id, servers = listOf(archivedOnlyServer)), sections, ""),
        )
    }
}
