package com.leongziqi.hikercircle

/** Checks each qualifying impact for sustained stillness using elapsed time. */
internal class FallImpactDetector {
    companion object {
        const val GRAVITY = 9.80665
        const val CHECK_TIMEOUT_MILLIS = 62_000L
        private const val IMPACT_WINDOW_MILLIS = 500L
        private const val SETTLE_MILLIS = 2_000L
        private const val QUIET_MILLIS = 10_000L
        private const val MAX_SENSOR_GAP_MILLIS = 1_000L
    }

    enum class Outcome { VERIFIED, EXPIRED }

    private var impactWindowEndsAt: Long? = null
    private var settleEndsAt: Long? = null
    private var checkEndsAt = 0L
    private var quietSince: Long? = null
    private var lastQuietSampleAt: Long? = null

    val isChecking: Boolean get() = settleEndsAt != null

    fun recordAcceleration(now: Long, magnitude: Double, sensitivity: Double) {
        if (settleEndsAt?.let { now < it } == true) return
        val normalized = (sensitivity - 1.0) / 9.0
        val afterFreeFall = impactWindowEndsAt?.let { now <= it } == true
        val impactG = if (afterFreeFall) 5.0 - normalized else 3.6 - 0.8 * normalized
        if (magnitude >= impactG * GRAVITY) {
            reset()
            settleEndsAt = now + SETTLE_MILLIS
            checkEndsAt = now + CHECK_TIMEOUT_MILLIS
        } else if (!isChecking && !afterFreeFall &&
            magnitude <= (0.25 + 0.15 * normalized) * GRAVITY
        ) {
            impactWindowEndsAt = now + IMPACT_WINDOW_MILLIS
        }
    }

    fun recordRotation(now: Long, moved: Boolean) {
        val settledAt = settleEndsAt ?: return
        if (now < settledAt || now >= checkEndsAt) return
        if (moved) {
            quietSince = null
            lastQuietSampleAt = null
            return
        }
        val lastSample = lastQuietSampleAt
        if (lastSample == null || now - lastSample > MAX_SENSOR_GAP_MILLIS) {
            quietSince = now
        }
        lastQuietSampleAt = now
    }

    fun outcomeAt(now: Long): Outcome? {
        if (!isChecking) return null
        if (now >= checkEndsAt) return Outcome.EXPIRED
        val since = quietSince ?: return null
        val lastSample = lastQuietSampleAt ?: return null
        if (lastSample - since >= QUIET_MILLIS && now - lastSample <= MAX_SENSOR_GAP_MILLIS) {
            return Outcome.VERIFIED
        }
        return null
    }

    fun reset() {
        impactWindowEndsAt = null
        settleEndsAt = null
        checkEndsAt = 0L
        quietSince = null
        lastQuietSampleAt = null
    }
}
