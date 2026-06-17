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

    final feature = features.first as Map?;
    if (feature == null) {
      throw const OpenRouteServiceException('Invalid route feature.');
    }

    final properties = feature['properties'] as Map?;
    if (properties == null) {
      throw const OpenRouteServiceException('Missing route properties.');
    }

    final summary = properties['summary'] as Map?;
    final segments = properties['segments'] as List?;

    int distanceMeters;
    double durationSeconds;
    double ascentMeters = 0;

    if (summary != null) {
      distanceMeters = _numValue(summary['distance']).toInt();
      durationSeconds = _numValue(summary['duration']);
    } else if (segments != null && segments.isNotEmpty) {
      final seg = segments.first as Map;
      distanceMeters = _numValue(seg['distance']).toInt();
      durationSeconds = _numValue(seg['duration']);
      final ascent = seg['ascent'];
      if (ascent is num) {
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

    final geometry = feature['geometry'] as Map?;
    if (geometry == null) {
      throw const OpenRouteServiceException('Missing route geometry.');
    }

    final coordinatesRaw = geometry['coordinates'];
    final coordinates = <List<double>>[];

    if (coordinatesRaw is List && coordinatesRaw.isNotEmpty) {
      if (coordinatesRaw.first is List) {
        for (final raw in coordinatesRaw) {
          if (raw is List && raw.length >= 2) {
            final lon = _numValue(raw[0]);
            final lat = _numValue(raw[1]);
            coordinates.add([lon, lat]);
          }
        }
      }
    }

    if (coordinates.length < 2) {
      throw const OpenRouteServiceException(
        'Route path has too few points.',
      );
    }

    if (ascentMeters <= 0 && segments == null) {
      if (segments != null && segments.isNotEmpty) {
        final seg = segments.first as Map;
        final ascent = seg['ascent'];
        if (ascent is num) {
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
    if (value is num) return value.toDouble();
    return 0.0;
  }
}
