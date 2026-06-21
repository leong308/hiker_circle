import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/mapbox_optimization_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const checkpoints = [
    TrailCheckpoint(
      name: 'Trailhead',
      latitude: 3.1000,
      longitude: 101.6000,
      order: 1,
    ),
    TrailCheckpoint(
      name: 'Waterfall',
      latitude: 3.1200,
      longitude: 101.6200,
      order: 2,
    ),
    TrailCheckpoint(
      name: 'Summit',
      latitude: 3.1400,
      longitude: 101.6400,
      order: 3,
    ),
  ];

  test('requests a detailed fixed-endpoint walking optimization', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'waypoints': [
            {'waypoint_index': 0},
            {'waypoint_index': 2},
            {'waypoint_index': 1},
          ],
          'trips': [
            {
              'distance': 4321.4,
              'duration': 2876.6,
              'geometry': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
            },
          ],
        }),
        200,
      );
    });

    final result = await MapboxOptimizationService(
      client: client,
      accessToken: 'test-token',
    ).optimizeWalkingRoute(checkpoints);

    expect(
      requestedUri.path,
      '/optimized-trips/v1/mapbox/walking/'
      '101.6,3.1;101.62,3.12;101.64,3.14',
    );
    expect(requestedUri.queryParameters['source'], 'first');
    expect(requestedUri.queryParameters['destination'], 'last');
    expect(requestedUri.queryParameters['roundtrip'], 'false');
    expect(requestedUri.queryParameters['overview'], 'full');
    expect(requestedUri.queryParameters['geometries'], 'polyline');
    expect(
      requestedUri.queryParameters['radiuses'],
      'unlimited;unlimited;unlimited',
    );
    expect(result.distanceMeters, 4321);
    expect(result.durationSeconds, 2877);
    expect(result.encodedPolyline, '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(checkpoints.map((checkpoint) => checkpoint.name), [
      'Trailhead',
      'Waterfall',
      'Summit',
    ]);
  });

  test('rejects checkpoint counts outside the app limit', () async {
    final service = MapboxOptimizationService(
      client: MockClient(
        (_) async => throw StateError('Network must not be called'),
      ),
      accessToken: 'test-token',
    );

    expect(
      () => service.optimizeWalkingRoute(checkpoints.take(2).toList()),
      throwsA(isA<MapboxOptimizationException>()),
    );
    expect(
      () => service.optimizeWalkingRoute(
        List.generate(
          13,
          (index) => TrailCheckpoint(
            name: 'Checkpoint $index',
            latitude: 3 + (index / 100),
            longitude: 101 + (index / 100),
            order: index + 1,
          ),
        ),
      ),
      throwsA(isA<MapboxOptimizationException>()),
    );
  });
}
