// HikeHistorySummary and detail models parse completed hikes, route samples and team tracks.
import '../../home/Model/hike_session_models.dart';
import '../../home/Model/shared_team_hike_summary.dart';

/// Computes map.
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

/// Computes maps.
List<Map<String, dynamic>> _maps(Object? value) => value is Iterable
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const <Map<String, dynamic>>[];

/// Computes text.
String _text(Object? value) => value is String ? value.trim() : '';

/// Computes integer.
int _integer(Object? value) => value is num && value.isFinite
    ? value.round()
    : int.tryParse('$value') ?? 0;

/// Computes number.
double _number(Object? value) => value is num && value.isFinite
    ? value.toDouble()
    : double.tryParse('$value') ?? 0;

/// Computes date.
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Parse the compact history row separately from route and telemetry detail payloads.
class HikeHistorySummary {
  /// Creates hike history summary.
  const HikeHistorySummary({
    required this.sessionId,
    required this.trailId,
    required this.trailName,
    required this.location,
    required this.difficulty,
    required this.hikeType,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.distanceKm,
    required this.checkIns,
    required this.manualPins,
    required this.routePointCount,
    required this.batteryStartPercent,
    required this.batteryEndPercent,
    required this.teamMemberCount,
    required this.coverImageUrl,
    this.teamHikeSessionId = '',
  });

  /// Creates hike history summary from stored map data.
  factory HikeHistorySummary.fromMap(Map<String, dynamic> data) {
    return HikeHistorySummary(
      sessionId: _text(data['sessionId']),
      trailId: _text(data['trailId']),
      trailName: _text(data['trailName']).isEmpty
          ? 'Completed hike'
          : _text(data['trailName']),
      location: _text(data['location']),
      difficulty: _text(data['difficulty']),
      hikeType: _text(data['hikeType']) == 'team' ? 'team' : 'solo',
      startedAt: _date(data['startedAtLocal']),
      endedAt: _date(data['endedAtLocal']),
      duration: Duration(
        seconds: _integer(data['durationSeconds']).clamp(0, 2592000),
      ),
      distanceKm: _number(data['distanceKm']).clamp(0, 5000),
      checkIns: _integer(data['checkIns']).clamp(0, 100000),
      manualPins: _integer(data['manualPins']).clamp(0, 100000),
      routePointCount: _integer(data['routePointCount']).clamp(0, 1000000),
      batteryStartPercent: _integer(data['batteryStartPercent']).clamp(0, 100),
      batteryEndPercent: _integer(data['batteryEndPercent']).clamp(0, 100),
      teamMemberCount: _integer(data['teamMemberCount']).clamp(1, 50),
      coverImageUrl: _text(data['coverImageUrl']),
      teamHikeSessionId: _text(data['teamHikeSessionId']),
    );
  }

  final String sessionId;
  final String trailId;
  final String trailName;
  final String location;
  final String difficulty;
  final String hikeType;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Duration duration;
  final double distanceKm;
  final int checkIns;
  final int manualPins;
  final int routePointCount;
  final int batteryStartPercent;
  final int batteryEndPercent;
  final int teamMemberCount;
  final String coverImageUrl;
  final String teamHikeSessionId;

  /// Returns is team.
  bool get isTeam => hikeType == 'team';
}

/// Represents hike history checkpoint.
class HikeHistoryCheckpoint {
  /// Creates hike history checkpoint.
  const HikeHistoryCheckpoint({
    required this.name,
    required this.order,
    required this.latitude,
    required this.longitude,
  });

  /// Creates hike history checkpoint from stored map data.
  factory HikeHistoryCheckpoint.fromMap(Map<String, dynamic> data) =>
      HikeHistoryCheckpoint(
        name: _text(data['name']).isEmpty ? 'Checkpoint' : _text(data['name']),
        order: _integer(data['order']),
        latitude: _number(data['latitude']),
        longitude: _number(data['longitude']),
      );

  final String name;
  final int order;
  final double latitude;
  final double longitude;
}

/// Represents hike history check in.
class HikeHistoryCheckIn {
  /// Creates hike history check in.
  const HikeHistoryCheckIn({
    required this.id,
    required this.status,
    required this.checkedInAt,
    required this.batteryLevel,
    this.coordinate,
  });

  /// Creates hike history check in from stored map data.
  factory HikeHistoryCheckIn.fromMap(Map<String, dynamic> data) =>
      HikeHistoryCheckIn(
        id: _text(data['checkInId']),
        status: _text(data['status']).isEmpty ? 'safe' : _text(data['status']),
        checkedInAt: _date(data['checkedInAtLocal']),
        batteryLevel: _integer(data['batteryLevel']).clamp(0, 100),
        coordinate: data['coordinate'] is Map
            ? HikeCoordinate.tryFromFirestore(_map(data['coordinate']))
            : null,
      );

  final String id;
  final String status;
  final DateTime? checkedInAt;
  final int batteryLevel;
  final HikeCoordinate? coordinate;
}

