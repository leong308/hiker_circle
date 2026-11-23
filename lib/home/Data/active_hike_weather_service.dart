// ActiveHikeWeatherService loads and persists the active hike's location-based weather snapshot.
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../Model/hike_session_models.dart';

/// Represents active hike weather exception.
class ActiveHikeWeatherException implements Exception {
  /// Creates active hike weather exception.
  const ActiveHikeWeatherException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents active hike weather sample.
class ActiveHikeWeatherSample {
  /// Creates active hike weather sample.
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
    this.isCached = false,
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
  final bool isCached;

  /// Returns summary.
  String get summary => activeHikeWeatherSummary(weatherCode);
}

/// Represents active hike weather snapshot.
class ActiveHikeWeatherSnapshot {
  /// Creates active hike weather snapshot.
  const ActiveHikeWeatherSnapshot({
    required this.samples,
    required this.fetchedAt,
    this.isCachedFallback = false,
  });

  final List<ActiveHikeWeatherSample> samples;
  final DateTime fetchedAt;
  final bool isCachedFallback;

  /// Returns current.
  ActiveHikeWeatherSample? get current =>
      samples.isEmpty ? null : samples.first;

  /// Converts to persistence.
  Map<String, dynamic> toPersistence() => {
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'isCachedFallback': isCachedFallback,
    'samples': [
      for (final sample in samples)
        {
          'label': sample.label,
          'shortLabel': sample.shortLabel,
          'distanceAheadMeters': sample.distanceAheadMeters,
          'coordinate': sample.coordinate.toFirestore(),
          'temperatureCelsius': sample.temperatureCelsius,
          'apparentTemperatureCelsius': sample.apparentTemperatureCelsius,
          'humidityPercent': sample.humidityPercent,
          'windSpeedKph': sample.windSpeedKph,
          'precipitationMillimeters': sample.precipitationMillimeters,
          'weatherCode': sample.weatherCode,
          'observedAt': sample.observedAt.toUtc().toIso8601String(),
          'isCached': sample.isCached,
        },
    ],
  };

  /// Creates active hike weather snapshot using from persistence.
  factory ActiveHikeWeatherSnapshot.fromPersistence(Map<String, dynamic> data) {
    /// Computes date.
    DateTime date(Object? value) {
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null) {
        throw const FormatException('Invalid weather timestamp');
      }
      return parsed;
    }

    /// Computes number.
    double number(Map sample, String key) {
      final value = sample[key];
      if (value is! num || !value.isFinite) {
        throw const FormatException('Invalid weather measurement');
      }
      return value.toDouble();
    }

    final rows = data['samples'];
    if (rows is! List || rows.isEmpty) {
      throw const FormatException('No cached weather samples');
    }
    return ActiveHikeWeatherSnapshot(
      fetchedAt: date(data['fetchedAt']),
      isCachedFallback: data['isCachedFallback'] == true,
      samples: [
        for (final row in rows)
          (() {
            if (row is! Map || row['coordinate'] is! Map) {
              throw const FormatException('Invalid weather sample');
            }
            final coordinate = HikeCoordinate.tryFromFirestore(
              Map<String, dynamic>.from(row['coordinate'] as Map),
            );
            if (coordinate == null) {
              throw const FormatException('Invalid weather position');
            }
            return ActiveHikeWeatherSample(
              label: row['label'] as String,
              shortLabel: row['shortLabel'] as String,
              distanceAheadMeters: number(row, 'distanceAheadMeters').toInt(),
              coordinate: coordinate,
              temperatureCelsius: number(row, 'temperatureCelsius'),
              apparentTemperatureCelsius: number(
                row,
                'apparentTemperatureCelsius',
              ),
              humidityPercent: number(row, 'humidityPercent').toInt(),
              windSpeedKph: number(row, 'windSpeedKph'),
              precipitationMillimeters: number(row, 'precipitationMillimeters'),
              weatherCode: number(row, 'weatherCode').toInt(),
              observedAt: date(row['observedAt']),
              isCached: row['isCached'] == true,
            );
          })(),
      ],
    );
  }
}

