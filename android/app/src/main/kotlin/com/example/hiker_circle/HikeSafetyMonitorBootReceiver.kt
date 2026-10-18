// HikeSafetyMonitorBootReceiver restores configured safety monitoring after Android restarts.
package com.leongziqi.hikercircle

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class HikeSafetyMonitorBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
            intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        HikeSafetyMonitorService.restartIfConfigured(context)
    }
}
