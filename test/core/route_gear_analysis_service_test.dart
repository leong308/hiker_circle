import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/core/services/hiking_route_service.dart';
import 'package:hiker_circle/core/services/route_gear_analysis_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

LatLng pt(double x, double y) => LatLng(y / 111320, x / 111320);
Map<String, dynamic> feature(
  int id,
  Map<String, String> tags,
  List<LatLng> points,
) => {
  'type': 'way',
  'id': id,
  'tags': tags,
  'geometry': points
      .map((p) => {'lat': p.latitude, 'lon': p.longitude})
      .toList(),
};

class MemoryDb extends LocalSessionDatabase {
  final values = <String, Object?>{};
  @override
  Future<Object?> loadLocalPreference({
    required String ownerPhoneNumber,
    required String key,
  }) async => values[key];
  @override
  Future<void> saveLocalPreference({
    required String ownerPhoneNumber,
    required String key,
    required Object? value,
    bool isDirty = false,
  }) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final route = [pt(0, 0), pt(100, 0)];
  test(
    '50 m corridor uses segments, excludes 51 m, and distinguishes nearby water',
    () {
      final inside = RouteGearAnalysisService.classify(route, [
        feature(1, {'waterway': 'stream'}, [pt(20, 49), pt(80, 49)]),
      ]);
      expect(inside.waterNearby, true);
      expect(inside.possibleCrossing, false);
      final outside = RouteGearAnalysisService.classify(route, [
        feature(1, {'waterway': 'stream'}, [pt(20, 51), pt(80, 51)]),
      ]);
      expect(outside.waterNearby, false);
      final crossing = RouteGearAnalysisService.classify(route, [
        feature(2, {'waterway': 'river'}, [pt(50, -100), pt(50, 100)]),
      ]);
      expect(
        crossing.possibleCrossing,
        true,
      ); // Both river vertices are far away.
    },
  );
  test(
    'walking bridge suppresses crossing; road bridge and separate crossing do not',
    () {
      final river = feature(
        1,
        {'waterway': 'river'},
        [pt(50, -100), pt(50, 100)],
      );
      final bridge = feature(
        2,
        {'bridge': 'yes', 'highway': 'footway'},
        [pt(45, 0), pt(55, 0)],
      );
      expect(
        RouteGearAnalysisService.classify(route, [
          river,
          bridge,
        ]).possibleCrossing,
        false,
      );
      final road = feature(
        2,
        {'bridge': 'yes', 'highway': 'motorway'},
        [pt(45, 0), pt(55, 0)],
      );
      expect(
        RouteGearAnalysisService.classify(route, [
          river,
          road,
        ]).possibleCrossing,
        true,
      );
      final loop = [pt(0, 0), pt(100, 0), pt(100, 70), pt(0, 70)];
      expect(
        RouteGearAnalysisService.classify(loop, [
          river,
          bridge,
        ]).possibleCrossing,
        true,
      );
    },
  );
  test(
    'surface tags drive rough gear only inside corridor and never guess phone coverage',
    () {
      final data = RouteGearAnalysisService.classify(route, [
        feature(1, {'highway': 'path', 'surface': 'mud'}, route),
      ]);
      expect(data.rough, true);
      expect(data.muddy, true);
      expect(data.surfaceMapped, true);
      expect(
        RouteGearAnalysisService.classify(route, [
          feature(
            1,
            {'highway': 'path', 'surface': 'mud'},
            [pt(0, 51), pt(100, 51)],
          ),
        ]).rough,
        false,
      );
      expect(RouteGearAnalysisService.classify(route, []).surfaceMapped, false);
    },
  );
  test(
    'successful results persist, repeated requests reuse cache, route changes invalidate cache',
    () async {
      final db = MemoryDb();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(
          Uri.splitQueryString(request.body)['data'],
          contains('around:56'),
        );
        return http.Response(
          jsonEncode({
            'elements': [
              feature(1, {'waterway': 'river'}, [pt(50, -100), pt(50, 100)]),
            ],
          }),
          200,
        );
      });
      Future<HikingRouteResult> loader(Trail t) async => HikingRouteResult(
        distanceMeters: 100,
        duration: const Duration(minutes: 10),
        encodedPolyline: PolylineCodec.encode(
          t.trailId == 'changed' ? [pt(1000, 0), pt(1100, 0)] : route,
        ),
      );
      final trail = Trail.fromPersistence({'trailId': 'test'});
      final service = RouteGearAnalysisService(
        database: db,
        client: client,
        routeLoader: loader,
      );
      final results = await Future.wait([
        service.analyze(trail),
        service.analyze(trail),
      ]);
      expect(calls, 1);
      expect(results.first.possibleCrossing, true);
      await RouteGearAnalysisService(
        database: db,
        client: client,
        routeLoader: loader,
      ).analyze(trail);
      expect(calls, 1);
      final changed = await service.analyze(
        Trail.fromPersistence({'trailId': 'changed'}),
      );
      expect(calls, 2);
      expect(changed.possibleCrossing, false);
    },
  );
  test('provider failure is unavailable rather than a clear route', () async {
    final service = RouteGearAnalysisService(
      database: MemoryDb(),
      client: MockClient((_) async => http.Response('busy', 429)),
      routeLoader: (_) async => HikingRouteResult(
        distanceMeters: 100,
        duration: const Duration(minutes: 10),
        encodedPolyline: PolylineCodec.encode(route),
      ),
    );
    final result = await service.analyze(
      Trail.fromPersistence({'trailId': 'test'}),
    );
    expect(result.status, 'unavailable');
    expect(result.usable, false);
  });
}
