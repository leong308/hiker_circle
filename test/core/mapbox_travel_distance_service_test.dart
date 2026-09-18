import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/mapbox_travel_distance_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response matrix(List<num?> distances, {List<num>? snaps}) => http.Response(
  jsonEncode({
    'code': 'Ok',
    'distances': [distances],
    'sources': [
      {'distance': 5},
    ],
    'destinations': [
      for (var i = 0; i < distances.length; i++) {'distance': snaps?[i] ?? 5},
    ],
  }),
  200,
);

void main() {
  const destination = (id: 'trail', latitude: 5.41, longitude: 100.27);

  test(
    'uses driving distance in km, caches, and refreshes for a moved origin',
    () async {
      var requests = 0;
      final service = MapboxTravelDistanceService(
        accessToken: 'test',
        client: MockClient((request) async {
          requests++;
          expect(
            request.url.path,
            contains('/mapbox/driving/101.7,3.1;100.27,5.41'),
          );
          expect(request.url.queryParameters['sources'], '0');
          expect(request.url.queryParameters['destinations'], '0;1');
          expect(request.url.queryParameters['annotations'], 'distance');
          expect(
            request.url.queryParameters.containsKey('fallback_speed'),
            isFalse,
          );
          return matrix([0, 385400]);
        }),
      );
      for (var i = 0; i < 2; i++) {
        expect(
          await service.distancesKm(
            latitude: 3.1,
            longitude: 101.7,
            destinations: [destination],
          ),
          {'trail': 385.4},
        );
      }
      expect(requests, 1);
    },
  );

  test(
    'batches 25 trails and preserves null routes without aerial fallback',
    () async {
      final sizes = <int>[];
      final service = MapboxTravelDistanceService(
        accessToken: 'test',
        client: MockClient((request) async {
          final count = request.url.path.split('/').last.split(';').length;
          sizes.add(count);
          if (count == 2) return matrix([0, null]);
          return matrix(List.generate(24, (i) => (i + 1) * 1000));
        }),
      );
      final result = await service.distancesKm(
        latitude: 3,
        longitude: 101,
        destinations: [
          for (var i = 0; i < 25; i++)
            (id: '$i', latitude: 4 + i / 100, longitude: 102),
        ],
      );
      expect(sizes, [25, 2]);
      expect(result['0'], 1);
      expect(result['23'], 24);
      expect(result['24'], isNull);
    },
  );

  test(
    'does not reuse a distance after origin or destination changes',
    () async {
      var calls = 0;
      final service = MapboxTravelDistanceService(
        accessToken: 'test',
        client: MockClient((_) async => matrix([0, ++calls * 1000])),
      );
      expect(
        (await service.distancesKm(
          latitude: 3,
          longitude: 101,
          destinations: [destination],
        ))['trail'],
        1,
      );
      expect(
        (await service.distancesKm(
          latitude: 3.2,
          longitude: 101,
          destinations: [destination],
        ))['trail'],
        2,
      );
      expect(
        (await service.distancesKm(
          latitude: 3.2,
          longitude: 101,
          destinations: [(id: 'trail', latitude: 5.5, longitude: 100.27)],
        ))['trail'],
        3,
      );
    },
  );

  test('rejects distant road snaps and retries temporary failures', () async {
    var calls = 0;
    final service = MapboxTravelDistanceService(
      accessToken: 'test',
      client: MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('unavailable', 503);
        return matrix([0, 12000], snaps: [0, 2000]);
      }),
    );
    for (var i = 0; i < 2; i++) {
      expect(
        (await service.distancesKm(
          latitude: 3,
          longitude: 101,
          destinations: [destination],
        ))['trail'],
        isNull,
      );
    }
    expect(calls, 2);
  });

  test('invalid coordinates and missing token never make a request', () async {
    final client = MockClient(
      (_) async => throw StateError('Unexpected request'),
    );
    final service = MapboxTravelDistanceService(
      accessToken: 'test',
      client: client,
    );
    expect(
      await service.distancesKm(
        latitude: double.nan,
        longitude: 101,
        destinations: [destination],
      ),
      {'trail': null},
    );
    expect(
      await MapboxTravelDistanceService(
        accessToken: '',
        client: client,
      ).distancesKm(latitude: 3, longitude: 101, destinations: [destination]),
      {'trail': null},
    );
  });
}
