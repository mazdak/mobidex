package mobidex.android.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import mobidex.android.MobidexUiState
import mobidex.android.model.ProjectRecord
import mobidex.android.model.ServerConnectionState

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
    fun discoveredSessionCountIsNeverRenderedAsActiveSessions() {
        val project = ProjectRecord(
            path = "/srv/app",
            discovered = true,
            discoveredSessionCount = 60,
        )

        assertEquals(listOf("60 discovered sessions"), projectSupportingLabels(project))
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
}
