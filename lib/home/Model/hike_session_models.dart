import 'dart:math' as math;

import '../../sos/Model/sos_models.dart';
import '../../trail/Model/trail_models.dart';

enum HikeType {
  solo,
  team;

  String get label {
    switch (this) {
      case HikeType.solo:
        return 'Solo Hike';
      case HikeType.team:
        return 'Team Hike';
    }
  }
}

class FallDetectionSettings {
  const FallDetectionSettings({
    required this.sensorSensitivity,
    required this.stillnessDuration,
  });

  static const double minSensorSensitivity = 1;
  static const double maxSensorSensitivity = 10;
  static const double gravityMetersPerSecondSquared = 9.80665;
  static const Duration impactWindowDuration = Duration(milliseconds: 500);
  static const Duration postImpactBounceDuration = Duration(seconds: 2);
  static const Duration stillnessVerificationDuration = Duration(seconds: 10);
  static const Duration backpackTrapStillnessDuration = Duration(seconds: 20);

  final double sensorSensitivity;
  final Duration stillnessDuration;

  double get normalizedSensitivity {
    final clamped = sensorSensitivity.clamp(
      minSensorSensitivity,
      maxSensorSensitivity,
    );
    return (clamped - minSensorSensitivity) /
        (maxSensorSensitivity - minSensorSensitivity);
  }

  double get impactAccelerationThreshold {
    return _lerp(
      5.0 * gravityMetersPerSecondSquared,
      4.0 * gravityMetersPerSecondSquared,
      normalizedSensitivity,
    );
  }

  double get directImpactAccelerationThreshold {
    return _lerp(
      3.6 * gravityMetersPerSecondSquared,
      2.8 * gravityMetersPerSecondSquared,
      normalizedSensitivity,
    );
  }

  double get freeFallAccelerationThreshold {
    return _lerp(
      0.25 * gravityMetersPerSecondSquared,
      0.40 * gravityMetersPerSecondSquared,
      normalizedSensitivity,
    );
  }

  double get stillnessVarianceThreshold {
    return _lerp(0.012, 0.032, normalizedSensitivity);
  }

  double get significantLinearMovementThreshold {
    return _lerp(0.55, 1.25, normalizedSensitivity);
  }

  double get altitudeDropThresholdMeters {
    return _lerp(1.6, 0.8, normalizedSensitivity);
  }

  String get sensitivityLabel {
    if (sensorSensitivity < 3.5) {
      return 'Low';
    }
    if (sensorSensitivity > 7) {
      return 'High';
    }
    return 'Balanced';
  }

  String get responseCountdownDurationLabel {
    if (stillnessDuration.inSeconds < 60) {
      return '${stillnessDuration.inSeconds} sec';
    }
    return '${stillnessDuration.inMinutes} min';
  }

  String get stillnessDurationLabel => responseCountdownDurationLabel;

  bool get isHighSensitivity => sensorSensitivity > 7;

  static double _lerp(double start, double end, double amount) {
    return start + (end - start) * amount;
  }
}

class PlannedHike {
  const PlannedHike({
    required this.trail,
    required this.plannedStartTime,
    required this.expectedReturnTime,
    required this.weatherCached,
    required this.offlineMapDownloaded,
    required this.emergencyContactsSelected,
    required this.checklistCompleted,
    required this.checklistTotal,
    required this.phoneBatteryLevel,
    required this.liveLocationConfigured,
  });

  final Trail trail;
  final DateTime plannedStartTime;
  final DateTime expectedReturnTime;
  final bool weatherCached;
  final bool offlineMapDownloaded;
  final bool emergencyContactsSelected;
  final int checklistCompleted;
  final int checklistTotal;
  final int phoneBatteryLevel;
  final bool liveLocationConfigured;

  int get preparationPercent {
    if (checklistTotal == 0) {
      return 0;
    }
    return ((checklistCompleted / checklistTotal) * 100).round();
  }

  List<String> get missingPreparationItems {
    return [
      if (!offlineMapDownloaded) 'Offline map not downloaded',
      if (!weatherCached) 'Weather forecast not cached',
      if (!emergencyContactsSelected) 'No emergency contact selected',
      if (phoneBatteryLevel < 60) 'Phone battery below recommended level',
      if (checklistCompleted < checklistTotal) 'Gear checklist incomplete',
      if (!liveLocationConfigured) 'Live location sharing not configured',
    ];
  }
}

