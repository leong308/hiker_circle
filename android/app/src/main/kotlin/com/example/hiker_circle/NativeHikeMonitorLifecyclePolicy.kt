package com.leongziqi.hikercircle

/** Orders native monitor commands around a durable stop, without Android APIs. */
internal object NativeHikeMonitorLifecyclePolicy {
    fun cancelsPendingWarning(phase: String?): Boolean = phase == "awaiting_response"

    fun recoversPendingDispatch(enabled: Boolean, phase: String?): Boolean =
        !enabled && phase in setOf("triggering", "dispatching", "dispatch_failed")

    fun acceptsStart(
        hasExplicitConfig: Boolean,
        enabled: Boolean,
        incomingGeneration: Long?,
        stopGeneration: Long,
    ): Boolean = if (hasExplicitConfig) {
        incomingGeneration != null && incomingGeneration == stopGeneration
    } else {
        enabled
    }

    fun appliesStop(
        incomingGeneration: Long?,
        stopGeneration: Long,
        enabled: Boolean,
    ): Boolean = !enabled &&
        (incomingGeneration == null || incomingGeneration == stopGeneration)

    fun allowsTracking(
        enabled: Boolean,
        activeGeneration: Long,
        stopGeneration: Long,
    ): Boolean = enabled && activeGeneration == stopGeneration
}
