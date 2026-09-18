import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/session_weather_forecast.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

final midnight = DateTime.utc(2026, 9, 16, 16); // 17 Sep, trail midnight UTC+8.
TrailWeather sessionWeather({
  bool gap = false,
  bool missingWind = false,
  bool beforeRain = true,
  bool afterStorm = false,
}) {
  final times = List.generate(
    48,
    (i) => midnight.add(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
  );
  final data = <String, dynamic>{
    'utc_offset_seconds': 28800,
    'hourly': {
      'time': [for (var i = 0; i < 48; i++) gap && i == 9 ? null : times[i]],
      'temperature_2m': List.filled(48, 26),
      'apparent_temperature': List.filled(48, 28),
      'precipitation_probability': List.generate(
        48,
        (i) => beforeRain && i == 7 ? 80 : 20,
      ),
      'precipitation': List.filled(48, 0),
      'relative_humidity_2m': List.filled(48, 70),
      'wind_speed_10m': List.generate(
        48,
        (i) => missingWind && i == 9 ? null : 10,
      ),
      'wind_gusts_10m': List.filled(48, 15),
      'visibility': List.filled(48, 10000),
      'uv_index': List.filled(48, 2),
      'weather_code': List.generate(48, (i) => afterStorm && i == 12 ? 95 : 1),
    },
    'daily': {
      'time': [times[0], times[24]],
      'sunrise': [times[7], times[31]],
      'sunset': [times[19], times[43]],
    },
  };
  return TrailWeather(
    summary: '',
    temperatureRange: '',
    rainProbability: 0,
    cachedAt: DateTime.now(),
    forecastData: data,
  );
}

void main() {
  SessionWeatherForecast model(TrailWeather weather) => SessionWeatherForecast(
    weather,
    midnight.add(const Duration(hours: 8, minutes: 30)),
    midnight.add(const Duration(hours: 11, minutes: 30)),
  );
  test(
    'fractional departure clips a session with exactly two-hour buffers and separate statistics',
    () {
      final f = model(sessionWeather());
      expect(f.from, midnight.add(const Duration(hours: 6, minutes: 30)));
      expect(f.to, midnight.add(const Duration(hours: 13, minutes: 30)));
      expect(f.session.hours.length, 4);
      expect(f.buffer.hours.length, 8);
      expect(f.session.peakRainChance, 20);
      expect(f.before.peakRainChance, 80);
      final warnings = f.cautions(DateTime.now());
      expect(warnings.any((c) => c.id == 'Before departure-rain'), isTrue);
      expect(warnings.any((c) => c.id == 'rain' || c.id == 'dark'), isFalse);
    },
  );
  test('a storm after return is explicitly a buffer risk', () {
    final warnings = model(
      sessionWeather(beforeRain: false, afterStorm: true),
    ).cautions(DateTime.now());
    expect(warnings.any((c) => c.id == 'After expected return-storm'), isTrue);
    expect(warnings.any((c) => c.id == 'storm'), isFalse);
  });
  test('gaps and missing metrics remain unavailable', () {
    final gap = model(sessionWeather(gap: true));
    expect(gap.session.covered, isFalse);
    expect(gap.peak('wind_speed_10m'), isNull);
    expect(gap.cautions(DateTime.now()).any((c) => c.id == 'data'), isTrue);
    final missing = model(sessionWeather(missingWind: true));
    expect(missing.session.covered, isTrue);
    expect(missing.peak('wind_speed_10m'), isNull);
    expect(missing.peak('apparent_temperature'), 28);
  });
  test('overnight schedule keeps dates and receives darkness caution', () {
    final f = SessionWeatherForecast(
      sessionWeather(),
      midnight.add(const Duration(hours: 23, minutes: 30)),
      midnight.add(const Duration(hours: 27)),
    );
    expect(f.buffer.covered, isTrue);
    expect(f.session.hours.length, 4);
    expect(f.cautions(DateTime.now()).any((c) => c.id == 'dark'), isTrue);
  });
}
