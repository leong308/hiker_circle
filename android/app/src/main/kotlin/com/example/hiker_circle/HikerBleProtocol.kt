package com.leongziqi.hikercircle

import android.bluetooth.le.ScanResult
import android.os.ParcelUuid
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.math.roundToInt

object HikerBleProtocol {
    val SOS_SERVICE_UUID: UUID = UUID.fromString("7e2a1d32-8b10-4f4d-9f78-0c6f1d65cba1")
    val TEAM_LOCATION_SERVICE_UUID: UUID =
        UUID.fromString("7e2a1d33-8b10-4f4d-9f78-0c6f1d65cba1")
    val SOS_HELP_SERVICE_UUID: UUID = UUID.fromString("7e2a1d34-8b10-4f4d-9f78-0c6f1d65cba1")
    val SOS_HELP_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d35-8b10-4f4d-9f78-0c6f1d65cba1")
    val TEAM_LOCATION_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d36-8b10-4f4d-9f78-0c6f1d65cba1")
    const val MANUFACTURER_ID: Int = 0x02E5

    private const val MAGIC_H = 0x48.toByte()
    private const val MAGIC_C = 0x43.toByte()
    private const val VERSION = 1.toByte()
    private const val TYPE_SOS = 1.toByte()
    private const val TYPE_TEAM_LOCATION = 2.toByte()
    private const val TYPE_SOS_HELP = 3.toByte()

    fun isSosAdvertisement(result: ScanResult): Boolean {
        val record = result.scanRecord ?: return false
        val hasService = record.serviceUuids
            ?.contains(ParcelUuid(SOS_SERVICE_UUID)) == true
        val manufacturerData = record.getManufacturerSpecificData(MANUFACTURER_ID)
        val hasPacket = manufacturerData?.let(::isSosPacket) == true
        return hasService || hasPacket
    }

    fun sosEventIdFrom(result: ScanResult): Long? {
        val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID)
            ?: return null
        if (!isSosPacket(data) || data.size < 9) {
            return null
        }
        return ByteBuffer.wrap(data, 5, 4)
            .order(ByteOrder.BIG_ENDIAN)
            .int
            .toLong()
            .and(0xffffffffL)
    }

    private fun isSosPacket(data: ByteArray): Boolean {
        return data.size >= 4 &&
            data[0] == MAGIC_H &&
            data[1] == MAGIC_C &&
            data[2] == VERSION &&
            data[3] == TYPE_SOS
    }

    fun encodeSosHelpBeacon(
        phoneNumberHash: Long,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
        capturedAtMillis: Long,
    ): ByteArray {
        val accuracyDecimeters = ((accuracyMeters ?: 0.0) * 10)
            .roundToInt()
            .coerceIn(0, 65535)
        return ByteBuffer.allocate(22)
            .order(ByteOrder.BIG_ENDIAN)
            .put(MAGIC_H)
            .put(MAGIC_C)
            .put(VERSION)
            .put(TYPE_SOS_HELP)
            .putInt(phoneNumberHash.toInt())
            .putInt((latitude * 10_000_000).roundToInt())
            .putInt((longitude * 10_000_000).roundToInt())
            .putShort(accuracyDecimeters.toShort())
            .putInt((capturedAtMillis / 1000L).toInt())
            .array()
    }

    fun decodeSosHelpBeacon(result: ScanResult): SosHelpBeaconPacket? {
        val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID)
            ?: return null
        return decodeSosHelpBeacon(data, result.rssi)
    }

    fun decodeSosHelpBeacon(data: ByteArray, rssi: Int): SosHelpBeaconPacket? {
        if (data.size < 22 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2] != VERSION ||
            data[3] != TYPE_SOS_HELP
        ) {
            return null
        }
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        buffer.position(4)
        val phoneHash = buffer.int.toLong().and(0xffffffffL)
        val latitude = buffer.int / 10_000_000.0
        val longitude = buffer.int / 10_000_000.0
        val accuracy = buffer.short.toInt().and(0xFFFF) / 10.0
        val capturedAtMillis = buffer.int.toLong() * 1000L
        return SosHelpBeaconPacket(
            phoneNumberHash = phoneHash,
            latitude = latitude,
            longitude = longitude,
            accuracyMeters = accuracy,
            capturedAtMillis = capturedAtMillis,
            rssi = rssi,
        )
    }

    fun encodeTeamLocation(
        teamSessionHash: Long,
        phoneNumberHash: Long,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
        capturedAtMillis: Long,
    ): ByteArray {
        val accuracyDecimeters = ((accuracyMeters ?: 0.0) * 10)
            .roundToInt()
            .coerceIn(0, 65535)
        return ByteBuffer.allocate(26)
            .order(ByteOrder.BIG_ENDIAN)
            .put(MAGIC_H)
            .put(MAGIC_C)
            .put(VERSION)
            .put(TYPE_TEAM_LOCATION)
            .putInt(teamSessionHash.toInt())
            .putInt(phoneNumberHash.toInt())
            .putInt((latitude * 10_000_000).roundToInt())
            .putInt((longitude * 10_000_000).roundToInt())
            .putShort(accuracyDecimeters.toShort())
            .putInt((capturedAtMillis / 1000L).toInt())
            .array()
    }

    fun decodeTeamLocation(result: ScanResult): TeamLocationPacket? {
        val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID)
            ?: return null
        return decodeTeamLocation(data, result.rssi)
    }

    fun decodeTeamLocation(data: ByteArray, rssi: Int): TeamLocationPacket? {
        if (data.size < 26 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2] != VERSION ||
            data[3] != TYPE_TEAM_LOCATION
        ) {
            return null
        }
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        buffer.position(4)
        val teamHash = buffer.int.toLong().and(0xffffffffL)
        val phoneHash = buffer.int.toLong().and(0xffffffffL)
        val latitude = buffer.int / 10_000_000.0
        val longitude = buffer.int / 10_000_000.0
        val accuracy = buffer.short.toInt().and(0xFFFF) / 10.0
        val capturedAtMillis = buffer.int.toLong() * 1000L
        return TeamLocationPacket(
            teamSessionHash = teamHash,
            phoneNumberHash = phoneHash,
            latitude = latitude,
            longitude = longitude,
            accuracyMeters = accuracy,
            capturedAtMillis = capturedAtMillis,
            rssi = rssi,
        )
    }

    fun hash(value: String): Long {
        var hash = 0x811c9dc5L
        for (byte in value.trim().lowercase().toByteArray(Charsets.UTF_8)) {
            hash = hash xor byte.toLong().and(0xff)
            hash = (hash * 0x01000193L).and(0xffffffffL)
        }
        return hash
    }

    fun phoneHash(phoneNumber: String): Long {
        return hash(phoneNumber.filter { it.isDigit() })
    }

    data class TeamLocationPacket(
        val teamSessionHash: Long,
        val phoneNumberHash: Long,
        val latitude: Double,
        val longitude: Double,
        val accuracyMeters: Double,
        val capturedAtMillis: Long,
        val rssi: Int,
    )

    data class SosHelpBeaconPacket(
        val phoneNumberHash: Long,
        val latitude: Double,
        val longitude: Double,
        val accuracyMeters: Double,
        val capturedAtMillis: Long,
        val rssi: Int,
    )
}
