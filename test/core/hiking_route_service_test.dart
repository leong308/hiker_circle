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
}
