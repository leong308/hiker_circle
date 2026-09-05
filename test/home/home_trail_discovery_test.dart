import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/ModelView/fall_stillness_monitor.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/find_hike_page.dart';
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
    expect(find.text('HIKING TRAILS', skipOffstage: false), findsOneWidget);
    expect(find.text('KL Forest Trail', skipOffstage: false), findsOneWidget);
    expect(find.text('Suggested for today'), findsNothing);
    expect(find.text('Offline Ready Routes'), findsNothing);
  });

  testWidgets('shows every trail matching the Best Matches filter', (
    tester,
  ) async {
    final trails = List<Trail>.generate(
      7,
      (index) => _testTrail().copyWith(
        trailId: 'trail-$index',
        name: 'Matching Trail ${index + 1}',
        ratingAverage: 5 - (index * 0.1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardPage(
          phoneNumber: '+60123456789',
          plannedHike: null,
          trails: trails,
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

    for (var index = 0; index < trails.length; index++) {
      expect(
        find.text('Matching Trail ${index + 1}', skipOffstage: false),
        findsOneWidget,
      );
    }
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

  testWidgets('shows a scheduled hike only once when preparation exists', (
    tester,
  ) async {
    final trail = _testTrail();
    final departure = DateTime.now().add(const Duration(days: 1));
    final upcoming = _upcomingHike(
      id: 'scheduled-ridge',
      trailName: 'Scheduled Ridge',
      departure: departure,
    );
    final planned = PlannedHike(
      trail: trail,
      plannedStartTime: departure,
      expectedReturnTime: departure.add(const Duration(hours: 3)),
      weatherCached: false,
      offlineMapDownloaded: false,
      emergencyContactsSelected: false,
      checklistCompleted: 0,
      checklistTotal: 24,
      phoneBatteryLevel: 70,
      liveLocationConfigured: false,
      upcomingHikeId: upcoming.id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardPage(
          phoneNumber: '+60123456789',
          myUpcomingHikes: [upcoming],
          plannedHike: planned,
          trails: const [],
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

    expect(find.text('Scheduled Ridge'), findsOneWidget);
    expect(find.text('Upcoming Hike'), findsNothing);
  });

  testWidgets('find hike refreshes an initially empty list automatically', (
    tester,
  ) async {
    final departure = DateTime.now().add(const Duration(hours: 2));
    final repository = _FindHikeRepository([
      const <UpcomingHike>[],
      [_upcomingHike(id: 'new-hike', departure: departure)],
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: FindHikePage(
          session: AppSession(
            phoneNumber: '+60999999999',
            signedInAt: DateTime.now(),
          ),
          repository: repository,
        ),
      ),
    );
    for (var i = 0; i < 20 && repository.loadCount == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repository.loadCount, 1);
    expect(find.text('Newly Visible Hike'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.loadCount, greaterThanOrEqualTo(2));
    expect(find.text('Newly Visible Hike'), findsOneWidget);
  });

  testWidgets('filters Hiking Trails by Malaysian state without leaving home', (
    tester,
  ) async {
    final malaysiaTrail = _testTrail();
    final selangorTrail = malaysiaTrail.copyWith(
      trailId: 'selangor-trail',
      name: 'Selangor Ridge',
      area: 'Gombak',
      state: 'Selangor',
      latitude: 3.3258,
      longitude: 101.7527,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardPage(
          phoneNumber: '+60123456789',
          plannedHike: null,
          trails: [malaysiaTrail, selangorTrail],
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

    await tester.tap(find.text('State'));
    await tester.pump();
    for (
      var i = 0;
      i < 30 && find.byType(CupertinoPicker).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CupertinoPicker), findsOneWidget);
    expect(find.text('Country'), findsNothing);
    expect(find.text('Choose a state in Malaysia.'), findsOneWidget);
    final statePicker = tester.widget<CupertinoPicker>(
      find.byType(CupertinoPicker),
    );
    final stateChildren =
        (statePicker.childDelegate as ListWheelChildListDelegate).children;
    final selangorIndex = stateChildren.indexWhere(
      (child) => ((child as Center).child! as Text).data == 'Selangor',
    );
    expect(selangorIndex, greaterThanOrEqualTo(0));
    final stateScrollController = statePicker.scrollController;
    statePicker.onSelectedItemChanged?.call(selangorIndex);
    await tester.pump();
    final rebuiltStatePicker = tester.widget<CupertinoPicker>(
      find.byType(CupertinoPicker),
    );
    expect(rebuiltStatePicker.scrollController, same(stateScrollController));
    await tester.tap(find.text('Use this state'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Selangor Ridge'), findsOneWidget);
    expect(find.text('Team Trail'), findsNothing);
    expect(find.text('State · Selangor'), findsOneWidget);
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

UpcomingHike _upcomingHike({
  required String id,
  required DateTime departure,
  String trailName = 'Newly Visible Hike',
}) {
  return UpcomingHike(
    id: id,
    sessionId: id,
    trailId: 'team-trail',
    trailName: trailName,
    latitude: 5.4141,
    longitude: 100.3288,
    area: 'George Town',
    state: 'Penang',
    country: 'Malaysia',
    distanceKm: 5.2,
    durationMinutes: 120,
    difficulty: 'Moderate',
    startPointName: 'Trailhead',
    destinationName: 'End point',
    departureTime: departure,
    expectedReturnTime: departure.add(const Duration(hours: 3)),
    hikeType: 'group',
    participantCount: 1,
    creatorPhone: '+60123456789',
    creatorName: 'Host',
    createdAt: DateTime.now(),
  );
}

class _FindHikeRepository extends HikerCircleFirebaseRepository {
  _FindHikeRepository(this.responses)
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'test',
        ),
      );

  final List<List<UpcomingHike>> responses;
  int loadCount = 0;

  @override
  Future<List<UpcomingHike>> loadUpcomingHikes() async {
    final index = loadCount.clamp(0, responses.length - 1);
    loadCount += 1;
    return responses[index];
  }
}
