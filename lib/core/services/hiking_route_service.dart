import 'dart:async';

import '../../app/Data/local_session_database.dart';
import '../../trail/Model/trail_models.dart';
import 'geoapify_service.dart';
import 'google_routes_service.dart';
import 'mapbox_optimization_service.dart';
import 'naismith_rule.dart';
import 'open_route_service.dart';
import 'open_topo_data_service.dart';

class HikingRouteServiceException implements Exception {
  const HikingRouteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HikingRouteResult {
  const HikingRouteResult({
    required this.distanceMeters,
    required this.duration,
    required this.encodedPolyline,
    this.elevationGainMeters,
    this.sourceLabel = 'Unknown',
  });

  final int distanceMeters;
  final Duration duration;
  final String encodedPolyline;
  final double? elevationGainMeters;
  final String sourceLabel;

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

class HikingRouteService {
  HikingRouteService({
    OpenRouteService? openRouteService,
    GeoapifyService? geoapifyService,
    GoogleRoutesService? googleRoutesService,
    MapboxOptimizationService? mapboxOptimizationService,
    OpenTopoDataService? openTopoDataService,
    LocalSessionDatabase? localDatabase,
  }) : _openRouteService = openRouteService ?? OpenRouteService(),
       _geoapifyService = geoapifyService ?? GeoapifyService(),
       _googleRoutesService = googleRoutesService ?? GoogleRoutesService(),
       _mapboxOptimizationService =
           mapboxOptimizationService ?? MapboxOptimizationService(),
       _openTopoDataService = openTopoDataService ?? OpenTopoDataService(),
       _localDatabase = localDatabase;

  final OpenRouteService _openRouteService;
  final GeoapifyService _geoapifyService;
  final GoogleRoutesService _googleRoutesService;
  final MapboxOptimizationService _mapboxOptimizationService;
  final OpenTopoDataService _openTopoDataService;
  final LocalSessionDatabase? _localDatabase;

  Future<HikingRouteResult> findHikingRouteForTrail(Trail trail) async {
    if (trail.checkpoints.length < 2 || trail.checkpoints.length > 12) {
      throw const HikingRouteServiceException(
        'A route requires between 2 and 12 checkpoints.',
      );
    }

    final sorted = [...trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    final start = sorted.first;
    final end = sorted.last;
    final startLat = start.latitude;
    final startLng = start.longitude;
    final endLat = end.latitude;
    final endLng = end.longitude;
    final waypoints = sorted.length > 2
        ? sorted.sublist(1, sorted.length - 1)
        : <TrailCheckpoint>[];

    if (sorted.length >= 3) {
      try {
        final optimized = await _mapboxOptimizationService
            .optimizeWalkingRoute(sorted)
            .timeout(const Duration(seconds: 30));
        if (optimized.distanceMeters <= 0 ||
            optimized.encodedPolyline.isEmpty) {
          throw const MapboxOptimizationException(
            'Mapbox returned an incomplete route.',
          );
        }
        double elevation = 0;
        try {
          final decoded = PolylineCodec.decode(optimized.encodedPolyline);
          final topo = await _openTopoDataService
              .getElevations(
                coordinates: decoded
                    .map((point) => [point.longitude, point.latitude])
                    .toList(),
              )
              .timeout(const Duration(seconds: 25));
          elevation = topo.elevationGainMeters;
        } catch (_) {
          // Elevation enrichment is best effort.
        }
        return HikingRouteResult(
          distanceMeters: optimized.distanceMeters,
          duration: Duration(
            minutes: hikingDurationMinutes(
              optimized.distanceMeters,
              elevationGainMeters: elevation,
            ),
          ),
          encodedPolyline: optimized.encodedPolyline,
          elevationGainMeters: elevation,
          sourceLabel: 'Mapbox optimized walking route',
        );
      } on MapboxOptimizationException {
        // Fall through to the existing hiking-route providers.
      } on TimeoutException {
        // Fall through to the existing hiking-route providers.
      }
    }

    try {
      final ors = await _openRouteService
          .computeFootHikingRoute(
            startLatitude: startLat,
            startLongitude: startLng,
            endLatitude: endLat,
            endLongitude: endLng,
            waypoints: waypoints,
          )
          .timeout(const Duration(seconds: 45));

      double elevation = ors.ascentMeters;
      List<List<double>> coords = ors.coordinates;

      if (elevation <= 0) {
        try {
          final topo = await _openTopoDataService
              .getElevations(coordinates: coords)
              .timeout(const Duration(seconds: 25));
          elevation = topo.elevationGainMeters;
        } catch (_) {}
      }

      final durationMin = hikingDurationMinutes(
        ors.distanceMeters,
        elevationGainMeters: elevation,
      );

      final points = coords.map((c) => LatLng(c[1], c[0])).toList();
      final polyline = PolylineCodec.encode(points);

      return HikingRouteResult(
        distanceMeters: ors.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: polyline,
        elevationGainMeters: elevation,
        sourceLabel: 'ORS foot-hiking',
      );
    } on OpenRouteServiceException {
      // fall through to Geoapify
    } on TimeoutException {
      // fall through to Geoapify
    }

    try {
      final geoapify = await _geoapifyService
          .computeHikingRoute(
            startLatitude: startLat,
            startLongitude: startLng,
            endLatitude: endLat,
            endLongitude: endLng,
            waypoints: waypoints,
          )
          .timeout(const Duration(seconds: 45));

      double elevation = geoapify.elevationGainMeters ?? 0;
      List<List<double>> coords = geoapify.coordinates;

      if (elevation <= 0) {
        try {
          final topo = await _openTopoDataService
              .getElevations(coordinates: coords)
              .timeout(const Duration(seconds: 25));
          elevation = topo.elevationGainMeters;
        } catch (_) {}
      }

      final durationMin = hikingDurationMinutes(
        geoapify.distanceMeters,
        elevationGainMeters: elevation,
      );

      final points = coords.map((c) => LatLng(c[1], c[0])).toList();
      final polyline = PolylineCodec.encode(points);

      return HikingRouteResult(
        distanceMeters: geoapify.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: polyline,
        elevationGainMeters: elevation,
        sourceLabel: 'Geoapify hiking route',
      );
    } on GeoapifyException {
      // fall through to Google
    } on TimeoutException {
      // fall through to Google
    }

    try {
      final googleRoute = await _googleRoutesService
          .computeWalkingRouteForTrail(trail)
          .timeout(const Duration(seconds: 45));
      if (!_routeDistanceLooksUsable(trail, googleRoute.distanceMeters)) {
        throw GoogleRoutesServiceException(
          'Google route distance ${googleRoute.distanceLabel} does not match ${trail.distanceLabel}.',
        );
      }

      final durationMin = hikingDurationMinutes(googleRoute.distanceMeters);

      return HikingRouteResult(
        distanceMeters: googleRoute.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: googleRoute.encodedPolyline,
        elevationGainMeters: googleRoute.elevationGainMeters,
        sourceLabel: 'Google Walking Route',
      );
    } on TimeoutException {
      throw const HikingRouteServiceException(
        'Route providers are responding slowly. The route will be retried.',
      );
    } on GoogleRoutesServiceException catch (googleError) {
      throw HikingRouteServiceException(
        'No route found. ORS: unavailable. Geoapify: unavailable. '
        'Google: ${googleError.message}',
      );
    }
  }

  static String checkpointsHash(List<TrailCheckpoint> checkpoints) {
    final sorted = [...checkpoints]..sort((a, b) => a.order.compareTo(b.order));
    final buffer = StringBuffer();
    for (final cp in sorted) {
      buffer.write('${cp.name}|${cp.latitude}|${cp.longitude}|${cp.order};');
    }
    return buffer.toString().hashCode.toRadixString(16);
  }

  Future<HikingRouteResult> findHikingRouteForTrailWithCache(
    Trail trail,
  ) async {
    final savedPolyline = trail.routeEncodedPolyline?.trim() ?? '';
    if (_isUsablePolyline(savedPolyline)) {
      return HikingRouteResult(
        distanceMeters: (trail.distanceKm * 1000).round(),
        duration: Duration(minutes: trail.estimatedDurationMinutes),
        encodedPolyline: savedPolyline,
        elevationGainMeters: trail.elevationGainMeters.toDouble(),
        sourceLabel: 'Saved trail route',
      );
    }

    final db = _localDatabase;
    if (db != null) {
      final hash = checkpointsHash(trail.checkpoints);
      try {
        final cached = await db.loadRouteCache(
          trailId: trail.trailId,
          checkpointsHash: hash,
        );
        if (cached != null) {
          final cachedPolyline = cached['encoded_polyline'] as String? ?? '';
          if (_isUsablePolyline(cachedPolyline)) {
            return HikingRouteResult(
              distanceMeters: cached['distance_meters'] as int,
              duration: Duration(seconds: cached['duration_seconds'] as int),
              encodedPolyline: cachedPolyline,
              elevationGainMeters: (cached['elevation_gain_meters'] as num?)
                  ?.toDouble(),
              sourceLabel: '${cached['source_label']} (cached)',
            );
          }
        }
      } catch (_) {
        // Cache lookup failure is non-fatal; proceed to fetch route.
      }
    }

    if (trail.checkpoints.length < 2 || trail.checkpoints.length > 12) {
      throw const HikingRouteServiceException(
        'A route requires between 2 and 12 checkpoints.',
      );
    }

    final result = await findHikingRouteForTrail(trail);

    if (db != null) {
      try {
        await db.saveRouteCache(
          trailId: trail.trailId,
          checkpointsHash: checkpointsHash(trail.checkpoints),
          encodedPolyline: result.encodedPolyline,
          distanceMeters: result.distanceMeters,
          durationSeconds: result.duration.inSeconds,
          elevationGainMeters: result.elevationGainMeters,
          sourceLabel: result.sourceLabel,
        );
      } catch (_) {
        // Cache save failure is non-fatal.
      }
    }

    return result;
  }

  bool _isUsablePolyline(String encodedPolyline) {
    if (encodedPolyline.isEmpty) {
      return false;
    }
    try {
      return PolylineCodec.decode(encodedPolyline).length >= 2;
    } catch (_) {
      return false;
    }
  }

  bool _routeDistanceLooksUsable(Trail trail, int distanceMeters) {
    final expectedDistanceMeters = trail.distanceKm * 1000;
    if (expectedDistanceMeters <= 0) {
      return true;
    }
    final ratio = distanceMeters / expectedDistanceMeters;
    return ratio >= 0.45 && ratio <= 2.1;
  }
}

class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

abstract final class PolylineCodec {
  static String encode(List<LatLng> points) {
    var previousLatitude = 0;
    var previousLongitude = 0;
    final buffer = StringBuffer();

    for (final point in points) {
      final latitude = (point.latitude * 100000).round();
      final longitude = (point.longitude * 100000).round();
      buffer
        ..write(_encodeValue(latitude - previousLatitude))
        ..write(_encodeValue(longitude - previousLongitude));
      previousLatitude = latitude;
      previousLongitude = longitude;
    }

    return buffer.toString();
  }

  static List<LatLng> decode(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var previousLatitude = 0;
    var previousLongitude = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLatitude = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      previousLatitude += deltaLatitude;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLongitude = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      previousLongitude += deltaLongitude;

      points.add(
        LatLng(previousLatitude / 100000.0, previousLongitude / 100000.0),
      );
    }

    return points;
  }

  static String _encodeValue(int value) {
    var encoded = value < 0 ? ~(value << 1) : value << 1;
    final buffer = StringBuffer();
    while (encoded >= 0x20) {
      buffer.writeCharCode((0x20 | (encoded & 0x1f)) + 63);
      encoded >>= 5;
    }
    buffer.writeCharCode(encoded + 63);
    return buffer.toString();
  }
}
