// QrScannerPlatformView streams camera QR results and owns Android camera lifecycle cleanup.
package com.leongziqi.hikercircle

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.Button
import android.widget.LinearLayout
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
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
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun onCameraPermissionResult(granted: Boolean) {
        val views = synchronized(activeViews) { activeViews.toList() }
        views.forEach { view ->
            if (granted) view.start() else view.showCameraPermissionDenied()
        }
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
    private val retryButton = Button(activity)
    private val lifecycleOwner = activity as? LifecycleOwner
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val scanner: BarcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build(),
    )
    private var cameraProvider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var lastValue = ""
    private var lastValueAtMillis = 0L
    private var starting = false
    private var permissionRequested = false
    private var previewTimeout: Runnable? = null
    private var consecutiveFrameErrors = 0
    @Volatile private var generation = 0
    @Volatile private var disposed = false

    private val lifecycleObserver = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_RESUME -> start()
            Lifecycle.Event.ON_PAUSE -> {
                stopCamera()
                if (!disposed) statusText.text = "Camera paused. Return to continue scanning."
            }
            else -> Unit
        }
    }

    init {
        root.setBackgroundColor(Color.BLACK)
        // Flutter composes AndroidView into its own surface. TextureView avoids
        // a separate SurfaceView overlay that can leave this preview black.
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
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
        statusText.setPadding(24, 20, 24, 12)
        statusText.text = "Starting camera..."
        retryButton.visibility = View.GONE
        val statusPanel = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.argb(180, 0, 0, 0))
            addView(statusText, LinearLayout.LayoutParams(-1, -2))
            addView(retryButton, LinearLayout.LayoutParams(-2, -2))
        }
        root.addView(
            statusPanel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ),
        )
        root.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                start(requestPermission = !permissionRequested)
            }

            override fun onViewDetachedFromWindow(view: View) {
                stopCamera()
            }
        })
        lifecycleOwner?.let { owner ->
            owner.lifecycle.addObserver(lifecycleObserver)
            previewView.previewStreamState.observe(owner) { state ->
                if (!disposed && analysis != null && state == PreviewView.StreamState.STREAMING) {
                    showPreviewReady()
                }
            }
        }
    }

    override fun getView(): View = root

    fun start(requestPermission: Boolean = false) {
        if (disposed || !root.isAttachedToWindow || starting || analysis != null) return
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (requestPermission) {
                permissionRequested = true
                statusText.text = "Allow camera access to scan profile QR codes."
                retryButton.visibility = View.GONE
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.CAMERA),
                    MainActivity.QR_SCANNER_CAMERA_REQUEST_CODE,
                )
            } else {
                showCameraPermissionDenied()
            }
            return
        }

        val owner = lifecycleOwner
        if (owner == null) {
            showError("QR scanning is unavailable on this Android device.")
            return
        }
        if (!owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) return

        starting = true
        consecutiveFrameErrors = 0
        val attempt = ++generation
        statusText.text = "Starting camera..."
        retryButton.visibility = View.GONE
        try {
            val providerFuture = ProcessCameraProvider.getInstance(activity)
            providerFuture.addListener(
                {
                    if (disposed || generation != attempt || !root.isAttachedToWindow) return@addListener
                    try {
                        val provider = providerFuture.get()
                        cameraProvider = provider
                        bindCamera(provider, owner, attempt)
                    } catch (_: Exception) {
                        if (!disposed && generation == attempt) {
                            showError("Unable to start the camera. Close other camera apps and try again.")
                        }
                    }
                },
                ContextCompat.getMainExecutor(activity),
            )
        } catch (_: Exception) {
            showError("Unable to start the camera. Please try again.")
        }
    }

    fun showCameraPermissionDenied() {
        if (disposed) return
        stopCamera()
        statusText.text = "Camera permission is required to scan QR codes."
        retryButton.text = "Allow camera"
        retryButton.visibility = View.VISIBLE
        retryButton.setOnClickListener {
            if (permissionRequested && !ActivityCompat.shouldShowRequestPermissionRationale(
                    activity, Manifest.permission.CAMERA,
                )
            ) {
                activity.startActivity(Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", activity.packageName, null),
                ))
            } else {
                start(requestPermission = true)
            }
        }
    }

    private fun bindCamera(provider: ProcessCameraProvider, owner: LifecycleOwner, attempt: Int) {
        val cameraPreview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }
        val imageAnalysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { imageAnalysis ->
                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    analyzeImage(imageProxy, attempt)
                }
            }

        try {
            provider.bindToLifecycle(
                owner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                cameraPreview,
                imageAnalysis,
            )
            preview = cameraPreview
            analysis = imageAnalysis
            starting = false
            if (previewView.previewStreamState.value == PreviewView.StreamState.STREAMING) {
                showPreviewReady()
            } else {
                previewTimeout = Runnable {
                    if (!disposed && generation == attempt &&
                        previewView.previewStreamState.value != PreviewView.StreamState.STREAMING
                    ) showError("The camera preview did not start. Please try again.")
                }.also { root.postDelayed(it, 12_000L) }
            }
        } catch (error: Exception) {
            imageAnalysis.clearAnalyzer()
            provider.unbind(cameraPreview, imageAnalysis)
            throw error
        }
    }

    private fun showPreviewReady() {
        clearPreviewTimeout()
        statusText.text = "Point your camera at a HikerCircle profile QR."
        retryButton.visibility = View.GONE
    }

    private fun showError(message: String) {
        if (disposed) return
        stopCamera()
        statusText.text = message
        retryButton.text = "Retry camera"
        retryButton.visibility = View.VISIBLE
        retryButton.setOnClickListener {
            stopCamera()
            start(requestPermission = true)
        }
    }

    private fun analyzeImage(imageProxy: ImageProxy, attempt: Int) {
        if (disposed || generation != attempt) {
            imageProxy.close()
            return
        }
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        try {
            val image = InputImage.fromMediaImage(
                mediaImage,
                imageProxy.imageInfo.rotationDegrees,
            )
            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    if (disposed || generation != attempt) return@addOnSuccessListener
                    consecutiveFrameErrors = 0
                    val rawValue = barcodes.firstNotNullOfOrNull { it.rawValue }
                    if (!rawValue.isNullOrBlank()) emitIfNew(rawValue, attempt)
                }
                .addOnFailureListener {
                    if (!disposed && generation == attempt && ++consecutiveFrameErrors >= 3) {
                        showError("Unable to read camera frames. Please try again.")
                    }
                }
                .addOnCompleteListener { imageProxy.close() }
        } catch (_: Exception) {
            imageProxy.close()
            activity.runOnUiThread {
                if (!disposed && generation == attempt) {
                    showError("Unable to read camera frames. Please try again.")
                }
            }
        }
    }

    private fun emitIfNew(rawValue: String, attempt: Int) {
        val now = SystemClock.elapsedRealtime()
        if (rawValue == lastValue && now - lastValueAtMillis < 2500L) {
            return
        }
        lastValue = rawValue
        lastValueAtMillis = now
        activity.runOnUiThread {
            if (!disposed && generation == attempt) emitQrValue(rawValue)
        }
    }

    private fun clearPreviewTimeout() {
        previewTimeout?.let { root.removeCallbacks(it) }
        previewTimeout = null
    }

    private fun stopCamera() {
        generation++
        starting = false
        clearPreviewTimeout()
        analysis?.clearAnalyzer()
        val ownedUseCases = listOfNotNull(preview, analysis)
        if (ownedUseCases.isNotEmpty()) cameraProvider?.unbind(*ownedUseCases.toTypedArray())
        preview = null
        analysis = null
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        onDispose(this)
        lifecycleOwner?.let { owner ->
            owner.lifecycle.removeObserver(lifecycleObserver)
            previewView.previewStreamState.removeObservers(owner)
        }
        stopCamera()
        scanner.close()
        cameraExecutor.shutdown()
    }
}
