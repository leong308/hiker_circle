import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/home/Data/active_hike_weather_controller.dart';
import 'package:hiker_circle/home/Data/active_hike_weather_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/active_hike_weather_sheet.dart';

class Weather extends ActiveHikeWeatherService {
  Weather(this.load);
  final Future<ActiveHikeWeatherSnapshot> Function(ActiveHikeSession) load;
  final calls = <ActiveHikeSession>[];
  @override
  Future<ActiveHikeWeatherSnapshot> fetchForHike(ActiveHikeSession hike) {
    calls.add(hike);
    return load(hike);
  }
}

class MemoryDatabase extends LocalSessionDatabase {
  LocalCachedEntity? cached;
  @override
  Future<void> saveCachedEntity(LocalCachedEntity entity) async {
    cached = entity;
  }

  @override
  Future<LocalCachedEntity?> loadCachedEntity({
    required String ownerPhoneNumber,
    required String entityType,
    required String entityId,
    bool includeExpired = false,
  }) async => cached;
}

ActiveHikeSession hike({
  String sessionId = 'offline-start',
  String start = '2026-10-12T08:00:00Z',
}) => ActiveHikeSession.fromPersistence({
  'sessionId': sessionId,
  'startedAt': start,
});

ActiveHikeWeatherSnapshot readings(
  DateTime fetchedAt, {
  bool fallback = false,
  double temperature = 25.2,
}) => ActiveHikeWeatherSnapshot(
  fetchedAt: fetchedAt,
  isCachedFallback: fallback,
  samples: [
    for (var i = 0; i < 4; i++)
      ActiveHikeWeatherSample(
        label: [
          'Your location',
          '200 m upcoming',
          '500 m upcoming',
          '1 km upcoming',
        ][i],
        shortLabel: ['Now', '200m', '500m', '1km'][i],
        distanceAheadMeters: [0, 200, 500, 1000][i],
        coordinate: HikeCoordinate(
          latitude: 3.1,
          longitude: 101.6 + i / 1000,
          capturedAt: fetchedAt,
          accuracyMeters: 12,
          altitudeMeters: 250,
        ),
        temperatureCelsius: temperature,
        apparentTemperatureCelsius: 27.4,
        humidityPercent: 82,
        windSpeedKph: 5.5,
        precipitationMillimeters: 0.3,
        weatherCode: 2,
        observedAt: fetchedAt.subtract(const Duration(minutes: 5)),
        isCached: fallback,
      ),
  ],
);

