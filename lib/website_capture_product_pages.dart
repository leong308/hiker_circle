// Isolated website media routes. Imported only by website_capture_main.dart.
// These are the current product widgets with fictional data and local callbacks.
// This file does not initialize Firebase, authenticate an account, or dispatch alerts.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app/Data/app_settings_controller.dart';
import 'app/Data/firebase_bootstrap.dart';
import 'app/Data/hiker_circle_firebase_repository.dart';
import 'app/Model/app_session.dart';
import 'core/services/hiking_route_service.dart';
import 'home/Data/hike_briefing_weather_service.dart';
import 'home/Model/hike_session_models.dart';
import 'home/Model/route_gear_assessment.dart';
import 'home/ModelView/fall_stillness_monitor.dart';
import 'home/View/final_preparation_review_page.dart';
import 'home/View/hike_safety_settings_page.dart';
import 'home/View/hiking_forecast_sheet.dart';
import 'home/View/home_dashboard_page.dart';
import 'home/View/hiker_home_page.dart';
import 'home/View/start_hike_wizard_page.dart';
import 'home/View/team_readiness_map_page.dart';
import 'home/View/trail_rating_dialog.dart';
import 'me/Data/expired_hikes_repository.dart';
import 'me/Model/hike_history_models.dart';
import 'me/View/hike_history_page.dart';
import 'me/View/widgets/app_settings_content.dart';
import 'navigation/View/hiker_bottom_nav_bar.dart';
import 'trail/Model/trail_hazard_assessment.dart';
import 'trail/Model/trail_models.dart';
import 'trail/Model/trail_weather_location.dart';
import 'trail/View/trail_hazard_alert_dialog.dart';
import 'trail/View/trail_page.dart';

