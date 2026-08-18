import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/planned_hike_state_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('selectNext uses the nearest non-expired scheduled hike', () {
    final now = DateTime.utc(2026, 8, 4, 8);
    final expired = _upcoming(
      id: 'expired',
      departureTime: now.subtract(const Duration(minutes: 11)),
    );
    final later = _upcoming(
      id: 'later',
      departureTime: now.add(const Duration(hours: 4)),
    );
    final next = _upcoming(
      id: 'next',
      departureTime: now.add(const Duration(hours: 1)),
    );

    expect(
      PlannedHikeStateResolver.selectNext([later, expired, next], now: now)?.id,
      'next',
    );
  });

  test('confirmed remote hike wins over its local pending duplicate', () {
    final departure = DateTime.utc(2026, 8, 5, 1);
    final pending = _upcoming(id: 'local_pending_1', departureTime: departure);
    final confirmed = _upcoming(id: 'cloud-1', departureTime: departure);

    final merged = PlannedHikeStateResolver.mergeUpcomingHikes(
      remote: [confirmed],
      cached: [pending],
      retainUnconfirmedCachedHikes: true,
    );

    expect(merged.map((hike) => hike.id), ['cloud-1']);
  });

  test('remote metadata keeps the preferred local pending safety draft', () {
    final departure = DateTime.utc(2026, 8, 5, 1);
    final olderDraft =
        HikeSessionDraft.fromTrail(
          _trail(cachedAt: DateTime.utc(2026, 8, 4)),
        ).copyWith(
          departureTime: departure,
          expectedReturnTime: departure.add(const Duration(hours: 4)),
          shareLiveLocation: false,
        );
    final privatePendingDraft = olderDraft.copyWith(
      shareLiveLocation: true,
      fallDetectionEnabled: true,
      duressEnabled: true,
      emergencyContactNames: const ['Private contact'],
    );
    final cachedConfirmed = _upcoming(
      id: 'cached-cloud-copy',
      departureTime: departure,
      draft: olderDraft,
      creatorName: 'Cached host',
    );
    final pending = _upcoming(
      id: 'local_pending_2',
      departureTime: departure,
      draft: privatePendingDraft,
      creatorName: 'Pending host',
    );
    final remote = _upcoming(
      id: 'cloud-confirmed',
      departureTime: departure,
      creatorName: 'Authoritative host',
    );

    final merged = PlannedHikeStateResolver.mergeUpcomingHikes(
      remote: [remote],
      cached: [cachedConfirmed, pending],
      retainUnconfirmedCachedHikes: false,
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, 'cloud-confirmed');
    expect(merged.single.creatorName, 'Authoritative host');
    expect(merged.single.draft?.shareLiveLocation, isTrue);
    expect(merged.single.draft?.fallDetectionEnabled, isTrue);
    expect(merged.single.draft?.duressEnabled, isTrue);
    expect(merged.single.draft?.emergencyContactNames, ['Private contact']);
  });

  test('resolver derives truthful readiness from current local state', () {
    final now = DateTime.utc(2026, 8, 4, 8);
    final savedTrail = _trail(cachedAt: now.subtract(const Duration(days: 1)));
    final liveTrail =
        _trail(cachedAt: now.subtract(const Duration(minutes: 20))).copyWith(
          weather: TrailWeather(
            summary: 'Current rain forecast',
            temperatureRange: '24-27 C',
            rainProbability: 70,
            cachedAt: now.subtract(const Duration(minutes: 20)),
          ),
        );
    final draft = HikeSessionDraft.fromTrail(savedTrail).copyWith(
      departureTime: now.add(const Duration(hours: 2)),
      expectedReturnTime: now.add(const Duration(hours: 6)),
      shareLiveLocation: true,
    );
    final upcoming = _upcoming(
      id: 'cloud-1',
      departureTime: draft.departureTime,
      draft: draft,
    );

    final planned = PlannedHikeStateResolver.resolve(
      upcomingHike: upcoming,
      liveTrails: [liveTrail],
      emergencyContactsSelected: false,
      phoneBatteryLevel: null,
      completedChecklistItems: const {
        'Charged phone',
        'forged checklist entry',
      },
      now: now,
    );

    expect(planned.upcomingHikeId, upcoming.id);
    expect(planned.trail.weather.summary, 'Current rain forecast');
    expect(planned.weatherCached, isTrue);
    expect(planned.hasKnownBatteryLevel, isFalse);
    expect(planned.liveLocationConfigured, isTrue);
    expect(planned.completedChecklistItems, {'Charged phone'});
    expect(planned.checklistCompleted, 1);
    expect(
      planned.missingPreparationItems,
      contains('No emergency contact selected'),
    );
    expect(
      planned.missingPreparationItems,
      contains('Phone battery level unavailable'),
    );
  });

  test('stale weather is not reported as prepared', () {
    final now = DateTime.utc(2026, 8, 4, 8);
    final trail = _trail(cachedAt: now.subtract(const Duration(hours: 5)));
    final draft = HikeSessionDraft.fromTrail(trail).copyWith(
      departureTime: now.add(const Duration(hours: 1)),
      expectedReturnTime: now.add(const Duration(hours: 4)),
    );
    final planned = PlannedHikeStateResolver.resolve(
      upcomingHike: _upcoming(
        id: 'stale-weather',
        departureTime: draft.departureTime,
        draft: draft,
      ),
      liveTrails: const [],
      emergencyContactsSelected: true,
      phoneBatteryLevel: 85,
      now: now,
    );

    expect(planned.weatherCached, isFalse);
    expect(
      planned.missingPreparationItems,
      contains('Weather forecast not cached'),
    );
  });
}

