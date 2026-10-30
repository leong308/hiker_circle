// SafetyAlertActivity shows the native fall/stillness response prompt above the lock screen.
package com.leongziqi.hikercircle

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.window.OnBackInvokedDispatcher
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.max

/** Full-screen, lock-screen-visible response surface for native hike alerts. */
class SafetyAlertActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var titleView: TextView
    private lateinit var modeView: TextView
    private lateinit var bodyView: TextView
    private lateinit var footerView: TextView
    private lateinit var countdownStopButton: Button
    private lateinit var stopSlider: SosStopSlider
    private var stoppingAlert = false
    private val eventChanges = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "event_phase" || key == "dispatch_message" || key == "event_id" ||
            key == "event_local_alarm_stopped"
        ) {
            handler.post { if (!isFinishing) refreshContent() }
        }
    }
    private val refresh = object : Runnable {
        override fun run() {
            refreshContent()
            handler.postDelayed(this, 1_000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) { /* A triggered alarm requires the explicit safe response. */ }
        }
        @Suppress("DEPRECATION")
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        window.statusBarColor = Color.rgb(36, 15, 28)
        window.navigationBarColor = Color.rgb(75, 20, 38)
        setContentView(buildContent())
        refreshContent()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        refreshContent()
    }

    override fun onResume() {
        super.onResume()
        getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
            .registerOnSharedPreferenceChangeListener(eventChanges)
        handler.removeCallbacks(refresh)
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
            .unregisterOnSharedPreferenceChangeListener(eventChanges)
        super.onPause()
    }

    @Deprecated("The safety response surface must stay visible until acted on")
    override fun onBackPressed() = Unit

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // Preserve the existing countdown response: any screen touch can
        // confirm safety before the native detector escalates the alert.
        if (event.actionMasked == MotionEvent.ACTION_DOWN && isAwaitingResponse()) {
            stopAlert()
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    private fun buildContent(): View {
        val root = FrameLayout(this).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
                intArrayOf(0xFF240F1C.toInt(), 0xFF6D1830.toInt(), 0xFFB73640.toInt()))
        }
        root.addView(View(this).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            background = GradientDrawable().apply {
                gradientType = GradientDrawable.RADIAL_GRADIENT
                colors = intArrayOf(0x44FFC6BF, 0x00FFC6BF)
                gradientRadius = dp(420).toFloat()
                setGradientCenter(1f, 0f)
            }
        }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        val scroll = ScrollView(this).apply { isFillViewport = true }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(28), dp(24), dp(24))
        }
        content.addView(text("HIKERCIRCLE SAFETY", 12f, 0xD9FFFFFF.toInt()).apply {
            letterSpacing = 0.18f
            typeface = Typeface.DEFAULT_BOLD
        }, matchWrap())
        content.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        val badge = FrameLayout(this).apply {
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x14FFFFFF)
                setStroke(dp(1), 0x30FFFFFF)
            }
        }
        badge.addView(text("SOS", 32f, 0xFF842039.toInt()).apply {
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
                intArrayOf(0xFFFFE8DC.toInt(), 0xFFFFC6BF.toInt())).apply {
                shape = GradientDrawable.OVAL
            }
        }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        content.addView(badge, LinearLayout.LayoutParams(dp(126), dp(126)).apply { topMargin = dp(28) })
        titleView = text("SOS triggered", 34f, Color.WHITE).apply { typeface = Typeface.DEFAULT_BOLD }
        modeView = text("", 16f, 0xFFFFDAD7.toInt()).apply { typeface = Typeface.DEFAULT_BOLD }
        bodyView = text("", 16f, 0xE6FFFFFF.toInt()).apply { setLineSpacing(0f, 1.15f) }
        content.addView(titleView, matchWrap(top = 24))
        content.addView(modeView, matchWrap(top = 10))
        content.addView(bodyView, matchWrap(top = 14))
        content.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        countdownStopButton = Button(this).apply {
            text = "I'm safe — cancel SOS"
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            setTextColor(0xFF842039.toInt())
            background = roundedBackground(0xFFFFE8DC.toInt(), 32f)
            setOnClickListener {
                // A phase change can arrive between the last refresh and this
                // click. Once triggered, only the slider may stop the alarm.
                if (isAwaitingResponse()) stopAlert() else refreshContent()
            }
        }
        stopSlider = SosStopSlider(this) { stopAlert() }
        content.addView(countdownStopButton, matchWrap(top = 32, height = 74))
        content.addView(stopSlider, matchWrap(top = 32, height = 74))
        footerView = text("Messages already sent cannot be recalled.", 12f, 0xBFFFFFFF.toInt())
        content.addView(footerView, matchWrap(top = 14))
        content.addView(Button(this).apply {
            text = "Open HikerCircle"
            textSize = 14f
            isAllCaps = false
            setTextColor(0xE6FFFFFF.toInt())
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener {
                startActivity(Intent(this@SafetyAlertActivity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                })
                finish()
            }
        }, matchWrap(top = 6, height = 48))
        scroll.addView(content, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(scroll, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        return root
    }

    private fun refreshContent() {
        val prefs = getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
        if (prefs.getString("event_id", null).isNullOrBlank() ||
            prefs.getBoolean("event_local_alarm_stopped", false)
        ) {
            finish()
            return
        }
        val isStillness = prefs.getString("event_kind", "prolonged_stillness") == "prolonged_stillness"
        val phase = prefs.getString("event_phase", "awaiting_response")
        val awaitingResponse = phase == "awaiting_response"
        countdownStopButton.visibility = if (awaitingResponse) View.VISIBLE else View.GONE
        stopSlider.visibility = if (awaitingResponse) View.GONE else View.VISIBLE
        footerView.text = if (awaitingResponse) "No SOS has been sent yet." else "Messages already sent cannot be recalled."
        modeView.text = if (isStillness) "Prolonged-stillness SOS" else "Fall SOS"
        if (awaitingResponse) {
            val deadline = prefs.getLong("event_deadline_wall", 0L)
            val seconds = max(0L, (deadline - System.currentTimeMillis() + 999L) / 1_000L)
            titleView.text = if (isStillness) "Are you okay?" else "Possible fall detected"
            bodyView.text = "Tap anywhere within $seconds seconds to confirm you are safe."
            return
        }
        titleView.text = "SOS triggered"
        bodyView.text = when (phase) {
            "dispatching", "triggering" -> "Notifying your emergency contacts. Slide below to stop the alarm and confirm you are safe."
            "dispatched" -> prefs.getString("dispatch_message", null) ?: "Your alert was sent or queued. Slide below to stop the alarm."
            else -> "Contact delivery needs attention. You can stop the alarm and check delivery in HikerCircle."
        }
    }

    private fun stopAlert() {
        if (stoppingAlert) return
        stoppingAlert = true
        stopSlider.setStopping(true)
        val awaitingResponse = isAwaitingResponse()
        val eventId = getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
            .getString("event_id", "").orEmpty()
        try {
            if (awaitingResponse) {
                startService(Intent(this, HikeSafetyMonitorService::class.java).apply {
                    action = HikeSafetyMonitorService.ACTION_CANCEL_ALERT
                })
            } else if (!HikeSafetyMonitorService.stopTriggeredSafetyAlarm(this, eventId)) {
                throw IllegalStateException("The native alarm could not be stopped.")
            }
        } catch (_: RuntimeException) {
            stoppingAlert = false
            stopSlider.setStopping(false)
            bodyView.text = "The alarm could not stop. Please try again."
            return
        }
        startActivity(Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(if (awaitingResponse) "hikercircle://hike/safety-safe" else
                "hikercircle://hike/safety-alarm-stopped?eventId=${Uri.encode(eventId)}")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        })
        finish()
    }

    private fun isAwaitingResponse(): Boolean = getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
        .getString("event_phase", null) == "awaiting_response"

    private fun text(value: String, size: Float, color: Int) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(color)
        gravity = Gravity.CENTER
    }

    private fun matchWrap(top: Int = 0, height: Int = ViewGroup.LayoutParams.WRAP_CONTENT) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(height)).apply { topMargin = dp(top) }

    private fun dp(value: Int): Int = if (value < 0) value else (value * resources.displayMetrics.density).toInt()

    private fun roundedBackground(color: Int, radiusDp: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radiusDp * resources.displayMetrics.density
    }
}

