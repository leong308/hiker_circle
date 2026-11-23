// NativeLocationSampleBuffer keeps GPS samples until both local import and cloud acknowledgement.
package com.leongziqi.hikercircle

import android.content.ContentValues
import android.content.Context
import net.zetetic.database.sqlcipher.SQLiteDatabase
import net.zetetic.database.sqlcipher.SQLiteOpenHelper
import android.location.Location

/** Durable transfer queue. A cloud acknowledgement never removes an unimported local sample. */
class NativeLocationSampleBuffer(context: Context) :
    SQLiteOpenHelper(context.applicationContext, NativeLocationCipher.NAME,
        NativeLocationCipher.password(context), null, 1, 0, NativeLocationCipher.preserveOnError, null, true) {
    init { setWriteAheadLoggingEnabled(true) }

    // Update local: create GPS sample table and index
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE samples (
                sample_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, owner_uid TEXT NOT NULL,
                sampled_at INTEGER NOT NULL, captured_at INTEGER NOT NULL,
                latitude REAL NOT NULL, longitude REAL NOT NULL, accuracy REAL NOT NULL,
                altitude REAL, speed REAL, local_transferred INTEGER NOT NULL DEFAULT 0,
                cloud_acknowledged INTEGER NOT NULL DEFAULT 0
            )
        """.trimIndent())
        db.execSQL("CREATE INDEX samples_session_time ON samples(session_id, owner_uid, sampled_at)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    // pendingSessions: List only this account's sessions still awaiting the selected acknowledgement.
    fun pendingSessions(ownerUid: String, forCloud: Boolean = false): List<String> {
        if (ownerUid.isBlank()) return emptyList()
        val flag = if (forCloud) "cloud_acknowledged" else "local_transferred"
        // Query local: pending GPS sessions
        return readableDatabase.rawQuery(
            "SELECT session_id FROM samples WHERE owner_uid=? AND $flag=0 GROUP BY session_id ORDER BY MIN(sampled_at)",
            arrayOf(ownerUid),
        ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
    }

    // remapSession: Move provisional session samples without transferring the old cloud acknowledgement.
    fun remapSession(oldSessionId: String, newSessionId: String, ownerUid: String): Int {
        require(oldSessionId.isNotBlank() && newSessionId.isNotBlank() && ownerUid.isNotBlank())
        if (oldSessionId == newSessionId) return 0
        val db = writableDatabase
        var moved = 0
        db.beginTransaction()
        try {
            // Query local: GPS samples under provisional ID
            db.query("samples", null, "session_id=? AND owner_uid=?", arrayOf(oldSessionId, ownerUid), null, null, null).use { cursor ->
                while (cursor.moveToNext()) {
                    val sampledAt = cursor.getLong(cursor.getColumnIndexOrThrow("sampled_at"))
                    val id = "$newSessionId:$sampledAt"
                    val transferred = cursor.getInt(cursor.getColumnIndexOrThrow("local_transferred"))
                    val values = ContentValues().apply {
                        put("sample_id", id); put("session_id", newSessionId); put("owner_uid", ownerUid)
                        put("sampled_at", sampledAt)
                        put("captured_at", cursor.getLong(cursor.getColumnIndexOrThrow("captured_at")))
                        for (column in listOf("latitude", "longitude", "accuracy", "altitude", "speed")) {
                            val index = cursor.getColumnIndexOrThrow(column)
                            if (!cursor.isNull(index)) put(column, cursor.getDouble(index))
                        }
                        put("local_transferred", transferred)
                        // A server acknowledgement for the old session does not acknowledge the new one.
                        put("cloud_acknowledged", 0)
                    }
                    // Update local: copy samples to confirmed session
                    db.insertWithOnConflict("samples", null, values, SQLiteDatabase.CONFLICT_IGNORE)
                    db.execSQL("UPDATE samples SET local_transferred=MAX(local_transferred, ?) WHERE sample_id=? AND owner_uid=?", arrayOf(transferred, id, ownerUid))
                    // Query local: copied GPS sample
                    db.rawQuery("SELECT 1 FROM samples WHERE sample_id=? AND owner_uid=?", arrayOf(id, ownerUid)).use {
                        check(it.moveToFirst()) { "The target GPS session belongs to another account." }
                    }
                    moved += 1
                }
            }
            // Update local: remove old session samples
            db.delete("samples", "session_id=? AND owner_uid=?", arrayOf(oldSessionId, ownerUid))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return moved
    }

    fun append(sessionId: String, ownerUid: String, sampledAt: Long, location: Location) {
        require(sessionId.isNotBlank() && ownerUid.isNotBlank())
        val values = ContentValues().apply {
            put("sample_id", "$sessionId:$sampledAt")
            put("session_id", sessionId)
            put("owner_uid", ownerUid)
            put("sampled_at", sampledAt)
            put("captured_at", location.time)
            put("latitude", location.latitude)
            put("longitude", location.longitude)
            put("accuracy", location.accuracy.toDouble())
            if (location.hasAltitude() && location.altitude.isFinite() && location.altitude in -1000.0..100000.0) put("altitude", location.altitude)
            if (location.hasSpeed() && location.speed.isFinite() && location.speed >= 0f) put("speed", location.speed.toDouble())
        }
        // Update local: insert unique GPS sample
        writableDatabase.insertWithOnConflict("samples", null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }

    // pending: Read an ordered, bounded batch for local import or footprint upload.
    fun pending(sessionId: String, ownerUid: String, limit: Int = 500, forCloud: Boolean = false): List<Map<String, Any>> {
        if (sessionId.isBlank() || ownerUid.isBlank()) return emptyList()
        val flag = if (forCloud) "cloud_acknowledged" else "local_transferred"
        // Query local: pending GPS samples by time
        return readableDatabase.query(
            "samples", null, "session_id = ? AND owner_uid = ? AND $flag = 0",
            arrayOf(sessionId, ownerUid), null, null, "sampled_at ASC", limit.coerceIn(1, 500).toString(),
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(buildMap {
                        put("sampleId", cursor.getString(cursor.getColumnIndexOrThrow("sample_id")))
                        put("sessionId", cursor.getString(cursor.getColumnIndexOrThrow("session_id")))
                        put("sampledAtMillis", cursor.getLong(cursor.getColumnIndexOrThrow("sampled_at")))
                        put("capturedAtMillis", cursor.getLong(cursor.getColumnIndexOrThrow("captured_at")))
                        put("latitude", cursor.getDouble(cursor.getColumnIndexOrThrow("latitude")))
                        put("longitude", cursor.getDouble(cursor.getColumnIndexOrThrow("longitude")))
                        put("accuracyMeters", cursor.getDouble(cursor.getColumnIndexOrThrow("accuracy")))
                        put("cloudAcknowledged", cursor.getInt(cursor.getColumnIndexOrThrow("cloud_acknowledged")) == 1)
                        val altitude = cursor.getColumnIndexOrThrow("altitude")
                        val speed = cursor.getColumnIndexOrThrow("speed")
                        if (!cursor.isNull(altitude)) put("altitudeMeters", cursor.getDouble(altitude))
                        if (!cursor.isNull(speed)) put("speedMetersPerSecond", cursor.getDouble(speed))
                    })
                }
            }
        }
    }

    // acknowledge: Delete samples only after both local import and cloud upload have acknowledged them.
    fun acknowledge(sessionId: String, ownerUid: String, sampleIds: List<String>, cloud: Boolean = false): Int {
        if (sessionId.isBlank() || ownerUid.isBlank() || sampleIds.isEmpty()) return 0
        val db = writableDatabase
        var changed = 0
        db.beginTransaction()
        try {
            for (ids in sampleIds.distinct().chunked(400)) {
                val where = "session_id = ? AND owner_uid = ? AND sample_id IN (${ids.joinToString(",") { "?" }})"
                val args = (listOf(sessionId, ownerUid) + ids).toTypedArray()
                // Update local: acknowledge GPS sample transfer
                changed += db.update("samples", ContentValues().apply {
                    put(if (cloud) "cloud_acknowledged" else "local_transferred", 1)
                }, where, args)
            }
            // Update local: remove fully acknowledged samples
            db.delete("samples", "local_transferred = 1 AND cloud_acknowledged = 1", null)
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return changed
    }
}
