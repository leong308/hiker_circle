import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/geoapify_service.dart';
import 'package:hiker_circle/core/services/google_routes_service.dart';
import 'package:hiker_circle/core/services/mapbox_optimization_service.dart';
import 'package:hiker_circle/core/services/open_route_service.dart';
import 'package:hiker_circle/core/services/open_meteo_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const start = TrailCheckpoint(
    name: 'Start',
    latitude: 3.1,
    longitude: 101.6,
    order: 1,
  );
  const end = TrailCheckpoint(
    name: 'End',
    latitude: 3.2,
    longitude: 101.7,
    order: 2,
  );

  test('Geoapify accepts standard LineString route coordinates', () async {
    final service = GeoapifyService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'features': [
              {
                'properties': {
                  'distance': 1500,
                  'time': 1800,
                  'legs': [
                    {'elevation_gain': 80},
                  ],
                },
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [101.6, 3.1],
                    [101.7, 3.2],
                  ],
                },
              },
            ],
          }),
          200,
        ),
      ),
    );

    final route = await service.computeHikingRoute(
      startLatitude: start.latitude,
      startLongitude: start.longitude,
      endLatitude: end.latitude,
      endLongitude: end.longitude,
    );

    expect(route.coordinates, [
      [101.6, 3.1],
      [101.7, 3.2],
    ]);
    expect(route.elevationGainMeters, 80);
  });

  test('OpenRouteService reads ascent when summary is present', () async {
    final service = OpenRouteService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'features': [
              {
                'properties': {
                  'summary': {'distance': 1200, 'duration': 900},
                  'segments': [
                    {'ascent': 125.5},
                  ],
                },
                'geometry': {
                  'coordinates': [
                    [101.6, 3.1],
                    [101.7, 3.2],
                  ],
                },
              },
            ],
          }),
          200,
        ),
      ),
    );

    final route = await service.computeFootHikingRoute(
      startLatitude: start.latitude,
      startLongitude: start.longitude,
      endLatitude: end.latitude,
      endLongitude: end.longitude,
    );

    expect(route.ascentMeters, 125.5);
    expect(route.coordinates, hasLength(2));
  });

  test('Google Routes preserves fractional protobuf durations', () async {
    final service = GoogleRoutesService(
      apiKey: 'test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'routes': [
              {
                'distanceMeters': 500,
                'duration': '90.5s',
                'polyline': {'encodedPolyline': 'encoded'},
              },
            ],
          }),
          200,
        ),
      ),
    );

    final route = await service.computeWalkingRoute(
      origin: start,
      destination: end,
    );

    expect(route.duration, const Duration(milliseconds: 90500));
    expect(route.encodedPolyline, 'encoded');
  });

  test(
    'route providers reject non-finite metrics without numeric crashes',
    () async {
      final mapbox = MapboxOptimizationService(
        accessToken: 'test',
        client: MockClient(
          (_) async => http.Response(
            '{"code":"Ok","trips":[{"distance":1e400,"duration":10,"geometry":"encoded"}]}',
            200,
          ),
        ),
      );
      final google = GoogleRoutesService(
        apiKey: 'test',
        client: MockClient(
          (_) async => http.Response(
            '{"routes":[{"distanceMeters":1e400,"duration":"1e400s","polyline":{"encodedPolyline":"encoded"}}]}',
            200,
          ),
        ),
      );

      await expectLater(
        mapbox.optimizeWalkingRoute([
          start,
          const TrailCheckpoint(
            name: 'Middle',
            latitude: 3.15,
            longitude: 101.65,
            order: 2,
          ),
          end.copyWith(order: 3),
        ]),
        throwsA(isA<MapboxOptimizationException>()),
      );
      final googleRoute = await google.computeWalkingRoute(
        origin: start,
        destination: end,
      );
      expect(googleRoute.distanceMeters, 0);
      expect(googleRoute.duration, Duration.zero);
    },
  );

  test('OpenMeteo tolerates malformed optional values', () async {
    final service = OpenMeteoService(
      client: MockClient(
        (_) async => http.Response(
          '{"current":{"temperature_2m":24,"weather_code":2,"relative_humidity_2m":"bad","apparent_temperature":null,"wind_speed_10m":1e400,"uv_index":3},"daily":{"temperature_2m_max":["bad"],"temperature_2m_min":[20],"precipitation_probability_max":[null],"weather_code":["bad"]},"hourly":{"time":["2099-01-01T00:00"],"temperature_2m":[1e400],"weather_code":[2],"precipitation_probability":[20]}}',
          200,
        ),
      ),
    );

    final weather = await service.fetchWeather(latitude: 3.1, longitude: 101.6);

    expect(weather.temperatureRange, contains('20'));
    expect(weather.temperatureRange, contains('24'));
    expect(weather.humidity, isNull);
    expect(weather.windSpeed, isNull);
    expect(weather.hourlyForecast, isEmpty);
  });
}
