// ManualSosWidgetProvider opens the manual SOS flow from the Android home screen.
package com.leongziqi.hikercircle

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

class ManualSosWidgetProvider : AppWidgetProvider() {
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
        val sosIntent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("hikercircle://sos/manual?source=android_widget")
            setPackage(context.packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            sosIntent,
            flags,
        )

        return RemoteViews(context.packageName, R.layout.manual_sos_widget).apply {
            setOnClickPendingIntent(R.id.manual_sos_widget_root, pendingIntent)
            setOnClickPendingIntent(R.id.manual_sos_widget_button, pendingIntent)
        }
    }
}
