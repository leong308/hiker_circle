import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hiker_circle/home/Data/active_hike_weather_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/start_hike_wizard_page.dart';
import 'package:hiker_circle/core/widgets/route_preview_map.dart';
import 'package:hiker_circle/core/services/trail_geometry_storage.dart';
import 'package:hiker_circle/core/services/hiking_route_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/Model/recorded_trail_request.dart';

Trail unlisted() => Trail.fromPersistence({
  'trailId': 'unlisted_1234567890',
  'routeProvider': 'recorded-location-hike',
  'name': 'Hike from current location',
  'latitude': 5.1,
  'longitude': 100.1,
  'estimatedDurationMinutes': 120,
});
void main() {
  test(
    'unlisted mode survives persistence and disables reference-route deviation',
    () {
      final trail = unlisted();
      final draft = HikeSessionDraft.fromTrail(trail);
      expect(draft.pathDeviationEnabled, isFalse);
      expect(draft.effectiveCheckpoints, isEmpty);
      expect(
        HikeSessionDraft.fromPersistence(
          draft.toPersistence(),
        ).trail.isUnlisted,
        isTrue,
      );
    },
  );
  test(
    'location-only weather makes exactly one request at the current GPS position',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.queryParameters['latitude'], '5.20000');
        expect(request.url.queryParameters['longitude'], '100.20000');
        return http.Response(
          jsonEncode({
            'current': {
              'time': '2026-10-12T08:00',
              'temperature_2m': 25,
              'relative_humidity_2m': 80,
              'apparent_temperature': 27,
              'precipitation': 0.1,
              'weather_code': 2,
              'wind_speed_10m': 10,
            },
          }),
          200,
        );
      });
      final hike =
          ActiveHikeSession.fromDraft(
            HikeSessionDraft.fromTrail(unlisted()),
          ).copyWith(
            latestLocation: HikeCoordinate(
              latitude: 5.2,
              longitude: 100.2,
              capturedAt: DateTime.now(),
            ),
          );
      final weather = await ActiveHikeWeatherService(
        client: client,
      ).fetchForHike(hike);
      expect(requests, 1);
      expect(weather.samples, hasLength(1));
      expect(weather.samples.single.distanceAheadMeters, 0);
      client.close();
    },
  );
  test(
    'unknown routes cannot clone starting-point cached weather into conditions ahead',
    () async {
      final client = MockClient((_) async => http.Response('offline', 503));
      final hike = ActiveHikeSession.fromDraft(
        HikeSessionDraft.fromTrail(unlisted()),
      );
      expect(
        () => ActiveHikeWeatherService(client: client).fetchForHike(hike),
        throwsA(isA<ActiveHikeWeatherException>()),
      );
      client.close();
    },
  );
  test(
    'admin candidates preserve recording order and use the normal checkpoint hash',
    () {
      final points = [
        for (var i = 0; i < 5; i++)
          HikeCoordinate(
            latitude: 5.123456789 + i * .001,
            longitude: 100.123456789 + i * .001,
            capturedAt: DateTime.utc(2026, 10, 12, 8, i),
            altitudeMeters: 50 + i.toDouble(),
          ),
      ];
      final candidate = recordedTrailCandidate({
        'requestId': 'request',
        'proposed': {
          'name': 'New trail',
          'area': 'Forest',
          'state': 'Penang',
          'country': 'Malaysia',
        },
        'durationMinutes': 60,
        'checkpoints': [
          for (final i in [0, 2, 4])
            {
              'name': 'Stop $i',
              'order': [0, 2, 4].indexOf(i) + 1,
              'latitude': points[i].latitude,
              'longitude': points[i].longitude,
            },
        ],
      }, points);
      expect(candidate.isUnlisted, isFalse);
      expect(candidate.checkpoints[1].latitude, points[2].latitude);
      expect(
        HikingRouteService.savedRouteMatchesCheckpoints(candidate),
        isTrue,
      );
      expect(
        PolylineCodec.decode(candidate.routeEncodedPolyline!),
        hasLength(5),
      );
      expect(candidate.toFirestore()['checkpoints'], hasLength(3));
    },
  );
  test(
    'native geometry retains full coordinate precision and chunks long recordings without dropping points',
    () {
      final points = [
        for (var i = 0; i < 20000; i++)
          {
            'lat': 5.123456789 + i * .000001,
            'lon': 100.123456789 + i * .000001,
            'ele': 50.123456789,
          },
      ];
      final geometry = TrailGeometryStorage.fromCoordinates(points);
      expect(geometry.points, points);
      expect(geometry.isChunked, isTrue);
      expect(geometry.chunks.expand((p) => p).toList(), points);
      expect(geometry.document('now').containsKey('points'), isFalse);
      expect(
        geometry.metadata('trails/new/routeGeometry/path', 'now')['pointCount'],
        20000,
      );
      expect(
        TrailGeometryStorage.fromPolyline(geometry.encodedPolyline).checksum,
        geometry.checksum,
      );
    },
  );
  testWidgets('location hike skips the route preview and prevents scheduling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartHikeWizardPage(
          preselectedTrail: unlisted(),
          availableTrails: [unlisted()],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RoutePreviewMap), findsNothing);
    final button = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(button);
    tester.widget<FilledButton>(button).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Your location hike'), findsOneWidget);
    expect(find.byType(RoutePreviewMap), findsNothing);
    expect(find.text('Schedule for Later'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Safety Settings'), findsOneWidget);
    expect(
      find.textContaining('Path deviation alerts are unavailable'),
      findsOneWidget,
    );
    expect(find.byType(RoutePreviewMap), findsNothing);
  });
}
