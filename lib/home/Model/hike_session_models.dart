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
    );
  }

  final String sessionId;
  final HikeSessionDraft draft;
  final DateTime startedAt;
  final int batteryLevel;
  final int queuedUpdates;
  final int manualPins;
  final int checkIns;

  Trail get trail => draft.trail;

  ActiveHikeSession copyWith({
    String? sessionId,
    int? batteryLevel,
    int? queuedUpdates,
    int? manualPins,
    int? checkIns,
  }) {
    return ActiveHikeSession(
      sessionId: sessionId ?? this.sessionId,
      draft: draft,
      startedAt: startedAt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      queuedUpdates: queuedUpdates ?? this.queuedUpdates,
      manualPins: manualPins ?? this.manualPins,
      checkIns: checkIns ?? this.checkIns,
    );
  }
}