class HikeSessionDraft {
  const HikeSessionDraft({
    required this.hikeType,
    required this.trail,
    required this.startPointName,
    required this.destinationName,
    required this.departureTime,
    required this.expectedArrivalTime,
    required this.expectedReturnTime,
    required this.safetyCheckInInterval,
    required this.locationRecordingInterval,
    required this.emergencyContactNames,
    required this.shareLiveLocation,
    required this.fallDetectionEnabled,
    required this.fallDetectionSettings,
    required this.pathDeviationEnabled,
    required this.offlinePhysicalAlertEnabled,
    required this.duressEnabled,
    required this.completedChecklistItems,
  });

  factory HikeSessionDraft.fromTrail(Trail trail) {
    final departure = DateTime(2026, 6, 5, 6, 30);
    return HikeSessionDraft(
      hikeType: HikeType.solo,
      trail: trail,
      startPointName: trail.checkpoints.first.name,
      destinationName: trail.checkpoints.last.name,
      departureTime: departure,
      expectedArrivalTime: DateTime(2026, 6, 5, 8, 30),
      expectedReturnTime: DateTime(2026, 6, 5, 11, 30),
      safetyCheckInInterval: const Duration(minutes: 30),
      locationRecordingInterval: const Duration(minutes: 5),
      emergencyContactNames: const ['Mother', 'Brother'],
      shareLiveLocation: true,
      fallDetectionEnabled: true,
      fallDetectionSettings: const FallDetectionSettings(
        sensorSensitivity: 5,
        stillnessDuration: Duration(seconds: 30),
      ),
      pathDeviationEnabled: true,
      offlinePhysicalAlertEnabled: true,
      duressEnabled: true,
      completedChecklistItems: const {
        'Drinking water',
        'Charged phone',
        'Torch',
        'Rain protection',
      },
    );
  }

  final HikeType hikeType;
  final Trail trail;
  final String startPointName;
  final String destinationName;
  final DateTime departureTime;
  final DateTime expectedArrivalTime;
  final DateTime expectedReturnTime;
  final Duration safetyCheckInInterval;
  final Duration locationRecordingInterval;
  final List<String> emergencyContactNames;
  final bool shareLiveLocation;
  final bool fallDetectionEnabled;
  final FallDetectionSettings fallDetectionSettings;
  final bool pathDeviationEnabled;
  final bool offlinePhysicalAlertEnabled;
  final bool duressEnabled;
  final Set<String> completedChecklistItems;

  HikeSessionDraft copyWith({
    HikeType? hikeType,
    Trail? trail,
    String? startPointName,
    String? destinationName,
    DateTime? departureTime,
    DateTime? expectedArrivalTime,
    DateTime? expectedReturnTime,
    Duration? safetyCheckInInterval,
    Duration? locationRecordingInterval,
    List<String>? emergencyContactNames,
    bool? shareLiveLocation,
    bool? fallDetectionEnabled,
    FallDetectionSettings? fallDetectionSettings,
    bool? pathDeviationEnabled,
    bool? offlinePhysicalAlertEnabled,
    bool? duressEnabled,
    Set<String>? completedChecklistItems,
  }) {
    return HikeSessionDraft(
      hikeType: hikeType ?? this.hikeType,
      trail: trail ?? this.trail,
      startPointName: startPointName ?? this.startPointName,
      destinationName: destinationName ?? this.destinationName,
      departureTime: departureTime ?? this.departureTime,
      expectedArrivalTime: expectedArrivalTime ?? this.expectedArrivalTime,
      expectedReturnTime: expectedReturnTime ?? this.expectedReturnTime,
      safetyCheckInInterval:
          safetyCheckInInterval ?? this.safetyCheckInInterval,
      locationRecordingInterval:
          locationRecordingInterval ?? this.locationRecordingInterval,
      emergencyContactNames:
          emergencyContactNames ?? this.emergencyContactNames,
      shareLiveLocation: shareLiveLocation ?? this.shareLiveLocation,
      fallDetectionEnabled: fallDetectionEnabled ?? this.fallDetectionEnabled,
      fallDetectionSettings:
          fallDetectionSettings ?? this.fallDetectionSettings,
      pathDeviationEnabled: pathDeviationEnabled ?? this.pathDeviationEnabled,
      offlinePhysicalAlertEnabled:
          offlinePhysicalAlertEnabled ?? this.offlinePhysicalAlertEnabled,
      duressEnabled: duressEnabled ?? this.duressEnabled,
      completedChecklistItems:
          completedChecklistItems ?? this.completedChecklistItems,
    );
  }
}

