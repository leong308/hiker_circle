import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../Model/hike_session_models.dart';

class ActiveHikeWeatherException implements Exception {
  const ActiveHikeWeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ActiveHikeWeatherSample {
  const ActiveHikeWeatherSample({
    required this.label,
    required this.shortLabel,
    required this.distanceAheadMeters,
    required this.coordinate,
    required this.temperatureCelsius,
    required this.apparentTemperatureCelsius,
    required this.humidityPercent,
    required this.windSpeedKph,
    required this.precipitationMillimeters,
    required this.weatherCode,
    required this.observedAt,
  });

  final String label;
  final String shortLabel;
  final int distanceAheadMeters;
  final HikeCoordinate coordinate;
  final double temperatureCelsius;
  final double apparentTemperatureCelsius;
  final int humidityPercent;
  final double windSpeedKph;
  final double precipitationMillimeters;
  final int weatherCode;
  final DateTime observedAt;

  String get summary => activeHikeWeatherSummary(weatherCode);
}

class ActiveHikeWeatherSnapshot {
  const ActiveHikeWeatherSnapshot({
    required this.samples,
    required this.fetchedAt,
  });

  final List<ActiveHikeWeatherSample> samples;
  final DateTime fetchedAt;

  ActiveHikeWeatherSample? get current =>
      samples.isEmpty ? null : samples.first;
}

class ActiveHikeWeatherService {
  const ActiveHikeWeatherService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<ActiveHikeWeatherSnapshot> fetchForHike(
    ActiveHikeSession activeHike,
  ) async {
    final route = _routeCoordinates(activeHike);
    if (route.isEmpty) {
      throw const ActiveHikeWeatherException(
        'The trail route has no coordinates for weather sampling.',
      );
    }

    final current = activeHike.latestLocation ?? route.first;
    final currentProgress = _progressAlongRoute(route, current);
    const targets = <({String label, String shortLabel, int meters})>[
      (label: 'Your location', shortLabel: 'Now', meters: 0),
      (label: '200 m upcoming', shortLabel: '200m', meters: 200),
      (label: '500 m upcoming', shortLabel: '500m', meters: 500),
      (label: '1 km upcoming', shortLabel: '1km', meters: 1000),
    ];

    final positions = targets.map((target) {
      if (target.meters == 0) {
        return current;
      }
      return _coordinateAtDistance(route, currentProgress + target.meters);
    }).toList();

    final client = _client ?? http.Client();
    try {
      final samples = await Future.wait([
        for (var index = 0; index < targets.length; index++)
          _fetchCurrentWeather(
            client: client,
            coordinate: positions[index],
            label: targets[index].label,
            shortLabel: targets[index].shortLabel,
            distanceAheadMeters: targets[index].meters,
          ),
      ]);
      return ActiveHikeWeatherSnapshot(
        samples: samples,
        fetchedAt: DateTime.now(),
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<ActiveHikeWeatherSample> _fetchCurrentWeather({
    required http.Client client,
    required HikeCoordinate coordinate,
    required String label,
    required String shortLabel,
    required int distanceAheadMeters,
  }) async {
    try {
      final response = await client
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': coordinate.latitude.toStringAsFixed(5),
              'longitude': coordinate.longitude.toStringAsFixed(5),
              'current':
                  'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
              'timezone': 'auto',
              'forecast_days': '1',
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ActiveHikeWeatherException(
          'Weather service returned ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['current'] is! Map<String, dynamic>) {
        throw const ActiveHikeWeatherException(
          'Weather service returned incomplete current conditions.',
        );
      }
      final current = Map<String, dynamic>.from(decoded['current'] as Map);
      return ActiveHikeWeatherSample(
        label: label,
        shortLabel: shortLabel,
        distanceAheadMeters: distanceAheadMeters,
        coordinate: coordinate,
        temperatureCelsius: _doubleFrom(current['temperature_2m']),
        apparentTemperatureCelsius: _doubleFrom(
          current['apparent_temperature'],
        ),
        humidityPercent: _intFrom(current['relative_humidity_2m']),
        windSpeedKph: _doubleFrom(current['wind_speed_10m']),
        precipitationMillimeters: _doubleFrom(current['precipitation']),
        weatherCode: _intFrom(current['weather_code']),
        observedAt:
            DateTime.tryParse(_stringFrom(current['time'])) ?? DateTime.now(),
      );
    } on ActiveHikeWeatherException {
      rethrow;
    } on FormatException {
      throw const ActiveHikeWeatherException(
        'Weather service returned invalid data.',
      );
    } catch (_) {
      throw ActiveHikeWeatherException('Unable to fetch weather for $label.');
    }
  }

  List<HikeCoordinate> _routeCoordinates(ActiveHikeSession activeHike) {
    final encoded = activeHike.trail.routeEncodedPolyline;
    if (encoded != null && encoded.isNotEmpty) {
      final decoded = _decodePolyline(encoded);
      if (decoded.length >= 2) {
        return _orientRoute(decoded, activeHike);
      }
    }

    final checkpoints = [...activeHike.draft.effectiveCheckpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    return checkpoints
        .map(
          (checkpoint) => HikeCoordinate(
            latitude: checkpoint.latitude,
            longitude: checkpoint.longitude,
            capturedAt: DateTime.now(),
          ),
        )
        .toList();
  }

  List<HikeCoordinate> _decodePolyline(String encoded) {
    final points = <HikeCoordinate>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      latitude += (result & 1) == 1 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      longitude += (result & 1) == 1 ? ~(result >> 1) : result >> 1;
      points.add(
        HikeCoordinate(
          latitude: latitude / 100000,
          longitude: longitude / 100000,
          capturedAt: DateTime.now(),
        ),
      );
    }
    return points;
  }

  List<HikeCoordinate> _orientRoute(
    List<HikeCoordinate> route,
    ActiveHikeSession hike,
  ) {
    final checkpoints = [...hike.draft.effectiveCheckpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    if (checkpoints.length < 2) {
      return route;
    }
    final start = HikeCoordinate(
      latitude: checkpoints.first.latitude,
      longitude: checkpoints.first.longitude,
      capturedAt: DateTime.now(),
    );
    final end = HikeCoordinate(
      latitude: checkpoints.last.latitude,
      longitude: checkpoints.last.longitude,
      capturedAt: DateTime.now(),
    );
    final forward = route.first.distanceTo(start) + route.last.distanceTo(end);
    final reverse = route.first.distanceTo(end) + route.last.distanceTo(start);
    return reverse < forward ? route.reversed.toList() : route;
  }

  double _progressAlongRoute(
    List<HikeCoordinate> route,
    HikeCoordinate current,
  ) {
    if (route.length < 2) {
      return 0;
    }
    var bestDistance = double.infinity;
    var bestProgress = 0.0;
    var traversed = 0.0;
    for (var index = 1; index < route.length; index++) {
      final start = route[index - 1];
      final end = route[index];
      final segmentLength = start.distanceTo(end);
      if (segmentLength <= 0) {
        continue;
      }
      final projection = _projectOnSegment(current, start, end);
      final distance = current.distanceTo(projection.coordinate);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestProgress = traversed + segmentLength * projection.fraction;
      }
      traversed += segmentLength;
    }
    return bestProgress;
  }

  ({HikeCoordinate coordinate, double fraction}) _projectOnSegment(
    HikeCoordinate point,
    HikeCoordinate start,
    HikeCoordinate end,
  ) {
    final referenceLatitude =
        (start.latitude + end.latitude + point.latitude) / 3;
    final longitudeScale = math.cos(referenceLatitude * math.pi / 180);
    final segmentX = (end.longitude - start.longitude) * longitudeScale;
    final segmentY = end.latitude - start.latitude;
    final pointX = (point.longitude - start.longitude) * longitudeScale;
    final pointY = point.latitude - start.latitude;
    final segmentSquared = segmentX * segmentX + segmentY * segmentY;
    final fraction = segmentSquared <= 0
        ? 0.0
        : ((pointX * segmentX + pointY * segmentY) / segmentSquared).clamp(
            0.0,
            1.0,
          );
    return (
      coordinate: HikeCoordinate(
        latitude: start.latitude + (end.latitude - start.latitude) * fraction,
        longitude:
            start.longitude + (end.longitude - start.longitude) * fraction,
        capturedAt: DateTime.now(),
      ),
      fraction: fraction,
    );
  }

  HikeCoordinate _coordinateAtDistance(
    List<HikeCoordinate> route,
    double targetDistance,
  ) {
    if (route.length < 2 || targetDistance <= 0) {
      return route.first;
    }
    var traversed = 0.0;
    for (var index = 1; index < route.length; index++) {
      final start = route[index - 1];
      final end = route[index];
      final segmentLength = start.distanceTo(end);
      if (traversed + segmentLength >= targetDistance && segmentLength > 0) {
        final fraction = ((targetDistance - traversed) / segmentLength).clamp(
          0.0,
          1.0,
        );
        return HikeCoordinate(
          latitude: start.latitude + (end.latitude - start.latitude) * fraction,
          longitude:
              start.longitude + (end.longitude - start.longitude) * fraction,
          capturedAt: DateTime.now(),
        );
      }
      traversed += segmentLength;
    }
    return route.last;
  }

  double _doubleFrom(Object? value) => value is num ? value.toDouble() : 0;

  int _intFrom(Object? value) => value is num ? value.toInt() : 0;

  String _stringFrom(Object? value) => value is String ? value : '';
}

String activeHikeWeatherSummary(int code) {
  const summaries = <int, String>{
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Overcast',
    45: 'Foggy',
    48: 'Rime fog',
    51: 'Light drizzle',
    53: 'Drizzle',
    55: 'Heavy drizzle',
    56: 'Freezing drizzle',
    57: 'Heavy freezing drizzle',
    61: 'Light rain',
    63: 'Rain',
    65: 'Heavy rain',
    66: 'Freezing rain',
    67: 'Heavy freezing rain',
    71: 'Light snow',
    73: 'Snow',
    75: 'Heavy snow',
    77: 'Snow grains',
    80: 'Rain showers',
    81: 'Rain showers',
    82: 'Heavy showers',
    85: 'Snow showers',
    86: 'Heavy snow showers',
    95: 'Thunderstorm',
    96: 'Thunderstorm with hail',
    99: 'Severe thunderstorm',
  };
  return summaries[code] ?? 'Unknown conditions';
}
