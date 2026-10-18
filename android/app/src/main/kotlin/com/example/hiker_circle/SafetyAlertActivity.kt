// SafetyAlertActivity shows the native fall/stillness response prompt above the lock screen.
package com.leongziqi.hikercircle

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.max

/** Full-screen, lock-screen-visible response surface for native hike alerts. */
class SafetyAlertActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var titleView: TextView
    private lateinit var bodyView: TextView
    private lateinit var stopButton: Button
    private var stoppingAlert = false

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
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
        )
        window.statusBarColor = Color.rgb(116, 20, 28)
        window.navigationBarColor = Color.rgb(34, 12, 15)
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
        handler.removeCallbacks(refresh)
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        super.onPause()
    }

    @Deprecated("The safety response surface must stay visible until acted on")
    override fun onBackPressed() = Unit

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN && isAwaitingResponse()) {
            stopAlert()
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    private fun buildContent(): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(48), dp(28), dp(40))
            setBackgroundColor(Color.rgb(45, 13, 18))
        }
        val badge = TextView(this).apply {
            text = "HIKERCIRCLE SAFETY"
            setTextColor(Color.rgb(255, 205, 92))
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        titleView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 34f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(28), 0, dp(18))
        }
        bodyView = TextView(this).apply {
            setTextColor(Color.rgb(245, 225, 228))
            textSize = 19f
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.15f)
        }
        stopButton = Button(this).apply {
            text = "I'M SAFE — TAP ANYWHERE"
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            setTextColor(Color.rgb(42, 17, 20))
            background = roundedBackground(Color.rgb(255, 220, 104), 18f)
            setOnClickListener { stopAlert() }
        }
        val openButton = Button(this).apply {
            text = "Open HikerCircle"
            textSize = 16f
            isAllCaps = false
            setTextColor(Color.WHITE)
            background = roundedBackground(Color.rgb(112, 37, 47), 16f)
            setOnClickListener {
                startActivity(
                    Intent(this@SafetyAlertActivity, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    },
                )
                finish()
            }
        }
        root.addView(badge, matchWrap())
        root.addView(titleView, matchWrap())
        root.addView(bodyView, matchWrap())
        root.addView(stopButton, matchWrap(top = 38, height = 64))
        root.addView(openButton, matchWrap(top = 14, height = 56))
        return root
    }

    private fun refreshContent() {
        val prefs = getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
        val eventId = prefs.getString("event_id", null)
        if (eventId.isNullOrBlank()) {
            finish()
            return
        }
        val kind = prefs.getString("event_kind", "prolonged_stillness")
        val isStillness = kind == "prolonged_stillness"
        val phase = prefs.getString("event_phase", "awaiting_response")
        val deadline = prefs.getLong("event_deadline_wall", 0L)
        val seconds = max(0L, (deadline - System.currentTimeMillis() + 999L) / 1_000L)
        when (phase) {
            "awaiting_response" -> {
                titleView.text = if (isStillness) {
                    "Are you okay?"
                } else {
                    "Possible fall detected"
                }
                bodyView.text =
                    "Tap anywhere on this screen within $seconds seconds to confirm " +
                    "you are safe. No SOS has been sent yet."
            }
            "dispatching", "triggering" -> {
                titleView.text = "SOS escalation started"
                bodyView.text =
                    "HikerCircle is notifying your emergency contacts. " +
                    "Press the button below to stop the phone alarm and confirm you are safe."
            }
            "dispatched" -> {
                titleView.text = "Emergency alert processed"
                bodyView.text = prefs.getString("dispatch_message", null)
                    ?: "Your alert was sent or queued. Press below to stop the alarm and confirm you are safe."
            }
            else -> {
                titleView.text = "Safety alert needs attention"
                bodyView.text =
                    "Open HikerCircle to retry contact delivery, or confirm that you are safe."
            }
        }
    }

    private fun stopAlert() {
        if (stoppingAlert) return
        stoppingAlert = true
        startService(
            Intent(this, HikeSafetyMonitorService::class.java).apply {
                action = HikeSafetyMonitorService.ACTION_CANCEL_ALERT
            },
        )
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("hikercircle://hike/safety-safe")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
        )
        finish()
    }

    private fun isAwaitingResponse(): Boolean =
        getSharedPreferences("hiker_circle_hike_safety", MODE_PRIVATE)
            .getString("event_phase", null) == "awaiting_response"

    private fun matchWrap(top: Int = 0, height: Int = ViewGroup.LayoutParams.WRAP_CONTENT) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(height)).apply {
            topMargin = dp(top)
        }

    private fun dp(value: Int): Int = if (value < 0) value else
        (value * resources.displayMetrics.density).toInt()

    private fun roundedBackground(color: Int, radiusDp: Float) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radiusDp * resources.displayMetrics.density
        }
}
