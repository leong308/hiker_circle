import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('active hike snapshot survives a JSON round trip', () {
    final trail = Trail(
      trailId: 'trail-persist',
      name: 'Persistent Ridge',
      area: 'Bentong',
      state: 'Pahang',
      latitude: 3.5,
      longitude: 101.9,
      distanceKm: 7.4,
      difficulty: 'Moderate',
      estimatedDurationMinutes: 210,
      elevationGainMeters: 620,
      ratingAverage: 4.8,
      offlineMapAvailable: true,
      offlineMapDownloaded: true,
      isVerifiedTrail: true,
      routeFilePath: 'offline/persistent-ridge.mbtiles',
      coverColorValue: 0xFF237A4B,
      coverImageUrls: const ['https://example.com/one.jpg'],
      checkpoints: const [
        TrailCheckpoint(
          name: 'Start',
          latitude: 3.5,
          longitude: 101.9,
          order: 1,
        ),
        TrailCheckpoint(
          name: 'Summit',
          latitude: 3.52,
          longitude: 101.92,
          order: 2,
        ),
      ],
      weather: TrailWeather(
        summary: 'Cloudy',
        temperatureRange: '22-28 C',
        rainProbability: 35,
        cachedAt: DateTime.utc(2026, 6, 20, 1),
        humidity: 82,
        windSpeed: 8.5,
        hourlyForecast: [
          HourlyForecast(
            time: DateTime.utc(2026, 6, 20, 2),
            temperature: 24,
            precipitationProbability: 35,
            weatherCode: 2,
          ),
        ],
      ),
      hazards: [
        TrailHazard(
          type: 'Slippery',
          description: 'Wet rocks',
          severity: 'Moderate',
          locationLabel: 'Summit approach',
          reportedAt: DateTime.utc(2026, 6, 19),
        ),
      ],
      routeEncodedPolyline: 'encoded-route',
      routeCheckpointsHash: 'route-hash',
    );
    final draft = HikeSessionDraft.fromTrail(trail).copyWith(
      hikeType: HikeType.team,
      teamBuddies: const [
        TeamHikeBuddy(
          name: 'Amin',
          handle: '@amin',
          phoneNumber: '+60111111111',
        ),
      ],
      customCheckpoints: trail.checkpoints,
    );
    final teamSession = TeamHikeSession(
      id: 'team-1',
      activeHikeSessionId: 'hike-1',
      hostPhoneNumber: '+60122222222',
      trailId: trail.trailId,
      trailName: trail.name,
      phase: TeamHikePhase.active,
      participants: const [],
      startedAt: DateTime.utc(2026, 6, 20, 1, 30),
    );
    final latest = HikeCoordinate(
      latitude: 3.51,
      longitude: 101.91,
      accuracyMeters: 4,
      capturedAt: DateTime.utc(2026, 6, 20, 2),
    );
    final activeHike = ActiveHikeSession(
      sessionId: 'hike-1',
      draft: draft,
      startedAt: DateTime.utc(2026, 6, 20, 1, 30),
      batteryLevel: 76,
      batteryStartedLevel: 94,
      queuedUpdates: 2,
      manualPins: 1,
      checkIns: 3,
      latestLocation: latest,
      routePoints: [
        HikeCoordinate(
          latitude: 3.5,
          longitude: 101.9,
          capturedAt: DateTime.utc(2026, 6, 20, 1, 30),
        ),
        latest,
      ],
      manualPinLocations: [
        HikeManualPin(
          id: 'pin-1',
          coordinate: latest,
          pinnedAt: DateTime.utc(2026, 6, 20, 2),
        ),
      ],
      checkInRecords: [
        HikeCheckInRecord(
          id: 'check-in-1',
          checkedInAt: DateTime.utc(2026, 6, 20, 1, 50),
          coordinate: latest,
        ),
      ],
      teamHikeSessionId: teamSession.id,
      teamHikeSession: teamSession,
    );

    final encoded = jsonEncode(activeHike.toPersistence());
    final restored = ActiveHikeSession.fromPersistence(
      Map<String, dynamic>.from(jsonDecode(encoded) as Map),
    );

    expect(restored.sessionId, activeHike.sessionId);
    expect(restored.startedAt, activeHike.startedAt);
    expect(restored.batteryLevel, 76);
    expect(restored.batteryStartedLevel, 94);
    expect(restored.checkIns, 3);
    expect(restored.routePoints, hasLength(2));
    expect(restored.manualPinLocations.single.id, 'pin-1');
    expect(restored.checkInRecords.single.id, 'check-in-1');
    expect(restored.latestLocation?.accuracyMeters, 4);
    expect(restored.teamHikeSession?.phase, TeamHikePhase.active);
    expect(restored.draft.hikeType, HikeType.team);
    expect(restored.draft.teamBuddies.single.name, 'Amin');
    expect(restored.trail.difficulty, 'Moderate');
    expect(restored.trail.coverImageUrls, hasLength(1));
    expect(restored.trail.weather.hourlyForecast, hasLength(1));
    expect(restored.trail.hazards.single.description, 'Wet rocks');
    expect(restored.trail.routeEncodedPolyline, 'encoded-route');
  });
}
