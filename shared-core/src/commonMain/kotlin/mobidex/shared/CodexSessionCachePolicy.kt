package mobidex.shared

object CodexSessionCachePolicy {
    const val DEFAULT_SESSION_LIST_TTL_SECONDS: Long = 30 * 60
    const val DEFAULT_THREAD_DETAIL_TTL_SECONDS: Long = 30 * 60
    const val DEFAULT_PROJECT_LIST_TTL_SECONDS: Long = 30 * 60

    fun isFresh(
        fetchedAtEpochSeconds: Long?,
        nowEpochSeconds: Long,
        ttlSeconds: Long,
    ): Boolean {
        if (fetchedAtEpochSeconds == null || ttlSeconds <= 0) return false
        return nowEpochSeconds - fetchedAtEpochSeconds in 0 until ttlSeconds
    }

    fun shouldRefresh(
        fetchedAtEpochSeconds: Long?,
        nowEpochSeconds: Long,
        ttlSeconds: Long,
    ): Boolean = !isFresh(fetchedAtEpochSeconds, nowEpochSeconds, ttlSeconds)
}
