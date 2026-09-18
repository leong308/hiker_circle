import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_preview_map.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/Model/recorded_hike_map_points.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  final started = DateTime.utc(2026, 9, 18);
  final first = HikeCoordinate(
    latitude: 5.123456789,
    longitude: 100.987654321,
    capturedAt: started,
  );
  final last = HikeCoordinate(
    latitude: 5.123756789,
    longitude: 100.987254321,
    capturedAt: started.add(const Duration(minutes: 1)),
  );
  ActiveHikeSession hike(
    List<HikeCoordinate> points, {
    HikeCoordinate? latest,
  }) => ActiveHikeSession(
    sessionId: 'recorded-only',
    draft: HikeSessionDraft.fromTrail(_trail()),
    startedAt: started,
    batteryLevel: 70,
    queuedUpdates: 0,
    manualPins: 0,
    checkIns: 0,
    routePoints: points,
    latestLocation: latest,
  );

  test(
    'one off-trail sample stays one point and never becomes checkpoints',
    () {
      final session = hike([first], latest: first);
      final points = recordedHikeMapPoints(session);
      final map = RoutePreviewMap(
        trail: session.trail,
        recordedTrackPoints: points,
      );
      expect(points, hasLength(1));
      expect(points.single.coordinates.lat, first.latitude);
      expect(points.single.coordinates.lng, first.longitude);
      expect(map.effectiveCheckpoints, isEmpty);
      final report = HikeSummaryReport.fromActiveHike(
        activeHike: session,
        endedAt: started.add(const Duration(minutes: 2)),
      );
      expect(report.routePointCount, 1);
      expect(report.distanceKm, 0);
    },
  );

  test(
    'off-trail movement keeps full GPS precision and chronological direction',
    () {
      final session = hike([last, first], latest: last);
      final points = recordedHikeMapPoints(session);
      expect(points, hasLength(2));
      expect(points.first.coordinates.lat, first.latitude);
      expect(points.first.coordinates.lng, first.longitude);
      expect(points.last.coordinates.lat, last.latitude);
      expect(points.last.coordinates.lng, last.longitude);
      // These checkpoints are in a different area and must never appear.
      expect(points.any((p) => p.coordinates.lat == 3), isFalse);
      expect(
        HikeSummaryReport.fromActiveHike(
          activeHike: session,
          endedAt: started.add(const Duration(minutes: 2)),
        ).routePointCount,
        points.length,
      );
    },
  );

  test('latest GPS sample is included without inventing trail geometry', () {
    expect(recordedHikeMapPoints(hike([], latest: first)), hasLength(1));
    expect(recordedHikeMapPoints(hike([first], latest: last)), hasLength(2));
    expect(recordedHikeMapPoints(hike([])), isEmpty);
    expect(
      recordedHikeMapPoints(
        hike([
          HikeCoordinate(
            latitude: double.nan,
            longitude: 100,
            capturedAt: started,
          ),
        ]),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'empty recording shows no GPS state despite valid trail checkpoints',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoutePreviewMap(
              trail: _trail(),
              recordedTrackPoints: const [],
            ),
          ),
        ),
      );
      expect(
        find.text('No GPS movement was recorded for this hike'),
        findsOneWidget,
      );
      expect(find.text('Trail coordinates are unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('normal trail preview still uses planned checkpoints', () {
    final trail = _trail();
    expect(
      RoutePreviewMap(trail: trail).effectiveCheckpoints,
      trail.checkpoints,
    );
  });
}

Trail _trail() {
  return Trail(
    trailId: 'summary-trail',
    name: 'Summary Trail',
    area: 'Test',
    state: 'Test',
    latitude: 3,
    longitude: 101,
    distanceKm: 2,
    difficulty: 'Easy',
    estimatedDurationMinutes: 60,
    elevationGainMeters: 50,
    ratingAverage: 4,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: const [
      TrailCheckpoint(name: 'Start', latitude: 3, longitude: 101, order: 1),
      TrailCheckpoint(name: 'End', latitude: 3.01, longitude: 101.01, order: 2),
    ],
    weather: TrailWeather(
      summary: '',
      temperatureRange: '',
      rainProbability: 0,
      cachedAt: DateTime.utc(2026),
    ),
    hazards: const [],
  );
}
