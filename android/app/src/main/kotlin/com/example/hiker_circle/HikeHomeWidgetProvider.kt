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

private fun visibleWidgetHikes(context: Context, now: Double): List<JSONObject> = try {
    val json = context.getSharedPreferences("home_widgets", Context.MODE_PRIVATE)
        .getString("snapshot", "{\"hikes\":[]}") ?: "{\"hikes\":[]}"
    val data = JSONObject(json).optJSONArray("hikes")
    (0 until (data?.length() ?: 0))
        .mapNotNull { data?.optJSONObject(it) }
        .filter { it.optDouble("expires", 0.0) > now }
        .sortedBy { it.optDouble("departure", 0.0) }
} catch (_: Exception) {
    emptyList()
}

open class HikeHomeWidgetProvider(
    private val weatherMode: Boolean = false,
) : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        for (id in ids) manager.updateAppWidget(id, views(context, id))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: android.os.Bundle,
    ) {
        manager.updateAppWidget(id, views(context, id))
    }

    private fun views(context: Context, id: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.hike_home_widget)
        val now = System.currentTimeMillis() / 1000.0
        val hike = visibleWidgetHikes(context, now).firstOrNull()
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
        val compact = options.getInt(
            AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
            320,
        ) < 250
        val accent = context.getColor(
            if (weatherMode) R.color.widget_cyan else R.color.widget_green,
        )

        views.setTextViewText(
            R.id.hike_widget_heading,
            if (weatherMode) "HIKE WEATHER" else "NEXT HIKE",
        )
        views.setTextColor(R.id.hike_widget_heading, accent)
        views.setImageViewResource(
            R.id.hike_widget_heading_icon,
            if (weatherMode) R.drawable.ic_widget_weather else R.drawable.ic_widget_hike,
        )
        views.setInt(R.id.hike_widget_name, "setMaxLines", if (compact) 2 else 1)
        resetDynamicVisibility(views)

        if (hike == null) {
            showEmptyState(views, accent)
        } else {
            views.setTextViewText(R.id.hike_widget_name, hike.optString("name"))
            if (weatherMode) {
                showWeather(views, hike, now, compact)
            } else {
                showNextHike(views, hike, now, compact)
            }
        }

        val deepLink = if (weatherMode) {
            "hikercircle://hike/weather"
        } else {
            "hikercircle://hike/briefing"
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLink))
            .setPackage(context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.hike_widget_root, pending)
        return views
    }

    private fun resetDynamicVisibility(views: RemoteViews) {
        views.setViewVisibility(R.id.hike_widget_context, View.GONE)
        views.setViewVisibility(R.id.hike_widget_empty_content, View.GONE)
        views.setViewVisibility(R.id.hike_widget_next_content, View.GONE)
        views.setViewVisibility(R.id.hike_widget_weather_content, View.GONE)
        views.setViewVisibility(R.id.hike_widget_countdown, View.GONE)
        views.setViewVisibility(R.id.hike_widget_gear_progress, View.GONE)
        views.setViewVisibility(R.id.hike_widget_weather_metrics, View.GONE)
        views.setViewVisibility(R.id.hike_widget_weather_status, View.GONE)
        views.setViewVisibility(R.id.hike_widget_weather_detail, View.GONE)
    }

    private fun showEmptyState(views: RemoteViews, accent: Int) {
        views.setTextViewText(R.id.hike_widget_name, "Plan your next hike")
        views.setViewVisibility(R.id.hike_widget_empty_content, View.VISIBLE)
        views.setTextViewText(
            R.id.hike_widget_empty_message,
            if (weatherMode) {
                "Schedule a hike in HikerCircle to see its forecast."
            } else {
                "Your next route and departure appear here."
            },
        )
        views.setTextViewText(R.id.hike_widget_empty_action, "Open HikerCircle →")
        views.setTextColor(R.id.hike_widget_empty_action, accent)
    }

    private fun showNextHike(
        views: RemoteViews,
        hike: JSONObject,
        now: Double,
        compact: Boolean,
    ) {
        views.setViewVisibility(R.id.hike_widget_next_content, View.VISIBLE)
        views.setTextViewText(
            R.id.hike_widget_main,
            "${String.format(Locale.getDefault(), "%.1f", hike.optDouble("distanceKm"))} km · " +
                hike.optString("difficulty"),
        )
        views.setViewVisibility(
            R.id.hike_widget_main,
            if (compact) View.GONE else View.VISIBLE,
        )

        val departure = hike.optDouble("departure", 0.0)
        val returning = hike.optDouble("returning", 0.0)
        views.setTextViewText(
            R.id.hike_widget_detail,
            if (compact) {
                formatDateTime(departure)
            } else {
                "${formatDateTime(departure)} → ${formatDateTime(returning)}"
            },
        )
        views.setViewVisibility(R.id.hike_widget_countdown, View.VISIBLE)
        if (departure > now && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            views.setChronometer(
                R.id.hike_widget_countdown,
                SystemClock.elapsedRealtime() + ((departure - now) * 1000).toLong(),
                "%s to go",
                true,
            )
            views.setChronometerCountDown(R.id.hike_widget_countdown, true)
        } else if (departure > now) {
            views.setChronometer(
                R.id.hike_widget_countdown,
                SystemClock.elapsedRealtime(),
                "%s",
                false,
            )
            views.setTextViewText(
                R.id.hike_widget_countdown,
                "Starts ${formatClock(departure)}",
            )
        } else {
            views.setChronometer(
                R.id.hike_widget_countdown,
                SystemClock.elapsedRealtime(),
                "%s",
                false,
            )
            views.setTextViewText(R.id.hike_widget_countdown, "Departure time reached")
        }

        val total = hike.optInt("gearTotal", 0).coerceAtLeast(0)
        val done = hike.optInt("gearDone", 0).coerceIn(0, total)
        views.setTextViewText(
            R.id.hike_widget_footer,
            if (total > 0) "Gear checklist $done/$total" else "Tap to review preparation",
        )
        if (total > 0) {
            views.setViewVisibility(R.id.hike_widget_gear_progress, View.VISIBLE)
            views.setProgressBar(
                R.id.hike_widget_gear_progress,
                100,
                ((done.toDouble() / total) * 100).toInt().coerceIn(0, 100),
                false,
            )
        }
    }

    private fun showWeather(
        views: RemoteViews,
        hike: JSONObject,
        now: Double,
        compact: Boolean,
    ) {
        views.setViewVisibility(R.id.hike_widget_weather_content, View.VISIBLE)
        val contextLabel = when {
            now < hike.optDouble("departure") -> "Upcoming hike"
            now < hike.optDouble("returning") -> "Scheduled hike window"
            else -> "Past hike window"
        }
        views.setTextViewText(R.id.hike_widget_context, contextLabel)
        views.setViewVisibility(R.id.hike_widget_context, View.VISIBLE)

        val weather = hike.optJSONObject("weather")
        if (weather != null && weather.optBoolean("covered")) {
            val temperature = if (weather.has("minTemp") && weather.has("maxTemp")) {
                "${Math.round(weather.getDouble("minTemp"))}–" +
                    "${Math.round(weather.getDouble("maxTemp"))}°"
            } else {
                "—"
            }
            val rain = if (weather.has("rain")) {
                "${Math.round(weather.getDouble("rain"))}%"
            } else {
                "—"
            }
            views.setViewVisibility(R.id.hike_widget_weather_metrics, View.VISIBLE)
            views.setTextViewText(R.id.hike_widget_temperature, temperature)
            views.setTextViewText(R.id.hike_widget_rain, rain)
            if (!compact) {
                views.setViewVisibility(R.id.hike_widget_weather_detail, View.VISIBLE)
                views.setTextViewText(
                    R.id.hike_widget_weather_detail,
                    "Departure to return · ${weather.optString("daylight")}",
                )
            }
            val updated = weather.optDouble("updated", 0.0)
            val status = if (now - updated >= 14400) "Outdated ·" else "Updated"
            views.setTextViewText(
                R.id.hike_widget_weather_footer,
                "$status ${formatClock(updated)}${if (compact) "" else " · Open-Meteo"}",
            )
        } else {
            val status = hike.optString("weatherStatus")
            views.setViewVisibility(R.id.hike_widget_weather_status, View.VISIBLE)
            views.setTextViewText(
                R.id.hike_widget_weather_status_title,
                when (status) {
                    "beyondRange", "incomplete" -> "Forecast available closer to departure"
                    "unavailable" -> "Forecast unavailable"
                    else -> "Open app to refresh forecast"
                },
            )
            views.setTextViewText(
                R.id.hike_widget_weather_status_detail,
                when (status) {
                    "beyondRange" -> "Forecasts cover up to 16 days ahead."
                    "unavailable" -> "Tap to retry in HikerCircle."
                    else -> "Weather for your scheduled hiking window."
                },
            )
            views.setTextViewText(
                R.id.hike_widget_weather_footer,
                "Tap to view hike weather →",
            )
        }
    }

    private fun formatDateTime(epoch: Double): String = SimpleDateFormat(
        "d MMM · HH:mm",
        Locale.getDefault(),
    ).format(Date((epoch * 1000).toLong()))

    private fun formatClock(epoch: Double): String = SimpleDateFormat(
        "HH:mm",
        Locale.getDefault(),
    ).format(Date((epoch * 1000).toLong()))

    companion object {
        fun publish(context: Context, snapshot: String) {
            JSONObject(snapshot) // Reject invalid JSON before replacing the last valid snapshot.
            context.getSharedPreferences("home_widgets", Context.MODE_PRIVATE)
                .edit()
                .putString("snapshot", snapshot)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            UpcomingHikesWidgetProvider().onUpdate(
                context,
                manager,
                manager.getAppWidgetIds(
                    ComponentName(context, UpcomingHikesWidgetProvider::class.java),
                ),
            )
            NextHikeWidgetProvider().onUpdate(
                context,
                manager,
                manager.getAppWidgetIds(
                    ComponentName(context, NextHikeWidgetProvider::class.java),
                ),
            )
            HikeWeatherWidgetProvider().onUpdate(
                context,
                manager,
                manager.getAppWidgetIds(
                    ComponentName(context, HikeWeatherWidgetProvider::class.java),
                ),
            )
        }
    }
}

class UpcomingHikesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        val now = System.currentTimeMillis() / 1000.0
        val hikes = visibleWidgetHikes(context, now)
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.upcoming_hikes_widget)
            val limit = if (context.resources.configuration.fontScale > 1.2f) 3 else 4
            val visible = hikes.take(limit)
            views.removeAllViews(R.id.upcoming_widget_rows)
            views.setTextViewText(R.id.upcoming_widget_count, "${hikes.size} planned")
            views.setViewVisibility(
                R.id.upcoming_widget_empty,
                if (hikes.isEmpty()) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.upcoming_widget_rows,
                if (hikes.isEmpty()) View.GONE else View.VISIBLE,
            )

            visible.forEachIndexed { index, hike ->
                val row = RemoteViews(
                    context.packageName,
                    R.layout.upcoming_hike_widget_row,
                )
                val date = Date((hike.optDouble("departure") * 1000).toLong())
                row.setTextViewText(
                    R.id.upcoming_row_month,
                    SimpleDateFormat("MMM", Locale.getDefault()).format(date),
                )
                row.setTextViewText(
                    R.id.upcoming_row_day,
                    SimpleDateFormat("d", Locale.getDefault()).format(date),
                )
                row.setTextViewText(R.id.upcoming_row_name, hike.optString("name"))
                row.setTextViewText(
                    R.id.upcoming_row_detail,
                    "${SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)}  ·  " +
                        "${String.format(Locale.getDefault(), "%.1f", hike.optDouble("distanceKm"))} km",
                )
                row.setViewVisibility(
                    R.id.upcoming_row_separator,
                    if (index == visible.lastIndex) View.GONE else View.VISIBLE,
                )
                val uri = Uri.parse("hikercircle://upcoming-hike/view")
                    .buildUpon()
                    .appendQueryParameter("upcomingHikeId", hike.optString("id"))
                    .build()
                row.setOnClickPendingIntent(
                    R.id.upcoming_row_root,
                    open(context, uri, id * 10 + index),
                )
                views.addView(R.id.upcoming_widget_rows, row)
            }

            views.setTextViewText(
                R.id.upcoming_widget_footer,
                if (hikes.size > limit) {
                    "+${hikes.size - limit} more · Open your hiking plans →"
                } else {
                    "Tap a hike to review preparation →"
                },
            )
            views.setOnClickPendingIntent(
                R.id.upcoming_widget_root,
                open(context, Uri.parse("hikercircle://hike/briefing"), id),
            )
            manager.updateAppWidget(id, views)
        }
    }

    private fun open(
        context: Context,
        uri: Uri,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
