import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/home_screen_widget_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'next_hike_briefing_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/home_widgets');
  final snapshots = <Map<String, dynamic>>[];
  setUp(() {
    snapshots.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'update');
          snapshots.add(
            jsonDecode(call.arguments as String) as Map<String, dynamic>,
          );
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'publishes a native snapshot and scheduled forecast with preparation',
    () async {
      final hike = fixtures.testHike();
      final service = HomeScreenWidgetService(
        channel: channel,
        weather: fixtures.TestWeatherService(
          fixtures.testForecast(hike.departureTime),
        ),
      );
      final plan = PlannedHike(
        trail: Trail.fromPersistence({'trailId': hike.trailId}),
        plannedStartTime: hike.departureTime,
        expectedReturnTime: hike.expectedReturnTime,
        weatherCached: true,
        offlineMapDownloaded: false,
        emergencyContactsSelected: true,
        checklistCompleted: 8,
        checklistTotal: 24,
        phoneBatteryLevel: 85,
        liveLocationConfigured: false,
        upcomingHikeId: hike.id,
      );
      await service.update(hikes: [hike], plan: plan);
      final item = (snapshots.last['hikes'] as List).single as Map;
      expect(item['name'], hike.trailName);
      expect(item['gearDone'], 8);
      expect(item['weather']['rain'], 65);
      expect(item['weather']['covered'], true);
      expect(
        item['departure'],
        hike.departureTime.millisecondsSinceEpoch ~/ 1000,
      );
      expect(jsonEncode(item), isNot(contains('creatorPhone')));
      expect(jsonEncode(item), isNot(contains('participantPhones')));
      final count = snapshots.length;
      await service.update(hikes: [hike], plan: plan);
      expect(snapshots.length, count);
    },
  );

  test(
    'clear prevents an outstanding forecast from restoring signed-out data',
    () async {
      final hike = fixtures.testHike();
      final weather = fixtures.TestWeatherService(
        fixtures.testForecast(hike.departureTime),
      )..pending = Completer<TrailWeather>();
      final service = HomeScreenWidgetService(
        channel: channel,
        weather: weather,
      );
      final updating = service.update(hikes: [hike]);
      for (var i = 0; i < 10 && weather.calls == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(weather.calls, 1);
      await service.clear();
      weather.pending!.complete(weather.weather);
      await updating;
      expect(snapshots.last['hikes'], isEmpty);
    },
  );

  test(
    'expired schedules are cleared and future dates do not fetch weather',
    () async {
      final old = fixtures.testHike(
        departure: DateTime.now().subtract(const Duration(days: 1)),
      );
      final future = fixtures.testHike(
        departure: DateTime.now().add(const Duration(days: 12)),
      );
      final weather = fixtures.TestWeatherService(
        fixtures.testForecast(future.departureTime),
      );
      final service = HomeScreenWidgetService(
        channel: channel,
        weather: weather,
      );
      await service.update(hikes: [old, future]);
      expect((snapshots.last['hikes'] as List).length, 1);
      expect(weather.calls, 0);
      await service.update(hikes: [old]);
      expect(snapshots.last['hikes'], isEmpty);
    },
  );

  test(
    'weather failure preserves the hike instead of hiding the widget',
    () async {
      final hike = fixtures.testHike();
      final weather = fixtures.TestWeatherService(
        fixtures.testForecast(hike.departureTime),
      )..fail = true;
      final service = HomeScreenWidgetService(
        channel: channel,
        weather: weather,
      );
      await service.update(hikes: [hike]);
      final item = (snapshots.last['hikes'] as List).single as Map;
      expect(item['name'], hike.trailName);
      expect(item.containsKey('weather'), isFalse);
    },
  );
}
