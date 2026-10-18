// PrecautionCheckService evaluates trail facts and conditions before a hike is confirmed.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'trail_models.dart';
import 'trail_precautions.dart';

class PrecautionCheckService {
  /// Return an explicit unavailable-data precaution when forecast retrieval fails.
  static Future<List<TrailPrecaution>> check(
    Trail trail, {
    DateTime? departure,
    int? durationMinutes,
    double? latitude,
    double? longitude,
  }) async {
    final now = DateTime.now().toUtc();
    TrailWeather weather;
    try {
      final response = await http
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': '${latitude ?? trail.latitude}',
              'longitude': '${longitude ?? trail.longitude}',
              'hourly':
                  'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,visibility,uv_index',
              'daily': 'sunrise,sunset',
              'timezone': 'Asia/Kuala_Lumpur',
              'timeformat': 'unixtime',
              'temperature_unit': 'celsius',
              'wind_speed_unit': 'kmh',
              'precipitation_unit': 'mm',
              'forecast_days': '7',
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const FormatException('Weather unavailable');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      weather = TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: now,
        forecastData: data,
      );
    } catch (_) {
      return const [
        TrailPrecaution(
          'data',
          3,
          'Conditions could not be checked',
          'Weather refresh failed. Check official warnings and conditions before continuing; previous information may be outdated.',
          quickAction: 'Check local conditions and official alerts.',
          quickFacts: ['Forecast unavailable'],
        ),
      ];
    }
    final time = (departure ?? now).toUtc().add(const Duration(hours: 8));
    final midnight =
        DateTime.utc(
          time.year,
          time.month,
          time.day,
        ).subtract(const Duration(hours: 8)).millisecondsSinceEpoch ~/
        1000;
    final days = (weather.forecastData['daily'] as Map?)?['time'];
    final day = days is List ? days.indexOf(midnight) : -1;
    return trailPrecautions(
      weather: weather,
      day: day,
      now: now,
      elevationGain: trail.elevationGainMeters,
      durationMinutes: durationMinutes ?? trail.estimatedDurationMinutes,
      departureMinute: time.hour * 60 + time.minute,
    );
  }
}
