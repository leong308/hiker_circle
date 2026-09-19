import '../../core/services/hiking_route_service.dart';
import 'dart:convert';

import '../../trail/Model/trail_models.dart';
import '../Model/hike_session_models.dart';

/// Resolves the transient preparation dashboard from cloud-owned upcoming
/// hikes and the small amount of preparation state that belongs on-device.
class PlannedHikeStateResolver {
  const PlannedHikeStateResolver._();

  static const Duration visibleAfterDepartureGrace =
      UpcomingHike.visibleAfterDepartureGrace;
  static const Duration weatherFreshness = Duration(hours: 4);

  static List<UpcomingHike> mergeUpcomingHikes({
    required Iterable<UpcomingHike> remote,
    required Iterable<UpcomingHike> cached,
    required bool retainUnconfirmedCachedHikes,
    Set<String> consumedHikeIds = const {},
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    bool eligible(UpcomingHike hike) =>
        hike.isUpcomingAt(currentTime) && !consumedHikeIds.contains(hike.id);
    final remoteHikes = remote.where(eligible).toList();
    final cachedHikes = cached.where(eligible).toList();
    final draftCandidates =
        cachedHikes.where((hike) => hike.draft != null).toList()
          ..sort((left, right) {
            if (left.isLocalPendingSync != right.isLocalPendingSync) {
              return left.isLocalPendingSync ? -1 : 1;
            }
            return right.createdAt.compareTo(left.createdAt);
          });
    final localDraftBySchedule = <String, HikeSessionDraft>{};
    for (final candidate in draftCandidates) {
      localDraftBySchedule.putIfAbsent(
        _scheduleKey(candidate),
        () => candidate.draft!,
      );
    }
    final merged = <UpcomingHike>[];
    final ids = <String>{};
    final scheduleKeys = <String>{};

    void add(UpcomingHike hike) {
      if (!eligible(hike)) return;
      final scheduleKey = _scheduleKey(hike);
      if (!ids.add(hike.id) || !scheduleKeys.add(scheduleKey)) return;
      final localDraft = localDraftBySchedule[scheduleKey];
      merged.add(localDraft == null ? hike : hike.withDraft(localDraft));
    }

    for (final hike in remoteHikes) {
      add(hike);
    }
    if (retainUnconfirmedCachedHikes) {
      cachedHikes.sort((a, b) {
        if (a.isLocalPendingSync != b.isLocalPendingSync) {
          return a.isLocalPendingSync ? 1 : -1;
        }
        return a.departureTime.compareTo(b.departureTime);
      });
      for (final hike in cachedHikes) {
        add(hike);
      }
    }
    merged.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return List<UpcomingHike>.unmodifiable(merged);
  }

  static UpcomingHike? selectNext(
    Iterable<UpcomingHike> hikes, {
    DateTime? now,
  }) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final eligible =
        hikes.where((hike) => hike.isUpcomingAt(currentTime)).toList()
          ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
    return eligible.isEmpty ? null : eligible.first;
  }

  static bool representsSameSchedule(UpcomingHike first, UpcomingHike second) {
    return _scheduleKey(first) == _scheduleKey(second);
  }

  static PlannedHike resolve({
    required UpcomingHike upcomingHike,
    required Iterable<Trail> liveTrails,
    required bool emergencyContactsSelected,
    required int? phoneBatteryLevel,
    Set<String>? completedChecklistItems,
    DateTime? now,
  }) {
    Trail? liveTrail;
    for (final candidate in liveTrails) {
      if (candidate.trailId == upcomingHike.trailId) {
        liveTrail = candidate;
        break;
      }
    }
    final trail = _resolvedTrail(upcomingHike, liveTrail);
    final completed = GearChecklistCatalog.sanitize(
      completedChecklistItems ??
          upcomingHike.draft?.completedChecklistItems ??
          const <String>{},
    );
    final battery = phoneBatteryLevel?.clamp(0, 100).toInt();
    return PlannedHike(
      upcomingHikeId: upcomingHike.id,
      trail: trail,
      plannedStartTime: upcomingHike.departureTime,
      expectedReturnTime: upcomingHike.expectedReturnTime,
      weatherCached: _hasFreshWeather(trail.weather, now ?? DateTime.now()),
      // Offline map packs are currently unavailable in the mobile build.
      // Never inherit the global trail flag and claim that this phone has one.
      offlineMapDownloaded: false,
      emergencyContactsSelected: emergencyContactsSelected,
      checklistCompleted: completed.length,
      checklistTotal: GearChecklistCatalog.itemCount,
      phoneBatteryLevel: battery ?? 0,
      hasKnownBatteryLevel: battery != null,
      liveLocationConfigured: upcomingHike.draft?.shareLiveLocation == true,
      locationRecordingInterval:
          upcomingHike.draft?.locationRecordingInterval ??
          HikeSessionDraft.defaultLocationRecordingInterval,
      completedChecklistItems: completed,
    ).withGearProgress();
  }

