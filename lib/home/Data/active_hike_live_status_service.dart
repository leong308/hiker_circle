import '../../app/Data/app_settings_controller.dart';
import 'location_update_interval_controller.dart';
// ActiveHikeLiveStatusService bridges hike status, native GPS buffers and native safety events.
import 'dart:async';

import 'package:flutter/services.dart';

import '../Model/hike_session_models.dart';

/// Represents active hike live status service.
class ActiveHikeLiveStatusService {
  /// Creates active hike live status service.
  const ActiveHikeLiveStatusService();

  static const MethodChannel _channel = MethodChannel(
    'hiker_circle/active_hike_live_status',
  );

  /// Sets native safety event handler.
  void setNativeSafetyEventHandler(
    Future<void> Function()? handler, {
    Future<void> Function()? onFallImpactCheckChanged,
  }) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              switch (call.method) {
                case 'onNativeSafetyEvent':
                  await handler();
                case 'onFallImpactCheckChanged':
                  await onFallImpactCheckChanged?.call();
              }
            },
    );
  }

  /// Reads the current impact check for the active hike.
  Future<bool> isCheckingFallImpact({
    required String sessionId,
    required String ownerUid,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('isCheckingFallImpact', {
            'sessionId': sessionId,
            'ownerUid': ownerUid,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Send the current session identity and recording interval to native background tracking.
  Future<void> startOrUpdate(
    ActiveHikeSession activeHike, {
    String ownerUid = '',
  }) async {
    try {
      await _channel.invokeMethod<void>('startOrUpdateActiveHikeLiveStatus', {
        ..._activeHikeToPlatformMap(activeHike),
        'ownerUid': ownerUid,
        'locationUploadIntervalMillis':
            activeHike.draft.locationRecordingInterval.inMilliseconds,
      });
    } on MissingPluginException {
      // Desktop/web builds do not provide this optional platform surface.
    } on PlatformException {
      // Live status is optional; keep the hike session running if the native
      // surface is unavailable or disabled by the user.
    }
  }

  /// Returns pending native location samples.
  Future<List<Map<String, dynamic>>> getPendingNativeLocationSamples(
    String sessionId,
  ) async {
    try {
      final rows = await _channel.invokeListMethod<dynamic>(
        'getPendingNativeLocationSamples',
        {'sessionId': sessionId, 'limit': 500},
      );
      return (rows ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Acknowledge only samples already accepted by the durable Flutter storage path.
  Future<void> acknowledgeNativeLocationSamples(
    String sessionId,
    List<String> sampleIds,
  ) async {
    try {
      await _channel.invokeMethod<dynamic>('acknowledgeNativeLocationSamples', {
        'sessionId': sessionId,
        'sampleIds': sampleIds,
      });
    } on MissingPluginException {
      /* Optional platform feature. */
    } on PlatformException {
      /* Durable samples will be read again. */
    }
  }

  /// Marks native location samples cloud acknowledged.
  Future<void> markNativeLocationSamplesCloudAcknowledged(
    String sessionId,
    List<int> sampledAtMillis,
  ) async {
    try {
      await _channel.invokeMethod<dynamic>(
        'markNativeLocationSamplesCloudAcknowledged',
        {'sessionId': sessionId, 'sampledAtMillis': sampledAtMillis},
      );
    } on MissingPluginException {
      /* Optional platform feature. */
    } on PlatformException {
      /* Cloud retries remain idempotent. */
    }
  }

  /// Returns native location buffer sessions.
  Future<List<String>> getNativeLocationBufferSessions() async {
    try {
      return await _channel.invokeListMethod<String>(
            'getNativeLocationBufferSessions',
          ) ??
          const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Computes remap native location session.
  Future<void> remapNativeLocationSession(
    String oldSessionId,
    String newSessionId,
  ) async {
    try {
      await _channel.invokeMethod<dynamic>('remapNativeLocationSession', {
        'oldSessionId': oldSessionId,
        'newSessionId': newSessionId,
      });
    } on MissingPluginException {
      /* Optional surface. */
    } on PlatformException {
      /* Original samples remain in durable storage. */
    }
  }

  /// Stops.
  Future<bool> stop() async {
    try {
      await _channel
          .invokeMethod<void>('stopActiveHikeLiveStatus')
          .timeout(const Duration(seconds: 3));
      return true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Computes consume pending safety event.
  Future<NativeHikeSafetyEvent?> consumePendingSafetyEvent({
    bool strict = false,
  }) async {
    try {
      final operation = _channel.invokeMapMethod<Object?, Object?>(
        'consumePendingSafetyEvent',
        strict ? const {'preferCurrent': true} : null,
      );
      final data = strict
          ? await operation.timeout(const Duration(seconds: 4))
          : await operation;
      if (data == null) return null;
      return NativeHikeSafetyEvent.fromPlatform(data);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      if (strict) rethrow;
      return null;
    }
  }

  /// Computes acknowledge safety event.
  Future<bool> acknowledgeSafetyEvent(String eventId) async {
    try {
      await _channel.invokeMethod<void>('acknowledgeSafetyEvent', {
        'eventId': eventId,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Cancels native safety alert.
  Future<bool> cancelNativeSafetyAlert(String eventId) async =>
      await _channel.invokeMethod<bool>('cancelNativeSafetyAlert', {
        'eventId': eventId,
      }) ??
      false;

  /// Silence this triggered event without deleting its durable dispatch work.
  /// False means the native event no longer matches; the caller can re-read it.
  Future<bool> stopTriggeredSafetyAlarm(String eventId) async {
    try {
      return await _channel
              .invokeMethod<bool>('stopTriggeredSafetyAlarm', {
                'eventId': eventId,
              })
              .timeout(const Duration(seconds: 4)) ??
          false;
    } on MissingPluginException {
      // Desktop/web do not provide the optional native safety service.
      return true;
    }
  }

  /// Require native proof before treating a public safety URL as a safe response.
  Future<bool> wasSafetyAlarmStopped(String eventId) async {
    if (eventId.trim().isEmpty) return false;
    try {
      return await _channel
              .invokeMethod<bool>('wasSafetyAlarmStopped', {'eventId': eventId})
              .timeout(const Duration(seconds: 4)) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Marks safety event dispatched.
  Future<bool> markSafetyEventDispatched(
    String eventId, {
    String? message,
  }) async {
    try {
      await _channel.invokeMethod<void>('markSafetyEventDispatched', {
        'eventId': eventId,
        if (message != null) 'message': message,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Computes request ios safety permissions.
  Future<void> requestIosSafetyPermissions() async {
    try {
      await _channel.invokeMethod<bool>('requestIosSafetyPermissions');
    } on MissingPluginException {
      // iOS-only permission surface.
    } on PlatformException {
      // The caller will re-read readiness and show Settings guidance.
    }
  }

  /// Opens ios safety settings.
  Future<void> openIosSafetySettings() async {
    try {
      await _channel.invokeMethod<void>('openIosSafetySettings');
    } on MissingPluginException {
      // iOS-only settings surface.
    } on PlatformException {
      // Keep the in-app guidance visible if Settings cannot open.
    }
  }

  /// Computes active power settings.
  Future<Map<String, dynamic>?> activePowerSettings() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'getActiveHikePowerSettings',
      );
      return value;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Computes native safety status.
  Future<NativeHikeSafetyStatus> nativeSafetyStatus() async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>(
        'getNativeSafetyStatus',
      );
      return NativeHikeSafetyStatus.fromPlatform(data);
    } on MissingPluginException {
      return const NativeHikeSafetyStatus.unsupported();
    } on PlatformException {
      return const NativeHikeSafetyStatus.unsupported();
    }
  }

  /// Opens background location settings.
  Future<void> openBackgroundLocationSettings() async {
    try {
      await _channel.invokeMethod<void>('openBackgroundLocationSettings');
    } on MissingPluginException {
      // Native monitoring is Android-only.
    } on PlatformException {
      // The caller retains its in-app guidance when settings cannot open.
    }
  }

  /// Opens full screen intent settings.
  Future<void> openFullScreenIntentSettings() async {
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } on MissingPluginException {
      // Native monitoring is Android-only.
    } on PlatformException {
      // The caller retains its in-app guidance when settings cannot open.
    }
  }

  /// Opens overlay settings.
  Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } on MissingPluginException {
      // Native monitoring is Android-only.
    } on PlatformException {
      // The caller retains its in-app guidance when settings cannot open.
    }
  }

  /// Computes active hike to platform map.
  Map<String, Object?> _activeHikeToPlatformMap(ActiveHikeSession activeHike) {
    return {
      'sessionId': activeHike.sessionId,
      'batterySafetyAdjusted': activeHike.batterySafetyAdjusted,
      'batterySafetyRevision': activeHike.batterySafetyRevision,
      'batteryOriginalFootprintIntervalSeconds':
          activeHike.batteryOriginalFootprintIntervalSeconds ??
          LocationUpdateIntervalController.instance.preferredInterval.inSeconds,
      'batteryOriginalSensorSensitivity':
          activeHike.batteryOriginalSensorSensitivity ??
          AppSettingsController.instance.fallSensorSensitivity,
      'trailName': activeHike.trail.name,
      'startedAtMillis': activeHike.startedAt.millisecondsSinceEpoch,
      'expectedReturnAtMillis':
          activeHike.draft.expectedReturnTime.millisecondsSinceEpoch,
      'checkIns': activeHike.checkIns,
      'queuedUpdates': activeHike.queuedUpdates,
      'batteryLevel': activeHike.batteryLevel,
      'distanceKm': activeHike.recordedDistanceKm,
      'routePointCount': activeHike.routePointCount,
      'fallDetectionEnabled': activeHike.draft.fallDetectionEnabled,
      'shareLiveLocation': activeHike.draft.shareLiveLocation,
      'sensorSensitivity':
          activeHike.draft.fallDetectionSettings.sensorSensitivity,
      'fallResponseMillis': activeHike
          .draft
          .fallDetectionSettings
          .fallResponseDuration
          .inMilliseconds,
      'longestRestMillis': activeHike
          .draft
          .fallDetectionSettings
          .longestRestDuration
          .inMilliseconds,
    };
  }
}

/// Represents native hike safety event.
class NativeHikeSafetyEvent {
  /// Creates native hike safety event.
  const NativeHikeSafetyEvent({
    required this.eventId,
    required this.sessionId,
    required this.kind,
    required this.phase,
    this.dispatchMessage,
    required this.detectedAt,
    required this.deadlineAt,
    required this.triggeredAt,
    this.localAlarmStopped = false,
    this.ownerUid = '',
  });

  /// Creates native hike safety event using from platform.
  factory NativeHikeSafetyEvent.fromPlatform(Map<Object?, Object?> data) {
    /// Computes date from.
    DateTime? dateFrom(Object? value) {
      final millis = value is num ? value.toInt() : 0;
      return millis > 0
          ? DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
          : null;
    }

    return NativeHikeSafetyEvent(
      eventId: data['eventId']?.toString() ?? '',
      sessionId: data['sessionId']?.toString() ?? '',
      kind: data['kind']?.toString() ?? 'prolonged_stillness',
      phase: data['phase']?.toString() ?? 'awaiting_response',
      dispatchMessage: data['dispatchMessage']?.toString(),
      detectedAt: dateFrom(data['detectedAtMillis']),
      deadlineAt: dateFrom(data['deadlineAtMillis']),
      triggeredAt: dateFrom(data['triggeredAtMillis']),
      localAlarmStopped: data['localAlarmStopped'] == true,
      ownerUid: data['ownerUid']?.toString() ?? '',
    );
  }

  final String eventId;
  final String sessionId;
  final String kind;
  final String phase;
  final String? dispatchMessage;
  final DateTime? detectedAt;
  final DateTime? deadlineAt;
  final DateTime? triggeredAt;
  final bool localAlarmStopped;
  final String ownerUid;

  /// Returns is triggering.
  bool get isTriggering => phase == 'triggering';

  /// Returns is dispatching.
  bool get isDispatching => phase == 'dispatching';

  /// Returns is dispatched.
  bool get isDispatched => phase == 'dispatched';

  /// Returns is dispatch failed.
  bool get isDispatchFailed => phase == 'dispatch_failed';

  /// Returns is ready for flutter dispatch.
  bool get isReadyForFlutterDispatch => phase == 'ready_for_flutter_dispatch';

  /// Returns is prolonged stillness.
  bool get isProlongedStillness => kind == 'prolonged_stillness';
}

/// Represents native hike safety status.
class NativeHikeSafetyStatus {
  /// Creates native hike safety status.
  const NativeHikeSafetyStatus({
    required this.supported,
    required this.configured,
    required this.backgroundLocationGranted,
    required this.fineLocationGranted,
    required this.fullScreenIntentGranted,
    required this.overlayGranted,
    this.platform = 'unknown',
    this.notificationAuthorizationStatus = 'unknown',
    this.notificationsAuthorized = false,
    this.timeSensitiveGranted = false,
    this.liveActivitiesGranted = false,
    this.motionAuthorizationStatus = 'unknown',
    this.motionGranted = false,
  });

  /// Creates native hike safety status using unsupported.
  const NativeHikeSafetyStatus.unsupported()
    : this(
        supported: false,
        configured: false,
        backgroundLocationGranted: false,
        fineLocationGranted: false,
        fullScreenIntentGranted: false,
        overlayGranted: false,
        platform: 'unsupported',
      );

  /// Creates native hike safety status using from platform.
  factory NativeHikeSafetyStatus.fromPlatform(Map<Object?, Object?>? data) {
    if (data == null) return const NativeHikeSafetyStatus.unsupported();
    return NativeHikeSafetyStatus(
      supported: true,
      configured: data['configured'] == true,
      backgroundLocationGranted: data['backgroundLocationGranted'] == true,
      fineLocationGranted: data['fineLocationGranted'] == true,
      fullScreenIntentGranted: data['fullScreenIntentGranted'] == true,
      overlayGranted: data['overlayGranted'] == true,
      platform: data['platform']?.toString() ?? 'unknown',
      notificationAuthorizationStatus:
          data['notificationAuthorizationStatus']?.toString() ?? 'unknown',
      notificationsAuthorized: data['notificationsAuthorized'] == true,
      timeSensitiveGranted: data['timeSensitiveGranted'] == true,
      liveActivitiesGranted: data['liveActivitiesGranted'] == true,
      motionAuthorizationStatus:
          data['motionAuthorizationStatus']?.toString() ?? 'unknown',
      motionGranted: data['motionGranted'] == true,
    );
  }

  final bool supported;
  final bool configured;
  final bool backgroundLocationGranted;
  final bool fineLocationGranted;
  final bool fullScreenIntentGranted;
  final bool overlayGranted;
  final String platform;
  final String notificationAuthorizationStatus;
  final bool notificationsAuthorized;
  final bool timeSensitiveGranted;
  final bool liveActivitiesGranted;
  final String motionAuthorizationStatus;
  final bool motionGranted;
}
