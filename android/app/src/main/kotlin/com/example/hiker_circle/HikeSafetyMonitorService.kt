// HikeSafetyMonitorService records footprints and runs fall, stillness, and response timers.
package com.leongziqi.hikercircle

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.app.KeyguardManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.functions.FirebaseFunctions
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import java.util.Locale
import java.lang.ref.WeakReference
import org.json.JSONArray

/**
 * Native, process-independent active-hike safety monitor.
 *
 * Flutter remains responsible for the authenticated contact dispatch, but the
 * sensor/location watch, user response countdown, vibration and system prompt
 * live in this foreground service. This keeps the safety timer alive when the
 * Flutter activity is backgrounded or its Dart isolate is reclaimed.
 */
class HikeSafetyMonitorService : Service(), SensorEventListener, LocationListener {
    companion object {
        @Volatile var flutterUiForeground = false
        var onFallImpactCheckChanged: (() -> Unit)? = null
        @Volatile private var runningService: WeakReference<HikeSafetyMonitorService>? = null

        const val ACTION_START = "com.leongziqi.hikercircle.safety.START"
        const val ACTION_STOP = "com.leongziqi.hikercircle.safety.STOP"
        const val ACTION_REMAP_SESSION = "com.leongziqi.hikercircle.safety.REMAP_SESSION"
        const val ACTION_CANCEL_ALERT = "com.leongziqi.hikercircle.safety.CANCEL_ALERT"
        const val ACTION_STOP_TRIGGERED_ALARM =
            "com.leongziqi.hikercircle.safety.STOP_TRIGGERED_ALARM"
        const val ACTION_ACKNOWLEDGE_ALERT =
            "com.leongziqi.hikercircle.safety.ACKNOWLEDGE_ALERT"
        private const val ACTION_MARK_DISPATCHED =
            "com.leongziqi.hikercircle.safety.MARK_DISPATCHED"

        private const val PREFS = "hiker_circle_hike_safety"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_STOP_GENERATION = "stop_generation"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_TRAIL_NAME = "trail_name"
        private const val KEY_REST_MILLIS = "rest_millis"
        private const val KEY_RESPONSE_MILLIS = "response_millis"
        private const val KEY_SENSITIVITY = "sensitivity"
        private const val KEY_BATTERY_ADJUSTED = "battery_safety_adjusted"
        private const val KEY_BATTERY_REVISION = "battery_safety_revision"
        private const val KEY_ORIGINAL_SENSITIVITY = "battery_original_sensitivity"
        private const val KEY_ORIGINAL_INTERVAL = "battery_original_interval"
        private const val KEY_FALL_DETECTION_ENABLED = "fall_detection_enabled"
        private const val KEY_LAST_MOTION_WALL = "last_motion_wall"
        private const val KEY_EVENT_ID = "event_id"
        private const val KEY_EVENT_KIND = "event_kind"
        private const val KEY_EVENT_PHASE = "event_phase"
        private const val KEY_EVENT_DETECTED_WALL = "event_detected_wall"
        private const val KEY_EVENT_DEADLINE_WALL = "event_deadline_wall"
        private const val KEY_EVENT_TRIGGERED_WALL = "event_triggered_wall"
        private const val KEY_DISPATCH_MESSAGE = "dispatch_message"
        private const val KEY_LOCAL_ALARM_STOPPED = "event_local_alarm_stopped"
        private const val KEY_DISPATCH_ONLY = "event_dispatch_only"
        private const val KEY_STOPPED_EVENT_IDS = "stopped_safety_event_ids"
        private const val MAX_STOPPED_EVENT_RECEIPTS = 32
        private const val KEY_LAST_LATITUDE = "last_latitude"
        private const val KEY_LAST_LONGITUDE = "last_longitude"
        private const val KEY_LAST_ACCURACY = "last_accuracy"
        private const val KEY_LAST_CAPTURED_AT = "last_captured_at"
        private const val KEY_OWNER_UID = "owner_uid"
        private const val KEY_UPLOAD_INTERVAL = "location_upload_interval"

        private const val ACTIVE_CHANNEL_ID = "hiker_circle_hike_safety_active"
        private const val ALERT_CHANNEL_ID = "hiker_circle_hike_safety_alerts"
        private const val IMPACT_CHANNEL_ID = "hiker_circle_hike_impact_check"
        private const val ACTIVE_NOTIFICATION_ID = 4212
        private const val ALERT_NOTIFICATION_ID = 4213
        private const val IMPACT_NOTIFICATION_ID = 4234
        private const val SENSOR_PERIOD_MICROS = 100_000
        private const val LOCATION_INTERVAL_MILLIS = 5_000L
        private const val LOCATION_MAX_AGE_MILLIS = 30_000L
        private const val WARNING_RESPONSE_MILLIS = 15_000L

        fun startOrUpdate(context: Context, config: SafetyConfig) {
            val generation = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getLong(KEY_STOP_GENERATION, 0L)
            val intent = Intent(context, HikeSafetyMonitorService::class.java).apply {
                action = ACTION_START
                putExtra(KEY_STOP_GENERATION, generation)
                putExtra(KEY_SESSION_ID, config.sessionId)
                putExtra(KEY_TRAIL_NAME, config.trailName)
                putExtra(KEY_REST_MILLIS, config.longestRestMillis)
                putExtra(KEY_RESPONSE_MILLIS, config.responseMillis)
                putExtra(KEY_SENSITIVITY, config.sensitivity)
                putExtra(KEY_BATTERY_ADJUSTED, config.batterySafetyAdjusted)
                putExtra(KEY_BATTERY_REVISION, config.batterySafetyRevision)
                putExtra(KEY_ORIGINAL_SENSITIVITY, config.batteryOriginalSensitivity ?: -1.0)
                putExtra(KEY_ORIGINAL_INTERVAL, config.batteryOriginalIntervalMillis ?: -1L)
                putExtra(KEY_FALL_DETECTION_ENABLED, config.fallDetectionEnabled)
                putExtra(KEY_OWNER_UID, config.ownerUid)
                putExtra(KEY_UPLOAD_INTERVAL, config.locationUploadIntervalMillis)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // The channel may return, or the process may die, before Android
            // delivers ACTION_STOP. Persist the barrier first so neither a
            // queued start nor a sticky/boot restore can revive that monitor.
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val generation = prefs.getLong(KEY_STOP_GENERATION, 0L) + 1L
            val editor = prefs.edit()
                .putBoolean(KEY_ENABLED, false)
                .putLong(KEY_STOP_GENERATION, generation)
            if (NativeHikeMonitorLifecyclePolicy.cancelsPendingWarning(
                    prefs.getString(KEY_EVENT_PHASE, null),
                )) {
                clearPendingEvent(editor)
            } else if (prefs.getString(KEY_EVENT_ID, null) != null) {
                // Ending tracking also stops local outputs, but leaves an
                // already-escalated event intact until delivery is durable.
                editor.putBoolean(KEY_LOCAL_ALARM_STOPPED, true)
            }
            check(editor.commit()) { "Unable to stop the native hike monitor safely." }
            context.startService(
                Intent(context, HikeSafetyMonitorService::class.java).apply {
                    action = ACTION_STOP
                    putExtra(KEY_STOP_GENERATION, generation)
                },
            )
        }

        fun isConfigured(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false)

        fun isCheckingFallImpact(sessionId: String, ownerUid: String): Boolean {
            val service = runningService?.get() ?: return false
            val current = service.config ?: return false
            return service.monitoring && service.trackingEnabled() && service.impactDetector.isChecking &&
                current.sessionId == sessionId && current.ownerUid == ownerUid
        }

        fun requestWarningCancellation(context: Context, eventId: String): Boolean {
            if (eventId.isBlank() || pendingEvent(context)?.get("eventId") != eventId) return false
            context.startService(Intent(context, HikeSafetyMonitorService::class.java).apply {
                action = ACTION_CANCEL_ALERT
                putExtra(KEY_EVENT_ID, eventId)
            })
            return true
        }

        // remapSession: Replace a provisional hike ID in the running monitor and buffered samples.
        fun remapSession(context: Context, oldSessionId: String, newSessionId: String, ownerUid: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_SESSION_ID, null) != oldSessionId || prefs.getString(KEY_OWNER_UID, null) != ownerUid) return
            check(prefs.edit().putString(KEY_SESSION_ID, newSessionId).commit()) { "Unable to remap the active native hike." }
            if (isConfigured(context)) runCatching {
                context.startService(Intent(context, HikeSafetyMonitorService::class.java).apply {
                    action = ACTION_REMAP_SESSION
                    putExtra("oldSessionId", oldSessionId)
                    putExtra("newSessionId", newSessionId)
                    putExtra(KEY_OWNER_UID, ownerUid)
                })
            }
        }

