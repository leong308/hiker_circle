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

class TeamHikeBuddy {
  const TeamHikeBuddy({
    required this.name,
    required this.handle,
    required this.phoneNumber,
    this.role = 'Teammate',
    this.avatarColorValue = 0xFF34A853,
  });

  factory TeamHikeBuddy.fromFirestore(Map<String, dynamic> data) {
    return TeamHikeBuddy(
      name: _modelStringFrom(data['name']).isEmpty
          ? 'Trail buddy'
          : _modelStringFrom(data['name']),
      handle: _modelStringFrom(data['handle']),
      phoneNumber: _modelStringFrom(data['phoneNumber']),
      role: _modelStringFrom(data['role']).isEmpty
          ? 'Teammate'
          : _modelStringFrom(data['role']),
      avatarColorValue: _modelIntFrom(
        data['avatarColorValue'],
        fallback: 0xFF34A853,
      ),
    );
  }

  final String name;
  final String handle;
  final String phoneNumber;
  final String role;
  final int avatarColorValue;

  String get normalizedPhoneNumber =>
      phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');

  String get shortName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Buddy';
    }
    final firstPart = trimmed.split(RegExp(r'\s+')).first;
    return firstPart.isEmpty ? trimmed : firstPart;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'handle': handle,
      'phoneNumber': phoneNumber,
      'role': role,
      'avatarColorValue': avatarColorValue,
    };
  }
}

enum TeamHikePhase {
  inviting,
  readyCheck,
  countdown,
  active,
  completed;

  String get label {
    switch (this) {
      case TeamHikePhase.inviting:
        return 'Inviting';
      case TeamHikePhase.readyCheck:
        return 'Ready Check';
      case TeamHikePhase.countdown:
        return 'Starting';
      case TeamHikePhase.active:
        return 'Active';
      case TeamHikePhase.completed:
        return 'Completed';
    }
  }
}

enum TeamHikeParticipantStatus {
  invited,
  joined,
  ready,
  active,
  offline;

  String get label {
    switch (this) {
      case TeamHikeParticipantStatus.invited:
        return 'Invited';
      case TeamHikeParticipantStatus.joined:
        return 'Joined';
      case TeamHikeParticipantStatus.ready:
        return 'Ready';
      case TeamHikeParticipantStatus.active:
        return 'Tracking';
      case TeamHikeParticipantStatus.offline:
        return 'Offline';
    }
  }

  bool get isReadyForStart {
    return this == TeamHikeParticipantStatus.ready ||
        this == TeamHikeParticipantStatus.active;
  }
}

class TeamHikeParticipant {
  const TeamHikeParticipant({
    required this.buddy,
    required this.status,
    this.isHost = false,
    this.isLeader = false,
    this.progressMeters = 0,
    this.latestLocation,
    this.invitedAt,
    this.joinedAt,
    this.readyAt,
    this.lastPingAt,
    this.lastOkAt,
    this.updatedAt,
  });

  factory TeamHikeParticipant.fromFirestore(Map<String, dynamic> data) {
    final buddyData = data['buddy'] is Map
        ? Map<String, dynamic>.from(data['buddy'] as Map)
        : data;
    final locationData = data['latestLocation'] is Map
        ? Map<String, dynamic>.from(data['latestLocation'] as Map)
        : null;
    return TeamHikeParticipant(
      buddy: TeamHikeBuddy.fromFirestore(buddyData),
      status: _teamHikeParticipantStatusFromName(
        _modelStringFrom(data['status']),
      ),
      isHost: data['isHost'] == true,
      isLeader: data['isLeader'] == true,
      progressMeters: _modelDoubleFrom(data['progressMeters']),
      latestLocation: locationData == null
          ? null
          : HikeCoordinate.fromFirestore(locationData),
      invitedAt: _modelDateFromValue(data['invitedAtLocal']),
      joinedAt: _modelDateFromValue(data['joinedAtLocal']),
      readyAt: _modelDateFromValue(data['readyAtLocal']),
      lastPingAt: _modelDateFromValue(data['lastPingAtLocal']),
      lastOkAt: _modelDateFromValue(data['lastOkAtLocal']),
      updatedAt: _modelDateFromValue(data['updatedAtLocal']),
    );
  }

  final TeamHikeBuddy buddy;
  final TeamHikeParticipantStatus status;
  final bool isHost;
  final bool isLeader;
  final double progressMeters;
  final HikeCoordinate? latestLocation;
  final DateTime? invitedAt;
  final DateTime? joinedAt;
  final DateTime? readyAt;
  final DateTime? lastPingAt;
  final DateTime? lastOkAt;
  final DateTime? updatedAt;

  String get phoneNumber => buddy.phoneNumber;

  bool get canBePinged =>
      status == TeamHikeParticipantStatus.joined ||
      status == TeamHikeParticipantStatus.ready ||
      status == TeamHikeParticipantStatus.active;

