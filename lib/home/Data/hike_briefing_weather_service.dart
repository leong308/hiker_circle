// HikeBriefingWeatherService shares bounded forecast caching for scheduled hike briefings.
import '../../app/Data/local_session_database.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../trail/Model/trail_models.dart';

/// One shared, bounded cache for the Home briefing. No requests on map movement.
class HikeBriefingWeatherService {
  /// Creates hike briefing weather service.
  HikeBriefingWeatherService({http.Client? client}) : _client = client;
  static final shared = HikeBriefingWeatherService();
  static const freshness = TrailWeather.cacheFreshness;
  static const forecastDays = 16;

  /// Checks whether beyond forecast.
  static bool isBeyondForecast(DateTime departure, {DateTime? now}) =>
      departure.toUtc().difference((now ?? DateTime.now()).toUtc()) >=
      const Duration(days: forecastDays);
  final http.Client? _client;
  final _cache = <String, TrailWeather>{};
  final _pending = <String, Future<TrailWeather>>{};
  final _failed = <String, DateTime>{};

  /// Fetches.
  Future<TrailWeather> fetch(
    double latitude,
    double longitude, {
    bool force = false,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const FormatException('Invalid trail coordinates');
    }
    final key =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    final now = DateTime.now().toUtc();
    if (_client == null && !_cache.containsKey(key)) {
      try {
        final local = await LocalSessionDatabase().loadCachedEntity(
          ownerPhoneNumber: '',
          entityType: 'briefing_weather',
          entityId: key,
          includeExpired: true,
        );
        if (local != null) {
          _cache[key] = TrailWeather.fromPersistence(local.payload);
        }
      } catch (_) {
        /* Offline briefing remains best-effort. */
      }
    }
    final cached = _cache[key];
    if (!force &&
        cached != null &&
        now.difference(cached.cachedAt) < freshness) {
      return cached;
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final failed = _failed[key];
    if (!force &&
        failed != null &&
        now.difference(failed) < const Duration(minutes: 5)) {
      throw const FormatException('Weather temporarily unavailable');
    }
    final request = _fetch(latitude, longitude);
    _pending[key] = request;
    try {
      final weather = await request;
      if (_client == null) {
        await LocalSessionDatabase().saveCachedEntity(
          LocalCachedEntity(
            ownerPhoneNumber: '',
            entityType: 'briefing_weather',
            entityId: key,
            parentId: '',
            payload: weather.toFirestore(),
            cachedAt: weather.cachedAt,
          ),
        );
      }

      _cache.remove(key);
      _cache[key] = weather;
      if (_cache.length > 12) _cache.remove(_cache.keys.first);
      _failed.remove(key);
      return weather;
    } catch (_) {
      _failed[key] = now;
      if (_failed.length > 12) _failed.remove(_failed.keys.first);
      rethrow;
    } finally {
      _pending.remove(key);
    }
  }

  /// Fetches.
  Future<TrailWeather> _fetch(double latitude, double longitude) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': '$latitude',
              'longitude': '$longitude',
              'current':
                  'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
              'hourly':
                  'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,visibility,uv_index',
              'daily': 'sunrise,sunset',
              'timezone': 'auto',
              'timeformat': 'unixtime',
              'temperature_unit': 'celsius',
              'wind_speed_unit': 'kmh',
              'precipitation_unit': 'mm',
              'past_days': '1',
              'forecast_days': '$forecastDays',
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const FormatException('Weather unavailable');
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> ||
          data['hourly'] is! Map ||
          (data['hourly'] as Map)['time'] is! List ||
          data['utc_offset_seconds'] is! num) {
        throw const FormatException('Incomplete forecast');
      }
      return TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: DateTime.now().toUtc(),
        forecastData: data,
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}
