import '../Model/trail_models.dart';
import '../Model/trail_weather_location.dart';

/// Reads the trail's shared forecast before requesting any provider refresh.
class TrailCheckpointWeatherRepository {
  /// Receives cloud boundaries from the app's configured repository.
  const TrailCheckpointWeatherRepository({
    required this.readCached,
    required this.fetchWeather,
    this.now = DateTime.now,
  });

  final Future<Map<String, dynamic>?> Function(
    String trailId,
    String checkpointKey,
  )
  readCached;
  final Future<Map<String, dynamic>> Function(
    String trailId,
    String checkpointKey,
  )
  fetchWeather;
  final DateTime Function() now;
  static const freshness = TrailWeather.cacheFreshness;

  /// Shows existing data first; only missing or stale forecasts need a callable.
  Stream<TrailWeather> watch(
    Trail trail,
    TrailWeatherLocation location,
  ) async* {
    if (trail.distanceKm <= 3 ||
        location.key == TrailWeatherLocation.trailheadKey ||
        !TrailWeatherLocation.forTrail(
          trail,
        ).any((point) => point.key == location.key)) {
      throw const FormatException(
        'Choose a saved checkpoint on a trail longer than 3 km.',
      );
    }
    Map<String, dynamic>? cached;
    try {
      cached = await readCached(trail.trailId, location.key);
    } catch (_) {
      // The callable can still recover when a direct cache read is unavailable.
    }
    final raw = cached?['weather'];
    if (raw is Map) {
      final weather = TrailWeather.fromPersistence(
        Map<String, dynamic>.from(raw),
      );
      if (_hasForecast(weather)) {
        yield weather;
        final age = now().toUtc().difference(weather.cachedAt.toUtc());
        if (age >= const Duration(minutes: -1) && age < freshness) return;
      }
    }
    final response = await fetchWeather(trail.trailId, location.key);
    final updated = response['weather'];
    if (updated is! Map) {
      throw const FormatException('Checkpoint forecast is missing.');
    }
    final weather = TrailWeather.fromPersistence(
      Map<String, dynamic>.from(updated),
    );
    if (!_hasForecast(weather)) {
      throw const FormatException('Checkpoint forecast is incomplete.');
    }
    yield weather;
  }

  /// Requires daily and hourly data before displaying a saved forecast.
  bool _hasForecast(TrailWeather weather) =>
      weather.forecastData['daily'] is Map &&
      (weather.forecastData['daily'] as Map)['time'] is List &&
      ((weather.forecastData['daily'] as Map)['time'] as List).isNotEmpty &&
      weather.forecastData['hourly'] is Map &&
      (weather.forecastData['hourly'] as Map)['time'] is List &&
      ((weather.forecastData['hourly'] as Map)['time'] as List).isNotEmpty;
}