/// Current product screens for the separate, visibly labelled media demo app.
Map<String, WidgetBuilder> websiteCaptureProductPages() {
  final data = _CaptureProductData();
  final repository = _CaptureProductRepository(data);
  final session = AppSession(
    phoneNumber: '+10000000000',
    signedInAt: data.now,
    username: 'Alex',
  );
  Widget wizard(BuildContext context, {bool schedule = false}) =>
      StartHikeWizardPage(
        preselectedTrail: data.trail,
        availableTrails: data.trails,
        repository: repository,
        session: session,
        startWithSchedule: schedule,
        emergencyContactNames: const ['Jamie', 'Sam', 'Taylor'],
        onLocationSelected: (_) async => TrailHazardAlertAction.acknowledge,
        onEditEmergencyContacts: () async => ['Jamie', 'Sam', 'Taylor'],
        onScheduled: (_) async {},
        onStartNow: (_) async => false,
      );
  Future<void> openWizard(BuildContext context) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (context) => wizard(context)));
  }

  Widget preparation(BuildContext context) => FinalPreparationReviewPage(
    hike: data.upcoming,
    plan: data.plan,
    isHost: true,
    canStart: true,
    checkTrailheadOnStart: false,
    onPlanChanged: (_) async {},
    loadWeather: () async => data.weather,
    loadRouteAnalysis: (_) async => data.gearAssessment,
    loadBatteryLevel: () async => 86,
    onStart: (_) async => false,
  );
  Widget detail(BuildContext context) => TrailDetailPage(
    session: session,
    hikerCircleRepository: repository,
    trail: data.trail,
    onStartHike: (_) => openWizard(context),
  );
  return {
    'checkpoints': (context) => StartHikeWizardPage(
      availableTrails: data.trails,
      repository: repository,
      session: session,
      emergencyContactNames: const ['Jamie', 'Sam', 'Taylor'],
      onLocationSelected: (_) async => TrailHazardAlertAction.acknowledge,
      onEditEmergencyContacts: () async => ['Jamie', 'Sam', 'Taylor'],
      onScheduled: (_) async {},
      onStartNow: (_) async => false,
    ),
    'active-fullscreen': (context) => ActiveHikeHomePage(
      activeHike: data.active,
      currentPhoneNumber: session.phoneNumber,
      onEndHike: () {},
      onCheckIn: () {},
      onReportHazard: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => HazardReportPage(
            session: session,
            hikerCircleRepository: repository,
            trail: data.trail,
          ),
        ),
      ),
      onOpenTeamChat: () {},
      onPingTeamMember: (_) async => data.team,
      fallStillnessSnapshot: const FallStillnessMonitorSnapshot.inactive(),
      onCancelFallStillnessSos: () {},
    ),
    'active-home': (context) => Scaffold(
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: 0,
        onDestinationSelected: (_) {},
      ),
      body: HomeDashboardPage(
        phoneNumber: session.phoneNumber,
        plannedHike: null,
        trails: data.trails,
        isLoadingTrails: false,
        activeHike: data.active,
        isVisible: true,
        onStartHike: (_) async {},
        onFindHike: () {},
        onOpenTrailDetail: (_) {},
        onActiveHikeChanged: (_) {},
        onCheckInRequested: (hike) async => hike,
        onPingTeamMember: (_) async => data.team,
        onEndHike: () {},
        fallStillnessSnapshot: const FallStillnessMonitorSnapshot.inactive(),
        onCancelFallStillnessSos: () {},
      ),
    ),
    'team-locations': (_) => TeamReadinessMapPage(
      initialTeam: data.team,
      teams: Stream.value(data.team),
      currentPhoneNumber: session.phoneNumber,
    ),
    'rating': (_) => _CaptureRatingPage(history: data.history),
    'home': (context) => Scaffold(
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: 0,
        onDestinationSelected: (_) {},
      ),
      body: HomeDashboardPage(
        phoneNumber: session.phoneNumber,
        plannedHike: data.plan,
        myUpcomingHikes: [data.upcoming, data.secondUpcoming],
        trails: data.trails,
        isLoadingTrails: false,
        activeHike: null,
        isVisible: true,
        onStartHike: (_) => openWizard(context),
        onFindHike: () {},
        onOpenTrailDetail: (_) => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: detail)),
        onTapUpcomingHike: (_) async {
          await Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: preparation));
        },
        onActiveHikeChanged: (_) {},
        onPlannedHikeChanged: (_) async {},
        onCheckInRequested: (hike) async => hike,
        onPingTeamMember: (_) async => null,
        onEndHike: () {},
        fallStillnessSnapshot: const FallStillnessMonitorSnapshot.inactive(),
        onCancelFallStillnessSos: () {},
      ),
    ),
    'trails': (context) => Scaffold(
      body: TrailPage(
        session: session,
        hikerCircleRepository: repository,
        initialTrails: data.trails,
        onStartHike: (_) => openWizard(context),
      ),
    ),
    'trail-detail': detail,
    'create-hike': wizard,
    'schedule': (context) => wizard(context, schedule: true),
    'hike-safety': (context) => HikeSafetySettingsPage(
      initialDraft: data.draft,
      onSave: (_) async {},
      onEditContacts: () async => ['Jamie', 'Sam', 'Taylor'],
      onContinue: (_) async {
        await Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: preparation));
        return null;
      },
    ),
    'preparation': preparation,
    'forecast': (_) => Scaffold(
      body: SafeArea(
        child: HikingForecastSheet(
          hike: data.upcoming,
          weather: data.weather,
          elevationGain: data.trail.elevationGainMeters,
          service: HikeBriefingWeatherService(
            trailForecast: (id, {refresh = false}) async => data.weather,
          ),
        ),
      ),
    ),
    'hazard-report': (_) => HazardReportPage(
      session: session,
      hikerCircleRepository: repository,
      trail: data.trail,
    ),
    'hike-history': (_) => HikeHistoryPage(
      repository: repository,
      loadHistory: () async => [data.history.summary],
      loadDetail: (_) async => data.history,
      loadExpiredHikes: (_) async => ExpiredHikesPage(hikes: [data.expired]),
      enableInteractiveRoute: false,
    ),
    'hike-analysis': (_) => HikeHistoryDetailPage(
      summary: data.history.summary,
      loadDetail: (_) async => data.history,
      enableInteractiveRoute: false,
    ),
    'app-settings': (context) => Scaffold(
      body: SafeArea(
        child: AppSettingsContent(
          settings: AppSettingsController.instance,
          onBack: () => Navigator.of(context).maybePop(),
          onLoginSecurity: () {},
          onChangePassword: () {},
          onPrivateUnlock: (_) {},
          onPreciseLocation: (_) {},
          onHapticFeedback: (_) {},
          onTimeZone: () {},
          timeZoneLabel: 'Kuala Lumpur (UTC+08:00)',
        ),
      ),
    ),
  };
}

