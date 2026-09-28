import 'route_gear_assessment.dart';
import 'hike_shirt_color.dart';
import 'trail_gear_plan.dart';
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
    this.fallResponseDuration = const Duration(seconds: 30),
    this.longestRestDuration = const Duration(minutes: 3),
  });

  static const double minSensorSensitivity = 1;
  static const double maxSensorSensitivity = 10;
  static const double gravityMetersPerSecondSquared = 9.80665;
  static const Duration impactWindowDuration = Duration(milliseconds: 500);
  static const Duration postImpactBounceDuration = Duration(seconds: 2);
  static const Duration stillnessVerificationDuration = Duration(seconds: 10);
  static const Duration backpackTrapStillnessDuration = Duration(seconds: 20);

  final double sensorSensitivity;
  final Duration fallResponseDuration;
  final Duration longestRestDuration;

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
    if (fallResponseDuration.inSeconds < 60) {
      return '${fallResponseDuration.inSeconds} sec';
    }
    return '${fallResponseDuration.inMinutes} min';
  }

  String get longestRestDurationLabel {
    if (longestRestDuration.inMinutes < 60) {
      return '${longestRestDuration.inMinutes} min';
    }
    final hours = longestRestDuration.inHours;
    return '$hours hr${hours == 1 ? '' : 's'}';
  }

  bool get isHighSensitivity => sensorSensitivity > 7;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FallDetectionSettings &&
            other.sensorSensitivity == sensorSensitivity &&
            other.fallResponseDuration == fallResponseDuration &&
            other.longestRestDuration == longestRestDuration;
  }

  @override
  int get hashCode =>
      Object.hash(sensorSensitivity, fallResponseDuration, longestRestDuration);

  static double _lerp(double start, double end, double amount) {
    return start + (end - start) * amount;
  }
}

class GearChecklistCatalog {
  const GearChecklistCatalog._();

  static const Map<String, List<String>> sections = {
    'Safety Essentials': [
      'Charged phone',
      'Power bank',
      'Torch',
      'First-aid kit',
      'Emergency whistle',
      'Multi-tool',
    ],
    'Navigation & Communication': [
      'GPS device or app',
      'Physical map',
      'Compass',
      'Fully charged phone',
      'Emergency contacts saved',
    ],
    'Water and Food': [
      'Drinking water',
      'Water filter or tablets',
      'Energy snack',
      'Extra food for delays',
    ],
    'Weather & Clothing': [
      'Raincoat',
      'Extra clothing layer',
      'Sun protection (hat, sunscreen)',
      'Warm hat and gloves',
    ],
    'Emergency & Recovery': [
      'Headlamp with spare batteries',
      'Fire starter or matches',
      'Emergency blanket',
      'Whistle',
      'Signal mirror',
    ],
  };

  static final Set<String> allItems = Set<String>.unmodifiable({
    ...sections.values.expand((items) => items),
    ...TrailGearPlan.allItems,
  });

  static int get itemCount => allItems.length;

  static Set<String> sanitize(Iterable<String> items) {
    return Set<String>.unmodifiable(
      items.where(
        (item) =>
            allItems.contains(item) ||
            TrailGearPlan.isPreference(item) ||
            HikeShirtColor.isPreference(item),
      ),
    );
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
    this.locationRecordingInterval =
        HikeSessionDraft.defaultLocationRecordingInterval,
    this.upcomingHikeId = '',
    this.hasKnownBatteryLevel = true,
    this.completedChecklistItems = const {},
    this.gearAssessment,
  });

  final RouteGearAssessment? gearAssessment;
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
  final Duration locationRecordingInterval;
  final String upcomingHikeId;
  final bool hasKnownBatteryLevel;
  final Set<String> completedChecklistItems;

  TrailGearPlan get gearPlan => TrailGearPlan.forTrail(
    trail,
    plannedStartTime,
    expectedReturnTime,
    saved: completedChecklistItems,
    assessment: gearAssessment,
  );
  Set<String> get missingRequiredGear =>
      gearPlan.missingRequired(completedChecklistItems);
  bool get requiredGearReady => missingRequiredGear.isEmpty;

  HikeSessionDraft applyToDraft(HikeSessionDraft draft) => draft.copyWith(
    completedChecklistItems: completedChecklistItems,
    trail: draft.trail.copyWith(weather: trail.weather),
    shareLiveLocation: liveLocationConfigured,
    locationRecordingInterval: locationRecordingInterval,
  );

  PlannedHike withGearProgress() => copyWith(
    checklistCompleted: gearPlan.completed(completedChecklistItems),
    checklistTotal: gearPlan.items.length,
  );

  int get preparationPercent {
    if (checklistTotal == 0) {
      return 0;
    }
    return ((checklistCompleted / checklistTotal) * 100).round();
  }

  List<String> get missingPreparationItems {
    return [
      if (!weatherCached) 'Weather forecast not cached',
      if (!emergencyContactsSelected) 'No emergency contact selected',
      if (!hasKnownBatteryLevel)
        'Phone battery level unavailable'
      else if (phoneBatteryLevel < 60)
        'Phone battery below recommended level',
      if (checklistCompleted < checklistTotal) 'Gear checklist incomplete',
      if (!liveLocationConfigured) 'Live location sharing not configured',
    ];
  }

  PlannedHike copyWith({
    RouteGearAssessment? gearAssessment,
    Trail? trail,
    DateTime? plannedStartTime,
    DateTime? expectedReturnTime,
    bool? weatherCached,
    bool? offlineMapDownloaded,
    bool? emergencyContactsSelected,
    int? checklistCompleted,
    int? checklistTotal,
    int? phoneBatteryLevel,
    bool? liveLocationConfigured,
    Duration? locationRecordingInterval,
    String? upcomingHikeId,
    bool? hasKnownBatteryLevel,
    Set<String>? completedChecklistItems,
  }) {
    return PlannedHike(
      gearAssessment: gearAssessment ?? this.gearAssessment,
      trail: trail ?? this.trail,
      plannedStartTime: plannedStartTime ?? this.plannedStartTime,
      expectedReturnTime: expectedReturnTime ?? this.expectedReturnTime,
      weatherCached: weatherCached ?? this.weatherCached,
      offlineMapDownloaded: offlineMapDownloaded ?? this.offlineMapDownloaded,
      emergencyContactsSelected:
          emergencyContactsSelected ?? this.emergencyContactsSelected,
      checklistCompleted: checklistCompleted ?? this.checklistCompleted,
      checklistTotal: checklistTotal ?? this.checklistTotal,
      phoneBatteryLevel: phoneBatteryLevel ?? this.phoneBatteryLevel,
      liveLocationConfigured:
          liveLocationConfigured ?? this.liveLocationConfigured,
      locationRecordingInterval:
          locationRecordingInterval ?? this.locationRecordingInterval,
      upcomingHikeId: upcomingHikeId ?? this.upcomingHikeId,
      hasKnownBatteryLevel: hasKnownBatteryLevel ?? this.hasKnownBatteryLevel,
      completedChecklistItems:
          completedChecklistItems ?? this.completedChecklistItems,
    );
  }
}

