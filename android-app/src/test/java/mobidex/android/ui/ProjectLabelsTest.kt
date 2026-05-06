package mobidex.android.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import mobidex.android.model.ProjectRecord

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
}
