package com.leongziqi.hikercircle

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID

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
    private val pairedButtonRegistry by lazy { PairedSosButtonRegistry(activity) }
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null
    private var teamScanCallback: ScanCallback? = null
    private var pairedButtonSetupScanCallback: ScanCallback? = null
    private var teamAdvertiseCallback: AdvertiseCallback? = null
    private var sosTestAdvertiseCallback: AdvertiseCallback? = null
    private var latestTeamPayload: Map<String, Any?>? = null
    private val activeTeamGatts = mutableMapOf<String, BluetoothGatt>()
    private val lastTeamConnectAtMillis = mutableMapOf<String, Long>()
    private val teamGattConnectDebounceMillis = 10000L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pairingGatt: BluetoothGatt? = null
    private var pairingAttempt: PairingAttempt? = null
    private var pairingResult: MethodChannel.Result? = null
    private var locationGatt: BluetoothGatt? = null
    private var locationPayload: ByteArray? = null
    private var locationResult: MethodChannel.Result? = null
    private val pairingTimeout = Runnable {
        finishPairing(
            success = false,
            errorCode = "paired_button_confirmation_timeout",
            errorMessage = "The button was not physically confirmed within 15 seconds.",
        )
    }

    private data class PairingAttempt(
        val address: String,
        val displayName: String,
        val deviceId: ByteArray,
        val pairingSecret: ByteArray,
        var requestCharacteristic: BluetoothGattCharacteristic? = null,
        var statusCharacteristic: BluetoothGattCharacteristic? = null,
    )
    private val sosButtonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BleSosMonitorService.ACTION_SOS_BUTTON_DETECTED) {
                return
            }
            when (intent.getStringExtra(BleSosMonitorService.EXTRA_EVENT_TYPE)) {
                BleSosMonitorService.EVENT_PAIRED_OWNER -> {
                    emitPairedSosButton(
                        deviceId = intent.getStringExtra(BleSosMonitorService.EXTRA_DEVICE_ID) ?: return,
                        displayName = intent.getStringExtra(BleSosMonitorService.EXTRA_DISPLAY_NAME),
                        counter = intent.getLongExtra(BleSosMonitorService.EXTRA_COUNTER, 0L),
                        mode = intent.getIntExtra(BleSosMonitorService.EXTRA_MODE, 1),
                        rssi = intent.getIntExtra(BleSosMonitorService.EXTRA_RSSI, 0),
                        receivedAtMillis = intent.getLongExtra(
                            BleSosMonitorService.EXTRA_RECEIVED_AT_MILLIS,
                            System.currentTimeMillis(),
                        ),
                    )
                    return
                }
                BleSosMonitorService.EVENT_PAIRED_NEARBY -> {
                    emitNearbySosButton(
                        deviceId = intent.getStringExtra(BleSosMonitorService.EXTRA_DEVICE_ID) ?: return,
                        counter = intent.getLongExtra(BleSosMonitorService.EXTRA_COUNTER, 0L),
                        rssi = intent.getIntExtra(BleSosMonitorService.EXTRA_RSSI, 0),
                        receivedAtMillis = intent.getLongExtra(
                            BleSosMonitorService.EXTRA_RECEIVED_AT_MILLIS,
                            System.currentTimeMillis(),
                        ),
                    )
                    return
                }
                BleSosMonitorService.EVENT_PAIRED_LOCATION -> {
                    emitNearbySosLocation(
                        deviceId = intent.getStringExtra(BleSosMonitorService.EXTRA_DEVICE_ID) ?: return,
                        counter = intent.getLongExtra(BleSosMonitorService.EXTRA_COUNTER, 0L),
                        latitude = intent.getDoubleExtra(BleSosMonitorService.EXTRA_LATITUDE, 0.0),
                        longitude = intent.getDoubleExtra(BleSosMonitorService.EXTRA_LONGITUDE, 0.0),
                        accuracyMeters = intent.getDoubleExtra(
                            BleSosMonitorService.EXTRA_ACCURACY_METERS,
                            0.0,
                        ),
                        rssi = intent.getIntExtra(BleSosMonitorService.EXTRA_RSSI, 0),
                        receivedAtMillis = intent.getLongExtra(
                            BleSosMonitorService.EXTRA_RECEIVED_AT_MILLIS,
                            System.currentTimeMillis(),
                        ),
                    )
                    return
                }
            }
            emitSosButton(
                counter = if (intent.hasExtra(BleSosMonitorService.EXTRA_COUNTER)) {
                    intent.getLongExtra(BleSosMonitorService.EXTRA_COUNTER, 0L)
                } else {
                    null
                },
                rssi = intent.getIntExtra(BleSosMonitorService.EXTRA_RSSI, 0),
                receivedAtMillis = intent.getLongExtra(
                    BleSosMonitorService.EXTRA_RECEIVED_AT_MILLIS,
                    System.currentTimeMillis(),
                ),
                source = intent.getStringExtra(BleSosMonitorService.EXTRA_SOURCE)
                    ?: "ble_button",
            )
        }
    }

    init {
        methodChannel.setMethodCallHandler(::handleMethodCall)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
        registerSosButtonReceiver()
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
        stopPairedButtonSetupScan()
        stopSosTestAdvertiser()
        finishPairing(
            success = false,
            errorCode = "paired_button_bridge_disposed",
            errorMessage = "The BLE bridge was disposed before pairing completed.",
        )
        finishLocationHandoff(
            success = false,
            errorCode = "paired_button_bridge_disposed",
            errorMessage = "The BLE bridge was disposed before the location was sent.",
        )
        runCatching { activity.unregisterReceiver(sosButtonReceiver) }
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    private fun registerSosButtonReceiver() {
        val filter = IntentFilter(BleSosMonitorService.ACTION_SOS_BUTTON_DETECTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(
                sosButtonReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            activity.registerReceiver(sosButtonReceiver, filter)
        }
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
            "startPairedButtonSetupScan" -> {
                withBlePermissions(result, includeAdvertisePermission = false) {
                    startPairedButtonSetupScan()
                    result.success(null)
                }
            }
            "stopPairedButtonSetupScan" -> {
                stopPairedButtonSetupScan()
                result.success(null)
            }
            "pairSosButton" -> {
                val address = call.argument<String>("address")?.trim()
                val displayName = call.argument<String>("displayName")?.trim()
                if (address.isNullOrEmpty() || displayName.isNullOrEmpty()) {
                    result.error(
                        "paired_button_invalid_request",
                        "A button address and display name are required.",
                        null,
                    )
                } else {
                    withBlePermissions(result, includeAdvertisePermission = false) {
                        beginPairing(address, displayName, result)
                    }
                }
            }
            "listPairedSosButtons" -> result.success(
                pairedButtonRegistry.buttons().map { button ->
                    mapOf(
                        "deviceId" to button.deviceIdHex,
                        "displayName" to button.displayName,
                        "pairedAtMillis" to button.pairedAtMillis,
                        "lastSeenAtMillis" to button.lastSeenAtMillis,
                        "lastAcceptedEventId" to button.lastAcceptedEventId,
                    )
                },
            )
            "unpairSosButton" -> {
                val deviceId = call.argument<String>("deviceId")?.trim()?.uppercase()
                if (deviceId.isNullOrEmpty()) {
                    result.error("paired_button_invalid_id", "A button device ID is required.", null)
                } else {
                    result.success(pairedButtonRegistry.remove(deviceId))
                }
            }
            "sendPairedSosLocation" -> {
                val deviceId = call.argument<String>("deviceId")?.trim()?.uppercase()
                val eventId = call.argument<Number>("eventId")?.toLong()
                val latitude = call.argument<Number>("latitude")?.toDouble()
                val longitude = call.argument<Number>("longitude")?.toDouble()
                val accuracyMeters = call.argument<Number>("accuracyMeters")?.toDouble()
                val capturedAtMillis = call.argument<Number>("capturedAtMillis")?.toLong()
                    ?: System.currentTimeMillis()
                if (deviceId.isNullOrEmpty() || eventId == null ||
                    latitude == null || longitude == null
                ) {
                    result.error(
                        "paired_button_location_invalid",
                        "A button ID, event ID, latitude, and longitude are required.",
                        null,
                    )
                } else {
                    withBlePermissions(result, includeAdvertisePermission = false) {
                        beginLocationHandoff(
                            deviceId,
                            eventId,
                            latitude,
                            longitude,
                            accuracyMeters,
                            capturedAtMillis,
                            result,
                        )
                    }
                }
            }
            "setLegacyUnpairedSosButtonEnabled" -> {
                pairedButtonRegistry.setLegacyUnpairedEnabled(
                    call.argument<Boolean>("enabled") ?: false,
                )
                result.success(null)
            }
            "isLegacyUnpairedSosButtonEnabled" ->
                result.success(pairedButtonRegistry.isLegacyUnpairedEnabled())
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
        emitEvent(
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

    private fun emitSosButton(
        counter: Long?,
        rssi: Int,
        receivedAtMillis: Long,
        source: String,
    ) {
        emitEvent(
            buildMap<String, Any> {
                put("type", "sosButton")
                put("source", source)
                put("rssi", rssi)
                put("receivedAtMillis", receivedAtMillis)
                if (counter != null) {
                    put("counter", counter)
                    put("broadcastId", counter)
                }
            },
        )
    }

    private fun startPairedButtonSetupScan() {
        if (pairedButtonSetupScanCallback != null || !hasScanPermission()) {
            return
        }
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: return
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                emitPairedButtonSetupDevice(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::emitPairedButtonSetupDevice)
            }

            override fun onScanFailed(errorCode: Int) {
                emitStatus(
                    "paired_button_setup_scan_failed",
                    "Bluetooth setup scan failed with code $errorCode.",
                )
            }
        }
        pairedButtonSetupScanCallback = callback
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        // Scan without a controller-side UUID filter. Some Android Bluetooth
        // stacks fail to report a peripheral that starts advertising after a
        // filtered scan has already begun. We validate the setup UUID/name in
        // software instead.
        scanner.startScan(null, settings, callback)
        emitStatus("paired_button_setup_scan_started")
    }

    private fun stopPairedButtonSetupScan() {
        val callback = pairedButtonSetupScanCallback ?: return
        pairedButtonSetupScanCallback = null
        if (hasScanPermission()) {
            runCatching {
                bluetoothManager?.adapter?.bluetoothLeScanner?.stopScan(callback)
            }
        }
        emitStatus("paired_button_setup_scan_stopped")
    }

    private fun emitPairedButtonSetupDevice(result: ScanResult) {
        val record = result.scanRecord
        val advertisedSetupService = record?.serviceUuids?.any {
            it.uuid == HikerBleProtocol.PAIRED_BUTTON_SETUP_SERVICE_UUID
        } == true
        val advertisedName = record?.deviceName ?: result.device.name
        if (!advertisedSetupService && advertisedName != "HikerCircle Setup") {
            return
        }
        val name = advertisedName ?: "HikerCircle Setup"
        emitEvent(
            mapOf(
                "type" to "pairedButtonSetupDevice",
                "status" to "paired_button_setup_device_found",
                "address" to result.device.address,
                "displayName" to name,
                "rssi" to result.rssi,
                "receivedAtMillis" to System.currentTimeMillis(),
            ),
        )
    }

    private fun beginLocationHandoff(
        deviceIdHex: String,
        eventId: Long,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
        capturedAtMillis: Long,
        result: MethodChannel.Result,
    ) {
        val button = pairedButtonRegistry.find(deviceIdHex)
        val address = button?.address
        if (button == null || address.isNullOrEmpty()) {
            result.error(
                "paired_button_address_missing",
                "This paired button has no saved BLE address. Re-pair it before sending location.",
                null,
            )
            return
        }
        finishLocationHandoff(success = false)
        val payload = runCatching {
            HikerBleProtocol.encodeSosLocationHandoff(
                eventId = eventId,
                latitude = latitude,
                longitude = longitude,
                accuracyMeters = accuracyMeters,
                capturedAtMillis = capturedAtMillis,
                pairingSecret = button.pairingSecret,
            )
        }.getOrElse {
            result.error("paired_button_location_invalid", it.message, null)
            return
        }
        locationPayload = payload
        locationResult = result
        val device = runCatching {
            bluetoothManager?.adapter?.getRemoteDevice(address)
        }.getOrNull()
        if (device == null) {
            finishLocationHandoff(
                success = false,
                errorCode = "paired_button_address_invalid",
                errorMessage = "The paired button BLE address is invalid.",
            )
            return
        }
        locationGatt = runCatching {
            device.connectGatt(activity, false, locationGattCallback)
        }.getOrNull()
        if (locationGatt == null) {
            finishLocationHandoff(
                success = false,
                errorCode = "paired_button_location_connect_failed",
                errorMessage = "Unable to connect to the SOS button for its location handoff.",
            )
        }
    }

    private val locationGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS ||
                newState != BluetoothProfile.STATE_CONNECTED
            ) {
                finishLocationHandoff(
                    success = false,
                    errorCode = "paired_button_location_connect_failed",
                    errorMessage = "The SOS button location connection failed.",
                )
                return
            }
            if (hasConnectPermission()) {
                gatt.discoverServices()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS || !hasConnectPermission()) {
                finishLocationHandoff(
                    success = false,
                    errorCode = "paired_button_location_services_failed",
                    errorMessage = "The SOS button location service was not found.",
                )
                return
            }
            val characteristic = gatt
                .getService(HikerBleProtocol.ACTIVE_SOS_SERVICE_UUID)
                ?.getCharacteristic(HikerBleProtocol.SOS_LOCATION_CHARACTERISTIC_UUID)
            val payload = locationPayload
            if (characteristic == null || payload == null) {
                finishLocationHandoff(
                    success = false,
                    errorCode = "paired_button_location_service_missing",
                    errorMessage = "The SOS button is not accepting location handoffs.",
                )
                return
            }
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            characteristic.value = payload
            if (!gatt.writeCharacteristic(characteristic)) {
                finishLocationHandoff(
                    success = false,
                    errorCode = "paired_button_location_write_failed",
                    errorMessage = "The SOS button rejected the location handoff.",
                )
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid == HikerBleProtocol.SOS_LOCATION_CHARACTERISTIC_UUID) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    finishLocationHandoff(success = true)
                } else {
                    finishLocationHandoff(
                        success = false,
                        errorCode = "paired_button_location_write_failed",
                        errorMessage = "The SOS button rejected the location handoff.",
                    )
                }
            }
        }
    }

    private fun finishLocationHandoff(
        success: Boolean,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        val gatt = locationGatt
        locationGatt = null
        locationPayload = null
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        val result = locationResult
        locationResult = null
        if (success) {
            result?.success(null)
        } else if (result != null && errorCode != null) {
            result.error(errorCode, errorMessage, null)
        }
    }

    private fun beginPairing(
        address: String,
        displayName: String,
        result: MethodChannel.Result,
    ) {
        if (pairingResult != null) {
            result.error(
                "paired_button_pairing_active",
                "Another paired-button pairing operation is already active.",
                null,
            )
            return
        }
        if (!hasConnectPermission()) {
            result.error(
                "paired_button_connect_permission_denied",
                "Bluetooth connection permission is required to pair the button.",
                null,
            )
            return
        }
        // The discovery scan is no longer needed after the user selects a
        // button. Stop it before opening GATT so it cannot compete with or
        // invalidate the foreground SOS monitor's scan registration.
        stopPairedButtonSetupScan()
        val material = pairedButtonRegistry.newPairingMaterial()
        pairingAttempt = PairingAttempt(
            address = address,
            displayName = displayName,
            deviceId = material.deviceId,
            pairingSecret = material.pairingSecret,
        )
        pairingResult = result
        emitStatus("paired_button_pairing_connecting")
        val device = runCatching { bluetoothManager?.adapter?.getRemoteDevice(address) }
            .getOrNull()
        if (device == null) {
            finishPairing(
                success = false,
                errorCode = "paired_button_invalid_address",
                errorMessage = "The selected SOS button address is invalid.",
            )
            return
        }
        pairingGatt = runCatching {
            device.connectGatt(activity, false, pairingGattCallback)
        }.getOrElse {
            finishPairing(
                success = false,
                errorCode = "paired_button_connect_failed",
                errorMessage = "Unable to connect to the SOS button.",
            )
            null
        }
    }

    private val pairingGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(
            gatt: BluetoothGatt,
            status: Int,
            newState: Int,
        ) {
            if (status != BluetoothGatt.GATT_SUCCESS ||
                newState != BluetoothProfile.STATE_CONNECTED
            ) {
                if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    finishPairing(
                        success = false,
                        errorCode = "paired_button_disconnected",
                        errorMessage = "The SOS button disconnected before pairing completed.",
                    )
                }
                return
            }
            if (hasConnectPermission()) {
                gatt.discoverServices()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                finishPairing(
                    success = false,
                    errorCode = "paired_button_services_failed",
                    errorMessage = "The SOS button setup service was not available.",
                )
                return
            }
            val service = gatt.getService(HikerBleProtocol.PAIRED_BUTTON_SETUP_SERVICE_UUID)
            val request = service?.getCharacteristic(
                HikerBleProtocol.PAIRED_BUTTON_PAIR_REQUEST_CHARACTERISTIC_UUID,
            )
            val statusCharacteristic = service?.getCharacteristic(
                HikerBleProtocol.PAIRED_BUTTON_STATUS_CHARACTERISTIC_UUID,
            )
            if (request == null || statusCharacteristic == null) {
                finishPairing(
                    success = false,
                    errorCode = "paired_button_setup_service_invalid",
                    errorMessage = "The SOS button setup characteristics are incomplete.",
                )
                return
            }
            pairingAttempt?.requestCharacteristic = request
            pairingAttempt?.statusCharacteristic = statusCharacteristic
            gatt.setCharacteristicNotification(statusCharacteristic, true)
            val descriptor = statusCharacteristic.getDescriptor(CLIENT_CONFIG_DESCRIPTOR)
            if (descriptor != null) {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                gatt.writeDescriptor(descriptor)
            } else {
                writePairRequest(gatt)
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (descriptor.characteristic.uuid ==
                HikerBleProtocol.PAIRED_BUTTON_STATUS_CHARACTERISTIC_UUID
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    writePairRequest(gatt)
                } else {
                    finishPairing(
                        success = false,
                        errorCode = "paired_button_notifications_failed",
                        errorMessage = "Unable to subscribe to button pairing status.",
                    )
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid == HikerBleProtocol.PAIRED_BUTTON_STATUS_CHARACTERISTIC_UUID) {
                handlePairingStatus(characteristic.value)
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS &&
                characteristic.uuid == HikerBleProtocol.PAIRED_BUTTON_STATUS_CHARACTERISTIC_UUID
            ) {
                handlePairingStatus(characteristic.value)
            }
        }
    }

    private fun writePairRequest(gatt: BluetoothGatt) {
        val attempt = pairingAttempt ?: return
        val characteristic = attempt.requestCharacteristic ?: return
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = HikerBleProtocol.encodePairRequest(
            attempt.deviceId,
            attempt.pairingSecret,
        )
        if (!gatt.writeCharacteristic(characteristic)) {
            finishPairing(
                success = false,
                errorCode = "paired_button_pair_write_failed",
                errorMessage = "Unable to write pairing data to the SOS button.",
            )
        } else {
            emitStatus("paired_button_pairing_written")
            mainHandler.postDelayed(pairingTimeout, 15000L)
        }
    }

    private fun handlePairingStatus(value: ByteArray) {
        val status = HikerBleProtocol.decodePairingStatus(value) ?: return
        val attempt = pairingAttempt ?: return
        if (!status.deviceId.contentEquals(ByteArray(6)) &&
            !status.deviceId.contentEquals(attempt.deviceId)
        ) {
            return
        }
        when (status.status) {
            HikerBleProtocol.PAIRING_STATUS_READY -> emitStatus("paired_button_ready")
            HikerBleProtocol.PAIRING_STATUS_AWAITING_CONFIRMATION ->
                emitStatus("paired_button_awaiting_confirmation")
            HikerBleProtocol.PAIRING_STATUS_PAIRED -> {
                pairedButtonRegistry.saveConfirmedPairing(
                    attempt.deviceId,
                    attempt.pairingSecret,
                    attempt.displayName,
                    attempt.address,
                )
                finishPairing(success = true)
            }
            HikerBleProtocol.PAIRING_STATUS_INVALID_REQUEST -> finishPairing(
                success = false,
                errorCode = "paired_button_invalid_pair_request",
                errorMessage = "The SOS button rejected the pairing request.",
            )
            HikerBleProtocol.PAIRING_STATUS_CONFIRMATION_EXPIRED -> finishPairing(
                success = false,
                errorCode = "paired_button_confirmation_expired",
                errorMessage = "The button confirmation window expired.",
            )
        }
    }

    private fun finishPairing(
        success: Boolean,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        mainHandler.post {
            mainHandler.removeCallbacks(pairingTimeout)
            runCatching { pairingGatt?.disconnect() }
            runCatching { pairingGatt?.close() }
            pairingGatt = null
            pairingAttempt = null
            val result = pairingResult
            pairingResult = null
            if (success) {
                // Re-register the long-running scanner after setup mode/GATT
                // has ended. This is required on Android variants that leave
                // the previous callback registered but no longer delivering.
                startSosButtonMonitor()
                emitStatus("paired_button_paired")
                result?.success(null)
            } else if (result != null) {
                emitStatus(errorCode ?: "paired_button_pairing_failed", errorMessage)
                result.error(errorCode ?: "paired_button_pairing_failed", errorMessage, null)
            }
        }
    }

    private val CLIENT_CONFIG_DESCRIPTOR: UUID =
        UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private fun emitPairedSosButton(
        deviceId: String,
        displayName: String?,
        counter: Long,
        mode: Int,
        rssi: Int,
        receivedAtMillis: Long,
    ) {
        emitEvent(
            mapOf(
                "type" to "pairedSosButton",
                "source" to "paired_ble_button",
                "deviceId" to deviceId,
                "displayName" to displayName,
                "counter" to counter,
                "mode" to mode,
                "rssi" to rssi,
                "receivedAtMillis" to receivedAtMillis,
            ),
        )
    }

    private fun emitNearbySosButton(
        deviceId: String,
        counter: Long,
        rssi: Int,
        receivedAtMillis: Long,
    ) {
        emitEvent(
            mapOf(
                "type" to "nearbySosButton",
                "source" to "paired_ble_button",
                "deviceId" to deviceId,
                "counter" to counter,
                "rssi" to rssi,
                "receivedAtMillis" to receivedAtMillis,
            ),
        )
    }

    private fun emitNearbySosLocation(
        deviceId: String,
        counter: Long,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        rssi: Int,
        receivedAtMillis: Long,
    ) {
        emitEvent(
            mapOf(
                "type" to "nearbySosLocation",
                "source" to "paired_ble_button_location",
                "deviceId" to deviceId,
                "counter" to counter,
                "latitude" to latitude,
                "longitude" to longitude,
                "accuracyMeters" to accuracyMeters,
                "rssi" to rssi,
                "receivedAtMillis" to receivedAtMillis,
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

    private fun emitEvent(event: Any) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun emitStatus(status: String, message: String? = null) {
        emitEvent(
            mapOf(
                "type" to "status",
                "status" to status,
                "message" to message,
                "receivedAtMillis" to System.currentTimeMillis(),
            ),
        )
    }
}
