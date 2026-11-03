// HikerCircleApplication initializes Firebase App Check before native services start.
package com.leongziqi.hikercircle

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.AppCheckProviderFactory
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory

/** Initialize before a service or headless isolate makes its first Firebase call. */
class HikerCircleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.CAPTURE_ONLY || FirebaseApp.initializeApp(this) == null) return
        val factory = if (BuildConfig.DEBUG || BuildConfig.DEVELOPMENT_ONLY_SIGNING) {
            Class.forName("com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory")
                .getMethod("getInstance").invoke(null) as AppCheckProviderFactory
        } else PlayIntegrityAppCheckProviderFactory.getInstance()
        val appCheck = FirebaseAppCheck.getInstance()
        appCheck.installAppCheckProviderFactory(factory)
        if (BuildConfig.DEVELOPMENT_ONLY_SIGNING) {
            // Verify private installations without sending OTPs or reading user
            // data. Never log the attestation token or its installation secret.
            appCheck.getAppCheckToken(false)
                .addOnSuccessListener {
                    Log.i("HikerCircleAppCheck", "Development app verification succeeded.")
                }
                .addOnFailureListener {
                    Log.w("HikerCircleAppCheck", "Development app verification unavailable.")
                }
        }
    }
}