class TeamHikeBuddy {
  const TeamHikeBuddy({
    required this.name,
    required this.handle,
    required this.phoneNumber,
    this.role = 'Teammate',
    this.photoURL = '',
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
      photoURL: _modelStringFrom(data['photoURL']),
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
  final String photoURL;
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

  TeamHikeBuddy copyWith({
    String? name,
    String? handle,
    String? phoneNumber,
    String? role,
    String? photoURL,
    int? avatarColorValue,
  }) {
    return TeamHikeBuddy(
      name: name ?? this.name,
      handle: handle ?? this.handle,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      photoURL: photoURL ?? this.photoURL,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'handle': handle,
      'phoneNumber': phoneNumber,
      'role': role,
      if (photoURL.trim().isNotEmpty) 'photoURL': photoURL.trim(),
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
  offline,
  ended;

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
      case TeamHikeParticipantStatus.ended:
        return 'Ended';
    }
  }

  bool get isReadyForStart {
    return this == TeamHikeParticipantStatus.ready ||
        this == TeamHikeParticipantStatus.active;
  }
}

class TeamHikeParticipant {
  static const Duration locationFreshnessLimit = Duration(minutes: 2);

  const TeamHikeParticipant({
    required this.buddy,
    required this.status,
    this.isHost = false,
    this.isLeader = false,
    this.progressMeters = 0,
    this.latestLocation,
    this.locationUpdatedAt,
    this.invitedAt,
    this.joinedAt,
    this.readyAt,
    this.lastPingAt,
    this.lastOkAt,
    this.updatedAt,
    this.safetySettings = const {},
    this.isolatedSince,
    this.separationAlertActive = false,
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
          : HikeCoordinate.tryFromFirestore(locationData),
      locationUpdatedAt: _modelDateFromValue(data['locationUpdatedAtLocal']),
      invitedAt: _modelDateFromValue(data['invitedAtLocal']),
      joinedAt: _modelDateFromValue(data['joinedAtLocal']),
      readyAt: _modelDateFromValue(data['readyAtLocal']),
      lastPingAt: _modelDateFromValue(data['lastPingAtLocal']),
      lastOkAt: _modelDateFromValue(data['lastOkAtLocal']),
      updatedAt: _modelDateFromValue(data['updatedAtLocal']),
      safetySettings: _modelMapFrom(data['safetySettings']),
      isolatedSince: _modelDateFromValue(data['isolatedSinceLocal']),
      separationAlertActive: data['separationAlertActive'] == true,
    );
  }

  final TeamHikeBuddy buddy;
  final TeamHikeParticipantStatus status;
  final bool isHost;
  final bool isLeader;
  final double progressMeters;
  final HikeCoordinate? latestLocation;
  final DateTime? locationUpdatedAt;
  final DateTime? invitedAt;
  final DateTime? joinedAt;
  final DateTime? readyAt;
  final DateTime? lastPingAt;
  final DateTime? lastOkAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> safetySettings;
  final DateTime? isolatedSince;
  final bool separationAlertActive;

  String get phoneNumber => buddy.phoneNumber;

  bool get canBePinged =>
      status == TeamHikeParticipantStatus.joined ||
      status == TeamHikeParticipantStatus.ready ||
      status == TeamHikeParticipantStatus.active;

  DateTime? get effectiveLocationUpdatedAt =>
      locationUpdatedAt ?? latestLocation?.capturedAt;

  bool hasFreshLocationAt(
    DateTime now, {
    Duration maxAge = locationFreshnessLimit,
  }) {
    final location = latestLocation;
    final timestamp = effectiveLocationUpdatedAt;
    if (location?.hasValidPosition != true || timestamp == null) {
      return false;
    }
    final age = now.toUtc().difference(timestamp.toUtc());
    return age >= const Duration(minutes: -1) && age <= maxAge;
  }

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
    DateTime? locationUpdatedAt,
    DateTime? invitedAt,
    DateTime? joinedAt,
    DateTime? readyAt,
    DateTime? lastPingAt,
    DateTime? lastOkAt,
    DateTime? updatedAt,
    Map<String, dynamic>? safetySettings,
    DateTime? isolatedSince,
    bool? separationAlertActive,
    bool clearIsolatedSince = false,
  }) {
    return TeamHikeParticipant(
      buddy: buddy ?? this.buddy,
      status: status ?? this.status,
      isHost: isHost ?? this.isHost,
      isLeader: isLeader ?? this.isLeader,
      progressMeters: progressMeters ?? this.progressMeters,
      latestLocation: latestLocation ?? this.latestLocation,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      invitedAt: invitedAt ?? this.invitedAt,
      joinedAt: joinedAt ?? this.joinedAt,
      readyAt: readyAt ?? this.readyAt,
      lastPingAt: lastPingAt ?? this.lastPingAt,
      lastOkAt: lastOkAt ?? this.lastOkAt,
      updatedAt: updatedAt ?? this.updatedAt,
      safetySettings: safetySettings ?? this.safetySettings,
      isolatedSince: clearIsolatedSince
          ? null
          : isolatedSince ?? this.isolatedSince,
      separationAlertActive:
          separationAlertActive ?? this.separationAlertActive,
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
      if (latestLocation?.hasValidPosition == true)
        'latestLocation': latestLocation!.toFirestore(),
      if (locationUpdatedAt != null)
        'locationUpdatedAtLocal': locationUpdatedAt!.toUtc().toIso8601String(),
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
      if (safetySettings.isNotEmpty) 'safetySettings': safetySettings,
      if (isolatedSince != null)
        'isolatedSinceLocal': isolatedSince!.toUtc().toIso8601String(),
      'separationAlertActive': separationAlertActive,
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
    this.sourceUpcomingHikeId = '',
    this.activeHikeSessionId = '',
    this.countdownSeconds = 5,
    this.createdAt,
    this.readinessStartedAt,
    this.countdownStartedAt,
    this.startedAt,
    this.updatedAt,
    this.sharedDraft,
  });

  factory TeamHikeSession.fromFirestore(
    Map<String, dynamic> data, {
    String id = '',
  }) {
    return TeamHikeSession(
      id: id.isEmpty ? _modelStringFrom(data['teamHikeSessionId']) : id,
      sourceUpcomingHikeId: _modelStringFrom(data['sourceUpcomingHikeId']),
      activeHikeSessionId: _modelStringFrom(data['activeHikeSessionId']),
      hostPhoneNumber: _modelStringFrom(data['hostPhoneNumber']),
      trailId: _modelStringFrom(data['trailId']),
      trailName: _modelStringFrom(data['trailName']),
      phase: _teamHikePhaseFromName(_modelStringFrom(data['phase'])),
      countdownSeconds: _modelIntFrom(data['countdownSeconds'], fallback: 5),
      createdAt: _modelDateFromValue(data['createdAtLocal']),
      readinessStartedAt: _modelDateFromValue(
        data['readinessStartedAtLocal'] ?? data['readinessStartedAt'],
      ),
      countdownStartedAt: _modelDateFromValue(data['countdownStartedAtLocal']),
      startedAt: _modelDateFromValue(data['startedAtLocal']),
      updatedAt: _modelDateFromValue(data['updatedAtLocal']),
      sharedDraft: data['draft'] is Map
          ? HikeSessionDraft.fromPersistence(_modelMapFrom(data['draft']))
          : null,
      participants: _modelListOfMaps(
        data['participants'],
      ).map(TeamHikeParticipant.fromFirestore).toList(),
    );
  }