class _CaptureProductData {
  final now = DateTime.now();
  late final departure = DateTime(now.year, now.month, now.day + 1, 7, 30);
  late final weather = TrailWeather(
    summary: 'Partly cloudy',
    temperatureRange: '22–28°C',
    rainProbability: 25,
    cachedAt: now.toUtc(),
    humidity: 78,
    windSpeed: 6,
    uvIndex: 4,
    feelsLike: 26,
    hourlyForecast: List.generate(
      72,
      (index) => HourlyForecast(
        time: _hours[index],
        temperature: 23 + (index % 6).toDouble(),
        precipitationProbability: 10 + (index % 4) * 5,
        weatherCode: 2,
      ),
    ),
    forecastData: {
      'timezone': 'Asia/Kuala_Lumpur',
      'utc_offset_seconds': 28800,
      'hourly': {
        'time': _hours
            .map((hour) => hour.millisecondsSinceEpoch ~/ 1000)
            .toList(),
        'temperature_2m': List.generate(72, (index) => 23 + index % 6),
        'apparent_temperature': List.generate(72, (index) => 24 + index % 6),
        'precipitation_probability': List.generate(
          72,
          (index) => 10 + (index % 4) * 5,
        ),
        'relative_humidity_2m': List.filled(72, 78),
        'wind_speed_10m': List.filled(72, 6),
        'wind_gusts_10m': List.filled(72, 12),
        'precipitation': List.filled(72, 0.2),
        'weather_code': List.filled(72, 2),
        'visibility': List.filled(72, 12000),
        'uv_index': List.filled(72, 4),
      },
      'daily': {
        'time': List.generate(
          3,
          (index) =>
              DateTime(
                now.year,
                now.month,
                now.day + index,
              ).millisecondsSinceEpoch ~/
              1000,
        ),
        'sunrise': List.generate(
          3,
          (index) =>
              DateTime(
                now.year,
                now.month,
                now.day + index,
                7,
              ).millisecondsSinceEpoch ~/
              1000,
        ),
        'sunset': List.generate(
          3,
          (index) =>
              DateTime(
                now.year,
                now.month,
                now.day + index,
                19,
              ).millisecondsSinceEpoch ~/
              1000,
        ),
      },
    },
  );
  late final _hours = List.generate(
    72,
    (index) => DateTime(now.year, now.month, now.day, index),
  );
  static const checkpoints = [
    TrailCheckpoint(
      name: 'Trailhead',
      latitude: 3.3004,
      longitude: 101.7393,
      order: 0,
    ),
    TrailCheckpoint(
      name: 'Forest junction',
      latitude: 3.3051,
      longitude: 101.7408,
      order: 1,
    ),
    TrailCheckpoint(
      name: 'Ridge lookout',
      latitude: 3.3107,
      longitude: 101.7443,
      order: 2,
    ),
    TrailCheckpoint(
      name: 'Summit',
      latitude: 3.3151,
      longitude: 101.7482,
      order: 3,
    ),
  ];
  late final trail = Trail(
    trailId: 'website-demo-forest-loop',
    name: 'Forest Ridge Trail',
    area: 'Gombak',
    state: 'Selangor',
    country: 'Malaysia',
    latitude: checkpoints.first.latitude,
    longitude: checkpoints.first.longitude,
    distanceKm: 5.4,
    difficulty: 'Moderate',
    estimatedDurationMinutes: 180,
    elevationGainMeters: 380,
    minElevationMeters: 220,
    maxElevationMeters: 600,
    ratingAverage: 4.7,
    ratingCount: 24,
    moderateDifficultyVotes: 20,
    easyDifficultyVotes: 4,
    offlineMapAvailable: true,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF276B47,
    checkpoints: checkpoints,
    weather: weather,
    hazards: const [],
    routeCheckpointsHash: HikingRouteService.checkpointsHash(checkpoints),
    routeEncodedPolyline: PolylineCodec.encode([
      for (final point in checkpoints) LatLng(point.latitude, point.longitude),
    ]),
  );
  late final trails = [
    trail,
    trail.copyWith(
      trailId: 'website-demo-valley',
      name: 'Valley Nature Walk',
      distanceKm: 3.2,
      difficulty: 'Easy',
    ),
  ];
  late final draft = HikeSessionDraft.fromTrail(trail).copyWith(
    departureTime: departure,
    expectedArrivalTime: departure.add(const Duration(hours: 3)),
    expectedReturnTime: departure.add(const Duration(hours: 5)),
    emergencyContactNames: const ['Jamie', 'Sam', 'Taylor'],
    shareLiveLocation: true,
  );
  late final upcoming = _upcoming('website-demo-next', trail, departure);
  late final secondUpcoming = _upcoming(
    'website-demo-weekend',
    trails.last,
    departure.add(const Duration(days: 1)),
  );
  late final expired = _upcoming(
    'website-demo-expired',
    trail,
    departure.subtract(const Duration(days: 4)),
  );
  UpcomingHike _upcoming(String id, Trail route, DateTime start) =>
      UpcomingHike(
        id: id,
        sessionId: id,
        trailId: route.trailId,
        trailName: route.name,
        latitude: route.latitude,
        longitude: route.longitude,
        area: route.area,
        state: route.state,
        country: route.country,
        distanceKm: route.distanceKm,
        durationMinutes: route.estimatedDurationMinutes,
        difficulty: route.difficulty,
        startPointName: 'Trailhead',
        destinationName: 'Summit',
        departureTime: start,
        expectedReturnTime: start.add(const Duration(hours: 5)),
        hikeType: 'solo',
        participantCount: 1,
        creatorPhone: '+10000000000',
        creatorName: 'Alex',
        createdAt: now.subtract(const Duration(days: 1)),
        participantPhones: const ['+10000000000'],
        draft: draft,
      );
  late final gearAssessment = RouteGearAssessment(
    routeKey: 'website-demo',
    checkedAt: now,
    status: 'complete',
    featureCount: 4,
    rough: true,
    surfaceMapped: true,
  );
  late final plan = PlannedHike(
    trail: trail,
    plannedStartTime: departure,
    expectedReturnTime: departure.add(const Duration(hours: 5)),
    weatherCached: true,
    offlineMapDownloaded: false,
    emergencyContactsSelected: true,
    checklistCompleted: 0,
    checklistTotal: 12,
    phoneBatteryLevel: 86,
    liveLocationConfigured: true,
    upcomingHikeId: upcoming.id,
    gearAssessment: gearAssessment,
  );
  late final team = TeamHikeSession(
    id: 'website-demo-team',
    hostPhoneNumber: '+10000000000',
    trailId: trail.trailId,
    trailName: trail.name,
    phase: TeamHikePhase.readyCheck,
    sharedDraft: draft.copyWith(hikeType: HikeType.team),
    updatedAt: now,
    participants: [
      for (var index = 0; index < 3; index++)
        TeamHikeParticipant(
          buddy: TeamHikeBuddy(
            name: ['Alex', 'Jamie', 'Sam'][index],
            handle: ['alex_demo', 'jamie_demo', 'sam_demo'][index],
            phoneNumber: '+1000000000$index',
            avatarColorValue: [0xFF34A853, 0xFF4285F4, 0xFFFBBC05][index],
          ),
          status: TeamHikeParticipantStatus.ready,
          isHost: index == 0,
          isLeader: index == 0,
          latestLocation: HikeCoordinate(
            latitude: checkpoints[index].latitude,
            longitude: checkpoints[index].longitude,
            capturedAt: now,
          ),
          locationUpdatedAt: now,
          readyAt: now,
        ),
    ],
  );
  late final active = ActiveHikeSession(
    sessionId: 'website-demo-active',
    draft: draft.copyWith(
      hikeType: HikeType.team,
      teamBuddies: team.participants.map((person) => person.buddy).toList(),
      departureTime: now.subtract(const Duration(minutes: 35)),
      expectedArrivalTime: now.add(const Duration(hours: 2)),
      expectedReturnTime: now.add(const Duration(hours: 3)),
    ),
    startedAt: now.subtract(const Duration(minutes: 35)),
    batteryLevel: 86,
    batteryStartedLevel: 95,
    queuedUpdates: 0,
    manualPins: 1,
    checkIns: 2,
    latestLocation: HikeCoordinate(
      latitude: checkpoints[1].latitude,
      longitude: checkpoints[1].longitude,
      capturedAt: now,
    ),
    routePoints: [
      for (final point in checkpoints.take(2))
        HikeCoordinate(
          latitude: point.latitude,
          longitude: point.longitude,
          capturedAt: now,
        ),
    ],
    teamHikeSessionId: team.id,
    teamHikeSession: team,
  );
  late final history = HikeHistoryDetail.fromMap({
    'summary': {
      'sessionId': 'website-demo-history',
      'trailId': trail.trailId,
      'trailName': trail.name,
      'location': 'Gombak, Selangor',
      'difficulty': 'Moderate',
      'hikeType': 'solo',
      'startedAtLocal': now
          .subtract(const Duration(days: 2, hours: 3))
          .toIso8601String(),
      'endedAtLocal': now.subtract(const Duration(days: 2)).toIso8601String(),
      'durationSeconds': 10800,
      'distanceKm': 5.4,
      'checkIns': 5,
      'manualPins': 2,
      'routePointCount': 120,
      'batteryStartPercent': 95,
      'batteryEndPercent': 78,
      'teamMemberCount': 1,
    },
    'plan': {
      'startPointName': 'Trailhead',
      'destinationName': 'Summit',
      'checkpoints': [for (final p in checkpoints) p.toFirestore()],
    },
    'trail': {
      'plannedDistanceKm': 5.4,
      'estimatedDurationMinutes': 180,
      'elevationGainMeters': 380,
      'ratingAverage': 4.7,
      'ratingCount': 24,
      'isVerifiedTrail': true,
    },
    'performance': {
      'averageSpeedKmh': 1.8,
      'paceMinutesPerKm': 33.3,
      'storedRoutePointCount': 120,
      'minAltitudeMeters': 220,
      'maxAltitudeMeters': 600,
    },
    'safety': {
      'safetyCheckInIntervalSeconds': 1800,
      'locationRecordingIntervalSeconds': 10,
      'shareLiveLocation': true,
      'fallDetectionEnabled': true,
      'pathDeviationEnabled': true,
      'offlinePhysicalAlertEnabled': true,
      'duressEnabled': true,
    },
    'battery': {'usedPercent': 17, 'lowestRecordedPercent': 78},
    'routePoints': [
      for (final p in checkpoints)
        {'latitude': p.latitude, 'longitude': p.longitude},
    ],
    'insights': [
      'You completed 5.4 km with 380 m of elevation gain.',
      'Five safety check-ins recorded along the route.',
    ],
    'rating': {
      'stars': 5,
      'difficulty': 'Moderate',
      'comment': 'A rewarding ridge walk with a shaded approach.',
    },
  });
}