  String get responseLabel {
    final okAt = lastOkAt;
    if (okAt != null) {
      return 'OK ${_compactElapsed(DateTime.now().difference(okAt))} ago';
    }
    final pingAt = lastPingAt;
    if (pingAt != null) {
      return 'Ping sent';
    }
    return status.label;
  }

  TeamHikeParticipant copyWith({
    TeamHikeBuddy? buddy,
    TeamHikeParticipantStatus? status,
    bool? isHost,
    bool? isLeader,
    double? progressMeters,
    HikeCoordinate? latestLocation,
    DateTime? invitedAt,
    DateTime? joinedAt,
    DateTime? readyAt,
    DateTime? lastPingAt,
    DateTime? lastOkAt,
    DateTime? updatedAt,
  }) {
    return TeamHikeParticipant(
      buddy: buddy ?? this.buddy,
      status: status ?? this.status,
      isHost: isHost ?? this.isHost,
      isLeader: isLeader ?? this.isLeader,
      progressMeters: progressMeters ?? this.progressMeters,
      latestLocation: latestLocation ?? this.latestLocation,
      invitedAt: invitedAt ?? this.invitedAt,
      joinedAt: joinedAt ?? this.joinedAt,
      readyAt: readyAt ?? this.readyAt,
      lastPingAt: lastPingAt ?? this.lastPingAt,
      lastOkAt: lastOkAt ?? this.lastOkAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'buddy': buddy.toFirestore(),
      'phoneNumber': phoneNumber,
      'status': status.name,
      'isHost': isHost,
      'isLeader': isLeader,
      'progressMeters': progressMeters,
      if (latestLocation != null)
        'latestLocation': latestLocation!.toFirestore(),
      if (invitedAt != null)
        'invitedAtLocal': invitedAt!.toUtc().toIso8601String(),
      if (joinedAt != null)
        'joinedAtLocal': joinedAt!.toUtc().toIso8601String(),
      if (readyAt != null) 'readyAtLocal': readyAt!.toUtc().toIso8601String(),
      if (lastPingAt != null)
        'lastPingAtLocal': lastPingAt!.toUtc().toIso8601String(),
      if (lastOkAt != null)
        'lastOkAtLocal': lastOkAt!.toUtc().toIso8601String(),
      if (updatedAt != null)
        'updatedAtLocal': updatedAt!.toUtc().toIso8601String(),
    };
  }
}

class TeamHikeSession {
  const TeamHikeSession({
    required this.id,
    required this.hostPhoneNumber,
    required this.trailId,
    required this.trailName,
    required this.phase,
    required this.participants,
    this.activeHikeSessionId = '',
    this.countdownSeconds = 5,
    this.createdAt,
    this.countdownStartedAt,
    this.startedAt,
    this.updatedAt,
  });

  factory TeamHikeSession.fromFirestore(
    Map<String, dynamic> data, {
    String id = '',
  }) {
    return TeamHikeSession(
      id: id.isEmpty ? _modelStringFrom(data['teamHikeSessionId']) : id,
      activeHikeSessionId: _modelStringFrom(data['activeHikeSessionId']),
      hostPhoneNumber: _modelStringFrom(data['hostPhoneNumber']),
      trailId: _modelStringFrom(data['trailId']),
      trailName: _modelStringFrom(data['trailName']),
      phase: _teamHikePhaseFromName(_modelStringFrom(data['phase'])),
      countdownSeconds: _modelIntFrom(data['countdownSeconds'], fallback: 5),
      createdAt: _modelDateFromValue(data['createdAtLocal']),
      countdownStartedAt: _modelDateFromValue(data['countdownStartedAtLocal']),
      startedAt: _modelDateFromValue(data['startedAtLocal']),
      updatedAt: _modelDateFromValue(data['updatedAtLocal']),
      participants: _modelListOfMaps(
        data['participants'],
      ).map(TeamHikeParticipant.fromFirestore).toList(),
    );
  }

  final String id;
  final String activeHikeSessionId;
  final String hostPhoneNumber;
  final String trailId;
  final String trailName;
  final TeamHikePhase phase;
  final int countdownSeconds;
  final DateTime? createdAt;
  final DateTime? countdownStartedAt;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final List<TeamHikeParticipant> participants;

  int get readyCount => participants
      .where((participant) => participant.status.isReadyForStart)
      .length;

  int get invitedCount => participants
      .where(
        (participant) =>
            participant.status == TeamHikeParticipantStatus.invited,
      )
      .length;

  bool get everyoneReady =>
      participants.isNotEmpty &&
      participants.every((participant) => participant.status.isReadyForStart);

  TeamHikeParticipant? get leader {
    final leaders = participants.where((participant) => participant.isLeader);
    if (leaders.isNotEmpty) {
      return leaders.first;
    }
    if (participants.isEmpty) {
      return null;
    }
    return [
      ...participants,
    ].reduce((a, b) => a.progressMeters >= b.progressMeters ? a : b);
  }

