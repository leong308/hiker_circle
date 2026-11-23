package com.leongziqi.hikercircle

/** Distinguishes sustained turns from brief noise in the rest timer. */
internal class StillnessRotationFilter {
    companion object {
        private const val TURN_THRESHOLD = 0.08f
        private const val CLEAR_TURN_THRESHOLD = 0.20f
        private const val MIN_TURN_MILLIS = 350L
        private const val MAX_SAMPLE_GAP_MILLIS = 500L
    }

    private var turnStartedAt: Long? = null
    private var lastSampleAt: Long? = null

    fun detectsMotion(sampledAt: Long, peakRotation: Float): Boolean {
        val previous = lastSampleAt
        lastSampleAt = sampledAt
        if (peakRotation <= TURN_THRESHOLD) {
            turnStartedAt = null
            return false
        }
        val continuous = previous != null && sampledAt - previous in 1L..MAX_SAMPLE_GAP_MILLIS
        val start = if (continuous) turnStartedAt ?: sampledAt else sampledAt
        turnStartedAt = start
        return peakRotation >= CLEAR_TURN_THRESHOLD || sampledAt - start >= MIN_TURN_MILLIS
    }

    fun reset() {
        turnStartedAt = null
        lastSampleAt = null
    }
}
