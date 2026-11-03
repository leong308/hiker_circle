// HikerBleService bridges native BLE button events, pairing/readiness and nearby SOS/team
// observations into typed Flutter streams.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../sos/Model/sos_models.dart';

/// Represents hiker ble service.
class HikerBleService {
  /// Creates hiker ble service.
  const HikerBleService();

  // Native pairing may spend up to 30 seconds connecting and then grant a
  // fresh 15-second physical-confirmation window.
  static const Duration _gattOperationTimeout = Duration(seconds: 50);
  static const Duration _pairingOperationTimeout = Duration(seconds: 80);

  static const String defaultPairedButtonName = 'HikerCircle Button';

  /// Checks whether terminal pairing compatibility error.
  static bool isTerminalPairingCompatibilityError(String? code) =>
      code == 'paired_button_firmware_incompatible' ||
      code == 'paired_button_bluetooth_cache_stale' ||
      code == 'paired_button_setup_service_invalid';

  static const String sosServiceUuid = '7e2a1d32-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String teamLocationServiceUuid =
      '7e2a1d33-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String sosHelpServiceUuid =
      '7e2a1d34-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonSetupServiceUuid =
      '7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonPairRequestCharacteristicUuid =
      '7e2a1d38-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonStatusCharacteristicUuid =
      '7e2a1d39-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonLogChallengeCharacteristicUuid =
      '7e2a1d3c-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonLogAuthCharacteristicUuid =
      '7e2a1d3d-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonLogDataCharacteristicUuid =
      '7e2a1d3e-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonLogPageCharacteristicUuid =
      '7e2a1d3f-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonMaintenanceServiceUuid =
      '7e2a1d40-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String pairedButtonTestControlCharacteristicUuid =
      '7e2a1d41-8b10-4f4d-9f78-0c6f1d65cba1';
  static const int manufacturerId = 0x02e5;
  static const int pairedSosProtocolVersion = 2;
  static const int pairedSosPacketType = 4;
  static const MethodChannel _methodChannel = MethodChannel(
    'hiker_circle/ble_bridge',
  );
  static const EventChannel _eventChannel = EventChannel(
    'hiker_circle/ble_events',
  );

  // EventChannel supports one native event sink. Recreating
  // receiveBroadcastStream() for each page causes a later listener (such as
  // the paired-button setup page) to replace the Home page listener, and its
  // cancellation can then clear the native sink completely. Keep one shared
  // platform subscription and fan its events out to every Dart listener.
  static final Stream<Object?> _platformEvents = _eventChannel
      .receiveBroadcastStream()
      .asBroadcastStream();

  static final Stream<HikerBleEvent> _events = _platformEvents
      .where((event) => event is! Map || event['type'] != 'buttonDebug')
      .map(HikerBleEvent.fromPlatform);

  /// Returns button debug events.
  Stream<Map<Object?, Object?>> get buttonDebugEvents => _platformEvents
      .where((event) => event is Map && event['type'] == 'buttonDebug')
      .map((event) => Map<Object?, Object?>.from(event as Map));

  static bool _buttonDebugCaptureEnabled = false;
  static int _buttonDebugCaptureRevision = 0;

  /// Suppresses diagnostic previews during capture without suppressing real SOS events.
  static bool get isButtonDebugCaptureEnabled => _buttonDebugCaptureEnabled;

  /// Opens the diagnostic gate before native acknowledgement and restores it if the request fails.
  Future<void> setButtonDebugCapture(bool enabled) async {
    final previous = _buttonDebugCaptureEnabled;
    final revision = ++_buttonDebugCaptureRevision;
    _buttonDebugCaptureEnabled = enabled;
    try {
      await _methodChannel.invokeMethod<void>('setButtonDebugCapture', {
        'enabled': enabled,
      });
    } catch (_) {
      if (revision == _buttonDebugCaptureRevision) {
        _buttonDebugCaptureEnabled = previous;
      }
      rethrow;
    }
  }

  /// Returns events.
  Stream<HikerBleEvent> get events => _events;

