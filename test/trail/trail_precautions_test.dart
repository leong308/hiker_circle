import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/Model/trail_precautions.dart';

void main() {
  final midnight = DateTime.utc(2026, 9, 10).millisecondsSinceEpoch ~/ 1000;
  TrailWeather weather({
    Map<String, List<num?>> overrides = const {},
    bool stale = false,
  }) {
    final hourly = <String, dynamic>{
      'time': List.generate(48, (i) => midnight + i * 3600),
      for (final key in [
        'temperature_2m',
        'relative_humidity_2m',
        'apparent_temperature',
        'precipitation',
        'precipitation_probability',
        'weather_code',
        'wind_speed_10m',
        'wind_gusts_10m',
        'visibility',
        'uv_index',
      ])
        key: List<num?>.filled(
          48,
          key == 'visibility'
              ? 10000
              : key == 'temperature_2m'
              ? 25
              : 0,
        ),
      ...overrides,
    };
    return TrailWeather(
      summary: '',
      temperatureRange: '',
      rainProbability: 0,
      cachedAt: DateTime.utc(2026, 9, stale ? 9 : 10),
      forecastData: {
        'utc_offset_seconds': 0,
        'daily': {
          'time': [midnight],
          'sunrise': [midnight + 6 * 3600],
          'sunset': [midnight + 19 * 3600],
        },
        'hourly': hourly,
      },
    );
  }

  List<TrailPrecaution> evaluate(
    TrailWeather w, {
    int? departure,
    int gain = 0,
    int duration = 120,
  }) => trailPrecautions(
    weather: w,
    day: 0,
    now: DateTime.utc(2026, 9, 10),
    departureMinute: departure,
    elevationGain: gain,
    durationMinutes: duration,
  );
  Set<String> ids(List<TrailPrecaution> values) =>
      values.map((v) => v.id).toSet();
  test('calm complete forecast does not invent hazards', () {
    expect(evaluate(weather()), isEmpty);
  });
  test('hourly window excludes later storms and includes delay buffer', () {
    final codes = List<num?>.filled(48, 0)..[15] = 95;
    expect(
      ids(
        evaluate(
          weather(overrides: {'weather_code': codes}),
          departure: 8 * 60,
        ),
      ),
      isNot(contains('storm')),
    );
    expect(
      ids(
        evaluate(
          weather(overrides: {'weather_code': codes}),
          departure: 13 * 60,
        ),
      ),
      contains('storm'),
    );
  });
  test('humid heat must occur in same hour and combines ascent', () {
    final temp = List<num?>.filled(48, 25)..[8] = 30;
    final humidity = List<num?>.filled(48, 50)..[9] = 80;
    expect(
      ids(
        evaluate(
          weather(
            overrides: {
              'temperature_2m': temp,
              'relative_humidity_2m': humidity,
            },
          ),
        ),
      ),
      isNot(contains('heat')),
    );
    humidity[8] = 80;
    final result = evaluate(
      weather(
        overrides: {'temperature_2m': temp, 'relative_humidity_2m': humidity},
      ),
      gain: 700,
    );
    expect(ids(result), contains('heat'));
    expect(ids(result), isNot(contains('ascent')));
    expect(result.firstWhere((c) => c.id == 'heat').message, contains('700 m'));
  });
  test(
    'heavy rain supersedes generic wet trail; rain chance is not intensity',
    () {
      expect(
        evaluate(
          weather(
            overrides: {'precipitation_probability': List.filled(48, 100)},
          ),
        ).firstWhere((c) => c.id == 'rain').priority,
        1,
      );
      final result = evaluate(
        weather(overrides: {'precipitation': List.filled(48, 10)}),
      );
      expect(result.where((c) => c.id == 'rain'), hasLength(1));
      expect(result.first.priority, 3);
    },
  );
  test('sunset, darkness and long hike thresholds', () {
    expect(
      ids(evaluate(weather(), departure: 16 * 60 + 30)),
      contains('sunset'),
    );
    expect(ids(evaluate(weather(), departure: 17 * 60)), contains('dark'));
    expect(ids(evaluate(weather(), departure: 5 * 60)), contains('dark'));
    expect(ids(evaluate(weather(), duration: 240)), contains('duration'));
  });
  test(
    'stale, null and truncated forecast warn instead of declaring safety',
    () {
      expect(ids(evaluate(weather(stale: true))), contains('data'));
      expect(
        ids(
          evaluate(
            weather(
              overrides: {
                'visibility': [null],
              },
            ),
          ),
        ),
        contains('data'),
      );
      expect(
        ids(evaluate(weather(), departure: 23 * 60, duration: 2000)),
        contains('data'),
      );
    },
  );
  test('wind UV visibility and ascent boundaries', () {
    final result = evaluate(
      weather(
        overrides: {
          'wind_gusts_10m': List.filled(48, 40),
          'uv_index': List.filled(48, 3),
          'visibility': List.filled(48, 999),
        },
      ),
      gain: 500,
    );
    expect(ids(result), containsAll(['wind', 'uv', 'visibility', 'ascent']));
  });
}