UpcomingHike _upcoming({
  required String id,
  required DateTime departureTime,
  HikeSessionDraft? draft,
  String creatorName = 'Test Hiker',
}) {
  final trail = draft?.trail ?? _trail(cachedAt: DateTime.utc(2026, 8, 4));
  return UpcomingHike(
    id: id,
    sessionId: id,
    trailId: trail.trailId,
    trailName: trail.name,
    latitude: trail.latitude,
    longitude: trail.longitude,
    area: trail.area,
    state: trail.state,
    distanceKm: trail.distanceKm,
    durationMinutes: trail.estimatedDurationMinutes,
    difficulty: trail.difficulty,
    startPointName: 'Start',
    destinationName: 'Summit',
    departureTime: departureTime,
    expectedReturnTime: departureTime.add(const Duration(hours: 4)),
    hikeType: 'solo',
    participantCount: 1,
    creatorPhone: '+60111111111',
    creatorName: creatorName,
    createdAt: DateTime.utc(2026, 8, 4),
    participantPhones: const ['+60111111111'],
    draft: draft,
  );
}

Trail _trail({required DateTime cachedAt}) {
  return Trail(
    trailId: 'trail-1',
    name: 'Persistence Trail',
    area: 'Test',
    state: 'Test',
    latitude: 3.1,
    longitude: 101.6,
    distanceKm: 5,
    difficulty: 'Moderate',
    estimatedDurationMinutes: 120,
    elevationGainMeters: 300,
    ratingAverage: 4.5,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: const [
      TrailCheckpoint(name: 'Start', latitude: 3.1, longitude: 101.6, order: 1),
      TrailCheckpoint(name: 'Mid', latitude: 3.11, longitude: 101.61, order: 2),
      TrailCheckpoint(
        name: 'Summit',
        latitude: 3.12,
        longitude: 101.62,
        order: 3,
      ),
    ],
    weather: TrailWeather(
      summary: 'Clear',
      temperatureRange: '24-28 C',
      rainProbability: 10,
      cachedAt: cachedAt,
    ),
    hazards: const [],
  );
}