  /// Limits paired-button ownership to the signed-in app account. Native
  /// code hashes this identifier before persisting it; pairing secrets never
  /// cross back into Dart.
  Future<void> setActiveSosAccount(String? accountId) async {
    try {
      await _methodChannel.invokeMethod<void>('setActiveSosAccount', {
        'accountId': accountId?.trim(),
      });
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to secure the active SOS account.',
      );
    }
  }

  /// Checks whether supported.
  Future<bool> isSupported() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens bluetooth settings.
  Future<void> openBluetoothSettings() async {
    try {
      await _methodChannel.invokeMethod<void>('openBluetoothSettings');
    } on MissingPluginException {
      throw const HikerBleException(
        'Android Bluetooth settings are not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to open Android Bluetooth settings.',
        code: error.code,
      );
    }
  }

  /// Opens battery optimization settings.
  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _methodChannel.invokeMethod<void>(
        'openBatteryOptimizationSettings',
      );
    } on MissingPluginException {
      throw const HikerBleException(
        'Battery optimization settings are not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to open battery optimization settings.',
        code: error.code,
      );
    }
  }

  /// Returns sos button readiness.
  Future<SosButtonReadiness> getSosButtonReadiness() async {
    try {
      final raw = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getSosButtonReadiness',
      );
      return SosButtonReadiness.fromPlatform(raw ?? const {});
    } on MissingPluginException {
      return SosButtonReadiness.unsupported();
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to inspect SOS button readiness.',
        code: error.code,
      );
    }
  }

  /// Reads durable native notices only for the currently active SOS account.
  Future<List<Map<String, dynamic>>> readSosButtonNotices(String owner) async {
    try {
      final rows = await _methodChannel.invokeMethod<List<Object?>>(
        'readSosButtonNotices',
        {'accountId': owner},
      );
      return (rows ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } on MissingPluginException {
      return const [];
    }
  }

  /// Removes native records only after their local notification-history copy is saved.
  Future<void> acknowledgeSosButtonNotices(
    String owner,
    List<String> ids,
  ) async {
    try {
      await _methodChannel.invokeMethod<void>('acknowledgeSosButtonNotices', {
        'accountId': owner,
        'messageIds': ids,
      });
    } on MissingPluginException {
      /* Older bridges have no durable notice queue. */
    }
  }

  /// Computes restart sos button monitor.
  Future<void> restartSosButtonMonitor() async {
    try {
      await _methodChannel.invokeMethod<void>('restartSosButtonMonitor');
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to restart SOS button monitoring.',
        code: error.code,
      );
    }
  }

  /// Sets lost button warning.
  Future<void> setLostButtonWarning({
    required bool enabled,
    required Duration threshold,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('setLostButtonWarning', {
        'enabled': enabled,
        'thresholdMillis': threshold.inMilliseconds,
      });
    } on MissingPluginException {
      throw const HikerBleException(
        'Lost-button warnings are not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to update lost-button warnings.',
        code: error.code,
      );
    }
  }

  /// Starts sos button monitor.
  Future<void> startSosButtonMonitor() async {
    try {
      await _methodChannel.invokeMethod<void>('startSosButtonMonitor', {
        'sosServiceUuid': sosServiceUuid,
        'manufacturerId': manufacturerId,
      });
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException catch (error) {
      debugPrint('Unable to start BLE SOS button monitor: ${error.message}');
    }
  }

  /// Stops sos button monitor.
  Future<void> stopSosButtonMonitor() async {
    try {
      await _methodChannel.invokeMethod<void>('stopSosButtonMonitor');
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException {
      // Optional native BLE bridge.
    }
  }

  /// Starts paired button setup scan.
  Future<void> startPairedButtonSetupScan() async {
    try {
      await _methodChannel.invokeMethod<void>('startPairedButtonSetupScan');
    } on MissingPluginException {
      throw const HikerBleException('BLE pairing is not available here.');
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to scan for a paired SOS button.',
      );
    }
  }

  /// Stops paired button setup scan.
  Future<void> stopPairedButtonSetupScan() async {
    try {
      await _methodChannel.invokeMethod<void>('stopPairedButtonSetupScan');
    } on MissingPluginException {
      // Pairing is Android-first; unsupported platforms simply have no setup scan.
    } on PlatformException {
      // Setup scan is best-effort while leaving the existing SOS monitor active.
    }
  }

  /// Computes pair sos button.
  Future<void> pairSosButton({
    required String address,
    required String displayName,
  }) async {
    try {
      await _methodChannel
          .invokeMethod<void>('pairSosButton', {
            'address': address,
            'displayName': displayName,
          })
          .timeout(_pairingOperationTimeout);
    } on MissingPluginException {
      throw const HikerBleException('BLE pairing is not available here.');
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to pair the SOS button.',
        code: error.code,
      );
    } on TimeoutException {
      throw const HikerBleException('SOS button pairing timed out.');
    }
  }

  /// Computes list paired sos buttons.
  Future<List<PairedSosButton>> listPairedSosButtons() async {
    try {
      final raw = await _methodChannel.invokeMethod<List<Object?>>(
        'listPairedSosButtons',
      );
      return raw
              ?.whereType<Map>()
              .map(
                (item) => PairedSosButton.fromPlatform(
                  Map<Object?, Object?>.from(item),
                ),
              )
              .toList(growable: false) ??
          const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to securely read paired SOS buttons.',
      );
    }
  }

  /// Computes arm paired sos button test.
  Future<void> armPairedSosButtonTest(
    String deviceId, {
    Duration duration = const Duration(seconds: 30),
  }) async {
    final normalizedDeviceId = deviceId.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(normalizedDeviceId)) {
      throw const HikerBleException(
        'The paired SOS button ID is invalid.',
        code: 'paired_button_test_invalid',
      );
    }
    try {
      await _methodChannel.invokeMethod<void>('armPairedSosButtonTest', {
        'deviceId': normalizedDeviceId,
        'durationMillis': duration.inMilliseconds.clamp(5000, 30000).toInt(),
      });
    } on MissingPluginException {
      throw const HikerBleException(
        'SOS button testing is not available here.',
        code: 'paired_button_test_unavailable',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to start the SOS button test.',
        code: error.code,
      );
    }
  }

  /// Cancels paired sos button test.
  Future<void> cancelPairedSosButtonTest() async {
    try {
      await _methodChannel.invokeMethod<void>('cancelPairedSosButtonTest');
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to stop the SOS button test.',
        code: error.code,
      );
    }
  }

  /// Clears unreadable device-local pairing data so the physical button can
  /// be securely paired again. This intentionally does not clear the signed-in
  /// account scope.
  Future<void> resetPairedSosButtonRegistry() async {
    try {
      await _methodChannel.invokeMethod<void>('resetPairedSosButtonRegistry');
    } on MissingPluginException {
      throw const HikerBleException(
        'SOS button pairing reset is not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to reset SOS button pairing data.',
      );
    }
  }

  /// Computes paired sos button log.
  Future<List<HikerBleButtonLogRecord>> readPairedSosButtonLog(
    String deviceId,
  ) async {
    try {
      final raw = await _methodChannel
          .invokeMethod<List<Object?>>('readPairedSosButtonLog', {
            'deviceId': deviceId,
          })
          .timeout(_gattOperationTimeout);
      return raw
              ?.whereType<Map>()
              .map(
                (item) => HikerBleButtonLogRecord.fromPlatform(
                  Map<Object?, Object?>.from(item),
                ),
              )
              .toList(growable: false) ??
          const [];
    } on MissingPluginException {
      throw const HikerBleException(
        'BLE event-log download is not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to download the SOS button event log.',
        code: error.code,
      );
    } on TimeoutException {
      throw const HikerBleException('SOS button event-log download timed out.');
    }
  }

  /// Computes unpair sos button.
  Future<bool> unpairSosButton(String deviceId) async {
    try {
      return await _methodChannel.invokeMethod<bool>('unpairSosButton', {
            'deviceId': deviceId,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to securely unpair the SOS button.',
      );
    }
  }

  /// Sends the owner's current fix to the button that just emitted [eventId].
  /// Android performs the GATT connection and HMAC using its encrypted local
  /// registry; the pairing secret never crosses into Dart.
  Future<void> sendPairedSosLocation({
    required String deviceId,
    required int eventId,
    required SosTriggerLocation location,
  }) async {
    try {
      await _methodChannel
          .invokeMethod<void>('sendPairedSosLocation', {
            'deviceId': deviceId,
            'eventId': eventId,
            'latitude': location.latitude,
            'longitude': location.longitude,
            'accuracyMeters': location.accuracyMeters,
            'capturedAtMillis': (location.capturedAt ?? DateTime.now().toUtc())
                .millisecondsSinceEpoch,
          })
          .timeout(_gattOperationTimeout);
    } on MissingPluginException {
      throw const HikerBleException(
        'BLE location handoff is not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to send the SOS location to the button.',
      );
    } on TimeoutException {
      throw const HikerBleException('SOS button location handoff timed out.');
    }
  }

  /// Starts team location exchange.
  Future<void> startTeamLocationExchange({
    required String teamHikeSessionId,
    required String phoneNumber,
    required SosTriggerLocation location,
  }) async {
    if (teamHikeSessionId.trim().isEmpty || phoneNumber.trim().isEmpty) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('startTeamLocationExchange', {
        ..._teamLocationPayload(
          teamHikeSessionId: teamHikeSessionId,
          phoneNumber: phoneNumber,
          location: location,
        ),
        'teamLocationServiceUuid': teamLocationServiceUuid,
        'manufacturerId': manufacturerId,
      });
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException {
      // BLE permissions/support can be missing; cloud team sync still runs.
    }
  }

  /// Updates team location.
  Future<void> updateTeamLocation({
    required String teamHikeSessionId,
    required String phoneNumber,
    required SosTriggerLocation location,
  }) async {
    if (teamHikeSessionId.trim().isEmpty || phoneNumber.trim().isEmpty) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('updateTeamLocation', {
        ..._teamLocationPayload(
          teamHikeSessionId: teamHikeSessionId,
          phoneNumber: phoneNumber,
          location: location,
        ),
        'teamLocationServiceUuid': teamLocationServiceUuid,
        'manufacturerId': manufacturerId,
      });
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException {
      // Optional native BLE bridge.
    }
  }

  /// Stops team location exchange.
  Future<void> stopTeamLocationExchange() async {
    try {
      await _methodChannel.invokeMethod<void>('stopTeamLocationExchange');
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException {
      // Optional native BLE bridge.
    }
  }

  /// Computes team location payload.
  Map<String, Object?> _teamLocationPayload({
    required String teamHikeSessionId,
    required String phoneNumber,
    required SosTriggerLocation location,
  }) {
    return {
      'teamSessionId': teamHikeSessionId,
      'teamSessionHash': hikerBleHash(teamHikeSessionId),
      'phoneNumber': phoneNumber,
      'phoneNumberHash': hikerBlePhoneHash(phoneNumber),
      'latitude': location.latitude,
      'longitude': location.longitude,
      'accuracyMeters': location.accuracyMeters,
      'capturedAtMillis': (location.capturedAt ?? DateTime.now().toUtc())
          .millisecondsSinceEpoch,
    };
  }
}

/// Represents hiker ble event.
sealed class HikerBleEvent {
  /// Creates hiker ble event.
  const HikerBleEvent();

  /// Creates hiker ble event using from platform.
  factory HikerBleEvent.fromPlatform(Object? raw) {
    if (raw is! Map) {
      return HikerBleStatusEvent(
        status: 'unknown',
        message: 'BLE bridge emitted an unreadable event.',
        receivedAt: DateTime.now().toUtc(),
      );
    }
    final data = Map<Object?, Object?>.from(raw);
    final type = _stringFrom(data['type']);
    // Ignore old queued native events as well as new unpaired-button packets.
    if (type == 'sosButton') {
      return HikerBleStatusEvent(
        status: 'unsupported_unpaired_button',
        receivedAt: DateTime.now().toUtc(),
      );
    }
    final mode =
        _intFrom(data['mode']) ?? int.tryParse('${data['mode']}'.trim());
    final source = _stringFrom(data['source'])?.toLowerCase();
    if (const {
          'pairedSosButton',
          'nearbySosButton',
          'nearbySosLocation',
        }.contains(type) &&
        (data['isTest'] == true ||
            mode == 2 ||
            const {
              'paired_ble_button_test',
              'ble_sos_test',
              'button_debug',
            }.contains(source))) {
      return HikerBlePairedSosButtonTestEvent.fromPlatform(data);
    }
    return switch (type) {
      'pairedButtonSetupDevice' => HikerBlePairedButtonSetupEvent.fromPlatform(
        data,
      ),
      'pairedSosButton' => HikerBlePairedSosButtonEvent.fromPlatform(data),
      'pairedSosButtonTest' => HikerBlePairedSosButtonTestEvent.fromPlatform(
        data,
      ),
      'nearbySosButton' => HikerBleNearbySosButtonEvent.fromPlatform(data),
      'nearbySosLocation' => HikerBleNearbySosLocationEvent.fromPlatform(data),
      'sosHelp' => HikerBleSosHelpEvent.fromPlatform(data),
      'teamLocation' => HikerBleTeamLocationEvent.fromPlatform(data),
      _ => HikerBleStatusEvent.fromPlatform(data),
    };
  }
}

/// Represents hiker ble exception.
class HikerBleException implements Exception {
  /// Creates hiker ble exception.
  const HikerBleException(this.message, {this.code});

  final String message;
  final String? code;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents hiker ble paired button setup event.
class HikerBlePairedButtonSetupEvent extends HikerBleEvent {
  /// Creates hiker ble paired button setup event.
  const HikerBlePairedButtonSetupEvent({
    required this.address,
    required this.displayName,
    required this.rssi,
    required this.receivedAt,
    this.setupModeState,
    this.setupModeRemainingSeconds,
  });

  /// Creates hiker ble paired button setup event using from platform.
  factory HikerBlePairedButtonSetupEvent.fromPlatform(
    Map<Object?, Object?> data,
  ) {
    final setupModeState = _intFrom(data['setupModeState']);
    final setupModeRemainingSeconds = _intFrom(
      data['setupModeRemainingSeconds'],
    );
    return HikerBlePairedButtonSetupEvent(
      address: _stringFrom(data['address'], fallback: '')!,
      displayName: _stringFrom(
        data['displayName'],
        fallback: HikerBleService.defaultPairedButtonName,
      )!,
      rssi: _intFrom(data['rssi']) ?? 0,
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
      setupModeState:
          setupModeState != null && setupModeState >= 0 && setupModeState <= 255
          ? setupModeState
          : null,
      setupModeRemainingSeconds:
          setupModeRemainingSeconds != null &&
              setupModeRemainingSeconds >= 0 &&
              setupModeRemainingSeconds <= 255
          ? setupModeRemainingSeconds
          : null,
    );
  }

  final String address;
  final String displayName;
  final int rssi;
  final DateTime receivedAt;
  final int? setupModeState;
  final int? setupModeRemainingSeconds;
}

/// Represents paired sos button.
class PairedSosButton {
  /// Creates paired sos button.
  const PairedSosButton({
    required this.deviceId,
    required this.displayName,
    required this.pairedAt,
    this.lastSeenAt,
    this.lastAcceptedEventId,
  });

  /// Creates paired sos button using from platform.
  factory PairedSosButton.fromPlatform(Map<Object?, Object?> data) {
    return PairedSosButton(
      deviceId: _stringFrom(data['deviceId'], fallback: '')!,
      displayName: _stringFrom(
        data['displayName'],
        fallback: HikerBleService.defaultPairedButtonName,
      )!,
      pairedAt: _dateFromMillis(data['pairedAtMillis']),
      lastSeenAt: _nullableDateFromMillis(data['lastSeenAtMillis']),
      lastAcceptedEventId: _intFrom(data['lastAcceptedEventId']),
    );
  }

  final String deviceId;
  final String displayName;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final int? lastAcceptedEventId;
}

/// Represents sos button readiness.
class SosButtonReadiness {
  /// Creates sos button readiness.
  const SosButtonReadiness({
    required this.supported,
    required this.bluetoothEnabled,
    required this.scanPermissionGranted,
    required this.connectPermissionGranted,
    required this.notificationPermissionGranted,
    required this.notificationsEnabled,
    required this.batteryOptimizationExempt,
    required this.monitorEnabled,
    required this.monitorHealthy,
    required this.monitorHeartbeatAt,
    required this.scanState,
    required this.lastScanStartedAt,
    required this.lastScanResultAt,
    required this.lastFailure,
    required this.restartCount,
    required this.lostButtonWarningEnabled,
    required this.lostButtonThreshold,
    required this.checkedAt,
    required this.pairedButtons,
  });

  /// Creates sos button readiness using unsupported.
  factory SosButtonReadiness.unsupported() => SosButtonReadiness(
    supported: false,
    bluetoothEnabled: false,
    scanPermissionGranted: false,
    connectPermissionGranted: false,
    notificationPermissionGranted: false,
    notificationsEnabled: false,
    batteryOptimizationExempt: false,
    monitorEnabled: false,
    monitorHealthy: false,
    monitorHeartbeatAt: null,
    scanState: 'unsupported',
    lastScanStartedAt: null,
    lastScanResultAt: null,
    lastFailure: null,
    restartCount: 0,
    lostButtonWarningEnabled: false,
    lostButtonThreshold: const Duration(hours: 1),
    checkedAt: DateTime.now().toUtc(),
    pairedButtons: const [],
  );

  /// Creates sos button readiness using from platform.
  factory SosButtonReadiness.fromPlatform(Map<Object?, Object?> data) {
    final rawButtons = data['pairedButtons'];
    return SosButtonReadiness(
      supported: data['supported'] == true,
      bluetoothEnabled: data['bluetoothEnabled'] == true,
      scanPermissionGranted: data['scanPermissionGranted'] == true,
      connectPermissionGranted: data['connectPermissionGranted'] == true,
      notificationPermissionGranted:
          data['notificationPermissionGranted'] == true,
      notificationsEnabled: data['notificationsEnabled'] == true,
      batteryOptimizationExempt: data['batteryOptimizationExempt'] == true,
      monitorEnabled: data['monitorEnabled'] == true,
      monitorHealthy: data['monitorHealthy'] == true,
      monitorHeartbeatAt: _nullableDateFromMillis(
        data['monitorHeartbeatAtMillis'],
      ),
      scanState: _stringFrom(data['scanState'], fallback: 'unknown')!,
      lastScanStartedAt: _nullableDateFromMillis(
        data['lastScanStartedAtMillis'],
      ),
      lastScanResultAt: _nullableDateFromMillis(data['lastScanResultAtMillis']),
      lastFailure: _stringFrom(data['lastFailure']),
      restartCount: _intFrom(data['restartCount']) ?? 0,
      lostButtonWarningEnabled: data['lostButtonWarningEnabled'] != false,
      lostButtonThreshold: Duration(
        milliseconds:
            _intFrom(data['lostButtonThresholdMillis']) ??
            const Duration(hours: 1).inMilliseconds,
      ),
      checkedAt: _dateFromMillis(data['checkedAtMillis']),
      pairedButtons: rawButtons is List
          ? rawButtons
                .whereType<Map>()
                .map(
                  (value) => PairedSosButton.fromPlatform(
                    Map<Object?, Object?>.from(value),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  final bool supported;
  final bool bluetoothEnabled;
  final bool scanPermissionGranted;
  final bool connectPermissionGranted;
  final bool notificationPermissionGranted;
  final bool notificationsEnabled;
  final bool batteryOptimizationExempt;
  final bool monitorEnabled;
  final bool monitorHealthy;
  final DateTime? monitorHeartbeatAt;
  final String scanState;
  final DateTime? lastScanStartedAt;
  final DateTime? lastScanResultAt;
  final String? lastFailure;
  final int restartCount;
  final bool lostButtonWarningEnabled;
  final Duration lostButtonThreshold;
  final DateTime checkedAt;
  final List<PairedSosButton> pairedButtons;

  /// Returns has paired button.
  bool get hasPairedButton => pairedButtons.isNotEmpty;

  /// Returns freshest button.
  PairedSosButton? get freshestButton {
    PairedSosButton? freshest;
    for (final button in pairedButtons) {
      if (freshest == null ||
          (button.lastSeenAt != null &&
              (freshest.lastSeenAt == null ||
                  button.lastSeenAt!.isAfter(freshest.lastSeenAt!)))) {
        freshest = button;
      }
    }
    return freshest;
  }

  /// Computes button seen recently.
  bool buttonSeenRecently({Duration maximumAge = const Duration(minutes: 2)}) {
    final lastSeen = freshestButton?.lastSeenAt;
    return lastSeen != null && checkedAt.difference(lastSeen) <= maximumAge;
  }

  /// Returns blocking warnings.
  List<String> get blockingWarnings {
    final warnings = <String>[];
    if (!supported) warnings.add('Bluetooth Low Energy is unavailable.');
    if (!bluetoothEnabled) warnings.add('Bluetooth is turned off.');
    if (!scanPermissionGranted || !connectPermissionGranted) {
      warnings.add('Required Bluetooth permission is missing.');
    }
    if (!notificationPermissionGranted || !notificationsEnabled) {
      warnings.add('SOS notifications are disabled.');
    }
    if (!monitorEnabled || !monitorHealthy) {
      warnings.add('The background SOS monitor is not healthy.');
    }
    if (hasPairedButton && !buttonSeenRecently()) {
      warnings.add('The paired SOS button has not been seen recently.');
    }
    return warnings;
  }
}

/// Represents hiker ble button log record.
class HikerBleButtonLogRecord {
  /// Creates hiker ble button log record.
  const HikerBleButtonLogRecord({
    required this.sequence,
    required this.uptimeMillis,
    required this.epochSeconds,
    required this.eventId,
    required this.type,
    required this.resetReason,
    required this.detail,
  });

  /// Creates hiker ble button log record using from platform.
  factory HikerBleButtonLogRecord.fromPlatform(Map<Object?, Object?> data) {
    return HikerBleButtonLogRecord(
      sequence: _intFrom(data['sequence']) ?? 0,
      uptimeMillis: _intFrom(data['uptimeMillis']) ?? 0,
      epochSeconds: _intFrom(data['epochSeconds']) ?? 0,
      eventId: _intFrom(data['eventId']) ?? 0,
      type: _intFrom(data['type']) ?? 0,
      resetReason: _intFrom(data['resetReason']) ?? 0,
      detail: _intFrom(data['detail']) ?? 0,
    );
  }

  final int sequence;
  final int uptimeMillis;
  final int epochSeconds;
  final int eventId;
  final int type;
  final int resetReason;
  final int detail;

  /// Returns epoch time.
  DateTime? get epochTime {
    if (epochSeconds <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        epochSeconds * 1000,
        isUtc: true,
      );
    } on ArgumentError {
      return null;
    }
  }

  /// Returns uptime.
  Duration get uptime => Duration(milliseconds: uptimeMillis);

  /// Returns type label.
  String get typeLabel => switch (type) {
    1 => 'Boot',
    2 => 'Button press',
    3 => 'SOS triggered',
    4 => 'Setup mode started',
    5 => 'Pairing request',
    6 => 'Pairing confirmed',
    7 => 'Pairing expired',
    8 => 'Factory reset',
    9 => 'Location accepted',
    10 => 'Location rejected',
    11 => 'Location relay started',
    12 => 'SOS session finished',
    13 => 'Log download authorized',
    14 => 'Maintenance started',
    15 => 'Maintenance stopped',
    16 => 'Authentication rejected',
    17 => 'Button input fault',
    18 => 'SOS press queued',
    19 => 'Test mode armed',
    20 => 'Test request rejected',
    _ => 'Unknown event ($type)',
  };
}

/// An authenticated type-4 press from a button paired to this phone.
/// The native Android/iOS registry verifies its tag; no secret is exposed to
/// Dart or included in this event.
class HikerBlePairedSosButtonEvent extends HikerBleEvent {
  /// Creates hiker ble paired sos button event.
  const HikerBlePairedSosButtonEvent({
    required this.deviceId,
    required this.receivedAt,
    required this.mode,
    this.displayName,
    this.counter,
    this.rssi,
  });

  /// Creates hiker ble paired sos button event using from platform.
  factory HikerBlePairedSosButtonEvent.fromPlatform(
    Map<Object?, Object?> data,
  ) {
    return HikerBlePairedSosButtonEvent(
      deviceId: _stringFrom(data['deviceId'], fallback: '')!,
      displayName: _stringFrom(data['displayName']),
      counter: _intFrom(data['counter']),
      mode: _intFrom(data['mode']) ?? 1,
      rssi: _intFrom(data['rssi']),
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
    );
  }

  final String deviceId;
  final String? displayName;
  final int? counter;
  final int mode;
  final int? rssi;
  final DateTime receivedAt;
}

/// An authenticated press consumed by an explicitly armed local test window.
/// Native code emits this instead of persisting or dispatching an SOS.
class HikerBlePairedSosButtonTestEvent extends HikerBleEvent {
  /// Creates hiker ble paired sos button test event.
  const HikerBlePairedSosButtonTestEvent({
    required this.deviceId,
    required this.receivedAt,
    this.displayName,
    this.counter,
    this.rssi,
  });

  /// Creates hiker ble paired sos button test event using from platform.
  factory HikerBlePairedSosButtonTestEvent.fromPlatform(
    Map<Object?, Object?> data,
  ) {
    return HikerBlePairedSosButtonTestEvent(
      deviceId: _stringFrom(data['deviceId'], fallback: '')!,
      displayName: _stringFrom(data['displayName']),
      counter: _intFrom(data['counter']),
      rssi: _intFrom(data['rssi']),
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
    );
  }

  final String deviceId;
  final String? displayName;
  final int? counter;
  final int? rssi;
  final DateTime receivedAt;
}

/// An unverified type-4 press from another person's paired button. This event
/// must only lead to a non-destructive proximity popup.
class HikerBleNearbySosButtonEvent extends HikerBleEvent {
  /// Creates hiker ble nearby sos button event.
  const HikerBleNearbySosButtonEvent({
    required this.deviceId,
    required this.receivedAt,
    this.counter,
    this.rssi,
  });

  /// Creates hiker ble nearby sos button event using from platform.
  factory HikerBleNearbySosButtonEvent.fromPlatform(
    Map<Object?, Object?> data,
  ) {
    return HikerBleNearbySosButtonEvent(
      deviceId: _stringFrom(data['deviceId'], fallback: '')!,
      counter: _intFrom(data['counter']),
      rssi: _intFrom(data['rssi']),
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
    );
  }

  final String deviceId;
  final int? counter;
  final int? rssi;
  final DateTime receivedAt;
}

/// Represents hiker ble sos help event.
class HikerBleSosHelpEvent extends HikerBleEvent {
  /// Creates hiker ble sos help event.
  const HikerBleSosHelpEvent({
    required this.phoneNumberHash,
    required this.location,
    required this.receivedAt,
    this.rssi,
    this.source = 'ble_sos_test',
  });

  /// Creates hiker ble sos help event using from platform.
  factory HikerBleSosHelpEvent.fromPlatform(Map<Object?, Object?> data) {
    return HikerBleSosHelpEvent(
      phoneNumberHash: _intFrom(data['phoneNumberHash']) ?? 0,
      rssi: _intFrom(data['rssi']),
      source: _stringFrom(data['source'], fallback: 'ble_sos_test')!,
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
      location: SosTriggerLocation(
        latitude: _doubleFrom(data['latitude']),
        longitude: _doubleFrom(data['longitude']),
        accuracyMeters: _nullableDoubleFrom(data['accuracyMeters']),
        capturedAt: _dateFromMillis(data['capturedAtMillis']),
      ),
    );
  }

  final int phoneNumberHash;
  final SosTriggerLocation location;
  final DateTime receivedAt;
  final int? rssi;
  final String source;

  /// Type-three beacons are short-lived diagnostics, not an emergency observation.
  bool canPresentTestPreview(DateTime now, {bool debugCaptureEnabled = false}) {
    if (debugCaptureEnabled) return false;
    final age = now.toUtc().difference(receivedAt.toUtc());
    return !age.isNegative && age <= const Duration(seconds: 30);
  }
}

/// Represents hiker ble team location event.
class HikerBleTeamLocationEvent extends HikerBleEvent {
  /// Creates hiker ble team location event.
  const HikerBleTeamLocationEvent({
    required this.teamSessionHash,
    required this.phoneNumberHash,
    required this.location,
    required this.receivedAt,
    this.rssi,
  });

  /// Creates hiker ble team location event using from platform.
  factory HikerBleTeamLocationEvent.fromPlatform(Map<Object?, Object?> data) {
    final capturedAt = _dateFromMillis(data['capturedAtMillis']);
    return HikerBleTeamLocationEvent(
      teamSessionHash: _intFrom(data['teamSessionHash']) ?? 0,
      phoneNumberHash: _intFrom(data['phoneNumberHash']) ?? 0,
      rssi: _intFrom(data['rssi']),
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
      location: SosTriggerLocation(
        latitude: _doubleFrom(data['latitude']),
        longitude: _doubleFrom(data['longitude']),
        accuracyMeters: _nullableDoubleFrom(data['accuracyMeters']),
        capturedAt: capturedAt,
      ),
    );
  }

  final int teamSessionHash;
  final int phoneNumberHash;
  final SosTriggerLocation location;
  final DateTime receivedAt;
  final int? rssi;
}

/// A type-5 location relay from a paired SOS button. The location was
/// accepted by the button from the owner's phone, but nearby phones do not
/// possess the pairing secret and must treat the relay as an unverified
/// proximity signal.
class HikerBleNearbySosLocationEvent extends HikerBleEvent {
  /// Creates hiker ble nearby sos location event.
  const HikerBleNearbySosLocationEvent({
    required this.deviceId,
    required this.location,
    required this.receivedAt,
    this.counter,
    this.rssi,
  });

  /// Creates hiker ble nearby sos location event using from platform.
  factory HikerBleNearbySosLocationEvent.fromPlatform(
    Map<Object?, Object?> data,
  ) {
    return HikerBleNearbySosLocationEvent(
      deviceId: _stringFrom(data['deviceId'], fallback: '')!,
      counter: _intFrom(data['counter']),
      rssi: _intFrom(data['rssi']),
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
      location: SosTriggerLocation(
        latitude: _doubleFrom(data['latitude']),
        longitude: _doubleFrom(data['longitude']),
        accuracyMeters: _nullableDoubleFrom(data['accuracyMeters']),
        capturedAt: _dateFromMillis(data['receivedAtMillis']),
      ),
    );
  }

  final String deviceId;
  final int? counter;
  final int? rssi;
  final DateTime receivedAt;
  final SosTriggerLocation location;
}

/// Represents hiker ble status event.
class HikerBleStatusEvent extends HikerBleEvent {
  /// Creates hiker ble status event.
  const HikerBleStatusEvent({
    required this.status,
    required this.receivedAt,
    this.message,
  });

  /// Creates hiker ble status event using from platform.
  factory HikerBleStatusEvent.fromPlatform(Map<Object?, Object?> data) {
    return HikerBleStatusEvent(
      status: _stringFrom(data['status'], fallback: 'status')!,
      message: _stringFrom(data['message']),
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
    );
  }

  final String status;
  final String? message;
  final DateTime receivedAt;
}

/// Computes hiker ble phone hash.
int hikerBlePhoneHash(String phoneNumber) {
  return hikerBleHash(phoneNumber.replaceAll(RegExp(r'[^0-9]'), ''));
}

/// Computes hiker ble hash.
int hikerBleHash(String value) {
  const int fnvPrime = 0x01000193;
  var hash = 0x811c9dc5;
  for (final unit in value.trim().toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  return hash;
}

/// Computes string from.
String? _stringFrom(Object? value, {String? fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

/// Computes int from.
int? _intFrom(Object? value) {
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return null;
}

/// Computes double from.
double _doubleFrom(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return 0;
}

/// Computes nullable double from.
double? _nullableDoubleFrom(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return null;
}

/// Computes date from millis.
DateTime _dateFromMillis(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    } on ArgumentError {
      // Ignore malformed native timestamps and fall back to receipt time.
    }
  }
  return DateTime.now().toUtc();
}

/// Computes nullable date from millis.
DateTime? _nullableDateFromMillis(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    } on ArgumentError {
      return null;
    }
  }
  return null;
}
