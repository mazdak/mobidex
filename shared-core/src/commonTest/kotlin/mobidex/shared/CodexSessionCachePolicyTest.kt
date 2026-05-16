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
                nowEpochSeconds = 130,
                ttlSeconds = 45,
            )
        )
    }

    @Test
    fun cacheEntryStalesAtTtlBoundary() {
        assertFalse(
            CodexSessionCachePolicy.isFresh(
                fetchedAtEpochSeconds = 100,
                nowEpochSeconds = 145,
                ttlSeconds = 45,
            )
        )
    }

    @Test
    fun futureClockSkewForcesRefresh() {
        assertTrue(
            CodexSessionCachePolicy.shouldRefresh(
                fetchedAtEpochSeconds = 200,
                nowEpochSeconds = 100,
                ttlSeconds = 45,
            )
        )
    }
}