/// Represents hike history member track.
class HikeHistoryMemberTrack {
  /// Creates hike history member track.
  const HikeHistoryMemberTrack({
    required this.name,
    required this.isCurrentUser,
    required this.routePoints,
  });

  /// Creates hike history member track from stored map data.
  factory HikeHistoryMemberTrack.fromMap(Map<String, dynamic> data) =>
      HikeHistoryMemberTrack(
        name: _text(data['name']).isEmpty ? 'Hiker' : _text(data['name']),
        isCurrentUser: data['isCurrentUser'] == true,
        routePoints: _maps(
          data['routePoints'],
        ).map(HikeCoordinate.tryFromFirestore).nonNulls.toList(),
      );

  final String name;
  final bool isCurrentUser;
  final List<HikeCoordinate> routePoints;
}

/// Represents hike history detail.
class HikeHistoryDetail {
  /// Creates hike history detail.
  const HikeHistoryDetail({
    required this.summary,
    required this.startPointName,
    required this.destinationName,
    required this.plannedStartTime,
    required this.estimatedArrivalTime,
    required this.estimatedReturnTime,
    required this.checkpoints,
    required this.plannedDistanceKm,
    required this.estimatedDurationMinutes,
    required this.elevationGainMeters,
    required this.trailRatingAverage,
    required this.trailRatingCount,
    required this.isVerifiedTrail,
    required this.averageSpeedKmh,
    required this.paceMinutesPerKm,
    required this.storedRoutePointCount,
    required this.routePointsDownsampled,
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
    required this.safetyCheckInIntervalSeconds,
    required this.locationRecordingIntervalSeconds,
    required this.shareLiveLocation,
    required this.fallDetectionEnabled,
    required this.pathDeviationEnabled,
    required this.offlinePhysicalAlertEnabled,
    required this.duressEnabled,
    required this.pathDeviationAlertCount,
    required this.completedChecklistItems,
    required this.checkInRecords,
    required this.manualPins,
    required this.routePoints,
    required this.telemetryPointCount,
    required this.batteryUsedPercent,
    required this.lowestRecordedBatteryPercent,
    required this.teamBuddyNames,
    required this.memberTracks,
    required this.insights,
    required this.ratingStars,
    required this.ratingDifficulty,
    required this.ratingComment,
    required this.sourceUpcomingHikeId,
    required this.teamHikeSessionId,
    required this.groupChatId,
    required this.routeCaptureAvailable,
    this.sharedTeamSummary,
  });