/// Represents active hike weather service.
class ActiveHikeWeatherService {
  /// Creates active hike weather service.
  const ActiveHikeWeatherService({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// Sample the current position and listed-route points ahead; unlisted hikes use the recorded location only.
  Future<ActiveHikeWeatherSnapshot> fetchForHike(
    ActiveHikeSession activeHike,
  ) async {
    final route = _routeCoordinates(activeHike);
    if (route.isEmpty) {
      throw const ActiveHikeWeatherException(
        'The trail route has no coordinates for weather sampling.',
      );
    }

    final latestLocation = activeHike.latestLocation;
    final current = latestLocation?.hasValidPosition == true
        ? latestLocation!
        : route.first;
    final currentProgress = _progressAlongRoute(route, current);
    final targets = <({String label, String shortLabel, int meters})>[
      (
        label:
            activeHike.trail.isUnlisted &&
                DateTime.now().toUtc().difference(current.capturedAt.toUtc()) >
                    const Duration(minutes: 2)
            ? 'Last recorded location'
            : 'Your location',
        shortLabel: 'Now',
        meters: 0,
      ),
      if (!activeHike.trail.isUnlisted)
        (label: '200 m upcoming', shortLabel: '200m', meters: 200),
      if (!activeHike.trail.isUnlisted)
        (label: '500 m upcoming', shortLabel: '500m', meters: 500),
      if (!activeHike.trail.isUnlisted)
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
    } catch (error) {
      final cachedSnapshot = activeHike.trail.isUnlisted
          ? null
          : _cachedTrailWeatherSnapshot(
              activeHike: activeHike,
              targets: targets,
              positions: positions,
            );
      if (cachedSnapshot != null) {
        return cachedSnapshot;
      }
      if (error is ActiveHikeWeatherException) {
        rethrow;
      }
      throw const ActiveHikeWeatherException(
        'Unable to fetch weather for this hike.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Fetches current weather.
  Future<ActiveHikeWeatherSample> _fetchCurrentWeather({
    required http.Client client,
    required HikeCoordinate coordinate,
    required String label,
    required String shortLabel,
    required int distanceAheadMeters,
  }) async {
    try {
      // API: Open-Meteo active hike forecast
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
      for (final key in [
        'temperature_2m',
        'apparent_temperature',
        'relative_humidity_2m',
        'wind_speed_10m',
        'precipitation',
        'weather_code',
      ]) {
        final value = current[key];
        if (value is! num || !value.isFinite) {
          throw const ActiveHikeWeatherException(
            'Weather service returned incomplete current conditions.',
          );
        }
      }
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

  /// Computes route coordinates.
  List<HikeCoordinate> _routeCoordinates(ActiveHikeSession activeHike) {
    if (activeHike.trail.isUnlisted) {
      final latest = activeHike.latestLocation;
      return [
        if (latest?.hasValidPosition == true)
          latest!
        else
          HikeCoordinate(
            latitude: activeHike.trail.latitude,
            longitude: activeHike.trail.longitude,
            capturedAt: DateTime.now(),
          ),
      ];
    }
    final encoded = activeHike.trail.routeEncodedPolyline;
    if (encoded != null && encoded.isNotEmpty) {
      final decoded = _decodePolyline(encoded);
      if (decoded.length >= 2) {
        return _orientRoute(decoded, activeHike);
      }
    }

    final checkpoints = [...activeHike.draft.effectiveCheckpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    final checkpointCoordinates = checkpoints
        .where((checkpoint) => checkpoint.hasValidCoordinate)
        .map(
          (checkpoint) => HikeCoordinate(
            latitude: checkpoint.latitude,
            longitude: checkpoint.longitude,
            capturedAt: DateTime.now(),
          ),
        )
        .toList();
    if (checkpointCoordinates.isNotEmpty) {
      return checkpointCoordinates;
    }

    final recordedRoute =
        activeHike.routePoints
            .where((coordinate) => coordinate.hasValidPosition)
            .toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    if (recordedRoute.isNotEmpty) {
      return recordedRoute;
    }
    final latest = activeHike.latestLocation;
    return latest?.hasValidPosition == true ? [latest!] : const [];
  }

  /// Computes decode polyline.
  List<HikeCoordinate> _decodePolyline(String encoded) {
    try {
      final points = <HikeCoordinate>[];
      var index = 0;
      var latitude = 0;
      var longitude = 0;

      /// Computes delta.
      int? readDelta() {
        var shift = 0;
        var result = 0;
        while (true) {
          if (index >= encoded.length || shift > 30) {
            return null;
          }
          final byte = encoded.codeUnitAt(index++) - 63;
          if (byte < 0 || byte > 0x3f) {
            return null;
          }
          result |= (byte & 0x1f) << shift;
          if (byte < 0x20) {
            return (result & 1) == 1 ? ~(result >> 1) : result >> 1;
          }
          shift += 5;
        }
      }

      while (index < encoded.length) {
        final latitudeDelta = readDelta();
        final longitudeDelta = readDelta();
        if (latitudeDelta == null || longitudeDelta == null) {
          return const [];
        }
        latitude += latitudeDelta;
        longitude += longitudeDelta;
        final coordinate = HikeCoordinate(
          latitude: latitude / 100000,
          longitude: longitude / 100000,
          capturedAt: DateTime.now(),
        );
        if (!coordinate.hasValidPosition) {
          return const [];
        }
        points.add(coordinate);
      }
      return points;
    } catch (_) {
      return const [];
    }
  }

  /// Computes cached trail weather snapshot.
  ActiveHikeWeatherSnapshot? _cachedTrailWeatherSnapshot({
    required ActiveHikeSession activeHike,
    required List<({String label, String shortLabel, int meters})> targets,
    required List<HikeCoordinate> positions,
  }) {
    final weather = activeHike.trail.weather;
    final forecasts = [...weather.hourlyForecast]
      ..sort((a, b) => a.time.compareTo(b.time));
    final forecast = forecasts.isEmpty
        ? null
        : forecasts.reduce(
            (a, b) =>
                a.time.difference(DateTime.now()).abs() <=
                    b.time.difference(DateTime.now()).abs()
                ? a
                : b,
          );
    final temperature =
        forecast?.temperature ??
        weather.feelsLike ??
        _temperatureFromRange(weather.temperatureRange);
    final cachedAt = weather.cachedAt.toUtc();
    final hasRealCacheTimestamp =
        cachedAt.isAfter(DateTime.utc(2000)) &&
        cachedAt.isBefore(DateTime.now().toUtc().add(const Duration(days: 1)));
    if (temperature == null ||
        !temperature.isFinite ||
        !hasRealCacheTimestamp ||
        positions.length != targets.length) {
      return null;
    }
    final humidity = (weather.humidity ?? 0).clamp(0, 100);
    final windSpeed = weather.windSpeed?.isFinite == true
        ? math.max(0, weather.windSpeed!).toDouble()
        : 0.0;
    final weatherCode =
        forecast?.weatherCode ?? _weatherCodeFromSummary(weather.summary);
    final observedAt = forecast?.time ?? cachedAt;
    return ActiveHikeWeatherSnapshot(
      samples: [
        for (var index = 0; index < targets.length; index++)
          ActiveHikeWeatherSample(
            label: '${targets[index].label} (cached)',
            shortLabel: '${targets[index].shortLabel}*',
            distanceAheadMeters: targets[index].meters,
            coordinate: positions[index],
            temperatureCelsius: temperature,
            apparentTemperatureCelsius: weather.feelsLike ?? temperature,
            humidityPercent: humidity,
            windSpeedKph: windSpeed,
            precipitationMillimeters: 0,
            weatherCode: weatherCode,
            observedAt: observedAt,
            isCached: true,
          ),
      ],
      fetchedAt: cachedAt,
      isCachedFallback: true,
    );
  }

  /// Computes temperature from range.
  double? _temperatureFromRange(String value) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  /// Computes weather code from summary.
  int _weatherCodeFromSummary(String summary) {
    final normalized = summary.toLowerCase();
    if (normalized.contains('thunder')) return 95;
    if (normalized.contains('snow')) return 71;
    if (normalized.contains('rain') || normalized.contains('drizzle')) {
      return 61;
    }
    if (normalized.contains('fog') || normalized.contains('mist')) return 45;
    if (normalized.contains('clear') || normalized.contains('sun')) return 0;
    return 3;
  }

  /// Computes orient route.
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

  /// Computes progress along route.
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

  /// Computes project on segment.
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

  /// Computes coordinate at distance.
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

  /// Computes double from.
  double _doubleFrom(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : 0;

  /// Computes int from.
  int _intFrom(Object? value) =>
      value is num && value.isFinite ? value.toInt() : 0;

  /// Computes string from.
  String _stringFrom(Object? value) => value is String ? value : '';
}

/// Computes active hike weather summary.
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
