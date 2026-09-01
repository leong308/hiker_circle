import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/me/Model/hike_history_models.dart';
import 'package:hiker_circle/me/View/hike_history_page.dart';

void main() {
  final summary = HikeHistorySummary.fromMap(_summaryMap);
  final detail = parseHikeHistoryDetail({'detail': _detailMap});

  test(
    'history parser retains hike details without unknown private fields',
    () {
      final hikes = parseHikeHistoryList({
        'hikes': [
          {..._summaryMap, 'userPhoneNumber': '+60111111111'},
        ],
      });

      expect(hikes, hasLength(1));
      expect(hikes.single.trailName, 'Pine Ridge');
      expect(hikes.single.distanceKm, 8.4);
      expect(hikes.single.sessionId, 'session_1');
    },
  );

  testWidgets('completed hike opens its comprehensive private detail', (
    tester,
  ) async {
    final repository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
        'test',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HikeHistoryPage(
          repository: repository,
          loadHistory: () async => [summary],
          loadDetail: (_) async => detail,
          enableInteractiveRoute: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hike history'), findsOneWidget);
    expect(find.text('Pine Ridge'), findsOneWidget);
    expect(find.text('8.4 km'), findsWidgets);

    await tester.tap(find.byKey(const Key('hike-history-session_1')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Actual hike'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Actual hike'), findsOneWidget);
    expect(find.text('8.40 km'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Safety record'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Safety record'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Your route rating'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('5 / 5 stars'), findsOneWidget);
    expect(find.text('Moderate'), findsWidgets);
    expect(find.text('Excellent route.'), findsOneWidget);
  });

  testWidgets('slow history sync keeps a loading toast visible', (
    tester,
  ) async {
    final completer = Completer<List<HikeHistorySummary>>();
    final repository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
        'test',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HikeHistoryPage(
          repository: repository,
          loadHistory: () => completer.future,
          loadDetail: (_) async => detail,
          enableInteractiveRoute: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading your hike history…'), findsOneWidget);
    expect(find.byKey(const Key('hiker-circle-loading-toast')), findsOneWidget);

    completer.complete([summary]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hiker-circle-loading-toast')), findsNothing);
    expect(find.text('Pine Ridge'), findsOneWidget);
  });

  testWidgets('slow detail load explains that route records are loading', (
    tester,
  ) async {
    final completer = Completer<HikeHistoryDetail>();
    await tester.pumpWidget(
      MaterialApp(
        home: HikeHistoryDetailPage(
          summary: summary,
          loadDetail: (_) => completer.future,
          enableInteractiveRoute: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading hike details…'), findsOneWidget);
    expect(
      find.text('Preparing the route and safety records.'),
      findsOneWidget,
    );

    completer.complete(detail);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hiker-circle-loading-toast')), findsNothing);
  });
}

final _summaryMap = <String, dynamic>{
  'sessionId': 'session_1',
  'trailId': 'trail_1',
  'trailName': 'Pine Ridge',
  'location': 'Gombak, Selangor',
  'difficulty': 'Moderate',
  'hikeType': 'solo',
  'startedAtLocal': '2026-08-20T01:00:00.000Z',
  'endedAtLocal': '2026-08-20T03:30:00.000Z',
  'durationSeconds': 9000,
  'distanceKm': 8.4,
  'checkIns': 2,
  'manualPins': 1,
  'routePointCount': 80,
  'batteryStartPercent': 92,
  'batteryEndPercent': 71,
  'teamMemberCount': 1,
  'coverImageUrl': '',
};

final _detailMap = <String, dynamic>{
  'summary': _summaryMap,
  'plan': {
    'startPointName': 'North Gate',
    'destinationName': 'Summit',
    'plannedStartTimeLocal': '2026-08-20T01:00:00.000Z',
    'estimatedArrivalTimeLocal': '2026-08-20T02:00:00.000Z',
    'estimatedReturnTimeLocal': '2026-08-20T04:00:00.000Z',
    'checkpoints': [
      {'name': 'North Gate', 'order': 1, 'latitude': 3.1, 'longitude': 101.6},
      {'name': 'Summit', 'order': 2, 'latitude': 3.2, 'longitude': 101.7},
    ],
  },
  'trail': {
    'plannedDistanceKm': 7.8,
    'estimatedDurationMinutes': 180,
    'elevationGainMeters': 520,
    'ratingAverage': 4.6,
    'ratingCount': 32,
    'isVerifiedTrail': true,
  },
  'performance': {
    'averageSpeedKmh': 3.36,
    'paceMinutesPerKm': 17.8,
    'storedRoutePointCount': 2,
    'routePointsDownsampled': true,
    'minAltitudeMeters': 110,
    'maxAltitudeMeters': 620,
  },
  'safety': {
    'safetyCheckInIntervalSeconds': 1800,
    'locationRecordingIntervalSeconds': 30,
    'shareLiveLocation': true,
    'fallDetectionEnabled': true,
    'pathDeviationEnabled': true,
    'offlinePhysicalAlertEnabled': true,
    'duressEnabled': true,
    'pathDeviationAlertCount': 0,
    'completedChecklistItems': ['Water', 'First aid kit'],
    'checkIns': [
      {
        'checkInId': 'check_1',
        'status': 'safe',
        'checkedInAtLocal': '2026-08-20T02:00:00.000Z',
        'batteryLevel': 80,
      },
    ],
    'manualPins': [
      {
        'pinId': 'pin_1',
        'pinnedAtLocal': '2026-08-20T02:10:00.000Z',
        'coordinate': {'latitude': 3.15, 'longitude': 101.65},
      },
    ],
  },
  'battery': {'usedPercent': 21, 'lowestRecordedPercent': 71},
  'team': {'hikeType': 'solo', 'memberCount': 1, 'buddies': []},
  'routePoints': [
    {
      'latitude': 3.1,
      'longitude': 101.6,
      'capturedAtLocal': '2026-08-20T01:00:00.000Z',
    },
    {
      'latitude': 3.2,
      'longitude': 101.7,
      'capturedAtLocal': '2026-08-20T03:20:00.000Z',
    },
  ],
  'telemetryPointCount': 80,
  'insights': ['Good tracking coverage.'],
  'rating': {
    'stars': 5,
    'difficulty': 'moderate',
    'comment': 'Excellent route.',
  },
  'source': {
    'sourceUpcomingHikeId': '',
    'teamHikeSessionId': '',
    'routeCaptureAvailable': true,
    'sessionId': 'session_1',
  },
};