  /// Creates hike history detail from stored map data.
  factory HikeHistoryDetail.fromMap(Map<String, dynamic> data) {
    final plan = _map(data['plan']);
    final trail = _map(data['trail']);
    final performance = _map(data['performance']);
    final safety = _map(data['safety']);
    final battery = _map(data['battery']);
    final team = _map(data['team']);
    final rating = _map(data['rating']);
    final source = _map(data['source']);
    final manualPins = _maps(safety['manualPins'])
        .map((pin) {
          final normalized = <String, dynamic>{
            'pinId': pin['pinId'],
            'pinnedAtLocal': pin['pinnedAtLocal'],
            'coordinate': _map(pin['coordinate']),
          };
          return HikeManualPin.tryFromPersistence(normalized);
        })
        .nonNulls
        .toList();
    return HikeHistoryDetail(
      summary: HikeHistorySummary.fromMap(_map(data['summary'])),
      sharedTeamSummary: data['teamSummary'] is Map
          ? SharedTeamHikeSummary.fromMap(_map(data['teamSummary']))
          : null,
      startPointName: _text(plan['startPointName']),
      destinationName: _text(plan['destinationName']),
      plannedStartTime: _date(plan['plannedStartTimeLocal']),
      estimatedArrivalTime: _date(plan['estimatedArrivalTimeLocal']),
      estimatedReturnTime: _date(plan['estimatedReturnTimeLocal']),
      checkpoints: _maps(
        plan['checkpoints'],
      ).map(HikeHistoryCheckpoint.fromMap).toList(),
      plannedDistanceKm: _number(trail['plannedDistanceKm']),
      estimatedDurationMinutes: _integer(trail['estimatedDurationMinutes']),
      elevationGainMeters: _integer(trail['elevationGainMeters']),
      trailRatingAverage: _number(trail['ratingAverage']).clamp(0, 5),
      trailRatingCount: _integer(trail['ratingCount']).clamp(0, 10000000),
      isVerifiedTrail: trail['isVerifiedTrail'] == true,
      averageSpeedKmh: _number(performance['averageSpeedKmh']),
      paceMinutesPerKm: _number(performance['paceMinutesPerKm']),
      storedRoutePointCount: _integer(performance['storedRoutePointCount']),
      routePointsDownsampled: performance['routePointsDownsampled'] == true,
      minAltitudeMeters: performance['minAltitudeMeters'] is num
          ? _number(performance['minAltitudeMeters'])
          : null,
      maxAltitudeMeters: performance['maxAltitudeMeters'] is num
          ? _number(performance['maxAltitudeMeters'])
          : null,
      safetyCheckInIntervalSeconds: _integer(
        safety['safetyCheckInIntervalSeconds'],
      ),
      locationRecordingIntervalSeconds: _integer(
        safety['locationRecordingIntervalSeconds'],
      ),
      shareLiveLocation: safety['shareLiveLocation'] == true,
      fallDetectionEnabled: safety['fallDetectionEnabled'] == true,
      pathDeviationEnabled: safety['pathDeviationEnabled'] == true,
      offlinePhysicalAlertEnabled:
          safety['offlinePhysicalAlertEnabled'] == true,
      duressEnabled: safety['duressEnabled'] == true,
      pathDeviationAlertCount: _integer(safety['pathDeviationAlertCount']),
      completedChecklistItems: safety['completedChecklistItems'] is Iterable
          ? List<String>.from(safety['completedChecklistItems'])
          : const [],
      checkInRecords: _maps(
        safety['checkIns'],
      ).map(HikeHistoryCheckIn.fromMap).toList(),
      manualPins: manualPins,
      routePoints: _maps(
        data['routePoints'],
      ).map(HikeCoordinate.tryFromFirestore).nonNulls.toList(),
      telemetryPointCount: _integer(data['telemetryPointCount']),
      batteryUsedPercent: _integer(battery['usedPercent']).clamp(0, 100),
      lowestRecordedBatteryPercent: battery['lowestRecordedPercent'] is num
          ? _integer(battery['lowestRecordedPercent']).clamp(0, 100)
          : null,
      teamBuddyNames: _maps(team['buddies'])
          .map((buddy) => _text(buddy['name']))
          .where((name) => name.isNotEmpty)
          .toList(),
      memberTracks: _maps(team['memberTracks'])
          .map(HikeHistoryMemberTrack.fromMap)
          .where((track) => track.routePoints.isNotEmpty)
          .toList(),
      insights: data['insights'] is Iterable
          ? List<String>.from(data['insights'])
                .map(
                  (insight) =>
                      insight.startsWith('Route notes: ') &&
                          insight.endsWith(
                            'pinned locations and automatic GPS tracking.',
                          )
                      ? 'Route recorded with automatic GPS tracking.'
                      : insight,
                )
                .toList()
          : const [],
      ratingStars: _integer(rating['stars']).clamp(0, 5),
      ratingDifficulty: _text(rating['difficulty']),
      ratingComment: _text(rating['comment']),
      sourceUpcomingHikeId: _text(source['sourceUpcomingHikeId']),
      teamHikeSessionId: _text(source['teamHikeSessionId']),
      groupChatId: _text(source['groupChatId']),
      routeCaptureAvailable: source['routeCaptureAvailable'] == true,
    );
  }

  final HikeHistorySummary summary;
  final SharedTeamHikeSummary? sharedTeamSummary;
  final String startPointName;
  final String destinationName;
  final DateTime? plannedStartTime;
  final DateTime? estimatedArrivalTime;
  final DateTime? estimatedReturnTime;
  final List<HikeHistoryCheckpoint> checkpoints;
  final double plannedDistanceKm;
  final int estimatedDurationMinutes;
  final int elevationGainMeters;
  final double trailRatingAverage;
  final int trailRatingCount;
  final bool isVerifiedTrail;
  final double averageSpeedKmh;
  final double paceMinutesPerKm;
  final int storedRoutePointCount;
  final bool routePointsDownsampled;
  final double? minAltitudeMeters;
  final double? maxAltitudeMeters;
  final int safetyCheckInIntervalSeconds;
  final int locationRecordingIntervalSeconds;
  final bool shareLiveLocation;
  final bool fallDetectionEnabled;
  final bool pathDeviationEnabled;
  final bool offlinePhysicalAlertEnabled;
  final bool duressEnabled;
  final int pathDeviationAlertCount;
  final List<String> completedChecklistItems;
  final List<HikeHistoryCheckIn> checkInRecords;
  final List<HikeManualPin> manualPins;
  final List<HikeCoordinate> routePoints;
  final int telemetryPointCount;
  final int batteryUsedPercent;
  final int? lowestRecordedBatteryPercent;
  final List<String> teamBuddyNames;
  final List<HikeHistoryMemberTrack> memberTracks;
  final List<String> insights;
  final int ratingStars;
  final String ratingDifficulty;
  final String ratingComment;
  final String sourceUpcomingHikeId;
  final String teamHikeSessionId;
  final String groupChatId;
  final bool routeCaptureAvailable;
}

/// Parses hike history list.
List<HikeHistorySummary> parseHikeHistoryList(Object? payload) {
  final data = _map(payload);
  return _maps(data['hikes'])
      .map(HikeHistorySummary.fromMap)
      .where((hike) => hike.sessionId.isNotEmpty)
      .toList();
}

/// Parses hike history detail.
HikeHistoryDetail parseHikeHistoryDetail(Object? payload) {
  final detail = _map(_map(payload)['detail']);
  if (detail.isEmpty) {
    throw const FormatException('Missing hike history detail.');
  }
  return HikeHistoryDetail.fromMap(detail);
}
