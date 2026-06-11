import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../trail/Model/trail_models.dart';
import '../config/google_api_config.dart';

class GoogleRoutesServiceException implements Exception {
  const GoogleRoutesServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleRouteResult {
  const GoogleRouteResult({
    required this.distanceMeters,
    required this.duration,
    required this.encodedPolyline,
    this.sourceLabel = 'Google Walking Route',
  });

  final int distanceMeters;
  final Duration duration;
  final String encodedPolyline;
  final String sourceLabel;

  GoogleRouteResult copyWith({
    int? distanceMeters,
    Duration? duration,
    String? encodedPolyline,
    String? sourceLabel,
  }) {
    return GoogleRouteResult(
      distanceMeters: distanceMeters ?? this.distanceMeters,
      duration: duration ?? this.duration,
      encodedPolyline: encodedPolyline ?? this.encodedPolyline,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }

  String get distanceLabel {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '$distanceMeters m';
  }

  String get durationLabel {
    final minutes = duration.inMinutes;
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${remainingMinutes}m';
  }
}

class GoogleRoutesService {
  const GoogleRoutesService({
    http.Client? client,
    String apiKey = GoogleApiConfig.routesApiKey,
  }) : _client = client,
       _apiKey = apiKey;

  final http.Client? _client;
  final String _apiKey;

  Future<GoogleRouteResult> computeWalkingRouteForTrail(Trail trail) async {
    if (trail.checkpoints.length < 2) {
      throw const GoogleRoutesServiceException(
        'Trail needs at least a start and destination point.',
      );
    }

    final checkpoints = [...trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    return (await computeWalkingRoute(
      origin: checkpoints.first,
      destination: checkpoints.last,
      intermediates: checkpoints.sublist(1, checkpoints.length - 1),
    )).copyWith(sourceLabel: 'Google Routes walking via checkpoints');
  }

  Future<GoogleRouteResult> computeWalkingRoute({
    required TrailCheckpoint origin,
    required TrailCheckpoint destination,
    List<TrailCheckpoint> intermediates = const [],
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const GoogleRoutesServiceException(
        'Google Routes API key is not configured.',
      );
    }

    final client = _client ?? http.Client();
    try {
      final response = await client.post(
        Uri.https('routes.googleapis.com', '/directions/v2:computeRoutes'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              },
            },
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.latitude,
                'longitude': destination.longitude,
              },
            },
          },
          if (intermediates.isNotEmpty)
            'intermediates': intermediates
                .map(
                  (checkpoint) => {
                    'location': {
                      'latLng': {
                        'latitude': checkpoint.latitude,
                        'longitude': checkpoint.longitude,
                      },
                    },
                  },
                )
                .toList(),
          'travelMode': 'WALK',
          'polylineQuality': 'HIGH_QUALITY',
          'polylineEncoding': 'ENCODED_POLYLINE',
          'computeAlternativeRoutes': false,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleRoutesServiceException(
          'Google Routes ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GoogleRoutesServiceException(
          'Google Routes returned an unexpected response.',
        );
      }

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        throw const GoogleRoutesServiceException(
          'Google Routes did not return a route for this trail.',
        );
      }

      final route = Map<String, dynamic>.from(routes.first as Map);
      final polyline = route['polyline'];
      final encodedPolyline = polyline is Map
          ? polyline['encodedPolyline'] as String? ?? ''
          : '';

      return GoogleRouteResult(
        distanceMeters: route['distanceMeters'] is num
            ? (route['distanceMeters'] as num).toInt()
            : 0,
        duration: _durationFromGoogle(route['duration']),
        encodedPolyline: encodedPolyline,
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Duration _durationFromGoogle(Object? value) {
    if (value is! String || !value.endsWith('s')) {
      return Duration.zero;
    }

    final seconds = int.tryParse(value.substring(0, value.length - 1)) ?? 0;
    return Duration(seconds: seconds);
  }
}
