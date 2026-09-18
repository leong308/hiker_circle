import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/hiking_route_service.dart';
import 'package:hiker_circle/core/services/trail_hazard_enrichment_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final angle in [12.4, 12.6, -12.4, -12.6]) {
    test('steep caution starts at 12.5 degrees: $angle degree slope', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'overpass.test') {
          return http.Response('{"elements":[]}', 200);
        }
        final latitudes = request.url.queryParameters['latitude']!.split(',');
        return http.Response(
          jsonEncode({
            'elevation': [
              for (final lat in latitudes)
                200 +
                    double.parse(lat) *
                        math.pi /
                        180 *
                        6371000 *
                        math.tan(angle * math.pi / 180),
            ],
          }),
          200,
        );
      });
      final service = TrailHazardEnrichmentService(
        client: client,
        overpassEndpoint: Uri.parse('https://overpass.test/api'),
        elevationEndpoint: Uri.parse('https://elevation.test/api'),
      );
      final hazards = await service.fetchForTrail(
        trail: _trail(),
        routePoints: const [LatLng(0, 101), LatLng(.004, 101)],
      );
      if (angle.abs() < 12.5) {
        expect(hazards, isEmpty);
      } else {
        expect(hazards, isNotEmpty);
        expect(
          hazards.every(
            (h) =>
                h.hazard.hazardType ==
                (angle > 0 ? 'steep_ascent' : 'steep_descent'),
          ),
          isTrue,
        );
        expect(hazards.every((h) => h.hazard.severity == 'caution'), isTrue);
      }
    });
  }

  test('maps priority OSM hazards and suppresses bridged water', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'overpass.test') {
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({
            'elements': [
              _node(1, 2.9505, 101.9005, {'ford': 'stepping_stones'}),
              _node(2, 2.9510, 101.9010, {'highway': 'ladder'}),
              _node(3, 2.9515, 101.9015, {'safety_rope': 'yes'}),
              _node(4, 2.9520, 101.9020, {
                'sac_scale': 'demanding_mountain_hiking',
              }),
              _node(5, 2.9525, 101.9025, {'natural': 'scree'}),
              _node(6, 2.9530, 101.9030, {'surface': 'mud'}),
              _node(7, 2.9535, 101.9035, {'smoothness': 'very_bad'}),
              _node(8, 2.9540, 101.9040, {'bridge': 'yes', 'highway': 'path'}),
              _node(9, 2.9540, 101.9040, {'waterway': 'stream'}),
              _node(10, 2.9580, 101.9080, {'waterway': 'river'}),
              _node(11, 2.9550, 101.9050, {
                'bridge': 'yes',
                'highway': 'primary',
              }),
            ],
          }),
          200,
        );
      }
      if (request.url.host == 'elevation.test') {
        final count = request.url.queryParameters['latitude']!
            .split(',')
            .length;
        return http.Response(
          jsonEncode({
            'elevation': [
              for (var index = 0; index < count; index++) index * 30,
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final service = TrailHazardEnrichmentService(
      client: client,
      overpassEndpoint: Uri.parse('https://overpass.test/api/interpreter'),
      elevationEndpoint: Uri.parse('https://elevation.test/v1/elevation'),
    );

    final matches = await service.fetchForTrail(
      trail: _trail(),
      routePoints: const [LatLng(2.95, 101.9), LatLng(2.96, 101.91)],
    );
    final types = matches.map((match) => match.hazard.hazardType).toSet();

    expect(
      types,
      containsAll(<String>[
        'stepping_stones',
        'ladder_section',
        'rope_assisted_section',
        'scrambling_section',
        'loose_rock',
        'muddy_surface',
        'rough_surface',
        'bridge_crossing',
        'river',
        'steep_ascent',
      ]),
    );
    expect(
      matches.where(
        (match) =>
            match.hazard.hazardType == 'stream' &&
            match.hazard.sourceFeatureId == 'node/9',
      ),
      isEmpty,
      reason: 'the water feature covered by a bridge must not get another pin',
    );
    expect(
      matches.where((match) => match.hazard.sourceFeatureId == 'node/11'),
      isEmpty,
      reason: 'a vehicle bridge crossing the trail must not become a trail pin',
    );
  });
}

Map<String, Object> _node(
  int id,
  double latitude,
  double longitude,
  Map<String, String> tags,
) {
  return {
    'type': 'node',
    'id': id,
    'lat': latitude,
    'lon': longitude,
    'tags': tags,
  };
}

Trail _trail() {
  return Trail(
    trailId: 'trail-extended',
    name: 'Extended Trail',
    area: 'Test',
    state: 'Selangor',
    latitude: 2.95,
    longitude: 101.9,
    distanceKm: 2,
    difficulty: 'Moderate',
    estimatedDurationMinutes: 60,
    elevationGainMeters: 100,
    ratingAverage: 4,
    offlineMapAvailable: true,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: const [],
    weather: TrailWeather(
      summary: 'Clear',
      temperatureRange: '24-30 C',
      rainProbability: 20,
      cachedAt: DateTime.utc(2026, 9, 12),
    ),
    hazards: const [],
  );
}