  final String id;
  final String sourceUpcomingHikeId;
  final String activeHikeSessionId;
  final String hostPhoneNumber;
  final String trailId;
  final String trailName;
  final TeamHikePhase phase;
  final int countdownSeconds;
  final DateTime? createdAt;
  final DateTime? readinessStartedAt;
  final DateTime? countdownStartedAt;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final List<TeamHikeParticipant> participants;
  final HikeSessionDraft? sharedDraft;

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
    String? sourceUpcomingHikeId,
    String? activeHikeSessionId,
    String? hostPhoneNumber,
    String? trailId,
    String? trailName,
    TeamHikePhase? phase,
    int? countdownSeconds,
    DateTime? createdAt,
    DateTime? readinessStartedAt,
    DateTime? countdownStartedAt,
    DateTime? startedAt,
    DateTime? updatedAt,
    List<TeamHikeParticipant>? participants,
    HikeSessionDraft? sharedDraft,
  }) {
    return TeamHikeSession(
      id: id ?? this.id,
      sourceUpcomingHikeId: sourceUpcomingHikeId ?? this.sourceUpcomingHikeId,
      activeHikeSessionId: activeHikeSessionId ?? this.activeHikeSessionId,
      hostPhoneNumber: hostPhoneNumber ?? this.hostPhoneNumber,
      trailId: trailId ?? this.trailId,
      trailName: trailName ?? this.trailName,
      phase: phase ?? this.phase,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      createdAt: createdAt ?? this.createdAt,
      readinessStartedAt: readinessStartedAt ?? this.readinessStartedAt,
      countdownStartedAt: countdownStartedAt ?? this.countdownStartedAt,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participants: participants ?? this.participants,
      sharedDraft: sharedDraft ?? this.sharedDraft,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teamHikeSessionId': id,
      if (sourceUpcomingHikeId.trim().isNotEmpty)
        'sourceUpcomingHikeId': sourceUpcomingHikeId.trim(),
      'activeHikeSessionId': activeHikeSessionId,
      'hostPhoneNumber': hostPhoneNumber,
      'trailId': trailId,
      'trailName': trailName,
      'phase': phase.name,
      'countdownSeconds': countdownSeconds,
      'participants': participants
          .map((participant) => participant.toFirestore())
          .toList(),
      if (sharedDraft != null) 'draft': sharedDraft!.toPersistence(),
      if (createdAt != null)
        'createdAtLocal': createdAt!.toUtc().toIso8601String(),
      if (readinessStartedAt != null)
        'readinessStartedAtLocal': readinessStartedAt!
            .toUtc()
            .toIso8601String(),
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
    this.customCheckpoints,
    this.soloDistanceAcknowledgedKm,
  });

  static const defaultLocationRecordingInterval = Duration(seconds: 30);
  static const minLocationRecordingInterval = Duration(seconds: 5);
  static const maxLocationRecordingInterval = Duration(minutes: 1);

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
      Duration(minutes: math.max(0, trail.estimatedDurationMinutes)),
    );
    final checkpoints =
        trail.checkpoints
            .where((checkpoint) => checkpoint.hasValidCoordinate)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final fallbackName = trail.name.trim().isEmpty
        ? 'Trail'
        : trail.name.trim();
    return HikeSessionDraft(
      hikeType: HikeType.solo,
      trail: trail,
      startPointName: checkpoints.isEmpty
          ? fallbackName
          : _checkpointDisplayName(checkpoints.first, fallbackName),
      destinationName: checkpoints.isEmpty
          ? fallbackName
          : _checkpointDisplayName(checkpoints.last, fallbackName),
      departureTime: departure,
      expectedArrivalTime: expectedArrival,
      expectedReturnTime: expectedArrival.add(const Duration(hours: 2)),
      safetyCheckInInterval: const Duration(minutes: 30),
      locationRecordingInterval: defaultLocationRecordingInterval,
      emergencyContactNames: const [],
      shareLiveLocation: false,
      fallDetectionEnabled: true,
      fallDetectionSettings: const FallDetectionSettings(
        sensorSensitivity: 5,
        fallResponseDuration: Duration(seconds: 30),
        longestRestDuration: Duration(minutes: 3),
      ),
      pathDeviationEnabled: true,
      offlinePhysicalAlertEnabled: true,
      duressEnabled: true,
      completedChecklistItems: const {},
    );
  }

  factory HikeSessionDraft.fromPersistence(Map<String, dynamic> data) {
    final now = DateTime.now();
    final fallDetectionPreferenceVersion = _modelIntFrom(
      data['fallDetectionPreferenceVersion'],
      fallback: 0,
    );
    final customCheckpointsValue = data['customCheckpoints'];
    final trail = Trail.fromPersistence(_modelMapFrom(data['trail']));
    final parsedCustomCheckpoints = customCheckpointsValue is Iterable
        ? (_modelListOfMaps(customCheckpointsValue)
              .where(_modelCheckpointMapHasValidCoordinate)
              .map(TrailCheckpoint.fromPersistence)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order)))
        : null;
    final customCheckpoints = parsedCustomCheckpoints?.isNotEmpty == true
        ? parsedCustomCheckpoints
        : null;
    final effectiveCheckpoints = [...(customCheckpoints ?? trail.checkpoints)]
      ..sort((a, b) => a.order.compareTo(b.order));
    final fallbackName = trail.name.trim().isEmpty
        ? 'Trail'
        : trail.name.trim();
    final savedStartName = _modelStringFrom(data['startPointName']).trim();
    final savedDestinationName = _modelStringFrom(
      data['destinationName'],
    ).trim();
    return HikeSessionDraft(
      hikeType: HikeType.values.firstWhere(
        (type) => type.name == _modelStringFrom(data['hikeType']),
        orElse: () => HikeType.solo,
      ),
      trail: trail,
      startPointName: savedStartName.isNotEmpty
          ? savedStartName
          : effectiveCheckpoints.isEmpty
          ? fallbackName
          : _checkpointDisplayName(effectiveCheckpoints.first, fallbackName),
      destinationName: savedDestinationName.isNotEmpty
          ? savedDestinationName
          : effectiveCheckpoints.isEmpty
          ? fallbackName
          : _checkpointDisplayName(effectiveCheckpoints.last, fallbackName),
      departureTime: _modelLocalDateFromValue(data['departureTime']) ?? now,
      expectedArrivalTime:
          _modelLocalDateFromValue(data['expectedArrivalTime']) ?? now,
      expectedReturnTime:
          _modelLocalDateFromValue(data['expectedReturnTime']) ?? now,
      safetyCheckInInterval: Duration(
        seconds: _positiveModelIntFrom(
          data['safetyCheckInIntervalSeconds'],
          fallback: 1800,
        ),
      ),
      locationRecordingInterval: Duration(
        seconds:
            _positiveModelIntFrom(
              data['locationRecordingIntervalSeconds'],
              fallback: defaultLocationRecordingInterval.inSeconds,
            ).clamp(
              minLocationRecordingInterval.inSeconds,
              maxLocationRecordingInterval.inSeconds,
            ),
      ),
      emergencyContactNames: _modelStringList(data['emergencyContactNames']),
      shareLiveLocation: data['shareLiveLocation'] == true,
      // Older builds converted a missing flag to false and could then persist
      // that accidental opt-out. Only a versioned preference is trustworthy;
      // every legacy draft gets the safety-on default once during migration.
      fallDetectionEnabled: fallDetectionPreferenceVersion >= 1
          ? data['fallDetectionEnabled'] is bool
                ? data['fallDetectionEnabled'] as bool
                : true
          : true,
      fallDetectionSettings: FallDetectionSettings(
        sensorSensitivity:
            _modelDoubleFrom(
              _modelMapFrom(data['fallDetectionSettings'])['sensorSensitivity'],
              fallback: 5,
            ).clamp(
              FallDetectionSettings.minSensorSensitivity,
              FallDetectionSettings.maxSensorSensitivity,
            ),
        fallResponseDuration: Duration(
          seconds: _positiveModelIntFrom(
            _modelMapFrom(
                  data['fallDetectionSettings'],
                )['fallResponseDurationSeconds'] ??
                _modelMapFrom(
                  data['fallDetectionSettings'],
                )['stillnessDurationSeconds'],
            fallback: 30,
          ),
        ),
        longestRestDuration: Duration(
          seconds: _positiveModelIntFrom(
            _modelMapFrom(
              data['fallDetectionSettings'],
            )['longestRestDurationSeconds'],
            fallback: 180,
          ),
        ),
      ),
      pathDeviationEnabled: data['pathDeviationEnabled'] == true,
      offlinePhysicalAlertEnabled: data['offlinePhysicalAlertEnabled'] == true,
      duressEnabled: data['duressEnabled'] == true,
      completedChecklistItems: _modelStringList(
        data['completedChecklistItems'],
      ).toSet(),
      teamBuddies: _modelListOfMaps(
        data['teamBuddies'],
      ).map(TeamHikeBuddy.fromFirestore).toList(),
      customCheckpoints: customCheckpoints,
      soloDistanceAcknowledgedKm: (data['soloDistanceAcknowledgedKm'] as num?)
          ?.toDouble(),
    );
  }

  final double? soloDistanceAcknowledgedKm;
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
  final List<TrailCheckpoint>? customCheckpoints;

  Map<String, dynamic> toPersistence() {
    return {
      'hikeType': hikeType.name,
      if (soloDistanceAcknowledgedKm != null)
        'soloDistanceAcknowledgedKm': soloDistanceAcknowledgedKm,
      'trail': trail.toPersistence(),
      'startPointName': startPointName,
      'destinationName': destinationName,
      'departureTime': departureTime.toUtc().toIso8601String(),
      'expectedArrivalTime': expectedArrivalTime.toUtc().toIso8601String(),
      'expectedReturnTime': expectedReturnTime.toUtc().toIso8601String(),
      'safetyCheckInIntervalSeconds': safetyCheckInInterval.inSeconds,
      'locationRecordingIntervalSeconds': locationRecordingInterval.inSeconds,
      'emergencyContactNames': emergencyContactNames,
      'shareLiveLocation': shareLiveLocation,
      'fallDetectionEnabled': fallDetectionEnabled,
      'fallDetectionPreferenceVersion': 1,
      'fallDetectionSettings': {
        'sensorSensitivity': fallDetectionSettings.sensorSensitivity,
        'fallResponseDurationSeconds':
            fallDetectionSettings.fallResponseDuration.inSeconds,
        'longestRestDurationSeconds':
            fallDetectionSettings.longestRestDuration.inSeconds,
        // Keep the legacy key so older app builds can still restore the
        // post-fall response duration.
        'stillnessDurationSeconds':
            fallDetectionSettings.fallResponseDuration.inSeconds,
      },
      'pathDeviationEnabled': pathDeviationEnabled,
      'offlinePhysicalAlertEnabled': offlinePhysicalAlertEnabled,
      'duressEnabled': duressEnabled,
      'completedChecklistItems': completedChecklistItems.toList(),
      'teamBuddies': teamBuddies.map((buddy) => buddy.toFirestore()).toList(),
      if (customCheckpoints != null)
        'customCheckpoints': customCheckpoints!
            .where((checkpoint) => checkpoint.hasValidCoordinate)
            .map((checkpoint) => checkpoint.toFirestore())
            .toList(),
    };
  }

  List<TrailCheckpoint> get effectiveCheckpoints =>
      (customCheckpoints ?? trail.checkpoints)
          .where((checkpoint) => checkpoint.hasValidCoordinate)
          .toList();

  List<TrailCheckpoint> _sortedCheckpoints(List<TrailCheckpoint>? cps) {
    final list = [
      ...(cps ?? trail.checkpoints).where(
        (checkpoint) => checkpoint.hasValidCoordinate,
      ),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  List<TrailCheckpoint> get sortedCheckpoints =>
      _sortedCheckpoints(customCheckpoints);

  HikeSessionDraft addCheckpoint(TrailCheckpoint cp) {
    if (!cp.hasValidCoordinate) {
      return this;
    }
    final cps = [...(customCheckpoints ?? trail.checkpoints)];
    final maxOrder = cps.fold<int>(0, (m, c) => c.order > m ? c.order : m);
    final added = cp.copyWith(order: maxOrder + 1);
    cps.add(added);
    return copyWith(
      customCheckpoints: cps,
      startPointName: cps.first.name,
      destinationName: cps.last.name,
    );
  }

  HikeSessionDraft removeCheckpointAt(int index) {
    final cps = [...(customCheckpoints ?? trail.checkpoints)]
      ..sort((a, b) => a.order.compareTo(b.order));
    if (cps.length <= 3) return this;
    if (index == 0 || index == cps.length - 1) return this;
    cps.removeAt(index);
    final reindexed = cps
        .asMap()
        .entries
        .map((e) => e.value.copyWith(order: e.key + 1))
        .toList();
    return copyWith(
      customCheckpoints: reindexed,
      startPointName: reindexed.first.name,
      destinationName: reindexed.last.name,
    );
  }

  HikeSessionDraft reorderCheckpoint(int oldIndex, int newIndex) {
    final cps = [...(customCheckpoints ?? trail.checkpoints)]
      ..sort((a, b) => a.order.compareTo(b.order));
    if (oldIndex < 0 || oldIndex >= cps.length) return this;
    if (newIndex < 0 || newIndex >= cps.length) return this;
    if (oldIndex < newIndex) newIndex--;
    final item = cps.removeAt(oldIndex);
    cps.insert(newIndex, item);
    final reindexed = cps
        .asMap()
        .entries
        .map((e) => e.value.copyWith(order: e.key + 1))
        .toList();
    return copyWith(
      customCheckpoints: reindexed,
      startPointName: reindexed.first.name,
      destinationName: reindexed.last.name,
    );
  }

  bool get hasCustomCheckpoints => customCheckpoints != null;

  HikeSessionDraft copyWith({
    double? soloDistanceAcknowledgedKm,
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
    List<TrailCheckpoint>? customCheckpoints,
  }) {
    return HikeSessionDraft(
      soloDistanceAcknowledgedKm:
          soloDistanceAcknowledgedKm ??
          ((trail == null ||
                  (trail.trailId == this.trail.trailId &&
                      trail.distanceKm == this.trail.distanceKm))
              ? this.soloDistanceAcknowledgedKm
              : null),
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
      customCheckpoints: customCheckpoints ?? this.customCheckpoints,
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
    this.checkInRecords = const [],
    String? teamHikeSessionId = '',
    this.teamHikeSession,
    this.sourceUpcomingHikeId = '',
  }) : _teamHikeSessionId = teamHikeSessionId;

  factory ActiveHikeSession.fromDraft(
    HikeSessionDraft draft, {
    String teamHikeSessionId = '',
    TeamHikeSession? teamHikeSession,
    String sourceUpcomingHikeId = '',
    int? initialBatteryLevel,
  }) {
    final normalizedBatteryLevel = initialBatteryLevel?.clamp(0, 100).toInt();
    return ActiveHikeSession(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      draft: draft,
      startedAt: DateTime.now(),
      // Zero is only an internal placeholder until the native battery reading
      // arrives. `hasKnownBatteryLevel` keeps it from being shown as real data.
      batteryLevel: normalizedBatteryLevel ?? 0,
      queuedUpdates: 0,
      manualPins: 0,
      checkIns: 0,
      batteryStartedLevel: normalizedBatteryLevel,
      teamHikeSessionId: teamHikeSessionId,
      teamHikeSession: teamHikeSession,
      sourceUpcomingHikeId: sourceUpcomingHikeId,
    );
  }

  factory ActiveHikeSession.fromPersistence(Map<String, dynamic> data) {
    final teamSessionData = _modelMapFrom(data['teamHikeSession']);
    final routePoints = _modelCoordinatesFrom(data['routePoints']);
    final latestLocation = data['latestLocation'] is Map
        ? HikeCoordinate.tryFromFirestore(_modelMapFrom(data['latestLocation']))
        : null;
    final manualPinLocations = _modelListOfMaps(
      data['manualPinLocations'],
    ).map(HikeManualPin.tryFromPersistence).nonNulls.toList();
    final checkInRecords = _modelListOfMaps(
      data['checkInRecords'],
    ).map(HikeCheckInRecord.fromPersistence).toList();
    return ActiveHikeSession(
      sessionId: _modelStringFrom(data['sessionId']),
      draft: HikeSessionDraft.fromPersistence(_modelMapFrom(data['draft'])),
      startedAt:
          _modelDateFromValue(data['startedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      batteryLevel: _modelIntFrom(data['batteryLevel']).clamp(0, 100),
      batteryStartedLevel: data['batteryStartedLevel'] is num
          ? _modelIntFrom(data['batteryStartedLevel']).clamp(0, 100)
          : null,
      queuedUpdates: math.max(0, _modelIntFrom(data['queuedUpdates'])),
      manualPins: math.max(
        manualPinLocations.length,
        _modelIntFrom(data['manualPins']),
      ),
      checkIns: math.max(
        checkInRecords.length,
        _modelIntFrom(data['checkIns']),
      ),
      latestLocation: latestLocation,
      routePoints: routePoints,
      manualPinLocations: manualPinLocations,
      checkInRecords: checkInRecords,
      teamHikeSessionId: _modelStringFrom(data['teamHikeSessionId']),
      teamHikeSession: teamSessionData.isEmpty
          ? null
          : TeamHikeSession.fromFirestore(
              teamSessionData,
              id: _modelStringFrom(teamSessionData['teamHikeSessionId']),
            ),
      sourceUpcomingHikeId: _modelStringFrom(data['sourceUpcomingHikeId']),
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
  final List<HikeCheckInRecord> checkInRecords;
  final String? _teamHikeSessionId;
  final TeamHikeSession? teamHikeSession;
  final String sourceUpcomingHikeId;

  Map<String, dynamic> toPersistence() {
    return {
      'sessionId': sessionId,
      'draft': draft.toPersistence(),
      'startedAt': startedAt.toUtc().toIso8601String(),
      'batteryLevel': batteryLevel,
      if (batteryStartedLevel != null)
        'batteryStartedLevel': batteryStartedLevel,
      'queuedUpdates': queuedUpdates,
      'manualPins': manualPins,
      'checkIns': checkIns,
      if (latestLocation?.hasValidPosition == true)
        'latestLocation': latestLocation!.toFirestore(),
      'routePoints': routePoints
          .where((coordinate) => coordinate.hasValidPosition)
          .map((coordinate) => coordinate.toFirestore())
          .toList(),
      'manualPinLocations': manualPinLocations
          .where((pin) => pin.coordinate.hasValidPosition)
          .map((pin) => pin.toFirestore())
          .toList(),
      'checkInRecords': checkInRecords
          .where(
            (record) =>
                record.coordinate == null ||
                record.coordinate!.hasValidPosition,
          )
          .map((record) => record.toPersistence())
          .toList(),
      'teamHikeSessionId': teamHikeSessionId,
      if (teamHikeSession != null)
        'teamHikeSession': teamHikeSession!.toFirestore(),
      if (sourceUpcomingHikeId.trim().isNotEmpty)
        'sourceUpcomingHikeId': sourceUpcomingHikeId.trim(),
    };
  }

  String get teamHikeSessionId => _teamHikeSessionId ?? '';
  Trail get trail => draft.trail;
  Duration get elapsedDuration => DateTime.now().difference(startedAt);
  int get routePointCount => routePoints.length;
  bool get hasKnownBatteryLevel =>
      batteryLevel > 0 || batteryStartedLevel != null;

  double get recordedDistanceKm {
    final validRoutePoints = routePoints
        .where((point) => point.hasValidPosition)
        .toList();
    if (validRoutePoints.length < 2) {
      return 0;
    }

    var totalMeters = 0.0;
    for (var index = 1; index < validRoutePoints.length; index++) {
      totalMeters += validRoutePoints[index - 1].distanceTo(
        validRoutePoints[index],
      );
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
    HikeSessionDraft? draft,
    int? batteryLevel,
    int? batteryStartedLevel,
    int? queuedUpdates,
    int? manualPins,
    int? checkIns,
    HikeCoordinate? latestLocation,
    List<HikeCoordinate>? routePoints,
    List<HikeManualPin>? manualPinLocations,
    List<HikeCheckInRecord>? checkInRecords,
    String? teamHikeSessionId,
    TeamHikeSession? teamHikeSession,
    String? sourceUpcomingHikeId,
  }) {
    return ActiveHikeSession(
      sessionId: sessionId ?? this.sessionId,
      draft: draft ?? this.draft,
      startedAt: startedAt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryStartedLevel: batteryStartedLevel ?? this.batteryStartedLevel,
      queuedUpdates: queuedUpdates ?? this.queuedUpdates,
      manualPins: manualPins ?? this.manualPins,
      checkIns: checkIns ?? this.checkIns,
      latestLocation: latestLocation ?? this.latestLocation,
      routePoints: routePoints ?? this.routePoints,
      manualPinLocations: manualPinLocations ?? this.manualPinLocations,
      checkInRecords: checkInRecords ?? this.checkInRecords,
      teamHikeSessionId: teamHikeSessionId ?? this.teamHikeSessionId,
      teamHikeSession: teamHikeSession ?? this.teamHikeSession,
      sourceUpcomingHikeId: sourceUpcomingHikeId ?? this.sourceUpcomingHikeId,
    );
  }
}

class HikeCoordinate {
  const HikeCoordinate({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
    this.altitudeMeters,
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
    return tryFromFirestore(data) ??
        HikeCoordinate(
          latitude: 0,
          longitude: 0,
          capturedAt: DateTime.now().toUtc(),
        );
  }

  static HikeCoordinate? tryFromFirestore(Map<String, dynamic> data) {
    final latitude = _validLatitudeFrom(data['latitude']);
    final longitude = _validLongitudeFrom(data['longitude']);
    if (latitude == null || longitude == null) {
      return null;
    }
    final capturedAt = data['capturedAtLocal'];
    return HikeCoordinate(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: _validAccuracyFrom(data['accuracyMeters']),
      altitudeMeters: _validAltitudeFrom(
        data['altitudeMeters'] ?? data['altitude'],
      ),
      capturedAt: capturedAt is String
          ? DateTime.tryParse(capturedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? altitudeMeters;
  final DateTime capturedAt;

  bool get hasValidPosition =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
      if (altitudeMeters != null) 'altitudeMeters': altitudeMeters,
      'capturedAtLocal': capturedAt.toUtc().toIso8601String(),
    };
  }

  double distanceTo(HikeCoordinate other) {
    if (!hasValidPosition || !other.hasValidPosition) {
      return double.infinity;
    }
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
    final boundedHaversine = haversine.clamp(0.0, 1.0);
    final centralAngle =
        2 *
        math.atan2(
          math.sqrt(boundedHaversine),
          math.sqrt(1 - boundedHaversine),
        );
    return earthRadiusMeters * centralAngle;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  static double? _validLatitudeFrom(Object? value) {
    if (value is num && value.isFinite && value >= -90 && value <= 90) {
      return value.toDouble();
    }
    return null;
  }

  static double? _validLongitudeFrom(Object? value) {
    if (value is num && value.isFinite && value >= -180 && value <= 180) {
      return value.toDouble();
    }
    return null;
  }

  static double? _validAccuracyFrom(Object? value) {
    if (value is num && value.isFinite && value >= 0) {
      return value.toDouble();
    }
    return null;
  }

  static double? _validAltitudeFrom(Object? value) {
    if (value is num && value.isFinite && value >= -500 && value <= 10000) {
      return value.toDouble();
    }
    return null;
  }
}

class HikeManualPin {
  const HikeManualPin({
    required this.id,
    required this.coordinate,
    required this.pinnedAt,
  });

  factory HikeManualPin.fromPersistence(Map<String, dynamic> data) {
    return tryFromPersistence(data) ??
        HikeManualPin(
          id: _modelStringFrom(data['pinId']),
          coordinate: HikeCoordinate(
            latitude: 0,
            longitude: 0,
            capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
          pinnedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
  }

  static HikeManualPin? tryFromPersistence(Map<String, dynamic> data) {
    final coordinate = HikeCoordinate.tryFromFirestore(
      _modelMapFrom(data['coordinate']),
    );
    if (coordinate == null) {
      return null;
    }
    return HikeManualPin(
      id: _modelStringFrom(data['pinId']),
      coordinate: coordinate,
      pinnedAt:
          _modelDateFromValue(data['pinnedAtLocal']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

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

class HikeCheckInRecord {
  const HikeCheckInRecord({
    required this.id,
    required this.checkedInAt,
    this.coordinate,
  });

  factory HikeCheckInRecord.fromPersistence(Map<String, dynamic> data) {
    return HikeCheckInRecord(
      id: _modelStringFrom(data['checkInId']),
      checkedInAt:
          _modelDateFromValue(data['checkedInAtLocal']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      coordinate: data['coordinate'] is Map
          ? HikeCoordinate.tryFromFirestore(_modelMapFrom(data['coordinate']))
          : null,
    );
  }

  final String id;
  final DateTime checkedInAt;
  final HikeCoordinate? coordinate;

  Map<String, dynamic> toPersistence() {
    return {
      'checkInId': id,
      'checkedInAtLocal': checkedInAt.toUtc().toIso8601String(),
      if (coordinate?.hasValidPosition == true)
        'coordinate': coordinate!.toFirestore(),
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
    final routePoints = recordedRoutePointsFor(activeHike);
    final distanceKm = _recordedDistanceKmFor(routePoints);
    final measuredDuration = endedAt.difference(activeHike.startedAt);
    final duration = measuredDuration.isNegative
        ? Duration.zero
        : measuredDuration;
    final actualCheckIns = math.max(
      activeHike.checkIns,
      activeHike.checkInRecords.length,
    );
    final actualManualPins = activeHike.manualPinLocations.length;
    final batteryStart =
        activeHike.batteryStartedLevel ?? activeHike.batteryLevel;
    final batteryDrop = math.max(0, batteryStart - activeHike.batteryLevel);
    final movingHours = math.max(duration.inMilliseconds / 3600000, 0.1);
    final paceMinutesPerKm = distanceKm <= 0
        ? 0
        : duration.inSeconds / 60 / math.max(distanceKm, 0.1);

    return HikeSummaryReport(
      sessionId: activeHike.sessionId,
      trailName: activeHike.trail.name,
      startedAt: activeHike.startedAt,
      endedAt: endedAt,
      duration: duration,
      distanceKm: distanceKm,
      checkIns: actualCheckIns,
      manualPins: actualManualPins,
      routePointCount: routePoints.length,
      batteryStartPercent: batteryStart,
      batteryEndPercent: activeHike.batteryLevel,
      insights: [
        'Average pace: ${paceMinutesPerKm.round()} min/km across ${distanceKm.toStringAsFixed(2)} km.',
        'Tracking density: ${routePoints.length} GPS points saved for replay and safety review.',
        'Route notes: $actualManualPins pinned locations and automatic GPS tracking.',
        'Battery used: $batteryDrop% over ${_formatDuration(duration)} (${(batteryDrop / movingHours).toStringAsFixed(1)}% per hour).',
        if (activeHike.queuedUpdates == 0)
          'Cloud sync: all hike telemetry is up to date.'
        else
          'Cloud sync: ${activeHike.queuedUpdates} updates are still queued for upload.',
      ],
    );
  }

  static List<HikeCoordinate> recordedRoutePointsFor(
    ActiveHikeSession activeHike,
  ) {
    final points = activeHike.routePoints
        .where((point) => point.hasValidPosition)
        .toList();
    points.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final latest = activeHike.latestLocation;
    if (latest?.hasValidPosition == true &&
        (points.isEmpty || points.last.distanceTo(latest!) > 2)) {
      points.add(latest!);
    }
    points.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return points;
  }

  static double _recordedDistanceKmFor(List<HikeCoordinate> routePoints) {
    if (routePoints.length < 2) {
      return 0;
    }
    var totalMeters = 0.0;
    for (var index = 1; index < routePoints.length; index++) {
      totalMeters += routePoints[index - 1].distanceTo(routePoints[index]);
    }
    return totalMeters / 1000;
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
      if (checkIns > 0) 'Past check-ins: $checkIns',
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
      'durationSeconds': duration.inSeconds,
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
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
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

double _modelDoubleFrom(Object? value, {double fallback = 0}) {
  return value is num && value.isFinite ? value.toDouble() : fallback;
}

int _modelIntFrom(Object? value, {int fallback = 0}) {
  return value is num && value.isFinite ? value.toInt() : fallback;
}

int _positiveModelIntFrom(Object? value, {required int fallback}) {
  final result = _modelIntFrom(value, fallback: fallback);
  return result > 0 ? result : fallback;
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

DateTime? _modelLocalDateFromValue(Object? value) {
  return _modelDateFromValue(value)?.toLocal();
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

Map<String, dynamic> _modelMapFrom(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

List<HikeCoordinate> _modelCoordinatesFrom(Object? value) {
  final coordinates = _modelListOfMaps(
    value,
  ).map(HikeCoordinate.tryFromFirestore).nonNulls.toList();
  coordinates.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return coordinates;
}

bool _modelCheckpointMapHasValidCoordinate(Map<String, dynamic> data) {
  final latitude = data['latitude'];
  final longitude = data['longitude'];
  return latitude is num &&
      longitude is num &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

String _checkpointDisplayName(TrailCheckpoint checkpoint, String fallback) {
  final name = checkpoint.name.trim();
  return name.isEmpty ? fallback : name;
}

List<String> _modelStringList(Object? value) {
  if (value is! Iterable) {
    return const [];
  }
  return value.whereType<String>().toList();
}

HikeSessionDraft? _modelDraftFromValue(Object? value) {
  if (value is! Map) {
    return null;
  }
  try {
    final draft = HikeSessionDraft.fromPersistence(
      Map<String, dynamic>.from(value),
    );
    return draft.trail.trailId.trim().isEmpty ? null : draft;
  } catch (_) {
    return null;
  }
}

class UpcomingHike {
  // Match the backend's window for starting a scheduled hike.
  static const visibleAfterDepartureGrace = Duration(minutes: 15);

  const UpcomingHike({
    required this.id,
    required this.sessionId,
    required this.trailId,
    required this.trailName,
    required this.latitude,
    required this.longitude,
    required this.area,
    required this.state,
    this.country = '',
    required this.distanceKm,
    required this.durationMinutes,
    required this.difficulty,
    required this.startPointName,
    required this.destinationName,
    required this.departureTime,
    required this.expectedReturnTime,
    required this.hikeType,
    required this.participantCount,
    required this.creatorPhone,
    required this.creatorName,
    required this.createdAt,
    this.participantPhones = const [],
    this.isDeleted = false,
    this.deletedAt,
    this.draft,
    this.joinRequestStatus = '',
    this.joinPolicy = 'open',
    this.departureReminderCount = 0,
    this.departureReminderSentByMe = false,
  });

  final String id;
  final String sessionId;
  final String trailId;
  final String trailName;
  final double latitude;
  final double longitude;
  final String area;
  final String state;
  final String country;
  final double distanceKm;
  final int durationMinutes;
  final String difficulty;
  final String startPointName;
  final String destinationName;
  final DateTime departureTime;
  final DateTime expectedReturnTime;
  final String hikeType;
  final int participantCount;
  final String creatorPhone;
  final String creatorName;
  final DateTime createdAt;
  final List<String> participantPhones;
  final bool isDeleted;
  final DateTime? deletedAt;
  final HikeSessionDraft? draft;
  final String joinRequestStatus;
  final String joinPolicy;
  final int departureReminderCount;
  final bool departureReminderSentByMe;

  bool get requiresJoinApproval => joinPolicy != 'open';

  bool get isLocalPendingSync => id.startsWith('local_pending_');

  DateTime get visibleUntil =>
      departureTime.toUtc().add(visibleAfterDepartureGrace);

  bool isUpcomingAt(DateTime now) =>
      !isDeleted && visibleUntil.isAfter(now.toUtc());

  Map<String, dynamic> toFirestore() => {
    'sessionId': sessionId,
    'trailId': trailId,
    'trailName': trailName,
    'latitude': latitude,
    'longitude': longitude,
    'area': area,
    'state': state,
    if (country.trim().isNotEmpty) 'country': country.trim(),
    'distanceKm': distanceKm,
    'durationMinutes': durationMinutes,
    'difficulty': difficulty,
    'startPointName': startPointName,
    'destinationName': destinationName,
    'departureTimeLocal': departureTime.toUtc().toIso8601String(),
    'expectedReturnTimeLocal': expectedReturnTime.toUtc().toIso8601String(),
    'hikeType': hikeType,
    'participantCount': participantCount,
    'creatorPhone': creatorPhone,
    'creatorName': creatorName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (participantPhones.isNotEmpty) 'participantPhones': participantPhones,
    if (isDeleted) 'isDeleted': true,
    if (deletedAt != null)
      'deletedAtLocal': deletedAt!.toUtc().toIso8601String(),
    if (joinRequestStatus.isNotEmpty) 'joinRequestStatus': joinRequestStatus,
    'joinPolicy': joinPolicy,
    if (departureReminderCount > 0)
      'departureReminderCount': departureReminderCount,
    if (departureReminderSentByMe) 'departureReminderSentByMe': true,
  };

  Map<String, dynamic> toPersistence() => {
    ...toFirestore(),
    if (draft != null) 'draft': draft!.toPersistence(),
  };

  UpcomingHike withDraft(HikeSessionDraft value) {
    return UpcomingHike(
      id: id,
      sessionId: sessionId,
      trailId: trailId,
      trailName: trailName,
      latitude: latitude,
      longitude: longitude,
      area: area,
      state: state,
      country: country,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      difficulty: difficulty,
      startPointName: startPointName,
      destinationName: destinationName,
      departureTime: departureTime,
      expectedReturnTime: expectedReturnTime,
      hikeType: hikeType,
      participantCount: participantCount,
      creatorPhone: creatorPhone,
      creatorName: creatorName,
      createdAt: createdAt,
      participantPhones: participantPhones,
      isDeleted: isDeleted,
      deletedAt: deletedAt,
      draft: value,
      joinRequestStatus: joinRequestStatus,
      joinPolicy: joinPolicy,
      departureReminderCount: departureReminderCount,
      departureReminderSentByMe: departureReminderSentByMe,
    );
  }

  factory UpcomingHike.fromFirestore(String id, Map<String, dynamic> data) {
    final phones = data['participantPhones'];
    final participantPhones = phones is List
        ? phones
              .map((e) => e is String ? e : '')
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    return UpcomingHike(
      id: id,
      sessionId: _modelStringFrom(data['sessionId']),
      trailId: _modelStringFrom(data['trailId']),
      trailName: _modelStringFrom(data['trailName']),
      latitude: _modelDoubleFrom(data['latitude']),
      longitude: _modelDoubleFrom(data['longitude']),
      area: _modelStringFrom(data['area']),
      state: _modelStringFrom(data['state']),
      country: _modelStringFrom(data['country']),
      distanceKm: _modelDoubleFrom(data['distanceKm']),
      durationMinutes: _modelIntFrom(data['durationMinutes']),
      difficulty: _modelStringFrom(data['difficulty']),
      startPointName: _modelStringFrom(data['startPointName']),
      destinationName: _modelStringFrom(data['destinationName']),
      departureTime:
          _modelLocalDateFromValue(data['departureTimeLocal']) ??
          _modelLocalDateFromValue(data['departureTime']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expectedReturnTime:
          _modelLocalDateFromValue(data['expectedReturnTimeLocal']) ??
          DateTime.now(),
      hikeType: _modelStringFrom(data['hikeType']),
      participantCount: _modelIntFrom(data['participantCount']),
      creatorPhone: _modelStringFrom(data['creatorPhone']),
      creatorName: _modelStringFrom(data['creatorName']),
      createdAt: _modelDateFromValue(data['createdAt']) ?? DateTime.now(),
      participantPhones: participantPhones,
      isDeleted: data['isDeleted'] == true,
      deletedAt: _modelDateFromValue(data['deletedAtLocal']),
      draft: _modelDraftFromValue(data['draft']),
      joinRequestStatus: _modelStringFrom(data['joinRequestStatus']),
      joinPolicy: _modelStringFrom(data['joinPolicy']) == 'approval'
          ? 'approval'
          : 'open',
      departureReminderCount: _modelIntFrom(data['departureReminderCount']),
      departureReminderSentByMe: data['departureReminderSentByMe'] == true,
    );
  }

  double distanceFrom(double lat, double lng) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        !lat.isFinite ||
        !lng.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return double.infinity;
    }
    const R = 6371;
    final dLat = _toRadians(latitude - lat);
    final dLng = _toRadians(longitude - lng);
    final sinHalfDLat = math.sin(dLat / 2);
    final sinHalfDLng = math.sin(dLng / 2);
    final a =
        sinHalfDLat * sinHalfDLat +
        math.cos(_toRadians(lat)) *
            math.cos(_toRadians(latitude)) *
            sinHalfDLng *
            sinHalfDLng;
    return R * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static double _toRadians(double deg) => deg * 3.141592653589793 / 180;
}

class UpcomingHikeJoinRequestReview {
  const UpcomingHikeJoinRequestReview({
    required this.requestId,
    required this.hikeId,
    required this.status,
    required this.reason,
    required this.requesterName,
    required this.trailName,
    this.departureTime,
    this.needsJoinPolicyChoice = false,
    this.profile = const <String, dynamic>{},
    this.achievements = const <Map<String, dynamic>>[],
    this.hikeHistory = const <Map<String, dynamic>>[],
  });

  final String requestId;
  final String hikeId;
  final String status;
  final String reason;
  final String requesterName;
  final String trailName;
  final DateTime? departureTime;
  final bool needsJoinPolicyChoice;
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> achievements;
  final List<Map<String, dynamic>> hikeHistory;

  bool get canResolve => status == 'pending';

  factory UpcomingHikeJoinRequestReview.fromMap(Map<String, dynamic> data) {
    return UpcomingHikeJoinRequestReview(
      requestId: _modelStringFrom(data['requestId']),
      hikeId: _modelStringFrom(data['hikeId']),
      status: _modelStringFrom(data['status']).isEmpty
          ? 'expired'
          : _modelStringFrom(data['status']),
      reason: _modelStringFrom(data['reason']),
      requesterName: _modelStringFrom(data['requesterName']).isEmpty
          ? 'A hiker'
          : _modelStringFrom(data['requesterName']),
      trailName: _modelStringFrom(data['trailName']).isEmpty
          ? 'Upcoming hike'
          : _modelStringFrom(data['trailName']),
      departureTime: _modelDateFromValue(data['departureTimeLocal']),
      needsJoinPolicyChoice: data['needsJoinPolicyChoice'] == true,
      profile: data['profile'] is Map
          ? Map<String, dynamic>.from(data['profile'] as Map)
          : const <String, dynamic>{},
      achievements: data['achievements'] is List
          ? (data['achievements'] as List)
                .whereType<Map>()
                .map((value) => Map<String, dynamic>.from(value))
                .toList()
          : const <Map<String, dynamic>>[],
      hikeHistory: data['hikeHistory'] is List
          ? (data['hikeHistory'] as List)
                .whereType<Map>()
                .map((value) => Map<String, dynamic>.from(value))
                .toList()
          : const <Map<String, dynamic>>[],
    );
  }
}

class HikeReminderPreference {
  const HikeReminderPreference({
    this.enabled = true,
    this.firstReminderMinutesBefore = 120,
    this.repeatIntervalMinutes = 30,
    this.finalReminderMinutesBefore = 15,
    this.maximumReminders = 4,
  });

  factory HikeReminderPreference.fromFirestore(Map<String, dynamic> data) {
    return HikeReminderPreference(
      enabled: data['enabled'] != false,
      firstReminderMinutesBefore: _modelIntFrom(
        data['firstReminderMinutesBefore'],
        fallback: 120,
      ),
      repeatIntervalMinutes: _modelIntFrom(
        data['repeatIntervalMinutes'],
        fallback: 30,
      ),
      finalReminderMinutesBefore: _modelIntFrom(
        data['finalReminderMinutesBefore'],
        fallback: 15,
      ),
      maximumReminders: _modelIntFrom(data['maximumReminders'], fallback: 4),
    ).normalized();
  }

  static const firstReminderOptions = <int>[
    15,
    30,
    60,
    120,
    180,
    360,
    720,
    1440,
  ];
  static const repeatIntervalOptions = <int>[0, 15, 30, 60, 120, 360];
  static const finalReminderOptions = <int>[5, 10, 15, 30, 60];
  static const maximumReminderOptions = <int>[1, 2, 3, 4, 5, 6, 7, 8];

  final bool enabled;
  final int firstReminderMinutesBefore;
  final int repeatIntervalMinutes;
  final int finalReminderMinutesBefore;
  final int maximumReminders;

  HikeReminderPreference normalized() {
    final first = firstReminderOptions.contains(firstReminderMinutesBefore)
        ? firstReminderMinutesBefore
        : 120;
    final repeat = repeatIntervalOptions.contains(repeatIntervalMinutes)
        ? repeatIntervalMinutes
        : 30;
    final finalBefore =
        finalReminderOptions.contains(finalReminderMinutesBefore)
        ? finalReminderMinutesBefore
        : 15;
    final maximum = maximumReminderOptions.contains(maximumReminders)
        ? maximumReminders
        : 4;
    return HikeReminderPreference(
      enabled: enabled,
      firstReminderMinutesBefore: first,
      repeatIntervalMinutes: repeat,
      finalReminderMinutesBefore: finalBefore.clamp(5, first),
      maximumReminders: repeat == 0 ? 1 : maximum,
    );
  }

  HikeReminderPreference copyWith({
    bool? enabled,
    int? firstReminderMinutesBefore,
    int? repeatIntervalMinutes,
    int? finalReminderMinutesBefore,
    int? maximumReminders,
  }) {
    return HikeReminderPreference(
      enabled: enabled ?? this.enabled,
      firstReminderMinutesBefore:
          firstReminderMinutesBefore ?? this.firstReminderMinutesBefore,
      repeatIntervalMinutes:
          repeatIntervalMinutes ?? this.repeatIntervalMinutes,
      finalReminderMinutesBefore:
          finalReminderMinutesBefore ?? this.finalReminderMinutesBefore,
      maximumReminders: maximumReminders ?? this.maximumReminders,
    ).normalized();
  }

  Map<String, dynamic> toFirestore() {
    final value = normalized();
    return {
      'enabled': value.enabled,
      'firstReminderMinutesBefore': value.firstReminderMinutesBefore,
      'repeatIntervalMinutes': value.repeatIntervalMinutes,
      'finalReminderMinutesBefore': value.finalReminderMinutesBefore,
      'maximumReminders': value.maximumReminders,
    };
  }
}

class GroupChat {
  const GroupChat({
    required this.id,
    required this.hikeSessionId,
    required this.trailName,
    required this.participantPhones,
    required this.creatorPhone,
    required this.createdAt,
    this.chatType = 'group',
    this.participantNames = const {},
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageSenderPhone,
    this.hikeEndedAt,
    this.chatRemovesAt,
    this.isDeleted = false,
    this.closureReason = '',
    this.lastReadAt = const {},
    this.unreadCount = const {},
    this.departureTime,
    this.participantPhotoURLs = const {},
    this.customName = '',
    this.requiresHostNaming = false,
    this.namingPromptShown = false,
    this.latestJoinedName = '',
  });

  final String id;
  final String hikeSessionId;
  final String trailName;
  final List<String> participantPhones;
  final String creatorPhone;
  final DateTime createdAt;
  final String chatType;
  final Map<String, String> participantNames;
  final DateTime? departureTime;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderPhone;
  final DateTime? hikeEndedAt;
  final DateTime? chatRemovesAt;
  final bool isDeleted;
  final String closureReason;
  final Map<String, DateTime> lastReadAt;
  final Map<String, int> unreadCount;
  final Map<String, String> participantPhotoURLs;
  final String customName;
  final bool requiresHostNaming;
  final bool namingPromptShown;
  final String latestJoinedName;

  bool get isDirect => chatType == 'direct';

  String displayNameFor(String phoneNumber) {
    if (!isDirect) {
      if (customName.trim().isNotEmpty) {
        return customName.trim();
      }
      if (departureTime != null) {
        return defaultGroupName(trailName, departureTime!);
      }
      return '${trailName.trim().isEmpty ? 'Hike' : trailName.trim()} Group';
    }
    for (final phone in participantPhones) {
      if (_modelPhoneKey(phone) == _modelPhoneKey(phoneNumber)) {
        continue;
      }
      final name = participantNames[_modelPhoneKey(phone)]?.trim() ?? '';
      return name.isEmpty ? phone : name;
    }
    return trailName.isEmpty ? 'Private chat' : trailName;
  }

  String photoURLFor(String phoneNumber) {
    return participantPhotoURLs[_modelPhoneKey(phoneNumber)]?.trim() ?? '';
  }

  DateTime? lastReadAtFor(String phoneNumber) {
    return lastReadAt[_modelPhoneKey(phoneNumber)];
  }

  int unreadCountFor(String phoneNumber) {
    return unreadCount[_modelPhoneKey(phoneNumber)] ?? 0;
  }

  GroupChat copyWith({Map<String, String>? participantPhotoURLs}) {
    return GroupChat(
      id: id,
      hikeSessionId: hikeSessionId,
      trailName: trailName,
      participantPhones: participantPhones,
      creatorPhone: creatorPhone,
      createdAt: createdAt,
      chatType: chatType,
      participantNames: participantNames,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      lastMessageSenderPhone: lastMessageSenderPhone,
      hikeEndedAt: hikeEndedAt,
      chatRemovesAt: chatRemovesAt,
      isDeleted: isDeleted,
      closureReason: closureReason,
      lastReadAt: lastReadAt,
      unreadCount: unreadCount,
      departureTime: departureTime,
      participantPhotoURLs: participantPhotoURLs ?? this.participantPhotoURLs,
      customName: customName,
      requiresHostNaming: requiresHostNaming,
      namingPromptShown: namingPromptShown,
      latestJoinedName: latestJoinedName,
    );
  }

  static String defaultGroupName(String trailName, DateTime departureTime) {
    final local = departureTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthName(local.month);
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final rawLocation = trailName.trim().isEmpty ? 'Hike' : trailName.trim();
    const suffix = ' Group';
    final prefix = '$day$month $hour:$minute ';
    final availableLocationLength = 60 - prefix.length - suffix.length;
    final location = rawLocation.length <= availableLocationLength
        ? rawLocation
        : rawLocation.substring(0, availableLocationLength).trimRight();
    return '$prefix$location$suffix';
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Map<String, dynamic> toFirestore() {
    return {
      'hikeSessionId': hikeSessionId,
      'trailName': trailName,
      'participantPhones': participantPhones,
      'creatorPhone': creatorPhone,
      'chatType': chatType,
      if (participantNames.isNotEmpty) 'participantNames': participantNames,
      if (participantPhotoURLs.isNotEmpty)
        'participantPhotoURLs': participantPhotoURLs,
      'createdAtLocal': createdAt.toUtc().toIso8601String(),
      if (departureTime != null)
        'departureTimeLocal': departureTime!.toUtc().toIso8601String(),
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastMessageAt != null)
        'lastMessageAtLocal': lastMessageAt!.toUtc().toIso8601String(),
      if (lastMessageSenderPhone != null)
        'lastMessageSenderPhone': lastMessageSenderPhone,
      if (hikeEndedAt != null)
        'hikeEndedAtLocal': hikeEndedAt!.toUtc().toIso8601String(),
      if (chatRemovesAt != null)
        'chatRemovesAtLocal': chatRemovesAt!.toUtc().toIso8601String(),
      if (isDeleted) 'isDeleted': true,
      if (closureReason.isNotEmpty) 'closureReason': closureReason,
      if (lastReadAt.isNotEmpty)
        'lastReadAt': lastReadAt.map(
          (k, v) => MapEntry(k, v.toUtc().toIso8601String()),
        ),
      if (unreadCount.isNotEmpty) 'unreadCount': unreadCount,
      if (customName.isNotEmpty) 'customName': customName,
      if (requiresHostNaming) 'requiresHostNaming': true,
      if (namingPromptShown) 'namingPromptShown': true,
      if (latestJoinedName.isNotEmpty) 'latestJoinedName': latestJoinedName,
    };
  }

  factory GroupChat.fromFirestore(String id, Map<String, dynamic> data) {
    final rawPhones = data['participantPhones'];
    final phones = rawPhones is Iterable
        ? rawPhones
              .whereType<String>()
              .map((phone) => phone.trim())
              .where((phone) => phone.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    final rawNames = data['participantNames'];
    final participantNames = rawNames is Map
        ? rawNames.map(
            (key, value) =>
                MapEntry(key.toString(), value is String ? value : ''),
          )
        : <String, String>{};
    final rawPhotoURLs = data['participantPhotoURLs'];
    final participantPhotoURLs = rawPhotoURLs is Map
        ? rawPhotoURLs.map(
            (key, value) =>
                MapEntry(key.toString(), value is String ? value : ''),
          )
        : <String, String>{};
    final lastReadAt = <String, DateTime>{};
    if (data['lastReadAt'] is Map) {
      (data['lastReadAt'] as Map).forEach((key, value) {
        final phoneKey = _modelPhoneKey(key.toString());
        if (phoneKey.isEmpty) {
          return;
        }
        lastReadAt[phoneKey] = _modelDateFromValue(value) ?? DateTime.now();
      });
    }
    final unreadCount = <String, int>{};
    if (data['unreadCount'] is Map) {
      (data['unreadCount'] as Map).forEach((key, value) {
        final phoneKey = _modelPhoneKey(key.toString());
        if (phoneKey.isEmpty) {
          return;
        }
        unreadCount[phoneKey] = value is num ? value.toInt() : 0;
      });
    }
    return GroupChat(
      id: id,
      hikeSessionId: _modelStringFrom(data['hikeSessionId']),
      trailName: _modelStringFrom(data['trailName']),
      participantPhones: phones,
      creatorPhone: _modelStringFrom(data['creatorPhone']),
      createdAt: _modelDateFromValue(data['createdAtLocal']) ?? DateTime.now(),
      chatType: _modelStringFrom(data['chatType']).isEmpty
          ? 'group'
          : _modelStringFrom(data['chatType']),
      participantNames: participantNames,
      participantPhotoURLs: participantPhotoURLs,
      lastMessage: data['lastMessage'] is String
          ? data['lastMessage'] as String
          : null,
      lastMessageAt: data['lastMessageAtLocal'] != null
          ? _modelDateFromValue(data['lastMessageAtLocal'])
          : null,
      lastMessageSenderPhone: data['lastMessageSenderPhone'] is String
          ? data['lastMessageSenderPhone'] as String
          : null,
      hikeEndedAt: _modelDateFromValue(
        data['hikeEndedAtLocal'] ?? data['hikeEndedAt'],
      ),
      chatRemovesAt: _modelDateFromValue(data['chatRemovesAtLocal']),
      isDeleted: data['isDeleted'] == true,
      closureReason: _modelStringFrom(data['closureReason']),
      departureTime: _modelDateFromValue(data['departureTimeLocal']),
      lastReadAt: lastReadAt,
      unreadCount: unreadCount,
      customName: _modelStringFrom(data['customName']),
      requiresHostNaming: data['requiresHostNaming'] == true,
      namingPromptShown: data['namingPromptShown'] == true,
      latestJoinedName: _modelStringFrom(data['latestJoinedName']),
    );
  }
}

String _modelPhoneKey(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderPhone,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isSystemMessage = false,
    this.seenBy = const [],
    this.sendStatus = SendStatus.sent,
    this.attachment,
    this.senderPhotoURL = '',
  });

  final String id;
  final String chatId;
  final String senderPhone;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final bool isSystemMessage;
  final List<String> seenBy;
  final SendStatus sendStatus;
  final ChatAttachment? attachment;
  final String senderPhotoURL;

  Map<String, dynamic> toFirestore() {
    return {
      'chatId': chatId,
      'senderPhone': senderPhone,
      'senderName': senderName,
      'text': text,
      'sentAtLocal': sentAt.toUtc().toIso8601String(),
      'isSystemMessage': isSystemMessage,
      'seenBy': seenBy,
      if (senderPhotoURL.trim().isNotEmpty)
        'senderPhotoURL': senderPhotoURL.trim(),
      if (attachment != null) 'attachment': attachment!.toFirestore(),
    };
  }

  factory ChatMessage.fromFirestore(String id, Map<String, dynamic> data) {
    final rawSeenBy = data['seenBy'];
    final seenBy = rawSeenBy is List
        ? rawSeenBy.whereType<String>().toList()
        : <String>[];
    return ChatMessage(
      id: id,
      chatId: _modelStringFrom(data['chatId']),
      senderPhone: _modelStringFrom(data['senderPhone']),
      senderName: _modelStringFrom(data['senderName']),
      senderPhotoURL: _modelStringFrom(data['senderPhotoURL']),
      text: _modelStringFrom(data['text']),
      sentAt: _modelDateFromValue(data['sentAtLocal']) ?? DateTime.now(),
      isSystemMessage: data['isSystemMessage'] == true,
      seenBy: seenBy,
      attachment: data['attachment'] is Map
          ? ChatAttachment.fromFirestore(
              Map<String, dynamic>.from(data['attachment'] as Map),
            )
          : null,
    );
  }

  factory ChatMessage.fromPending({
    required String localId,
    required String chatId,
    required String senderPhone,
    required String senderName,
    required String text,
    required DateTime createdAt,
    SendStatus sendStatus = SendStatus.sending,
    ChatAttachment? attachment,
    String senderPhotoURL = '',
  }) {
    return ChatMessage(
      id: localId,
      chatId: chatId,
      senderPhone: senderPhone,
      senderName: senderName,
      text: text,
      sentAt: createdAt,
      sendStatus: sendStatus,
      attachment: attachment,
      senderPhotoURL: senderPhotoURL,
    );
  }
}

enum ChatAttachmentType { image, video, document }

class ChatAttachment {
  const ChatAttachment({
    required this.type,
    required this.url,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  factory ChatAttachment.fromFirestore(Map<String, dynamic> data) {
    return ChatAttachment(
      type: ChatAttachmentType.values.firstWhere(
        (type) => type.name == _modelStringFrom(data['type']),
        orElse: () => ChatAttachmentType.document,
      ),
      url: _modelStringFrom(data['url']),
      fileName: _modelStringFrom(data['fileName']),
      contentType: _modelStringFrom(data['contentType']),
      sizeBytes: _modelIntFrom(data['sizeBytes']),
    );
  }

  final ChatAttachmentType type;
  final String url;
  final String fileName;
  final String contentType;
  final int sizeBytes;

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'url': url,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
    };
  }
}

enum SendStatus { sending, sent, failed }
