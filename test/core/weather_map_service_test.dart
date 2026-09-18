import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/weather_map_service.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test(
    '10-minute estimates interpolate the hourly trend without additional data',
    () {
      final start = DateTime.utc(2026, 9, 14);
      final forecast = TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 99,
        cachedAt: start,
        forecastData: {
          'utc_offset_seconds': 28800,
          'hourly': {
            'time': [
              start.millisecondsSinceEpoch ~/ 1000,
              start.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                  1000,
            ],
            'precipitation_probability': [20, 80],
          },
        },
      );
      for (var minute = 0; minute <= 60; minute += 10) {
        final sample = trailRainEstimateAt(
          forecast,
          forecastTime: start.add(Duration(minutes: minute)),
          now: start,
        );
        expect(sample.probability, 20 + minute);
        expect(sample.time, start.add(Duration(minutes: minute)));
      }
      expect(
        trailRainEstimateAt(
          forecast,
          forecastTime: start.add(const Duration(minutes: 19)),
          now: start,
        ).probability,
        30,
      );
      expect(
        trailRainEstimateAt(
          forecast,
          forecastTime: start.add(const Duration(minutes: 70)),
          now: start,
        ).probability,
        isNull,
      );
      expect(
        trailRainEstimateAt(
          forecast,
          forecastTime: start.add(const Duration(minutes: 20)),
          now: start.add(const Duration(hours: 4)),
        ).probability,
        isNull,
      );
    },
  );
  test('10-minute estimates do not bridge missing values or forecast gaps', () {
    final start = DateTime.utc(2026, 9, 14);
    for (final data in [
      {
        'time': [
          start.millisecondsSinceEpoch ~/ 1000,
          start.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        ],
        'precipitation_probability': [20, null],
      },
      {
        'time': [
          start.millisecondsSinceEpoch ~/ 1000,
          start.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
        ],
        'precipitation_probability': [20, 80],
      },
    ]) {
      final weather = TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: start,
        forecastData: {'hourly': data},
      );
      expect(
        trailRainEstimateAt(
          weather,
          forecastTime: start.add(const Duration(minutes: 10)),
          now: start,
        ).probability,
        isNull,
      );
    }
  });

  final now = DateTime.utc(2026, 9, 14, 3, 30);
  TrailWeather weather({
    List<dynamic>? rain,
    DateTime? cachedAt,
    List<HourlyForecast> legacy = const [],
    bool structured = true,
  }) => TrailWeather(
    summary: 'Cloudy',
    temperatureRange: '25–30 °C',
    rainProbability: 99,
    cachedAt: cachedAt ?? now.subtract(const Duration(minutes: 10)),
    hourlyForecast: legacy,
    forecastData: structured
        ? {
            'hourly': {
              'time': [
                now
                        .subtract(const Duration(minutes: 30))
                        .millisecondsSinceEpoch ~/
                    1000,
                now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
                    1000,
              ],
              'precipitation_probability': rain ?? [29, 80],
            },
          }
        : {},
  );

  test('rain uses current hour, not daily maximum or next hour', () {
    expect(currentTrailRainProbability(weather(), now), 29);
    expect(
      currentTrailRainProbability(
        weather(),
        now.add(const Duration(minutes: 30)),
      ),
      80,
    );
  });
  test('stale, future-dated and uncovered forecasts stay unavailable', () {
    expect(
      currentTrailRainProbability(
        weather(cachedAt: now.subtract(const Duration(hours: 4))),
        now,
      ),
      isNull,
    );
    expect(
      currentTrailRainProbability(
        weather(cachedAt: now.add(const Duration(hours: 1))),
        now,
      ),
      isNull,
    );
    expect(
      currentTrailRainProbability(weather(), now.add(const Duration(hours: 2))),
      isNull,
    );
  });
  test('missing or invalid probability is not reported as zero', () {
    for (final value in [null, -1, 101, double.nan, '25']) {
      expect(currentTrailRainProbability(weather(rain: [value]), now), isNull);
    }
    expect(currentTrailRainProbability(weather(rain: [0]), now), 0);
  });
  test(
    'legacy hourly forecasts remain supported without daily substitution',
    () {
      final legacy = [
        HourlyForecast(
          time: now.subtract(const Duration(minutes: 20)),
          temperature: 25,
          precipitationProbability: 42,
          weatherCode: 3,
        ),
      ];
      expect(
        currentTrailRainProbability(
          weather(structured: false, legacy: legacy),
          now,
        ),
        42,
      );
      expect(
        currentTrailRainProbability(weather(structured: false), now),
        isNull,
      );
      expect(
        currentTrailRainProbability(weather(rain: [null], legacy: legacy), now),
        isNull,
      );
    },
  );
  test(
    'arrival forecast advances with hiking elapsed time, even over four hours ahead',
    () {
      final start = DateTime.utc(2026, 9, 14, 3);
      final forecast = TrailWeather(
        summary: 'Forecast',
        temperatureRange: '20–30',
        rainProbability: 99,
        cachedAt: start,
        forecastData: {
          'hourly': {
            'time': List.generate(
              8,
              (i) =>
                  start.add(Duration(hours: i)).millisecondsSinceEpoch ~/ 1000,
            ),
            'precipitation_probability': [10, 20, 30, 40, 50, 60, 70, 80],
          },
        },
      );
      for (final hour in [0, 1, 5, 7]) {
        expect(
          trailRainProbabilityAt(
            forecast,
            forecastTime: start.add(Duration(hours: hour, minutes: 30)),
            now: start.add(const Duration(minutes: 10)),
          ),
          (hour + 1) * 10,
        );
      }
      expect(
        trailRainProbabilityAt(
          forecast,
          forecastTime: start.add(const Duration(hours: 8)),
          now: start,
        ),
        isNull,
      );
      expect(
        trailRainProbabilityAt(
          forecast,
          forecastTime: start.add(const Duration(hours: 5)),
          now: start.add(const Duration(hours: 4)),
        ),
        isNull,
      );
    },
  );

  test('arrival label uses the trail timezone and rolls over midnight', () {
    final forecast = TrailWeather(
      summary: '',
      temperatureRange: '',
      rainProbability: 0,
      cachedAt: now,
      forecastData: {'utc_offset_seconds': 28800},
    );
    expect(
      trailForecastArrivalLabel(forecast, DateTime.utc(2026, 9, 14, 17, 5)),
      '15/9 01:05',
    );
  });

  test('tile templates use only Maps 1.0 and preserve Mapbox placeholders', () {
    final template = WeatherMapService.tileTemplate(
      WeatherMapLayer.rain,
      'test key',
    );
    expect(
      template,
      'https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid=test+key',
    );
    expect(
      () => WeatherMapService.tileTemplate(WeatherMapLayer.off, 'key'),
      throwsArgumentError,
    );
    expect(
      () => WeatherMapService.tileTemplate(WeatherMapLayer.wind, ''),
      throwsArgumentError,
    );
  });
}
