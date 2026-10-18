// HikerCircleApplication initializes Firebase App Check before native services start.
package com.leongziqi.hikercircle

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.AppCheckProviderFactory
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory

/** Initialize before a service or headless isolate makes its first Firebase call. */
class HikerCircleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.CAPTURE_ONLY || FirebaseApp.initializeApp(this) == null) return
        val factory = if (BuildConfig.DEBUG) {
            Class.forName("com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory")
                .getMethod("getInstance").invoke(null) as AppCheckProviderFactory
        } else PlayIntegrityAppCheckProviderFactory.getInstance()
        FirebaseAppCheck.getInstance().installAppCheckProviderFactory(factory)
    }
}