        fun restartIfConfigured(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!isConfigured(context) && !NativeHikeMonitorLifecyclePolicy.recoversPendingDispatch(
                    false, prefs.getString(KEY_EVENT_PHASE, null),
                )) return
            val intent = Intent(context, HikeSafetyMonitorService::class.java).apply {
                action = ACTION_START
            }
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        fun powerSettings(context: Context, ownerUid: String): Map<String, Any?>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_ENABLED, false) || ownerUid.isBlank() || prefs.getString(KEY_OWNER_UID, "") != ownerUid) return null
            return mapOf("sessionId" to prefs.getString(KEY_SESSION_ID, ""),
                "batterySafetyAdjusted" to prefs.getBoolean(KEY_BATTERY_ADJUSTED, false),
                "batterySafetyRevision" to prefs.getInt(KEY_BATTERY_REVISION, 0),
                "batteryOriginalSensorSensitivity" to if (prefs.contains(KEY_ORIGINAL_SENSITIVITY)) prefs.getFloat(KEY_ORIGINAL_SENSITIVITY, 5f).toDouble() else null,
                "batteryOriginalFootprintIntervalSeconds" to if (prefs.contains(KEY_ORIGINAL_INTERVAL)) prefs.getLong(KEY_ORIGINAL_INTERVAL, 30_000L) / 1000 else null,
                "sensorSensitivity" to prefs.getFloat(KEY_SENSITIVITY, 5f).toDouble(),
                "intervalSeconds" to prefs.getLong(KEY_UPLOAD_INTERVAL, 30_000L) / 1000)
        }

        fun pendingEvent(context: Context): Map<String, Any?>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val eventId = prefs.getString(KEY_EVENT_ID, null) ?: return null
            return mapOf(
                "eventId" to eventId,
                "sessionId" to prefs.getString(KEY_SESSION_ID, ""),
                "ownerUid" to prefs.getString(KEY_OWNER_UID, ""),
                "kind" to prefs.getString(KEY_EVENT_KIND, "prolonged_stillness"),
                "phase" to prefs.getString(KEY_EVENT_PHASE, "awaiting_response"),
                "detectedAtMillis" to prefs.getLong(KEY_EVENT_DETECTED_WALL, 0L),
                "deadlineAtMillis" to prefs.getLong(KEY_EVENT_DEADLINE_WALL, 0L),
                "triggeredAtMillis" to prefs.getLong(KEY_EVENT_TRIGGERED_WALL, 0L),
                "dispatchMessage" to prefs.getString(KEY_DISPATCH_MESSAGE, null),
                "localAlarmStopped" to prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false),
            )
        }

        // Silence only local outputs. The event and headless dispatcher must
        // survive until contacts are notified or a durable retry is saved.
        fun stopTriggeredSafetyAlarm(context: Context, eventId: String): Boolean {
            if (eventId.isBlank()) return false
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_EVENT_ID, null) != eventId ||
                prefs.getString(KEY_EVENT_PHASE, null) == "awaiting_response"
            ) return false
            if (!prefs.edit().putBoolean(KEY_LOCAL_ALARM_STOPPED, true).commit()) {
                prefs.edit().putBoolean(KEY_LOCAL_ALARM_STOPPED, false).apply()
                throw IllegalStateException("The alarm stop request could not be saved.")
            }
            return try {
                val service = runningService?.get()
                if (service == null) {
                    // No service instance means its physical outputs are off.
                    recordStoppedAlarmReceipt(context, eventId)
                    true
                } else {
                    val stopped = service.stopTriggeredAlarmOutputs(eventId)
                    if (!stopped && prefs.getString(KEY_EVENT_ID, null) == eventId) {
                        check(prefs.edit().putBoolean(KEY_LOCAL_ALARM_STOPPED, false).commit())
                    }
                    stopped
                }
            } catch (error: RuntimeException) {
                if (prefs.getString(KEY_EVENT_ID, null) == eventId &&
                    !wasSafetyAlarmStopped(context, eventId)
                ) {
                    prefs.edit().putBoolean(KEY_LOCAL_ALARM_STOPPED, false).commit()
                }
                // A failed stop is a channel error, never a stale-event false
                // result that Flutter could mistake for an already-off alarm.
                throw error
            }
        }

        fun wasSafetyAlarmStopped(context: Context, eventId: String): Boolean =
            eventId.isNotBlank() && stoppedAlarmReceipts(context).contains(eventId)

        private fun stoppedAlarmReceipts(context: Context): List<String> = runCatching {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val receipts = JSONArray(prefs.getString(KEY_STOPPED_EVENT_IDS, "[]"))
            (0 until receipts.length()).mapNotNull { receipts.optString(it).takeIf(String::isNotBlank) }
        }.getOrDefault(emptyList())

        private fun recordStoppedAlarmReceipt(context: Context, eventId: String) {
            val receipts = (stoppedAlarmReceipts(context).filter { it != eventId } + eventId)
                .takeLast(MAX_STOPPED_EVENT_RECEIPTS)
            check(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_STOPPED_EVENT_IDS, JSONArray(receipts).toString()).commit()) {
                "The completed alarm stop could not be saved."
            }
        }

        // A delivery receipt keeps the physical alarm active until a safe
        // response. Unlike acknowledgeEvent, it must not clear the event.
        fun markEventDispatched(context: Context, eventId: String, message: String?) {
            if (eventId.isBlank()) return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_EVENT_ID, null) != eventId) return
            prefs.edit()
                .putString(KEY_EVENT_PHASE, "dispatched")
                .putString(KEY_DISPATCH_MESSAGE, message?.takeIf { it.isNotBlank() }
                    ?: "Emergency alert sent or saved securely for retry.")
                .apply()
            // The event-ID guard also applies when this intent is handled;
            // a safe response may arrive before the service processes it.
            runCatching {
                context.startService(Intent(context, HikeSafetyMonitorService::class.java).apply {
                    action = ACTION_MARK_DISPATCHED
                    putExtra(KEY_EVENT_ID, eventId)
                })
            }
        }

        fun acknowledgeEvent(context: Context, eventId: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_EVENT_ID, null) != eventId) return
            runCatching {
                context.startService(
                    Intent(context, HikeSafetyMonitorService::class.java).apply {
                        action = ACTION_ACKNOWLEDGE_ALERT
                        putExtra(KEY_EVENT_ID, eventId)
                    },
                )
            }
        }

        private fun clearPendingEvent(editor: android.content.SharedPreferences.Editor):
            android.content.SharedPreferences.Editor = editor
            .remove(KEY_EVENT_ID)
            .remove(KEY_EVENT_KIND)
            .remove(KEY_EVENT_PHASE)
            .remove(KEY_EVENT_DETECTED_WALL)
            .remove(KEY_EVENT_DEADLINE_WALL)
            .remove(KEY_EVENT_TRIGGERED_WALL)
            .remove(KEY_DISPATCH_MESSAGE)
            .remove(KEY_LOCAL_ALARM_STOPPED)
            .remove(KEY_DISPATCH_ONLY)
    }

    data class SafetyConfig(
        val sessionId: String,
        val trailName: String,
        val longestRestMillis: Long,
        val responseMillis: Long,
        val sensitivity: Double,
        val fallDetectionEnabled: Boolean,
        val ownerUid: String,
        val locationUploadIntervalMillis: Long,
        val batterySafetyAdjusted: Boolean = false,
        val batterySafetyRevision: Int = 0,
        val batteryOriginalSensitivity: Double? = null,
        val batteryOriginalIntervalMillis: Long? = null,
    )

    private enum class DetectionState {
        NORMAL,
        AWAITING_RESPONSE,
        TRIGGERING,
    }

    private lateinit var sensorManager: SensorManager
    private lateinit var locationManager: LocationManager
    private lateinit var notificationManager: NotificationManager
    private lateinit var keyguardManager: KeyguardManager
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var config: SafetyConfig? = null
    private var activeGeneration = 0L
    private var state = DetectionState.NORMAL
    private val impactDetector = FallImpactDetector()
    private val stillnessRotation = StillnessRotationFilter()
    private var lastMotionElapsed = SystemClock.elapsedRealtime()
    private var lastMotionPersistedElapsed = 0L
    private var responseDeadlineElapsed = 0L
    private var referenceLocation: Location? = null
    private var monitoring = false
    private var backgroundEngine: FlutterEngine? = null
    private var backgroundDispatchEventId: String? = null
    private var backgroundDispatchTimeout: Runnable? = null
    private var textToSpeech: TextToSpeech? = null
    private var pendingSpeechMessage: String? = null
    private lateinit var physicalAlarm: NativeSosAlarmController
    private var wasDeviceLockedDuringWarning = false
    private var latestLocation: Location? = null
    private val locationSamples by lazy { NativeLocationSampleBuffer(this) }
    private var lastSampleAtElapsed = 0L
    private var lastUploadAttemptElapsed = SystemClock.elapsedRealtime()
    private var uploadingLocations = false

    private val ticker = object : Runnable {
        override fun run() {
            if (!monitoring || !trackingEnabled()) return
            HikeArrivalSafety.tick(this@HikeSafetyMonitorService)
            sampleLocationIfDue()
            uploadBufferedLocationsIfDue()
            evaluateTimers()
            handler.postDelayed(this, 1_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(SensorManager::class.java)
        locationManager = getSystemService(LocationManager::class.java)
        notificationManager = getSystemService(NotificationManager::class.java)
        keyguardManager = getSystemService(KeyguardManager::class.java)
        physicalAlarm = NativeSosAlarmController(this, handler)
        runningService = WeakReference(this)
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_REMAP_SESSION -> {
                val current = config
                if (current != null && current.sessionId == intent.getStringExtra("oldSessionId") && current.ownerUid == intent.getStringExtra(KEY_OWNER_UID)) {
                    val remapped = intent.getStringExtra("newSessionId").orEmpty()
                    if (remapped.isNotBlank()) config = current.copy(sessionId = remapped)
                }
                if (monitoring) return START_STICKY
            }
            ACTION_STOP -> {
                val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                val generation = intent.takeIf { it.hasExtra(KEY_STOP_GENERATION) }
                    ?.getLongExtra(KEY_STOP_GENERATION, 0L)
                if (!NativeHikeMonitorLifecyclePolicy.appliesStop(
                        generation, prefs.getLong(KEY_STOP_GENERATION, 0L),
                        prefs.getBoolean(KEY_ENABLED, false),
                    )) return if (monitoring) START_STICKY else START_NOT_STICKY
                prefs.edit()
                    .putBoolean(KEY_BATTERY_ADJUSTED, false).putInt(KEY_BATTERY_REVISION, 0)
                    .remove(KEY_ORIGINAL_SENSITIVITY).remove(KEY_ORIGINAL_INTERVAL).apply()
                if (retainPendingDispatchWithoutTracking()) return START_NOT_STICKY
                getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean(KEY_ENABLED, false)
                    .remove(KEY_DISPATCH_ONLY)
                    .apply()
                stopMonitoring()
                stopWarningOutputs()
                physicalAlarm.stop()
                notificationManager.cancel(ALERT_NOTIFICATION_ID)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_CANCEL_ALERT -> {
                val eventId = intent.getStringExtra(KEY_EVENT_ID).orEmpty()
                val pending = pendingEvent(this)
                if (eventId.isNotBlank() && pending?.get("eventId") == eventId) {
                    if (pending["phase"] == "awaiting_response") {
                        cancelAlert("Response received")
                    } else {
                        // A late response only silences the matching escalated event.
                        stopTriggeredSafetyAlarm(this, eventId)
                    }
                }
                // A notification action can recreate the service. Restore sensors below.
                if (monitoring) return START_STICKY
            }
            ACTION_ACKNOWLEDGE_ALERT -> {
                val eventId = intent.getStringExtra(KEY_EVENT_ID)
                if (!eventId.isNullOrBlank() && pendingEvent(this)?.get("eventId") == eventId) {
                    cancelAlert("Alert acknowledged")
                }
                if (monitoring) return START_STICKY
            }
            ACTION_STOP_TRIGGERED_ALARM -> {
                stopTriggeredSafetyAlarm(this, intent.getStringExtra(KEY_EVENT_ID).orEmpty())
                if (monitoring) return START_STICKY
                if (retainPendingDispatchWithoutTracking()) return START_NOT_STICKY
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_MARK_DISPATCHED -> {
                val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                val eventId = intent.getStringExtra(KEY_EVENT_ID)
                if (!eventId.isNullOrBlank() &&
                    prefs.getString(KEY_EVENT_ID, null) == eventId &&
                    prefs.getString(KEY_EVENT_PHASE, null) == "dispatched"
                ) {
                    state = DetectionState.TRIGGERING
                    if (!completeStoppedDispatchedEvent(eventId)) {
                        notificationManager.notify(ALERT_NOTIFICATION_ID,
                            dispatchResultNotification(prefs.getString(KEY_DISPATCH_MESSAGE, null)
                                ?: "Emergency alert sent or saved securely for retry."))
                    }
                }
                // Do not start dispatch or change physical alarm outputs for
                // a delivery receipt, including after an event was cancelled.
                return if (monitoring) START_STICKY else START_NOT_STICKY
            }
        }

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (NativeHikeMonitorLifecyclePolicy.recoversPendingDispatch(
                prefs.getBoolean(KEY_ENABLED, false), prefs.getString(KEY_EVENT_PHASE, null),
            ) && retainPendingDispatchWithoutTracking()) return START_NOT_STICKY

        val restored = readConfig(intent)
        if (restored == null || restored.sessionId.isBlank()) {
            // Reject a stale start without destroying a newer live monitor or
            // an already-triggered SOS dispatcher that is saving its retry.
            if (!monitoring && backgroundEngine == null) stopSelf(startId)
            return if (monitoring && trackingEnabled()) START_STICKY else START_NOT_STICKY
        }
        val previous = config
        val previousGeneration = activeGeneration
        config = restored
        activeGeneration = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getLong(KEY_STOP_GENERATION, 0L)
        if (monitoring && previousGeneration != activeGeneration) {
            // A fresh explicit resume may overtake delivery of an older STOP.
            // Its durable barrier already cancelled any un-escalated warning;
            // do not carry the old in-memory countdown into the new monitor.
            stopMonitoring()
            stopWarningOutputs()
            physicalAlarm.stop()
            state = DetectionState.NORMAL
            wasDeviceLockedDuringWarning = false
            responseDeadlineElapsed = 0L
            if (pendingEvent(this) == null) notificationManager.cancel(ALERT_NOTIFICATION_ID)
        }
        persistConfig(restored)
        if (previous?.sessionId != restored.sessionId || previousGeneration != activeGeneration) {
            latestLocation = null
            referenceLocation = null
            lastSampleAtElapsed = 0L
            lastUploadAttemptElapsed = SystemClock.elapsedRealtime()
        }
        val locationGranted = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!locationGranted) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startForeground(ACTIVE_NOTIFICATION_ID, activeNotification("Safety monitoring active"))
        } catch (error: RuntimeException) {
            android.util.Log.w("HikeSafetyMonitor", "Foreground location monitor could not start", error)
            stopSelf()
            return START_NOT_STICKY
        }
        if (monitoring && previous?.fallDetectionEnabled != restored.fallDetectionEnabled) {
            sensorManager.unregisterListener(this)
            if (restored.fallDetectionEnabled) registerSensors()
            else {
                clearImpactCheck()
                if (state == DetectionState.AWAITING_RESPONSE) cancelAlert("Fall detection disabled")
            }
        }
        if (monitoring && previous?.locationUploadIntervalMillis != restored.locationUploadIntervalMillis) {
            locationManager.removeUpdates(this)
            registerLocationUpdates()
        }
        startMonitoring()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (runningService?.get() === this) runningService = null
        stopMonitoring()
        stopWarningOutputs()
        physicalAlarm.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        destroyBackgroundEngine()
        super.onDestroy()
    }

    private fun readConfig(intent: Intent?): SafetyConfig? {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val hasIncoming = intent?.hasExtra(KEY_SESSION_ID) == true
        val generation = intent?.takeIf { it.hasExtra(KEY_STOP_GENERATION) }
            ?.getLongExtra(KEY_STOP_GENERATION, 0L)
        if (!NativeHikeMonitorLifecyclePolicy.acceptsStart(
                hasIncoming, prefs.getBoolean(KEY_ENABLED, false), generation,
                prefs.getLong(KEY_STOP_GENERATION, 0L),
            )) return null
        val sessionId = intent?.getStringExtra(KEY_SESSION_ID)
            ?.takeIf { it.isNotBlank() }
            ?: prefs.getString(KEY_SESSION_ID, null)
            ?: return null
        val sameSession = prefs.getString(KEY_SESSION_ID, null) == sessionId &&
            (intent?.getStringExtra(KEY_OWNER_UID) ?: prefs.getString(KEY_OWNER_UID, "")) == prefs.getString(KEY_OWNER_UID, "")
        val adjusted = sameSession && prefs.getBoolean(KEY_BATTERY_ADJUSTED, false)
        val storedRevision = if (sameSession) prefs.getInt(KEY_BATTERY_REVISION, 0) else 0
        val incomingRevision = if (hasIncoming) intent!!.getIntExtra(KEY_BATTERY_REVISION, 0).coerceAtLeast(0) else storedRevision
        val incomingActive = if (hasIncoming) intent!!.getBooleanExtra(KEY_BATTERY_ADJUSTED, false) else adjusted
        val legacyPending = adjusted && storedRevision == 0 && incomingRevision == 0 && !incomingActive
        val stale = sameSession && (storedRevision > incomingRevision || legacyPending)
        val activeOverride = if (stale || !hasIncoming) adjusted else incomingActive
        val originalSensitivity = if (!activeOverride) null else if ((stale || !hasIncoming) && prefs.contains(KEY_ORIGINAL_SENSITIVITY)) {
            prefs.getFloat(KEY_ORIGINAL_SENSITIVITY, 5f).toDouble()
        } else intent?.getDoubleExtra(KEY_ORIGINAL_SENSITIVITY, -1.0)?.takeIf { it.isFinite() && it in 1.0..10.0 }
        val originalInterval = if (!activeOverride) null else if ((stale || !hasIncoming) && prefs.contains(KEY_ORIGINAL_INTERVAL)) {
            prefs.getLong(KEY_ORIGINAL_INTERVAL, 30_000L)
        } else intent?.getLongExtra(KEY_ORIGINAL_INTERVAL, -1L)?.takeIf { it in 5_000L..60_000L }
        return SafetyConfig(
            batterySafetyAdjusted = activeOverride,
            batterySafetyRevision = if (stale) storedRevision else incomingRevision,
            batteryOriginalSensitivity = originalSensitivity,
            batteryOriginalIntervalMillis = originalInterval,
            sessionId = sessionId,
            trailName = intent?.getStringExtra(KEY_TRAIL_NAME)
                ?: prefs.getString(KEY_TRAIL_NAME, "Active hike")
                ?: "Active hike",
            longestRestMillis = (if (intent?.hasExtra(KEY_REST_MILLIS) == true) {
                intent.getLongExtra(KEY_REST_MILLIS, 180_000L)
            } else {
                prefs.getLong(KEY_REST_MILLIS, 180_000L)
            }).coerceIn(30_000L, 86_400_000L),
            // The warning acknowledgement window is intentionally fixed. Only
            // the safe-rest duration is user configurable.
            responseMillis = WARNING_RESPONSE_MILLIS,
            sensitivity = (if (!stale && intent?.hasExtra(KEY_SENSITIVITY) == true) {
                intent.getDoubleExtra(KEY_SENSITIVITY, 5.0)
            } else {
                prefs.getFloat(KEY_SENSITIVITY, 5f).toDouble()
            }).coerceIn(1.0, 10.0),
            fallDetectionEnabled = if (
                intent?.hasExtra(KEY_FALL_DETECTION_ENABLED) == true
            ) {
                intent.getBooleanExtra(KEY_FALL_DETECTION_ENABLED, true)
            } else {
                prefs.getBoolean(KEY_FALL_DETECTION_ENABLED, true)
            },
            ownerUid = intent?.getStringExtra(KEY_OWNER_UID) ?: prefs.getString(KEY_OWNER_UID, "").orEmpty(),
            locationUploadIntervalMillis = (if (!stale && intent?.hasExtra(KEY_UPLOAD_INTERVAL) == true) {
                intent.getLongExtra(KEY_UPLOAD_INTERVAL, 60_000L)
            } else prefs.getLong(KEY_UPLOAD_INTERVAL, 60_000L)).coerceIn(5_000L, 86_400_000L),
        )
    }

    private fun persistConfig(value: SafetyConfig) {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val existingSession = prefs.getString(KEY_SESSION_ID, null)
        val editor = prefs.edit()
            .putBoolean(KEY_ENABLED, true)
            .putString(KEY_SESSION_ID, value.sessionId)
            .putString(KEY_TRAIL_NAME, value.trailName)
            .putLong(KEY_REST_MILLIS, value.longestRestMillis)
            .putLong(KEY_RESPONSE_MILLIS, value.responseMillis)
            .putFloat(KEY_SENSITIVITY, value.sensitivity.toFloat())
            .putBoolean(KEY_BATTERY_ADJUSTED, value.batterySafetyAdjusted)
            .putInt(KEY_BATTERY_REVISION, value.batterySafetyRevision)
            .putBoolean(KEY_FALL_DETECTION_ENABLED, value.fallDetectionEnabled)
            .putString(KEY_OWNER_UID, value.ownerUid)
            .putLong(KEY_UPLOAD_INTERVAL, value.locationUploadIntervalMillis)
        if (value.batteryOriginalSensitivity != null) editor.putFloat(KEY_ORIGINAL_SENSITIVITY, value.batteryOriginalSensitivity.toFloat())
        else editor.remove(KEY_ORIGINAL_SENSITIVITY)
        if (value.batteryOriginalIntervalMillis != null) editor.putLong(KEY_ORIGINAL_INTERVAL, value.batteryOriginalIntervalMillis)
        else editor.remove(KEY_ORIGINAL_INTERVAL)
        if (existingSession != value.sessionId) {
            editor.putLong(KEY_LAST_MOTION_WALL, System.currentTimeMillis())
            clearPendingEvent(editor)
            editor.remove(KEY_LAST_LATITUDE).remove(KEY_LAST_LONGITUDE)
                .remove(KEY_LAST_ACCURACY).remove(KEY_LAST_CAPTURED_AT)
        }
        editor.apply()
    }

    private fun trackingEnabled(): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        return NativeHikeMonitorLifecyclePolicy.allowsTracking(
            prefs.getBoolean(KEY_ENABLED, false), activeGeneration,
            prefs.getLong(KEY_STOP_GENERATION, 0L),
        )
    }

    private fun startMonitoring() {
        if (monitoring) {
            updateActiveNotification(
                if (impactDetector.isChecking) "Possible fall. Checking for movement."
                else "Safety monitoring active",
            )
            return
        }
        monitoring = true
        notificationManager.cancel(IMPACT_NOTIFICATION_ID)
        restoreMotionClock()
        restorePendingState()
        acquireWakeLock()
        if (config?.fallDetectionEnabled == true) registerSensors()
        registerLocationUpdates()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    private fun stopMonitoring() {
        clearImpactCheck()
        if (!monitoring) return
        monitoring = false
        handler.removeCallbacks(ticker)
        sensorManager.unregisterListener(this)
        runCatching { locationManager.removeUpdates(this) }
        wakeLock?.let { lock -> if (lock.isHeld) lock.release() }
        wakeLock = null
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:hike-safety-monitor",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun registerSensors() {
        stillnessRotation.reset()
        val accelerometer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER, true)
                ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        } else {
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        }
        val gyroscope = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE, true)
                ?: sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        } else {
            sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        }
        accelerometer?.let {
            sensorManager.registerListener(this, it, SENSOR_PERIOD_MICROS)
        }
        gyroscope?.let {
            sensorManager.registerListener(this, it, SENSOR_PERIOD_MICROS)
        }
        if (accelerometer == null) {
            updateActiveNotification("Accelerometer unavailable; location watch only")
        }
    }

    private fun registerLocationUpdates() {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            updateActiveNotification("Location unavailable; motion watch active")
            return
        }
        val providers = buildList {
            if (coarse && locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                add(LocationManager.NETWORK_PROVIDER)
            }
            if (fine && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                add(LocationManager.GPS_PROVIDER)
            }
            if (locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
                add(LocationManager.PASSIVE_PROVIDER)
            }
        }
        providers.forEach { provider ->
            runCatching {
                locationManager.requestLocationUpdates(
                    provider,
                    config?.locationUploadIntervalMillis ?: LOCATION_INTERVAL_MILLIS,
                    0f,
                    this,
                    Looper.getMainLooper(),
                )
                locationManager.getLastKnownLocation(provider)?.let(::onLocationChanged)
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (!monitoring || !trackingEnabled() ||
            config?.fallDetectionEnabled != true || state != DetectionState.NORMAL
        ) return
        val now = SystemClock.elapsedRealtime()
        val sampledAt = (event.timestamp / 1_000_000L).coerceAtMost(now)
        if (now - sampledAt > 1_000L || event.values.any { !it.isFinite() }) return
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                val magnitude = sqrt(
                    event.values[0].toDouble() * event.values[0] +
                        event.values[1].toDouble() * event.values[1] +
                        event.values[2].toDouble() * event.values[2],
                )
                handleAccelerometer(sampledAt, magnitude)
            }
            Sensor.TYPE_GYROSCOPE -> {
                val (x, y, z) = event.values
                val peakRotation = maxOf(abs(x), abs(y), abs(z))
                if (stillnessRotation.detectsMotion(sampledAt, peakRotation)) noteMotion(now)
                impactDetector.recordRotation(sampledAt, peakRotation > 0.08f)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun handleAccelerometer(now: Long, magnitude: Double) {
        val settings = config ?: return
        if (abs(magnitude - FallImpactDetector.GRAVITY) > 1.4) noteMotion(now)
        val wasChecking = impactDetector.isChecking
        impactDetector.recordAcceleration(now, magnitude, settings.sensitivity)
        if (!wasChecking && impactDetector.isChecking) showImpactCheck()
    }

    private fun clearImpactCheck() {
        val wasChecking = impactDetector.isChecking
        impactDetector.reset()
        if (!wasChecking) return
        notificationManager.cancel(IMPACT_NOTIFICATION_ID)
        onFallImpactCheckChanged?.invoke()
    }

    override fun onLocationChanged(location: Location) {
        if (!monitoring || !trackingEnabled()) return
        if (!isFreshLocation(location)) return
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else 50.0
        if (!accuracy.isFinite() || accuracy < 0 || accuracy > 500) return
        val existing = latestLocation
        if (existing != null && location.time < existing.time) return
        latestLocation = Location(location)
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_LAST_LATITUDE, location.latitude.toString())
            .putString(KEY_LAST_LONGITUDE, location.longitude.toString())
            .putString(KEY_LAST_ACCURACY, accuracy.toString())
            .putLong(KEY_LAST_CAPTURED_AT, location.time)
            .apply()
        val reference = referenceLocation
        if (reference == null) {
            referenceLocation = Location(location)
            return
        }
        val referenceAccuracy = if (reference.hasAccuracy()) {
            reference.accuracy.toDouble()
        } else {
            50.0
        }
        val movementThreshold = max(
            5.0,
            min(100.0, max(referenceAccuracy, accuracy) * 1.5),
        )
        val distance = reference.distanceTo(location).toDouble()
        if (distance.isFinite() && distance > movementThreshold) {
            referenceLocation = Location(location)
            noteMotion(SystemClock.elapsedRealtime())
        } else if (accuracy < referenceAccuracy) {
            referenceLocation = Location(location)
        }
    }

    private fun isFreshLocation(location: Location): Boolean {
        val age = System.currentTimeMillis() - location.time
        return location.latitude.isFinite() && location.latitude in -90.0..90.0 &&
            location.longitude.isFinite() && location.longitude in -180.0..180.0 &&
            location.hasAccuracy() && location.accuracy.isFinite() &&
            location.accuracy in 0f..500f && location.time > 0L &&
            age in -5_000L..LOCATION_MAX_AGE_MILLIS
    }

    // sampleLocationIfDue: Persist a due GPS sample before scheduling cloud footprint uploads.
    private fun sampleLocationIfDue() {
        if (!monitoring || !trackingEnabled()) return
        // The resumed Flutter isolate owns foreground sampling; avoid two clocks
        // recording nearly identical positions at different milliseconds.
        if (flutterUiForeground) return
        val settings = config ?: return
        val elapsed = SystemClock.elapsedRealtime()
        if (elapsed - lastSampleAtElapsed < (config?.locationUploadIntervalMillis ?: LOCATION_INTERVAL_MILLIS)) return
        val location = latestLocation?.takeIf(::isFreshLocation) ?: return
        if (settings.ownerUid.isBlank()) return
        if (FirebaseAuth.getInstance().currentUser?.uid != settings.ownerUid) return
        val sampledAt = System.currentTimeMillis()
        runCatching {
            locationSamples.append(settings.sessionId, settings.ownerUid, sampledAt, location)
        }.onSuccess {
            lastSampleAtElapsed = elapsed
            HikeArrivalSafety.recordFootprint(this, settings.sessionId, settings.ownerUid, location)
        }
            .onFailure { android.util.Log.e("HikeSafetyMonitor", "Unable to persist GPS sample", it) }
    }

    private fun uploadBufferedLocationsIfDue() {
        if (!monitoring) return
        val settings = config ?: return
        if (flutterUiForeground || uploadingLocations) return
        if (FirebaseAuth.getInstance().currentUser?.uid != settings.ownerUid) return
        val elapsed = SystemClock.elapsedRealtime()
        if (elapsed - lastUploadAttemptElapsed < settings.locationUploadIntervalMillis) return
        lastUploadAttemptElapsed = elapsed
        val sessions = runCatching { locationSamples.pendingSessions(settings.ownerUid, forCloud = true) }
            .getOrElse { return }
            .sortedBy { if (it == settings.sessionId) 0 else 1 }
        uploadNextLocationBatch(settings, sessions)
    }

    // uploadNextLocationBatch: Upload bounded footprint chunks and acknowledge only a confirmed server response.
    private fun uploadNextLocationBatch(settings: SafetyConfig, pendingSessions: List<String>) {
        if (!monitoring) return
        val uploadSessionId = pendingSessions.firstOrNull() ?: return
        if (uploadingLocations || flutterUiForeground ||
            FirebaseAuth.getInstance().currentUser?.uid != settings.ownerUid) return
        val samples = runCatching {
            locationSamples.pending(uploadSessionId, settings.ownerUid, 200, forCloud = true)
        }.getOrElse {
            android.util.Log.e("HikeSafetyMonitor", "Unable to read buffered GPS samples", it)
            return
        }
        if (samples.isEmpty()) {
            uploadNextLocationBatch(settings, pendingSessions.drop(1))
            return
        }
        uploadingLocations = true
        val points = samples.map { sample ->
            buildMap<String, Any> {
                put("recordedAtMillis", sample.getValue("sampledAtMillis"))
                put("fixCapturedAtMillis", sample.getValue("capturedAtMillis"))
                put("latitude", sample.getValue("latitude"))
                put("longitude", sample.getValue("longitude"))
                put("accuracyMeters", sample.getValue("accuracyMeters"))
                sample["altitudeMeters"]?.let { put("altitudeMeters", it) }
                put("pointType", "gps")
            }
        }
        runCatching {
            // Update cloud: upload background GPS footprints
            FirebaseFunctions.getInstance("us-central1")
                .getHttpsCallable("appendHikeFootprints")
                .call(mapOf("sessionId" to uploadSessionId, "footprints" to points))
                .addOnCompleteListener { task ->
                    uploadingLocations = false
                    if (task.isSuccessful) {
                        val payload = task.result?.data as? Map<*, *>
                        val acknowledged = (payload?.get("committedRecordedAtMillis") as? List<*>)
                            ?.mapNotNull { (it as? Number)?.toLong() }?.toSet().orEmpty()
                        val ids = samples.filter { (it["sampledAtMillis"] as Number).toLong() in acknowledged }
                            .map { it["sampleId"] as String }
                        val retained = runCatching { locationSamples.acknowledge(uploadSessionId, settings.ownerUid, ids, cloud = true) }
                            .onFailure { android.util.Log.e("HikeSafetyMonitor", "Unable to retain cloud GPS acknowledgement", it) }
                        // A single scheduled flush may need several bounded batches after an outage.
                        if (monitoring && config?.ownerUid == settings.ownerUid) {
                            val next = if (retained.isSuccess && ids.size == samples.size && samples.size == 200) pendingSessions else pendingSessions.drop(1)
                            uploadNextLocationBatch(settings, next)
                        }
                    } else {
                        android.util.Log.w("HikeSafetyMonitor", "GPS batch retained for retry", task.exception)
                        if (monitoring) uploadNextLocationBatch(settings, pendingSessions.drop(1))
                    }
                }
        }.onFailure {
            uploadingLocations = false
            android.util.Log.w("HikeSafetyMonitor", "GPS batch retained for retry", it)
        }
    }

    // evaluateTimers: Advance stillness and response timers from persisted motion state.
    private fun applyBatterySafetyIfNeeded() {
        if (!monitoring || !trackingEnabled()) return
        val current = config ?: return
        val battery = (getSystemService(BATTERY_SERVICE) as BatteryManager).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        if (battery !in 0..100) return
        val updated = if (!current.batterySafetyAdjusted && battery < 30) {
            current.copy(batterySafetyAdjusted = true, batterySafetyRevision = current.batterySafetyRevision + 1,
                batteryOriginalSensitivity = current.sensitivity, batteryOriginalIntervalMillis = current.locationUploadIntervalMillis,
                sensitivity = 5.0, locationUploadIntervalMillis = 60_000L)
        } else if (current.batterySafetyAdjusted && battery > 30) {
            val originalSensitivity = current.batteryOriginalSensitivity ?: return
            val originalInterval = current.batteryOriginalIntervalMillis ?: return
            current.copy(batterySafetyAdjusted = false, batterySafetyRevision = current.batterySafetyRevision + 1,
                sensitivity = originalSensitivity, locationUploadIntervalMillis = originalInterval,
                batteryOriginalSensitivity = null, batteryOriginalIntervalMillis = null)
        } else return
        config = updated
        persistConfig(updated)
        locationManager.removeUpdates(this)
        registerLocationUpdates()
    }

    private fun evaluateTimers() {
        if (!monitoring || !trackingEnabled()) return
        applyBatterySafetyIfNeeded()
        val settings = config ?: return
        if (!settings.fallDetectionEnabled) return
        val now = SystemClock.elapsedRealtime()
        when (state) {
            DetectionState.NORMAL -> {
                when (impactDetector.outcomeAt(now)) {
                    FallImpactDetector.Outcome.VERIFIED -> beginResponseCountdown("fall_stillness")
                    FallImpactDetector.Outcome.EXPIRED -> {
                        clearImpactCheck()
                        updateActiveNotification("Safety monitoring active")
                    }
                    null -> {
                        if (!impactDetector.isChecking && now - lastMotionElapsed >= settings.longestRestMillis) {
                            beginResponseCountdown("prolonged_stillness")
                        }
                    }
                }
            }
            DetectionState.AWAITING_RESPONSE -> {
                val deviceLocked = keyguardManager.isDeviceLocked
                if (wasDeviceLockedDuringWarning && !deviceLocked) {
                    cancelAlert("Phone unlock response received")
                    return
                }
                if (deviceLocked) wasDeviceLockedDuringWarning = true
                if (now >= responseDeadlineElapsed) escalateAlert()
            }
            DetectionState.TRIGGERING -> Unit
        }
    }

    // beginResponseCountdown: Start the fixed response window before escalating a safety alert.
    private fun beginResponseCountdown(kind: String) {
        if (!trackingEnabled()) return
        val settings = config ?: return
        clearImpactCheck()
        val nowWall = System.currentTimeMillis()
        val deadlineWall = nowWall + settings.responseMillis
        val eventId = "${settings.sessionId}:$kind:$nowWall"
        responseDeadlineElapsed = SystemClock.elapsedRealtime() + settings.responseMillis
        state = DetectionState.AWAITING_RESPONSE
        wasDeviceLockedDuringWarning = keyguardManager.isDeviceLocked
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_EVENT_ID, eventId)
            .putString(KEY_EVENT_KIND, kind)
            .putString(KEY_EVENT_PHASE, "awaiting_response")
            .putLong(KEY_EVENT_DETECTED_WALL, nowWall)
            .putLong(KEY_EVENT_DEADLINE_WALL, deadlineWall)
            .remove(KEY_EVENT_TRIGGERED_WALL)
            .remove(KEY_DISPATCH_MESSAGE)
            .remove(KEY_LOCAL_ALARM_STOPPED)
            .apply()
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            alertNotification(kind, settings.responseMillis, triggering = false),
        )
        vibrateAlert(longRunning = false)
        speakWarningPrompt(
            "Are you okay? Tap anywhere on the phone screen to respond.",
        )
        showSafetyPopup(eventId, kind)
    }

    private fun escalateAlert() {
        if (!trackingEnabled()) return
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val eventId = prefs.getString(KEY_EVENT_ID, null) ?: return
        val kind = prefs.getString(KEY_EVENT_KIND, "prolonged_stillness")
            ?: "prolonged_stillness"
        val triggeredWall = System.currentTimeMillis()
        state = DetectionState.TRIGGERING
        prefs.edit()
            .putString(KEY_EVENT_PHASE, "triggering")
            .putLong(KEY_EVENT_TRIGGERED_WALL, triggeredWall)
            .apply()
        // Request the response screen before Flutter engine initialization or
        // MediaPlayer.prepare can hold the main thread. A blocked activity
        // launch must never prevent the emergency dispatch or local alarm.
        val launch = safetyLaunchIntent(eventId, kind).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        runCatching { startActivity(launch) }
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            alertNotification(kind, 0L, triggering = true),
        )
        stopWarningOutputs()
        handler.post {
            // A safe response or a new hike can clear/replace this event before
            // the next turn. Neither dispatch nor alarm may revive it later.
            if (!isCurrentTriggeredEvent(eventId)) return@post
            if (prefs.getString(KEY_EVENT_PHASE, null) != "dispatched") {
                startBackgroundDispatch(eventId, kind, triggeredWall)
            }
            if (!isCurrentTriggeredEvent(eventId)) return@post
            if (prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)) return@post
            physicalAlarm.start()
            if (!isCurrentTriggeredEvent(eventId)) return@post
            if (prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)) return@post
            vibrateAlert(longRunning = true)
        }
    }

    private fun isCurrentTriggeredEvent(eventId: String): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        return eventId.isNotBlank() && prefs.getString(KEY_EVENT_ID, null) == eventId &&
            prefs.getString(KEY_EVENT_PHASE, null) in
                setOf("triggering", "dispatching", "dispatch_failed", "dispatched")
    }

    private fun cancelAlert(reason: String) {
        destroyBackgroundEngine()
        stopWarningOutputs()
        physicalAlarm.stop()
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        clearPendingEvent(prefs.edit()).apply()
        notificationManager.cancel(ALERT_NOTIFICATION_ID)
        getSystemService(Vibrator::class.java)?.cancel()
        resetToNormal(SystemClock.elapsedRealtime())
        if (monitoring && trackingEnabled()) {
            updateActiveNotification("$reason. Safety monitoring resumed.")
        }
    }

    private fun stopTriggeredAlarmOutputs(eventId: String): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (prefs.getString(KEY_EVENT_ID, null) != eventId ||
            !prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)
        ) return false
        try {
            stopWarningOutputs()
            physicalAlarm.stop()
            getSystemService(Vibrator::class.java)?.cancel()
            notificationManager.cancel(ALERT_NOTIFICATION_ID)
            // Proof is archived only after every local output stop completed,
            // before durable dispatch cleanup can remove the pending event.
            recordStoppedAlarmReceipt(this, eventId)
        } catch (error: RuntimeException) {
            if (prefs.getString(KEY_EVENT_ID, null) == eventId &&
                !wasSafetyAlarmStopped(this, eventId)
            ) prefs.edit().putBoolean(KEY_LOCAL_ALARM_STOPPED, false).apply()
            throw error
        }
        // Only a confirmed durable dispatch permits clearing the event/engine.
        completeStoppedDispatchedEvent(eventId)
        return true
    }

    private fun completeStoppedDispatchedEvent(eventId: String): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (prefs.getString(KEY_EVENT_ID, null) != eventId ||
            prefs.getString(KEY_EVENT_PHASE, null) != "dispatched" ||
            !prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)
        ) return false
        val dispatchOnly = prefs.getBoolean(KEY_DISPATCH_ONLY, false)
        destroyBackgroundEngine()
        clearPendingEvent(prefs.edit()).remove(KEY_DISPATCH_ONLY).apply()
        notificationManager.cancel(ALERT_NOTIFICATION_ID)
        if (dispatchOnly) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } else {
            resetToNormal(SystemClock.elapsedRealtime())
            if (monitoring && trackingEnabled()) updateActiveNotification("Safety monitoring active")
        }
        return true
    }

    private fun retainPendingDispatchWithoutTracking(): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val eventId = prefs.getString(KEY_EVENT_ID, null) ?: return false
        val phase = prefs.getString(KEY_EVENT_PHASE, null)
        if (phase !in setOf("triggering", "dispatching", "dispatch_failed")) return false
        // Ending a hike stops all tracking immediately, but must not destroy
        // an SOS dispatcher before it can save a durable retry or send it.
        prefs.edit().putBoolean(KEY_ENABLED, false)
            .putBoolean(KEY_LOCAL_ALARM_STOPPED, true)
            .putBoolean(KEY_DISPATCH_ONLY, true).apply()
        stopMonitoring()
        stopTriggeredAlarmOutputs(eventId)
        try {
            // Cold recovery of an actual pending SOS needs a foreground
            // dispatcher, never the location/sensor monitoring path.
            startForeground(ACTIVE_NOTIFICATION_ID,
                activeNotification("Finishing SOS delivery; hike tracking stopped"))
        } catch (error: RuntimeException) {
            // The original event remains durable for the foreground app retry
            // if Android disallows starting this service in the background.
            android.util.Log.w("HikeSafetyMonitor", "Pending SOS retained for foreground retry", error)
            stopSelf()
            return true
        }
        if (backgroundDispatchEventId != eventId) {
            handler.post {
                if (!isCurrentTriggeredEvent(eventId) ||
                    !prefs.getBoolean(KEY_DISPATCH_ONLY, false) ||
                    prefs.getString(KEY_EVENT_PHASE, null) !in setOf("triggering", "dispatching", "dispatch_failed")
                ) return@post
                startBackgroundDispatch(eventId,
                    prefs.getString(KEY_EVENT_KIND, "prolonged_stillness") ?: "prolonged_stillness",
                    prefs.getLong(KEY_EVENT_TRIGGERED_WALL, System.currentTimeMillis()))
            }
        }
        return true
    }

    private fun resetToNormal(now: Long) {
        state = DetectionState.NORMAL
        wasDeviceLockedDuringWarning = false
        responseDeadlineElapsed = 0L
        clearImpactCheck()
        stillnessRotation.reset()
        noteMotion(now, persistImmediately = true)
    }

    private fun noteMotion(now: Long, persistImmediately: Boolean = false) {
        lastMotionElapsed = now
        if (persistImmediately || now - lastMotionPersistedElapsed >= 5_000L) {
            lastMotionPersistedElapsed = now
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putLong(KEY_LAST_MOTION_WALL, System.currentTimeMillis())
                .apply()
        }
    }

    private fun restoreMotionClock() {
        val nowElapsed = SystemClock.elapsedRealtime()
        val nowWall = System.currentTimeMillis()
        val savedWall = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getLong(KEY_LAST_MOTION_WALL, nowWall)
        val age = (nowWall - savedWall).coerceIn(0L, 86_400_000L)
        lastMotionElapsed = nowElapsed - age
        lastMotionPersistedElapsed = nowElapsed
    }

    // restorePendingState: Resume an unfinished warning or dispatch after the service restarts.
    private fun restorePendingState() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val eventId = prefs.getString(KEY_EVENT_ID, null) ?: return
        val kind = prefs.getString(KEY_EVENT_KIND, "prolonged_stillness")
            ?: "prolonged_stillness"
        val phase = prefs.getString(KEY_EVENT_PHASE, "awaiting_response")
        val localAlarmStopped = prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)
        if (phase == "dispatched") {
            state = DetectionState.TRIGGERING
            if (completeStoppedDispatchedEvent(eventId)) return
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                dispatchResultNotification(
                    prefs.getString(KEY_DISPATCH_MESSAGE, null)
                        ?: "The emergency alert was sent or queued for retry.",
                ),
            )
            physicalAlarm.start()
            vibrateAlert(longRunning = true)
            return
        }
        if (phase == "triggering" || phase == "dispatching" ||
            phase == "dispatch_failed"
        ) {
            state = DetectionState.TRIGGERING
            if (!localAlarmStopped) {
                notificationManager.notify(
                    ALERT_NOTIFICATION_ID,
                    alertNotification(kind, 0L, triggering = true),
                )
                physicalAlarm.start()
                vibrateAlert(longRunning = true)
            }
            startBackgroundDispatch(
                eventId,
                kind,
                prefs.getLong(KEY_EVENT_TRIGGERED_WALL, System.currentTimeMillis()),
            )
            return
        }
        val remaining = prefs.getLong(KEY_EVENT_DEADLINE_WALL, 0L) -
            System.currentTimeMillis()
        if (remaining <= 0L) {
            state = DetectionState.AWAITING_RESPONSE
            wasDeviceLockedDuringWarning = keyguardManager.isDeviceLocked
            responseDeadlineElapsed = SystemClock.elapsedRealtime()
            escalateAlert()
        } else {
            state = DetectionState.AWAITING_RESPONSE
            wasDeviceLockedDuringWarning = keyguardManager.isDeviceLocked
            responseDeadlineElapsed = SystemClock.elapsedRealtime() + remaining
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                alertNotification(kind, remaining, triggering = false),
            )
            vibrateAlert(longRunning = false)
            speakWarningPrompt(
                "Are you okay? Tap anywhere on the phone screen to respond.",
            )
            showSafetyPopup(eventId, kind)
        }
        // Keep the compiler and diagnostics aware that this is the persisted
        // event we are resuming, not a new candidate.
        if (eventId.isBlank()) cancelAlert("Invalid safety event")
    }

    // startBackgroundDispatch: Run the Flutter safety dispatcher in a headless engine.
    private fun startBackgroundDispatch(
        eventId: String,
        kind: String,
        triggeredWall: Long,
    ) {
        if (eventId.isBlank() || backgroundDispatchEventId == eventId) return
        backgroundDispatchEventId = eventId
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_EVENT_PHASE, "dispatching")
            .remove(KEY_DISPATCH_MESSAGE)
            .apply()

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val engine = FlutterEngine(applicationContext)
            backgroundEngine = engine
            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                "hiker_circle/hike_safety_background",
            )
            channel.setMethodCallHandler { call, result ->
                if (call.method != "dispatcherReady") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(null)
                val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                channel.invokeMethod(
                    "dispatchSafetyEvent",
                    mapOf(
                        "eventId" to eventId,
                        "sessionId" to (config?.sessionId
                            ?: prefs.getString(KEY_SESSION_ID, "").orEmpty()),
                        "kind" to kind,
                        "triggeredAtMillis" to triggeredWall,
                        "latitude" to prefs.getString(KEY_LAST_LATITUDE, null)
                            ?.toDoubleOrNull(),
                        "longitude" to prefs.getString(KEY_LAST_LONGITUDE, null)
                            ?.toDoubleOrNull(),
                        "accuracyMeters" to prefs.getString(KEY_LAST_ACCURACY, null)
                            ?.toDoubleOrNull(),
                        "capturedAtMillis" to prefs.getLong(KEY_LAST_CAPTURED_AT, 0L),
                    ),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            finishBackgroundDispatch(
                                eventId,
                                result as? Map<*, *>,
                                null,
                            )
                        }

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) {
                            finishBackgroundDispatch(
                                eventId,
                                null,
                                errorMessage ?: errorCode,
                            )
                        }

                        override fun notImplemented() {
                            finishBackgroundDispatch(
                                eventId,
                                null,
                                "Background dispatcher is unavailable.",
                            )
                        }
                    },
                )
            }
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "hikeSafetyBackgroundDispatcher",
                ),
            )
            backgroundDispatchTimeout = Runnable {
                finishBackgroundDispatch(
                    eventId,
                    null,
                    "Background dispatch timed out; tap to retry in the app.",
                )
            }.also { handler.postDelayed(it, 90_000L) }
        } catch (error: Throwable) {
            finishBackgroundDispatch(
                eventId,
                null,
                error.message ?: "Background dispatch could not start.",
            )
        }
    }

    private fun finishBackgroundDispatch(
        eventId: String,
        result: Map<*, *>?,
        error: String?,
    ) {
        if (backgroundDispatchEventId != eventId) return
        backgroundDispatchTimeout?.let(handler::removeCallbacks)
        backgroundDispatchTimeout = null
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (prefs.getString(KEY_EVENT_ID, null) != eventId) {
            destroyBackgroundEngine()
            return
        }

        val message: String
        if (error == null && result != null) {
            val sentCount = (result["sentCount"] as? Number)?.toInt() ?: 0
            val contactCount = (result["contactCount"] as? Number)?.toInt() ?: 0
            val queued = result["queuedForRetry"] == true
            message = when {
                sentCount > 0 && sentCount >= contactCount ->
                    resources.getQuantityString(R.plurals.sos_contacts_notified, sentCount, sentCount)
                sentCount > 0 && queued ->
                    resources.getQuantityString(R.plurals.sos_contacts_partially_notified, sentCount, sentCount)
                queued ->
                    "Emergency alert saved securely and queued until the network returns."
                else -> "Emergency alert processing completed."
            }
            prefs.edit()
                .putString(KEY_EVENT_PHASE, "dispatched")
                .putString(KEY_DISPATCH_MESSAGE, message)
                .apply()
            if (completeStoppedDispatchedEvent(eventId)) return
            getSystemService(Vibrator::class.java)?.cancel()
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                dispatchResultNotification(message),
            )
        } else {
            message = "Automatic contact delivery needs attention. Tap to retry in HikerCircle."
            prefs.edit()
                .putString(KEY_EVENT_PHASE, "dispatch_failed")
                .putString(KEY_DISPATCH_MESSAGE, error ?: message)
                .apply()
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                if (prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)) {
                    dispatchResultNotification(message)
                } else {
                    alertNotification(
                        prefs.getString(KEY_EVENT_KIND, "prolonged_stillness")
                            ?: "prolonged_stillness",
                        0L,
                        triggering = true,
                    )
                },
            )
        }
        destroyBackgroundEngine()
        if (prefs.getBoolean(KEY_DISPATCH_ONLY, false)) {
            // The failed outcome remains persisted for the in-app retry. The
            // finished headless engine no longer needs a tracking service.
            prefs.edit().remove(KEY_DISPATCH_ONLY).apply()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun destroyBackgroundEngine() {
        backgroundDispatchTimeout?.let(handler::removeCallbacks)
        backgroundDispatchTimeout = null
        backgroundDispatchEventId = null
        backgroundEngine?.destroy()
        backgroundEngine = null
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        notificationManager.createNotificationChannel(
            NotificationChannel(
                ACTIVE_CHANNEL_ID,
                "Active hike safety monitoring",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps fall, motion and prolonged-stillness monitoring active"
                setShowBadge(false)
            },
        )
        notificationManager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "Fall and stillness safety alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Urgent response prompts before a hike SOS is escalated"
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
        notificationManager.createNotificationChannel(
            NotificationChannel(
                IMPACT_CHANNEL_ID,
                "Possible fall checks",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
    }

    private fun showImpactCheck() {
        updateActiveNotification("Possible fall. Checking for movement.")
        onFallImpactCheckChanged?.invoke()
        if (flutterUiForeground) return
        val notification = notificationBuilder(IMPACT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Possible fall detected")
            .setContentText("Checking for movement")
            .setCategory(Notification.CATEGORY_STATUS)
            .setPriority(Notification.PRIORITY_HIGH)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notification.setTimeoutAfter(FallImpactDetector.CHECK_TIMEOUT_MILLIS)
        }
        notificationManager.notify(IMPACT_NOTIFICATION_ID, notification.build())
    }

    private fun activeNotification(status: String): Notification {
        val current = config
        val contentIntent = PendingIntent.getActivity(
            this,
            42120,
            Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(
                    "hikercircle://hike/active?sessionId=${Uri.encode(current?.sessionId ?: "")}",
                )
                setPackage(packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            pendingIntentFlags(),
        )
        return notificationBuilder(ACTIVE_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(current?.trailName ?: "Active hike")
            .setContentText(status)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
    }

    private fun updateActiveNotification(status: String) {
        notificationManager.notify(ACTIVE_NOTIFICATION_ID, activeNotification(status))
    }

    private fun alertNotification(kind: String, remainingMillis: Long, triggering: Boolean): Notification {
        val eventId = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(KEY_EVENT_ID, "") ?: ""
        val isStillness = kind == "prolonged_stillness"
        val title = if (triggering) {
            if (isStillness) "Stillness SOS escalation" else "Fall SOS escalation"
        } else {
            if (isStillness) "Prolonged stillness detected" else "Possible fall detected"
        }
        val seconds = ((remainingMillis + 999L) / 1_000L).coerceAtLeast(0L)
        val body = if (triggering) {
            "The response timer ended. HikerCircle is notifying your emergency contacts in the background."
        } else {
            "Are you okay? Tap I'M SAFE within $seconds seconds to cancel SOS."
        }
        val launchIntent = safetyLaunchIntent(eventId, kind)
        val launchPending = PendingIntent.getActivity(
            this,
            42130,
            launchIntent,
            pendingIntentFlags(),
        )
        val builder = notificationBuilder(ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(launchPending)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(Notification.PRIORITY_MAX)
        val cancelIntent = PendingIntent.getService(
            this,
            42131,
            Intent(this, HikeSafetyMonitorService::class.java).apply {
                action = if (triggering) ACTION_STOP_TRIGGERED_ALARM else ACTION_CANCEL_ALERT
                data = Uri.parse("hikercircle://hike/safety-response/${Uri.encode(eventId)}")
                putExtra(KEY_EVENT_ID, eventId)
            },
            pendingIntentFlags(),
        )
        builder.addAction(
            Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                "I'M SAFE — STOP ALARM",
                cancelIntent,
            ).build(),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setFullScreenIntent(launchPending, true)
        }
        return builder.build()
    }

    private fun dispatchResultNotification(message: String): Notification {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val eventId = prefs.getString(KEY_EVENT_ID, "") ?: ""
        val launch = if (prefs.getBoolean(KEY_LOCAL_ALARM_STOPPED, false)) {
            Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("hikercircle://hike/safety-alarm-stopped?eventId=${Uri.encode(eventId)}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        } else {
            safetyLaunchIntent(eventId,
                prefs.getString(KEY_EVENT_KIND, "prolonged_stillness") ?: "prolonged_stillness")
        }
        val launchPending = PendingIntent.getActivity(
            this,
            42132,
            launch,
            pendingIntentFlags(),
        )
        return notificationBuilder(ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("HikerCircle safety alert processed")
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(launchPending)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "I'M SAFE — STOP ALARM",
                    PendingIntent.getService(
                        this,
                        42131,
                        Intent(this, HikeSafetyMonitorService::class.java).apply {
                            action = ACTION_STOP_TRIGGERED_ALARM
                            putExtra(KEY_EVENT_ID, eventId)
                        },
                        pendingIntentFlags(),
                    ),
                ).build(),
            )
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(Notification.PRIORITY_HIGH)
            .build()
    }

    private fun safetyLaunchIntent(eventId: String, kind: String): Intent {
        return Intent(this, SafetyAlertActivity::class.java).apply {
            action = "com.leongziqi.hikercircle.SAFETY_EVENT"
            data = Uri.parse("hikercircle://hike/safety-popup/${Uri.encode(eventId)}")
            putExtra("nativeSafetyEventId", eventId)
            putExtra("nativeSafetyEventKind", kind)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
    }

    private fun showSafetyPopup(eventId: String, kind: String) {
        runCatching { startActivity(safetyLaunchIntent(eventId, kind)) }
    }

    private fun vibrateAlert(longRunning: Boolean) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = if (longRunning) {
            longArrayOf(0, 700, 300, 700, 300, 1_200)
        } else {
            longArrayOf(0, 500, 250, 500, 250, 500)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, if (longRunning) 0 else -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, if (longRunning) 0 else -1)
        }
    }

    private fun speakWarningPrompt(message: String) {
        val currentSpeaker = textToSpeech
        if (currentSpeaker != null) {
            speakWith(currentSpeaker, message)
            return
        }
        pendingSpeechMessage = message
        textToSpeech = TextToSpeech(applicationContext) { status ->
            val speaker = textToSpeech ?: return@TextToSpeech
            if (status == TextToSpeech.SUCCESS) {
                speaker.language = Locale.getDefault()
                speakWith(speaker, pendingSpeechMessage ?: message)
                pendingSpeechMessage = null
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun speakWith(speaker: TextToSpeech, message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            speaker.speak(message, TextToSpeech.QUEUE_FLUSH, null, "hike_safety_warning")
        } else {
            speaker.speak(message, TextToSpeech.QUEUE_FLUSH, null)
        }
    }

    private fun stopWarningOutputs() {
        pendingSpeechMessage = null
        textToSpeech?.stop()
        getSystemService(Vibrator::class.java)?.cancel()
    }

    private fun notificationBuilder(channelId: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun pendingIntentFlags(): Int = PendingIntent.FLAG_UPDATE_CURRENT or
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }

}
