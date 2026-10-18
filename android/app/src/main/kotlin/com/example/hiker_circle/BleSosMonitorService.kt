// BleSosMonitorService scans nearby SOS beacons and paired buttons while Flutter is inactive.
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
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import android.util.SparseArray
import org.json.JSONArray
import org.json.JSONObject

class BleSosMonitorService : Service() {
    companion object {
        const val ACTION_START = "com.leongziqi.hikercircle.ble_sos.START"
        const val ACTION_STOP = "com.leongziqi.hikercircle.ble_sos.STOP"
        const val ACTION_ARM_PAIRED_TEST =
            "com.leongziqi.hikercircle.ble_sos.ARM_PAIRED_TEST"
        const val ACTION_CANCEL_PAIRED_TEST =
            "com.leongziqi.hikercircle.ble_sos.CANCEL_PAIRED_TEST"
        const val ACTION_SOS_BUTTON_DETECTED =
            "com.leongziqi.hikercircle.ble_sos.SOS_BUTTON_DETECTED"
        const val INTERNAL_BLE_SOS_PERMISSION =
            "com.leongziqi.hikercircle.permission.INTERNAL_BLE_SOS"
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
        const val EXTRA_PENDING_OWNER_EVENT_STORED = "pendingOwnerEventStored"
        const val EXTRA_PENDING_NEARBY_EVENT_STORED = "pendingNearbyEventStored"
        const val EXTRA_TEST_DURATION_MILLIS = "testDurationMillis"
        const val EVENT_PAIRED_OWNER = "pairedOwner"
        const val EVENT_PAIRED_TEST = "pairedTest"
        const val EVENT_PAIRED_NEARBY = "pairedNearby"
        const val EVENT_PAIRED_LOCATION = "pairedLocation"
        const val EVENT_SOS_HELP = "sosHelp"
        private const val TAG = "HikerBleSosMonitor"
        private const val CHANNEL_ID = "hiker_circle_ble_sos"
        private const val NOTIFICATION_ID = 4211
        // Notification-channel alert behavior is immutable after first creation.
        // Version the ID when changing sound/vibration defaults so upgrades receive them.
        private const val SOS_DETECTED_CHANNEL_ID = "hiker_circle_ble_sos_detected_v2"
        private const val SOS_DETECTED_NOTIFICATION_ID = 4216
        private const val REGISTRY_ERROR_CHANNEL_ID = "hiker_circle_ble_registry_error"
        private const val REGISTRY_ERROR_NOTIFICATION_ID = 4214
        private const val HELP_GATT_CONNECT_DEBOUNCE_MILLIS = 3000L
        private const val READ_GATT_TIMEOUT_MILLIS = 10000L
        private const val MAX_HANDLED_EVENT_IDS = 256
        private const val HANDLED_EVENT_RETENTION_MILLIS = 24 * 60 * 60 * 1000L
        private const val LEGACY_EVENT_DEBOUNCE_MILLIS = 10000L
        private const val MAX_HELP_PACKET_AGE_MILLIS = 5 * 60 * 1000L
        private const val MAX_HELP_PACKET_FUTURE_SKEW_MILLIS = 2 * 60 * 1000L
        private const val MAX_CANDIDATE_PACKAGE_LOGS = 40
        const val MONITOR_PREFS = "hiker_circle_ble_monitor"
        const val MONITOR_ENABLED = "enabled"
        const val MONITOR_HEARTBEAT_AT_MILLIS = "heartbeatAtMillis"
        const val MONITOR_SCAN_STATE = "scanState"
        const val MONITOR_LAST_SCAN_STARTED_AT_MILLIS = "lastScanStartedAtMillis"
        const val MONITOR_LAST_RESULT_AT_MILLIS = "lastResultAtMillis"
        const val MONITOR_LAST_FAILURE = "lastFailure"
        const val MONITOR_RESTART_COUNT = "restartCount"
        const val LOST_BUTTON_WARNING_ENABLED = "lostButtonWarningEnabled"
        const val LOST_BUTTON_THRESHOLD_MILLIS = "lostButtonThresholdMillis"
        private const val HANDLED_EVENTS = "handledEvents"
        private const val DEFAULT_LOST_BUTTON_THRESHOLD_MILLIS = 15 * 60 * 1000L
        private const val PRESENCE_WRITE_INTERVAL_MILLIS = 30_000L
        private const val WATCHDOG_INTERVAL_MILLIS = 30_000L
        private const val PAIRED_TEST_DEVICE_ID = "pairedTestDeviceId"
        private const val PAIRED_TEST_EXPIRES_AT_MILLIS = "pairedTestExpiresAtMillis"
        const val PENDING_EVENT_PREFS = "hiker_circle_ble_pending_events"
        const val PENDING_OWNER_EVENTS = "paired_owner_events"
        const val PENDING_NEARBY_EVENTS = "paired_nearby_events"
        const val PENDING_HELP_EVENTS = "nearby_help_events"
        private const val MONITOR_WARNING_CHANNEL_ID = "hiker_circle_ble_monitor_warning"
        private const val MONITOR_WARNING_NOTIFICATION_ID = 4215
        private const val LOST_BUTTON_CHANNEL_ID = "hiker_circle_ble_button_lost"
        private const val LOST_BUTTON_NOTIFICATION_BASE_ID = 4300
    }

