// MobileSecurityBridge exposes device identity and password-page capture protection to Flutter.
package com.leongziqi.hikercircle

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MobileSecurityBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val io = Executors.newSingleThreadExecutor()
    private val protectedRoutes = mutableSetOf<String>()
    init {
        MethodChannel(messenger, "hiker_circle/security").setMethodCallHandler { call, result ->
            when (call.method) {
                "deviceInfo" -> result.success(mapOf("name" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(), "platform" to "android"))
                "databaseKey" -> io.execute {
                    try {
                        val key = LocalDatabaseKeyStore.key(activity, call.argument<String>("name") ?: "")
                        activity.runOnUiThread { result.success(key) }
                    } catch (_: Throwable) {
                        activity.runOnUiThread { result.error("database-key-unavailable", "The protected local database key is unavailable.", null) }
                    }
                }
                "protectPasswordPage" -> {
                    val route = call.argument<String>("route") ?: ""
                    if (call.argument<Boolean>("enabled") == true) protectedRoutes.add(route) else protectedRoutes.remove(route)
                    if (protectedRoutes.isNotEmpty()) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "passwordProtectionState" -> result.success(protectedRoutes.isNotEmpty() &&
                    activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
                else -> result.notImplemented()
            }
        }
    }
}
