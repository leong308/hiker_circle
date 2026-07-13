import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../sos/Model/sos_models.dart';

class HikerBleService {
  const HikerBleService();

  static const String defaultPairedButtonName = 'HikerCircle Button';
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
  static final Stream<HikerBleEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map(HikerBleEvent.fromPlatform)
      .asBroadcastStream();

  Stream<HikerBleEvent> get events => _events;

  Future<bool> isSupported() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

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

  Future<void> stopSosButtonMonitor() async {
    try {
      await _methodChannel.invokeMethod<void>('stopSosButtonMonitor');
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException {
      // Optional native BLE bridge.
    }
  }

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

  Future<void> stopPairedButtonSetupScan() async {
    try {
      await _methodChannel.invokeMethod<void>('stopPairedButtonSetupScan');
    } on MissingPluginException {
      // Pairing is Android-first; unsupported platforms simply have no setup scan.
    } on PlatformException {
      // Setup scan is best-effort while leaving the existing SOS monitor active.
    }
  }

  Future<void> pairSosButton({
    required String address,
    required String displayName,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>('pairSosButton', {
        'address': address,
        'displayName': displayName,
      });
    } on MissingPluginException {
      throw const HikerBleException('BLE pairing is not available here.');
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to pair the SOS button.',
      );
    }
  }

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
    } on PlatformException {
      return const [];
    }
  }

  Future<bool> isLegacyUnpairedSosButtonEnabled() async {
    try {
      return await _methodChannel.invokeMethod<bool>(
            'isLegacyUnpairedSosButtonEnabled',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> unpairSosButton(String deviceId) async {
    try {
      return await _methodChannel.invokeMethod<bool>('unpairSosButton', {
            'deviceId': deviceId,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
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
      await _methodChannel.invokeMethod<void>('sendPairedSosLocation', {
        'deviceId': deviceId,
        'eventId': eventId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracyMeters': location.accuracyMeters,
        'capturedAtMillis': (location.capturedAt ?? DateTime.now().toUtc())
            .millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      throw const HikerBleException(
        'BLE location handoff is not available here.',
      );
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to send the SOS location to the button.',
      );
    }
  }

  Future<void> setLegacyUnpairedSosButtonEnabled(bool enabled) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setLegacyUnpairedSosButtonEnabled',
        {'enabled': enabled},
      );
    } on MissingPluginException {
      // Unsupported on platforms without the Android paired-button registry.
    } on PlatformException {
      // The setting is optional; paired type-4 buttons remain the default.
    }
  }

  Future<void> broadcastPhysicalSosTest({
    required String phoneNumber,
    required SosTriggerLocation location,
    Duration duration = const Duration(seconds: 5),
  }) async {
    final broadcastStartedAt = DateTime.now().toUtc();
    try {
      await _methodChannel.invokeMethod<void>('broadcastPhysicalSosTest', {
        'manufacturerId': manufacturerId,
        'phoneNumber': phoneNumber,
        'phoneNumberHash': hikerBlePhoneHash(phoneNumber),
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracyMeters': location.accuracyMeters,
        'capturedAtMillis': broadcastStartedAt.millisecondsSinceEpoch,
        'durationMillis': duration.inMilliseconds.clamp(3000, 8000).toInt(),
      });
    } on MissingPluginException {
      throw const HikerBleException('BLE bridge is not available here.');
    } on PlatformException catch (error) {
      throw HikerBleException(
        error.message ?? 'Unable to broadcast the BLE SOS test.',
      );
    }
  }

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

  Future<void> stopTeamLocationExchange() async {
    try {
      await _methodChannel.invokeMethod<void>('stopTeamLocationExchange');
    } on MissingPluginException {
      // Optional native BLE bridge.
    } on PlatformException {
      // Optional native BLE bridge.
    }
  }

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

sealed class HikerBleEvent {
  const HikerBleEvent();

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
    return switch (type) {
      'pairedButtonSetupDevice' => HikerBlePairedButtonSetupEvent.fromPlatform(
        data,
      ),
      'sosButton' => HikerBleSosButtonEvent.fromPlatform(data),
      'pairedSosButton' => HikerBlePairedSosButtonEvent.fromPlatform(data),
      'nearbySosButton' => HikerBleNearbySosButtonEvent.fromPlatform(data),
      'nearbySosLocation' => HikerBleNearbySosLocationEvent.fromPlatform(data),
      'sosHelp' => HikerBleSosHelpEvent.fromPlatform(data),
      'teamLocation' => HikerBleTeamLocationEvent.fromPlatform(data),
      _ => HikerBleStatusEvent.fromPlatform(data),
    };
  }
}

class HikerBleException implements Exception {
  const HikerBleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HikerBlePairedButtonSetupEvent extends HikerBleEvent {
  const HikerBlePairedButtonSetupEvent({
    required this.address,
    required this.displayName,
    required this.rssi,
    required this.receivedAt,
  });

  factory HikerBlePairedButtonSetupEvent.fromPlatform(
    Map<Object?, Object?> data,
  ) {
    return HikerBlePairedButtonSetupEvent(
      address: _stringFrom(data['address'], fallback: '')!,
      displayName: _stringFrom(
        data['displayName'],
        fallback: HikerBleService.defaultPairedButtonName,
      )!,
      rssi: _intFrom(data['rssi']) ?? 0,
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
    );
  }

  final String address;
  final String displayName;
  final int rssi;
  final DateTime receivedAt;
}

class PairedSosButton {
  const PairedSosButton({
    required this.deviceId,
    required this.displayName,
    required this.pairedAt,
    this.lastSeenAt,
    this.lastAcceptedEventId,
  });

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

class HikerBleSosButtonEvent extends HikerBleEvent {
  const HikerBleSosButtonEvent({
    required this.receivedAt,
    this.counter,
    this.rssi,
    this.source = 'ble_button',
  });

  factory HikerBleSosButtonEvent.fromPlatform(Map<Object?, Object?> data) {
    return HikerBleSosButtonEvent(
      receivedAt: _dateFromMillis(data['receivedAtMillis']),
      counter: _intFrom(data['counter']),
      rssi: _intFrom(data['rssi']),
      source: _stringFrom(data['source'], fallback: 'ble_button')!,
    );
  }

  final DateTime receivedAt;
  final int? counter;
  final int? rssi;
  final String source;
}

/// An authenticated type-4 press from a button paired to this phone.
/// Only the native Android registry verifies its tag; no secret is exposed to
/// Dart or included in this event.
class HikerBlePairedSosButtonEvent extends HikerBleEvent {
  const HikerBlePairedSosButtonEvent({
    required this.deviceId,
    required this.receivedAt,
    required this.mode,
    this.displayName,
    this.counter,
    this.rssi,
  });

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

/// An unverified type-4 press from another person's paired button. This event
/// must only lead to a non-destructive proximity popup.
class HikerBleNearbySosButtonEvent extends HikerBleEvent {
  const HikerBleNearbySosButtonEvent({
    required this.deviceId,
    required this.receivedAt,
    this.counter,
    this.rssi,
  });

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

class HikerBleSosHelpEvent extends HikerBleEvent {
  const HikerBleSosHelpEvent({
    required this.phoneNumberHash,
    required this.location,
    required this.receivedAt,
    this.rssi,
    this.source = 'ble_sos_test',
  });

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
}

class HikerBleTeamLocationEvent extends HikerBleEvent {
  const HikerBleTeamLocationEvent({
    required this.teamSessionHash,
    required this.phoneNumberHash,
    required this.location,
    required this.receivedAt,
    this.rssi,
  });

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
  const HikerBleNearbySosLocationEvent({
    required this.deviceId,
    required this.location,
    required this.receivedAt,
    this.counter,
    this.rssi,
  });

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

class HikerBleStatusEvent extends HikerBleEvent {
  const HikerBleStatusEvent({
    required this.status,
    required this.receivedAt,
    this.message,
  });

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

int hikerBlePhoneHash(String phoneNumber) {
  return hikerBleHash(phoneNumber.replaceAll(RegExp(r'[^0-9]'), ''));
}

int hikerBleHash(String value) {
  const int fnvPrime = 0x01000193;
  var hash = 0x811c9dc5;
  for (final unit in value.trim().toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  return hash;
}

String? _stringFrom(Object? value, {String? fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

int? _intFrom(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return null;
}

double _doubleFrom(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

double? _nullableDoubleFrom(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

DateTime _dateFromMillis(Object? value) {
  if (value is num && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return DateTime.now().toUtc();
}

DateTime? _nullableDateFromMillis(Object? value) {
  if (value is num && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return null;
}
