import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/ModelView/fall_stillness_monitor.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/home_dashboard_page.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  testWidgets('shows best matches without a dummy upcoming hike', (
    tester,
  ) async {
    final trail = Trail(
      trailId: 'kl-forest',
      name: 'KL Forest Trail',
      area: 'Kuala Lumpur',
      state: 'Federal Territory',
      latitude: 3.139,
      longitude: 101.6869,
      distanceKm: 5.2,
      difficulty: 'Moderate',
      estimatedDurationMinutes: 120,
      elevationGainMeters: 240,
      ratingAverage: 4.7,
      offlineMapAvailable: true,
      offlineMapDownloaded: false,
      isVerifiedTrail: true,
      routeFilePath: '',
      coverColorValue: 0xFF3F8F5E,
      checkpoints: const [],
      weather: TrailWeather(
        summary: 'Clear',
        temperatureRange: '25-31 C',
        rainProbability: 20,
        cachedAt: DateTime.utc(2026, 6, 16),
      ),
      hazards: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardPage(
          phoneNumber: '+60123456789',
          plannedHike: null,
          trails: [trail],
          isLoadingTrails: false,
          activeHike: null,
          isVisible: true,
          onStartHike: (_) async {},
          onFindHike: () {},
          onOpenTrailDetail: (_) {},
          onActiveHikeChanged: (_) {},
          onCheckInRequested: (_) async => throw UnimplementedError(),
          onPinLocationRequested: (_) async => throw UnimplementedError(),
          onPingTeamMember: (_) async => null,
          onEndHike: () {},
          fallStillnessSnapshot: const FallStillnessMonitorSnapshot.inactive(),
          onCancelFallStillnessSos: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Upcoming Hike', skipOffstage: false), findsNothing);
    expect(find.text('Create Hike', skipOffstage: false), findsOneWidget);
    expect(find.text('Find a Hike', skipOffstage: false), findsOneWidget);
    expect(find.text('BEST MATCHES', skipOffstage: false), findsOneWidget);
    expect(find.text('KL Forest Trail', skipOffstage: false), findsOneWidget);
    expect(find.text('Suggested for today'), findsNothing);
    expect(find.text('Offline Ready Routes'), findsNothing);
  });

  testWidgets('Create Hike does not start the displayed upcoming team hike', (
    tester,
  ) async {
    final trail = _testTrail();
    final planned = PlannedHike(
      trail: trail,
      plannedStartTime: DateTime.now().add(const Duration(days: 1)),
      expectedReturnTime: DateTime.now().add(const Duration(days: 1, hours: 3)),
      weatherCached: false,
      offlineMapDownloaded: false,
      emergencyContactsSelected: false,
      checklistCompleted: 0,
      checklistTotal: 24,
      phoneBatteryLevel: 20,
      liveLocationConfigured: false,
      upcomingHikeId: 'joined-team-hike',
    );
    var createCalled = false;
    Trail? requestedTrail;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardPage(
          phoneNumber: '+60123456789',
          plannedHike: planned,
          trails: [trail],
          isLoadingTrails: false,
          activeHike: null,
          isVisible: true,
          onStartHike: (trail) async {
            createCalled = true;
            requestedTrail = trail;
          },
          onFindHike: () {},
          onOpenTrailDetail: (_) {},
          onActiveHikeChanged: (_) {},
          onCheckInRequested: (_) async => throw UnimplementedError(),
          onPinLocationRequested: (_) async => throw UnimplementedError(),
          onPingTeamMember: (_) async => null,
          onEndHike: () {},
          fallStillnessSnapshot: const FallStillnessMonitorSnapshot.inactive(),
          onCancelFallStillnessSos: () {},
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create Hike'));
    await tester.pump();

    expect(createCalled, isTrue);
    expect(requestedTrail, isNull);
    expect(find.text('Your safety preparation is incomplete.'), findsNothing);
  });

  testWidgets('filters Best Matches by country without leaving home', (
    tester,
  ) async {
    final malaysiaTrail = _testTrail();
    final nepalTrail = malaysiaTrail.copyWith(
      trailId: 'nepal-trail',
      name: 'Everest Foothill',
      area: 'Solukhumbu',
      state: 'Koshi',
      country: 'Nepal',
      latitude: 27.9881,
      longitude: 86.925,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardPage(
          phoneNumber: '+60123456789',
          plannedHike: null,
          trails: [malaysiaTrail, nepalTrail],
          isLoadingTrails: false,
          activeHike: null,
          isVisible: true,
          onStartHike: (_) async {},
          onFindHike: () {},
          onOpenTrailDetail: (_) {},
          onActiveHikeChanged: (_) {},
          onCheckInRequested: (_) async => throw UnimplementedError(),
          onPinLocationRequested: (_) async => throw UnimplementedError(),
          onPingTeamMember: (_) async => null,
          onEndHike: () {},
          fallStillnessSnapshot: const FallStillnessMonitorSnapshot.inactive(),
          onCancelFallStillnessSos: () {},
        ),
      ),
    );

    await tester.tap(find.text('Region'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nepal'));
    await tester.pumpAndSettle();

    expect(find.text('Everest Foothill'), findsOneWidget);
    expect(find.text('Team Trail'), findsNothing);
    expect(find.text('Nepal'), findsOneWidget);
  });
}

Trail _testTrail() {
  return Trail(
    trailId: 'team-trail',
    name: 'Team Trail',
    area: 'George Town',
    state: 'Penang',
    country: 'Malaysia',
    latitude: 5.4141,
    longitude: 100.3288,
    distanceKm: 5.2,
    difficulty: 'Moderate',
    estimatedDurationMinutes: 120,
    elevationGainMeters: 240,
    ratingAverage: 4.7,
    offlineMapAvailable: true,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF3F8F5E,
    checkpoints: const [],
    weather: TrailWeather(
      summary: 'Clear',
      temperatureRange: '25-31 C',
      rainProbability: 20,
      cachedAt: DateTime.utc(2026, 6, 16),
    ),
    hazards: const [],
  );
}