class _CaptureRatingPage extends StatefulWidget {
  const _CaptureRatingPage({required this.history});
  final HikeHistoryDetail history;
  @override
  State<_CaptureRatingPage> createState() => _CaptureRatingPageState();
}

class _CaptureRatingPageState extends State<_CaptureRatingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<bool>(
        context: context,
        builder: (_) => TrailRatingDialog(
          trailName: widget.history.summary.trailName,
          onSubmit: (_) async {},
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => HikeHistoryDetailPage(
    summary: widget.history.summary,
    loadDetail: (_) async => widget.history,
    enableInteractiveRoute: false,
  );
}

/// Injectable repository supplies only local fictional content to current widgets.
class _CaptureProductRepository extends HikerCircleFirebaseRepository {
  _CaptureProductRepository(this.data)
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'Website media demo',
        ),
      );
  final _CaptureProductData data;
  @override
  Future<List<Trail>> loadTrails() async => data.trails;
  @override
  Stream<List<Trail>> watchTrails() => Stream.value(data.trails);
  @override
  FirebaseFirestore get firestore => _CaptureFirestore(data);
  @override
  Future<Trail> refreshTrailWeatherViaCloud(Trail trail) async =>
      trail.copyWith(weather: data.weather);
  @override
  Future<TrailWeather> loadTrailWeatherForecast(
    String trailId, {
    bool refresh = false,
  }) async => data.weather;
  @override
  Stream<TrailWeather> watchTrailCheckpointWeather(
    Trail trail,
    TrailWeatherLocation location,
  ) => Stream.value(data.weather);
  @override
  Future<TrailHazardAssessment> loadTrailHazardAssessment(
    String trailId, {
    bool forceRefresh = false,
  }) async => const TrailHazardAssessment(alerts: [], isFresh: true);
}

// TrailDetailPage receives its live-document boundary from the injected repo.
// These interfaces expose a local stream; no SDK instance or cloud transport is created.
class _CaptureFirestore implements FirebaseFirestore {
  _CaptureFirestore(this.data);
  final _CaptureProductData data;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _CaptureCollection(data);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The SDK's @sealed interfaces are implemented only by this local media fixture.
// ignore: subtype_of_sealed_class
class _CaptureCollection implements CollectionReference<Map<String, dynamic>> {
  _CaptureCollection(this.data);
  final _CaptureProductData data;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _CaptureDocument(data);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _CaptureDocument implements DocumentReference<Map<String, dynamic>> {
  _CaptureDocument(this.data);
  final _CaptureProductData data;
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.value(_CaptureSnapshot(data));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _CaptureSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _CaptureSnapshot(this.product);
  final _CaptureProductData product;
  @override
  Map<String, dynamic> data() => product.trail.toFirestore();
  @override
  bool get exists => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