void main() {
  late Directory directory;
  late LocalSessionDatabase database;
  late DateTime now;
  final controllers = <ActiveHikeWeatherController>[];
  const owner = '+60111111111';

  ActiveHikeWeatherController controller(
    Weather service, {
    String phone = owner,
  }) {
    final result = ActiveHikeWeatherController(
      database: database,
      ownerPhoneNumber: phone,
      service: service,
      now: () => now,
    );
    controllers.add(result);
    return result;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hike_weather_cache_');
    database = LocalSessionDatabase(
      databasePath: '${directory.path}/weather.db',
    );
    now = DateTime.utc(2026, 10, 12, 8, 10);
  });
  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'SQLite retains every weather reading, sampled position and original timestamp',
    () async {
      final original = readings(now);
      final service = Weather((_) async => original);
      final cache = controller(service);
      await cache.bind(hike());
      final row = await database.loadCachedEntity(
        ownerPhoneNumber: owner,
        entityType: ActiveHikeWeatherController.cacheEntityType,
        entityId: ActiveHikeWeatherController.cacheKey(hike()),
      );
      expect(row, isNotNull);
      expect(row!.cachedAt, now);
      final restored = ActiveHikeWeatherSnapshot.fromPersistence(
        Map<String, dynamic>.from(row.payload['snapshot'] as Map),
      );
      expect(restored.toPersistence(), original.toPersistence());
      expect(row.payload['lastAttemptAt'], now.toIso8601String());
      expect(row.payload['lastRefreshFailed'], isFalse);
    },
  );

  testWidgets(
    'automatic refresh runs at fifteen minutes, including after a failed request',
    (tester) async {
      DateTime time() => tester.binding.clock.now();
      final firstUpdate = time();
      var fail = false;
      final service = Weather((_) async {
        if (fail) throw const ActiveHikeWeatherException('offline');
        return readings(time());
      });
      final cache = ActiveHikeWeatherController(
        database: MemoryDatabase(),
        ownerPhoneNumber: owner,
        service: service,
        now: time,
      );
      await cache.bind(hike());
      expect(service.calls, hasLength(1));
      await tester.pump(const Duration(minutes: 14, seconds: 59));
      expect(service.calls, hasLength(1));
      fail = true;
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, hasLength(2));
      expect(cache.value.snapshot!.fetchedAt, firstUpdate);
      expect(cache.value.error, isNotNull);
      await tester.pump(const Duration(minutes: 14, seconds: 59));
      expect(service.calls, hasLength(2));
      fail = false;
      await tester.pump(const Duration(seconds: 1));
      expect(service.calls, hasLength(3));
      expect(
        cache.value.snapshot!.fetchedAt,
        firstUpdate.add(const Duration(minutes: 30)),
      );
      cache.dispose();
    },
  );

  test(
    'GPS updates, remapped IDs and repeated refreshes fetch only once per fifteen minutes',
    () async {
      final service = Weather((_) async => readings(now));
      final cache = controller(service);
      await cache.bind(hike());
      now = now.add(const Duration(minutes: 1));
      for (var i = 0; i < 30; i++) {
        await cache.bind(
          hike().copyWith(
            sessionId: 'cloud-canonical',
            latestLocation: HikeCoordinate(
              latitude: 3.2 + i / 10000,
              longitude: 101.7,
              capturedAt: now,
            ),
          ),
        );
        await cache.refresh();
      }
      expect(service.calls, hasLength(1));
      expect(cache.value.snapshot, isNotNull);
      now = now.add(const Duration(minutes: 13, seconds: 59));
      await cache.refresh();
      expect(service.calls, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      await cache.refresh();
      expect(service.calls, hasLength(2));
      expect(service.calls.last.sessionId, 'cloud-canonical');
      expect(service.calls.last.latestLocation!.latitude, greaterThan(3.2));
    },
  );

  test(
    'failed refresh retains successful data and restart restores it without another request',
    () async {
      final originalTime = now;
      var fail = false;
      final service = Weather((_) async {
        if (fail) throw const ActiveHikeWeatherException('offline');
        return readings(now);
      });
      final cache = controller(service);
      await cache.bind(hike());
      final original = cache.value.snapshot!.toPersistence();
      fail = true;
      now = now.add(const Duration(minutes: 15));
      await cache.refresh();
      expect(cache.value.snapshot!.toPersistence(), original);
      expect(cache.value.snapshot!.fetchedAt, originalTime);
      expect(cache.value.error, isNotNull);
      now = now.add(const Duration(minutes: 2));
      await cache.refresh();
      expect(service.calls, hasLength(2));

      // Reopen the real SQLite file, with no in-memory controller cache.
      cache.dispose();
      controllers.remove(cache);
      await database.close();
      database = LocalSessionDatabase(
        databasePath: '${directory.path}/weather.db',
      );
      final restored = controller(service);
      await restored.bind(hike(sessionId: 'cloud-canonical'));
      expect(service.calls, hasLength(2));
      expect(restored.value.snapshot!.toPersistence(), original);
      expect(restored.value.error, isNotNull);
      expect(
        restored.value.nextRefreshAt,
        originalTime.add(const Duration(minutes: 30)),
      );
    },
  );

  test(
    'older trail fallback never replaces the actual last successful route readings',
    () async {
      var fallback = false;
      final service = Weather(
        (_) async => readings(
          fallback ? now.subtract(const Duration(hours: 4)) : now,
          fallback: fallback,
          temperature: fallback ? 15 : 25.2,
        ),
      );
      final cache = controller(service);
      await cache.bind(hike());
      final original = cache.value.snapshot!.toPersistence();
      fallback = true;
      now = now.add(const Duration(minutes: 15));
      await cache.refresh();
      expect(cache.value.snapshot!.toPersistence(), original);
      expect(cache.value.error, isNotNull);
    },
  );

  test(
    'cache and failed-attempt cooldown are isolated by owner and actual hike',
    () async {
      final success = controller(Weather((_) async => readings(now)));
      await success.bind(hike());
      final offline = Weather(
        (_) async => throw const ActiveHikeWeatherException('offline'),
      );
      final otherOwner = controller(offline, phone: '+60222222222');
      await otherOwner.bind(hike());
      expect(otherOwner.value.snapshot, isNull);
      final newHike = controller(offline);
      await newHike.bind(hike(start: '2026-10-12T08:30:00Z'));
      expect(newHike.value.snapshot, isNull);
      expect(offline.calls, hasLength(2));
      final reopened = controller(offline);
      await reopened.bind(hike(start: '2026-10-12T08:30:00Z'));
      expect(offline.calls, hasLength(2));
      expect(reopened.value.snapshot, isNull);
    },
  );

  test(
    'restored data remains visible during a request and concurrent requests share one fetch',
    () async {
      await controller(Weather((_) async => readings(now))).bind(hike());
      final previousTime = now;
      now = now.add(const Duration(minutes: 15));
      final pending = Completer<ActiveHikeWeatherSnapshot>();
      final loading = Completer<void>();
      final service = Weather((_) {
        loading.complete();
        return pending.future;
      });
      final cache = controller(service);
      final binding = cache.bind(hike());
      await loading.future;
      expect(cache.value.isLoading, isTrue);
      expect(cache.value.snapshot!.fetchedAt, previousTime);
      final concurrent = cache.refresh();
      pending.complete(readings(now));
      await Future.wait([binding, concurrent]);
      expect(service.calls, hasLength(1));
      expect(cache.value.snapshot!.fetchedAt, now);
    },
  );

  test(
    'late response from a previous hike cannot overwrite the new hike on screen',
    () async {
      final old = Completer<ActiveHikeWeatherSnapshot>();
      final started = Completer<void>();
      final service = Weather((active) {
        if (active.sessionId == 'old') {
          started.complete();
          return old.future;
        }
        return Future.value(readings(now, temperature: 28));
      });
      final cache = controller(service);
      final oldBinding = cache.bind(hike(sessionId: 'old'));
      await started.future;
      await cache.bind(hike(sessionId: 'new', start: '2026-10-12T08:30:00Z'));
      old.complete(
        readings(now.subtract(const Duration(minutes: 10)), temperature: 15),
      );
      await oldBinding;
      expect(cache.value.snapshot!.current!.temperatureCelsius, 28);
    },
  );

  testWidgets(
    'sheet preserves cards through refresh and failure and shows last updated below them',
    (tester) async {
      final snapshot = readings(DateTime(2026, 10, 12, 17, 0));
      final state = ValueNotifier(
        ActiveHikeWeatherViewState(snapshot: snapshot),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveHikeWeatherSheet(weatherState: state, onRetry: () {}),
          ),
        ),
      );
      expect(find.text('Weather along your hike'), findsOneWidget);
      expect(find.text('25°'), findsNWidgets(4));
      expect(find.textContaining('every 15 minutes'), findsOneWidget);
      state.value = ActiveHikeWeatherViewState(
        snapshot: snapshot,
        isLoading: true,
      );
      await tester.pump();
      expect(find.text('25°'), findsNWidgets(4));
      state.value = ActiveHikeWeatherViewState(
        snapshot: snapshot,
        error: 'offline',
      );
      await tester.pump();
      expect(find.text('25°'), findsNWidgets(4));
      expect(find.text('Weather is temporarily unavailable.'), findsNothing);
      expect(
        find.textContaining('Showing the previous update'),
        findsOneWidget,
      );
      final updated = find.byKey(
        const ValueKey('active-hike-weather-last-updated'),
      );
      expect(find.text('Last updated 12/10 · 17:00'), findsOneWidget);
      expect(
        tester.getTopLeft(updated).dy,
        greaterThan(tester.getBottomLeft(find.text('1 km upcoming')).dy),
      );
      expect(tester.takeException(), isNull);
      state.dispose();
    },
  );
}
