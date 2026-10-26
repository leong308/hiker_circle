// WeatherMapService defines weather layers and selects forecast rain probabilities using forecast
// time and real cache freshness separately.
import '../../trail/Model/trail_models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Defines the weather map layer choices.
enum WeatherMapLayer {
  off('Off', ''),
  rain('Rain', 'precipitation_new'),
  wind('Wind speed', 'wind_new'),
  temperature('Temperature', 'temp_new');

  /// Creates this model.
  const WeatherMapLayer(this.label, this.tileName);
  final String label;
  final String tileName;
}

/// Represents weather map service.
abstract final class WeatherMapService {
  // Availability marker only. Actual tile credentials stay on the server.
  /// Returns api key.
  static String get apiKey {
    try {
      return dotenv.env['OPENWEATHER_TILES_ENABLED'] == 'true'
          ? 'server-managed'
          : '';
    } catch (_) {
      return '';
    }
  }

  /// Computes tile template.
  static String tileTemplate(WeatherMapLayer layer, String key) {
    if (layer == WeatherMapLayer.off || key.trim().isEmpty) {
      throw ArgumentError('A weather layer and API key are required.');
    }
    return 'https://tile.openweathermap.org/map/${layer.tileName}'
        '/{z}/{x}/{y}.png?appid=${Uri.encodeQueryComponent(key.trim())}';
  }
}

/// Compatibility helper for views displaying the current forecast hour.
int? currentTrailRainProbability(TrailWeather weather, DateTime now) =>
    trailRainProbabilityAt(weather, forecastTime: now, now: now);

/// Select the forecast for simulated arrival while checking cache freshness
/// against the real clock. A hike several hours ahead is not a stale cache.
int? trailRainProbabilityAt(
  TrailWeather weather, {
  required DateTime forecastTime,
  required DateTime now,
}) {
  final age = now.toUtc().difference(weather.cachedAt.toUtc());
  if (age >= const Duration(hours: 4) || age.isNegative) return null;
  final hourly = weather.forecastData['hourly'];
  if (hourly is Map) {
    final times = hourly['time'];
    final probabilities = hourly['precipitation_probability'];
    if (times is List && probabilities is List) {
      final seconds = forecastTime.millisecondsSinceEpoch / 1000;
      for (var i = 0; i < times.length && i < probabilities.length; i++) {
        final time = times[i];
        final probability = probabilities[i];
        if (time is num &&
            time.isFinite &&
            seconds >= time &&
            seconds < time + 3600 &&
            probability is num &&
            probability.isFinite &&
            probability >= 0 &&
            probability <= 100) {
          return probability.round();
        }
      }
    }
    // Structured forecasts are authoritative, including missing readings.
    return null;
  }
  for (final hour in weather.hourlyForecast) {
    final elapsed = forecastTime.difference(hour.time);
    if (!elapsed.isNegative &&
        elapsed < const Duration(hours: 1) &&
        hour.precipitationProbability >= 0 &&
        hour.precipitationProbability <= 100) {
      return hour.precipitationProbability;
    }
  }
  return null;
}

/// Show arrival in the forecast's timezone, including day rollover.
String trailForecastArrivalLabel(TrailWeather weather, DateTime arrival) {
  final offset = weather.forecastData['utc_offset_seconds'];
  final local = offset is num && offset.isFinite
      ? arrival.toUtc().add(Duration(seconds: offset.round()))
      : arrival.toLocal();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '${local.day}/${local.month} $clock';
}

/// Represents trail rain estimate.
class TrailRainEstimate {
  /// Creates trail rain estimate.
  const TrailRainEstimate({required this.time, this.probability});
  final DateTime time;
  final int? probability;
}

/// A display estimate sampled every ten simulated minutes. This interpolates
/// the hourly probability trend; it is NOT the probability of rainfall within
/// a ten-minute interval and does not increase the underlying model resolution.
TrailRainEstimate trailRainEstimateAt(
  TrailWeather weather, {
  required DateTime forecastTime,
  required DateTime now,
}) {
  final offsetValue = weather.forecastData['utc_offset_seconds'];
  final offset = offsetValue is num && offsetValue.isFinite
      ? offsetValue.round()
      : forecastTime.toLocal().timeZoneOffset.inSeconds;
  final seconds = forecastTime.millisecondsSinceEpoch ~/ 1000;
  final sampleSeconds = ((seconds + offset) ~/ 600) * 600 - offset;
  final sampleTime = DateTime.fromMillisecondsSinceEpoch(
    sampleSeconds * 1000,
    isUtc: true,
  );

  /// Computes result.
  TrailRainEstimate result([num? probability]) =>
      TrailRainEstimate(time: sampleTime, probability: probability?.round());
  final age = now.toUtc().difference(weather.cachedAt.toUtc());
  if (age.isNegative || age >= const Duration(hours: 4)) return result();

  final entries = <(num, num?)>[];

  /// Computes valid.
  num? valid(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 100
      ? value
      : null;
  final hourly = weather.forecastData['hourly'];
  if (hourly is Map) {
    final times = hourly['time'];
    final values = hourly['precipitation_probability'];
    if (times is! List || values is! List) return result();
    for (var i = 0; i < times.length; i++) {
      final time = times[i];
      if (time is num && time.isFinite) {
        entries.add((time, i < values.length ? valid(values[i]) : null));
      }
    }
  } else {
    for (final hour in weather.hourlyForecast) {
      entries.add((
        hour.time.millisecondsSinceEpoch / 1000,
        valid(hour.precipitationProbability),
      ));
    }
  }
  for (var i = 0; i < entries.length; i++) {
    final (time, probability) = entries[i];
    if (sampleSeconds == time) return result(probability);
    if (time > sampleSeconds || i + 1 >= entries.length) continue;
    final (nextTime, nextProbability) = entries[i + 1];
    if (sampleSeconds >= nextTime) continue;
    if (nextTime - time != 3600 ||
        probability == null ||
        nextProbability == null) {
      return result();
    }
    final fraction = (sampleSeconds - time) / 3600;
    return result(probability + (nextProbability - probability) * fraction);
  }
  return result();
}
