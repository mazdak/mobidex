package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CodexSessionCachePolicyTest {
    @Test
    fun cacheEntryIsFreshInsideTtl() {
        assertTrue(
            CodexSessionCachePolicy.isFresh(
                fetchedAtEpochSeconds = 100,
                nowEpochSeconds = 100 + CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS - 1,
                ttlSeconds = CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
            )
        )
    }

    @Test
    fun cacheEntryStalesAtTtlBoundary() {
        assertFalse(
            CodexSessionCachePolicy.isFresh(
                fetchedAtEpochSeconds = 100,
                nowEpochSeconds = 100 + CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
                ttlSeconds = CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
            )
        )
    }

    @Test
    fun futureClockSkewForcesRefresh() {
        assertTrue(
            CodexSessionCachePolicy.shouldRefresh(
                fetchedAtEpochSeconds = 200,
                nowEpochSeconds = 100,
                ttlSeconds = CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
            )
        )
    }

    @Test
    fun defaultNavigationCachesLastThirtyMinutes() {
        assertTrue(
            CodexSessionCachePolicy.isFresh(
                fetchedAtEpochSeconds = 0,
                nowEpochSeconds = 29 * 60 + 59,
                ttlSeconds = CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
            )
        )
        assertFalse(
            CodexSessionCachePolicy.isFresh(
                fetchedAtEpochSeconds = 0,
                nowEpochSeconds = 30 * 60,
                ttlSeconds = CodexSessionCachePolicy.DEFAULT_SESSION_LIST_TTL_SECONDS,
            )
        )
    }
}
