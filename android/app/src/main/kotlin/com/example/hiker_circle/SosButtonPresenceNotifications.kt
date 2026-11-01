package com.leongziqi.hikercircle

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/** Native delivery and owner-scoped history continue while Flutter is inactive. */
class SosButtonPresenceNotifications(private val context: Context) {
    companion object { private val lock = Any(); private const val CHANNEL = "hiker_circle_button_presence_v1" }
    private val preferences = context.getSharedPreferences("hiker_circle_button_presence_v1", Context.MODE_PRIVATE)
    private val manager get() = context.getSystemService(NotificationManager::class.java)
    private fun key(button: PairedSosButtonRegistry.Button) = "${button.ownerScope}.${button.deviceIdHex}.${button.pairedAtMillis}"
    private fun id(button: PairedSosButtonRegistry.Button, seen: Boolean) =
        (if (seen) 0x50000000 else 0x40000000) or (key(button).hashCode() and 0x0fffffff)
    private fun records(): List<JSONObject> {
        val array = runCatching { JSONArray(preferences.getString("history", "[]")) }.getOrDefault(JSONArray())
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }
    private fun save(rows: List<JSONObject>) { preferences.edit().putString("history", JSONArray(rows.takeLast(128)).toString()).commit() }
    private fun append(button: PairedSosButtonRegistry.Button, messageId: String, title: String, body: String, type: String, at: Long) {
        val rows = records()
        if (rows.any { it.optString("messageId") == messageId }) return
        save(rows + JSONObject().put("ownerScope", button.ownerScope).put("messageId", messageId)
            .put("title", title).put("body", body).put("type", type).put("receivedAtMillis", at)
            .put("deepLink", "hikercircle://sos/device-settings?source=button_presence"))
    }
    /** Announce once on first detection and once after a full absence; routine packets stay quiet. */
    fun seen(button: PairedSosButtonRegistry.Button, previous: Long?, now: Long, notify: Boolean = true) = synchronized(lock) {
        if (button.ownerScope == null) return@synchronized
        recordLost(button, previous ?: button.pairedAtMillis, now, publish = false)
        val marker = "seen:${key(button)}"
        if (SosButtonPresencePolicy.shouldAnnounceSeen(previous, preferences.getBoolean(marker, false), now)) {
            val title = "SOS button is seen"
            val body = "Your phone detected ${button.displayName} nearby."
            append(button, "button_seen:${key(button)}:$now", title, body, "sos_button_seen", now)
            preferences.edit().putBoolean(marker, true).commit()
            if (notify) post(button, true, title, body)
        }
        manager.cancel(id(button, false))
        manager.cancel(4300 + (button.deviceIdHex.hashCode() and 0x3ff))
    }
    /** The monitor's watchdog applies the fixed hour even after upgrading from a disabled warning. */
    fun check(button: PairedSosButtonRegistry.Button, now: Long) = synchronized(lock) {
        recordLost(button, SosButtonPresencePolicy.reference(button.lastSeenAtMillis, button.pairedAtMillis, now), now, publish = true)
    }
    private fun recordLost(button: PairedSosButtonRegistry.Button, reference: Long, now: Long, publish: Boolean) {
        if (button.ownerScope == null || now - reference < SosButtonPresencePolicy.ABSENCE_MILLIS) return
        val marker = "lost:${key(button)}"
        if (preferences.getLong(marker, Long.MIN_VALUE) == reference) return
        val title = "SOS button not seen"
        val body = "HikerCircle has not detected ${button.displayName} for 1 hour. Check its power and keep it nearby."
        append(button, "button_unseen:${key(button)}:$reference", title, body, "sos_button_unseen", reference + SosButtonPresencePolicy.ABSENCE_MILLIS)
        preferences.edit().putLong(marker, reference).commit()
        if (publish) post(button, false, title, body)
    }
    /** Only the active owner can drain or acknowledge these records through the native bridge. */
    fun notices(owner: String): List<Map<String, Any>> = synchronized(lock) {
        records().filter { it.optString("ownerScope") == owner }.map { row -> row.keys().asSequence().associateWith { row.get(it) } }
    }
    fun acknowledge(owner: String, ids: Set<String>) = synchronized(lock) {
        save(records().filterNot { it.optString("ownerScope") == owner && ids.contains(it.optString("messageId")) })
    }
    fun cancel(buttons: List<PairedSosButtonRegistry.Button>) {
        runCatching { buttons.forEach { manager.cancel(id(it, false)); manager.cancel(id(it, true)); manager.cancel(4300 + (it.deviceIdHex.hashCode() and 0x3ff)) } }
    }
    private fun post(button: PairedSosButtonRegistry.Button, seen: Boolean, title: String, body: String) {
        runCatching {
            if (PairedSosButtonRegistry(context).activeOwnerScopeToken() != button.ownerScope) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) manager.createNotificationChannel(NotificationChannel(CHANNEL, "SOS button presence", NotificationManager.IMPORTANCE_HIGH))
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("hikercircle://sos/device-settings?source=button_presence")).setPackage(context.packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, CHANNEL) else Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
            manager.notify(id(button, seen), builder.setSmallIcon(if (seen) android.R.drawable.ic_dialog_info else android.R.drawable.ic_dialog_alert)
                .setContentTitle(title).setContentText(body).setAutoCancel(true)
                .setContentIntent(PendingIntent.getActivity(context, id(button, seen), intent, flags)).build())
        }
    }
}
