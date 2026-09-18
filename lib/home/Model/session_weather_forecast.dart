import '../../trail/Model/trail_models.dart';
import '../../trail/Model/trail_precautions.dart';
import 'hike_weather_briefing.dart';

class SessionWeatherForecast {
  SessionWeatherForecast(
    this.weather,
    this.departure,
    this.returning, {
    this.elevationGain = 0,
  });
  final TrailWeather weather;
  final DateTime departure, returning;
  final int elevationGain;
  DateTime get from => departure.subtract(const Duration(hours: 2));
  DateTime get to => returning.add(const Duration(hours: 2));
  late final session = HikeWeatherBriefing.fromWeather(
    weather,
    departure,
    returning,
  );
  late final buffer = HikeWeatherBriefing.fromWeather(weather, from, to);
  late final before = HikeWeatherBriefing.fromWeather(weather, from, departure);
  late final after = HikeWeatherBriefing.fromWeather(weather, returning, to);

  double? peak(String key, {HikeWeatherBriefing? window}) {
    final scope = window ?? session;
    final values = scope.hours.map((h) => h.value(key)).toList();
    if (!scope.covered || values.isEmpty || values.any((v) => v == null)) {
      return null;
    }
    return values.cast<double>().reduce((a, b) => a > b ? a : b);
  }

  List<TrailPrecaution> cautions(DateTime now) {
    final daily = weather.forecastData['daily'];
    final days = daily is Map && daily['time'] is List
        ? daily['time'] as List
        : [];
    final local = departure.toUtc().add(session.utcOffset);
    final day = days.indexWhere((epoch) {
      if (epoch is! num) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(
        (epoch * 1000).round(),
        isUtc: true,
      ).add(session.utcOffset);
      return d.year == local.year &&
          d.month == local.month &&
          d.day == local.day;
    });
    List<TrailPrecaution> rules(DateTime start, DateTime end) =>
        trailPrecautions(
          weather: weather,
          day: day,
          now: now,
          elevationGain: elevationGain,
          durationMinutes: returning.difference(departure).inMinutes,
          departureMinute: local.hour * 60 + local.minute,
          assessmentStart: start,
          assessmentEnd: end,
        );
    final result = rules(departure, returning);
    if (day < 0) {
      result.add(
        const TrailPrecaution(
          'daylight-data',
          2,
          'Daylight timing unavailable',
          'Sunrise or sunset data is missing. Check daylight before departure.',
        ),
      );
    }
    // Buffer-only risks are labelled separately; they never change the
    // scheduled hike's temperature/rain statistics or daylight assessment.
    for (final window in [
      (before, from, departure, 'Before departure'),
      (after, returning, to, 'After expected return'),
    ]) {
      for (final caution in rules(window.$2, window.$3)) {
        if ([
          'dark',
          'sunset',
          'daylight-data',
          'ascent',
          'duration',
          'data',
        ].contains(caution.id)) {
          continue;
        }
        if (result.any((c) => c.id == caution.id)) continue;
        result.add(
          TrailPrecaution(
            '${window.$4}-${caution.id}',
            caution.priority,
            '${window.$4}: ${caution.id == 'rain' && caution.priority == 1 ? 'rain may leave the trail wet' : caution.title}',
            'In the two-hour buffer. ${caution.message}',
          ),
        );
      }
    }
    if (!buffer.covered && !result.any((c) => c.id == 'data')) {
      result.add(
        const TrailPrecaution(
          'buffer-data',
          2,
          'Buffer forecast is incomplete',
          'Some hours before departure or after return are unavailable. Missing data does not mean dry or calm conditions.',
        ),
      );
    }
    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result;
  }
}