/** A tap never stops a triggered alarm; a drag or explicit accessibility action does. */
private class SosStopSlider(context: Context, private val onConfirmed: () -> Unit) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val density = resources.displayMetrics.density
    private var progress = 0f
    private var dragStartX = 0f
    private var dragging = false
    private var stopping = false
    private val thumbSize get() = 58f * density
    private val inset get() = 8f * density
    private val travel get() = max(0f, width - 2f * inset - thumbSize)
    private val rtl get() = layoutDirection == View.LAYOUT_DIRECTION_RTL

    init {
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = "Slide to stop alarm and confirm you are safe"
        minimumHeight = (74f * density).toInt()
    }

    fun setStopping(value: Boolean) {
        stopping = value
        if (!value) progress = 0f
        invalidate()
        sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val radius = height / 2f
        rect.set(1f, 1f, width - 1f, height - 1f)
        paint.shader = null
        paint.style = Paint.Style.FILL
        paint.color = 0x33180716
        canvas.drawRoundRect(rect, radius, radius, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = density
        paint.color = 0x61FFFFFF
        canvas.drawRoundRect(rect, radius, radius, paint)
        paint.style = Paint.Style.FILL
        val label = if (stopping) "Stopping alarm…" else "Slide to stop alarm"
        paint.color = Color.WHITE
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 15f * resources.displayMetrics.scaledDensity
        val labelWidth = max(1f, width - 2f * (thumbSize + 2f * inset))
        val measured = paint.measureText(label)
        if (measured > labelWidth) paint.textSize *= labelWidth / measured
        paint.textAlign = Paint.Align.CENTER
        val labelCenter = width / 2f
        canvas.drawText(label, labelCenter, height / 2f - (paint.ascent() + paint.descent()) / 2f, paint)
        val left = if (rtl) width - inset - thumbSize - progress * travel else inset + progress * travel
        val top = (height - thumbSize) / 2f
        rect.set(left, top, left + thumbSize, top + thumbSize)
        paint.shader = LinearGradient(left, top, left + thumbSize, top + thumbSize,
            0xFFFFE8DC.toInt(), 0xFFFFC6BF.toInt(), Shader.TileMode.CLAMP)
        canvas.drawRoundRect(rect, thumbSize / 2f, thumbSize / 2f, paint)
        paint.shader = null
        paint.color = 0xFF842039.toInt()
        paint.textSize = 27f * density
        canvas.drawText(if (rtl) "‹‹" else "››", left + thumbSize / 2f,
            height / 2f - (paint.ascent() + paint.descent()) / 2f, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (stopping) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val left = if (rtl) width - inset - thumbSize else inset
                if (event.x < left - inset || event.x > left + thumbSize + inset) return false
                dragging = true
                dragStartX = event.x
                parent?.requestDisallowInterceptTouchEvent(true)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging) return false
                progress = progressAt(event.x)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!dragging) return false
                progress = progressAt(event.x)
                dragging = false
                parent?.requestDisallowInterceptTouchEvent(false)
                if (progress >= 0.88f) {
                    stopping = true
                    invalidate()
                    onConfirmed()
                } else {
                    progress = 0f
                    invalidate()
                }
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                dragging = false
                progress = 0f
                parent?.requestDisallowInterceptTouchEvent(false)
                invalidate()
                return true
            }
        }
        return false
    }

    private fun progressAt(x: Float): Float {
        val distance = (x - dragStartX) * if (rtl) -1f else 1f
        return if (travel > 0f) (distance / travel).coerceIn(0f, 1f) else 0f
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.SeekBar"
        info.isEnabled = !stopping
        info.isClickable = !stopping
        info.contentDescription = if (stopping) "Stopping alarm" else contentDescription
        if (!stopping) info.addAction(AccessibilityNodeInfo.AccessibilityAction(
            AccessibilityNodeInfo.ACTION_CLICK, "Confirm safe and stop alarm"))
    }

    override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean {
        if (action == AccessibilityNodeInfo.ACTION_CLICK) {
            if (!stopping) {
                stopping = true
                invalidate()
                onConfirmed()
            }
            return true
        }
        return super.performAccessibilityAction(action, arguments)
    }
}
