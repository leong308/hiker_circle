package com.leongziqi.hikercircle

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class HikerBleBridge(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val METHOD_CHANNEL = "hiker_circle/ble_bridge"
        private const val EVENT_CHANNEL = "hiker_circle/ble_events"
        private const val PERMISSION_REQUEST_CODE = 8511
    }

    private val bluetoothManager: BluetoothManager?
        get() = activity.getSystemService(BluetoothManager::class.java)
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null
    private var teamScanCallback: ScanCallback? = null
    private var teamAdvertiseCallback: AdvertiseCallback? = null
    private var sosTestAdvertiseCallback: AdvertiseCallback? = null
    private var latestTeamPayload: Map<String, Any?>? = null
    private val activeTeamGatts = mutableMapOf<String, BluetoothGatt>()
    private val lastTeamConnectAtMillis = mutableMapOf<String, Long>()
    private val teamGattConnectDebounceMillis = 10000L
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        methodChannel.setMethodCallHandler(::handleMethodCall)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) {
            return false
        }
        val result = pendingPermissionResult
        val action = pendingPermissionAction
        pendingPermissionResult = null
        pendingPermissionAction = null
        if (grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        ) {
            action?.invoke()
        } else {
            result?.error(
                "ble_permission_denied",
                "Bluetooth permissions are required for SOS button and team BLE support.",
                null,
            )
        }
        return true
    }

    fun dispose() {
        stopTeamLocationExchange()
        stopSosTestAdvertiser()
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isBleSupported())
            "startSosButtonMonitor" -> {
                withBlePermissions(result, includeAdvertisePermission = false) {
                    startSosButtonMonitor()
                    result.success(null)
                }
            }
            "stopSosButtonMonitor" -> {
                stopSosButtonMonitor()
                result.success(null)
            }
            "broadcastPhysicalSosTest" -> {
                val payload = sosHelpPayloadFrom(call)
                if (payload == null) {
                    result.error(
                        "ble_sos_test_invalid",
                        "Physical SOS test payload is invalid.",
                        null,
                    )
                    return
                }
                withBlePermissions(result, includeAdvertisePermission = true) {
                    broadcastPhysicalSosTest(payload)
                    result.success(null)
                }
            }
            "startTeamLocationExchange",
            "updateTeamLocation" -> {
                val payload = teamPayloadFrom(call)
                if (payload == null) {
                    result.error(
                        "ble_team_location_invalid",
                        "Team BLE location payload is invalid.",
                        null,
                    )
                    return
                }
                latestTeamPayload = payload
                withBlePermissions(result, includeAdvertisePermission = true) {
                    startTeamScanner()
                    restartTeamAdvertiser()
                    result.success(null)
                }
            }
            "stopTeamLocationExchange" -> {
                stopTeamLocationExchange()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun withBlePermissions(
        result: MethodChannel.Result,
        includeAdvertisePermission: Boolean,
        action: () -> Unit,
    ) {
        if (!isBleSupported()) {
            result.error("ble_unsupported", "This phone does not support BLE.", null)
            return
        }
        val missing = requiredPermissions(includeAdvertisePermission).filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            action()
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "ble_permission_request_active",
                "A Bluetooth permission request is already active.",
                null,
            )
            return
        }
        pendingPermissionResult = result
        pendingPermissionAction = action
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    private fun requiredPermissions(includeAdvertisePermission: Boolean): List<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOfNotNull(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE.takeIf {
                    includeAdvertisePermission
                },
            )
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun isBleSupported(): Boolean {
        return activity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_BLUETOOTH_LE,
        ) && bluetoothManager?.adapter != null
    }

    private fun startSosButtonMonitor() {
        val intent = Intent(activity, BleSosMonitorService::class.java).apply {
            action = BleSosMonitorService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
        emitStatus("sos_monitor_started")
    }

    private fun stopSosButtonMonitor() {
        val intent = Intent(activity, BleSosMonitorService::class.java).apply {
            action = BleSosMonitorService.ACTION_STOP
        }
        activity.startService(intent)
        emitStatus("sos_monitor_stopped")
    }

    private fun broadcastPhysicalSosTest(payload: Map<String, Any?>) {
        stopSosTestAdvertiser()
        if (!hasAdvertisePermission()) {
            emitStatus("ble_sos_test_failed", "Bluetooth advertising permission is missing.")
            return
        }
        val advertiser = bluetoothManager?.adapter?.bluetoothLeAdvertiser ?: run {
            emitStatus("ble_sos_test_failed", "This phone cannot advertise BLE packets.")
            return
        }
        val durationMillis = (payload["durationMillis"] as Long).coerceIn(3000L, 8000L)
        val packet = HikerBleProtocol.encodeSosHelpBeacon(
            phoneNumberHash = payload["phoneNumberHash"] as Long,
            latitude = payload["latitude"] as Double,
            longitude = payload["longitude"] as Double,
            accuracyMeters = payload["accuracyMeters"] as? Double,
            capturedAtMillis = payload["capturedAtMillis"] as Long,
        )
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(durationMillis.toInt())
            .build()
        val data = AdvertiseData.Builder()
            .addManufacturerData(HikerBleProtocol.MANUFACTURER_ID, packet)
            .setIncludeDeviceName(false)
            .build()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                emitStatus("ble_sos_test_broadcast_started")
            }

            override fun onStartFailure(errorCode: Int) {
                emitStatus(
                    "ble_sos_test_failed",
                    "Android BLE advertiser failed with code $errorCode.",
                )
            }
        }
        sosTestAdvertiseCallback = callback
        advertiser.startAdvertising(settings, data, callback)
        mainHandler.postDelayed(
            {
                if (sosTestAdvertiseCallback === callback) {
                    stopSosTestAdvertiser()
                }
            },
            durationMillis + 500L,
        )
    }

    private fun startTeamScanner() {
        if (teamScanCallback != null || !hasScanPermission()) {
            return
        }
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: return
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handleTeamScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::handleTeamScanResult)
            }
        }
        teamScanCallback = callback
        val filters = listOf(
            ScanFilter.Builder()
                .setManufacturerData(
                    HikerBleProtocol.MANUFACTURER_ID,
                    byteArrayOf(0x48, 0x43, 0x01, 0x02),
                    byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()),
                )
                .build(),
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(HikerBleProtocol.TEAM_LOCATION_SERVICE_UUID))
                .build(),
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanner.startScan(filters, settings, callback)
        emitStatus("team_ble_scan_started")
    }

    private fun restartTeamAdvertiser() {
        stopTeamAdvertiser()
        if (!hasAdvertisePermission()) {
            return
        }
        val payload = latestTeamPayload ?: return
        val advertiser = bluetoothManager?.adapter?.bluetoothLeAdvertiser ?: return
        val packet = HikerBleProtocol.encodeTeamLocation(
            teamSessionHash = payload["teamSessionHash"] as Long,
            phoneNumberHash = payload["phoneNumberHash"] as Long,
            latitude = payload["latitude"] as Double,
            longitude = payload["longitude"] as Double,
            accuracyMeters = payload["accuracyMeters"] as? Double,
            capturedAtMillis = payload["capturedAtMillis"] as Long,
        )
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .addManufacturerData(HikerBleProtocol.MANUFACTURER_ID, packet)
            .setIncludeDeviceName(false)
            .build()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                emitStatus("team_ble_advertising_started")
            }

            override fun onStartFailure(errorCode: Int) {
                emitStatus(
                    "team_ble_advertising_failed",
                    "Android BLE advertiser failed with code $errorCode.",
                )
            }
        }
        teamAdvertiseCallback = callback
        advertiser.startAdvertising(settings, data, callback)
    }

    private fun stopTeamLocationExchange() {
        stopTeamScanner()
        stopTeamAdvertiser()
        latestTeamPayload = null
    }

    private fun stopTeamScanner() {
        val callback = teamScanCallback
        teamScanCallback = null
        if (callback != null && hasScanPermission()) {
            runCatching {
                bluetoothManager?.adapter?.bluetoothLeScanner?.stopScan(callback)
            }
        }
        activeTeamGatts.values.toList().forEach(::closeTeamGatt)
    }

    private fun stopTeamAdvertiser() {
        val callback = teamAdvertiseCallback ?: return
        teamAdvertiseCallback = null
        if (hasAdvertisePermission()) {
            runCatching {
                bluetoothManager?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
            }
        }
    }

    private fun stopSosTestAdvertiser() {
        val callback = sosTestAdvertiseCallback ?: return
        sosTestAdvertiseCallback = null
        if (hasAdvertisePermission()) {
            runCatching {
                bluetoothManager?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
            }
        }
    }

    private fun handleTeamScanResult(result: ScanResult) {
        val packet = HikerBleProtocol.decodeTeamLocation(result)
        if (packet != null) {
            emitTeamLocation(packet)
            return
        }
        val serviceUuids = result.scanRecord?.serviceUuids.orEmpty()
        if (serviceUuids.any { it.uuid == HikerBleProtocol.TEAM_LOCATION_SERVICE_UUID }) {
            connectForTeamLocationPayload(result)
        }
    }

    private fun connectForTeamLocationPayload(result: ScanResult) {
        if (!hasConnectPermission()) {
            return
        }
        val address = result.device.address ?: return
        val now = System.currentTimeMillis()
        if (activeTeamGatts.containsKey(address) ||
            now - (lastTeamConnectAtMillis[address] ?: 0L) < teamGattConnectDebounceMillis
        ) {
            return
        }
        lastTeamConnectAtMillis[address] = now

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS &&
                    newState == BluetoothProfile.STATE_CONNECTED
                ) {
                    if (hasConnectPermission()) {
                        gatt.discoverServices()
                    } else {
                        closeTeamGatt(gatt)
                    }
                    return
                }
                if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    closeTeamGatt(gatt)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS || !hasConnectPermission()) {
                    closeTeamGatt(gatt)
                    return
                }
                val characteristic = gatt
                    .getService(HikerBleProtocol.TEAM_LOCATION_SERVICE_UUID)
                    ?.getCharacteristic(HikerBleProtocol.TEAM_LOCATION_CHARACTERISTIC_UUID)
                if (characteristic == null) {
                    closeTeamGatt(gatt)
                    return
                }
                gatt.readCharacteristic(characteristic)
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS &&
                    characteristic.uuid == HikerBleProtocol.TEAM_LOCATION_CHARACTERISTIC_UUID
                ) {
                    HikerBleProtocol.decodeTeamLocation(
                        characteristic.value,
                        result.rssi,
                    )?.let(::emitTeamLocation)
                }
                closeTeamGatt(gatt)
            }
        }

        runCatching {
            activeTeamGatts[address] = result.device.connectGatt(activity, false, callback)
        }.onFailure {
            activeTeamGatts.remove(address)
        }
    }

    private fun closeTeamGatt(gatt: BluetoothGatt) {
        runCatching { gatt.device.address }.getOrNull()?.let(activeTeamGatts::remove)
        runCatching {
            if (hasConnectPermission()) {
                gatt.disconnect()
            }
            gatt.close()
        }
    }

    private fun emitTeamLocation(packet: HikerBleProtocol.TeamLocationPacket) {
        val ownPayload = latestTeamPayload
        if (ownPayload != null &&
            packet.phoneNumberHash == ownPayload["phoneNumberHash"] as Long
        ) {
            return
        }
        eventSink?.success(
            mapOf(
                "type" to "teamLocation",
                "teamSessionHash" to packet.teamSessionHash,
                "phoneNumberHash" to packet.phoneNumberHash,
                "latitude" to packet.latitude,
                "longitude" to packet.longitude,
                "accuracyMeters" to packet.accuracyMeters,
                "capturedAtMillis" to packet.capturedAtMillis,
                "receivedAtMillis" to System.currentTimeMillis(),
                "rssi" to packet.rssi,
            ),
        )
    }

    private fun teamPayloadFrom(call: MethodCall): Map<String, Any?>? {
        val teamSessionId = call.argument<String>("teamSessionId") ?: return null
        val phoneNumber = call.argument<String>("phoneNumber") ?: return null
        val latitude = call.argument<Number>("latitude")?.toDouble() ?: return null
        val longitude = call.argument<Number>("longitude")?.toDouble() ?: return null
        val capturedAtMillis = call.argument<Number>("capturedAtMillis")?.toLong()
            ?: System.currentTimeMillis()
        return mapOf(
            "teamSessionHash" to (
                call.argument<Number>("teamSessionHash")?.toLong()
                    ?: HikerBleProtocol.hash(teamSessionId)
                ),
            "phoneNumberHash" to (
                call.argument<Number>("phoneNumberHash")?.toLong()
                    ?: HikerBleProtocol.phoneHash(phoneNumber)
                ),
            "latitude" to latitude,
            "longitude" to longitude,
            "accuracyMeters" to call.argument<Number>("accuracyMeters")?.toDouble(),
            "capturedAtMillis" to capturedAtMillis,
        )
    }

    private fun sosHelpPayloadFrom(call: MethodCall): Map<String, Any?>? {
        val phoneNumber = call.argument<String>("phoneNumber") ?: return null
        val latitude = call.argument<Number>("latitude")?.toDouble() ?: return null
        val longitude = call.argument<Number>("longitude")?.toDouble() ?: return null
        val capturedAtMillis = call.argument<Number>("capturedAtMillis")?.toLong()
            ?: System.currentTimeMillis()
        val durationMillis = call.argument<Number>("durationMillis")?.toLong() ?: 5000L
        return mapOf(
            "phoneNumberHash" to (
                call.argument<Number>("phoneNumberHash")?.toLong()
                    ?: HikerBleProtocol.phoneHash(phoneNumber)
                ),
            "latitude" to latitude,
            "longitude" to longitude,
            "accuracyMeters" to call.argument<Number>("accuracyMeters")?.toDouble(),
            "capturedAtMillis" to capturedAtMillis,
            "durationMillis" to durationMillis,
        )
    }

    private fun hasScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
                activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasAdvertisePermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun emitStatus(status: String, message: String? = null) {
        eventSink?.success(
            mapOf(
                "type" to "status",
                "status" to status,
                "message" to message,
                "receivedAtMillis" to System.currentTimeMillis(),
            ),
        )
    }
}