class ActiveHikeSession {
  const ActiveHikeSession({
    required this.sessionId,
    required this.draft,
    required this.startedAt,
    required this.batteryLevel,
    required this.queuedUpdates,
    required this.manualPins,
    required this.checkIns,
    this.batteryStartedLevel,
    this.latestLocation,
    this.routePoints = const [],
    this.manualPinLocations = const [],
  });

  factory ActiveHikeSession.fromDraft(HikeSessionDraft draft) {
    return ActiveHikeSession(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      draft: draft,
      startedAt: DateTime.now(),
      batteryLevel: 67,
      queuedUpdates: 3,
      manualPins: 0,
      checkIns: 0,
      batteryStartedLevel: 67,
    );
  }

  final String sessionId;
  final HikeSessionDraft draft;
  final DateTime startedAt;
  final int batteryLevel;
  final int? batteryStartedLevel;
  final int queuedUpdates;
  final int manualPins;
  final int checkIns;
  final HikeCoordinate? latestLocation;
  final List<HikeCoordinate> routePoints;
  final List<HikeManualPin> manualPinLocations;

  Trail get trail => draft.trail;
  Duration get elapsedDuration => DateTime.now().difference(startedAt);
  int get routePointCount => routePoints.length;

  double get recordedDistanceKm {
    if (routePoints.length < 2) {
      return 0;
    }

    var totalMeters = 0.0;
    for (var index = 1; index < routePoints.length; index++) {
      totalMeters += routePoints[index - 1].distanceTo(routePoints[index]);
    }
    return totalMeters / 1000;
  }

  int? get batteryUsedPercent {
    final started = batteryStartedLevel;
    if (started == null) {
      return null;
    }
    return math.max(0, started - batteryLevel);
  }

  bool hasPinnedNear(HikeCoordinate coordinate, {double thresholdMeters = 12}) {
    return manualPinLocations.any(
      (pin) => pin.coordinate.distanceTo(coordinate) <= thresholdMeters,
    );
  }

  ActiveHikeSession copyWith({
    String? sessionId,
    int? batteryLevel,
    int? batteryStartedLevel,
    int? queuedUpdates,
    int? manualPins,
    int? checkIns,
    HikeCoordinate? latestLocation,
    List<HikeCoordinate>? routePoints,
    List<HikeManualPin>? manualPinLocations,
  }) {
    return ActiveHikeSession(
      sessionId: sessionId ?? this.sessionId,
      draft: draft,
      startedAt: startedAt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryStartedLevel: batteryStartedLevel ?? this.batteryStartedLevel,
      queuedUpdates: queuedUpdates ?? this.queuedUpdates,
      manualPins: manualPins ?? this.manualPins,
      checkIns: checkIns ?? this.checkIns,
      latestLocation: latestLocation ?? this.latestLocation,
      routePoints: routePoints ?? this.routePoints,
      manualPinLocations: manualPinLocations ?? this.manualPinLocations,
    );
  }
}

class HikeCoordinate {
  const HikeCoordinate({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
  });

  factory HikeCoordinate.fromTriggerLocation(SosTriggerLocation location) {
    return HikeCoordinate(
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
      capturedAt: location.capturedAt ?? DateTime.now().toUtc(),
    );
  }

  factory HikeCoordinate.fromFirestore(Map<String, dynamic> data) {
    final capturedAt = data['capturedAtLocal'];
    return HikeCoordinate(
      latitude: _doubleFrom(data['latitude']),
      longitude: _doubleFrom(data['longitude']),
      accuracyMeters: data['accuracyMeters'] is num
          ? (data['accuracyMeters'] as num).toDouble()
          : null,
      capturedAt: capturedAt is String
          ? DateTime.tryParse(capturedAt) ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
    );
  }

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime capturedAt;

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
      'capturedAtLocal': capturedAt.toUtc().toIso8601String(),
    };
  }

  double distanceTo(HikeCoordinate other) {
    const earthRadiusMeters = 6371000.0;
    final startLatitude = _degreesToRadians(latitude);
    final endLatitude = _degreesToRadians(other.latitude);
    final deltaLatitude = _degreesToRadians(other.latitude - latitude);
    final deltaLongitude = _degreesToRadians(other.longitude - longitude);
    final haversine =
        math.sin(deltaLatitude / 2) * math.sin(deltaLatitude / 2) +
        math.cos(startLatitude) *
            math.cos(endLatitude) *
            math.sin(deltaLongitude / 2) *
            math.sin(deltaLongitude / 2);
    final centralAngle =
        2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadiusMeters * centralAngle;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  static double _doubleFrom(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }
}

