// HikerCircleApplication initializes Firebase before native services start.
package com.leongziqi.hikercircle

import android.app.Application
import com.google.firebase.FirebaseApp

/** Initialize before a service or headless isolate makes its first Firebase call. */
class HikerCircleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (!BuildConfig.CAPTURE_ONLY) FirebaseApp.initializeApp(this)
    }
}
