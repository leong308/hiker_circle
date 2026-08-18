import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/active_hike_weather_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('truncated polyline safely falls back to trail checkpoints', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        jsonEncode({
          'current': {
            'time': '2026-08-04T08:00',
            'temperature_2m': 25,
            'relative_humidity_2m': 70,
            'apparent_temperature': 26,
            'precipitation': 0,
            'weather_code': 1,
            'wind_speed_10m': 4,
          },
        }),
        200,
      );
    });
    final activeHike = _activeHike(
      routeEncodedPolyline: '?',
      cachedAt: DateTime.utc(2026, 8, 4),
    );

    final snapshot = await ActiveHikeWeatherService(
      client: client,
    ).fetchForHike(activeHike);

    expect(requests, 4);
    expect(snapshot.samples, hasLength(4));
    expect(snapshot.isCachedFallback, isFalse);
  });

  test('network failure returns the durable trail weather cache', () async {
    final client = MockClient((request) async => http.Response('offline', 503));
    final activeHike = _activeHike(
      cachedAt: DateTime.utc(2026, 8, 4, 1),
      forecasts: [
        HourlyForecast(
          time: DateTime.utc(2026, 8, 4, 2),
          temperature: 24,
          precipitationProbability: 30,
          weatherCode: 2,
        ),
      ],
    );

    final snapshot = await ActiveHikeWeatherService(
      client: client,
    ).fetchForHike(activeHike);

    expect(snapshot.isCachedFallback, isTrue);
    expect(snapshot.fetchedAt, DateTime.utc(2026, 8, 4, 1));
    expect(snapshot.samples, hasLength(4));
    expect(snapshot.samples.every((sample) => sample.isCached), isTrue);
    expect(snapshot.samples.first.temperatureCelsius, 24);
    expect(snapshot.samples.first.label, contains('cached'));
  });

  test('network failure still reports an error without a real cache', () async {
    final client = MockClient((request) async => http.Response('offline', 503));
    final activeHike = _activeHike(
      cachedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );

    expect(
      () => ActiveHikeWeatherService(client: client).fetchForHike(activeHike),
      throwsA(isA<ActiveHikeWeatherException>()),
    );
  });
}

ActiveHikeSession _activeHike({
  String? routeEncodedPolyline,
  required DateTime cachedAt,
  List<HourlyForecast> forecasts = const [],
}) {
  final trail = Trail(
    trailId: 'weather-fallback-trail',
    name: 'Weather Fallback Trail',
    area: 'Test',
    state: 'Test',
    latitude: 3.1,
    longitude: 101.6,
    distanceKm: 2,
    difficulty: 'Easy',
    estimatedDurationMinutes: 60,
    elevationGainMeters: 40,
    ratingAverage: 4,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: const [
      TrailCheckpoint(name: 'Start', latitude: 3.1, longitude: 101.6, order: 1),
      TrailCheckpoint(name: 'End', latitude: 3.11, longitude: 101.62, order: 2),
    ],
    weather: TrailWeather(
      summary: 'Cloudy',
      temperatureRange: '23-28 C',
      rainProbability: 30,
      cachedAt: cachedAt,
      humidity: 78,
      windSpeed: 5,
      feelsLike: 25,
      hourlyForecast: forecasts,
    ),
    hazards: const [],
    routeEncodedPolyline: routeEncodedPolyline,
  );
  return ActiveHikeSession(
    sessionId: 'weather-fallback-session',
    draft: HikeSessionDraft.fromTrail(trail),
    startedAt: DateTime.utc(2026, 8, 4),
    batteryLevel: 90,
    queuedUpdates: 0,
    manualPins: 0,
    checkIns: 0,
  );
}
