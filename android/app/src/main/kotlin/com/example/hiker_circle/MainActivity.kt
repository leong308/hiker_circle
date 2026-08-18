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
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "hiker_circle/sos_device_alerts"
        private const val DEEP_LINK_CHANNEL = "hiker_circle/deeplinks"
        private const val BUILD_CONFIG_CHANNEL = "hiker_circle/build_config"
        private const val ACTIVE_HIKE_LIVE_STATUS_CHANNEL =
            "hiker_circle/active_hike_live_status"
        private const val CAMERA_REQUEST_CODE = 8472
        const val QR_SCANNER_CAMERA_REQUEST_CODE = 8475
        private const val LOCATION_REQUEST_CODE = 8473
        private const val POST_NOTIFICATIONS_REQUEST_CODE = 8474
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
    private var cameraManager: CameraManager? = null
    private var torchCameraId: String? = null
    private var isTorchPatternActive = false
    private var pendingTorchStart = false
    private var torchPatternIndex = 0
    private var locationManager: LocationManager? = null
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingLocationListener: LocationListener? = null
    private var pendingAllowLastKnownLocation = false
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
        completePendingLocation(lastKnownLocationFallback())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    "getBatteryLevel" -> getBatteryLevel(result)
                    "getOutputVolumeStatus" -> getOutputVolumeStatus(call, result)
                    "getCurrentTriggerLocation" -> getCurrentTriggerLocation(call, result)
                    "shareText" -> shareText(call, result)
                    else -> result.notImplemented()
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
            BUILD_CONFIG_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDevelopmentOnlyRelease" ->
                    result.success(BuildConfig.DEVELOPMENT_ONLY_SIGNING)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACTIVE_HIKE_LIVE_STATUS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
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
                        if (status.fallDetectionEnabled) {
                            HikeSafetyMonitorService.startOrUpdate(
                                this,
                                HikeSafetyMonitorService.SafetyConfig(
                                    sessionId = status.sessionId,
                                    trailName = status.trailName,
                                    longestRestMillis = status.longestRestMillis,
                                    responseMillis = status.fallResponseMillis,
                                    sensitivity = status.sensorSensitivity,
                                ),
                            )
                        } else {
                            HikeSafetyMonitorService.stop(this)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val deepLink = intent.dataString ?: return
        pendingDeepLink = deepLink
        deepLinkChannel?.invokeMethod("onDeepLink", deepLink)
    }

    override fun onResume() {
        super.onResume()
        hikerBleBridge?.onActivityResumed()
    }

    override fun onPause() {
        hikerBleBridge?.onActivityPaused()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
            .addLiveStatusAction(
                icon = android.R.drawable.ic_menu_mylocation,
                title = "Check in",
                pendingIntent = pendingActivityIntent(
                    activeHikeDeepLink("check-in", status.sessionId),
                    6102,
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
        val currentSpeaker = textToSpeech
        if (currentSpeaker != null) {
            speakWith(currentSpeaker, message)
            return
        }

        pendingSpeechMessage = message
        textToSpeech = TextToSpeech(this) { status ->
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
            speaker.speak(message, TextToSpeech.QUEUE_FLUSH, null, "fall_stillness_prompt")
        } else {
            speaker.speak(message, TextToSpeech.QUEUE_FLUSH, null)
        }
    }

    private fun stopSpokenPrompt() {
        pendingSpeechMessage = null
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
                completePendingLocation(location)
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
        val manualPins: Int,
        val queuedUpdates: Int,
        val batteryLevel: Int,
        val fallDetectionEnabled: Boolean,
        val sensorSensitivity: Double,
        val fallResponseMillis: Long,
        val longestRestMillis: Long,
    ) {
        val summary: String
            get() = "Check-ins $checkIns | Pins $manualPins | $queuedUpdates queued"

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
                    manualPins = (data["manualPins"] as? Number)?.toInt() ?: 0,
                    queuedUpdates = (data["queuedUpdates"] as? Number)?.toInt() ?: 0,
                    batteryLevel = (data["batteryLevel"] as? Number)?.toInt() ?: 0,
                    fallDetectionEnabled = data["fallDetectionEnabled"] as? Boolean
                        ?: true,
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
