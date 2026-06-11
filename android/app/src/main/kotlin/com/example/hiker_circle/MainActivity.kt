package com.leongziqi.hikercircle

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "hiker_circle/sos_device_alerts"
        private const val CAMERA_REQUEST_CODE = 8472
        private const val LOCATION_REQUEST_CODE = 8473
        private const val LOCATION_TIMEOUT_MILLIS = 6000L
        private const val ALARM_ASSET = "assets/audios/sos_alarm.mp3"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var mediaPlayer: MediaPlayer? = null
    private var cameraManager: CameraManager? = null
    private var torchCameraId: String? = null
    private var isTorchPatternActive = false
    private var pendingTorchStart = false
    private var torchPatternIndex = 0
    private var locationManager: LocationManager? = null
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingLocationListener: LocationListener? = null
    private var pendingAllowLastKnownLocation = false

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startManualSosPattern" -> {
                        try {
                            startManualSosPattern()
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
                    "getCurrentTriggerLocation" -> getCurrentTriggerLocation(call, result)
                    "shareText" -> shareText(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_REQUEST_CODE || !pendingTorchStart) {
            if (requestCode == LOCATION_REQUEST_CODE && pendingLocationResult != null) {
                if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
                    requestOneShotLocation()
                } else {
                    completePendingLocation(null)
                }
            }
            return
        }

        pendingTorchStart = false
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startTorchPattern()
        }
    }

    override fun onDestroy() {
        stopManualSosPattern()
        completePendingLocation(null)
        super.onDestroy()
    }

    private fun startManualSosPattern() {
        startAlarm()
        startTorchPattern()
    }

    private fun stopManualSosPattern() {
        stopAlarm()
        stopTorchPattern()
    }

    private fun startAlarm() {
        if (mediaPlayer?.isPlaying == true) {
            return
        }

        val alarmFile = copyFlutterAlarmAssetToCache()
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
    }

    private fun copyFlutterAlarmAssetToCache(): File {
        val alarmFile = File(cacheDir, "sos_alarm.mp3")
        if (alarmFile.exists() && alarmFile.length() > 0L) {
            return alarmFile
        }

        val assetKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(ALARM_ASSET)

        assets.open(assetKey).use { input ->
            FileOutputStream(alarmFile).use { output ->
                input.copyTo(output)
            }
        }

        return alarmFile
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
        val provider = locationProvider(manager) ?: run {
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

        runCatching {
            manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        }.onFailure {
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

    private fun locationProvider(manager: LocationManager): String? {
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

        return providers.firstOrNull { provider ->
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
}
