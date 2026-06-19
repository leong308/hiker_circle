import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/ModelView/fall_stillness_monitor.dart';
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
}
