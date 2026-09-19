import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hiker_circle/home/Data/hike_briefing_weather_service.dart';
import 'package:hiker_circle/home/Model/hike_weather_briefing.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

Map<String, dynamic> forecastData() {
  final midnight = DateTime.utc(2026, 9, 14, 16);
  int epoch(DateTime date) => date.millisecondsSinceEpoch ~/ 1000;
  return {
    'utc_offset_seconds': 28800,
    'hourly': <String, dynamic>{
      'time': List.generate(24, (i) => epoch(midnight.add(Duration(hours: i)))),
      'temperature_2m': List.generate(24, (i) => 20 + i.toDouble()),
      'precipitation_probability': List.generate(
        24,
        (i) => i == 19 ? 99 : i * 2,
      ),
    },
    'daily': {
      'time': [epoch(midnight)],
      'sunrise': [epoch(midnight.add(const Duration(hours: 7, minutes: 9)))],
      'sunset': [epoch(midnight.add(const Duration(hours: 19, minutes: 19)))],
    },
  };
}

TrailWeather weather(Map<String, dynamic> data) => TrailWeather(
  summary: '',
  temperatureRange: '',
  rainProbability: 0,
  cachedAt: DateTime.now(),
  forecastData: data,
);
void main() {
  final start = DateTime.utc(2026, 9, 14, 21, 30); // 05:30 at trail
  final end = DateTime.utc(2026, 9, 15, 0, 30); // 08:30
  test('summarizes only overlapping hours, not the day maximum', () {
    final result = HikeWeatherBriefing.fromWeather(
      weather(forecastData()),
      start,
      end,
    );
    expect(result.covered, isTrue);
    expect(result.hours.length, 4);
    expect(result.minTemperature, 25);
    expect(result.maxTemperature, 28);
    expect(result.peakRainChance, 16);
    expect(result.startsBeforeSunrise, isTrue);
    expect(result.endsAfterSunset, isFalse);
  });
  test('an exact return boundary excludes the following hour', () {
    final result = HikeWeatherBriefing.fromWeather(
      weather(forecastData()),
      start,
      DateTime.utc(2026, 9, 15),
    );
    expect(result.hours.length, 3);
    expect(result.peakRainChance, 14);
  });
  test('uncovered dates and gaps do not produce misleading window values', () {
    final data = forecastData();
    (data['hourly']['time'] as List).removeAt(6);
    final gap = HikeWeatherBriefing.fromWeather(weather(data), start, end);
    expect(gap.covered, isFalse);
    expect(gap.peakRainChance, isNull);
    final later = HikeWeatherBriefing.fromWeather(
      weather(forecastData()),
      start.add(const Duration(days: 8)),
      end.add(const Duration(days: 8)),
    );
    expect(later.covered, isFalse);
    expect(later.minTemperature, isNull);
  });
  test(
    'missing rain is unavailable, never zero, while temperature remains valid',
    () {
      final data = forecastData();
      data['hourly']['precipitation_probability'] = <dynamic>[
        for (var i = 0; i < 24; i++) i == 6 ? null : 20,
      ];
      final result = HikeWeatherBriefing.fromWeather(weather(data), start, end);
      expect(result.covered, isTrue);
      expect(result.peakRainChance, isNull);
      expect(result.minTemperature, 25);
    },
  );
  test('daylight after-sunset comparison uses timestamps, not device time', () {
    final result = HikeWeatherBriefing.fromWeather(
      weather(forecastData()),
      DateTime.utc(2026, 9, 15, 9),
      DateTime.utc(2026, 9, 15, 12),
    );
    expect(result.startsBeforeSunrise, isFalse);
    expect(result.endsAfterSunset, isTrue);
    expect(result.utcOffset, const Duration(hours: 8));
  });
  test('invalid windows are not treated as a forecast', () {
    expect(
      HikeWeatherBriefing.fromWeather(
        weather(forecastData()),
        end,
        start,
      ).covered,
      isFalse,
    );
  });
  test(
    'service uses trail coordinates and caches/deduplicates requests',
    () async {
      var calls = 0;
      final service = HikeBriefingWeatherService(
        client: MockClient((request) async {
          calls++;
          expect(request.url.queryParameters['latitude'], '5.4');
          expect(request.url.queryParameters['longitude'], '100.2');
          expect(request.url.queryParameters['forecast_days'], '16');
          expect(request.url.queryParameters['past_days'], '1');
          expect(request.url.queryParameters['wind_speed_unit'], 'kmh');
          expect(
            request.url.queryParameters['hourly'],
            contains('wind_gusts_10m'),
          );
          expect(request.url.queryParameters['hourly'], contains('uv_index'));
          expect(request.url.queryParameters['timezone'], 'auto');
          expect(request.url.queryParameters['timeformat'], 'unixtime');
          expect(
            request.url.queryParameters['current'],
            contains('temperature_2m'),
          );
          expect(
            request.url.queryParameters['current'],
            contains('precipitation'),
          );
          return http.Response(jsonEncode(forecastData()), 200);
        }),
      );
      await Future.wait([service.fetch(5.4, 100.2), service.fetch(5.4, 100.2)]);
      await service.fetch(5.4, 100.2);
      expect(calls, 1);
      await service.fetch(5.4, 100.2, force: true);
      expect(calls, 2);
    },
  );
  test('failed requests back off; manual retry can recover', () async {
    var calls = 0;
    final service = HikeBriefingWeatherService(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          calls == 1 ? '{}' : jsonEncode(forecastData()),
          calls == 1 ? 503 : 200,
        );
      }),
    );
    await expectLater(service.fetch(5, 100), throwsFormatException);
    await expectLater(service.fetch(5, 100), throwsFormatException);
    expect(calls, 1);
    await service.fetch(5, 100, force: true);
    expect(calls, 2);
  });
}
