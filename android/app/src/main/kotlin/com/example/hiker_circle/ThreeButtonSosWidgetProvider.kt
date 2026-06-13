package com.leongziqi.hikercircle

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

class ThreeButtonSosWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, viewsFor(context, appWidgetId))
        }
    }

    private fun viewsFor(context: Context, appWidgetId: Int): RemoteViews {
        return RemoteViews(context.packageName, R.layout.three_button_sos_widget).apply {
            setOnClickPendingIntent(
                R.id.instant_sos_widget_button,
                pendingIntentFor(
                    context = context,
                    requestCode = appWidgetId * 10 + 1,
                    uri = "hikercircle://sos/instant?source=android_actions_widget",
                ),
            )
            setOnClickPendingIntent(
                R.id.medical_sos_widget_button,
                pendingIntentFor(
                    context = context,
                    requestCode = appWidgetId * 10 + 2,
                    uri = "hikercircle://sos/medical?source=android_actions_widget",
                ),
            )
            setOnClickPendingIntent(
                R.id.duress_sos_widget_button,
                pendingIntentFor(
                    context = context,
                    requestCode = appWidgetId * 10 + 3,
                    uri = "hikercircle://sos/duress?source=android_actions_widget",
                ),
            )
        }
    }

    private fun pendingIntentFor(
        context: Context,
        requestCode: Int,
        uri: String,
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse(uri)
            setPackage(context.packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }

        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }
}
