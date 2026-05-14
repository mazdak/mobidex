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
        assertEquals("Loading Sessions...", projectSessionEmptyTitle(loading))
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
