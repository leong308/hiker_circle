import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';
import '../../trail/Model/trail_models.dart';

class OpenRouteServiceException implements Exception {
  const OpenRouteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenRouteResult {
  const OpenRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.ascentMeters,
    required this.coordinates,
  });

  final int distanceMeters;
  final double durationSeconds;
  final double ascentMeters;
  final List<List<double>> coordinates;
}

class OpenRouteService {
  OpenRouteService({http.Client? client, String? apiKey})
    : _client = client,
      _apiKey = apiKey ?? GoogleApiConfig.openRouteServiceApiKey;

  final http.Client? _client;
  final String _apiKey;

  Future<OpenRouteResult> computeFootHikingRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    List<TrailCheckpoint> waypoints = const [],
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const OpenRouteServiceException(
        'OpenRouteService API key is not configured.',
      );
    }

    final client = _client ?? http.Client();
    try {
      final response = await client.post(
        Uri.https(
          'api.openrouteservice.org',
          '/v2/directions/foot-hiking/geojson',
        ),
        headers: {
          'Authorization': _apiKey,
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json, application/geo+json',
        },
        body: jsonEncode({
          'coordinates': [
            [startLongitude, startLatitude],
            for (final wp in waypoints) [wp.longitude, wp.latitude],
            [endLongitude, endLatitude],
          ],
          'elevation': true,
          'format': 'geojson',
          'preference': 'steepest',
          'avoid_features': ['highways', 'tollways'],
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OpenRouteServiceException(
          'ORS ${response.statusCode}: ${response.body}',
        );
      }

      return _parseRouteResponse(response.body);
    } on OpenRouteServiceException {
      rethrow;
    } on FormatException {
      throw const OpenRouteServiceException(
        'OpenRouteService returned invalid data.',
      );
    } catch (_) {
      throw const OpenRouteServiceException(
        'Unable to compute route via OpenRouteService.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  OpenRouteResult _parseRouteResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const OpenRouteServiceException('Unexpected response format.');
    }

    final features = decoded['features'];
    if (features is! List || features.isEmpty) {
      throw const OpenRouteServiceException('No route found.');
    }

    final rawFeature = features.first;
    if (rawFeature is! Map) {
      throw const OpenRouteServiceException('Invalid route feature.');
    }
    final feature = Map<Object?, Object?>.from(rawFeature);

    final rawProperties = feature['properties'];
    if (rawProperties is! Map) {
      throw const OpenRouteServiceException('Missing route properties.');
    }
    final properties = Map<Object?, Object?>.from(rawProperties);

    final summary = properties['summary'] is Map
        ? Map<Object?, Object?>.from(properties['summary'] as Map)
        : null;
    final segments = properties['segments'] is List
        ? properties['segments'] as List
        : null;

    int distanceMeters;
    double durationSeconds;
    double ascentMeters = 0;

    if (summary != null) {
      distanceMeters = _numValue(summary['distance']).toInt();
      durationSeconds = _numValue(summary['duration']);
    } else if (segments != null && segments.isNotEmpty) {
      final rawSegment = segments.first;
      if (rawSegment is! Map) {
        throw const OpenRouteServiceException('Invalid route segment.');
      }
      final seg = Map<Object?, Object?>.from(rawSegment);
      distanceMeters = _numValue(seg['distance']).toInt();
      durationSeconds = _numValue(seg['duration']);
      final ascent = seg['ascent'];
      if (ascent is num && ascent.isFinite) {
        ascentMeters = ascent.toDouble();
      }
    } else {
      throw const OpenRouteServiceException(
        'Route has no distance or duration.',
      );
    }

    if (distanceMeters <= 0 || durationSeconds <= 0) {
      throw const OpenRouteServiceException(
        'Route has no valid distance or duration.',
      );
    }

    final rawGeometry = feature['geometry'];
    if (rawGeometry is! Map) {
      throw const OpenRouteServiceException('Missing route geometry.');
    }
    final geometry = Map<Object?, Object?>.from(rawGeometry);

    final coordinatesRaw = geometry['coordinates'];
    final coordinates = <List<double>>[];

    if (coordinatesRaw is List && coordinatesRaw.isNotEmpty) {
      if (coordinatesRaw.first is List) {
        for (final raw in coordinatesRaw) {
          if (raw is List && raw.length >= 2) {
            final lon = _numValue(raw[0]);
            final lat = _numValue(raw[1]);
            if (lon >= -180 && lon <= 180 && lat >= -90 && lat <= 90) {
              coordinates.add([lon, lat]);
            }
          }
        }
      }
    }

    if (coordinates.length < 2) {
      throw const OpenRouteServiceException('Route path has too few points.');
    }

    if (ascentMeters <= 0 && segments != null && segments.isNotEmpty) {
      final rawSegment = segments.first;
      if (rawSegment is Map) {
        final seg = Map<Object?, Object?>.from(rawSegment);
        final ascent = seg['ascent'];
        if (ascent is num && ascent.isFinite) {
          ascentMeters = ascent.toDouble();
        }
      }
    }

    return OpenRouteResult(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      ascentMeters: ascentMeters,
      coordinates: coordinates,
    );
  }

  double _numValue(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    return 0.0;
  }
}
