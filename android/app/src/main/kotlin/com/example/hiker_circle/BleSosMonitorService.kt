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
import android.content.BroadcastReceiver
import android.content.Context
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
        const val ACTION_SOS_BUTTON_DETECTED =
            "com.leongziqi.hikercircle.ble_sos.SOS_BUTTON_DETECTED"
        const val EXTRA_COUNTER = "counter"
        const val EXTRA_RSSI = "rssi"
        const val EXTRA_RECEIVED_AT_MILLIS = "receivedAtMillis"
        const val EXTRA_SOURCE = "source"
        const val EXTRA_EVENT_TYPE = "eventType"
        const val EXTRA_DEVICE_ID = "deviceId"
        const val EXTRA_DISPLAY_NAME = "displayName"
        const val EXTRA_MODE = "mode"
        const val EXTRA_LATITUDE = "latitude"
        const val EXTRA_LONGITUDE = "longitude"
        const val EXTRA_ACCURACY_METERS = "accuracyMeters"
        const val EXTRA_CAPTURED_AT_MILLIS = "capturedAtMillis"
        const val EVENT_PAIRED_OWNER = "pairedOwner"
        const val EVENT_PAIRED_NEARBY = "pairedNearby"
        const val EVENT_PAIRED_LOCATION = "pairedLocation"
        private const val TAG = "HikerBleSosMonitor"
        private const val CHANNEL_ID = "hiker_circle_ble_sos"
        private const val NOTIFICATION_ID = 4211
        // Notification-channel alert behavior is immutable after first creation.
        // Version the ID when changing sound/vibration defaults so upgrades receive them.
        private const val SOS_DETECTED_CHANNEL_ID = "hiker_circle_ble_sos_detected_v2"
        private const val SOS_DETECTED_NOTIFICATION_ID = 4213
        private const val HELP_GATT_CONNECT_DEBOUNCE_MILLIS = 3000L
        private const val MAX_HANDLED_EVENT_IDS = 128
        private const val MAX_CANDIDATE_PACKAGE_LOGS = 40
        private const val MONITOR_PREFS = "hiker_circle_ble_monitor"
        private const val MONITOR_ENABLED = "enabled"
    }

    private val bluetoothManager: BluetoothManager?
        get() = getSystemService(BluetoothManager::class.java)
    private val pairedButtonRegistry by lazy { PairedSosButtonRegistry(this) }
    private var scanCallback: ScanCallback? = null
    private var candidatePackageLogCount = 0
    private val handledEventIds = mutableSetOf<String>()
    private val handledEventIdOrder = ArrayDeque<String>()
    private val activeHelpGatts = mutableMapOf<String, BluetoothGatt>()
    private val lastHelpConnectAtMillis = mutableMapOf<String, Long>()
    private val restartHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val restartRunnable = Runnable {
        if (isMonitorEnabled()) startScan()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
                .edit().putBoolean(MONITOR_ENABLED, false).apply()
            stopSelf()
            return START_NOT_STICKY
        }

        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .edit().putBoolean(MONITOR_ENABLED, true).apply()

        startForeground(NOTIFICATION_ID, notification())
        // A setup scan/GATT pairing session can leave some Android Bluetooth
        // stacks with a registered callback that no longer receives results.
        // ACTION_START is also used after pairing and when the app resumes, so
        // replace the scan registration instead of trusting the old callback.
        if (scanCallback != null) {
            stopScan()
        }
        startScan()
        return START_STICKY
    }

    override fun onDestroy() {
        restartHandler.removeCallbacks(restartRunnable)
        stopScan()
        super.onDestroy()
    }

    private fun isMonitorEnabled(): Boolean =
        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .getBoolean(MONITOR_ENABLED, true)

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
                scanCallback = null
                restartHandler.removeCallbacks(restartRunnable)
                restartHandler.postDelayed(restartRunnable, 2000L)
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
        HikerBleProtocol.decodePairedSosRemote(result)?.let { packet ->
            Log.i(
                TAG,
                "Paired SOS packet decoded: device=${packet.deviceIdHex} " +
                    "event=${packet.eventId} rssi=${packet.rssi}",
            )
            handlePairedSosRemote(packet)
            return
        }
        HikerBleProtocol.decodePairedSosLocationRelay(result)?.let { packet ->
            Log.i(
                TAG,
                "Paired SOS location relay decoded: device=${packet.deviceIdHex} " +
                    "event=${packet.eventId} rssi=${packet.rssi}",
            )
            handlePairedSosLocationRelay(packet)
            return
        }
        if (!HikerBleProtocol.isSosAdvertisement(result)) {
            return
        }
        if (!pairedButtonRegistry.isLegacyUnpairedEnabled()) {
            // Version-1 packets are deliberately opt-in. Treating every
            // nearby legacy packet as this phone's SOS is unsafe.
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
        broadcastSosButtonDetected(eventId, result.rssi, now)
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
        postSosDetectedNotification(deepLink)
        Log.d(TAG, "Launching BLE SOS workflow: $deepLink")
        // Android can defer or block an activity launch from a background
        // foreground service. Keep the direct launch for an active app, and
        // always provide the notification action as a reliable fallback.
        runCatching { startActivity(launchIntent) }
            .onFailure { Log.w(TAG, "Unable to open BLE SOS workflow", it) }
    }

    private fun handlePairedSosRemote(packet: HikerBleProtocol.PairedSosRemotePacket) {
        val fingerprint = "paired_sos:${packet.deviceIdHex}:${packet.eventId}"
        val now = System.currentTimeMillis()
        val owner = pairedButtonRegistry.find(packet.deviceId)
        if (owner == null) {
            Log.i(
                TAG,
                "Paired SOS treated as nearby: device=${packet.deviceIdHex} " +
                    "event=${packet.eventId}",
            )
            if (hasHandledEvent(fingerprint)) return
            rememberHandledEvent(fingerprint)
            broadcastPairedSosEvent(
                eventType = EVENT_PAIRED_NEARBY,
                packet = packet,
                receivedAtMillis = now,
                displayName = null,
            )
            launchNearbyPairedButtonPopup(packet, now)
            return
        }

        if (!pairedButtonRegistry.hasValidTag(owner, packet)) {
            // Do not include packet data, device secret, or expected HMAC in
            // logs. A failed tag must never cause an SOS on the owning phone.
            Log.w(TAG, "Rejected invalid authenticated SOS button packet")
            return
        }
        if (pairedButtonRegistry.isReplay(owner, packet.eventId) || hasHandledEvent(fingerprint)) {
            return
        }
        rememberHandledEvent(fingerprint)
        pairedButtonRegistry.markSeen(packet.deviceId, packet.eventId, accepted = true)
        Log.i(
            TAG,
            "Authenticated owner SOS accepted: device=${packet.deviceIdHex} " +
                "event=${packet.eventId}",
        )
        broadcastPairedSosEvent(
            eventType = EVENT_PAIRED_OWNER,
            packet = packet,
            receivedAtMillis = now,
            displayName = owner.displayName,
        )
        launchOwnerPairedSos(packet, now)
    }

    private fun broadcastPairedSosEvent(
        eventType: String,
        packet: HikerBleProtocol.PairedSosRemotePacket,
        receivedAtMillis: Long,
        displayName: String?,
    ) {
        sendBroadcast(
            Intent(ACTION_SOS_BUTTON_DETECTED).apply {
                setPackage(packageName)
                putExtra(EXTRA_EVENT_TYPE, eventType)
                putExtra(EXTRA_SOURCE, "paired_ble_button")
                putExtra(EXTRA_DEVICE_ID, packet.deviceIdHex)
                putExtra(EXTRA_COUNTER, packet.eventId)
                putExtra(EXTRA_MODE, packet.mode)
                putExtra(EXTRA_RSSI, packet.rssi)
                putExtra(EXTRA_RECEIVED_AT_MILLIS, receivedAtMillis)
                if (displayName != null) putExtra(EXTRA_DISPLAY_NAME, displayName)
            },
        )
    }

    private fun handlePairedSosLocationRelay(
        packet: HikerBleProtocol.PairedSosLocationRelayPacket,
    ) {
        val fingerprint = "paired_sos_location:${packet.deviceIdHex}:${packet.eventId}"
        if (hasHandledEvent(fingerprint)) return
        rememberHandledEvent(fingerprint)
        // The owner already received the authenticated type-4 event and has
        // its own SOS workflow. Do not show that same phone a second nearby
        // location popup; only unpaired/nearby phones need this relay.
        if (pairedButtonRegistry.find(packet.deviceId) != null) {
            return
        }
        val now = System.currentTimeMillis()
        sendBroadcast(
            Intent(ACTION_SOS_BUTTON_DETECTED).apply {
                setPackage(packageName)
                putExtra(EXTRA_EVENT_TYPE, EVENT_PAIRED_LOCATION)
                putExtra(EXTRA_SOURCE, "paired_ble_button_location")
                putExtra(EXTRA_DEVICE_ID, packet.deviceIdHex)
                putExtra(EXTRA_COUNTER, packet.eventId)
                putExtra(EXTRA_LATITUDE, packet.latitude)
                putExtra(EXTRA_LONGITUDE, packet.longitude)
                putExtra(EXTRA_ACCURACY_METERS, packet.accuracyMeters)
                putExtra(EXTRA_RSSI, packet.rssi)
                putExtra(EXTRA_RECEIVED_AT_MILLIS, now)
            },
        )
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("nearby-button-location")
            .appendQueryParameter("source", "paired_ble_button_location")
            .appendQueryParameter("deviceId", packet.deviceIdHex)
            .appendQueryParameter("counter", packet.eventId.toString())
            .appendQueryParameter("latitude", packet.latitude.toString())
            .appendQueryParameter("longitude", packet.longitude.toString())
            .appendQueryParameter("accuracy", packet.accuracyMeters.toString())
            .appendQueryParameter("rssi", packet.rssi.toString())
            .appendQueryParameter("receivedAt", now.toString())
            .build()
        postSosDetectedNotification(deepLink)
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                data = deepLink
                setPackage(packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            })
        }.onFailure { Log.w(TAG, "Unable to open nearby SOS location popup", it) }
    }

    private fun launchOwnerPairedSos(
        packet: HikerBleProtocol.PairedSosRemotePacket,
        receivedAtMillis: Long,
    ) {
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("paired")
            .appendQueryParameter("source", "paired_ble_button")
            .appendQueryParameter("deviceId", packet.deviceIdHex)
            .appendQueryParameter("counter", packet.eventId.toString())
            .appendQueryParameter("rssi", packet.rssi.toString())
            .appendQueryParameter("receivedAt", receivedAtMillis.toString())
            .build()
        postSosDetectedNotification(deepLink)
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                data = deepLink
                setPackage(packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            })
        }.onFailure { Log.w(TAG, "Unable to open paired SOS workflow", it) }
    }

    private fun launchNearbyPairedButtonPopup(
        packet: HikerBleProtocol.PairedSosRemotePacket,
        receivedAtMillis: Long,
    ) {
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("nearby-button")
            .appendQueryParameter("source", "paired_ble_button")
            .appendQueryParameter("deviceId", packet.deviceIdHex)
            .appendQueryParameter("counter", packet.eventId.toString())
            .appendQueryParameter("rssi", packet.rssi.toString())
            .appendQueryParameter("receivedAt", receivedAtMillis.toString())
            .build()
        // This route only opens the non-destructive nearby-button popup.
        postSosDetectedNotification(deepLink)
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                data = deepLink
                setPackage(packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            })
        }.onFailure { Log.w(TAG, "Unable to open nearby-button popup", it) }
    }

    private fun broadcastSosButtonDetected(eventId: Long?, rssi: Int, receivedAtMillis: Long) {
        val intent = Intent(ACTION_SOS_BUTTON_DETECTED).apply {
            setPackage(packageName)
            putExtra(EXTRA_SOURCE, "ble_button")
            putExtra(EXTRA_RSSI, rssi)
            putExtra(EXTRA_RECEIVED_AT_MILLIS, receivedAtMillis)
            if (eventId != null) {
                putExtra(EXTRA_COUNTER, eventId)
            }
        }
        sendBroadcast(intent)
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

    private fun postSosDetectedNotification(deepLink: Uri) {
        val notificationManager = getSystemService(NotificationManager::class.java)
        val isNearbyButton = deepLink.path == "/nearby-button" ||
            deepLink.path == "/nearby-button-location"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    SOS_DETECTED_CHANNEL_ID,
                    "SOS button alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alerts received from the HikerCircle BLE SOS button"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0L, 350L, 180L, 350L)
                },
            )
        }
        val launchIntent = Intent(Intent.ACTION_VIEW).apply {
            data = deepLink
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
            Notification.Builder(this, SOS_DETECTED_CHANNEL_ID)
        } else {
            Notification.Builder(this)
                .setPriority(Notification.PRIORITY_HIGH)
                .setVibrate(longArrayOf(0L, 350L, 180L, 350L))
        }
        notificationManager.notify(
            SOS_DETECTED_NOTIFICATION_ID,
            builder
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(
                    if (isNearbyButton) {
                        "Nearby SOS button pressed"
                    } else {
                        "Your SOS button was pressed"
                    },
                )
                .setContentText(
                    if (isNearbyButton) {
                        "Someone nearby may need help. Tap to view the alert."
                    } else {
                        "Opening the Manual SOS workflow. Tap to return to HikerCircle."
                    },
                )
                .setContentIntent(
                    PendingIntent.getActivity(
                        this,
                        SOS_DETECTED_NOTIFICATION_ID,
                        launchIntent,
                        flags,
                    ),
                )
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_ALARM)
                .build(),
        )
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

/** Restarts the user-enabled BLE monitor after a device reboot or app update. */
class BleSosMonitorBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
            intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val enabled = context
            .getSharedPreferences("hiker_circle_ble_monitor", Context.MODE_PRIVATE)
            .getBoolean("enabled", false)
        if (!enabled) return
        val serviceIntent = Intent(context, BleSosMonitorService::class.java).apply {
            action = BleSosMonitorService.ACTION_START
        }
        runCatching {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
    }
}