  static UpcomingHike provisionalFromConfirmedDraft({
    required HikeSessionDraft draft,
    required String creatorPhone,
    required String creatorName,
    DateTime? createdAt,
  }) {
    final now = (createdAt ?? DateTime.now()).toUtc();
    final participantPhones = <String>{
      creatorPhone.trim(),
      ...draft.teamBuddies.map((buddy) => buddy.phoneNumber.trim()),
    }.where((phone) => phone.isNotEmpty).toList();
    final id =
        'local_pending_${now.microsecondsSinceEpoch}_${draft.trail.trailId.hashCode.abs()}';
    return UpcomingHike(
      id: id,
      sessionId: id,
      trailId: draft.trail.trailId,
      trailName: draft.trail.name,
      latitude: draft.trail.latitude,
      longitude: draft.trail.longitude,
      area: draft.trail.area,
      state: draft.trail.state,
      country: draft.trail.country,
      distanceKm: draft.trail.distanceKm,
      durationMinutes: draft.trail.estimatedDurationMinutes,
      difficulty: draft.trail.difficulty,
      startPointName: draft.startPointName,
      destinationName: draft.destinationName,
      departureTime: draft.departureTime,
      expectedReturnTime: draft.expectedReturnTime,
      hikeType: draft.hikeType.name,
      participantCount: participantPhones.length,
      creatorPhone: creatorPhone,
      creatorName: creatorName,
      createdAt: now,
      participantPhones: participantPhones,
      draft: draft,
    );
  }

  static String _scheduleKey(UpcomingHike hike) {
    final creatorPhone = hike.creatorPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return jsonEncode([
      hike.trailId.trim().toLowerCase(),
      hike.departureTime.toUtc().toIso8601String(),
      hike.expectedReturnTime.toUtc().toIso8601String(),
      hike.hikeType.trim().toLowerCase(),
      hike.startPointName.trim(),
      hike.destinationName.trim(),
      creatorPhone,
    ]);
  }

  static Trail _resolvedTrail(UpcomingHike hike, Trail? liveTrail) {
    final savedTrail = hike.draft?.trail;
    var trail = savedTrail ?? liveTrail ?? _fallbackTrail(hike);
    final custom = hike.draft?.customCheckpoints;
    if (custom != null &&
        HikingRouteService.checkpointsHash(custom) !=
            HikingRouteService.checkpointsHash(trail.checkpoints)) {
      trail = trail.copyWith(
        checkpoints: custom,
        routeEncodedPolyline: '',
        routeCheckpointsHash: '',
        routeGeometryMetadata: const {},
      );
    }

    trail = trail.copyWith(
      trailId: hike.trailId.trim().isEmpty ? trail.trailId : hike.trailId,
      name: hike.trailName.trim().isEmpty ? trail.name : hike.trailName,
      area: hike.area.trim().isEmpty ? trail.area : hike.area,
      state: hike.state.trim().isEmpty ? trail.state : hike.state,
      country: hike.country.trim().isEmpty ? trail.country : hike.country,
      latitude: _validLatitude(hike.latitude) ? hike.latitude : trail.latitude,
      longitude: _validLongitude(hike.longitude)
          ? hike.longitude
          : trail.longitude,
      distanceKm: hike.distanceKm > 0 ? hike.distanceKm : trail.distanceKm,
      difficulty: hike.difficulty.trim().isEmpty
          ? trail.difficulty
          : hike.difficulty,
      estimatedDurationMinutes: hike.durationMinutes > 0
          ? hike.durationMinutes
          : trail.estimatedDurationMinutes,
    );
    if (liveTrail == null) return trail;
    return trail.copyWith(
      weather: liveTrail.weather,
      difficulty: liveTrail.difficulty,
      easyDifficultyVotes: liveTrail.easyDifficultyVotes,
      moderateDifficultyVotes: liveTrail.moderateDifficultyVotes,
      hardDifficultyVotes: liveTrail.hardDifficultyVotes,
      hazards: liveTrail.hazards,
      ratingAverage: liveTrail.ratingAverage,
      elevationGainMeters: liveTrail.elevationGainMeters,
      offlineMapAvailable: liveTrail.offlineMapAvailable,
      isVerifiedTrail: liveTrail.isVerifiedTrail,
      coverColorValue: liveTrail.coverColorValue,
      coverImageUrls: liveTrail.coverImageUrls,
      coverImageCredits: liveTrail.coverImageCredits,
      routeFilePath: trail.routeFilePath.trim().isEmpty
          ? liveTrail.routeFilePath
          : trail.routeFilePath,
    );
  }

  static Trail _fallbackTrail(UpcomingHike hike) {
    return Trail(
      trailId: hike.trailId,
      name: hike.trailName.trim().isEmpty ? 'Scheduled hike' : hike.trailName,
      area: hike.area,
      state: hike.state,
      country: hike.country,
      latitude: _validLatitude(hike.latitude) ? hike.latitude : 0,
      longitude: _validLongitude(hike.longitude) ? hike.longitude : 0,
      distanceKm: hike.distanceKm < 0 ? 0 : hike.distanceKm,
      difficulty: hike.difficulty.trim().isEmpty ? 'Unknown' : hike.difficulty,
      estimatedDurationMinutes: hike.durationMinutes < 0
          ? 0
          : hike.durationMinutes,
      elevationGainMeters: 0,
      ratingAverage: 0,
      offlineMapAvailable: false,
      offlineMapDownloaded: false,
      isVerifiedTrail: false,
      routeFilePath: '',
      coverColorValue: 0xFF34A853,
      checkpoints: const [],
      weather: TrailWeather(
        summary: 'Weather unavailable',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      hazards: const [],
    );
  }

  static bool _hasFreshWeather(TrailWeather weather, DateTime now) {
    final cachedAt = weather.cachedAt.toUtc();
    final currentTime = now.toUtc();
    if (weather.summary.trim().isEmpty ||
        !cachedAt.isAfter(DateTime.utc(2000)) ||
        cachedAt.isAfter(currentTime.add(const Duration(minutes: 5)))) {
      return false;
    }
    return currentTime.difference(cachedAt) < weatherFreshness;
  }

  static bool _validLatitude(double value) =>
      value.isFinite && value >= -90 && value <= 90;

  static bool _validLongitude(double value) =>
      value.isFinite && value >= -180 && value <= 180;
}
