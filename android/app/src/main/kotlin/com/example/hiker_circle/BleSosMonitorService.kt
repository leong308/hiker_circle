package com.leongziqi.hikercircle

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.util.SparseArray

class BleSosMonitorService : Service() {
    companion object {
        const val ACTION_START = "com.leongziqi.hikercircle.ble_sos.START"
        const val ACTION_STOP = "com.leongziqi.hikercircle.ble_sos.STOP"
        private const val TAG = "HikerBleSosMonitor"
        private const val CHANNEL_ID = "hiker_circle_ble_sos"
        private const val NOTIFICATION_ID = 4211
        private const val HELP_GATT_CONNECT_DEBOUNCE_MILLIS = 3000L
        private const val MAX_HANDLED_EVENT_IDS = 128
        private const val MAX_CANDIDATE_PACKAGE_LOGS = 40
    }

    private val bluetoothManager: BluetoothManager?
        get() = getSystemService(BluetoothManager::class.java)
    private var scanCallback: ScanCallback? = null
    private var candidatePackageLogCount = 0
    private val handledEventIds = mutableSetOf<String>()
    private val handledEventIdOrder = ArrayDeque<String>()
    private val activeHelpGatts = mutableMapOf<String, BluetoothGatt>()
    private val lastHelpConnectAtMillis = mutableMapOf<String, Long>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, notification())
        startScan()
        return START_STICKY
    }

    override fun onDestroy() {
        stopScan()
        super.onDestroy()
    }

    private fun startScan() {
        if (!hasScanPermission()) {
            Log.w(TAG, "BLE SOS scan stopped: scan permission is missing")
            stopSelf()
            return
        }
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: run {
            Log.w(TAG, "BLE SOS scan stopped: scanner is unavailable")
            stopSelf()
            return
        }
        if (scanCallback != null) {
            Log.d(TAG, "BLE SOS scan already running")
            return
        }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handleScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::handleScanResult)
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "BLE SOS scan failed with code $errorCode")
            }
        }
        scanCallback = callback
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanner.startScan(null, settings, callback)
        Log.d(TAG, "BLE SOS scan started without hardware filters")
    }

    private fun stopScan() {
        val callback = scanCallback
        scanCallback = null
        if (callback != null && hasScanPermission()) {
            runCatching {
                bluetoothManager?.adapter?.bluetoothLeScanner?.stopScan(callback)
            }
        }
        activeHelpGatts.values.toList().forEach(::closeHelpGatt)
    }

    private fun handleScanResult(result: ScanResult) {
        logBleCandidatePackage(result)
        val helpBeacon = HikerBleProtocol.decodeSosHelpBeacon(result)
        if (helpBeacon != null) {
            Log.d(TAG, "BLE SOS help packet matched from ${result.device?.address}")
            handleHelpBeacon(helpBeacon)
            return
        }
        val serviceUuids = result.scanRecord?.serviceUuids.orEmpty()
        if (serviceUuids.any { it.uuid == HikerBleProtocol.SOS_HELP_SERVICE_UUID }) {
            Log.d(TAG, "BLE SOS help service matched from ${result.device?.address}")
            connectForSosHelpPayload(result)
            return
        }
        if (!HikerBleProtocol.isSosAdvertisement(result)) {
            return
        }
        val eventId = HikerBleProtocol.sosEventIdFrom(result)
        logPhysicalSosPackage(result, eventId)
        val manufacturerData = result.scanRecord?.getManufacturerSpecificData(
            HikerBleProtocol.MANUFACTURER_ID,
        )
        val serviceUuidText = result.scanRecord
            ?.serviceUuids
            .orEmpty()
            .joinToString(",") { it.uuid.toString() }
        val fingerprint = sosButtonFingerprint(result, eventId)
        val now = System.currentTimeMillis()
        if (hasHandledEvent(fingerprint)) {
            Log.d(TAG, "BLE SOS button duplicate ignored: $fingerprint")
            return
        }
        rememberHandledEvent(fingerprint)
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("instant")
            .appendQueryParameter("source", "ble_button")
            .appendQueryParameter("rssi", result.rssi.toString())
            .appendQueryParameter("receivedAt", now.toString())
            .appendQueryParameter("deviceAddress", result.device?.address ?: "")
            .appendQueryParameter("manufacturerData", hexString(manufacturerData))
            .appendQueryParameter("serviceUuids", serviceUuidText)
            .apply {
                if (eventId != null) {
                    appendQueryParameter("broadcastId", eventId.toString())
                    appendQueryParameter("counter", eventId.toString())
                }
            }
            .build()
        val launchIntent = Intent(Intent.ACTION_VIEW).apply {
            data = deepLink
            setPackage(packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        Log.d(TAG, "Launching BLE SOS workflow: $deepLink")
        startActivity(launchIntent)
    }

    private fun logBleCandidatePackage(result: ScanResult) {
        if (candidatePackageLogCount >= MAX_CANDIDATE_PACKAGE_LOGS) {
            return
        }
        val record = result.scanRecord ?: return
        val serviceUuids = record
            .serviceUuids
            .orEmpty()
            .joinToString(",") { it.uuid.toString() }
        val manufacturers = manufacturerDataSummary(record.manufacturerSpecificData)
        if (serviceUuids.isEmpty() && manufacturers == "none") {
            return
        }
        candidatePackageLogCount += 1
        Log.i(
            TAG,
            "BLE candidate package #$candidatePackageLogCount: " +
                "address=${result.device?.address} rssi=${result.rssi} " +
                "manufacturers=$manufacturers serviceUuids=[$serviceUuids] " +
                "rawScanRecord=${hexString(record.bytes)}",
        )
    }

    private fun logPhysicalSosPackage(result: ScanResult, eventId: Long?) {
        val record = result.scanRecord
        val manufacturerData = record?.getManufacturerSpecificData(
            HikerBleProtocol.MANUFACTURER_ID,
        )
        val serviceUuids = record
            ?.serviceUuids
            .orEmpty()
            .joinToString(",") { it.uuid.toString() }
        Log.i(
            TAG,
            "Physical SOS BLE package: address=${result.device?.address} " +
                "rssi=${result.rssi} eventId=${eventId ?: "none"} " +
                "manufacturerId=0x${HikerBleProtocol.MANUFACTURER_ID.toString(16)} " +
                "manufacturerData=${hexString(manufacturerData)} " +
                "serviceUuids=[$serviceUuids] " +
                "rawScanRecord=${hexString(record?.bytes)}",
        )
    }

    private fun connectForSosHelpPayload(result: ScanResult) {
        if (!hasConnectPermission()) {
            return
        }
        val address = result.device.address ?: return
        val now = System.currentTimeMillis()
        if (activeHelpGatts.containsKey(address) ||
            now - (lastHelpConnectAtMillis[address] ?: 0L) < HELP_GATT_CONNECT_DEBOUNCE_MILLIS
        ) {
            return
        }
        lastHelpConnectAtMillis[address] = now

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
                        closeHelpGatt(gatt)
                    }
                    return
                }
                if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    closeHelpGatt(gatt)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS || !hasConnectPermission()) {
                    closeHelpGatt(gatt)
                    return
                }
                val characteristic = gatt
                    .getService(HikerBleProtocol.SOS_HELP_SERVICE_UUID)
                    ?.getCharacteristic(HikerBleProtocol.SOS_HELP_CHARACTERISTIC_UUID)
                if (characteristic == null) {
                    closeHelpGatt(gatt)
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
                    characteristic.uuid == HikerBleProtocol.SOS_HELP_CHARACTERISTIC_UUID
                ) {
                    HikerBleProtocol.decodeSosHelpBeacon(
                        characteristic.value,
                        result.rssi,
                    )?.let(::handleHelpBeacon)
                }
                closeHelpGatt(gatt)
            }
        }

        runCatching {
            activeHelpGatts[address] = result.device.connectGatt(this, false, callback)
        }.onFailure {
            activeHelpGatts.remove(address)
        }
    }

    private fun closeHelpGatt(gatt: BluetoothGatt) {
        runCatching { gatt.device.address }.getOrNull()?.let(activeHelpGatts::remove)
        runCatching {
            if (hasConnectPermission()) {
                gatt.disconnect()
            }
            gatt.close()
        }
    }

    private fun handleHelpBeacon(packet: HikerBleProtocol.SosHelpBeaconPacket) {
        val fingerprint = sosHelpFingerprint(packet)
        val now = System.currentTimeMillis()
        if (hasHandledEvent(fingerprint)) {
            Log.d(TAG, "BLE SOS help duplicate ignored: $fingerprint")
            return
        }
        rememberHandledEvent(fingerprint)
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("help")
            .appendQueryParameter("source", "ble_sos_test")
            .appendQueryParameter("lat", packet.latitude.toString())
            .appendQueryParameter("lng", packet.longitude.toString())
            .appendQueryParameter("accuracy", packet.accuracyMeters.toString())
            .appendQueryParameter("sentAt", packet.capturedAtMillis.toString())
            .appendQueryParameter("phoneHash", packet.phoneNumberHash.toString())
            .appendQueryParameter("rssi", packet.rssi.toString())
            .appendQueryParameter("receivedAt", now.toString())
            .build()
        val launchIntent = Intent(Intent.ACTION_VIEW).apply {
            data = deepLink
            setPackage(packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        Log.d(TAG, "Launching BLE SOS help workflow: $deepLink")
        startActivity(launchIntent)
    }

    private fun sosButtonFingerprint(result: ScanResult, eventId: Long?): String {
        return eventId?.let { "sos_button:event:$it" }
            ?: result.device?.address?.let { "sos_button_legacy_device:$it" }
            ?: "sos_button_legacy_service:${HikerBleProtocol.SOS_SERVICE_UUID}"
    }

    private fun sosHelpFingerprint(packet: HikerBleProtocol.SosHelpBeaconPacket): String {
        return listOf(
            "sos_help",
            packet.phoneNumberHash,
            packet.latitude,
            packet.longitude,
            packet.accuracyMeters,
            packet.capturedAtMillis,
        ).joinToString(":")
    }

    private fun hasHandledEvent(fingerprint: String): Boolean {
        return handledEventIds.contains(fingerprint)
    }

    private fun rememberHandledEvent(fingerprint: String) {
        if (!handledEventIds.add(fingerprint)) {
            return
        }
        handledEventIdOrder.addLast(fingerprint)
        while (handledEventIdOrder.size > MAX_HANDLED_EVENT_IDS) {
            handledEventIds.remove(handledEventIdOrder.removeFirst())
        }
    }

    private fun hexString(bytes: ByteArray?): String {
        return bytes?.joinToString(" ") { "%02X".format(it.toInt().and(0xFF)) } ?: "none"
    }

    private fun manufacturerDataSummary(
        manufacturerData: SparseArray<ByteArray>?,
    ): String {
        if (manufacturerData == null || manufacturerData.size() == 0) {
            return "none"
        }
        return (0 until manufacturerData.size()).joinToString(";") { index ->
            val manufacturerId = manufacturerData.keyAt(index)
            val bytes = manufacturerData.valueAt(index)
            "0x${manufacturerId.toString(16)}=${hexString(bytes)}"
        }
    }

    private fun notification(): Notification {
        val notificationManager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "SOS button monitor",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Listens for the paired HikerCircle BLE SOS button"
                    setShowBadge(false)
                },
            )
        }
        val contentIntent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("hikercircle://sos/manual?source=ble_monitor")
            setPackage(packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("HikerCircle SOS button ready")
            .setContentText("Listening for your BLE emergency button.")
            .setContentIntent(PendingIntent.getActivity(this, 4212, contentIntent, flags))
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun hasScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }
}
