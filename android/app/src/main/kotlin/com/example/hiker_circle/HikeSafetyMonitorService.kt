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
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import java.util.Locale

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
        const val ACTION_START = "com.leongziqi.hikercircle.safety.START"
        const val ACTION_STOP = "com.leongziqi.hikercircle.safety.STOP"
        const val ACTION_CANCEL_ALERT = "com.leongziqi.hikercircle.safety.CANCEL_ALERT"
        const val ACTION_ACKNOWLEDGE_ALERT =
            "com.leongziqi.hikercircle.safety.ACKNOWLEDGE_ALERT"

        private const val PREFS = "hiker_circle_hike_safety"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_TRAIL_NAME = "trail_name"
        private const val KEY_REST_MILLIS = "rest_millis"
        private const val KEY_RESPONSE_MILLIS = "response_millis"
        private const val KEY_SENSITIVITY = "sensitivity"
        private const val KEY_LAST_MOTION_WALL = "last_motion_wall"
        private const val KEY_EVENT_ID = "event_id"
        private const val KEY_EVENT_KIND = "event_kind"
        private const val KEY_EVENT_PHASE = "event_phase"
        private const val KEY_EVENT_DETECTED_WALL = "event_detected_wall"
        private const val KEY_EVENT_DEADLINE_WALL = "event_deadline_wall"
        private const val KEY_EVENT_TRIGGERED_WALL = "event_triggered_wall"
        private const val KEY_DISPATCH_MESSAGE = "dispatch_message"
        private const val KEY_LAST_LATITUDE = "last_latitude"
        private const val KEY_LAST_LONGITUDE = "last_longitude"
        private const val KEY_LAST_ACCURACY = "last_accuracy"

        private const val ACTIVE_CHANNEL_ID = "hiker_circle_hike_safety_active"
        private const val ALERT_CHANNEL_ID = "hiker_circle_hike_safety_alerts"
        private const val ACTIVE_NOTIFICATION_ID = 4212
        private const val ALERT_NOTIFICATION_ID = 4213
        private const val SENSOR_PERIOD_MICROS = 100_000
        private const val LOCATION_INTERVAL_MILLIS = 30_000L
        private const val STILLNESS_VERIFY_MILLIS = 10_000L
        private const val WARNING_RESPONSE_MILLIS = 15_000L
        private const val FALL_VERIFY_LIMIT_MILLIS = 60_000L
        private const val GRAVITY = 9.80665

        fun startOrUpdate(context: Context, config: SafetyConfig) {
            val intent = Intent(context, HikeSafetyMonitorService::class.java).apply {
                action = ACTION_START
                putExtra(KEY_SESSION_ID, config.sessionId)
                putExtra(KEY_TRAIL_NAME, config.trailName)
                putExtra(KEY_REST_MILLIS, config.longestRestMillis)
                putExtra(KEY_RESPONSE_MILLIS, config.responseMillis)
                putExtra(KEY_SENSITIVITY, config.sensitivity)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, HikeSafetyMonitorService::class.java).apply {
                    action = ACTION_STOP
                },
            )
        }

        fun isConfigured(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ENABLED, false)

        fun restartIfConfigured(context: Context) {
            if (!isConfigured(context)) return
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

        fun pendingEvent(context: Context): Map<String, Any?>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val eventId = prefs.getString(KEY_EVENT_ID, null) ?: return null
            return mapOf(
                "eventId" to eventId,
                "sessionId" to prefs.getString(KEY_SESSION_ID, ""),
                "kind" to prefs.getString(KEY_EVENT_KIND, "prolonged_stillness"),
                "phase" to prefs.getString(KEY_EVENT_PHASE, "awaiting_response"),
                "detectedAtMillis" to prefs.getLong(KEY_EVENT_DETECTED_WALL, 0L),
                "deadlineAtMillis" to prefs.getLong(KEY_EVENT_DEADLINE_WALL, 0L),
                "triggeredAtMillis" to prefs.getLong(KEY_EVENT_TRIGGERED_WALL, 0L),
                "dispatchMessage" to prefs.getString(KEY_DISPATCH_MESSAGE, null),
            )
        }

        fun acknowledgeEvent(context: Context, eventId: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_EVENT_ID, null) != eventId) return
            prefs.edit()
                .remove(KEY_EVENT_ID)
                .remove(KEY_EVENT_KIND)
                .remove(KEY_EVENT_PHASE)
                .remove(KEY_EVENT_DETECTED_WALL)
                .remove(KEY_EVENT_DEADLINE_WALL)
                .remove(KEY_EVENT_TRIGGERED_WALL)
                .remove(KEY_DISPATCH_MESSAGE)
                .apply()
            context.getSystemService(NotificationManager::class.java)
                ?.cancel(ALERT_NOTIFICATION_ID)
            runCatching {
                context.startService(
                    Intent(context, HikeSafetyMonitorService::class.java).apply {
                        action = ACTION_ACKNOWLEDGE_ALERT
                    },
                )
            }
        }
    }

    data class SafetyConfig(
        val sessionId: String,
        val trailName: String,
        val longestRestMillis: Long,
        val responseMillis: Long,
        val sensitivity: Double,
    )

    private enum class DetectionState {
        NORMAL,
        IMPACT_WINDOW,
        BOUNCE,
        VERIFYING_FALL,
        VERIFYING_STILLNESS,
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
    private var state = DetectionState.NORMAL
    private var lastMotionElapsed = SystemClock.elapsedRealtime()
    private var lastMotionPersistedElapsed = 0L
    private var impactWindowEndsElapsed = 0L
    private var bounceEndsElapsed = 0L
    private var verificationStartedElapsed = 0L
    private var quietStartedElapsed = 0L
    private var responseDeadlineElapsed = 0L
    private var latestImpactAcceleration: Double? = null
    private var referenceLocation: Location? = null
    private var monitoring = false
    private var backgroundEngine: FlutterEngine? = null
    private var backgroundDispatchEventId: String? = null
    private var backgroundDispatchTimeout: Runnable? = null
    private var textToSpeech: TextToSpeech? = null
    private var pendingSpeechMessage: String? = null
    private lateinit var physicalAlarm: NativeSosAlarmController
    private var wasDeviceLockedDuringWarning = false

    private val ticker = object : Runnable {
        override fun run() {
            if (!monitoring) return
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
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean(KEY_ENABLED, false)
                    .apply()
                stopMonitoring()
                stopWarningOutputs()
                physicalAlarm.stop()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_CANCEL_ALERT -> {
                cancelAlert("Response received")
                return START_STICKY
            }
            ACTION_ACKNOWLEDGE_ALERT -> {
                cancelAlert("Alert acknowledged")
                return START_STICKY
            }
        }

        val restored = readConfig(intent)
        if (restored == null || restored.sessionId.isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }
        config = restored
        persistConfig(restored)
        startForeground(ACTIVE_NOTIFICATION_ID, activeNotification("Safety monitoring active"))
        startMonitoring()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
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
        val sessionId = intent?.getStringExtra(KEY_SESSION_ID)
            ?.takeIf { it.isNotBlank() }
            ?: prefs.getString(KEY_SESSION_ID, null)
            ?: return null
        return SafetyConfig(
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
            sensitivity = (if (intent?.hasExtra(KEY_SENSITIVITY) == true) {
                intent.getDoubleExtra(KEY_SENSITIVITY, 5.0)
            } else {
                prefs.getFloat(KEY_SENSITIVITY, 5f).toDouble()
            }).coerceIn(1.0, 10.0),
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
        if (existingSession != value.sessionId) {
            editor.putLong(KEY_LAST_MOTION_WALL, System.currentTimeMillis())
            clearPendingEvent(editor)
        }
        editor.apply()
    }

    private fun startMonitoring() {
        if (monitoring) {
            updateActiveNotification("Safety monitoring active")
            return
        }
        monitoring = true
        restoreMotionClock()
        restorePendingState()
        acquireWakeLock()
        registerSensors()
        registerLocationUpdates()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    private fun stopMonitoring() {
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
                    LOCATION_INTERVAL_MILLIS,
                    0f,
                    this,
                    Looper.getMainLooper(),
                )
                locationManager.getLastKnownLocation(provider)?.let(::onLocationChanged)
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        val now = SystemClock.elapsedRealtime()
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                val magnitude = sqrt(
                    event.values[0].toDouble() * event.values[0] +
                        event.values[1].toDouble() * event.values[1] +
                        event.values[2].toDouble() * event.values[2],
                )
                handleAccelerometer(now, magnitude)
            }
            Sensor.TYPE_GYROSCOPE -> {
                val moved = abs(event.values[0]) > 0.08f ||
                    abs(event.values[1]) > 0.08f ||
                    abs(event.values[2]) > 0.08f
                handleGyroscope(now, moved)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun handleAccelerometer(now: Long, magnitude: Double) {
        val settings = config ?: return
        val normalized = (settings.sensitivity - 1.0) / 9.0
        val directImpact = lerp(3.6 * GRAVITY, 2.8 * GRAVITY, normalized)
        val impact = lerp(5.0 * GRAVITY, 4.0 * GRAVITY, normalized)
        val freeFall = lerp(0.25 * GRAVITY, 0.40 * GRAVITY, normalized)

        if (abs(magnitude - GRAVITY) > 1.4 &&
            state != DetectionState.AWAITING_RESPONSE &&
            state != DetectionState.TRIGGERING) {
            noteMotion(now)
        }

        when (state) {
            DetectionState.NORMAL -> {
                if (magnitude >= directImpact) {
                    latestImpactAcceleration = magnitude
                    bounceEndsElapsed = now + 2_000L
                    state = DetectionState.BOUNCE
                } else if (magnitude <= freeFall) {
                    impactWindowEndsElapsed = now + 500L
                    state = DetectionState.IMPACT_WINDOW
                }
            }
            DetectionState.IMPACT_WINDOW -> {
                if (now > impactWindowEndsElapsed) {
                    resetToNormal(now, countAsMotion = false)
                } else if (magnitude >= impact) {
                    latestImpactAcceleration = magnitude
                    bounceEndsElapsed = now + 2_000L
                    state = DetectionState.BOUNCE
                }
            }
            else -> Unit
        }
    }

    private fun handleGyroscope(now: Long, moved: Boolean) {
        if (moved) {
            when (state) {
                DetectionState.VERIFYING_STILLNESS -> resetToNormal(now, countAsMotion = true)
                DetectionState.VERIFYING_FALL -> {
                    quietStartedElapsed = 0L
                    if (now - verificationStartedElapsed >= FALL_VERIFY_LIMIT_MILLIS) {
                        resetToNormal(now, countAsMotion = true)
                    }
                }
                DetectionState.NORMAL -> noteMotion(now)
                else -> Unit
            }
            return
        }
        if (state == DetectionState.VERIFYING_FALL ||
            state == DetectionState.VERIFYING_STILLNESS
        ) {
            if (quietStartedElapsed == 0L) quietStartedElapsed = now
        }
    }

    override fun onLocationChanged(location: Location) {
        if (!location.latitude.isFinite() || !location.longitude.isFinite()) return
        val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else 50.0
        if (!accuracy.isFinite() || accuracy < 0 || accuracy > 500) return
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_LAST_LATITUDE, location.latitude.toString())
            .putString(KEY_LAST_LONGITUDE, location.longitude.toString())
            .putString(KEY_LAST_ACCURACY, accuracy.toString())
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

    private fun evaluateTimers() {
        val settings = config ?: return
        val now = SystemClock.elapsedRealtime()
        when (state) {
            DetectionState.NORMAL -> {
                if (now - lastMotionElapsed >= settings.longestRestMillis) {
                    beginResponseCountdown("prolonged_stillness")
                }
            }
            DetectionState.IMPACT_WINDOW -> {
                if (now > impactWindowEndsElapsed) resetToNormal(now, countAsMotion = false)
            }
            DetectionState.BOUNCE -> {
                if (now >= bounceEndsElapsed) {
                    verificationStartedElapsed = now
                    quietStartedElapsed = 0L
                    state = DetectionState.VERIFYING_FALL
                    updateActiveNotification("Possible fall; checking phone movement")
                }
            }
            DetectionState.VERIFYING_FALL,
            DetectionState.VERIFYING_STILLNESS -> {
                if (quietStartedElapsed != 0L &&
                    now - quietStartedElapsed >= STILLNESS_VERIFY_MILLIS
                ) {
                    beginResponseCountdown(
                        if (state == DetectionState.VERIFYING_STILLNESS) {
                            "prolonged_stillness"
                        } else {
                            "fall_stillness"
                        },
                    )
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

    private fun beginResponseCountdown(kind: String) {
        val settings = config ?: return
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
        notificationManager.notify(
            ALERT_NOTIFICATION_ID,
            alertNotification(kind, 0L, triggering = true),
        )
        stopWarningOutputs()
        startBackgroundDispatch(eventId, kind, triggeredWall)
        physicalAlarm.start()
        vibrateAlert(longRunning = true)
        val launch = safetyLaunchIntent(eventId, kind).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        runCatching { startActivity(launch) }
    }

    private fun cancelAlert(reason: String) {
        destroyBackgroundEngine()
        stopWarningOutputs()
        physicalAlarm.stop()
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        clearPendingEvent(prefs.edit()).apply()
        notificationManager.cancel(ALERT_NOTIFICATION_ID)
        getSystemService(Vibrator::class.java)?.cancel()
        resetToNormal(SystemClock.elapsedRealtime(), countAsMotion = true)
        updateActiveNotification("$reason; safety monitoring resumed")
    }

    private fun resetToNormal(now: Long, countAsMotion: Boolean) {
        state = DetectionState.NORMAL
        wasDeviceLockedDuringWarning = false
        quietStartedElapsed = 0L
        verificationStartedElapsed = 0L
        latestImpactAcceleration = null
        if (countAsMotion) noteMotion(now)
        updateActiveNotification("Safety monitoring active")
    }

    private fun noteMotion(now: Long) {
        lastMotionElapsed = now
        if (now - lastMotionPersistedElapsed >= 5_000L) {
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

    private fun restorePendingState() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val eventId = prefs.getString(KEY_EVENT_ID, null) ?: return
        val kind = prefs.getString(KEY_EVENT_KIND, "prolonged_stillness")
            ?: "prolonged_stillness"
        val phase = prefs.getString(KEY_EVENT_PHASE, "awaiting_response")
        if (phase == "dispatched") {
            state = DetectionState.TRIGGERING
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
            notificationManager.notify(
                ALERT_NOTIFICATION_ID,
                alertNotification(kind, 0L, triggering = true),
            )
            physicalAlarm.start()
            vibrateAlert(longRunning = true)
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
            MethodChannel(
                engine.dartExecutor.binaryMessenger,
                "hiker_circle/build_config",
            ).setMethodCallHandler { call, result ->
                if (call.method == "isDevelopmentOnlyRelease") {
                    result.success(BuildConfig.DEVELOPMENT_ONLY_SIGNING)
                } else {
                    result.notImplemented()
                }
            }
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
                        "sessionId" to (config?.sessionId ?: ""),
                        "kind" to kind,
                        "triggeredAtMillis" to triggeredWall,
                        "latitude" to prefs.getString(KEY_LAST_LATITUDE, null)
                            ?.toDoubleOrNull(),
                        "longitude" to prefs.getString(KEY_LAST_LONGITUDE, null)
                            ?.toDoubleOrNull(),
                        "accuracyMeters" to prefs.getString(KEY_LAST_ACCURACY, null)
                            ?.toDoubleOrNull(),
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
                    "Emergency alert sent to $sentCount contact(s)."
                sentCount > 0 && queued ->
                    "Alert sent to $sentCount contact(s); remaining delivery is queued."
                queued ->
                    "Emergency alert saved securely and queued until the network returns."
                else -> "Emergency alert processing completed."
            }
            prefs.edit()
                .putString(KEY_EVENT_PHASE, "dispatched")
                .putString(KEY_DISPATCH_MESSAGE, message)
                .apply()
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
                alertNotification(
                    prefs.getString(KEY_EVENT_KIND, "prolonged_stillness")
                        ?: "prolonged_stillness",
                    0L,
                    triggering = true,
                ),
            )
        }
        destroyBackgroundEngine()
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
                action = ACTION_CANCEL_ALERT
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
        val launchPending = PendingIntent.getActivity(
            this,
            42132,
            safetyLaunchIntent(
                prefs.getString(KEY_EVENT_ID, "") ?: "",
                prefs.getString(KEY_EVENT_KIND, "prolonged_stillness")
                    ?: "prolonged_stillness",
            ),
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
                            action = ACTION_CANCEL_ALERT
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

    private fun clearPendingEvent(editor: android.content.SharedPreferences.Editor):
        android.content.SharedPreferences.Editor = editor
        .remove(KEY_EVENT_ID)
        .remove(KEY_EVENT_KIND)
        .remove(KEY_EVENT_PHASE)
        .remove(KEY_EVENT_DETECTED_WALL)
        .remove(KEY_EVENT_DEADLINE_WALL)
        .remove(KEY_EVENT_TRIGGERED_WALL)
        .remove(KEY_DISPATCH_MESSAGE)

    private fun lerp(start: Double, end: Double, amount: Double): Double =
        start + (end - start) * amount
}
