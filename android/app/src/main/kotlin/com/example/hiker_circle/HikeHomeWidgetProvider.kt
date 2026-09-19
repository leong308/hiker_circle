package com.leongziqi.hikercircle

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NextHikeWidgetProvider : HikeHomeWidgetProvider(false)
class HikeWeatherWidgetProvider : HikeHomeWidgetProvider(true)

open class HikeHomeWidgetProvider(private val weatherMode: Boolean = false) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context, id))
    }

    private fun views(context: Context, id: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.hike_home_widget)
        val now = System.currentTimeMillis() / 1000.0
        val hike = try {
            val data = JSONObject(context.getSharedPreferences("home_widgets", Context.MODE_PRIVATE)
                .getString("snapshot", "{\"hikes\":[]}") ?: "{\"hikes\":[]}").optJSONArray("hikes")
            (0 until (data?.length() ?: 0)).mapNotNull { data?.optJSONObject(it) }
                .filter { it.optDouble("expires", 0.0) > now }
                .minByOrNull { it.optDouble("departure", 0.0) }
        } catch (_: Exception) { null }
        views.setTextViewText(R.id.hike_widget_heading, if (weatherMode) "HIKE WEATHER" else "NEXT HIKE")
        views.setViewVisibility(R.id.hike_widget_countdown, View.GONE)
        views.setViewVisibility(R.id.hike_widget_context, View.GONE)
        if (hike == null) {
            views.setTextViewText(R.id.hike_widget_name, "Plan your next hike")
            views.setTextViewText(R.id.hike_widget_main, "Open HikerCircle to schedule a hike")
            views.setTextViewText(R.id.hike_widget_detail, if (weatherMode) "Your hiking forecast will appear here." else "Your route and gear checklist will appear here.")
            views.setTextViewText(R.id.hike_widget_footer, "Open HikerCircle →")
        } else {
            views.setTextViewText(R.id.hike_widget_name, hike.optString("name"))
            if (weatherMode) {
                val contextLabel = when {
                    now < hike.optDouble("departure") -> "Upcoming hike"
                    now < hike.optDouble("returning") -> "Scheduled hike window"
                    else -> "Past hike window"
                }
                views.setTextViewText(R.id.hike_widget_context, contextLabel)
                views.setViewVisibility(R.id.hike_widget_context, View.VISIBLE)
                val weather = hike.optJSONObject("weather")
                if (weather != null && weather.optBoolean("covered")) {
                    val temp = if (weather.has("minTemp") && weather.has("maxTemp"))
                        "${Math.round(weather.getDouble("minTemp"))}–${Math.round(weather.getDouble("maxTemp"))}°C" else "Temperature unavailable"
                    val rain = if (weather.has("rain")) "${Math.round(weather.getDouble("rain"))}% peak chance" else "Rain unavailable"
                    views.setTextViewText(R.id.hike_widget_main, "$temp  ·  $rain")
                    views.setTextViewText(R.id.hike_widget_detail, "Departure to return\n${weather.optString("daylight")}")
                    val updated = weather.optDouble("updated", 0.0)
                    val status = if (now - updated >= 14400) "Outdated" else "Updated"
                    views.setTextViewText(R.id.hike_widget_footer, "$status ${formatTime(updated)} · Open-Meteo")
                } else {
                    val weatherStatus = hike.optString("weatherStatus")
                    views.setTextViewText(R.id.hike_widget_main, when (weatherStatus) {
                        "beyondRange", "incomplete" -> "Forecast available closer to departure"
                        "unavailable" -> "Forecast unavailable"
                        else -> "Open app to refresh forecast"
                    })
                    views.setTextViewText(R.id.hike_widget_detail, when (weatherStatus) {
                        "beyondRange" -> "Forecasts cover up to 16 days ahead."
                        "unavailable" -> "Tap to retry in HikerCircle."
                        else -> "Weather for your scheduled hiking window."
                    })
                    views.setTextViewText(R.id.hike_widget_footer, "Tap to view hike weather →")
                }
            } else {
                val departure = hike.optDouble("departure", 0.0)
                views.setTextViewText(R.id.hike_widget_main, "${String.format(Locale.getDefault(), "%.1f", hike.optDouble("distanceKm"))} km · ${hike.optString("difficulty")}")
                views.setTextViewText(R.id.hike_widget_detail, "Depart ${formatTime(departure)}\nReturn ${formatTime(hike.optDouble("returning"))}")
                if (departure > now && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    views.setViewVisibility(R.id.hike_widget_countdown, View.VISIBLE)
                    views.setChronometer(R.id.hike_widget_countdown,
                        SystemClock.elapsedRealtime() + ((departure - now) * 1000).toLong(), "%s to departure", true)
                    views.setChronometerCountDown(R.id.hike_widget_countdown, true)
                }
                val gear = if (hike.has("gearTotal")) "Gear checklist ${hike.optInt("gearDone")}/${hike.optInt("gearTotal")}" else "Tap to review preparation"
                views.setTextViewText(R.id.hike_widget_footer, gear)
            }
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(if (weatherMode) "hikercircle://hike/weather" else "hikercircle://hike/briefing"))
            .setPackage(context.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.hike_widget_root, pending)
        return views
    }

    private fun formatTime(epoch: Double): String = SimpleDateFormat("d MMM · HH:mm", Locale.getDefault()).format(Date((epoch * 1000).toLong()))

    companion object {
        fun publish(context: Context, snapshot: String) {
            JSONObject(snapshot) // Reject invalid JSON before replacing the last valid snapshot.
            context.getSharedPreferences("home_widgets", Context.MODE_PRIVATE).edit().putString("snapshot", snapshot).apply()
            val manager = AppWidgetManager.getInstance(context)
            UpcomingHikesWidgetProvider().onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, UpcomingHikesWidgetProvider::class.java)))
            NextHikeWidgetProvider().onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, NextHikeWidgetProvider::class.java)))
            HikeWeatherWidgetProvider().onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, HikeWeatherWidgetProvider::class.java)))
        }
    }
}

