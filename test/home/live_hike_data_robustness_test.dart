import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_preview_map.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/ModelView/fall_stillness_monitor.dart';
import 'package:hiker_circle/home/View/active_tracking_map_view.dart';
import 'package:hiker_circle/home/View/gear_checklist_page.dart';
import 'package:hiker_circle/home/View/home_dashboard_page.dart';
import 'package:hiker_circle/home/View/start_hike_wizard_page.dart';
import 'package:hiker_circle/home/View/trail_gear_checklist.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('an empty persisted trail no longer crashes draft creation', () {
    final trail = _trail(checkpoints: const []);

    final draft = HikeSessionDraft.fromTrail(trail);

    expect(draft.startPointName, trail.name);
    expect(draft.destinationName, trail.name);
    expect(
      draft.locationRecordingInterval,
      HikeSessionDraft.defaultLocationRecordingInterval,
    );
    expect(draft.emergencyContactNames, isEmpty);
    final activeHike = ActiveHikeSession.fromDraft(draft);
    expect(activeHike.queuedUpdates, 0);
    expect(activeHike.hasKnownBatteryLevel, isFalse);
    expect(activeHike.batteryStartedLevel, isNull);
  });

  test('disabled offline packs do not block preparation readiness', () {
    final plan = PlannedHike(
      trail: _trail(),
      plannedStartTime: DateTime.utc(2026, 8, 5),
      expectedReturnTime: DateTime.utc(2026, 8, 5, 2),
      weatherCached: true,
      offlineMapDownloaded: false,
      emergencyContactsSelected: true,
      checklistCompleted: 1,
      checklistTotal: 1,
      phoneBatteryLevel: 90,
      liveLocationConfigured: true,
    );

    expect(plan.missingPreparationItems, isEmpty);
  });

  test(
    'trail persistence drops invalid checkpoints and normalizes difficulty',
    () {
      final restored = Trail.fromPersistence({
        ..._trail().toPersistence(),
        'difficulty': 'medium',
        'checkpoints': [
          {'name': 'Valid', 'latitude': 3.1, 'longitude': 101.6, 'order': 1},
          {
            'name': 'Invalid latitude',
            'latitude': 120,
            'longitude': 101.7,
            'order': 2,
          },
          {'name': 'Missing coordinate', 'order': 3},
        ],
      });

      expect(restored.difficulty, 'Moderate');
      expect(restored.checkpoints, hasLength(1));
      expect(restored.checkpoints.single.name, 'Valid');
    },
  );

  test(
    'active hike restore filters invalid GPS and orders valid route points',
    () {
      final draft = HikeSessionDraft.fromTrail(_trail());
      final persistence = ActiveHikeSession(
        sessionId: 'session-robust',
        draft: draft,
        startedAt: DateTime.utc(2026, 8, 4),
        batteryLevel: 80,
        queuedUpdates: 0,
        manualPins: 0,
        checkIns: 0,
      ).toPersistence();
      persistence
        ..['queuedUpdates'] = -4
        ..['latestLocation'] = {
          'latitude': 91,
          'longitude': 101,
          'capturedAtLocal': '2026-08-04T00:00:00Z',
        }
        ..['routePoints'] = [
          {
            'latitude': 3.2,
            'longitude': 101.8,
            'capturedAtLocal': '2026-08-04T00:02:00Z',
          },
          {
            'latitude': double.nan,
            'longitude': 101.7,
            'capturedAtLocal': '2026-08-04T00:01:00Z',
          },
          {
            'latitude': 3.1,
            'longitude': 101.7,
            'capturedAtLocal': '2026-08-04T00:00:00Z',
          },
        ];

      final restored = ActiveHikeSession.fromPersistence(persistence);

      expect(restored.latestLocation, isNull);
      expect(restored.queuedUpdates, 0);
      expect(restored.routePoints, hasLength(2));
      expect(restored.routePoints.first.latitude, 3.1);
      expect(restored.routePoints.last.latitude, 3.2);
      expect(restored.recordedDistanceKm, greaterThan(0));
    },
  );

  test('team session carries the shared hike draft through persistence', () {
    final draft = HikeSessionDraft.fromTrail(
      _trail(),
    ).copyWith(hikeType: HikeType.team);
    final teamSession = TeamHikeSession(
      id: 'team-shared-draft',
      hostPhoneNumber: '+60111111111',
      trailId: draft.trail.trailId,
      trailName: draft.trail.name,
      phase: TeamHikePhase.inviting,
      participants: const [],
      sharedDraft: draft,
    );

    final restored = TeamHikeSession.fromFirestore(teamSession.toFirestore());

    expect(restored.sharedDraft, isNotNull);
    expect(restored.sharedDraft!.hikeType, HikeType.team);
    expect(restored.sharedDraft!.trail.trailId, draft.trail.trailId);
    expect(
      teamSession.copyWith(phase: TeamHikePhase.readyCheck).sharedDraft,
      same(draft),
    );
  });

  test(
    'team location freshness prefers the dedicated update timestamp and round-trips',
    () {
      final now = DateTime.utc(2026, 8, 4, 8);
      final participant = TeamHikeParticipant.fromFirestore({
        'buddy': {'name': 'Buddy', 'phoneNumber': '+60112223333'},
        'status': 'active',
        'latestLocation': {
          'latitude': 3.1,
          'longitude': 101.6,
          'capturedAtLocal': now
              .subtract(const Duration(seconds: 10))
              .toIso8601String(),
        },
        'locationUpdatedAtLocal': now
            .subtract(const Duration(minutes: 3))
            .toIso8601String(),
      });

      expect(participant.hasFreshLocationAt(now), isFalse);
      final refreshed = participant.copyWith(locationUpdatedAt: now);
      expect(refreshed.hasFreshLocationAt(now), isTrue);

      final restored = TeamHikeParticipant.fromFirestore(
        refreshed.toFirestore(),
      );
      expect(restored.locationUpdatedAt, now);
      expect(restored.hasFreshLocationAt(now), isTrue);
    },
  );

  test('legacy team location freshness falls back to coordinate time', () {
    final now = DateTime.utc(2026, 8, 4, 8);
    final participant = TeamHikeParticipant.fromFirestore({
      'buddy': {'name': 'Buddy', 'phoneNumber': '+60112223333'},
      'status': 'active',
      'latestLocation': {
        'latitude': 3.1,
        'longitude': 101.6,
        'capturedAtLocal': now
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      },
    });

    expect(participant.locationUpdatedAt, isNull);
    expect(participant.hasFreshLocationAt(now), isTrue);
    expect(
      participant.hasFreshLocationAt(now.add(const Duration(minutes: 2))),
      isFalse,
    );
  });

  test('persisted tracking interval is bounded for separation safety', () {
    final base = HikeSessionDraft.fromTrail(_trail()).toPersistence();

    final tooSlow = HikeSessionDraft.fromPersistence({
      ...base,
      'locationRecordingIntervalSeconds': 3600,
    });
    final tooFast = HikeSessionDraft.fromPersistence({
      ...base,
      'locationRecordingIntervalSeconds': 1,
    });

    expect(
      tooSlow.locationRecordingInterval,
      HikeSessionDraft.maxLocationRecordingInterval,
    );
    expect(
      tooFast.locationRecordingInterval,
      HikeSessionDraft.minLocationRecordingInterval,
    );
  });

  test('scheduled hike timestamps hydrate in the device local timezone', () {
    final departureUtc = DateTime.utc(2026, 8, 14, 12, 2);
    final expectedReturnUtc = departureUtc.add(const Duration(hours: 3));
    final hike = UpcomingHike.fromFirestore('hike-1', {
      'departureTimeLocal': departureUtc.toIso8601String(),
      'expectedReturnTimeLocal': expectedReturnUtc.toIso8601String(),
    });
    final draft = HikeSessionDraft.fromPersistence({
      ...HikeSessionDraft.fromTrail(_trail()).toPersistence(),
      'departureTime': departureUtc.toIso8601String(),
      'expectedArrivalTime': departureUtc
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'expectedReturnTime': expectedReturnUtc.toIso8601String(),
    });

    expect(hike.departureTime.isUtc, isFalse);
    expect(hike.departureTime.toUtc(), departureUtc);
    expect(hike.expectedReturnTime.toUtc(), expectedReturnUtc);
    expect(draft.departureTime.isUtc, isFalse);
    expect(draft.departureTime.toUtc(), departureUtc);
    expect(draft.expectedReturnTime.toUtc(), expectedReturnUtc);
  });

  test('malformed group participants do not crash chat hydration', () {
    final malformed = GroupChat.fromFirestore('chat-1', {
      'participantPhones': {'unexpected': 'map'},
      'createdAtLocal': 'not-a-date',
    });
    final partiallyValid = GroupChat.fromFirestore('chat-2', {
      'participantPhones': [' +6011 ', 42, '', '+6022', '+6022'],
      'createdAtLocal': DateTime.utc(2026, 8, 4).toIso8601String(),
    });

    expect(malformed.participantPhones, isEmpty);
    expect(partiallyValid.participantPhones, ['+6011', '+6022']);
  });

  test('upcoming hike distance rejects invalid remote coordinates', () {
    final hike = UpcomingHike.fromFirestore('hike-1', {
      'latitude': 500,
      'longitude': 101.6,
    });

    expect(hike.distanceFrom(3.1, 101.6), double.infinity);
    expect(hike.distanceFrom(double.nan, 101.6), double.infinity);
  });

  testWidgets('maps show safe empty states when trail geometry is missing', (
    tester,
  ) async {
    final trail = _trail(checkpoints: const []);
    final activeHike = ActiveHikeSession.fromDraft(
      HikeSessionDraft.fromTrail(trail),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: RoutePreviewMap(trail: trail),
        ),
      ),
    );
    expect(find.text('Trail coordinates are unavailable'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: ActiveTrackingMapView(activeHike: activeHike),
        ),
      ),
    );
    expect(find.text('Waiting for trail coordinates'), findsOneWidget);
  });

  testWidgets(
    'start wizard shows an empty state instead of indexing no trail',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StartHikeWizardPage()));

      expect(
        find.text('No trails are available to plan a hike.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('gear checklist starts with no seeded completions', (
    tester,
  ) async {
    final plan = PlannedHike(
      trail: _trail(),
      plannedStartTime: DateTime.utc(2026, 8, 5),
      expectedReturnTime: DateTime.utc(2026, 8, 5, 2),
      weatherCached: true,
      offlineMapDownloaded: false,
      emergencyContactsSelected: true,
      checklistCompleted: 0,
      checklistTotal: GearChecklistPage.checklistItemCount,
      phoneBatteryLevel: 90,
      liveLocationConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: GearChecklistPage(plannedHike: plan)),
    );

    expect(find.text('0/${plan.gearPlan.items.length}'), findsOneWidget);
    final packingTiles = tester.widgetList<GearPackingTile>(
      find.byType(GearPackingTile),
    );
    expect(packingTiles, isNotEmpty);
    expect(packingTiles.every((tile) => !tile.packed), isTrue);
    expect(find.text('Offline map downloaded'), findsNothing);
  });

  testWidgets(
    'live dashboard formats fast tracking and unknown values safely',
    (tester) async {
      final draft = HikeSessionDraft.fromTrail(
        _trail(checkpoints: const []),
      ).copyWith(locationRecordingInterval: const Duration(seconds: 5));
      final activeHike = ActiveHikeSession.fromDraft(draft);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: HomeDashboardPage(
            phoneNumber: '+60123456789',
            plannedHike: null,
            trails: [draft.trail],
            isLoadingTrails: false,
            activeHike: activeHike,
            isVisible: true,
            onStartHike: (_) async {},
            onFindHike: () {},
            onOpenTrailDetail: (_) {},
            onActiveHikeChanged: (_) {},
            onCheckInRequested: (hike) async => hike,
            onPinLocationRequested: (hike) async => PinLocationResult(
              hike: hike,
              status: PinLocationStatus.unavailable,
            ),
            onPingTeamMember: (_) async => null,
            onEndHike: () {},
            fallStillnessSnapshot:
                const FallStillnessMonitorSnapshot.inactive(),
            onCancelFallStillnessSos: () {},
          ),
        ),
      );

      expect(find.text('Every 5 sec'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('None selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Trail _trail({
  List<TrailCheckpoint> checkpoints = const [
    TrailCheckpoint(name: 'Start', latitude: 3.1, longitude: 101.6, order: 1),
    TrailCheckpoint(name: 'End', latitude: 3.2, longitude: 101.7, order: 2),
  ],
}) {
  return Trail(
    trailId: 'robust-trail',
    name: 'Robust Trail',
    area: 'Test',
    state: 'Test',
    latitude: 3.1,
    longitude: 101.6,
    distanceKm: 2,
    difficulty: 'Moderate',
    estimatedDurationMinutes: 90,
    elevationGainMeters: 100,
    ratingAverage: 4,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: checkpoints,
    weather: TrailWeather(
      summary: 'Cloudy',
      temperatureRange: '23-28 C',
      rainProbability: 20,
      cachedAt: DateTime.utc(2026, 8, 4),
    ),
    hazards: const [],
  );
}