    private val bluetoothManager: BluetoothManager?
        get() = getSystemService(BluetoothManager::class.java)
    private val pairedButtonRegistry by lazy { PairedSosButtonRegistry(this) }
    private var scanCallback: ScanCallback? = null
    private var candidatePackageLogCount = 0
    private var registryErrorNotified = false
    private val handledEventIds = mutableSetOf<String>()
    private val handledEventIdOrder = ArrayDeque<String>()
    private val handledEventTimes = mutableMapOf<String, Long>()
    private val legacyEventHandledAtMillis = mutableMapOf<String, Long>()
    private val activeHelpGatts = mutableMapOf<String, BluetoothGatt>()
    private val helpGattTimeouts = mutableMapOf<String, Runnable>()
    private val lastHelpConnectAtMillis = mutableMapOf<String, Long>()
    private val restartHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val lastPresenceWriteAtMillis = mutableMapOf<String, Long>()
    private var consecutiveScanFailures = 0
    private val restartRunnable = Runnable {
        if (isMonitorEnabled()) startScan()
    }
    private val watchdogRunnable = object : Runnable {
        override fun run() {
            if (!isMonitorEnabled()) return
            updateMonitorHealth()
            checkLostButtons()
            if (scanCallback == null) startScan()
            restartHandler.postDelayed(this, WATCHDOG_INTERVAL_MILLIS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        loadHandledEvents()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(MONITOR_ENABLED, false)
                .remove(PAIRED_TEST_DEVICE_ID)
                .remove(PAIRED_TEST_EXPIRES_AT_MILLIS)
                .apply()
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_CANCEL_PAIRED_TEST) {
            clearPairedButtonTest()
        } else if (intent?.action == ACTION_ARM_PAIRED_TEST) {
            val deviceId = intent.getStringExtra(EXTRA_DEVICE_ID)
                ?.trim()
                ?.uppercase()
                .orEmpty()
            val durationMillis = intent.getLongExtra(
                EXTRA_TEST_DURATION_MILLIS,
                30_000L,
            ).coerceIn(5_000L, 30_000L)
            if (deviceId.matches(Regex("[0-9A-F]{12}"))) {
                getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
                    .edit()
                    .putString(PAIRED_TEST_DEVICE_ID, deviceId)
                    .putLong(
                        PAIRED_TEST_EXPIRES_AT_MILLIS,
                        System.currentTimeMillis() + durationMillis,
                    )
                    .apply()
            } else {
                clearPairedButtonTest()
            }
        }

        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .edit().putBoolean(MONITOR_ENABLED, true).apply()

        if (!hasScanPermission() || !hasConnectPermission()) {
            updateMonitorHealth(state = "permission_missing", failure = "Bluetooth permission is missing")
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, notification())
        } catch (error: RuntimeException) {
            // Permissions may change between the Activity check and service start.
            updateMonitorHealth(state = "start_failed", failure = error.message)
            stopSelf()
            return START_NOT_STICKY
        }
        updateMonitorHealth(state = "starting")
        // A setup scan/GATT pairing session can leave some Android Bluetooth
        // stacks with a registered callback that no longer receives results.
        // ACTION_START is also used after pairing and when the app resumes, so
        // replace the scan registration instead of trusting the old callback.
        if (scanCallback != null) {
            stopScan()
        }
        startScan()
        restartHandler.removeCallbacks(watchdogRunnable)
        restartHandler.postDelayed(watchdogRunnable, WATCHDOG_INTERVAL_MILLIS)
        return START_STICKY
    }

    override fun onDestroy() {
        restartHandler.removeCallbacks(restartRunnable)
        restartHandler.removeCallbacks(watchdogRunnable)
        stopScan()
        updateMonitorHealth(state = "stopped")
        super.onDestroy()
    }

    private fun isMonitorEnabled(): Boolean =
        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .getBoolean(MONITOR_ENABLED, true)

