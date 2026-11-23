package com.leongziqi.hikercircle

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.functions.FirebaseFunctions

/** Stores arrival evidence and the safe response separately from fall and SOS state. */
object HikeArrivalSafety {
    private const val PREFS = "hiker_circle_arrival_safety_v1"
    private const val CHANNEL = "hiker_circle_arrival_checks_v1"
    private const val ALARM_ID = 53126
    var onChanged: (() -> Unit)? = null
    private var acknowledgementInFlight = false
    private var lastAcknowledgementAttempt = 0L

    /** Updates one physical hike while retaining responses across offline-session remapping. */
    fun configure(context: Context, data: Map<*, *>): Map<String, Any?>? {
        val incoming = JSONObject(data)
        val owner = incoming.optString("owner")
        val tracking = incoming.optString("trackingKey")
        val plan = incoming.optJSONObject("plan") ?: return null
        if (owner.isBlank() || tracking.length != 64 || plan.optJSONArray("targets")?.length() == 0) return null
        var state = read(context)
        if (state.optString("owner") != owner || state.optString("trackingKey") != tracking) {
            cancelNotification(context, state)
            val warning = maxOf(plan.optLong("latestArrivalAtMillis"), System.currentTimeMillis())
            state = JSONObject().put("owner", owner).put("trackingKey", tracking)
                .put("warningAtMillis", warning)
                .put("responseDeadlineMillis", warning + incoming.optLong("responseWindowMillis", 300000))
        }
        state.put("sessionId", incoming.optString("sessionId"))
        state.put("eventId", incoming.optString("eventId"))
        state.put("trailName", incoming.optString("trailName"))
        state.put("plan", plan)
        var proof = state.optJSONObject("proof") ?: JSONObject()
        incoming.optJSONObject("proof")?.let { supplied ->
            val gates = proof.optJSONObject("passedGates") ?: JSONObject()
            supplied.optJSONObject("passedGates")?.let { next ->
                next.keys().forEach { key -> if (!gates.has(key)) gates.put(key, next.get(key)) }
            }
            proof.put("passedGates", gates)
            if (supplied.has("arrivedAtMillis")) proof = supplied
        }
        state.put("proof", proof)
        incoming.optJSONObject("cloud")?.let { cloud ->
            if (cloud.has("warningAtMillis")) state.put("warningAtMillis", cloud.get("warningAtMillis"))
            if (cloud.has("responseDeadlineMillis")) state.put("responseDeadlineMillis", cloud.get("responseDeadlineMillis"))
            if (cloud.optString("status") in setOf("safe", "arrived", "completed")) state.put("safe", true).put("cloudAcknowledged", true)
        }
        save(context, state)
        if (state.optBoolean("safe") || proof.has("arrivedAtMillis")) {
            cancelNotification(context, state)
            if (proof.has("arrivedAtMillis")) acknowledgeCloud(context, state)
        }
        else schedule(context, state)
        tick(context)
        return snapshot(context)
    }

    /** Adds only a fix that has already been saved to the durable footprint buffer. */
    fun recordFootprint(context: Context, sessionId: String, owner: String, location: Location) {
        val state = read(context)
        if (state.optString("sessionId") != sessionId || state.optString("owner") != owner) return
        val plan = state.optJSONObject("plan") ?: return
        if (!location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0 ||
            location.accuracy > plan.optDouble("maximumAccuracyMeters", 100.0) ||
            !location.latitude.isFinite() || !location.longitude.isFinite() ||
            location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0 ||
            location.time < plan.optLong("startedAtMillis") || location.time > System.currentTimeMillis() + 10000) return
        val proof = state.optJSONObject("proof") ?: JSONObject()
        if (proof.has("arrivedAtMillis")) { acknowledgeCloud(context, state); return }
        val passed = proof.optJSONObject("passedGates") ?: JSONObject()
        val radius = plan.optDouble("radiusMeters", 100.0)
        val targets = plan.optJSONArray("targets") ?: return
        for (index in 0 until targets.length()) {
            val target = targets.getJSONObject(index)
            val id = target.optString("id")
            val gated = target.optBoolean("requiresGate")
            val gates = target.optJSONArray("gates")
            if (gated && !passed.has(id) && gates != null &&
                (0 until gates.length()).any { distance(location, gates.getJSONObject(it)) <= radius }) passed.put(id, location.time)
            val gateAt = passed.optLong(id, -1)
            if ((!gated || gateAt >= plan.optLong("startedAtMillis") && gateAt < location.time) && distance(location, target) <= radius) {
                proof.put("arrivedAtMillis", location.time).put("targetId", id).put("targetName", target.optString("name"))
                break
            }
        }
        proof.put("passedGates", passed)
        state.put("proof", proof)
        save(context, state)
        if (proof.has("arrivedAtMillis")) { cancelNotification(context, state); acknowledgeCloud(context, state); changed() }
    }

