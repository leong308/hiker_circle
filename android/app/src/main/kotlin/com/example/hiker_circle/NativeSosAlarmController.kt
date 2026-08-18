package com.leongziqi.hikercircle

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import io.flutter.FlutterInjector
import java.io.File
import java.io.FileOutputStream

/** Native alarm + SOS flashlight pattern that does not depend on an Activity. */
class NativeSosAlarmController(
    private val context: Context,
    private val handler: Handler,
) {
    companion object {
        private const val SOS_ALARM_ASSET = "assets/audios/sos_alarm.mp3"
    }

    private data class TorchStep(val enabled: Boolean, val durationMillis: Long)

    private val cameraManager = context.getSystemService(CameraManager::class.java)
    private var mediaPlayer: MediaPlayer? = null
    private var torchCameraId: String? = null
    private var torchStepIndex = 0
    private var torchRunning = false
    private val torchPattern = listOf(
        TorchStep(true, 220L), TorchStep(false, 180L),
        TorchStep(true, 220L), TorchStep(false, 180L),
        TorchStep(true, 220L), TorchStep(false, 420L),
        TorchStep(true, 650L), TorchStep(false, 220L),
        TorchStep(true, 650L), TorchStep(false, 220L),
        TorchStep(true, 650L), TorchStep(false, 420L),
        TorchStep(true, 220L), TorchStep(false, 180L),
        TorchStep(true, 220L), TorchStep(false, 180L),
        TorchStep(true, 220L), TorchStep(false, 1_400L),
    )

    private val torchRunnable = object : Runnable {
        override fun run() {
            if (!torchRunning) return
            val cameraId = torchCameraId ?: findTorchCameraId()
            if (cameraId == null) {
                stopTorch()
                return
            }
            torchCameraId = cameraId
            val step = torchPattern[torchStepIndex]
            runCatching { cameraManager.setTorchMode(cameraId, step.enabled) }
            torchStepIndex = (torchStepIndex + 1) % torchPattern.size
            handler.postDelayed(this, step.durationMillis)
        }
    }

    fun start() {
        startAlarmSound()
        startTorch()
    }

    fun stop() {
        stopAlarmSound()
        stopTorch()
    }

    private fun startAlarmSound() {
        if (mediaPlayer?.isPlaying == true) return
        stopAlarmSound()
        runCatching {
            val alarmFile = copyAlarmAssetToCache()
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
        }.onFailure {
            stopAlarmSound()
        }
    }

    private fun stopAlarmSound() {
        mediaPlayer?.let { player ->
            runCatching {
                if (player.isPlaying) player.stop()
                player.release()
            }
        }
        mediaPlayer = null
    }

    private fun startTorch() {
        if (context.checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED || torchRunning
        ) {
            return
        }
        torchRunning = true
        torchStepIndex = 0
        handler.removeCallbacks(torchRunnable)
        handler.post(torchRunnable)
    }

    private fun stopTorch() {
        torchRunning = false
        handler.removeCallbacks(torchRunnable)
        torchCameraId?.let { cameraId ->
            runCatching { cameraManager.setTorchMode(cameraId, false) }
        }
        torchCameraId = null
        torchStepIndex = 0
    }

    private fun findTorchCameraId(): String? = runCatching {
        cameraManager.cameraIdList.firstOrNull { cameraId ->
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                characteristics.get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_BACK
        }
    }.getOrNull()

    private fun copyAlarmAssetToCache(): File {
        val alarmFile = File(context.cacheDir, "native_hike_sos_alarm.mp3")
        if (alarmFile.exists() && alarmFile.length() > 0L) return alarmFile
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context.applicationContext)
        loader.ensureInitializationComplete(context.applicationContext, null)
        val assetKey = loader.getLookupKeyForAsset(SOS_ALARM_ASSET)
        context.assets.open(assetKey).use { input ->
            FileOutputStream(alarmFile).use { output -> input.copyTo(output) }
        }
        return alarmFile
    }
}
