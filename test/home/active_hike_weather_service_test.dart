import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/active_hike_weather_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'samples current position and three distances ahead on the route',
    () async {
      final requestedLongitudes = <double>[];
      final client = MockClient((request) async {
        requestedLongitudes.add(
          double.parse(request.url.queryParameters['longitude']!),
        );
        return http.Response(
          jsonEncode({
            'current': {
              'time': '2026-06-20T08:00',
              'temperature_2m': 25.2,
              'relative_humidity_2m': 80,
              'apparent_temperature': 27.1,
              'precipitation': 0.2,
              'weather_code': 2,
              'wind_speed_10m': 5.4,
            },
          }),
          200,
        );
      });
      final trail = Trail(
        trailId: 'weather-route',
        name: 'Weather Route',
        area: 'Test',
        state: 'Test',
        latitude: 0,
        longitude: 0,
        distanceKm: 2.2,
        difficulty: 'Easy',
        estimatedDurationMinutes: 60,
        elevationGainMeters: 10,
        ratingAverage: 4,
        offlineMapAvailable: false,
        offlineMapDownloaded: false,
        isVerifiedTrail: true,
        routeFilePath: '',
        coverColorValue: 0xFF34A853,
        checkpoints: const [
          TrailCheckpoint(name: 'Start', latitude: 0, longitude: 0, order: 1),
          TrailCheckpoint(name: 'End', latitude: 0, longitude: 0.02, order: 2),
        ],
        weather: TrailWeather(
          summary: 'Unused trail forecast',
          temperatureRange: '',
          rainProbability: 0,
          cachedAt: DateTime.utc(2026, 6, 20),
        ),
        hazards: const [],
      );
      final activeHike = ActiveHikeSession(
        sessionId: 'weather-session',
        draft: HikeSessionDraft.fromTrail(trail),
        startedAt: DateTime.utc(2026, 6, 20),
        batteryLevel: 90,
        queuedUpdates: 0,
        manualPins: 0,
        checkIns: 0,
        latestLocation: HikeCoordinate(
          latitude: 0,
          longitude: 0.005,
          capturedAt: DateTime.utc(2026, 6, 20, 8),
        ),
      );

      final snapshot = await ActiveHikeWeatherService(
        client: client,
      ).fetchForHike(activeHike);

      expect(snapshot.samples, hasLength(4));
      expect(snapshot.samples.map((sample) => sample.shortLabel), [
        'Now',
        '200m',
        '500m',
        '1km',
      ]);
      expect(requestedLongitudes, hasLength(4));
      expect(requestedLongitudes[0], closeTo(0.005, 0.00001));
      expect(requestedLongitudes[1], greaterThan(requestedLongitudes[0]));
      expect(requestedLongitudes[2], greaterThan(requestedLongitudes[1]));
      expect(requestedLongitudes[3], greaterThan(requestedLongitudes[2]));
      expect(snapshot.samples.first.summary, 'Partly cloudy');
    },
  );
}
