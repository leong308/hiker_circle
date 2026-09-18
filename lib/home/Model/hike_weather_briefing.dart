import '../../trail/Model/trail_models.dart';

/// An hourly sample represents [time, time + 1 hour). All comparisons use epochs.
class HikeWeatherHour {
  const HikeWeatherHour(
    this.time,
    this.temperature,
    this.rainChance, {
    this.values = const {},
  });
  final Map<String, double?> values;
  double? value(String key) => key == "temperature_2m"
      ? temperature
      : key == "precipitation_probability"
      ? rainChance
      : values[key];
  final DateTime time;
  final double? temperature;
  final double? rainChance;
}

class HikeWeatherBriefing {
  const HikeWeatherBriefing({
    required this.hours,
    required this.covered,
    required this.utcOffset,
    this.minTemperature,
    this.maxTemperature,
    this.peakRainChance,
    this.sunrise,
    this.sunset,
    this.startsBeforeSunrise = false,
    this.endsAfterSunset = false,
  });

  final List<HikeWeatherHour> hours;
  final bool covered;
  final Duration utcOffset;
  final double? minTemperature, maxTemperature, peakRainChance;
  final DateTime? sunrise, sunset;
  final bool startsBeforeSunrise, endsAfterSunset;

  static HikeWeatherBriefing fromWeather(
    TrailWeather weather,
    DateTime departure,
    DateTime returning,
  ) {
    final data = weather.forecastData;
    final hourly = data['hourly'] is Map ? data['hourly'] as Map : const {};
    final times = hourly['time'] is List ? hourly['time'] as List : const [];
    final offset = Duration(
      seconds: (data['utc_offset_seconds'] as num?)?.toInt() ?? 0,
    );
    final start = departure.toUtc();
    final end = returning.toUtc();
    final hours = <HikeWeatherHour>[];
    for (var i = 0; i < times.length; i++) {
      final epoch = _number(times, i);
      if (epoch == null) continue;
      final time = _date(epoch);
      if (time.isBefore(end) &&
          time.add(const Duration(hours: 1)).isAfter(start)) {
        final rain = _number(hourly['precipitation_probability'], i);
        hours.add(
          HikeWeatherHour(
            time,
            _number(hourly['temperature_2m'], i),
            rain != null && rain >= 0 && rain <= 100 ? rain : null,
            values: {
              for (final key in [
                'apparent_temperature',
                'relative_humidity_2m',
                'precipitation',
                'weather_code',
                'wind_speed_10m',
                'wind_gusts_10m',
                'visibility',
                'uv_index',
              ])
                key: _number(hourly[key], i),
            },
          ),
        );
      }
    }
    hours.sort((a, b) => a.time.compareTo(b.time));
    var covered =
        end.isAfter(start) &&
        hours.isNotEmpty &&
        !hours.first.time.isAfter(start) &&
        !hours.last.time.add(const Duration(hours: 1)).isBefore(end);
    for (var i = 1; i < hours.length; i++) {
      if (hours[i].time.difference(hours[i - 1].time) !=
          const Duration(hours: 1)) {
        covered = false;
      }
    }
    final temps = hours.map((h) => h.temperature).whereType<double>().toList()
      ..sort();
    final rain = hours.map((h) => h.rainChance).whereType<double>().toList()
      ..sort();
    final daily = data['daily'] is Map ? data['daily'] as Map : const {};
    DateTime? sunrise, sunset;
    final days = daily['time'] is List ? daily['time'] as List : const [];
    for (var i = 0; i < days.length; i++) {
      final epoch = _number(days, i);
      if (epoch == null) continue;
      final day = _date(epoch).add(offset);
      final startLocal = start.add(offset);
      final endLocal = end.add(offset);
      if (_sameDay(day, startLocal)) {
        final value = _number(daily['sunrise'], i);
        if (value != null && value > 0) sunrise = _date(value);
      }
      if (_sameDay(day, endLocal)) {
        final value = _number(daily['sunset'], i);
        if (value != null && value > 0) sunset = _date(value);
      }
    }
    return HikeWeatherBriefing(
      hours: hours,
      covered: covered,
      utcOffset: offset,
      minTemperature: covered && temps.length == hours.length
          ? temps.first
          : null,
      maxTemperature: covered && temps.length == hours.length
          ? temps.last
          : null,
      peakRainChance: covered && rain.length == hours.length ? rain.last : null,
      sunrise: sunrise,
      sunset: sunset,
      startsBeforeSunrise: sunrise != null && start.isBefore(sunrise),
      endsAfterSunset: sunset != null && end.isAfter(sunset),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static DateTime _date(num epoch) =>
      DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round(), isUtc: true);
  static double? _number(dynamic values, int i) {
    if (values is! List || i >= values.length || values[i] is! num) return null;
    final value = (values[i] as num).toDouble();
    return value.isFinite ? value : null;
  }
}