class HikeManualPin {
  const HikeManualPin({
    required this.id,
    required this.coordinate,
    required this.pinnedAt,
  });

  final String id;
  final HikeCoordinate coordinate;
  final DateTime pinnedAt;

  Map<String, dynamic> toFirestore() {
    return {
      'pinId': id,
      'coordinate': coordinate.toFirestore(),
      'pinnedAtLocal': pinnedAt.toUtc().toIso8601String(),
    };
  }
}

enum PinLocationStatus { pinned, duplicate, unavailable }

class PinLocationResult {
  const PinLocationResult({required this.hike, required this.status});

  final ActiveHikeSession hike;
  final PinLocationStatus status;
}

class HikeSummaryReport {
  const HikeSummaryReport({
    required this.sessionId,
    required this.trailName,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.distanceKm,
    required this.checkIns,
    required this.manualPins,
    required this.routePointCount,
    required this.batteryStartPercent,
    required this.batteryEndPercent,
    required this.insights,
  });

  factory HikeSummaryReport.fromActiveHike({
    required ActiveHikeSession activeHike,
    required DateTime endedAt,
  }) {
    final distanceKm = activeHike.recordedDistanceKm > 0
        ? activeHike.recordedDistanceKm
        : activeHike.trail.distanceKm;
    final duration = endedAt.difference(activeHike.startedAt);
    final batteryStart =
        activeHike.batteryStartedLevel ?? activeHike.batteryLevel;
    final batteryDrop = math.max(0, batteryStart - activeHike.batteryLevel);
    final movingHours = math.max(duration.inMinutes / 60, 0.1);
    final paceMinutesPerKm = distanceKm <= 0
        ? 0
        : duration.inMinutes / math.max(distanceKm, 0.1);

    return HikeSummaryReport(
      sessionId: activeHike.sessionId,
      trailName: activeHike.trail.name,
      startedAt: activeHike.startedAt,
      endedAt: endedAt,
      duration: duration,
      distanceKm: distanceKm,
      checkIns: activeHike.checkIns,
      manualPins: activeHike.manualPins,
      routePointCount: activeHike.routePointCount,
      batteryStartPercent: batteryStart,
      batteryEndPercent: activeHike.batteryLevel,
      insights: [
        'Average pace: ${paceMinutesPerKm.round()} min/km across ${distanceKm.toStringAsFixed(2)} km.',
        'Tracking density: ${activeHike.routePointCount} GPS points saved for replay and safety review.',
        'Safety rhythm: ${activeHike.checkIns} check-ins and ${activeHike.manualPins} pinned locations.',
        'Battery used: $batteryDrop% over ${_formatDuration(duration)} (${(batteryDrop / movingHours).toStringAsFixed(1)}% per hour).',
        if (activeHike.queuedUpdates == 0)
          'Cloud sync: all hike telemetry is up to date.'
        else
          'Cloud sync: ${activeHike.queuedUpdates} updates are still queued for upload.',
      ],
    );
  }

  final String sessionId;
  final String trailName;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final double distanceKm;
  final int checkIns;
  final int manualPins;
  final int routePointCount;
  final int batteryStartPercent;
  final int batteryEndPercent;
  final List<String> insights;

  String get shareText {
    return [
      'Hike summary: $trailName',
      'Distance: ${distanceKm.toStringAsFixed(2)} km',
      'Duration: ${_formatDuration(duration)}',
      'Check-ins: $checkIns',
      'Pinned locations: $manualPins',
      'Battery: $batteryStartPercent% to $batteryEndPercent%',
      ...insights.map((insight) => '- $insight'),
    ].join('\n');
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sessionId': sessionId,
      'trailName': trailName,
      'startedAtLocal': startedAt.toUtc().toIso8601String(),
      'endedAtLocal': endedAt.toUtc().toIso8601String(),
      'durationMinutes': duration.inMinutes,
      'distanceKm': distanceKm,
      'checkIns': checkIns,
      'manualPins': manualPins,
      'routePointCount': routePointCount,
      'batteryStartPercent': batteryStartPercent,
      'batteryEndPercent': batteryEndPercent,
      'insights': insights,
      'shareText': shareText,
    };
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) {
      return '$minutes min';
    }
    return '${hours}h ${minutes}m';
  }
}
