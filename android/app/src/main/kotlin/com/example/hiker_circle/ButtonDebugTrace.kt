// ButtonDebugTrace mirrors real BLE packets to diagnostics without consuming SOS events.
package com.leongziqi.hikercircle

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.le.ScanResult
import android.os.Handler
import android.os.Looper

/** In-process tap shared by the Flutter bridge and the SOS foreground service.
 * Never changes a BLE packet, persists a secret, or consumes an SOS event. */
internal object ButtonDebugTrace {
    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var listener: ((Map<String, Any>) -> Unit)? = null

    fun start(sink: (Map<String, Any>) -> Unit) { listener = sink }
    fun stop() { listener = null }

    fun packet(direction: String, operation: String, device: String = "",
               characteristic: String = "", bytes: ByteArray = byteArrayOf(),
               status: String = "", message: String = "") {
        val sink = listener ?: return
        val safe = bytes.copyOf()
        val redacted = characteristic.startsWith("7e2a1d38", ignoreCase = true)
        if (redacted) for (i in 10 until safe.size) safe[i] = 0
        val event = mapOf<String, Any>(
            "type" to "buttonDebug", "timestampMillis" to System.currentTimeMillis(),
            "direction" to direction, "operation" to operation, "deviceId" to device,
            "characteristic" to characteristic, "bytes" to safe,
            "status" to status, "message" to if (redacted) "$message Pairing secret redacted before capture." else message,
        )
        handler.post { if (listener === sink) sink(event) }
    }

    @Suppress("MissingPermission")
    fun gatt(direction: String, operation: String, gatt: BluetoothGatt,
             characteristic: BluetoothGattCharacteristic, bytes: ByteArray = byteArrayOf(),
             status: String = "") {
        if (listener == null) return
        packet(direction, operation, runCatching { gatt.device.address }.getOrDefault(""),
            characteristic.uuid.toString(), bytes, status)
    }

    @Suppress("MissingPermission")
    fun read(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic): Boolean {
        this.gatt("TX", "read_request", gatt, characteristic)
        val accepted = gatt.readCharacteristic(characteristic)
        this.gatt("LOCAL", "read_queued", gatt, characteristic, status = accepted.toString())
        return accepted
    }

    @Suppress("MissingPermission")
    fun advertisement(result: ScanResult) {
        if (listener == null) return
        val record = result.scanRecord ?: return
        val device = runCatching { result.device.address }.getOrDefault("")
        record.getManufacturerSpecificData(HikerBleProtocol.MANUFACTURER_ID)?.let {
            packet("RX", "advertisement", device, "manufacturer:0x02E5", it,
                message = "RSSI=${result.rssi} dBm; company ID excluded from payload")
        }
        record.serviceData?.forEach { (uuid, data) ->
            if (uuid.toString().startsWith("7e2a1d", ignoreCase = true)) {
                packet("RX", "service_advertisement", device, uuid.toString(), data,
                    message = "RSSI=${result.rssi} dBm")
            }
        }
        if (record.getManufacturerSpecificData(HikerBleProtocol.MANUFACTURER_ID) == null &&
            record.serviceUuids?.any { it.toString().startsWith("7e2a1d", ignoreCase = true) } == true) {
            packet("RX", "service_advertisement", device,
                message = "Services=${record.serviceUuids}; RSSI=${result.rssi} dBm; no manufacturer payload")
        }
    }
}
