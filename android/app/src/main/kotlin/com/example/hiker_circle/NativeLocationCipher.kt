// NativeLocationCipher preserves GPS rows while migrating the native buffer to SQLCipher.
package com.leongziqi.hikercircle

import android.content.Context
import android.database.sqlite.SQLiteException
import net.zetetic.database.DatabaseErrorHandler
import net.zetetic.database.sqlcipher.SQLiteDatabase
import java.io.File

object NativeLocationCipher {
    const val NAME = "native_hike_locations_encrypted.db"
    val preserveOnError = object : DatabaseErrorHandler {
        override fun onCorruption(db: SQLiteDatabase, exception: SQLiteException) { throw exception }
    }

    @Synchronized fun password(context: Context): String {
        System.loadLibrary("sqlcipher")
        val key = LocalDatabaseKeyStore.key(context, "native-location")
        val original = context.getDatabasePath("native_hike_locations.db")
        val target = context.getDatabasePath(NAME)
        if (target.exists()) {
            SQLiteDatabase.openDatabase(target.path, key, null, SQLiteDatabase.OPEN_READONLY, preserveOnError, null).use {
                it.rawQuery("SELECT count(*) FROM sqlite_master", emptyArray<String>()).use { cursor -> check(cursor.moveToFirst()) }
            }
            removePlainSource(original)
            return key
        }
        if (!original.exists()) return key
        val pending = File(target.path + ".pending")
        if (pending.exists()) check(pending.delete())
        SQLiteDatabase.openDatabase(original.path, "", null, SQLiteDatabase.OPEN_READWRITE, preserveOnError, null).use { source ->
            source.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", emptyArray<String>()).use { it.moveToFirst() }
            val version = source.version
            source.execSQL("ATTACH DATABASE ? AS encrypted KEY ?", arrayOf(pending.path, key))
            source.rawQuery("SELECT sqlcipher_export('encrypted')", emptyArray<String>()).use { it.moveToFirst() }
            source.execSQL("PRAGMA encrypted.user_version=$version")
            source.execSQL("DETACH DATABASE encrypted")
        }
        SQLiteDatabase.openDatabase(pending.path, key, null, SQLiteDatabase.OPEN_READONLY, preserveOnError, null).use {
            it.rawQuery("PRAGMA integrity_check", emptyArray<String>()).use { cursor ->
                check(cursor.moveToFirst() && cursor.getString(0) == "ok")
            }
        }
        check(pending.renameTo(target)) { "Unable to commit encrypted GPS migration." }
        removePlainSource(original)
        return key
    }

    private fun removePlainSource(original: File) {
        for (suffix in listOf("", "-wal", "-shm", "-journal")) {
            val file = File(original.path + suffix)
            if (file.exists()) check(file.delete()) { "Unable to remove migrated GPS plaintext." }
        }
    }
}
