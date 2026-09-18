import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/hike_briefing_weather_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/next_hike_briefing.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

UpcomingHike testHike({DateTime? departure}) {
  final time = departure ?? DateTime.now().add(const Duration(hours: 2));
  return UpcomingHike(
    id: 'next',
    sessionId: '',
    trailId: 'ridge',
    trailName: 'Penang Hill Heritage Trail',
    latitude: 5.4,
    longitude: 100.2,
    area: 'Penang Hill',
    state: 'Penang',
    distanceKm: 5.2,
    durationMinutes: 180,
    difficulty: 'Moderate',
    startPointName: 'Heritage trailhead',
    destinationName: 'Summit',
    departureTime: time,
    expectedReturnTime: time.add(const Duration(hours: 3)),
    hikeType: 'solo',
    participantCount: 1,
    creatorPhone: 'me',
    creatorName: 'Me',
    createdAt: DateTime.now(),
  );
}

TrailWeather testForecast(DateTime start) {
  final first = DateTime.utc(
    start.year,
    start.month,
    start.day,
  ).subtract(const Duration(days: 1));
  final times = List.generate(
    96,
    (i) => first.add(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
  );
  return TrailWeather(
    summary: '',
    temperatureRange: '',
    rainProbability: 0,
    cachedAt: DateTime.now(),
    forecastData: {
      'utc_offset_seconds': 28800,
      'hourly': {
        'time': times,
        'temperature_2m': List.filled(96, 26),
        'precipitation_probability': List.filled(96, 65),
        'wind_speed_10m': List.filled(96, 10),
      },
    },
  );
}

class TestWeatherService extends HikeBriefingWeatherService {
  TestWeatherService(this.weather);
  final TrailWeather weather;
  int calls = 0;
  bool fail = false;
  Completer<TrailWeather>? pending;
  @override
  Future<TrailWeather> fetch(
    double latitude,
    double longitude, {
    bool force = false,
  }) async {
    calls++;
    if (fail) throw const FormatException('Offline');
    return pending == null ? weather : pending!.future;
  }
}

void main() {
  testWidgets(
    'gear progress, countdown and forecast details use the scheduled hike',
    (tester) async {
      final hike = testHike();
      final forecast = testForecast(hike.departureTime);
      final trail = Trail.fromPersistence({
        'trailId': 'ridge',
        'name': hike.trailName,
      });
      final plan = PlannedHike(
        trail: trail,
        plannedStartTime: hike.departureTime,
        expectedReturnTime: hike.expectedReturnTime,
        weatherCached: false,
        offlineMapDownloaded: false,
        emergencyContactsSelected: false,
        checklistCompleted: 6,
        checklistTotal: 24,
        phoneBatteryLevel: 40,
        liveLocationConfigured: false,
        upcomingHikeId: hike.id,
      );
      var reviews = 0;
      final service = TestWeatherService(forecast);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NextHikeBriefing(
                hike: hike,
                phoneNumber: 'me',
                plannedHike: plan,
                weatherService: service,
                onReview: () => reviews++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('packed · gear & safety'), findsOneWidget);
      expect(find.text('Countdown to departure'), findsNothing);
      expect(find.textContaining('Hosting'), findsNothing);
      expect(find.textContaining('Difficulty not rated'), findsOneWidget);
      expect(find.text('25% ready'), findsNothing);
      expect(find.text('65% peak chance'), findsOneWidget);
      expect(find.text('Add emergency contacts'), findsNothing);
      expect(find.text('Phone 40%'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('next-hike-briefing'))).height,
        lessThan(520),
      );
      expect(service.calls, 1);
      await tester.ensureVisible(find.text('Final preparation review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Final preparation review'));
      expect(reviews, 1);
      await tester.ensureVisible(find.text('65% peak chance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('65% peak chance'));
      await tester.pumpAndSettle();
      expect(find.text('Your hiking forecast'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(service.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('far-future departure makes no API request', (tester) async {
    final hike = testHike(
      departure: DateTime.now().add(const Duration(days: 12)),
    );
    final service = TestWeatherService(testForecast(hike.departureTime));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NextHikeBriefing(
              hike: hike,
              phoneNumber: 'me',
              weatherService: service,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.textContaining('Forecast available closer'), findsOneWidget);
  });
  testWidgets(
    'failed weather can be retried and disposing ignores pending response',
    (tester) async {
      final hike = testHike();
      final service = TestWeatherService(testForecast(hike.departureTime))
        ..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NextHikeBriefing(
                hike: hike,
                phoneNumber: 'me',
                weatherService: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Couldn’t refresh'), findsOneWidget);
      service.fail = false;
      service.pending = Completer<TrailWeather>();
      await tester.ensureVisible(find.byTooltip('Refresh hike weather'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh hike weather'));
      await tester.pump();
      expect(service.calls, 2);
      await tester.pumpWidget(const SizedBox());
      service.pending!.complete(service.weather);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('hidden briefing waits until visible to fetch', (tester) async {
    final hike = testHike();
    final service = TestWeatherService(testForecast(hike.departureTime));
    Widget page(bool visible) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: NextHikeBriefing(
            hike: hike,
            phoneNumber: 'me',
            weatherService: service,
            isVisible: visible,
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.pump(const Duration(minutes: 1));
    expect(service.calls, 0);
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
  });
  testWidgets('briefing fits narrow screens with large text in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hike = testHike();
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: NextHikeBriefing(
                  hike: hike,
                  phoneNumber: 'me',
                  weatherService: TestWeatherService(
                    testForecast(hike.departureTime),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
