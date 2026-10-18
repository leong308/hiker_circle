// LocalDatabaseKeyStore shares protected SQLCipher keys with native and Flutter workers.
package com.leongziqi.hikercircle

import android.content.Context

/** Random database keys, wrapped by a non-exportable Android Keystore key. */
object LocalDatabaseKeyStore {
    fun key(context: Context, name: String): String =
        com.hikercircle.securitybridge.DatabaseKeys.key(context, name)
}
