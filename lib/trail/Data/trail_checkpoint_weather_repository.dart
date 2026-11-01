import '../Model/trail_models.dart';
import '../Model/trail_weather_location.dart';

/// Reuses a fresh shared forecast and refreshes an expired forecast before display.
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

  /// Holds expired data as a fallback while requesting a current shared forecast.
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
    TrailWeather? fallback;
    final raw = cached?['weather'];
    if (raw is Map) {
      final weather = TrailWeather.fromPersistence(
        Map<String, dynamic>.from(raw),
      );
      if (_hasForecast(weather)) {
        final age = now().toUtc().difference(weather.cachedAt.toUtc());
        if (age >= const Duration(minutes: -1) && age < freshness) {
          yield weather;
          return;
        }
        fallback = weather;
      }
    }
    try {
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
    } catch (_) {
      if (fallback == null) rethrow;
      // Its original timestamp lets the UI retain the stale forecast label.
      yield fallback;
    }
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
