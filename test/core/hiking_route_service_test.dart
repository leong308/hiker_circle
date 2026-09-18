import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/hiking_route_service.dart';
import 'package:hiker_circle/core/services/open_topo_data_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test(
    'uses a valid route stored with the trail without waiting for network',
    () async {
      const encodedPolyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final trail = Trail(
        trailId: 'stored-route',
        name: 'Stored Route',
        area: 'Test Area',
        state: 'Test State',
        latitude: 38.5,
        longitude: -120.2,
        distanceKm: 7.2,
        difficulty: 'Moderate',
        estimatedDurationMinutes: 150,
        elevationGainMeters: 320,
        minElevationMeters: 84,
        maxElevationMeters: 412,
        ratingAverage: 4.5,
        offlineMapAvailable: false,
        offlineMapDownloaded: false,
        isVerifiedTrail: true,
        routeFilePath: '',
        coverColorValue: 0xFF34A853,
        checkpoints: const [
          TrailCheckpoint(
            name: 'Start',
            latitude: 38.5,
            longitude: -120.2,
            order: 1,
          ),
          TrailCheckpoint(
            name: 'End',
            latitude: 43.252,
            longitude: -126.453,
            order: 2,
          ),
        ],
        weather: TrailWeather(
          summary: '',
          temperatureRange: '',
          rainProbability: 0,
          cachedAt: DateTime.utc(2026),
        ),
        hazards: const [],
        routeEncodedPolyline: encodedPolyline,
      );

      final result = await HikingRouteService()
          .findHikingRouteForTrailWithCache(trail);

      expect(result.encodedPolyline, encodedPolyline);
      expect(result.sourceLabel, 'Saved trail route');
      expect(result.distanceMeters, 7200);
      expect(result.minElevationMeters, 84);
      expect(result.maxElevationMeters, 412);
      expect(result.elevationRangeLabel, '84 m – 412 m');
    },
  );

  test('elevation profile exposes altitude range separately from gain', () {
    const profile = OpenTopoDataResult(elevations: [120, 95, 160, 140, 190]);

    expect(profile.minimumElevationMeters, 95);
    expect(profile.maximumElevationMeters, 190);
    expect(profile.elevationGainMeters, 115);
  });
  test('checkpoint fingerprint is portable and ignores label-only edits', () {
    const points = [
      TrailCheckpoint(
        name: 'Start',
        latitude: 5.41,
        longitude: 100.27,
        order: 1,
      ),
      TrailCheckpoint(
        name: 'Finish',
        latitude: 5.42,
        longitude: 100.28,
        order: 2,
      ),
    ];
    expect(
      HikingRouteService.checkpointsHash(points),
      'sha256:aa81bdb1669aa970b8c83b8d57f5dc52cc166376c0e7c5062350624fada02ad0',
    );
    final trail = Trail.fromPersistence({
      'routeCheckpointsHash': HikingRouteService.checkpointsHash(points),
      'checkpoints': [
        {'name': 'Renamed', 'latitude': 5.41, 'longitude': 100.27, 'order': 1},
        {'name': 'Finish', 'latitude': 5.42, 'longitude': 100.28, 'order': 2},
      ],
    });
    expect(HikingRouteService.savedRouteMatchesCheckpoints(trail), isTrue);
    expect(
      HikingRouteService.savedRouteMatchesCheckpoints(
        trail.copyWith(
          checkpoints: [
            points.first,
            const TrailCheckpoint(
              name: 'Moved',
              latitude: 5.45,
              longitude: 100.28,
              order: 2,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });
}
