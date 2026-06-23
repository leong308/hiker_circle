package com.leongziqi.hikercircle

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.Collections
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class QrScannerPlatformViewFactory(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE), EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val activeViews = Collections.synchronizedSet(mutableSetOf<QrScannerPlatformView>())

    init {
        EventChannel(messenger, "hiker_circle/qr_scanner_events").setStreamHandler(this)
    }

    override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView {
        return QrScannerPlatformView(
            activity = activity,
            emitQrValue = { value -> eventSink?.success(value) },
            onDispose = { view -> activeViews.remove(view) },
        ).also { view ->
            activeViews.add(view)
            view.start()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun onCameraPermissionResult(granted: Boolean) {
        if (!granted) {
            activeViews.forEach { it.showCameraPermissionDenied() }
            return
        }
        activeViews.forEach { it.start() }
    }
}

class QrScannerPlatformView(
    private val activity: Activity,
    private val emitQrValue: (String) -> Unit,
    private val onDispose: (QrScannerPlatformView) -> Unit,
) : PlatformView {
    private val root = FrameLayout(activity)
    private val previewView = PreviewView(activity)
    private val statusText = TextView(activity)
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val scanner: BarcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build(),
    )
    private var cameraProvider: ProcessCameraProvider? = null
    private var lastValue = ""
    private var lastValueAtMillis = 0L
    private var disposed = false

    init {
        root.setBackgroundColor(Color.BLACK)
        root.addView(
            previewView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        statusText.setTextColor(Color.WHITE)
        statusText.gravity = Gravity.CENTER
        statusText.textSize = 15f
        statusText.setBackgroundColor(Color.argb(120, 0, 0, 0))
        root.addView(
            statusText,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ),
        )
    }

    override fun getView(): View = root

    fun start() {
        if (disposed) return
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            statusText.text = "Allow camera access to scan profile QR codes."
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                MainActivity.QR_SCANNER_CAMERA_REQUEST_CODE,
            )
            return
        }

        val lifecycleOwner = activity as? LifecycleOwner
        if (lifecycleOwner == null) {
            statusText.text = "QR scanner is unavailable on this Android device."
            return
        }

        statusText.text = "Point your camera at a HikerCircle profile QR."
        val providerFuture = ProcessCameraProvider.getInstance(activity)
        providerFuture.addListener(
            {
                if (disposed) return@addListener
                val provider = providerFuture.get()
                cameraProvider = provider
                bindCamera(provider, lifecycleOwner)
            },
            ContextCompat.getMainExecutor(activity),
        )
    }

    fun showCameraPermissionDenied() {
        statusText.text = "Camera permission is required to scan QR codes."
    }

    private fun bindCamera(provider: ProcessCameraProvider, lifecycleOwner: LifecycleOwner) {
        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { imageAnalysis ->
                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    analyzeImage(imageProxy)
                }
            }

        try {
            provider.unbindAll()
            provider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                analysis,
            )
        } catch (error: Exception) {
            statusText.text = "Unable to start the Android QR scanner."
        }
    }

    private fun analyzeImage(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val image = InputImage.fromMediaImage(
            mediaImage,
            imageProxy.imageInfo.rotationDegrees,
        )
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                val rawValue = barcodes.firstNotNullOfOrNull { it.rawValue }
                if (!rawValue.isNullOrBlank()) {
                    emitIfNew(rawValue)
                }
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }

    private fun emitIfNew(rawValue: String) {
        val now = System.currentTimeMillis()
        if (rawValue == lastValue && now - lastValueAtMillis < 2500L) {
            return
        }
        lastValue = rawValue
        lastValueAtMillis = now
        activity.runOnUiThread {
            emitQrValue(rawValue)
        }
    }

    override fun dispose() {
        disposed = true
        onDispose(this)
        cameraProvider?.unbindAll()
        scanner.close()
        cameraExecutor.shutdown()
    }
}
