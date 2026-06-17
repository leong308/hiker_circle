import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';
import '../../trail/Model/trail_models.dart';

class GeoapifyException implements Exception {
  const GeoapifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeoapifyLocation {
  const GeoapifyLocation({
    required this.area,
    required this.state,
    required this.country,
  });

  final String area;
  final String state;
  final String country;
}

class GeoapifyRouteResult {
  const GeoapifyRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.coordinates,
    this.elevationGainMeters,
  });

  final int distanceMeters;
  final double durationSeconds;
  final List<List<double>> coordinates;
  final double? elevationGainMeters;
}

class _ParsedRouteData {
  _ParsedRouteData({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.coordinates,
    this.elevationGainMeters,
  });

  final int distanceMeters;
  final double durationSeconds;
  final List<List<double>> coordinates;
  final double? elevationGainMeters;
}

class GeoapifyService {
  GeoapifyService({http.Client? client, String? apiKey})
    : _client = client,
      _apiKey = apiKey ?? GoogleApiConfig.geoapifyApiKey;

  final http.Client? _client;
  final String _apiKey;

  Future<GeoapifyLocation> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const GeoapifyException(
        'Geoapify API key is not configured.',
      );
    }

    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        Uri.https('api.geoapify.com', '/v1/geocode/reverse', {
          'lat': '$latitude',
          'lon': '$longitude',
          'apiKey': _apiKey,
          'lang': 'en',
          'limit': '1',
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeoapifyException(
          'Geoapify ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GeoapifyException(
          'Geoapify returned an unexpected response.',
        );
      }

      final features = decoded['features'];
      if (features is! List || features.isEmpty) {
        throw const GeoapifyException(
          'No location data found for these coordinates.',
        );
      }

      final properties = features.first is Map
          ? (features.first as Map)['properties']
          : null;
      if (properties is! Map) {
        throw const GeoapifyException(
          'Geoapify returned unexpected feature format.',
        );
      }

      final area = properties['city'] as String? ??
          properties['town'] as String? ??
          properties['village'] as String? ??
          properties['county'] as String? ??
          '';
      final state = properties['state'] as String? ?? '';
      final country = properties['country'] as String? ?? '';

      if (area.isEmpty && state.isEmpty) {
        throw const GeoapifyException(
          'No recognisable area or state at this location.',
        );
      }

      return GeoapifyLocation(
        area: area,
        state: state,
        country: country,
      );
    } on GeoapifyException {
      rethrow;
    } on FormatException {
      throw const GeoapifyException(
        'Geoapify returned invalid location data.',
      );
    } catch (_) {
      throw const GeoapifyException(
        'Unable to resolve location. Check your connection and try again.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<GeoapifyRouteResult> computeHikingRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    List<TrailCheckpoint> waypoints = const [],
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const GeoapifyException(
        'Geoapify API key is not configured.',
      );
    }

    final client = _client ?? http.Client();
    try {
      final wpStrings = [
        '$startLatitude,$startLongitude',
        for (final wp in waypoints) '${wp.latitude},${wp.longitude}',
        '$endLatitude,$endLongitude',
      ].join('|');
      final response = await client.get(
        Uri.https('api.geoapify.com', '/v1/routing', {
          'waypoints': wpStrings,
          'mode': 'hike',
          'format': 'geojson',
          'details': 'elevation',
          'apiKey': _apiKey,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeoapifyException(
          'Geoapify routing ${response.statusCode}: ${response.body}',
        );
      }

      final data = _parseRouteResponse(response.body);
      return GeoapifyRouteResult(
        distanceMeters: data.distanceMeters,
        durationSeconds: data.durationSeconds,
        coordinates: data.coordinates,
        elevationGainMeters: data.elevationGainMeters,
      );
    } on GeoapifyException {
      rethrow;
    } on FormatException {
      throw const GeoapifyException(
        'Geoapify routing returned invalid data.',
      );
    } catch (_) {
      throw const GeoapifyException(
        'Unable to compute hiking route. Check your connection.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  _ParsedRouteData _parseRouteResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const GeoapifyException('Unexpected response format.');
    }

    final features = decoded['features'];
    if (features is! List || features.isEmpty) {
      throw const GeoapifyException('No route found.');
    }

    final feature = features.first as Map?;
    if (feature == null) {
      throw const GeoapifyException('Invalid route feature.');
    }

    final properties = feature['properties'] as Map?;
    if (properties == null) {
      throw const GeoapifyException('Missing route properties.');
    }

    final distanceRaw = properties['distance'];
    final timeRaw = properties['time'];
    final distanceMeters = distanceRaw is num ? distanceRaw.toInt() : 0;
    final durationSeconds = timeRaw is num ? timeRaw.toDouble() : 0.0;

    if (distanceMeters <= 0 || durationSeconds <= 0) {
      throw const GeoapifyException('Route has no distance or duration.');
    }

    final geometry = feature['geometry'] as Map?;
    if (geometry == null) {
      throw const GeoapifyException('Missing route geometry.');
    }

    final coordinatesRaw = geometry['coordinates'];
    List<List<double>> coordinates;
    if (coordinatesRaw is List && coordinatesRaw.isNotEmpty) {
      if (coordinatesRaw.first is List) {
        coordinates = coordinatesRaw
            .whereType<List>()
            .expand((segment) => segment)
            .whereType<List>()
            .map((point) {
              final lon = point[0] is num ? (point[0] as num).toDouble() : 0.0;
              final lat = point[1] is num ? (point[1] as num).toDouble() : 0.0;
              return [lon, lat];
            })
            .toList();
      } else {
        coordinates = [];
      }
    } else {
      coordinates = [];
    }

    if (coordinates.length < 2) {
      throw const GeoapifyException('Route path has too few points.');
    }

    double? elevationGain;
    final legs = properties['legs'] as List?;
    if (legs != null && legs.isNotEmpty) {
      final firstLeg = legs.first as Map?;
      if (firstLeg != null) {
        final gain = firstLeg['elevation_gain'];
        if (gain is num) {
          elevationGain = gain.toDouble();
        }
      }
    }

    return _ParsedRouteData(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      coordinates: coordinates,
      elevationGainMeters: elevationGain,
    );
  }
}
