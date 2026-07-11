import 'dart:async';

import 'package:flutter/services.dart';

import '../../sos/Model/sos_models.dart';

class HikerBleService {
  const HikerBleService();

  static const String sosServiceUuid = '7e2a1d32-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String teamLocationServiceUuid =
      '7e2a1d33-8b10-4f4d-9f78-0c6f1d65cba1';
  static const String sosHelpServiceUuid =
      '7e2a1d34-8b10-4f4d-9f78-0c6f1d65cba1';
  static const int manufacturerId = 0x02e5;
  static const MethodChannel _methodChannel = MethodChannel(
    'hiker_circle/ble_bridge',
  );
  static const EventChannel _eventChannel = EventChannel(
    'hiker_circle/ble_events',
  );

  Stream<HikerBleEvent> get events {
    return _eventChannel.receiveBroadcastStream().map(
      HikerBleEvent.fromPlatform,
    );
  }

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
    } on PlatformException {
      // BLE permissions/support can be missing; SOS remains available in-app.
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
      'sosButton' => HikerBleSosButtonEvent.fromPlatform(data),
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
