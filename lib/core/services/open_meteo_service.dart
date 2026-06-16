import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../trail/Model/trail_models.dart';

class OpenMeteoException implements Exception {
  const OpenMeteoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenMeteoService {
  const OpenMeteoService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<TrailWeather> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': latitude.toStringAsFixed(4),
          'longitude': longitude.toStringAsFixed(4),
          'current':
              'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index',
          'daily':
              'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code,wind_speed_10m_max,uv_index_max',
          'hourly':
              'temperature_2m,precipitation_probability,weather_code',
          'timezone': 'auto',
          'forecast_hours': '12',
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OpenMeteoException(
          'OpenMeteo ${response.statusCode}: unable to fetch weather.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const OpenMeteoException(
          'OpenMeteo returned an unexpected response.',
        );
      }

      final current = decoded['current'];
      if (current is! Map<String, dynamic>) {
        throw const OpenMeteoException(
          'OpenMeteo response is missing current weather.',
        );
      }

      final currentTemp = current['temperature_2m'];
      final currentCode = current['weather_code'] ?? 0;

      final daily = decoded['daily'];
      if (daily is! Map<String, dynamic>) {
        throw const OpenMeteoException(
          'OpenMeteo response is missing daily forecast.',
        );
      }

      final tempMax = daily['temperature_2m_max'];
      final tempMin = daily['temperature_2m_min'];
      final precipProb = daily['precipitation_probability_max'];
      final dailyCodes = daily['weather_code'];

      final maxTemp = tempMax is List && tempMax.isNotEmpty
          ? (tempMax[0] as num).toDouble()
          : currentTemp is num
              ? currentTemp.toDouble()
              : 0.0;
      final minTemp = tempMin is List && tempMin.isNotEmpty
          ? (tempMin[0] as num).toDouble()
          : currentTemp is num
              ? currentTemp.toDouble()
              : 0.0;

      final dailyCode = dailyCodes is List && dailyCodes.isNotEmpty
          ? (dailyCodes[0] as num).toInt()
          : currentCode is num
              ? currentCode.toInt()
              : 0;

      final precipitationProbability = precipProb is List && precipProb.isNotEmpty
          ? (precipProb[0] as num).toInt()
          : 0;

      final humidity = current['relative_humidity_2m'];
      final feelsLike = current['apparent_temperature'];
      final windSpeed = current['wind_speed_10m'];
      final uvIndex = current['uv_index'];

      final hourlyForecast = _parseHourlyForecast(decoded['hourly']);

      return TrailWeather(
        summary: _wmoSummary(dailyCode),
        temperatureRange: '${minTemp.round()} °C - ${maxTemp.round()} °C',
        rainProbability: precipitationProbability.clamp(0, 100),
        cachedAt: DateTime.now(),
        humidity: humidity is num ? humidity.toInt() : null,
        windSpeed: windSpeed is num ? windSpeed.toDouble() : null,
        uvIndex: uvIndex is num ? uvIndex.toDouble() : null,
        feelsLike: feelsLike is num ? feelsLike.toDouble() : null,
        hourlyForecast: hourlyForecast,
      );
    } on OpenMeteoException {
      rethrow;
    } on FormatException {
      throw const OpenMeteoException(
        'OpenMeteo returned invalid data.',
      );
    } catch (_) {
      throw const OpenMeteoException(
        'Unable to fetch weather. Check your connection and try again.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  List<HourlyForecast> _parseHourlyForecast(Object? hourly) {
    if (hourly is! Map<String, dynamic>) {
      return const [];
    }

    final times = hourly['time'];
    final temps = hourly['temperature_2m'];
    final precipProbs = hourly['precipitation_probability'];
    final codes = hourly['weather_code'];

    if (times is! List || temps is! List || codes is! List) {
      return const [];
    }

    final now = DateTime.now();
    final forecasts = <HourlyForecast>[];
    var started = false;

    for (var i = 0; i < times.length && forecasts.length < 24; i++) {
      final timeStr = times[i];
      final temp = temps[i];
      final code = codes[i];

      if (timeStr is! String || temp is! num || code is! num) continue;

      final time = DateTime.tryParse(timeStr);
      if (time == null) continue;

      if (!started) {
        if (time.isBefore(now) || time.isAtSameMomentAs(now)) continue;
        started = true;
      }

      final precip = precipProbs is List && i < precipProbs.length
          ? precipProbs[i]
          : null;

      forecasts.add(HourlyForecast(
        time: time,
        temperature: temp.toDouble(),
        precipitationProbability:
            precip is num ? precip.toInt().clamp(0, 100) : 0,
        weatherCode: code.toInt(),
      ));
    }

    return forecasts;
  }
}

String _wmoSummary(int code) {
  const mapping = {
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Overcast',
    45: 'Foggy',
    48: 'Depositing rime fog',
    51: 'Light drizzle',
    53: 'Moderate drizzle',
    55: 'Dense drizzle',
    56: 'Light freezing drizzle',
    57: 'Dense freezing drizzle',
    61: 'Slight rain',
    63: 'Moderate rain',
    65: 'Heavy rain',
    66: 'Light freezing rain',
    67: 'Heavy freezing rain',
    71: 'Slight snow',
    73: 'Moderate snow',
    75: 'Heavy snow',
    77: 'Snow grains',
    80: 'Slight rain showers',
    81: 'Moderate rain showers',
    82: 'Violent rain showers',
    85: 'Slight snow showers',
    86: 'Heavy snow showers',
    95: 'Thunderstorm',
    96: 'Thunderstorm with slight hail',
    99: 'Thunderstorm with heavy hail',
  };
  return mapping[code] ?? 'Unknown';
}