  int get countdownRemainingSeconds {
    final start = countdownStartedAt;
    if (phase != TeamHikePhase.countdown || start == null) {
      return countdownSeconds;
    }
    final elapsed = DateTime.now().difference(start).inSeconds;
    return math.max(0, countdownSeconds - elapsed);
  }

  TeamHikeSession copyWith({
    String? id,
    String? activeHikeSessionId,
    String? hostPhoneNumber,
    String? trailId,
    String? trailName,
    TeamHikePhase? phase,
    int? countdownSeconds,
    DateTime? createdAt,
    DateTime? countdownStartedAt,
    DateTime? startedAt,
    DateTime? updatedAt,
    List<TeamHikeParticipant>? participants,
  }) {
    return TeamHikeSession(
      id: id ?? this.id,
      activeHikeSessionId: activeHikeSessionId ?? this.activeHikeSessionId,
      hostPhoneNumber: hostPhoneNumber ?? this.hostPhoneNumber,
      trailId: trailId ?? this.trailId,
      trailName: trailName ?? this.trailName,
      phase: phase ?? this.phase,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      createdAt: createdAt ?? this.createdAt,
      countdownStartedAt: countdownStartedAt ?? this.countdownStartedAt,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participants: participants ?? this.participants,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teamHikeSessionId': id,
      'activeHikeSessionId': activeHikeSessionId,
      'hostPhoneNumber': hostPhoneNumber,
      'trailId': trailId,
      'trailName': trailName,
      'phase': phase.name,
      'countdownSeconds': countdownSeconds,
      'participants': participants
          .map((participant) => participant.toFirestore())
          .toList(),
      if (createdAt != null)
        'createdAtLocal': createdAt!.toUtc().toIso8601String(),
      if (countdownStartedAt != null)
        'countdownStartedAtLocal': countdownStartedAt!
            .toUtc()
            .toIso8601String(),
      if (startedAt != null)
        'startedAtLocal': startedAt!.toUtc().toIso8601String(),
      if (updatedAt != null)
        'updatedAtLocal': updatedAt!.toUtc().toIso8601String(),
    };
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
    this.teamBuddies = const [],
  });

  factory HikeSessionDraft.fromTrail(Trail trail) {
    final now = DateTime.now();
    final departure = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final expectedArrival = departure.add(
      Duration(minutes: trail.estimatedDurationMinutes),
    );
    return HikeSessionDraft(
      hikeType: HikeType.solo,
      trail: trail,
      startPointName: trail.checkpoints.first.name,
      destinationName: trail.checkpoints.last.name,
      departureTime: departure,
      expectedArrivalTime: expectedArrival,
      expectedReturnTime: expectedArrival.add(const Duration(hours: 2)),
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
  final List<TeamHikeBuddy> teamBuddies;

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
    List<TeamHikeBuddy>? teamBuddies,
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
      teamBuddies: teamBuddies ?? this.teamBuddies,
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
    String? teamHikeSessionId = '',
    this.teamHikeSession,
  }) : _teamHikeSessionId = teamHikeSessionId;

  factory ActiveHikeSession.fromDraft(
    HikeSessionDraft draft, {
    String teamHikeSessionId = '',
    TeamHikeSession? teamHikeSession,
  }) {
    return ActiveHikeSession(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      draft: draft,
      startedAt: DateTime.now(),
      batteryLevel: 67,
      queuedUpdates: 3,
      manualPins: 0,
      checkIns: 0,
      batteryStartedLevel: 67,
      teamHikeSessionId: teamHikeSessionId,
      teamHikeSession: teamHikeSession,
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
  final String? _teamHikeSessionId;
  final TeamHikeSession? teamHikeSession;

  String get teamHikeSessionId => _teamHikeSessionId ?? '';
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
    String? teamHikeSessionId,
    TeamHikeSession? teamHikeSession,
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
      teamHikeSessionId: teamHikeSessionId ?? this.teamHikeSessionId,
      teamHikeSession: teamHikeSession ?? this.teamHikeSession,
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

TeamHikePhase _teamHikePhaseFromName(String value) {
  return TeamHikePhase.values.firstWhere(
    (phase) => phase.name == value,
    orElse: () => TeamHikePhase.inviting,
  );
}

TeamHikeParticipantStatus _teamHikeParticipantStatusFromName(String value) {
  return TeamHikeParticipantStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => TeamHikeParticipantStatus.invited,
  );
}

String _compactElapsed(Duration elapsed) {
  if (elapsed.inSeconds < 60) {
    return '${math.max(1, elapsed.inSeconds)}s';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes}m';
  }
  return '${elapsed.inHours}h';
}

String _modelStringFrom(Object? value) {
  return value is String ? value : '';
}

double _modelDoubleFrom(Object? value) {
  return value is num ? value.toDouble() : 0;
}

int _modelIntFrom(Object? value, {int fallback = 0}) {
  return value is num ? value.toInt() : fallback;
}

DateTime? _modelDateFromValue(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<Map<String, dynamic>> _modelListOfMaps(Object? value) {
  if (value is! Iterable) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
