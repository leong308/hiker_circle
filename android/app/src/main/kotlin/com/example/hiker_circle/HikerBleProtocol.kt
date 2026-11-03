// HikerBleProtocol encodes and validates BLE pairing, location, log, and SOS packet fields.
package com.leongziqi.hikercircle

import android.bluetooth.le.ScanResult
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
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
    val PAIRED_BUTTON_SETUP_SERVICE_UUID: UUID =
        UUID.fromString("7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_PAIR_REQUEST_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d38-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_STATUS_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d39-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_LOG_CHALLENGE_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d3c-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_LOG_AUTH_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d3d-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_LOG_DATA_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d3e-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_LOG_PAGE_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d3f-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_MAINTENANCE_SERVICE_UUID: UUID =
        UUID.fromString("7e2a1d40-8b10-4f4d-9f78-0c6f1d65cba1")
    val PAIRED_BUTTON_TEST_CONTROL_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d41-8b10-4f4d-9f78-0c6f1d65cba1")
    val ACTIVE_SOS_SERVICE_UUID: UUID =
        UUID.fromString("7e2a1d3a-8b10-4f4d-9f78-0c6f1d65cba1")
    val SOS_LOCATION_CHARACTERISTIC_UUID: UUID =
        UUID.fromString("7e2a1d3b-8b10-4f4d-9f78-0c6f1d65cba1")
    const val MANUFACTURER_ID: Int = 0x02E5

    private const val MAGIC_H = 0x48.toByte()
    private const val MAGIC_C = 0x43.toByte()
    private const val VERSION = 1.toByte()
    private const val TYPE_SOS = 1.toByte()
    private const val TYPE_TEAM_LOCATION = 2.toByte()
    private const val TYPE_SOS_HELP = 3.toByte()
    const val TYPE_PAIRED_SOS_REMOTE = 4
    const val TYPE_PAIRED_SOS_LOCATION_RELAY = 5
    const val TYPE_PAIRED_BUTTON_SETUP_STATUS = 6
    const val SETUP_STATE_ADVERTISING = 1
    const val PAIRING_STATUS_READY = 1
    const val PAIRING_STATUS_AWAITING_CONFIRMATION = 2
    const val PAIRING_STATUS_PAIRED = 3
    const val PAIRING_STATUS_INVALID_REQUEST = 4
    const val PAIRING_STATUS_CONFIRMATION_EXPIRED = 5
    private const val LOG_CHALLENGE_TYPE = 0x10
    private const val LOG_DATA_TYPE = 0x12
    private const val LOG_CHALLENGE_BYTES = 26
    private const val LOG_RECORD_BYTES = 20

    fun decodePairedSosRemote(result: ScanResult): PairedSosRemotePacket? {
        val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID)
            ?: return null
        return decodePairedSosRemote(data, result.rssi)
    }

    fun decodePairedSosRemote(data: ByteArray, rssi: Int): PairedSosRemotePacket? {
        if (data.size != 23 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2].toInt() != 2 ||
            data[3].toInt() != TYPE_PAIRED_SOS_REMOTE ||
            data[4].toInt().and(0xff) !in 1..2
        ) {
            return null
        }
        val eventId = ByteBuffer.wrap(data, 11, 4)
            .order(ByteOrder.BIG_ENDIAN)
            .int
            .toLong()
            .and(0xffffffffL)
        return PairedSosRemotePacket(
            deviceId = data.copyOfRange(5, 11),
            eventId = eventId,
            mode = data[4].toInt().and(0xff),
            messageTag = data.copyOfRange(15, 23),
            signedPayload = data.copyOfRange(0, 15),
            rssi = rssi,
        )
    }

    fun encodePairedButtonTestArm(
        challenge: ByteArray,
        pairingSecret: ByteArray,
        expectedDeviceId: ByteArray,
    ): ByteArray? {
        if (challenge.size != 22 || pairingSecret.size != 32 || expectedDeviceId.size != 6 ||
            challenge[0] != MAGIC_H || challenge[1] != MAGIC_C ||
            challenge[2].toInt().and(0xff) != 1 ||
            challenge[3].toInt().and(0xff) != 0x13 ||
            !challenge.copyOfRange(4, 10).contentEquals(expectedDeviceId)
        ) return null
        val tag = Mac.getInstance("HmacSHA256")
            .apply { init(SecretKeySpec(pairingSecret, "HmacSHA256")) }
            .doFinal(challenge)
            .copyOfRange(0, 8)
        return challenge + tag
    }

    /**
     * Type-5 is emitted by the button only after it has accepted an
     * authenticated owner-phone location handoff. Nearby phones do not have
     * the pairing secret, so this packet is a proximity/location signal and
     * must not be treated as proof of ownership.
     *
     * Layout (24 bytes after the company ID): HC, v2, type, device ID (6),
     * event ID (4), latitude/longitude E7 (4 each), accuracy decimetres (2).
     * The captured-at timestamp is authenticated in the GATT handoff but is
     * omitted here so the packet fits the legacy 31-byte advertisement limit.
     */
    fun decodePairedSosLocationRelay(result: ScanResult): PairedSosLocationRelayPacket? {
        val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID)
            ?: return null
        return decodePairedSosLocationRelay(data, result.rssi)
    }

    fun decodePairedSosLocationRelay(
        data: ByteArray,
        rssi: Int,
    ): PairedSosLocationRelayPacket? {
        if (data.size != 24 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2].toInt() != 2 ||
            data[3].toInt() != TYPE_PAIRED_SOS_LOCATION_RELAY
        ) {
            return null
        }
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        val latitude = buffer.getInt(14) / 10_000_000.0
        val longitude = buffer.getInt(18) / 10_000_000.0
        if (!isValidCoordinate(latitude, longitude)) return null
        return PairedSosLocationRelayPacket(
            deviceId = data.copyOfRange(4, 10),
            eventId = buffer.getInt(10).toLong().and(0xffffffffL),
            latitude = latitude,
            longitude = longitude,
            accuracyMeters = buffer.getShort(22).toInt().and(0xFFFF) / 10.0,
            rssi = rssi,
        )
    }

    fun encodePairRequest(deviceId: ByteArray, pairingSecret: ByteArray): ByteArray {
        require(deviceId.size == 6) { "Paired button device IDs must be six bytes." }
        require(pairingSecret.size == 32) { "Paired button secrets must be 32 bytes." }
        return ByteBuffer.allocate(42)
            .put(MAGIC_H)
            .put(MAGIC_C)
            .put(VERSION)
            .put(TYPE_SOS)
            .put(deviceId)
            .put(pairingSecret)
            .array()
    }

    fun encodeSosLocationHandoff(
        eventId: Long,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
        capturedAtMillis: Long,
        pairingSecret: ByteArray,
    ): ByteArray {
        require(pairingSecret.size == 32) { "Paired button secrets must be 32 bytes." }
        requireValidLocation(latitude, longitude, accuracyMeters)
        val accuracyDecimeters = accuracyDecimeters(accuracyMeters)
        val signed = ByteBuffer.allocate(22)
            .order(ByteOrder.BIG_ENDIAN)
            .put(MAGIC_H)
            .put(MAGIC_C)
            .put(2.toByte())
            .put(TYPE_PAIRED_SOS_LOCATION_RELAY.toByte())
            .putInt(eventId.toInt())
            .putInt((latitude * 10_000_000).roundToInt())
            .putInt((longitude * 10_000_000).roundToInt())
            .putShort(accuracyDecimeters.toShort())
            .putInt((capturedAtMillis / 1000L).toInt())
            .array()
        val tag = Mac.getInstance("HmacSHA256")
            .apply { init(SecretKeySpec(pairingSecret, "HmacSHA256")) }
            .doFinal(signed)
            .copyOfRange(0, 8)
        return signed + tag
    }

    fun decodePairingStatus(data: ByteArray): PairingStatus? {
        if (data.size != 10 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2] != VERSION
        ) {
            return null
        }
        return PairingStatus(
            status = data[3].toInt().and(0xff),
            deviceId = data.copyOfRange(4, 10),
        )
    }

    /**
     * Optional setup-mode advertisement emitted alongside the setup service
     * UUID. The six-byte payload is intentionally small enough to coexist
     * with a 128-bit service UUID in a legacy 31-byte advertisement.
     */
    fun decodePairedButtonSetupStatus(data: ByteArray?): PairedButtonSetupStatus? {
        if (data == null ||
            data.size != 6 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2] != VERSION ||
            data[3].toInt().and(0xff) != TYPE_PAIRED_BUTTON_SETUP_STATUS
        ) {
            return null
        }
        return PairedButtonSetupStatus(
            state = data[4].toInt().and(0xff),
            remainingSeconds = data[5].toInt().and(0xff),
        )
    }

    fun encodeLogAuthentication(
        challenge: ByteArray,
        deviceId: ByteArray,
        pairingSecret: ByteArray,
    ): ByteArray {
        require(challenge.size == LOG_CHALLENGE_BYTES) {
            "The SOS button returned an invalid log challenge " +
                "(expected $LOG_CHALLENGE_BYTES bytes, received ${challenge.size})."
        }
        require(deviceId.size == 6) { "Paired button device IDs must be six bytes." }
        require(pairingSecret.size == 32) { "Paired button secrets must be 32 bytes." }
        require(
            challenge[0] == MAGIC_H &&
                challenge[1] == MAGIC_C &&
                challenge[2] == VERSION &&
                challenge[3].toInt().and(0xff) == LOG_CHALLENGE_TYPE &&
                challenge.copyOfRange(4, 10).contentEquals(deviceId),
        ) {
            "The log challenge belongs to a different SOS button."
        }
        val tag = Mac.getInstance("HmacSHA256")
            .apply { init(SecretKeySpec(pairingSecret, "HmacSHA256")) }
            .doFinal(challenge)
            .copyOfRange(0, 8)
        // The button already owns this fresh challenge. Sending only its tag
        // keeps authentication inside one conservative ATT packet; firmware
        // still accepts the original challenge+tag format for older clients.
        return tag
    }

    fun decodeLogPage(data: ByteArray): LogPage? {
        if (data.size < 8 ||
            data[0] != MAGIC_H ||
            data[1] != MAGIC_C ||
            data[2] != VERSION ||
            data[3].toInt().and(0xff) != LOG_DATA_TYPE ||
            data[4].toInt().and(0xff) != LOG_RECORD_BYTES
        ) {
            return null
        }
        val totalCount = data[5].toInt().and(0xff)
        val pageIndex = data[6].toInt().and(0xff)
        val recordCount = data[7].toInt().and(0xff)
        if (totalCount > 32 ||
            recordCount > 8 ||
            data.size != 8 + recordCount * LOG_RECORD_BYTES
        ) {
            return null
        }
        val buffer = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        val records = buildList {
            repeat(recordCount) { index ->
                val offset = 8 + index * LOG_RECORD_BYTES
                add(
                    LogRecord(
                        sequence = buffer.getInt(offset).toLong().and(0xffffffffL),
                        uptimeMillis = buffer.getInt(offset + 4).toLong().and(0xffffffffL),
                        epochSeconds = buffer.getInt(offset + 8).toLong().and(0xffffffffL),
                        eventId = buffer.getInt(offset + 12).toLong().and(0xffffffffL),
                        type = data[offset + 16].toInt().and(0xff),
                        resetReason = data[offset + 17].toInt().and(0xff),
                        detail = buffer.getShort(offset + 18).toInt().and(0xffff),
                    ),
                )
            }
        }
        return LogPage(
            totalCount = totalCount,
            pageIndex = pageIndex,
            records = records,
        )
    }


    fun decodeSosHelpBeacon(result: ScanResult): SosHelpBeaconPacket? {
        val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID)
            ?: return null
        return decodeSosHelpBeacon(data, result.rssi)
    }

    fun decodeSosHelpBeacon(data: ByteArray, rssi: Int): SosHelpBeaconPacket? {
        if (data.size != 22 ||
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
        val capturedAtMillis = buffer.int.toLong().and(0xffffffffL) * 1000L
        if (!isValidCoordinate(latitude, longitude)) return null
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
        requireValidLocation(latitude, longitude, accuracyMeters)
        val accuracyDecimeters = accuracyDecimeters(accuracyMeters)
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
        if (data.size != 26 ||
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
        val capturedAtMillis = buffer.int.toLong().and(0xffffffffL) * 1000L
        if (!isValidCoordinate(latitude, longitude)) return null
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

    private fun requireValidLocation(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
    ) {
        require(isValidCoordinate(latitude, longitude)) {
            "BLE location coordinates are invalid."
        }
        require(accuracyMeters == null || (accuracyMeters.isFinite() && accuracyMeters >= 0.0)) {
            "BLE location accuracy is invalid."
        }
    }

    private fun isValidCoordinate(latitude: Double, longitude: Double): Boolean =
        latitude.isFinite() && longitude.isFinite() &&
            latitude in -90.0..90.0 && longitude in -180.0..180.0

    private fun accuracyDecimeters(accuracyMeters: Double?): Int =
        ((accuracyMeters ?: 0.0) * 10).roundToInt().coerceIn(0, 65535)

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

    data class PairedSosRemotePacket(
        val deviceId: ByteArray,
        val eventId: Long,
        val mode: Int,
        val messageTag: ByteArray,
        // Bytes 0-14 are the exact authenticated HMAC input. Do not log this
        // alongside pairing data; it is retained only for verification.
        val signedPayload: ByteArray,
        val rssi: Int,
    ) {
        val deviceIdHex: String
            get() = deviceId.joinToString("") { "%02X".format(it.toInt().and(0xff)) }
    }

    data class PairedSosLocationRelayPacket(
        val deviceId: ByteArray,
        val eventId: Long,
        val latitude: Double,
        val longitude: Double,
        val accuracyMeters: Double,
        val rssi: Int,
    ) {
        val deviceIdHex: String
            get() = deviceId.joinToString("") { "%02X".format(it.toInt().and(0xff)) }
    }

    data class PairingStatus(
        val status: Int,
        val deviceId: ByteArray,
    )

    data class PairedButtonSetupStatus(
        val state: Int,
        val remainingSeconds: Int,
    )

    data class LogRecord(
        val sequence: Long,
        val uptimeMillis: Long,
        val epochSeconds: Long,
        val eventId: Long,
        val type: Int,
        val resetReason: Int,
        val detail: Int,
    ) {
        fun toPlatformMap(): Map<String, Any> = mapOf(
            "sequence" to sequence,
            "uptimeMillis" to uptimeMillis,
            "epochSeconds" to epochSeconds,
            "eventId" to eventId,
            "type" to type,
            "resetReason" to resetReason,
            "detail" to detail,
        )
    }

    data class LogPage(
        val totalCount: Int,
        val pageIndex: Int,
        val records: List<LogRecord>,
    )

}