    private fun startScan() {
        if (!hasScanPermission()) {
            Log.w(TAG, "BLE SOS scan stopped: scan permission is missing")
            updateMonitorHealth(state = "permission_missing", failure = "Bluetooth scan permission is missing")
            postMonitorWarning("Bluetooth scan permission is missing. Open HikerCircle to restore SOS monitoring.")
            stopSelf()
            return
        }
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: run {
            // Bluetooth may be toggled off temporarily while the monitor is
            // enabled. Keep the foreground service alive and recover without
            // requiring the user to reopen HikerCircle.
            Log.w(TAG, "BLE SOS scanner is unavailable; retrying")
            updateMonitorHealth(state = "bluetooth_unavailable", failure = "Bluetooth is disabled or unavailable")
            restartHandler.removeCallbacks(restartRunnable)
            restartHandler.postDelayed(restartRunnable, 5000L)
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
                consecutiveScanFailures += 1
                incrementMonitorRestartCount()
                updateMonitorHealth(state = "scan_failed", failure = "Android BLE scan error $errorCode")
                if (consecutiveScanFailures >= 3) {
                    postMonitorWarning("SOS button monitoring is repeatedly failing. Open HikerCircle to retry.")
                }
                restartHandler.removeCallbacks(restartRunnable)
                restartHandler.postDelayed(restartRunnable, 2000L)
            }
        }
        scanCallback = callback
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                }
            }
            .build()
        val packetMask = byteArrayOf(
            0xff.toByte(),
            0xff.toByte(),
            0xff.toByte(),
            0xff.toByte(),
        )
        val filters = listOf(
            // Controller-side filters are required for reliable delivery when
            // the screen is off on many Android Bluetooth stacks. Each filter
            // is OR-ed; packet contents are still fully authenticated below.
            ScanFilter.Builder().setManufacturerData(
                HikerBleProtocol.MANUFACTURER_ID,
                byteArrayOf(0x48, 0x43, 0x01, 0x01),
                packetMask,
            ).build(),
            ScanFilter.Builder().setManufacturerData(
                HikerBleProtocol.MANUFACTURER_ID,
                byteArrayOf(0x48, 0x43, 0x01, 0x03),
                packetMask,
            ).build(),
            ScanFilter.Builder().setManufacturerData(
                HikerBleProtocol.MANUFACTURER_ID,
                byteArrayOf(0x48, 0x43, 0x02, 0x04),
                packetMask,
            ).build(),
            ScanFilter.Builder().setManufacturerData(
                HikerBleProtocol.MANUFACTURER_ID,
                byteArrayOf(0x48, 0x43, 0x02, 0x05),
                packetMask,
            ).build(),
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(HikerBleProtocol.SOS_SERVICE_UUID))
                .build(),
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(HikerBleProtocol.SOS_HELP_SERVICE_UUID))
                .build(),
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(HikerBleProtocol.PAIRED_BUTTON_MAINTENANCE_SERVICE_UUID))
                .build(),
        )
        runCatching { scanner.startScan(filters, settings, callback) }
            .onSuccess {
                consecutiveScanFailures = 0
                updateMonitorHealth(state = "scanning", scanStarted = true)
                cancelMonitorWarning()
                Log.d(TAG, "BLE SOS scan started with locked-screen hardware filters")
            }
            .onFailure { error ->
                scanCallback = null
                consecutiveScanFailures += 1
                incrementMonitorRestartCount()
                updateMonitorHealth(state = "scan_failed", failure = error.message ?: "Unable to start BLE scan")
                Log.w(TAG, "BLE SOS scan could not start", error)
                restartHandler.removeCallbacks(restartRunnable)
                restartHandler.postDelayed(restartRunnable, 2000L)
            }
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

    // handleScanResult: Separate paired-button events from nearby-help beacons before dispatch.
    private fun handleScanResult(result: ScanResult) {
        ButtonDebugTrace.advertisement(result)
        updateMonitorHealth(resultReceived = true)
        val serviceUuids = result.scanRecord?.serviceUuids.orEmpty()
        if (serviceUuids.any {
                it.uuid == HikerBleProtocol.PAIRED_BUTTON_MAINTENANCE_SERVICE_UUID
            }
        ) {
            handlePairedButtonPresence(result)
            return
        }
        logBleCandidatePackage(result)
        val helpBeacon = HikerBleProtocol.decodeSosHelpBeacon(result)
        if (helpBeacon != null) {
            Log.d(TAG, "BLE SOS help packet matched from ${result.device?.address}")
            handleHelpBeacon(helpBeacon)
            return
        }
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
        val isDuplicate = if (eventId == null) {
            val debounceNow = android.os.SystemClock.elapsedRealtime()
            val lastHandledAt = legacyEventHandledAtMillis[fingerprint]
            val duplicate = lastHandledAt != null &&
                debounceNow - lastHandledAt < LEGACY_EVENT_DEBOUNCE_MILLIS
            if (!duplicate) {
                legacyEventHandledAtMillis[fingerprint] = debounceNow
            }
            duplicate
        } else {
            hasHandledEvent(fingerprint)
        }
        if (isDuplicate) {
            Log.d(TAG, "BLE SOS button duplicate ignored: $fingerprint")
            return
        }
        if (eventId == null) {
            if (legacyEventHandledAtMillis.size > MAX_HANDLED_EVENT_IDS) {
                legacyEventHandledAtMillis.minByOrNull { it.value }?.key?.let {
                    legacyEventHandledAtMillis.remove(it)
                }
            }
        } else {
            rememberHandledEvent(fingerprint)
        }
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
        val owner = runCatching { pairedButtonRegistry.find(packet.deviceId) }.getOrElse {
            Log.e(TAG, "Unable to read paired SOS ownership; packet ignored safely", it)
            postRegistryErrorNotification()
            return
        }
        if (owner == null) {
            if (packet.mode == 2) {
                // Firmware-authenticated test packets are deliberately silent
                // on every non-owner phone and are never forwarded.
                rememberHandledEvent(fingerprint)
                Log.i(TAG, "Nearby paired-button test packet ignored safely")
                return
            }
            Log.i(
                TAG,
                "Paired SOS treated as nearby: device=${packet.deviceIdHex} " +
                    "event=${packet.eventId}",
            )
            if (hasHandledEvent(fingerprint)) return
            val pendingStored = persistPendingNearbyEvent(
                eventType = EVENT_PAIRED_NEARBY,
                fingerprint = fingerprint,
                deviceId = packet.deviceIdHex,
                counter = packet.eventId,
                rssi = packet.rssi,
                receivedAtMillis = now,
            )
            rememberHandledEvent(fingerprint)
            broadcastPairedSosEvent(
                eventType = EVENT_PAIRED_NEARBY,
                packet = packet,
                receivedAtMillis = now,
                displayName = null,
                pendingNearbyEventStored = pendingStored,
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
        if (isPairedButtonTestArmed(packet, now)) {
            rememberHandledEvent(fingerprint)
            val accepted = runCatching {
                pairedButtonRegistry.markSeen(packet.deviceId, packet.eventId, accepted = true)
            }.onFailure {
                Log.e(TAG, "Unable to persist paired SOS test replay state", it)
            }.isSuccess
            if (accepted) {
                clearPairedButtonTest()
                broadcastPairedSosEvent(
                    eventType = EVENT_PAIRED_TEST,
                    packet = packet,
                    receivedAtMillis = now,
                    displayName = owner.displayName,
                )
                Log.i(
                    TAG,
                    "Authenticated owner button press consumed by local test mode",
                )
            }
            return
        }
        if (packet.mode != 1) {
            // A test packet without a matching local arm window must fail
            // closed; it can neither open SOS nor become a nearby incident.
            rememberHandledEvent(fingerprint)
            runCatching {
                pairedButtonRegistry.markSeen(packet.deviceId, packet.eventId, accepted = true)
            }
            Log.w(TAG, "Unexpected authenticated test packet ignored safely")
            return
        }
        // The durable owner inbox is the source of truth when Flutter is not
        // running. Commit it before advancing replay state; otherwise a crash
        // between those writes could make a genuine SOS permanently
        // undeliverable. If the inbox write fails, leave replay state untouched
        // so a later advertisement can retry.
        val pendingStored = persistPendingOwnerEvent(packet, now, owner.displayName)
        if (pendingStored) {
            rememberHandledEvent(fingerprint)
            runCatching {
                pairedButtonRegistry.markSeen(packet.deviceId, packet.eventId, accepted = true)
            }.onFailure {
                // The durable event still survives. A duplicate after process
                // death is safer than losing an emergency.
                Log.e(TAG, "Unable to persist paired SOS replay state", it)
            }
        } else {
            Log.e(TAG, "Owner SOS inbox commit failed; replay state was not advanced")
        }
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
            pendingOwnerEventStored = pendingStored,
        )
        launchOwnerPairedSos(packet, now)
    }

    private fun isPairedButtonTestArmed(
        packet: HikerBleProtocol.PairedSosRemotePacket,
        now: Long,
    ): Boolean {
        val preferences = getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
        val expiresAt = preferences.getLong(PAIRED_TEST_EXPIRES_AT_MILLIS, 0L)
        if (expiresAt <= now) {
            if (expiresAt != 0L) clearPairedButtonTest()
            return false
        }
        val deviceId = preferences.getString(PAIRED_TEST_DEVICE_ID, null)
        return packet.mode == 2 && deviceId == packet.deviceIdHex
    }

    private fun clearPairedButtonTest() {
        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .edit()
            .remove(PAIRED_TEST_DEVICE_ID)
            .remove(PAIRED_TEST_EXPIRES_AT_MILLIS)
            .apply()
    }

    private fun broadcastPairedSosEvent(
        eventType: String,
        packet: HikerBleProtocol.PairedSosRemotePacket,
        receivedAtMillis: Long,
        displayName: String?,
        pendingOwnerEventStored: Boolean = false,
        pendingNearbyEventStored: Boolean = false,
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
                putExtra(EXTRA_PENDING_OWNER_EVENT_STORED, pendingOwnerEventStored)
                putExtra(EXTRA_PENDING_NEARBY_EVENT_STORED, pendingNearbyEventStored)
                if (displayName != null) putExtra(EXTRA_DISPLAY_NAME, displayName)
            },
            INTERNAL_BLE_SOS_PERMISSION,
        )
    }

    // persistPendingOwnerEvent: Persist an owner SOS event before waking the Flutter handler.
    private fun persistPendingOwnerEvent(
        packet: HikerBleProtocol.PairedSosRemotePacket,
        receivedAtMillis: Long,
        displayName: String,
    ): Boolean {
        val ownerScope = pairedButtonRegistry.activeOwnerScopeToken() ?: return false
        val preferences = getSharedPreferences(PENDING_EVENT_PREFS, MODE_PRIVATE)
        return runCatching {
            val pending = preferences.getString(PENDING_OWNER_EVENTS, null)
                ?.let(::JSONArray)
                ?: JSONArray()
            val fingerprint = "${packet.deviceIdHex}:${packet.eventId}"
            for (index in pending.length() - 1 downTo 0) {
                val item = pending.optJSONObject(index) ?: continue
                if (item.optString("fingerprint") == fingerprint &&
                    item.optString("ownerScope") == ownerScope
                ) {
                    pending.remove(index)
                }
            }
            pending.put(
                JSONObject()
                    .put("fingerprint", fingerprint)
                    .put("ownerScope", ownerScope)
                    .put("deviceId", packet.deviceIdHex)
                    .put("displayName", displayName)
                    .put("counter", packet.eventId)
                    .put("mode", packet.mode)
                    .put("rssi", packet.rssi)
                    .put("receivedAtMillis", receivedAtMillis),
            )
            while (pending.length() > 16) pending.remove(0)
            preferences.edit()
                .putString(PENDING_OWNER_EVENTS, pending.toString())
                .commit()
        }.onFailure {
            Log.e(TAG, "Unable to persist authenticated paired SOS event", it)
        }.getOrDefault(false)
    }

    private fun handlePairedSosLocationRelay(
        packet: HikerBleProtocol.PairedSosLocationRelayPacket,
    ) {
        val fingerprint = "paired_sos_location:${packet.deviceIdHex}:${packet.eventId}"
        if (hasHandledEvent(fingerprint)) return
        // The owner already received the authenticated type-4 event and has
        // its own SOS workflow. Do not show that same phone a second nearby
        // location popup; only unpaired/nearby phones need this relay.
        val isOwned = runCatching {
            pairedButtonRegistry.find(packet.deviceId) != null
        }.getOrElse {
            Log.e(TAG, "Unable to read paired SOS ownership; relay ignored safely", it)
            postRegistryErrorNotification()
            return
        }
        if (isOwned) {
            return
        }
        val now = System.currentTimeMillis()
        val pendingStored = persistPendingNearbyEvent(
            eventType = EVENT_PAIRED_LOCATION,
            fingerprint = fingerprint,
            deviceId = packet.deviceIdHex,
            counter = packet.eventId,
            rssi = packet.rssi,
            receivedAtMillis = now,
            latitude = packet.latitude,
            longitude = packet.longitude,
            accuracyMeters = packet.accuracyMeters,
        )
        rememberHandledEvent(fingerprint)
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
                putExtra(EXTRA_PENDING_NEARBY_EVENT_STORED, pendingStored)
            },
            INTERNAL_BLE_SOS_PERMISSION,
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

    private fun persistPendingNearbyEvent(
        eventType: String,
        fingerprint: String,
        deviceId: String,
        counter: Long,
        rssi: Int,
        receivedAtMillis: Long,
        latitude: Double? = null,
        longitude: Double? = null,
        accuracyMeters: Double? = null,
    ): Boolean {
        val ownerScope = pairedButtonRegistry.activeOwnerScopeToken() ?: return false
        val preferences = getSharedPreferences(PENDING_EVENT_PREFS, MODE_PRIVATE)
        return runCatching {
            val pending = preferences.getString(PENDING_NEARBY_EVENTS, null)
                ?.let(::JSONArray)
                ?: JSONArray()
            for (index in pending.length() - 1 downTo 0) {
                val item = pending.optJSONObject(index) ?: continue
                if (item.optString("fingerprint") == fingerprint &&
                    item.optString("ownerScope") == ownerScope
                ) {
                    pending.remove(index)
                }
            }
            val item = JSONObject()
                .put("fingerprint", fingerprint)
                .put("ownerScope", ownerScope)
                .put("eventType", eventType)
                .put("deviceId", deviceId)
                .put("counter", counter)
                .put("rssi", rssi)
                .put("receivedAtMillis", receivedAtMillis)
            if (latitude != null && longitude != null) {
                item.put("latitude", latitude)
                item.put("longitude", longitude)
                if (accuracyMeters != null) item.put("accuracyMeters", accuracyMeters)
            }
            pending.put(item)
            while (pending.length() > 16) pending.remove(0)
            preferences.edit()
                .putString(PENDING_NEARBY_EVENTS, pending.toString())
                .commit()
        }.onFailure {
            Log.e(TAG, "Unable to persist nearby paired SOS event", it)
        }.getOrDefault(false)
    }

    private fun launchOwnerPairedSos(
        packet: HikerBleProtocol.PairedSosRemotePacket,
        receivedAtMillis: Long,
    ) {
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("active")
            .appendQueryParameter("source", "trusted_ble_event_pending")
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
        sendBroadcast(intent, INTERNAL_BLE_SOS_PERMISSION)
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
                ButtonDebugTrace.read(gatt, characteristic)
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
            ButtonDebugTrace.gatt("RX", "read_response", gatt, characteristic, if (status == BluetoothGatt.GATT_SUCCESS) (characteristic.value ?: byteArrayOf()) else byteArrayOf(), "GATT $status")
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
            val gatt = result.device.connectGatt(this, false, callback)
            activeHelpGatts[address] = gatt
            val timeout = Runnable {
                if (activeHelpGatts[address] === gatt) closeHelpGatt(gatt)
            }
            helpGattTimeouts[address] = timeout
            restartHandler.postDelayed(timeout, READ_GATT_TIMEOUT_MILLIS)
        }.onFailure {
            activeHelpGatts.remove(address)
            helpGattTimeouts.remove(address)?.let(restartHandler::removeCallbacks)
        }
    }

    private fun closeHelpGatt(gatt: BluetoothGatt) {
        runCatching { gatt.device.address }.getOrNull()?.let { address ->
            activeHelpGatts.remove(address)
            helpGattTimeouts.remove(address)?.let(restartHandler::removeCallbacks)
        }
        runCatching {
            if (hasConnectPermission()) {
                gatt.disconnect()
            }
            gatt.close()
        }
    }

    private fun handleHelpBeacon(packet: HikerBleProtocol.SosHelpBeaconPacket) {
        val now = System.currentTimeMillis()
        if (packet.capturedAtMillis > now + MAX_HELP_PACKET_FUTURE_SKEW_MILLIS ||
            now - packet.capturedAtMillis > MAX_HELP_PACKET_AGE_MILLIS
        ) {
            Log.w(
                TAG,
                "BLE SOS help packet outside the accepted time window; ignoring it.",
            )
            return
        }
        val fingerprint = sosHelpFingerprint(packet)
        if (hasHandledEvent(fingerprint)) {
            Log.d(TAG, "BLE SOS help duplicate ignored: $fingerprint")
            return
        }
        rememberHandledEvent(fingerprint)
        persistPendingHelpEvent(packet, now, fingerprint)
        sendBroadcast(
            Intent(ACTION_SOS_BUTTON_DETECTED).apply {
                setPackage(packageName)
                putExtra(EXTRA_EVENT_TYPE, EVENT_SOS_HELP)
                putExtra(EXTRA_SOURCE, "ble_sos_test")
            },
            INTERNAL_BLE_SOS_PERMISSION,
        )
        val deepLink = Uri.Builder()
            .scheme("hikercircle")
            .authority("sos")
            .path("help")
            .appendQueryParameter("source", "trusted_ble_event_pending")
            .build()
        val launchIntent = Intent(Intent.ACTION_VIEW).apply {
            data = deepLink
            setPackage(packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        Log.d(TAG, "Launching BLE SOS help workflow: $deepLink")
        runCatching { startActivity(launchIntent) }
            .onFailure { Log.w(TAG, "Unable to foreground nearby SOS help", it) }
        postSosDetectedNotification(deepLink)
    }

    private fun persistPendingHelpEvent(
        packet: HikerBleProtocol.SosHelpBeaconPacket,
        receivedAtMillis: Long,
        fingerprint: String,
    ) {
        val preferences = getSharedPreferences(PENDING_EVENT_PREFS, MODE_PRIVATE)
        runCatching {
            val pending = preferences.getString(PENDING_HELP_EVENTS, null)
                ?.let(::JSONArray)
                ?: JSONArray()
            for (index in pending.length() - 1 downTo 0) {
                if (pending.optJSONObject(index)?.optString("fingerprint") == fingerprint) {
                    pending.remove(index)
                }
            }
            pending.put(
                JSONObject()
                    .put("fingerprint", fingerprint)
                    .put("phoneNumberHash", packet.phoneNumberHash)
                    .put("latitude", packet.latitude)
                    .put("longitude", packet.longitude)
                    .put("accuracyMeters", packet.accuracyMeters)
                    .put("capturedAtMillis", packet.capturedAtMillis)
                    .put("receivedAtMillis", receivedAtMillis)
                    .put("rssi", packet.rssi),
            )
            while (pending.length() > 16) pending.remove(0)
            check(
                preferences.edit()
                    .putString(PENDING_HELP_EVENTS, pending.toString())
                    .commit(),
            ) { "Unable to save nearby SOS help event." }
        }.onFailure {
            Log.e(TAG, "Unable to persist nearby SOS help event", it)
        }
    }

    private fun sosButtonFingerprint(result: ScanResult, eventId: Long?): String {
        val address = result.device?.address
        return eventId?.let { "sos_button:event:${address ?: "unknown"}:$it" }
            ?: address?.let { "sos_button_legacy_device:$it" }
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

    // hasHandledEvent: Reject an already handled BLE event across scan callbacks and restarts.
    private fun hasHandledEvent(fingerprint: String): Boolean {
        val handledAt = handledEventTimes[fingerprint] ?: return false
        if (System.currentTimeMillis() - handledAt > HANDLED_EVENT_RETENTION_MILLIS) {
            handledEventTimes.remove(fingerprint)
            handledEventIds.remove(fingerprint)
            handledEventIdOrder.remove(fingerprint)
            persistHandledEvents()
            return false
        }
        return handledEventIds.contains(fingerprint)
    }

    private fun rememberHandledEvent(fingerprint: String) {
        if (!handledEventIds.add(fingerprint)) {
            return
        }
        handledEventIdOrder.addLast(fingerprint)
        handledEventTimes[fingerprint] = System.currentTimeMillis()
        while (handledEventIdOrder.size > MAX_HANDLED_EVENT_IDS) {
            val removed = handledEventIdOrder.removeFirst()
            handledEventIds.remove(removed)
            handledEventTimes.remove(removed)
        }
        persistHandledEvents()
    }

    private fun loadHandledEvents() {
        val now = System.currentTimeMillis()
        val stored = getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .getString(HANDLED_EVENTS, null) ?: return
        runCatching {
            val objectValue = JSONObject(stored)
            val keys = objectValue.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val handledAt = objectValue.optLong(key, 0L)
                if (handledAt > 0L && now - handledAt <= HANDLED_EVENT_RETENTION_MILLIS) {
                    handledEventIds.add(key)
                    handledEventIdOrder.addLast(key)
                    handledEventTimes[key] = handledAt
                }
            }
        }.onFailure { Log.w(TAG, "Unable to restore BLE incident deduplication state", it) }
    }

    private fun persistHandledEvents() {
        val payload = JSONObject()
        handledEventIdOrder.forEach { key ->
            handledEventTimes[key]?.let { payload.put(key, it) }
        }
        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .edit().putString(HANDLED_EVENTS, payload.toString()).apply()
    }

    private fun handlePairedButtonPresence(result: ScanResult) {
        val address = result.device?.address?.uppercase() ?: return
        val now = System.currentTimeMillis()
        val previous = lastPresenceWriteAtMillis[address] ?: 0L
        if (now - previous < PRESENCE_WRITE_INTERVAL_MILLIS) return
        lastPresenceWriteAtMillis[address] = now
        runCatching { pairedButtonRegistry.markSeenByAddress(address) }
            .onSuccess { deviceId ->
                if (deviceId != null) {
                    cancelLostButtonWarning(deviceId)
                    Log.d(TAG, "Paired SOS button presence refreshed: $deviceId")
                }
            }
            .onFailure { Log.w(TAG, "Unable to persist paired button presence", it) }
    }

    private fun updateMonitorHealth(
        state: String? = null,
        failure: String? = null,
        scanStarted: Boolean = false,
        resultReceived: Boolean = false,
    ) {
        val now = System.currentTimeMillis()
        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE).edit().apply {
            putLong(MONITOR_HEARTBEAT_AT_MILLIS, now)
            if (state != null) putString(MONITOR_SCAN_STATE, state)
            if (scanStarted) putLong(MONITOR_LAST_SCAN_STARTED_AT_MILLIS, now)
            if (resultReceived) putLong(MONITOR_LAST_RESULT_AT_MILLIS, now)
            if (failure == null && state == "scanning") remove(MONITOR_LAST_FAILURE)
            if (failure != null) putString(MONITOR_LAST_FAILURE, failure)
        }.apply()
    }

    private fun incrementMonitorRestartCount() {
        val prefs = getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
        prefs.edit().putInt(
            MONITOR_RESTART_COUNT,
            prefs.getInt(MONITOR_RESTART_COUNT, 0) + 1,
        ).apply()
    }

    // checkLostButtons: Detect stale paired-button presence and update the disconnect warning.
    private fun checkLostButtons() {
        val prefs = getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
        if (!prefs.getBoolean(LOST_BUTTON_WARNING_ENABLED, true)) return
        val threshold = prefs.getLong(
            LOST_BUTTON_THRESHOLD_MILLIS,
            DEFAULT_LOST_BUTTON_THRESHOLD_MILLIS,
        ).coerceIn(5 * 60 * 1000L, 24 * 60 * 60 * 1000L)
        val now = System.currentTimeMillis()
        runCatching { pairedButtonRegistry.buttons() }.getOrDefault(emptyList()).forEach { button ->
            val reference = button.lastSeenAtMillis ?: button.pairedAtMillis
            if (now - reference >= threshold) {
                postLostButtonWarning(button.deviceIdHex, button.displayName, threshold)
            }
        }
    }

    private fun postMonitorWarning(message: String) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                MONITOR_WARNING_CHANNEL_ID,
                "SOS monitoring warnings",
                NotificationManager.IMPORTANCE_HIGH,
            ))
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("hikercircle://sos/device-settings?source=monitor_watchdog")
            setPackage(packageName)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MONITOR_WARNING_CHANNEL_ID)
        } else Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        manager.notify(MONITOR_WARNING_NOTIFICATION_ID, builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("SOS button monitoring needs attention")
            .setContentText(message)
            .setContentIntent(PendingIntent.getActivity(this, MONITOR_WARNING_NOTIFICATION_ID, intent, flags))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_ERROR)
            .build())
    }

    private fun cancelMonitorWarning() {
        getSystemService(NotificationManager::class.java).cancel(MONITOR_WARNING_NOTIFICATION_ID)
    }

    private fun lostNotificationId(deviceId: String): Int =
        LOST_BUTTON_NOTIFICATION_BASE_ID + (deviceId.hashCode().and(0x3ff))

    private fun postLostButtonWarning(deviceId: String, displayName: String, threshold: Long) {
        val prefs = getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
        val key = "lostNotified:$deviceId"
        if (prefs.getBoolean(key, false)) return
        prefs.edit().putBoolean(key, true).apply()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                LOST_BUTTON_CHANNEL_ID,
                "SOS button lost warnings",
                NotificationManager.IMPORTANCE_HIGH,
            ))
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("hikercircle://sos/device-settings?source=lost_button")
            setPackage(packageName)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val minutes = threshold / 60_000L
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, LOST_BUTTON_CHANNEL_ID)
        } else Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        manager.notify(lostNotificationId(deviceId), builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("$displayName has not been seen")
            .setContentText("No BLE presence for $minutes minutes. Check its power and keep it nearby.")
            .setContentIntent(PendingIntent.getActivity(this, lostNotificationId(deviceId), intent, flags))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_ERROR)
            .build())
    }

    private fun cancelLostButtonWarning(deviceId: String) {
        getSharedPreferences(MONITOR_PREFS, MODE_PRIVATE)
            .edit().remove("lostNotified:$deviceId").apply()
        getSystemService(NotificationManager::class.java).cancel(lostNotificationId(deviceId))
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
            deepLink.path == "/nearby-button-location" ||
            deepLink.path == "/help"
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

    private fun postRegistryErrorNotification() {
        if (registryErrorNotified) return
        registryErrorNotified = true
        val notificationManager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    REGISTRY_ERROR_CHANNEL_ID,
                    "SOS button setup alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alerts when secure SOS button pairing data needs attention"
                },
            )
        }
        val launchIntent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("hikercircle://sos/device-settings?source=ble_registry_error")
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
            Notification.Builder(this, REGISTRY_ERROR_CHANNEL_ID)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        }
        notificationManager.notify(
            REGISTRY_ERROR_NOTIFICATION_ID,
            builder
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("SOS button needs attention")
                .setContentText("Secure pairing data could not be read. Open HikerCircle and re-pair the button.")
                .setContentIntent(
                    PendingIntent.getActivity(
                        this,
                        REGISTRY_ERROR_NOTIFICATION_ID,
                        launchIntent,
                        flags,
                    ),
                )
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_ERROR)
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
