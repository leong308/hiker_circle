import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/session_weather_forecast.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test(
    'compact historical weather parses without losing trail or checkpoint data',
    () {
      final trail = Trail.fromPersistence({
        'trailId': 'historic-trail',
        'name': 'Original trail name',
        'latitude': 3.1,
        'longitude': 101.2,
        'routeEncodedPolyline': 'exact-original-geometry',
        'checkpoints': [
          {
            'name': 'River crossing',
            'latitude': 3.11,
            'longitude': 101.21,
            'order': 1,
          },
        ],
        'weather': {
          'summary': 'Light rain',
          'temperatureRange': '24–28°C',
          'rainProbability': 65,
          'humidity': 80,
          'windSpeed': 12.0,
          'cachedAtLocal': '2026-10-01T01:00:00Z',
          'forecastData': {
            'timezone': 'Asia/Kuala_Lumpur',
            'utc_offset_seconds': 28800,
            'current': {'temperature_2m': 26},
          },
        },
      });
      expect(trail.name, 'Original trail name');
      expect(trail.routeEncodedPolyline, 'exact-original-geometry');
      expect(trail.checkpoints.single.name, 'River crossing');
      expect(trail.weather.summary, 'Light rain');
      expect(trail.weather.humidity, 80);
      expect(trail.weather.hourlyForecast, isEmpty);
      expect(trail.weather.forecastData['timezone'], 'Asia/Kuala_Lumpur');
      final forecast = SessionWeatherForecast(
        trail.weather,
        DateTime.utc(2026, 10, 1, 2),
        DateTime.utc(2026, 10, 1, 5),
      );
      // Missing historical forecast series must be unavailable, not fabricated.
      expect(forecast.session.covered, isFalse);
      expect(forecast.peak('wind_speed_10m'), isNull);
      expect(
        forecast
            .cautions(DateTime.utc(2026, 10, 1, 2))
            .any((c) => c.id == 'data'),
        isTrue,
      );
    },
  );
}
