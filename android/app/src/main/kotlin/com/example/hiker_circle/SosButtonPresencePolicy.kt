package com.leongziqi.hikercircle

/** Fixed presence policy independent of UI settings and monitor restarts. */
object SosButtonPresencePolicy {
    const val ABSENCE_MILLIS = 3_600_000L
    fun reference(lastSeen: Long?, pairedAt: Long, now: Long): Long = minOf(lastSeen ?: pairedAt, now)
    fun shouldAnnounceSeen(previous: Long?, announced: Boolean, now: Long): Boolean =
        !announced || previous == null || now - previous >= ABSENCE_MILLIS
}
