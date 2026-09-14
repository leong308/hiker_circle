import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/core/services/static_hazard_dataset_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory temporaryDirectory;
  late LocalSessionDatabase database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hiker_circle_hazard_test_',
    );
    database = LocalSessionDatabase(
      databasePath: path.join(temporaryDirectory.path, 'hazards.db'),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('downloads, classifies, and stores compact trail hazard points', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['layers'], 'waterway,structure,road');
      expect(request.url.queryParameters['access_token'], 'test-token');
      return http.Response(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'id': 101,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.90001, 2.95001],
              },
              'properties': {
                'class': 'river',
                'tilequery': {
                  'distance': 5.0,
                  'geometry': 'linestring',
                  'layer': 'waterway',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 202,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.9002, 2.9502],
              },
              'properties': {
                'class': 'cliff',
                'tilequery': {
                  'distance': 40.0,
                  'geometry': 'linestring',
                  'layer': 'structure',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 102,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.901, 2.951],
              },
              'properties': {
                'class': 'stream',
                'tilequery': {
                  'distance': 7.0,
                  'geometry': 'linestring',
                  'layer': 'waterway',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 103,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.9023, 2.952],
              },
              'properties': {
                'class': 'river',
                'tilequery': {
                  'distance': 11.0,
                  'geometry': 'linestring',
                  'layer': 'waterway',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 303,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.90002, 2.95002],
              },
              'properties': {
                'class': 'path',
                'structure': 'bridge',
                'tilequery': {
                  'distance': 3.0,
                  'geometry': 'linestring',
                  'layer': 'road',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 104,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.906, 2.955],
              },
              'properties': {
                'class': 'stream',
                'tilequery': {
                  'distance': 3.0,
                  'geometry': 'linestring',
                  'layer': 'waterway',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 304,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.906, 2.955],
              },
              'properties': {
                'class': 'path',
                'structure': 'bridge',
                'tilequery': {
                  'distance': 3.0,
                  'geometry': 'linestring',
                  'layer': 'road',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 305,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.9015, 2.9515],
              },
              'properties': {
                'class': 'street_limited',
                'type': 'unclassified',
                'structure': 'bridge',
                'tilequery': {
                  'distance': 0.0,
                  'geometry': 'linestring',
                  'layer': 'road',
                },
              },
            },
            {
              'type': 'Feature',
              'id': 404,
              'geometry': {
                'type': 'Point',
                'coordinates': [101.903, 2.953],
              },
              'properties': {
                'class': 'path',
                'structure': 'ford',
                'tilequery': {
                  'distance': 4.0,
                  'geometry': 'linestring',
                  'layer': 'road',
                },
              },
            },
          ],
        }),
        200,
      );
    });
    final service = StaticHazardDatasetService(
      database: database,
      client: client,
      accessToken: 'test-token',
      enableExtendedHazards: false,
    );

    final summary = await service.downloadForTrails([_trail()]);
    final matches = await database.loadStaticHazardsForTrail('trail-1');

    expect(summary.hazardCount, 4);
    expect(matches.map((match) => match.hazard.hazardType).toSet(), {
      'stream',
      'cliff',
      'bridge_crossing',
      'ford_crossing',
    });
    final water = matches.firstWhere(
      (match) => match.hazard.hazardType == 'stream',
    );
    expect(water.relationship, 'possible_crossing');
    expect(water.hazard.description, isNot(contains('crocodile')));
    expect(water.hazard.safetyGuidance, contains('Do not infer wildlife'));
    expect(
      matches.any((match) => match.hazard.sourceFeatureId == '101'),
      isFalse,
      reason: 'water covered by a mapped bridge must be suppressed',
    );
    expect(
      matches.any((match) => match.hazard.sourceFeatureId == '103'),
      isFalse,
      reason: 'water farther than 10 m from the sampled trail is hidden',
    );
    final bridge = matches.firstWhere(
      (match) => match.hazard.hazardType == 'bridge_crossing',
    );
    expect(bridge.relationship, 'bridge_crossing');
    expect(bridge.hazard.description, contains('bridge over a river'));
    expect(
      matches.any((match) => match.hazard.sourceFeatureId == '304'),
      isFalse,
      reason: 'a bridge near the sample but off the actual route is hidden',
    );
    expect(
      matches.any((match) => match.hazard.sourceFeatureId == '305'),
      isFalse,
      reason:
          'a vehicle bridge crossing above or below the trail is not a hiking bridge',
    );
    expect(
      matches
          .singleWhere((match) => match.hazard.hazardType == 'ford_crossing')
          .relationship,
      'ford_crossing',
    );
  });

  test('automatically downloads once then reuses the SQLite scan', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({'type': 'FeatureCollection', 'features': const []}),
        200,
      );
    });
    final service = StaticHazardDatasetService(
      database: database,
      client: client,
      accessToken: 'test-token',
      enableExtendedHazards: false,
    );

    expect(await service.ensureForTrail(_trail()), isEmpty);
    expect(requestCount, 2);
    expect(await database.loadStaticHazardScanTime('trail-1'), isNotNull);

    expect(await service.ensureForTrail(_trail()), isEmpty);
    expect(requestCount, 2);
  });
}

Trail _trail() {
  return Trail(
    trailId: 'trail-1',
    name: 'Test Trail',
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
    checkpoints: const [
      TrailCheckpoint(
        name: 'Start',
        latitude: 2.95,
        longitude: 101.9,
        order: 1,
      ),
      TrailCheckpoint(name: 'End', latitude: 2.96, longitude: 101.91, order: 2),
    ],
    weather: TrailWeather(
      summary: 'Clear',
      temperatureRange: '24–30°C',
      rainProbability: 20,
      cachedAt: DateTime.utc(2026, 9, 11),
    ),
    hazards: const [],
  );
}