    /** Restores only the signed-in owner's pending local confirmation. */
    fun readState(context: Context, owner: String): Map<String, Any?>? =
        if (read(context).optString("owner") == owner) snapshot(context) else null

    /** Persists the explicit response before Flutter attempts cloud cancellation. */
    fun confirmSafe(context: Context, owner: String, tracking: String): Map<String, Any?>? {
        val state = read(context)
        if (state.optString("owner") != owner || state.optString("trackingKey") != tracking) return null
        state.put("safe", true).put("cloudAcknowledged", false).put("safeAtMillis", System.currentTimeMillis())
        save(context, state)
        cancelNotification(context, state)
        changed()
        return snapshot(context)
    }

    /** Stops only the matching owner's warning when their hike ends. */
    fun stop(context: Context, owner: String) {
        val state = read(context)
        if (state.optString("owner") != owner) return
        cancelNotification(context, state)
        check(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit())
    }

    /** Fires once from the foreground service or the system alarm; state survives a killed process. */
    fun tick(context: Context) {
        val state = read(context)
        if (state.optString("trackingKey").isBlank() || state.optBoolean("safe") ||
            state.optJSONObject("proof")?.has("arrivedAtMillis") == true || state.has("notifiedAtMillis") ||
            System.currentTimeMillis() < state.optLong("warningAtMillis", Long.MAX_VALUE)) return
        state.put("notifiedAtMillis", state.optLong("warningAtMillis"))
        save(context, state)
        val manager = context.getSystemService(NotificationManager::class.java)
        val raw = context.resources.getIdentifier("arrival_overdue", "raw", context.packageName)
        val sound = Uri.parse("android.resource://${context.packageName}/$raw")
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Hike arrival checks", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Spoken reminders when arrival at a peak or trail end is unconfirmed"
                setSound(sound, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            })
        }
        val link = Uri.Builder().scheme("hikercircle").authority("hike").path("arrival")
            .appendQueryParameter("sessionId", state.optString("sessionId")).build()
        val intent = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(link)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open = PendingIntent.getActivity(context, state.optString("trackingKey").hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert).setContentTitle("Is everything okay?")
            .setContentText("Arrival at the peak or trail end has not been confirmed. Open HikerCircle to respond.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Your latest arrival time has passed. Open HikerCircle and confirm you are okay before your emergency contacts are alerted."))
            .setSound(sound).setPriority(NotificationCompat.PRIORITY_HIGH).setContentIntent(open).setAutoCancel(true).build()
        runCatching { manager.notify(state.optString("trackingKey").hashCode(), notification) }
        changed()
    }

    /** Restores ordinary primitive channel values without leaking JSONObject instances into Flutter. */
    private fun snapshot(context: Context): Map<String, Any?> {
        val state = read(context)
        val arrived = state.optJSONObject("proof")?.has("arrivedAtMillis") == true
        state.put("arrived", arrived).put("overdue", !arrived && !state.optBoolean("safe") &&
            System.currentTimeMillis() >= state.optLong("warningAtMillis", Long.MAX_VALUE))
        return toMap(state)
    }

    /** Schedules an OS fallback while the existing active-hike service keeps its own one-second check. */
    private fun schedule(context: Context, state: JSONObject) {
        val at = state.optLong("warningAtMillis")
        if (state.has("notifiedAtMillis") || state.optLong("scheduledWarningAtMillis", -1) == at) return
        val alarm = context.getSystemService(AlarmManager::class.java)
        val intent = alarmIntent(context)
        if (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(at, System.currentTimeMillis() + 1000), intent)
        else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(at, System.currentTimeMillis() + 1000), intent)
        state.put("scheduledWarningAtMillis", at)
        save(context, state)
    }

    /** Cancels pending and delivered copies after confirmation or recorded arrival. */
    private fun cancelNotification(context: Context, state: JSONObject) {
        context.getSystemService(AlarmManager::class.java).cancel(alarmIntent(context))
        context.getSystemService(NotificationManager::class.java).cancel(state.optString("trackingKey").hashCode())
    }

    /** Cancels cloud work from a recorded arrival without depending on a live Flutter isolate. */
    private fun acknowledgeCloud(context: Context, state: JSONObject) {
        val now = System.currentTimeMillis()
        if (state.optBoolean("cloudAcknowledged") || acknowledgementInFlight ||
            now - lastAcknowledgementAttempt < 15000 ||
            FirebaseAuth.getInstance().currentUser?.uid != state.optString("owner") || state.optString("eventId").isBlank()) return
        acknowledgementInFlight = true; lastAcknowledgementAttempt = now
        val event = state.optString("eventId"); val tracking = state.optString("trackingKey")
        val reason = if (state.optJSONObject("proof")?.has("arrivedAtMillis") == true) "recorded_arrival" else "hiker_confirmation"
        // Update cloud: confirm safe hike arrival
        FirebaseFunctions.getInstance().getHttpsCallable("confirmHikeArrivalSafety")
            .call(mapOf("sessionId" to state.optString("sessionId"), "eventId" to event, "reason" to reason))
            .addOnCompleteListener { task ->
                acknowledgementInFlight = false
                val current = read(context)
                if (task.isSuccessful && current.optString("trackingKey") == tracking && current.optString("eventId") == event) {
                    current.put("cloudAcknowledged", true); save(context, current); changed()
                }
            }
    }

    /** Uses an explicit private receiver; a notification tap never confirms safety on its own. */
    private fun alarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(context, ALARM_ID,
        Intent(context, HikeArrivalSafetyReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** Reads only this feature's durable record. */
    private fun read(context: Context): JSONObject = runCatching { JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("state", "{}") ?: "{}") }.getOrElse { JSONObject() }

    /** Commit synchronously so a fast app termination cannot discard the hiker's response. */
    private fun save(context: Context, state: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val encoded = state.toString()
        if (prefs.getString("state", null) != encoded) check(prefs.edit().putString("state", encoded).commit())
    }

    /** Publishes callbacks on the Flutter channel's main thread. */
    private fun changed() { Handler(Looper.getMainLooper()).post { runCatching { onChanged?.invoke() } } }

    /** Converts a validated destination to metres. */
    private fun distance(location: Location, point: JSONObject): Double {
        val lat = point.optDouble("latitude", Double.NaN); val lng = point.optDouble("longitude", Double.NaN)
        if (!lat.isFinite() || !lng.isFinite() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return Double.MAX_VALUE
        val result = FloatArray(1); Location.distanceBetween(location.latitude, location.longitude, lat, lng, result)
        return result[0].toDouble()
    }

    /** Converts nested JSON containers to standard codec-supported collections. */
    private fun toMap(value: JSONObject): Map<String, Any?> = value.keys().asSequence().associateWith { key -> toValue(value.get(key)) }

    /** Recursively converts destination/gate arrays for the standard Flutter codec. */
    private fun toValue(item: Any?): Any? = when (item) {
        is JSONObject -> toMap(item)
        is org.json.JSONArray -> (0 until item.length()).map { toValue(item.get(it)) }
        JSONObject.NULL -> null
        else -> item
    }
}

/** Receives only the private scheduled deadline alarm. */
class HikeArrivalSafetyReceiver : BroadcastReceiver() {
    /** Restores the persisted warning without launching the app or creating an SOS. */
    override fun onReceive(context: Context, intent: Intent) { HikeArrivalSafety.tick(context) }
}
