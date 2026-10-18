// MainActivity exposes Android alarms, contacts, location, widgets, and sharing to Flutter.
package com.leongziqi.hikercircle

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.provider.ContactsContract
import com.google.firebase.auth.FirebaseAuth
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "hiker_circle/sos_device_alerts"
        private const val DEEP_LINK_CHANNEL = "hiker_circle/deeplinks"
        private const val ACTIVE_HIKE_LIVE_STATUS_CHANNEL =
            "hiker_circle/active_hike_live_status"
        private const val CAMERA_REQUEST_CODE = 8472
        const val QR_SCANNER_CAMERA_REQUEST_CODE = 8475
        private const val LOCATION_REQUEST_CODE = 8473
        private const val POST_NOTIFICATIONS_REQUEST_CODE = 8474
        private const val CONTACTS_REQUEST_CODE = 8476
        private const val LOCATION_TIMEOUT_MILLIS = 6000L
        private const val ALARM_ASSET = "assets/audios/sos_alarm.mp3"
        private const val MEDICAL_ALARM_ASSET = "assets/audios/med_alarm.mp3"
        private const val ACTIVE_HIKE_NOTIFICATION_CHANNEL_ID =
            "hiker_circle_active_hike"
        private const val ACTIVE_HIKE_NOTIFICATION_ID = 4207
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var mediaPlayer: MediaPlayer? = null
    private var activeAlarmAsset: String? = null
    private var textToSpeech: TextToSpeech? = null
    private var pendingSpeechMessage: String? = null
    private var speechReady = false
    private var hikeSpeechRequestId: String? = null
    private var hikeSpeechResult: MethodChannel.Result? = null
    private var safetySpeechRequestId: String? = null
    private var speechSequence = 0L
    private var cameraManager: CameraManager? = null
    private var torchCameraId: String? = null
    private var isTorchPatternActive = false
    private var pendingTorchStart = false
    private var torchPatternIndex = 0
    private var locationManager: LocationManager? = null
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingContactsResult: MethodChannel.Result? = null
    private val nativeLocationSamples by lazy { NativeLocationSampleBuffer(this) }
    private var pendingLocationListener: LocationListener? = null
    private var pendingAllowLastKnownLocation = false
    private var pendingRequirePreciseLocation = false
    private var pendingBestLocation: Location? = null
    private var deepLinkChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null
    private var pendingActiveHikeLiveStatus: ActiveHikeLiveStatus? = null
    private var qrScannerFactory: QrScannerPlatformViewFactory? = null
    private var hikerBleBridge: HikerBleBridge? = null

    private val sosTorchPattern = listOf(
        TorchStep(true, 220L),
        TorchStep(false, 180L),
        TorchStep(true, 220L),
        TorchStep(false, 180L),
        TorchStep(true, 220L),
        TorchStep(false, 420L),
        TorchStep(true, 650L),
        TorchStep(false, 220L),
        TorchStep(true, 650L),
        TorchStep(false, 220L),
        TorchStep(true, 650L),
        TorchStep(false, 420L),
        TorchStep(true, 220L),
        TorchStep(false, 180L),
        TorchStep(true, 220L),
        TorchStep(false, 180L),
        TorchStep(true, 220L),
        TorchStep(false, 1400L),
    )

    private val torchPatternRunnable = object : Runnable {
        override fun run() {
            if (!isTorchPatternActive) {
                return
            }

            val cameraId = torchCameraId ?: findTorchCameraId()
            if (cameraId == null) {
                stopTorchPattern()
                return
            }

            torchCameraId = cameraId
            val step = sosTorchPattern[torchPatternIndex]
            setTorch(cameraId, step.enabled)
            torchPatternIndex = (torchPatternIndex + 1) % sosTorchPattern.size
            mainHandler.postDelayed(this, step.durationMillis)
        }
    }

    private val locationTimeoutRunnable = Runnable {
        completePendingLocation(
            pendingBestLocation ?: lastKnownLocationFallback()
        )
    }

    // configureFlutterEngine: Register platform channels and attach lifecycle-aware native bridges.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MobileSecurityBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        cameraManager = getSystemService(CameraManager::class.java)
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        pendingDeepLink = intent?.dataString
        val qrFactory = QrScannerPlatformViewFactory(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        qrScannerFactory = qrFactory
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("hiker_circle/qr_scanner", qrFactory)
        hikerBleBridge = HikerBleBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startManualSosPattern" -> {
                        try {
                            startManualSosPattern(
                                call.argument<String>("alarmAsset") ?: ALARM_ASSET,
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "sos_device_alert_start_failed",
                                error.message,
                                null,
                            )
                        }
                    }
                    "stopManualSosPattern" -> {
                        stopManualSosPattern()
                        result.success(null)
                    }
                    "startSirenOnly" -> {
                        try {
                            startSirenOnly(
                                call.argument<String>("alarmAsset") ?: ALARM_ASSET,
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "sos_device_alert_start_failed",
                                error.message,
                                null,
                            )
                        }
                    }
                    "startFlashlightPattern" -> {
                        startTorchPattern()
                        result.success(null)
                    }
                    "stopFlashlightPattern" -> {
                        stopTorchPattern()
                        result.success(null)
                    }
                    "startFallStillnessCountdownVibration" -> {
                        startFallStillnessCountdownVibration()
                        result.success(null)
                    }
                    "stopFallStillnessCountdownVibration" -> {
                        stopFallStillnessCountdownVibration()
                        result.success(null)
                    }
                    "beginOutputVolumeMonitoring" -> {
                        result.success(null)
                    }
                    "endOutputVolumeMonitoring" -> {
                        result.success(null)
                    }
                    "speakFallStillnessPrompt" -> {
                        speakFallStillnessPrompt(
                            call.argument<String>("message")
                                ?: "Are you okay? Do you need help? Please respond by tapping the phone to cancel SOS.",
                        )
                        result.success(null)
                    }
                    "stopSpokenPrompt" -> {
                        stopSpokenPrompt()
                        result.success(null)
                    }
                    "speakHikePrecaution" -> {
                        val requestId = call.argument<String>("requestId")
                        val message = call.argument<String>("message")
                        if (requestId.isNullOrBlank() || message.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            speakHikePrecaution(requestId, message, result)
                        }
                    }
                    "stopHikePrecaution" -> {
                        val requestId = call.argument<String>("requestId")
                        if (!requestId.isNullOrBlank() && requestId == hikeSpeechRequestId) {
                            pendingSpeechMessage = null
                            completeHikeSpeech(false)
                            textToSpeech?.stop()
                        }
                        result.success(null)
                    }
                    "getBatteryLevel" -> getBatteryLevel(result)
                    "getDeviceContacts" -> getDeviceContacts(result)
                    "getOutputVolumeStatus" -> getOutputVolumeStatus(call, result)
                    "getCurrentTriggerLocation" -> getCurrentTriggerLocation(call, result)
                    "shareText" -> shareText(call, result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hiker_circle/home_widgets")
            .setMethodCallHandler { call, result ->
                if (call.method != "update") {
                    result.notImplemented()
                } else {
                    try {
                        HikeHomeWidgetProvider.publish(this, call.arguments as String)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("invalid_widget_snapshot", error.message, null)
                    }
                }
            }

        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeInitialDeepLink" -> {
                        result.success(pendingDeepLink)
                        pendingDeepLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACTIVE_HIKE_LIVE_STATUS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "remapNativeLocationSession" -> {
                    runCatching {
                        val oldSessionId = call.argument<String>("oldSessionId").orEmpty()
                        val newSessionId = call.argument<String>("newSessionId").orEmpty()
                        val owner = FirebaseAuth.getInstance().currentUser?.uid.orEmpty()
                        val count = nativeLocationSamples.remapSession(oldSessionId, newSessionId, owner)
                        HikeSafetyMonitorService.remapSession(this, oldSessionId, newSessionId, owner)
                        count
                    }.onSuccess(result::success).onFailure {
                        result.error("native_location_buffer_remap_failed", it.message, null)
                    }
                }
                "getNativeLocationBufferSessions" -> {
                    runCatching { nativeLocationSamples.pendingSessions(FirebaseAuth.getInstance().currentUser?.uid.orEmpty()) }
                        .onSuccess(result::success).onFailure {
                            result.error("native_location_buffer_read_failed", it.message, null)
                        }
                }
                "getPendingNativeLocationSamples" -> {
                    runCatching {
                        nativeLocationSamples.pending(
                            call.argument<String>("sessionId").orEmpty(),
                            FirebaseAuth.getInstance().currentUser?.uid.orEmpty(),
                            call.argument<Number>("limit")?.toInt() ?: 500,
                        )
                    }.onSuccess(result::success).onFailure {
                        result.error("native_location_buffer_read_failed", it.message, null)
                    }
                }
                "acknowledgeNativeLocationSamples", "acknowledgeNativeCloudLocationSamples" -> {
                    runCatching {
                        nativeLocationSamples.acknowledge(
                            call.argument<String>("sessionId").orEmpty(),
                            FirebaseAuth.getInstance().currentUser?.uid.orEmpty(),
                            call.argument<List<String>>("sampleIds") ?: emptyList(),
                            cloud = call.method == "acknowledgeNativeCloudLocationSamples",
                        )
                    }.onSuccess(result::success).onFailure {
                        result.error("native_location_buffer_ack_failed", it.message, null)
                    }
                }
                "markNativeLocationSamplesCloudAcknowledged" -> {
                    runCatching {
                        val sessionId = call.argument<String>("sessionId").orEmpty()
                        nativeLocationSamples.acknowledge(
                            sessionId, FirebaseAuth.getInstance().currentUser?.uid.orEmpty(),
                            (call.argument<List<Number>>("sampledAtMillis") ?: emptyList()).map { "$sessionId:${it.toLong()}" },
                            cloud = true,
                        )
                    }.onSuccess(result::success).onFailure {
                        result.error("native_location_buffer_ack_failed", it.message, null)
                    }
                }
                "startOrUpdateActiveHikeLiveStatus" -> {
                    val status = ActiveHikeLiveStatus.from(call.arguments)
                    if (status == null) {
                        result.error(
                            "active_hike_live_status_invalid",
                            "Active hike status payload is invalid.",
                            null,
                        )
                    } else {
                        startOrUpdateActiveHikeLiveStatus(status)
                        runCatching {
                            HikeSafetyMonitorService.startOrUpdate(
                                this,
                                HikeSafetyMonitorService.SafetyConfig(
                                    sessionId = status.sessionId,
                                    trailName = status.trailName,
                                    longestRestMillis = status.longestRestMillis,
                                    responseMillis = status.fallResponseMillis,
                                    sensitivity = status.sensorSensitivity,
                                    fallDetectionEnabled =
                                        status.fallDetectionEnabled,
                                    ownerUid = call.argument<String>("ownerUid").orEmpty(),
                                    locationUploadIntervalMillis = call.argument<Number>("locationUploadIntervalMillis")?.toLong() ?: 60_000L,
                                ),
                            )
                        }.onFailure {
                            result.error("native_location_monitor_start_failed", it.message, null)
                            return@setMethodCallHandler
                        }
                        result.success(null)
                    }
                }
                "stopActiveHikeLiveStatus" -> {
                    stopActiveHikeLiveStatus()
                    HikeSafetyMonitorService.stop(this)
                    result.success(null)
                }
                "consumePendingSafetyEvent" -> {
                    result.success(HikeSafetyMonitorService.pendingEvent(this))
                }
                "acknowledgeSafetyEvent" -> {
                    val eventId = call.argument<String>("eventId").orEmpty()
                    if (eventId.isNotBlank()) {
                        HikeSafetyMonitorService.acknowledgeEvent(this, eventId)
                    }
                    result.success(null)
                }
                "cancelNativeSafetyAlert" -> {
                    startService(
                        Intent(this, HikeSafetyMonitorService::class.java).apply {
                            action = HikeSafetyMonitorService.ACTION_CANCEL_ALERT
                        },
                    )
                    result.success(null)
                }
                "getNativeSafetyStatus" -> {
                    val backgroundLocationGranted =
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                            checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                            PackageManager.PERMISSION_GRANTED
                    val fullScreenIntentGranted =
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                            getSystemService(NotificationManager::class.java)
                                .canUseFullScreenIntent()
                    val overlayGranted = android.provider.Settings.canDrawOverlays(this)
                    result.success(
                        mapOf(
                            "configured" to HikeSafetyMonitorService.isConfigured(this),
                            "backgroundLocationGranted" to backgroundLocationGranted,
                            "fineLocationGranted" to hasFineLocationPermission(),
                            "fullScreenIntentGranted" to fullScreenIntentGranted,
                            "overlayGranted" to overlayGranted,
                        ),
                    )
                }
                "openBackgroundLocationSettings" -> {
                    startActivity(
                        Intent(
                            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startActivity(
                            Intent(
                                android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    }
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // onNewIntent: Forward widget and notification deep links to the existing Flutter activity.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val deepLink = intent.dataString ?: return
        pendingDeepLink = deepLink
        deepLinkChannel?.invokeMethod("onDeepLink", deepLink)
    }

    override fun onResume() {
        super.onResume()
        HikeSafetyMonitorService.flutterUiForeground = true
        hikerBleBridge?.onActivityResumed()
    }

    override fun onPause() {
        HikeSafetyMonitorService.flutterUiForeground = false
        hikerBleBridge?.onActivityPaused()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CONTACTS_REQUEST_CODE) {
            val result = pendingContactsResult
            pendingContactsResult = null
            if (result != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    readDeviceContacts(result)
                } else {
                    result.error("contacts_permission_denied", "Allow Contacts access in Settings to import a phone contact.", null)
                }
            }
            return
        }
        if (requestCode == POST_NOTIFICATIONS_REQUEST_CODE) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                pendingActiveHikeLiveStatus?.let { status ->
                    postActiveHikeNotification(status)
                }
            }
            pendingActiveHikeLiveStatus = null
            return
        }

        if (hikerBleBridge?.onRequestPermissionsResult(
                requestCode,
                permissions,
                grantResults,
            ) == true
        ) {
            return
        }

        if (requestCode == LOCATION_REQUEST_CODE && pendingLocationResult != null) {
            if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
                requestOneShotLocation()
            } else {
                completePendingLocation(null)
            }
            return
        }

        if (requestCode == QR_SCANNER_CAMERA_REQUEST_CODE) {
            qrScannerFactory?.onCameraPermissionResult(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            return
        }

        if (requestCode != CAMERA_REQUEST_CODE || !pendingTorchStart) {
            return
        }

        pendingTorchStart = false
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startTorchPattern()
        }
    }

    // onDestroy: Dispose activity-owned resources while the safety service keeps its own outputs.
    override fun onDestroy() {
        // Do not cancel the system vibrator here. The native hike-safety
        // foreground service may own an urgent response prompt after Flutter
        // is reclaimed or the activity is destroyed.
        stopSpokenPrompt()
        textToSpeech?.shutdown()
        textToSpeech = null
        stopManualSosPattern()
        hikerBleBridge?.dispose()
        hikerBleBridge = null
        completePendingLocation(null)
        pendingContactsResult?.error("contacts_request_cancelled", "The Contacts request was closed.", null)
        pendingContactsResult = null
        super.onDestroy()
    }

    private fun startManualSosPattern(alarmAsset: String = ALARM_ASSET) {
        startAlarm(normalizedAlarmAsset(alarmAsset))
        startTorchPattern()
    }

    private fun startSirenOnly(alarmAsset: String = ALARM_ASSET) {
        stopTorchPattern()
        startAlarm(normalizedAlarmAsset(alarmAsset))
    }

    private fun stopManualSosPattern() {
        stopAlarm()
        stopTorchPattern()
        stopFallStillnessCountdownVibration()
    }

    @Suppress("DEPRECATION")
    private fun startFallStillnessCountdownVibration() {
        val vibrator = currentVibrator() ?: return
        stopFallStillnessCountdownVibration()
        val pattern = longArrayOf(0L, 420L, 520L)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            vibrator.vibrate(pattern, 0)
        }
    }

    @Suppress("DEPRECATION")
    private fun stopFallStillnessCountdownVibration() {
        currentVibrator()?.cancel()
    }

    private fun currentVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun startOrUpdateActiveHikeLiveStatus(status: ActiveHikeLiveStatus) {
        if (!canPostNotifications()) {
            pendingActiveHikeLiveStatus = status
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    POST_NOTIFICATIONS_REQUEST_CODE,
                )
            }
            return
        }

        postActiveHikeNotification(status)
    }

    private fun stopActiveHikeLiveStatus() {
        pendingActiveHikeLiveStatus = null
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.cancel(ACTIVE_HIKE_NOTIFICATION_ID)
    }

    private fun canPostNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun postActiveHikeNotification(status: ActiveHikeLiveStatus) {
        val notificationManager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ACTIVE_HIKE_NOTIFICATION_CHANNEL_ID,
                "Active hike",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Live hike progress and quick actions"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ACTIVE_HIKE_NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setContentTitle("Hiking ${status.trailName}")
            .setContentText(status.summary)
            .setSubText("HikerCircle")
            .setContentIntent(
                pendingActivityIntent(activeHikeDeepLink("active", status.sessionId)),
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(status.startedAtMillis)
            .setUsesChronometer(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .addLiveStatusAction(
                icon = android.R.drawable.ic_menu_view,
                title = "View details",
                pendingIntent = pendingActivityIntent(
                    activeHikeDeepLink("active", status.sessionId),
                    6101,
                ),
            )
            .build()

        notificationManager.notify(ACTIVE_HIKE_NOTIFICATION_ID, notification)
    }

    private fun activeHikeDeepLink(path: String, sessionId: String): String {
        return Uri.Builder()
            .scheme("hikercircle")
            .authority("hike")
            .appendPath(path)
            .appendQueryParameter("source", "android_live_status")
            .appendQueryParameter("sessionId", sessionId)
            .build()
            .toString()
    }

    private fun pendingActivityIntent(
        uri: String,
        requestCode: Int = 6100,
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse(uri)
            setPackage(packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }

        return PendingIntent.getActivity(this, requestCode, intent, flags)
    }

    @Suppress("DEPRECATION")
    private fun Notification.Builder.addLiveStatusAction(
        icon: Int,
        title: String,
        pendingIntent: PendingIntent,
    ): Notification.Builder {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            addAction(
                Notification.Action.Builder(icon, title, pendingIntent).build(),
            )
        } else {
            addAction(icon, title, pendingIntent)
        }
        return this
    }

    private fun getBatteryLevel(result: MethodChannel.Result) {
        val batteryManager = getSystemService(BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        result.success(level.coerceIn(0, 100))
    }

    private fun getOutputVolumeStatus(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val requestedMinimum = call.argument<Double>("minimumRequiredVolume") ?: 0.2
        val minimumRequiredVolume = requestedMinimum.coerceIn(0.0, 1.0)
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager
            .getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            .coerceAtLeast(1)
        val outputVolume =
            audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / maxVolume

        result.success(
            mapOf(
                "platform" to "android",
                "isIos" to false,
                "canMeasureOutputVolume" to true,
                "outputVolume" to outputVolume,
                "minimumRequiredVolume" to minimumRequiredVolume,
                "isAudible" to true,
            ),
        )
    }

    private fun startAlarm(alarmAsset: String) {
        if (mediaPlayer?.isPlaying == true && activeAlarmAsset == alarmAsset) {
            return
        }
        stopAlarm()

        val alarmFile = copyFlutterAlarmAssetToCache(alarmAsset)
        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            isLooping = true
            setDataSource(alarmFile.absolutePath)
            prepare()
            start()
        }
        activeAlarmAsset = alarmAsset
    }

    private fun stopAlarm() {
        mediaPlayer?.let { player ->
            runCatching {
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            }
        }
        mediaPlayer = null
        activeAlarmAsset = null
    }

    private fun speakFallStillnessPrompt(message: String) {
        completeHikeSpeech(false)
        textToSpeech?.stop()
        safetySpeechRequestId = "fall_stillness_prompt_${++speechSequence}"
        queueSpeech(message)
    }

    private fun speakHikePrecaution(requestId: String, message: String, result: MethodChannel.Result) {
        // A routine forecast must never flush an urgent safety prompt.
        if (hikeSpeechResult != null || safetySpeechRequestId != null ||
            pendingSpeechMessage != null || textToSpeech?.isSpeaking == true) {
            result.success(false)
            return
        }
        hikeSpeechRequestId = requestId
        hikeSpeechResult = result
        queueSpeech(message)
    }

    private fun queueSpeech(message: String) {
        val currentSpeaker = textToSpeech
        if (currentSpeaker != null && speechReady) {
            speakWith(currentSpeaker, message)
            return
        }

        pendingSpeechMessage = message
        if (currentSpeaker != null) return
        textToSpeech = TextToSpeech(this) { status ->
            mainHandler.post {
                val speaker = textToSpeech ?: return@post
                if (status == TextToSpeech.SUCCESS) {
                    speechReady = true
                    speaker.language = Locale.getDefault()
                    speaker.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) = Unit
                        override fun onDone(utteranceId: String?) {
                            mainHandler.post {
                                if (utteranceId == safetySpeechRequestId) safetySpeechRequestId = null
                                if (utteranceId == hikeSpeechRequestId) completeHikeSpeech(true)
                            }
                        }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            mainHandler.post {
                                if (utteranceId == safetySpeechRequestId) safetySpeechRequestId = null
                                if (utteranceId == hikeSpeechRequestId) completeHikeSpeech(false)
                            }
                        }
                        override fun onStop(utteranceId: String?, interrupted: Boolean) {
                            mainHandler.post {
                                if (utteranceId == safetySpeechRequestId) safetySpeechRequestId = null
                                if (utteranceId == hikeSpeechRequestId) completeHikeSpeech(false)
                            }
                        }
                    })
                    val pending = pendingSpeechMessage
                    pendingSpeechMessage = null
                    if (pending != null) speakWith(speaker, pending)
                } else {
                    pendingSpeechMessage = null
                    safetySpeechRequestId = null
                    completeHikeSpeech(false)
                    textToSpeech?.shutdown()
                    textToSpeech = null
                    speechReady = false
                }
            }
        }
    }

    private fun speakWith(speaker: TextToSpeech, message: String) {
        val utteranceId = hikeSpeechRequestId ?: safetySpeechRequestId ?: "fall_stillness_prompt"
        if (speaker.speak(message, TextToSpeech.QUEUE_FLUSH, null, utteranceId) == TextToSpeech.ERROR) {
            safetySpeechRequestId = null
            completeHikeSpeech(false)
        }
    }

    private fun completeHikeSpeech(finished: Boolean) {
        val result = hikeSpeechResult
        hikeSpeechResult = null
        hikeSpeechRequestId = null
        result?.success(finished)
    }

    private fun stopSpokenPrompt() {
        pendingSpeechMessage = null
        safetySpeechRequestId = null
        completeHikeSpeech(false)
        textToSpeech?.stop()
    }

    private fun copyFlutterAlarmAssetToCache(alarmAsset: String): File {
        val alarmFile = File(cacheDir, alarmAsset.substringAfterLast('/'))
        if (alarmFile.exists() && alarmFile.length() > 0L) {
            return alarmFile
        }

        val assetKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(alarmAsset)

        assets.open(assetKey).use { input ->
            FileOutputStream(alarmFile).use { output ->
                input.copyTo(output)
            }
        }

        return alarmFile
    }

    private fun normalizedAlarmAsset(alarmAsset: String): String {
        return when (alarmAsset) {
            MEDICAL_ALARM_ASSET -> MEDICAL_ALARM_ASSET
            else -> ALARM_ASSET
        }
    }

    private fun startTorchPattern() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

        if (checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingTorchStart = true
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST_CODE)
            return
        }

        torchCameraId = findTorchCameraId()
        if (torchCameraId == null || isTorchPatternActive) {
            return
        }

        isTorchPatternActive = true
        torchPatternIndex = 0
        mainHandler.removeCallbacks(torchPatternRunnable)
        mainHandler.post(torchPatternRunnable)
    }

    private fun stopTorchPattern() {
        isTorchPatternActive = false
        pendingTorchStart = false
        mainHandler.removeCallbacks(torchPatternRunnable)
        torchCameraId?.let { cameraId -> setTorch(cameraId, false) }
    }

    private fun findTorchCameraId(): String? {
        val manager = cameraManager ?: return null
        return manager.cameraIdList.firstOrNull { cameraId ->
            val characteristics = manager.getCameraCharacteristics(cameraId)
            val hasFlash =
                characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            val lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING)
            hasFlash && lensFacing == CameraCharacteristics.LENS_FACING_BACK
        }
    }

    private fun setTorch(cameraId: String, enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

        runCatching {
            cameraManager?.setTorchMode(cameraId, enabled)
        }
    }

    private fun getDeviceContacts(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            readDeviceContacts(result)
            return
        }
        if (pendingContactsResult != null) {
            result.error("contacts_request_in_progress", "A Contacts permission request is already open.", null)
            return
        }
        pendingContactsResult = result
        requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), CONTACTS_REQUEST_CODE)
    }

    private fun readDeviceContacts(result: MethodChannel.Result) {
        Thread {
            val loaded = runCatching {
                val contacts = linkedMapOf<String, Pair<String, MutableSet<String>>>()
                contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER),
                    null, null, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " COLLATE LOCALIZED ASC",
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val id = cursor.getString(0)
                        val name = cursor.getString(1).orEmpty().trim()
                        val number = cursor.getString(2).orEmpty().trim()
                        if (name.isNotEmpty() && number.isNotEmpty()) {
                            contacts.getOrPut(id) { name to linkedSetOf() }.second.add(number)
                        }
                    }
                }
                contacts.map { (id, value) ->
                    mapOf("id" to id, "fullName" to value.first, "phoneNumbers" to value.second.toList())
                }
            }
            runOnUiThread {
                loaded.onSuccess(result::success).onFailure {
                    result.error("contacts_read_failed", it.message ?: "Unable to load phone contacts.", null)
                }
            }
        }.start()
    }

    // getCurrentTriggerLocation: Resolve a fresh SOS location with a bounded last-known fallback.
    private fun getCurrentTriggerLocation(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        if (pendingLocationResult != null) {
            result.error(
                "location_request_in_progress",
                "A trigger location request is already in progress.",
                null,
            )
            return
        }

        pendingLocationResult = result
        pendingAllowLastKnownLocation = call.argument<Boolean>("allowLastKnown") == true
        pendingRequirePreciseLocation = call.argument<Boolean>("requirePrecise") == true
        pendingBestLocation = null
        if (!hasLocationPermission()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    ),
                    LOCATION_REQUEST_CODE,
                )
            } else {
                completePendingLocation(lastKnownLocationFallback())
            }
            return
        }

        requestOneShotLocation()
    }

    // shareText: Open Android's share sheet with the prepared hike text.
    private fun shareText(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.error("share_text_missing", "Share text is missing.", null)
            return
        }

        val subject = call.argument<String>("subject") ?: "HikerCircle"
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(sendIntent, subject)
        runCatching {
            startActivity(chooser)
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("share_text_failed", error.message, null)
        }
    }

    @Suppress("MissingPermission")
    private fun requestOneShotLocation() {
        val manager = locationManager ?: run {
            completePendingLocation(lastKnownLocationFallback())
            return
        }
        val providers = locationProviders(manager)
        if (providers.isEmpty()) {
            completePendingLocation(lastKnownLocationFallback())
            return
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val currentBest = pendingBestLocation
                if (currentBest == null ||
                    (!currentBest.hasAccuracy() && location.hasAccuracy()) ||
                    (currentBest.hasAccuracy() && location.hasAccuracy() &&
                        location.accuracy < currentBest.accuracy)
                ) {
                    pendingBestLocation = location
                }
                val isPreciseFix = hasFineLocationPermission() &&
                    location.hasAccuracy() && location.accuracy <= 25f
                if (!pendingRequirePreciseLocation || isPreciseFix) {
                    completePendingLocation(location)
                }
            }
        }

        pendingLocationListener = listener
        mainHandler.removeCallbacks(locationTimeoutRunnable)
        mainHandler.postDelayed(locationTimeoutRunnable, LOCATION_TIMEOUT_MILLIS)

        val registered = providers.count { provider ->
            runCatching {
                // Request network and GPS concurrently. Selecting GPS alone
                // caused every indoor request to time out even when a fresh
                // network position was available.
                manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            }.isSuccess
        }
        if (registered == 0) {
            completePendingLocation(lastKnownLocationFallback())
        }
    }

    private fun completePendingLocation(location: Location?) {
        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        mainHandler.removeCallbacks(locationTimeoutRunnable)
        pendingLocationListener?.let { listener ->
            runCatching {
                locationManager?.removeUpdates(listener)
            }
        }
        pendingLocationListener = null
        pendingAllowLastKnownLocation = false
        pendingRequirePreciseLocation = false
        pendingBestLocation = null

        result.success(location?.toFlutterMap())
    }

    private fun locationProviders(manager: LocationManager): List<String> {
        val providers = if (hasFineLocationPermission()) {
            listOf(
                LocationManager.NETWORK_PROVIDER,
                LocationManager.GPS_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )
        } else {
            listOf(
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )
        }

        return providers.filter { provider ->
            runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false)
        }
    }

    private fun hasLocationPermission(): Boolean {
        return hasFineLocationPermission() || hasCoarseLocationPermission()
    }

    private fun hasFineLocationPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasCoarseLocationPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    @Suppress("MissingPermission")
    private fun lastKnownLocationFallback(): Location? {
        if (!pendingAllowLastKnownLocation || !hasLocationPermission()) {
            return null
        }

        val manager = locationManager ?: return null
        val providers = if (hasFineLocationPermission()) {
            listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )
        } else {
            listOf(
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )
        }

        return providers
            .mapNotNull { provider ->
                runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
            }
            .maxByOrNull { location -> location.time }
    }

    private fun Location.toFlutterMap(): Map<String, Any> {
        val data = mutableMapOf<String, Any>(
            "latitude" to latitude,
            "longitude" to longitude,
            "capturedAtMillis" to time,
        )

        if (hasAccuracy()) {
            data["accuracyMeters"] = accuracy.toDouble()
        }

        return data
    }

    private data class TorchStep(
        val enabled: Boolean,
        val durationMillis: Long,
    )

    private data class ActiveHikeLiveStatus(
        val sessionId: String,
        val trailName: String,
        val startedAtMillis: Long,
        val expectedReturnAtMillis: Long,
        val checkIns: Int,
        val routePointCount: Int,
        val manualPins: Int,
        val queuedUpdates: Int,
        val batteryLevel: Int,
        val fallDetectionEnabled: Boolean,
        val shareLiveLocation: Boolean,
        val sensorSensitivity: Double,
        val fallResponseMillis: Long,
        val longestRestMillis: Long,
    ) {
        val summary: String
            get() = "GPS $routePointCount | Pins $manualPins | $queuedUpdates queued"

        companion object {
            fun from(arguments: Any?): ActiveHikeLiveStatus? {
                val data = arguments as? Map<*, *> ?: return null
                return ActiveHikeLiveStatus(
                    sessionId = data["sessionId"] as? String ?: return null,
                    trailName = data["trailName"] as? String ?: "Active hike",
                    startedAtMillis = (data["startedAtMillis"] as? Number)?.toLong()
                        ?: return null,
                    expectedReturnAtMillis = (data["expectedReturnAtMillis"] as? Number)
                        ?.toLong() ?: 0L,
                    checkIns = (data["checkIns"] as? Number)?.toInt() ?: 0,
                    routePointCount = (data["routePointCount"] as? Number)?.toInt() ?: 0,
                    manualPins = (data["manualPins"] as? Number)?.toInt() ?: 0,
                    queuedUpdates = (data["queuedUpdates"] as? Number)?.toInt() ?: 0,
                    batteryLevel = (data["batteryLevel"] as? Number)?.toInt() ?: 0,
                    fallDetectionEnabled = data["fallDetectionEnabled"] as? Boolean
                        ?: true,
                    shareLiveLocation = data["shareLiveLocation"] as? Boolean
                        ?: false,
                    sensorSensitivity = (data["sensorSensitivity"] as? Number)
                        ?.toDouble()?.coerceIn(1.0, 10.0) ?: 5.0,
                    fallResponseMillis = (data["fallResponseMillis"] as? Number)
                        ?.toLong()?.coerceIn(5_000L, 600_000L) ?: 30_000L,
                    longestRestMillis = (data["longestRestMillis"] as? Number)
                        ?.toLong()?.coerceIn(30_000L, 86_400_000L) ?: 180_000L,
                )
            }
        }
    }
}