class UpcomingHikesWidgetProvider : AppWidgetProvider() {
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle) {
        onUpdate(context, manager, intArrayOf(id))
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val now = System.currentTimeMillis() / 1000.0
        val hikes = try {
            val data = JSONObject(context.getSharedPreferences("home_widgets", Context.MODE_PRIVATE)
                .getString("snapshot", "{\"hikes\":[]}") ?: "{\"hikes\":[]}").optJSONArray("hikes")
            (0 until (data?.length() ?: 0)).mapNotNull { data?.optJSONObject(it) }
                .filter { it.optDouble("expires", 0.0) > now }.sortedBy { it.optDouble("departure", 0.0) }
        } catch (_: Exception) { emptyList() }
        for (id in ids) {
            val view = RemoteViews(context.packageName, R.layout.upcoming_hikes_widget)
            val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 300)
            val limit = if (height < 280 || context.resources.configuration.fontScale > 1.2f) 3 else 4
            view.removeAllViews(R.id.upcoming_widget_rows)
            view.setTextViewText(R.id.upcoming_widget_count, "${hikes.size} planned")
            view.setViewVisibility(R.id.upcoming_widget_empty, if (hikes.isEmpty()) View.VISIBLE else View.GONE)
            hikes.take(limit).forEachIndexed { index, hike ->
                val row = RemoteViews(context.packageName, R.layout.upcoming_hike_widget_row)
                val date = Date((hike.optDouble("departure") * 1000).toLong())
                row.setTextViewText(R.id.upcoming_row_month, SimpleDateFormat("MMM", Locale.getDefault()).format(date))
                row.setTextViewText(R.id.upcoming_row_day, SimpleDateFormat("d", Locale.getDefault()).format(date))
                row.setTextViewText(R.id.upcoming_row_name, hike.optString("name"))
                row.setTextViewText(R.id.upcoming_row_detail, "${SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)}  ·  ${String.format(Locale.getDefault(), "%.1f", hike.optDouble("distanceKm"))} km")
                val uri = Uri.parse("hikercircle://upcoming-hike/view").buildUpon().appendQueryParameter("upcomingHikeId", hike.optString("id")).build()
                row.setOnClickPendingIntent(R.id.upcoming_row_root, open(context, uri, id * 10 + index))
                view.addView(R.id.upcoming_widget_rows, row)
            }
            view.setTextViewText(R.id.upcoming_widget_footer, if (hikes.size > limit) "+${hikes.size - limit} more · Open your hiking plans →" else "Tap a hike to review preparation →")
            view.setOnClickPendingIntent(R.id.upcoming_widget_root, open(context, Uri.parse("hikercircle://hike/briefing"), id))
            manager.updateAppWidget(id, view)
        }
    }
    private fun open(context: Context, uri: Uri, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
