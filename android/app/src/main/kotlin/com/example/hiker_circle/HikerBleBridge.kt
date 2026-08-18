package com.leongziqi.hikercircle

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothDevice
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
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.UUID
import org.json.JSONArray

class HikerBleBridge(
    private val activity: Activity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val METHOD_CHANNEL = "hiker_circle/ble_bridge"
        private const val EVENT_CHANNEL = "hiker_circle/ble_events"
        private const val PERMISSION_REQUEST_CODE = 8511
        private const val GATT_OPERATION_TIMEOUT_MILLIS = 30000L
        private const val SECURE_BOND_TIMEOUT_MILLIS = 45000L
        private const val READ_GATT_TIMEOUT_MILLIS = 10000L
        private const val PAIRING_CONFIRMATION_TIMEOUT_MILLIS = 15000L
        private const val MAX_PENDING_SOS_AGE_MILLIS = 5 * 60 * 1000L
        private const val MAX_PENDING_SOS_FUTURE_SKEW_MILLIS = 2 * 60 * 1000L
        private const val TAG = "HikerBleBridge"
    }

    private val bluetoothManager: BluetoothManager?
        get() = activity.getSystemService(BluetoothManager::class.java)
    private val pairedButtonRegistry by lazy { PairedSosButtonRegistry(activity) }
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var isActivityResumed = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionAction: (() -> Unit)? = null
    private var teamScanCallback: ScanCallback? = null
    private var pairedButtonSetupScanCallback: ScanCallback? = null
    private var teamAdvertiseCallback: AdvertiseCallback? = null
    private var sosTestAdvertiseCallback: AdvertiseCallback? = null
    private var latestTeamPayload: Map<String, Any?>? = null
    private val activeTeamGatts = mutableMapOf<String, BluetoothGatt>()
    private val teamGattTimeouts = mutableMapOf<String, Runnable>()
    private val lastTeamConnectAtMillis = mutableMapOf<String, Long>()
    private val handledTeamPackets = mutableSetOf<String>()
    private val handledTeamPacketOrder = ArrayDeque<String>()
    private val teamGattConnectDebounceMillis = 10000L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pairingGatt: BluetoothGatt? = null
    private var pairingAttempt: PairingAttempt? = null
    private var pairingResult: MethodChannel.Result? = null
    private var bondStateReceiverRegistered = false
    private var locationGatt: BluetoothGatt? = null
    private var locationPayload: ByteArray? = null
    private var locationResult: MethodChannel.Result? = null
    private val locationTimeout = Runnable {
        finishLocationHandoff(
            success = false,
            errorCode = "paired_button_location_timeout",
            errorMessage = "The SOS button location handoff timed out.",
        )
    }
    private var logGatt: BluetoothGatt? = null
    private var logButton: PairedSosButtonRegistry.Button? = null
    private var logResult: MethodChannel.Result? = null
    private var logAuthCharacteristic: BluetoothGattCharacteristic? = null
    private var logPageCharacteristic: BluetoothGattCharacteristic? = null
    private var logDataCharacteristic: BluetoothGattCharacteristic? = null
    private var logServiceCacheRefreshAttempted = false
    private val downloadedLogRecords = mutableListOf<HikerBleProtocol.LogRecord>()
    private var nextLogPage = 0
    private var expectedLogPages = 1
    private val pairingOperationTimeout = Runnable {
        finishPairing(
            success = false,
            errorCode = "paired_button_pairing_timeout",
            errorMessage = "Android secure pairing or the SOS button connection timed out.",
        )
    }
    private val pairingTimeout = Runnable {
        finishPairing(
            success = false,
            errorCode = "paired_button_confirmation_timeout",
            errorMessage = "The button was not physically confirmed within 15 seconds.",
        )
    }
    private val logDownloadTimeout = Runnable {
        finishLogDownload(
            success = false,
            errorCode = "paired_button_log_timeout",
            errorMessage = "The SOS button log download timed out.",
        )
    }

    private data class PairingAttempt(
        val address: String,
        val displayName: String,
        val deviceId: ByteArray,
        val pairingSecret: ByteArray,
        val ownerScope: String,
        var requestCharacteristic: BluetoothGattCharacteristic? = null,
        var statusCharacteristic: BluetoothGattCharacteristic? = null,
        var serviceCacheRefreshAttempted: Boolean = false,
    )
    private val sosButtonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BleSosMonitorService.ACTION_SOS_BUTTON_DETECTED) {
                return
            }
            when (intent.getStringExtra(BleSosMonitorService.EXTRA_EVENT_TYPE)) {
                BleSosMonitorService.EVENT_PAIRED_OWNER -> {
                    if (intent.getBooleanExtra(
                            BleSosMonitorService.EXTRA_PENDING_OWNER_EVENT_STORED,
                            false,
                        )
                    ) {
                        if (isActivityResumed) drainPendingOwnerEvents()
                        return
                    }
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
                BleSosMonitorService.EVENT_PAIRED_TEST -> {
                    emitPairedSosButtonTest(
                        deviceId = intent.getStringExtra(BleSosMonitorService.EXTRA_DEVICE_ID) ?: return,
                        displayName = intent.getStringExtra(BleSosMonitorService.EXTRA_DISPLAY_NAME),
                        counter = intent.getLongExtra(BleSosMonitorService.EXTRA_COUNTER, 0L),
                        rssi = intent.getIntExtra(BleSosMonitorService.EXTRA_RSSI, 0),
                        receivedAtMillis = intent.getLongExtra(
                            BleSosMonitorService.EXTRA_RECEIVED_AT_MILLIS,
                            System.currentTimeMillis(),
                        ),
                    )
                    return
                }
                BleSosMonitorService.EVENT_PAIRED_NEARBY -> {
                    if (intent.getBooleanExtra(
                            BleSosMonitorService.EXTRA_PENDING_NEARBY_EVENT_STORED,
                            false,
                        )
                    ) {
                        if (isActivityResumed) drainPendingNearbyEvents()
                        return
                    }
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
                    if (intent.getBooleanExtra(
                            BleSosMonitorService.EXTRA_PENDING_NEARBY_EVENT_STORED,
                            false,
                        )
                    ) {
                        if (isActivityResumed) drainPendingNearbyEvents()
                        return
                    }
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
                BleSosMonitorService.EVENT_SOS_HELP -> {
                    if (isActivityResumed) drainPendingHelpEvents()
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

    private val bondStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
            val attempt = pairingAttempt ?: return
            @Suppress("DEPRECATION")
            val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(
                    BluetoothDevice.EXTRA_DEVICE,
                    BluetoothDevice::class.java,
                )
            } else {
                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
            } ?: return
            val addressMatches = runCatching {
                device.address.equals(attempt.address, ignoreCase = true)
            }.getOrDefault(false)
            if (!addressMatches) return
            when (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, device.bondState)) {
                BluetoothDevice.BOND_BONDED -> connectPairingGatt(
                    device,
                    reusedExistingBond = false,
                )
                BluetoothDevice.BOND_NONE -> {
                    val previousState = intent.getIntExtra(
                        BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE,
                        BluetoothDevice.BOND_NONE,
                    )
                    if (previousState == BluetoothDevice.BOND_BONDING) {
                        finishPairing(
                            success = false,
                            errorCode = "paired_button_secure_bond_rejected",
                            errorMessage = "Android Bluetooth pairing was cancelled or rejected. Put the button in setup mode and try again.",
                        )
                    }
                }
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(::handleMethodCall)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
        registerSosButtonReceiver()
        registerBondStateReceiver()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (isActivityResumed) drainPendingEvents()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun onActivityResumed() {
        isActivityResumed = true
        drainPendingEvents()
    }

    fun onActivityPaused() {
        isActivityResumed = false
    }

    private fun drainPendingEvents() {
        drainPendingOwnerEvents()
        drainPendingNearbyEvents()
        drainPendingHelpEvents()
    }

    private fun drainPendingOwnerEvents(): Boolean {
        val events = eventSink ?: return false
        val ownerScope = pairedButtonRegistry.activeOwnerScopeToken() ?: return false
        val preferences = activity.getSharedPreferences(
            BleSosMonitorService.PENDING_EVENT_PREFS,
            Context.MODE_PRIVATE,
        )
        return runCatching {
            val raw = preferences.getString(
                BleSosMonitorService.PENDING_OWNER_EVENTS,
                null,
            ) ?: return@runCatching false
            val pending = JSONArray(raw)
            val remaining = JSONArray()
            var delivered = false
            var queueChanged = false
            val now = System.currentTimeMillis()
            for (index in 0 until pending.length()) {
                val item = pending.optJSONObject(index)
                if (item == null) {
                    queueChanged = true
                    continue
                }
                val itemOwnerScope = item.optString("ownerScope")
                val receivedAtMillis = item.optLong("receivedAtMillis", -1L)
                if (itemOwnerScope.isBlank() ||
                    receivedAtMillis <= 0L ||
                    receivedAtMillis > now + MAX_PENDING_SOS_FUTURE_SKEW_MILLIS ||
                    now - receivedAtMillis > MAX_PENDING_SOS_AGE_MILLIS
                ) {
                    queueChanged = true
                    continue
                }
                if (itemOwnerScope != ownerScope) {
                    remaining.put(item)
                    continue
                }
                val deviceId = item.optString("deviceId").uppercase()
                val counter = item.optLong("counter", -1L)
                val mode = item.optInt("mode", -1)
                if (!deviceId.matches(Regex("[0-9A-F]{12}")) ||
                    counter !in 0L..0xffffffffL ||
                    mode != 1
                ) {
                    queueChanged = true
                    continue
                }
                events.success(
                    mapOf(
                        "type" to "pairedSosButton",
                        "source" to "paired_ble_button",
                        "deviceId" to deviceId,
                        "displayName" to item.optString("displayName"),
                        "counter" to counter,
                        "mode" to mode,
                        "rssi" to item.optInt("rssi"),
                        "receivedAtMillis" to receivedAtMillis,
                    ),
                )
                delivered = true
                queueChanged = true
            }
            if (queueChanged) {
                val saved = preferences.edit()
                    .putString(
                        BleSosMonitorService.PENDING_OWNER_EVENTS,
                        remaining.toString(),
                    )
                    .commit()
                if (!saved) {
                    emitStatus(
                        "paired_button_pending_event_write_failed",
                        "An authenticated SOS event was delivered but could not be removed from the pending queue.",
                    )
                }
            }
            delivered
        }.getOrElse { error ->
            emitStatus(
                "paired_button_pending_event_read_failed",
                error.message ?: "Unable to read a pending authenticated SOS event.",
            )
            false
        }
    }

    private fun drainPendingHelpEvents(): Boolean {
        val events = eventSink ?: return false
        val preferences = activity.getSharedPreferences(
            BleSosMonitorService.PENDING_EVENT_PREFS,
            Context.MODE_PRIVATE,
        )
        return runCatching {
            val raw = preferences.getString(
                BleSosMonitorService.PENDING_HELP_EVENTS,
                null,
            ) ?: return@runCatching false
            val pending = JSONArray(raw)
            val now = System.currentTimeMillis()
            var delivered = false
            for (index in 0 until pending.length()) {
                val item = pending.optJSONObject(index) ?: continue
                val latitude = item.optDouble("latitude", Double.NaN)
                val longitude = item.optDouble("longitude", Double.NaN)
                val accuracyMeters = item.optDouble("accuracyMeters", Double.NaN)
                    .takeIf { it.isFinite() && it >= 0.0 }
                val capturedAtMillis = item.optLong("capturedAtMillis", -1L)
                val receivedAtMillis = item.optLong("receivedAtMillis", -1L)
                if (!isValidBleLocation(latitude, longitude, accuracyMeters) ||
                    capturedAtMillis <= 0L ||
                    receivedAtMillis <= 0L ||
                    capturedAtMillis > now + MAX_PENDING_SOS_FUTURE_SKEW_MILLIS ||
                    now - capturedAtMillis > MAX_PENDING_SOS_AGE_MILLIS ||
                    receivedAtMillis > now + MAX_PENDING_SOS_FUTURE_SKEW_MILLIS ||
                    now - receivedAtMillis > MAX_PENDING_SOS_AGE_MILLIS
                ) {
                    continue
                }
                events.success(
                    buildMap<String, Any> {
                        put("type", "sosHelp")
                        put("source", "ble_sos_test")
                        put("phoneNumberHash", item.optLong("phoneNumberHash"))
                        put("latitude", latitude)
                        put("longitude", longitude)
                        if (accuracyMeters != null) put("accuracyMeters", accuracyMeters)
                        put("capturedAtMillis", capturedAtMillis)
                        put("receivedAtMillis", receivedAtMillis)
                        put("rssi", item.optInt("rssi"))
                    },
                )
                delivered = true
            }
            check(
                preferences.edit()
                    .remove(BleSosMonitorService.PENDING_HELP_EVENTS)
                    .commit(),
            ) { "Unable to clear nearby SOS help events." }
            delivered
        }.getOrElse { error ->
            emitStatus(
                "ble_sos_help_pending_event_failed",
                error.message ?: "Unable to restore a nearby SOS help event.",
            )
            false
        }
    }

    private fun drainPendingNearbyEvents(): Boolean {
        val events = eventSink ?: return false
        val ownerScope = pairedButtonRegistry.activeOwnerScopeToken() ?: return false
        val preferences = activity.getSharedPreferences(
            BleSosMonitorService.PENDING_EVENT_PREFS,
            Context.MODE_PRIVATE,
        )
        return runCatching {
            val raw = preferences.getString(
                BleSosMonitorService.PENDING_NEARBY_EVENTS,
                null,
            ) ?: return@runCatching false
            val pending = JSONArray(raw)
            val remaining = JSONArray()
            val now = System.currentTimeMillis()
            var delivered = false
            var queueChanged = false
            for (index in 0 until pending.length()) {
                val item = pending.optJSONObject(index)
                if (item == null) {
                    queueChanged = true
                    continue
                }
                val itemOwnerScope = item.optString("ownerScope")
                val receivedAtMillis = item.optLong("receivedAtMillis", -1L)
                if (itemOwnerScope.isBlank() ||
                    receivedAtMillis <= 0L ||
                    receivedAtMillis > now + MAX_PENDING_SOS_FUTURE_SKEW_MILLIS ||
                    now - receivedAtMillis > MAX_PENDING_SOS_AGE_MILLIS
                ) {
                    queueChanged = true
                    continue
                }
                if (itemOwnerScope != ownerScope) {
                    remaining.put(item)
                    continue
                }
                val eventType = item.optString("eventType")
                val deviceId = item.optString("deviceId").uppercase()
                val counter = item.optLong("counter", -1L)
                if (!deviceId.matches(Regex("[0-9A-F]{12}")) ||
                    counter !in 0L..0xffffffffL
                ) {
                    queueChanged = true
                    continue
                }
                val event = mutableMapOf<String, Any>(
                    "source" to if (eventType == BleSosMonitorService.EVENT_PAIRED_LOCATION) {
                        "paired_ble_button_location"
                    } else {
                        "paired_ble_button"
                    },
                    "deviceId" to deviceId,
                    "counter" to counter,
                    "rssi" to item.optInt("rssi"),
                    "receivedAtMillis" to receivedAtMillis,
                )
                when (eventType) {
                    BleSosMonitorService.EVENT_PAIRED_NEARBY -> {
                        event["type"] = "nearbySosButton"
                    }
                    BleSosMonitorService.EVENT_PAIRED_LOCATION -> {
                        val latitude = item.optDouble("latitude", Double.NaN)
                        val longitude = item.optDouble("longitude", Double.NaN)
                        val accuracyMeters = item.optDouble("accuracyMeters", Double.NaN)
                            .takeIf { it.isFinite() && it >= 0.0 }
                        if (!isValidBleLocation(latitude, longitude, accuracyMeters)) {
                            queueChanged = true
                            continue
                        }
                        event["type"] = "nearbySosLocation"
                        event["latitude"] = latitude
                        event["longitude"] = longitude
                        if (accuracyMeters != null) {
                            event["accuracyMeters"] = accuracyMeters
                        }
                    }
                    else -> {
                        queueChanged = true
                        continue
                    }
                }
                events.success(event)
                delivered = true
                queueChanged = true
            }
            if (queueChanged) {
                check(
                    preferences.edit()
                        .putString(
                            BleSosMonitorService.PENDING_NEARBY_EVENTS,
                            remaining.toString(),
                        )
                        .commit(),
                ) { "Unable to clear delivered nearby SOS button events." }
            }
            delivered
        }.getOrElse { error ->
            emitStatus(
                "paired_button_nearby_pending_event_failed",
                error.message ?: "Unable to restore a nearby SOS button event.",
            )
            false
        }
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
                "Bluetooth permission is required for SOS button monitoring.",
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
        finishLogDownload(
            success = false,
            errorCode = "paired_button_bridge_disposed",
            errorMessage = "The BLE bridge was disposed before the log was downloaded.",
        )
        pendingPermissionResult?.error(
            "paired_button_bridge_disposed",
            "The BLE permission request was interrupted.",
            null,
        )
        pendingPermissionResult = null
        pendingPermissionAction = null
        runCatching { activity.unregisterReceiver(sosButtonReceiver) }
        if (bondStateReceiverRegistered) {
            runCatching { activity.unregisterReceiver(bondStateReceiver) }
            bondStateReceiverRegistered = false
        }
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    private fun registerSosButtonReceiver() {
        val filter = IntentFilter(BleSosMonitorService.ACTION_SOS_BUTTON_DETECTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(
                sosButtonReceiver,
                filter,
                BleSosMonitorService.INTERNAL_BLE_SOS_PERMISSION,
                mainHandler,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            activity.registerReceiver(
                sosButtonReceiver,
                filter,
                BleSosMonitorService.INTERNAL_BLE_SOS_PERMISSION,
                mainHandler,
            )
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isBleSupported())
            "openBluetoothSettings" -> {
                runCatching {
                    activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                }.onSuccess {
                    result.success(null)
                }.onFailure { error ->
                    result.error(
                        "bluetooth_settings_unavailable",
                        error.message ?: "Unable to open Android Bluetooth settings.",
                        null,
                    )
                }
            }
            "startSosButtonMonitor" -> {
                withBlePermissions(
                    result,
                    includeAdvertisePermission = false,
                ) {
                    startSosButtonMonitor()
                    result.success(null)
                }
            }
            "stopSosButtonMonitor" -> {
                stopSosButtonMonitor()
                result.success(null)
            }
            "setActiveSosAccount" -> {
                runCatching {
                    pairedButtonRegistry.setActiveOwnerScope(
                        call.argument<String>("accountId"),
                    )
                }.onSuccess {
                    if (isActivityResumed) drainPendingEvents()
                    result.success(null)
                }.onFailure { error ->
                    result.error(
                        "paired_button_account_write_failed",
                        error.message ?: "Unable to secure the active SOS account.",
                        null,
                    )
                }
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
            "listPairedSosButtons" -> runCatching {
                pairedButtonRegistry.buttons().map { button ->
                    mapOf(
                        "deviceId" to button.deviceIdHex,
                        "displayName" to button.displayName,
                        "pairedAtMillis" to button.pairedAtMillis,
                        "lastSeenAtMillis" to button.lastSeenAtMillis,
                        "lastAcceptedEventId" to button.lastAcceptedEventId,
                    )
                }
            }.onSuccess(result::success).onFailure { error ->
                result.error(
                    "paired_button_registry_read_failed",
                    error.message ?: "Unable to securely read paired SOS buttons.",
                    null,
                )
            }
            "armPairedSosButtonTest" -> {
                val deviceId = call.argument<String>("deviceId")?.trim()?.uppercase()
                val durationMillis = call.argument<Number>("durationMillis")
                    ?.toLong()
                    ?.coerceIn(5_000L, 30_000L)
                    ?: 30_000L
                if (deviceId == null ||
                    !deviceId.matches(Regex("[0-9A-F]{12}"))
                ) {
                    result.error(
                        "paired_button_test_invalid",
                        "A valid paired SOS button ID is required.",
                        null,
                    )
                } else {
                    runCatching { pairedButtonRegistry.find(deviceId) }
                        .onSuccess { button ->
                            if (button == null) {
                                result.error(
                                    "paired_button_test_not_paired",
                                    "This SOS button is not paired to the active account.",
                                    null,
                                )
                            } else {
                                withBlePermissions(
                                    result,
                                    includeAdvertisePermission = false,
                                ) {
                                    armPairedSosButtonTest(deviceId, durationMillis)
                                    result.success(null)
                                }
                            }
                        }
                        .onFailure { error ->
                            result.error(
                                "paired_button_registry_read_failed",
                                error.message ?: "Unable to verify the paired SOS button.",
                                null,
                            )
                        }
                }
            }
            "cancelPairedSosButtonTest" -> {
                cancelPairedSosButtonTest()
                result.success(null)
            }
            "resetPairedSosButtonRegistry" -> {
                if (pairingResult != null || locationResult != null || logResult != null) {
                    result.error(
                        "paired_button_busy",
                        "Wait for the current SOS button operation to finish before resetting pairing data.",
                        null,
                    )
                } else {
                    runCatching {
                        stopPairedButtonSetupScan()
                        pairedButtonRegistry.resetRegistry()
                        check(
                            activity.getSharedPreferences(
                                BleSosMonitorService.PENDING_EVENT_PREFS,
                                Context.MODE_PRIVATE,
                            ).edit()
                                .remove(BleSosMonitorService.PENDING_OWNER_EVENTS)
                                .remove(BleSosMonitorService.PENDING_NEARBY_EVENTS)
                                .commit(),
                        ) { "Unable to clear pending SOS button events." }
                    }.onSuccess {
                        result.success(null)
                    }.onFailure { error ->
                        result.error(
                            "paired_button_registry_reset_failed",
                            error.message ?: "Unable to reset SOS button pairing data.",
                            null,
                        )
                    }
                }
            }
            "unpairSosButton" -> {
                val deviceId = call.argument<String>("deviceId")?.trim()?.uppercase()
                if (deviceId.isNullOrEmpty()) {
                    result.error("paired_button_invalid_id", "A button device ID is required.", null)
                } else {
                    runCatching { pairedButtonRegistry.remove(deviceId) }
                        .onSuccess(result::success)
                        .onFailure { error ->
                            result.error(
                                "paired_button_registry_write_failed",
                                error.message ?: "Unable to securely remove this SOS button.",
                                null,
                            )
                        }
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
            "readPairedSosButtonLog" -> {
                val deviceId = call.argument<String>("deviceId")?.trim()?.uppercase()
                if (deviceId.isNullOrEmpty()) {
                    result.error(
                        "paired_button_invalid_id",
                        "A button device ID is required.",
                        null,
                    )
                } else {
                    withBlePermissions(result, includeAdvertisePermission = false) {
                        beginLogDownload(deviceId, result)
                    }
                }
            }
            "setLegacyUnpairedSosButtonEnabled" -> {
                val saved = pairedButtonRegistry.setLegacyUnpairedEnabled(
                    call.argument<Boolean>("enabled") ?: false,
                )
                if (saved) {
                    result.success(null)
                } else {
                    result.error(
                        "paired_button_setting_write_failed",
                        "Unable to save the legacy-button setting.",
                        null,
                    )
                }
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
        includeNotificationPermission: Boolean = false,
        action: () -> Unit,
    ) {
        if (!isBleSupported()) {
            result.error("ble_unsupported", "This phone does not support BLE.", null)
            return
        }
        val missing = requiredPermissions(
            includeAdvertisePermission,
            includeNotificationPermission,
        ).filter {
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

    private fun requiredPermissions(
        includeAdvertisePermission: Boolean,
        includeNotificationPermission: Boolean,
    ): List<String> {
        val bluetoothPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
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
        return bluetoothPermissions + listOfNotNull(
            Manifest.permission.POST_NOTIFICATIONS.takeIf {
                includeNotificationPermission &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
            },
        )
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

    private fun armPairedSosButtonTest(deviceId: String, durationMillis: Long) {
        val intent = Intent(activity, BleSosMonitorService::class.java).apply {
            action = BleSosMonitorService.ACTION_ARM_PAIRED_TEST
            putExtra(BleSosMonitorService.EXTRA_DEVICE_ID, deviceId)
            putExtra(BleSosMonitorService.EXTRA_TEST_DURATION_MILLIS, durationMillis)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
        emitStatus("paired_button_test_armed")
    }

    private fun cancelPairedSosButtonTest() {
        val intent = Intent(activity, BleSosMonitorService::class.java).apply {
            action = BleSosMonitorService.ACTION_CANCEL_PAIRED_TEST
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
        emitStatus("paired_button_test_cancelled")
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
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: run {
            emitStatus("team_ble_scan_failed", "Bluetooth scanning is unavailable.")
            return
        }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handleTeamScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::handleTeamScanResult)
            }

            override fun onScanFailed(errorCode: Int) {
                if (teamScanCallback === this) teamScanCallback = null
                emitStatus(
                    "team_ble_scan_failed",
                    "Android BLE team scan failed with code $errorCode.",
                )
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
        runCatching { scanner.startScan(filters, settings, callback) }
            .onSuccess { emitStatus("team_ble_scan_started") }
            .onFailure { error ->
                if (teamScanCallback === callback) teamScanCallback = null
                emitStatus("team_ble_scan_failed", error.message)
            }
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
        runCatching { advertiser.startAdvertising(settings, data, callback) }
            .onFailure { error ->
                if (teamAdvertiseCallback === callback) teamAdvertiseCallback = null
                emitStatus("team_ble_advertising_failed", error.message)
            }
    }

    private fun stopTeamLocationExchange() {
        stopTeamScanner()
        stopTeamAdvertiser()
        latestTeamPayload = null
        handledTeamPackets.clear()
        handledTeamPacketOrder.clear()
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
            val gatt = result.device.connectGatt(activity, false, callback)
            activeTeamGatts[address] = gatt
            val timeout = Runnable {
                if (activeTeamGatts[address] === gatt) closeTeamGatt(gatt)
            }
            teamGattTimeouts[address] = timeout
            mainHandler.postDelayed(timeout, READ_GATT_TIMEOUT_MILLIS)
        }.onFailure {
            activeTeamGatts.remove(address)
            teamGattTimeouts.remove(address)?.let(mainHandler::removeCallbacks)
        }
    }

    private fun closeTeamGatt(gatt: BluetoothGatt) {
        runCatching { gatt.device.address }.getOrNull()?.let { address ->
            activeTeamGatts.remove(address)
            teamGattTimeouts.remove(address)?.let(mainHandler::removeCallbacks)
        }
        runCatching {
            if (hasConnectPermission()) {
                gatt.disconnect()
            }
            gatt.close()
        }
    }

    private fun emitTeamLocation(packet: HikerBleProtocol.TeamLocationPacket) {
        val ownPayload = latestTeamPayload ?: return
        if (packet.teamSessionHash != ownPayload["teamSessionHash"] as Long ||
            packet.phoneNumberHash == ownPayload["phoneNumberHash"] as Long
        ) {
            return
        }
        val fingerprint = listOf(
            packet.teamSessionHash,
            packet.phoneNumberHash,
            packet.latitude,
            packet.longitude,
            packet.accuracyMeters,
            packet.capturedAtMillis,
        ).joinToString(":")
        if (!handledTeamPackets.add(fingerprint)) return
        handledTeamPacketOrder.addLast(fingerprint)
        while (handledTeamPacketOrder.size > 128) {
            handledTeamPackets.remove(handledTeamPacketOrder.removeFirst())
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
        val scanner = bluetoothManager?.adapter?.bluetoothLeScanner ?: run {
            emitStatus(
                "paired_button_setup_scan_failed",
                "Bluetooth scanning is unavailable. Turn Bluetooth on and try again.",
            )
            return
        }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                emitPairedButtonSetupDevice(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::emitPairedButtonSetupDevice)
            }

            override fun onScanFailed(errorCode: Int) {
                if (pairedButtonSetupScanCallback === this) {
                    pairedButtonSetupScanCallback = null
                }
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
        runCatching { scanner.startScan(null, settings, callback) }
            .onSuccess { emitStatus("paired_button_setup_scan_started") }
            .onFailure { error ->
                if (pairedButtonSetupScanCallback === callback) {
                    pairedButtonSetupScanCallback = null
                }
                emitStatus("paired_button_setup_scan_failed", error.message)
            }
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
        val setupStatus = HikerBleProtocol.decodePairedButtonSetupStatus(
            record?.getManufacturerSpecificData(HikerBleProtocol.MANUFACTURER_ID),
        )
        val event = mutableMapOf<String, Any?>(
            "type" to "pairedButtonSetupDevice",
            "status" to "paired_button_setup_device_found",
            "address" to result.device.address,
            "displayName" to name,
            "rssi" to result.rssi,
            "receivedAtMillis" to System.currentTimeMillis(),
        )
        if (setupStatus != null) {
            event["setupModeState"] = setupStatus.state
            event["setupModeRemainingSeconds"] = setupStatus.remainingSeconds
        }
        emitEvent(
            event,
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
                if (!gatt.requestMtu(247)) {
                    gatt.discoverServices()
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
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

    private fun registerBondStateReceiver() {
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        bondStateReceiverRegistered = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(
                    bondStateReceiver,
                    filter,
                    Context.RECEIVER_EXPORTED,
                )
            } else {
                activity.registerReceiver(bondStateReceiver, filter)
            }
        }.isSuccess
    }

    private fun beginLogDownload(
        deviceIdHex: String,
        result: MethodChannel.Result,
    ) {
        if (logResult != null) {
            result.error(
                "paired_button_log_active",
                "Another SOS button log download is already active.",
                null,
            )
            return
        }
        if (pairingResult != null || locationResult != null) {
            result.error(
                "paired_button_busy",
                "The SOS button is busy with another maintenance operation.",
                null,
            )
            return
        }
        val button = pairedButtonRegistry.find(deviceIdHex)
        val address = button?.address
        if (button == null || address.isNullOrEmpty() || button.pairingSecret.size != 32) {
            result.error(
                "paired_button_log_not_available",
                "This button must be paired again before its log can be downloaded.",
                null,
            )
            return
        }
        val device = runCatching {
            bluetoothManager?.adapter?.getRemoteDevice(address)
        }.getOrNull()
        if (device == null) {
            result.error(
                "paired_button_log_address_invalid",
                "The saved SOS button Bluetooth address is invalid.",
                null,
            )
            return
        }

        logButton = button
        logResult = result
        downloadedLogRecords.clear()
        nextLogPage = 0
        expectedLogPages = 1
        logServiceCacheRefreshAttempted = false
        mainHandler.postDelayed(logDownloadTimeout, 30000L)
        logGatt = runCatching {
            device.connectGatt(activity, false, logGattCallback)
        }.getOrNull()
        if (logGatt == null) {
            finishLogDownload(
                success = false,
                errorCode = "paired_button_log_connect_failed",
                errorMessage = "Unable to connect. Tap Start, then press the external button five times within 3 seconds.",
            )
        }
    }

    private val logGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(
            gatt: BluetoothGatt,
            status: Int,
            newState: Int,
        ) {
            if (gatt !== logGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS ||
                newState != BluetoothProfile.STATE_CONNECTED
            ) {
                if (newState == BluetoothProfile.STATE_DISCONNECTED || status != 0) {
                    finishLogDownload(
                        success = false,
                        errorCode = "paired_button_log_connect_failed",
                        errorMessage =
                            "Unable to connect. Tap Start, then press the external button five times within 3 seconds.",
                    )
                }
                return
            }
            if (hasConnectPermission()) {
                if (!gatt.requestMtu(247)) {
                    gatt.discoverServices()
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (gatt !== logGatt) return
            if (hasConnectPermission()) {
                gatt.discoverServices()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (gatt !== logGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS || !hasConnectPermission()) {
                finishLogDownload(
                    success = false,
                    errorCode = "paired_button_log_service_failed",
                    errorMessage = "The SOS button maintenance service was not available.",
                )
                return
            }
            val service =
                gatt.getService(HikerBleProtocol.PAIRED_BUTTON_MAINTENANCE_SERVICE_UUID)
                    ?: gatt.getService(HikerBleProtocol.PAIRED_BUTTON_SETUP_SERVICE_UUID)
            val challenge = service?.getCharacteristic(
                HikerBleProtocol.PAIRED_BUTTON_LOG_CHALLENGE_CHARACTERISTIC_UUID,
            )
            logAuthCharacteristic = service?.getCharacteristic(
                HikerBleProtocol.PAIRED_BUTTON_LOG_AUTH_CHARACTERISTIC_UUID,
            )
            logDataCharacteristic = service?.getCharacteristic(
                HikerBleProtocol.PAIRED_BUTTON_LOG_DATA_CHARACTERISTIC_UUID,
            )
            logPageCharacteristic = service?.getCharacteristic(
                HikerBleProtocol.PAIRED_BUTTON_LOG_PAGE_CHARACTERISTIC_UUID,
            )
            if (challenge == null ||
                logAuthCharacteristic == null ||
                logDataCharacteristic == null ||
                logPageCharacteristic == null
            ) {
                recoverFromIncompleteLogService(gatt)
                return
            }
            if (!gatt.readCharacteristic(challenge)) {
                finishLogDownload(
                    success = false,
                    errorCode = "paired_button_log_challenge_failed",
                    errorMessage = "Unable to read the SOS button log challenge.",
                )
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (gatt !== logGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                finishLogDownload(
                    success = false,
                    errorCode = "paired_button_log_read_failed",
                    errorMessage = "The SOS button log read failed.",
                )
                return
            }
            when (characteristic.uuid) {
                HikerBleProtocol.PAIRED_BUTTON_LOG_CHALLENGE_CHARACTERISTIC_UUID -> {
                    val button = logButton ?: return
                    val deviceId = runCatching {
                        button.deviceIdHex.chunked(2)
                            .map { it.toInt(16).toByte() }
                            .toByteArray()
                    }.getOrNull()
                    val auth = runCatching {
                        HikerBleProtocol.encodeLogAuthentication(
                            challenge = characteristic.value,
                            deviceId = deviceId ?: ByteArray(0),
                            pairingSecret = button.pairingSecret,
                        )
                    }.getOrElse {
                        finishLogDownload(
                            success = false,
                            errorCode = "paired_button_log_challenge_invalid",
                            errorMessage = it.message ?: "The log challenge was invalid.",
                        )
                        return
                    }
                    val authCharacteristic = logAuthCharacteristic ?: return
                    authCharacteristic.writeType =
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    authCharacteristic.value = auth
                    if (!gatt.writeCharacteristic(authCharacteristic)) {
                        finishLogDownload(
                            success = false,
                            errorCode = "paired_button_log_auth_failed",
                            errorMessage = "Unable to authenticate the log download.",
                        )
                    }
                }
                HikerBleProtocol.PAIRED_BUTTON_LOG_DATA_CHARACTERISTIC_UUID -> {
                    val page = HikerBleProtocol.decodeLogPage(characteristic.value)
                    if (page == null || page.pageIndex != nextLogPage) {
                        finishLogDownload(
                            success = false,
                            errorCode = "paired_button_log_auth_failed",
                            errorMessage =
                                "The button rejected authentication or returned invalid log data.",
                        )
                        return
                    }
                    downloadedLogRecords += page.records
                    expectedLogPages = maxOf(1, (page.totalCount + 7) / 8)
                    nextLogPage += 1
                    if (nextLogPage < expectedLogPages) {
                        writeLogPage(gatt, nextLogPage)
                    } else {
                        finishLogDownload(success = true)
                    }
                }
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (gatt !== logGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                finishLogDownload(
                    success = false,
                    errorCode = "paired_button_log_write_failed",
                    errorMessage = "The authenticated log request was rejected.",
                )
                return
            }
            when (characteristic.uuid) {
                HikerBleProtocol.PAIRED_BUTTON_LOG_AUTH_CHARACTERISTIC_UUID ->
                    writeLogPage(gatt, 0)
                HikerBleProtocol.PAIRED_BUTTON_LOG_PAGE_CHARACTERISTIC_UUID -> {
                    val dataCharacteristic = logDataCharacteristic ?: return
                    if (!gatt.readCharacteristic(dataCharacteristic)) {
                        finishLogDownload(
                            success = false,
                            errorCode = "paired_button_log_read_failed",
                            errorMessage = "Unable to read the selected log page.",
                        )
                    }
                }
            }
        }
    }

    private fun recoverFromIncompleteLogService(gatt: BluetoothGatt) {
        val discovered = gatt.services.joinToString(separator = "; ") { service ->
            "${service.uuid}=[${service.characteristics.joinToString { it.uuid.toString() }}]"
        }
        Log.w(TAG, "Incomplete SOS log GATT table; discovered=$discovered")
        if (logServiceCacheRefreshAttempted) {
            finishLogDownload(
                success = false,
                errorCode = "paired_button_log_service_missing",
                errorMessage =
                    "Android refreshed the button's Bluetooth services, but the authenticated log characteristics are still unavailable.",
            )
            return
        }

        logServiceCacheRefreshAttempted = true
        val cacheRefreshed = runCatching {
            val refresh = gatt.javaClass.getMethod("refresh")
            (refresh.invoke(gatt) as? Boolean) != false
        }.onFailure { error ->
            Log.w(TAG, "Android rejected the SOS log GATT cache refresh.", error)
        }.getOrDefault(false)

        logGatt = null
        runCatching { gatt.disconnect() }
        runCatching { gatt.close() }
        if (!cacheRefreshed) {
            finishLogDownload(
                success = false,
                errorCode = "paired_button_log_bluetooth_cache_stale",
                errorMessage =
                    "Android cached the button's older Bluetooth services and could not refresh them automatically. Forget HikerCircle Setup in Android Bluetooth settings, then pair the button again.",
            )
            return
        }

        mainHandler.postDelayed({
            val button = logButton
            if (logResult == null || button == null) return@postDelayed
            val device = runCatching {
                bluetoothManager?.adapter?.getRemoteDevice(button.address)
            }.getOrNull()
            if (device == null) {
                finishLogDownload(
                    success = false,
                    errorCode = "paired_button_log_address_invalid",
                    errorMessage = "The saved SOS button Bluetooth address is invalid.",
                )
                return@postDelayed
            }
            logGatt = runCatching {
                device.connectGatt(activity, false, logGattCallback)
            }.getOrNull()
            if (logGatt == null) {
                finishLogDownload(
                    success = false,
                    errorCode = "paired_button_log_connect_failed",
                    errorMessage = "Unable to reconnect after refreshing Android Bluetooth data.",
                )
            }
        }, 700L)
    }

    @Suppress("DEPRECATION")
    private fun writeLogPage(gatt: BluetoothGatt, page: Int) {
        val characteristic = logPageCharacteristic ?: return
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = byteArrayOf(page.toByte())
        if (!gatt.writeCharacteristic(characteristic)) {
            finishLogDownload(
                success = false,
                errorCode = "paired_button_log_page_failed",
                errorMessage = "Unable to select the next SOS button log page.",
            )
        }
    }

    private fun finishLogDownload(
        success: Boolean,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        mainHandler.removeCallbacks(logDownloadTimeout)
        val gatt = logGatt
        logGatt = null
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        logButton = null
        logAuthCharacteristic = null
        logPageCharacteristic = null
        logDataCharacteristic = null
        val result = logResult
        logResult = null
        if (success) {
            result?.success(downloadedLogRecords.map { it.toPlatformMap() })
        } else if (result != null && errorCode != null) {
            result.error(errorCode, errorMessage, null)
        }
        downloadedLogRecords.clear()
        nextLogPage = 0
        expectedLogPages = 1
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
        if (locationResult != null || logResult != null) {
            result.error(
                "paired_button_busy",
                "The SOS button is busy with another maintenance operation.",
                null,
            )
            return
        }
        val ownerScope = pairedButtonRegistry.activeOwnerScopeToken()
        if (ownerScope == null) {
            result.error(
                "paired_button_account_missing",
                "Sign in before pairing an SOS button.",
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
            ownerScope = ownerScope,
        )
        pairingResult = result
        mainHandler.postDelayed(pairingOperationTimeout, SECURE_BOND_TIMEOUT_MILLIS)
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
        when (device.bondState) {
            BluetoothDevice.BOND_BONDED -> {
                connectPairingGatt(device, reusedExistingBond = true)
                return
            }
            BluetoothDevice.BOND_BONDING -> {
                emitStatus(
                    "paired_button_secure_bond_pending",
                    "Android Bluetooth pairing is already in progress. HikerCircle will continue automatically when it is approved.",
                )
                return
            }
            else -> {
                val bondStarted = runCatching { device.createBond() }.getOrDefault(false)
                if (device.bondState == BluetoothDevice.BOND_BONDED) {
                    connectPairingGatt(device, reusedExistingBond = true)
                } else if (bondStarted || device.bondState == BluetoothDevice.BOND_BONDING) {
                    emitStatus(
                        "paired_button_secure_bond_pending",
                        "Approve Android's Bluetooth pairing request if it appears. HikerCircle will continue automatically.",
                    )
                } else {
                    finishPairing(
                        success = false,
                        errorCode = "paired_button_secure_bond_unsupported",
                        errorMessage = "This button did not accept secure Bluetooth bonding. Update its firmware before pairing.",
                    )
                }
                return
            }
        }
    }

    private fun connectPairingGatt(
        device: BluetoothDevice,
        reusedExistingBond: Boolean,
    ) {
        val attempt = pairingAttempt ?: return
        if (pairingResult == null || pairingGatt != null) return
        val matchesAttempt = runCatching {
            device.address.equals(attempt.address, ignoreCase = true)
        }.getOrDefault(false)
        if (!matchesAttempt || device.bondState != BluetoothDevice.BOND_BONDED) return
        mainHandler.removeCallbacks(pairingOperationTimeout)
        mainHandler.postDelayed(pairingOperationTimeout, GATT_OPERATION_TIMEOUT_MILLIS)
        emitStatus(
            if (reusedExistingBond) {
                "paired_button_secure_bond_reused"
            } else {
                "paired_button_secure_bond_approved"
            },
            if (reusedExistingBond) {
                "Android Bluetooth pairing was already approved. Continuing with SOS button setup."
            } else {
                "Android Bluetooth pairing is approved. Continuing with SOS button setup."
            },
        )
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
            if (gatt !== pairingGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS ||
                newState != BluetoothProfile.STATE_CONNECTED
            ) {
                if (newState == BluetoothProfile.STATE_DISCONNECTED ||
                    status != BluetoothGatt.GATT_SUCCESS
                ) {
                    finishPairing(
                        success = false,
                        errorCode = "paired_button_disconnected",
                        errorMessage = "The SOS button disconnected before pairing completed.",
                    )
                }
                return
            }
            if (hasConnectPermission()) {
                if (!gatt.requestMtu(247)) {
                    gatt.discoverServices()
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (gatt !== pairingGatt) return
            if (hasConnectPermission()) {
                gatt.discoverServices()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (gatt !== pairingGatt) return
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
                recoverFromIncompletePairingService(
                    gatt = gatt,
                    requestMissing = request == null,
                    statusMissing = statusCharacteristic == null,
                )
                return
            }
            pairingAttempt?.requestCharacteristic = request
            pairingAttempt?.statusCharacteristic = statusCharacteristic
            if (!gatt.setCharacteristicNotification(statusCharacteristic, true)) {
                finishPairing(
                    success = false,
                    errorCode = "paired_button_notifications_failed",
                    errorMessage = "Unable to subscribe to button pairing status.",
                )
                return
            }
            val descriptor = statusCharacteristic.getDescriptor(CLIENT_CONFIG_DESCRIPTOR)
            if (descriptor != null) {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                if (!gatt.writeDescriptor(descriptor)) {
                    finishPairing(
                        success = false,
                        errorCode = "paired_button_notifications_failed",
                        errorMessage = "Unable to enable button pairing notifications.",
                    )
                }
            } else {
                finishPairing(
                    success = false,
                    errorCode = "paired_button_notifications_missing",
                    errorMessage = "The button firmware does not expose pairing notifications.",
                )
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (gatt !== pairingGatt) return
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
            if (gatt !== pairingGatt) return
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
            if (gatt !== pairingGatt) return
            if (status == BluetoothGatt.GATT_SUCCESS &&
                characteristic.uuid == HikerBleProtocol.PAIRED_BUTTON_STATUS_CHARACTERISTIC_UUID
            ) {
                handlePairingStatus(characteristic.value)
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (gatt !== pairingGatt ||
                characteristic.uuid != HikerBleProtocol.PAIRED_BUTTON_PAIR_REQUEST_CHARACTERISTIC_UUID
            ) {
                return
            }
            if (status != BluetoothGatt.GATT_SUCCESS) {
                finishPairing(
                    success = false,
                    errorCode = "paired_button_pair_write_failed",
                    errorMessage = "The SOS button rejected the pairing data.",
                )
                return
            }
            emitStatus("paired_button_pairing_written")
            // The setup/GATT deadline must not shorten the physical
            // confirmation window after a slow connection or service scan.
            mainHandler.removeCallbacks(pairingOperationTimeout)
            mainHandler.removeCallbacks(pairingTimeout)
            mainHandler.postDelayed(
                pairingTimeout,
                PAIRING_CONFIRMATION_TIMEOUT_MILLIS,
            )
        }
    }

    private fun writePairRequest(gatt: BluetoothGatt) {
        val attempt = pairingAttempt ?: return
        val characteristic = attempt.requestCharacteristic ?: return
        if (gatt.device.bondState != BluetoothDevice.BOND_BONDED) {
            finishPairing(
                success = false,
                errorCode = "paired_button_secure_bond_lost",
                errorMessage = "The secure Bluetooth bond was lost before pairing data could be written.",
            )
            return
        }
        // The firmware must additionally mark this characteristic as requiring
        // encrypted, authenticated (MITM-protected) access. Android bonding
        // alone cannot prove which association model the peripheral selected.
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
        }
    }

    private fun handlePairingStatus(value: ByteArray) {
        val status = HikerBleProtocol.decodePairingStatus(value) ?: return
        val attempt = pairingAttempt ?: return
        val deviceIdMatches = status.deviceId.contentEquals(attempt.deviceId)
        val deviceIdIsEmpty = status.deviceId.contentEquals(ByteArray(6))
        // READY/AWAITING may precede assignment and carry zeroes. Every
        // terminal response must echo the generated ID; otherwise a spoofed
        // or stale notification could falsely complete this pairing attempt.
        if (status.status >= HikerBleProtocol.PAIRING_STATUS_PAIRED && !deviceIdMatches) {
            return
        }
        if (status.status < HikerBleProtocol.PAIRING_STATUS_PAIRED &&
            !deviceIdIsEmpty && !deviceIdMatches
        ) {
            return
        }
        when (status.status) {
            HikerBleProtocol.PAIRING_STATUS_READY -> emitStatus("paired_button_ready")
            HikerBleProtocol.PAIRING_STATUS_AWAITING_CONFIRMATION -> {
                emitStatus("paired_button_awaiting_confirmation")
                mainHandler.removeCallbacks(pairingTimeout)
                mainHandler.postDelayed(
                    pairingTimeout,
                    PAIRING_CONFIRMATION_TIMEOUT_MILLIS,
                )
            }
            HikerBleProtocol.PAIRING_STATUS_PAIRED -> {
                runCatching {
                    pairedButtonRegistry.saveConfirmedPairing(
                        attempt.deviceId,
                        attempt.pairingSecret,
                        attempt.displayName,
                        attempt.address,
                        expectedOwnerScope = attempt.ownerScope,
                    )
                }.onSuccess {
                    finishPairing(success = true)
                }.onFailure {
                    finishPairing(
                        success = false,
                        errorCode = "paired_button_registry_write_failed",
                        errorMessage = "The button confirmed pairing, but this phone could not save it securely. Pair it again.",
                    )
                }
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
            mainHandler.removeCallbacks(pairingOperationTimeout)
            mainHandler.removeCallbacks(pairingTimeout)
            runCatching { pairingGatt?.disconnect() }
            runCatching { pairingGatt?.close() }
            pairingGatt = null
            pairingAttempt?.pairingSecret?.fill(0)
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

    private fun emitPairedSosButtonTest(
        deviceId: String,
        displayName: String?,
        counter: Long,
        rssi: Int,
        receivedAtMillis: Long,
    ) {
        emitEvent(
            mapOf(
                "type" to "pairedSosButtonTest",
                "source" to "paired_ble_button_test",
                "deviceId" to deviceId,
                "displayName" to displayName,
                "counter" to counter,
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
        val accuracyMeters = call.argument<Number>("accuracyMeters")?.toDouble()
        if (!isValidBleLocation(latitude, longitude, accuracyMeters)) return null
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
            "accuracyMeters" to accuracyMeters,
            "capturedAtMillis" to capturedAtMillis,
        )
    }

    private fun sosHelpPayloadFrom(call: MethodCall): Map<String, Any?>? {
        val phoneNumber = call.argument<String>("phoneNumber") ?: return null
        val latitude = call.argument<Number>("latitude")?.toDouble() ?: return null
        val longitude = call.argument<Number>("longitude")?.toDouble() ?: return null
        val accuracyMeters = call.argument<Number>("accuracyMeters")?.toDouble()
        if (!isValidBleLocation(latitude, longitude, accuracyMeters)) return null
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
            "accuracyMeters" to accuracyMeters,
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

    private fun recoverFromIncompletePairingService(
        gatt: BluetoothGatt,
        requestMissing: Boolean,
        statusMissing: Boolean,
    ) {
        val attempt = pairingAttempt ?: return
        val missing = buildList {
            if (requestMissing) add("secure pairing request")
            if (statusMissing) add("pairing status")
        }.joinToString(" and ")
        val discovered = gatt.services.joinToString(separator = "; ") { service ->
            "${service.uuid}=[${service.characteristics.joinToString { it.uuid.toString() }}]"
        }
        Log.w(
            TAG,
            "Incomplete SOS setup GATT table; missing=$missing; discovered=$discovered",
        )
        if (attempt.serviceCacheRefreshAttempted) {
            finishPairing(
                success = false,
                errorCode = "paired_button_firmware_incompatible",
                errorMessage = "The button still does not expose its $missing field after Android refreshed Bluetooth data. This is not a distance problem. Forget HikerCircle Setup in Android Bluetooth settings, restart button setup mode, and scan again. If it remains missing, update the button firmware.",
            )
            return
        }

        attempt.serviceCacheRefreshAttempted = true
        emitStatus(
            "paired_button_refreshing_gatt_cache",
            "Android returned old or incomplete SOS button details. Refreshing them and reconnecting automatically…",
        )
        mainHandler.removeCallbacks(pairingOperationTimeout)
        val cacheRefreshed = runCatching {
            val refresh = gatt.javaClass.getMethod("refresh")
            (refresh.invoke(gatt) as? Boolean) != false
        }.onFailure { error ->
            Log.w(TAG, "Android rejected the SOS button GATT cache refresh.", error)
        }.getOrDefault(false)
        pairingGatt = null
        runCatching { gatt.disconnect() }
        runCatching { gatt.close() }
        if (!cacheRefreshed) {
            finishPairing(
                success = false,
                errorCode = "paired_button_bluetooth_cache_stale",
                errorMessage = "Android has cached incomplete SOS button details and could not refresh them automatically. Forget HikerCircle Setup in Android Bluetooth settings, restart button setup mode, and scan again.",
            )
            return
        }

        mainHandler.postDelayed({
            if (pairingAttempt !== attempt || pairingResult == null) return@postDelayed
            val device = runCatching {
                bluetoothManager?.adapter?.getRemoteDevice(attempt.address)
            }.getOrNull()
            if (device == null || device.bondState != BluetoothDevice.BOND_BONDED) {
                finishPairing(
                    success = false,
                    errorCode = "paired_button_secure_bond_lost",
                    errorMessage = "Android removed the Bluetooth bond while refreshing the SOS button. Restart setup mode and scan again.",
                )
                return@postDelayed
            }
            connectPairingGatt(device, reusedExistingBond = true)
        }, 900L)
    }

    private fun isValidBleLocation(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double?,
    ): Boolean = latitude.isFinite() && longitude.isFinite() &&
        latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
        (accuracyMeters == null || (accuracyMeters.isFinite() && accuracyMeters >= 0.0))
}
