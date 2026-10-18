// MapboxOptimizationService proposes a checkpoint visit order while preserving the caller-selected
// route endpoints.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../trail/Model/trail_models.dart';
import '../config/google_api_config.dart';

class MapboxOptimizationException implements Exception {
  const MapboxOptimizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MapboxOptimizationResult {
  const MapboxOptimizationResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
  });

  final int distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;
}

class MapboxOptimizationService {
  MapboxOptimizationService({http.Client? client, String? accessToken})
    : _client = client,
      _accessToken = accessToken ?? GoogleApiConfig.mapboxAccessToken;

  final http.Client? _client;
  final String _accessToken;

  /// Follows checkpoints in their specified order; a trail is not a
  /// travelling-salesperson tour whose intermediate stops may be reordered.
  Future<MapboxOptimizationResult> walkingRouteInOrder(
    List<TrailCheckpoint> checkpoints,
  ) async {
    if (checkpoints.length < 2 ||
        checkpoints.length > 12 ||
        checkpoints.any(
          (c) =>
              !c.latitude.isFinite ||
              !c.longitude.isFinite ||
              c.latitude.abs() > 90 ||
              c.longitude.abs() > 180,
        )) {
      throw const MapboxOptimizationException('Use 2–12 valid checkpoints.');
    }
    if (_accessToken.trim().isEmpty) {
      throw const MapboxOptimizationException(
        'Mapbox access token is not configured.',
      );
    }
    final sorted = [...checkpoints]..sort((a, b) => a.order.compareTo(b.order));
    final coordinates = sorted
        .map((c) => '${c.longitude},${c.latitude}')
        .join(';');
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/walking/$coordinates',
      {
        'access_token': _accessToken,
        'overview': 'full',
        'geometries': 'polyline',
        'steps': 'false',
        'alternatives': 'false',
        'continue_straight': 'false',
        'radiuses': List.filled(sorted.length, '50').join(';'),
      },
    );
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 || body is! Map || body['code'] != 'Ok') {
        throw const MapboxOptimizationException(
          'No walking route through these checkpoints.',
        );
      }
      final routes = body['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        throw const MapboxOptimizationException(
          'Mapbox returned no walking route.',
        );
      }
      final route = routes.first as Map;
      final geometry = route['geometry'];
      final legs = route['legs'];
      final distance = _roundedPositiveMetric(route['distance']);
      final duration = _roundedPositiveMetric(route['duration']);
      if (geometry is! String ||
          geometry.isEmpty ||
          distance == 0 ||
          duration == 0 ||
          legs is! List ||
          legs.length != sorted.length - 1) {
        throw const MapboxOptimizationException(
          'Mapbox returned an incomplete walking route.',
        );
      }
      return MapboxOptimizationResult(
        distanceMeters: distance,
        durationSeconds: duration,
        encodedPolyline: geometry,
      );
    } on http.ClientException {
      throw const MapboxOptimizationException(
        'Unable to reach Mapbox Directions.',
      );
    } on FormatException {
      throw const MapboxOptimizationException(
        'Mapbox returned invalid route data.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<MapboxOptimizationResult> optimizeWalkingRoute(
    List<TrailCheckpoint> checkpoints,
  ) async {
    if (checkpoints.length < 3 || checkpoints.length > 12) {
      throw const MapboxOptimizationException(
        'Mapbox optimization requires between 3 and 12 checkpoints.',
      );
    }
    if (_accessToken.trim().isEmpty) {
      throw const MapboxOptimizationException(
        'Mapbox access token is not configured.',
      );
    }

    final sorted = [...checkpoints]..sort((a, b) => a.order.compareTo(b.order));
    final coordinates = sorted
        .map((checkpoint) => '${checkpoint.longitude},${checkpoint.latitude}')
        .join(';');
    final uri = Uri.https(
      'api.mapbox.com',
      '/optimized-trips/v1/mapbox/walking/$coordinates',
      {
        'source': 'first',
        'destination': 'last',
        'roundtrip': 'false',
        'overview': 'full',
        'geometries': 'polyline',
        'steps': 'false',
        'radiuses': List.filled(sorted.length, 'unlimited').join(';'),
        'access_token': _accessToken,
      },
    );

    final client = _client ?? http.Client();
    try {
      final response = await client.get(uri);
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded is! Map<String, dynamic>) {
        throw MapboxOptimizationException(
          'Mapbox Optimization ${response.statusCode}.',
        );
      }
      final code = decoded['code'];
      if (code != 'Ok') {
        throw MapboxOptimizationException(
          decoded['message'] is String
              ? decoded['message'] as String
              : 'Mapbox Optimization returned $code.',
        );
      }
      final trips = decoded['trips'];
      if (trips is! List || trips.isEmpty || trips.first is! Map) {
        throw const MapboxOptimizationException(
          'Mapbox did not return an optimized route.',
        );
      }
      final trip = Map<String, dynamic>.from(trips.first as Map);
      final geometry = trip['geometry'];
      if (geometry is! String || geometry.isEmpty) {
        throw const MapboxOptimizationException(
          'Mapbox returned no route geometry.',
        );
      }
      final distanceMeters = _roundedPositiveMetric(trip['distance']);
      final durationSeconds = _roundedPositiveMetric(trip['duration']);
      if (distanceMeters == 0 || durationSeconds == 0) {
        throw const MapboxOptimizationException(
          'Mapbox returned invalid route distance or duration.',
        );
      }

      return MapboxOptimizationResult(
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        encodedPolyline: geometry,
      );
    } on MapboxOptimizationException {
      rethrow;
    } on http.ClientException {
      throw const MapboxOptimizationException(
        'Unable to reach Mapbox Optimization.',
      );
    } on FormatException {
      throw const MapboxOptimizationException(
        'Mapbox returned invalid route data.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  int _roundedPositiveMetric(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) {
      return 0;
    }
    final metric = value.toDouble();
    if (metric > 100000000) {
      return 0;
    }
    return metric.round();
  }
}
