import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

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
    this.minElevationMeters,
    this.maxElevationMeters,
    this.sourceLabel = 'Unknown',
  });

  final int distanceMeters;
  final Duration duration;
  final String encodedPolyline;
  final double? elevationGainMeters;
  final double? minElevationMeters;
  final double? maxElevationMeters;
  final String sourceLabel;

  bool get hasElevationRange =>
      minElevationMeters != null &&
      maxElevationMeters != null &&
      maxElevationMeters! >= minElevationMeters!;

  String get elevationRangeLabel => hasElevationRange
      ? '${minElevationMeters!.round()} m – ${maxElevationMeters!.round()} m'
      : 'Not available';

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
    if (trail.checkpoints.length < 2 ||
        trail.checkpoints.length > 12 ||
        trail.checkpoints.any((point) => !point.hasValidCoordinate)) {
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

    if (sorted.length >= 2) {
      try {
        final optimized = await _mapboxOptimizationService
            .walkingRouteInOrder(sorted)
            .timeout(const Duration(seconds: 30));
        if (optimized.distanceMeters <= 0 ||
            optimized.encodedPolyline.isEmpty) {
          throw const MapboxOptimizationException(
            'Mapbox returned an incomplete route.',
          );
        }
        final decoded = PolylineCodec.decode(optimized.encodedPolyline);
        if (decoded.length < 2) {
          throw const FormatException('Route has too few points.');
        }
        final topo = await _elevationProfile(
          decoded.map((point) => [point.longitude, point.latitude]).toList(),
        );
        final elevation = topo?.elevationGainMeters ?? 0;
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
          minElevationMeters: topo?.minimumElevationMeters,
          maxElevationMeters: topo?.maximumElevationMeters,
          sourceLabel: 'Mapbox walking route (checkpoint order)',
        );
      } on FormatException {
        // Malformed provider geometry must not prevent another provider trying.
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
      final coords = ors.coordinates;
      _validateProviderRoute(ors.distanceMeters, coords);
      final topo = await _elevationProfile(coords);
      if (elevation <= 0) elevation = topo?.elevationGainMeters ?? 0;

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
        minElevationMeters: topo?.minimumElevationMeters,
        maxElevationMeters: topo?.maximumElevationMeters,
        sourceLabel: 'ORS foot-hiking',
      );
    } on FormatException {
      // Invalid geometry is an unavailable provider response.
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
      final coords = geoapify.coordinates;
      _validateProviderRoute(geoapify.distanceMeters, coords);
      final topo = await _elevationProfile(coords);
      if (elevation <= 0) elevation = topo?.elevationGainMeters ?? 0;

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
        minElevationMeters: topo?.minimumElevationMeters,
        maxElevationMeters: topo?.maximumElevationMeters,
        sourceLabel: 'Geoapify hiking route',
      );
    } on FormatException {
      // Continue to Google if provider geometry cannot be decoded safely.
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

      final decoded = PolylineCodec.decode(googleRoute.encodedPolyline);
      if (decoded.length < 2) {
        throw const FormatException('Route has too few points.');
      }
      final topo = await _elevationProfile(
        decoded.map((point) => [point.longitude, point.latitude]).toList(),
      );
      final elevation =
          googleRoute.elevationGainMeters ?? topo?.elevationGainMeters ?? 0;
      final durationMin = hikingDurationMinutes(
        googleRoute.distanceMeters,
        elevationGainMeters: elevation,
      );

      return HikingRouteResult(
        distanceMeters: googleRoute.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: googleRoute.encodedPolyline,
        elevationGainMeters: elevation,
        minElevationMeters: topo?.minimumElevationMeters,
        maxElevationMeters: topo?.maximumElevationMeters,
        sourceLabel: 'Google Walking Route',
      );
    } on TimeoutException {
      throw const HikingRouteServiceException(
        'Route providers are responding slowly. The route will be retried.',
      );
    } on FormatException {
      throw const HikingRouteServiceException(
        'Route providers returned invalid geometry. Please retry.',
      );
    } on GoogleRoutesServiceException catch (googleError) {
      throw HikingRouteServiceException(
        'No route found. ORS: unavailable. Geoapify: unavailable. '
        'Google: ${googleError.message}',
      );
    }
  }

  void _validateProviderRoute(
    int distanceMeters,
    List<List<double>> coordinates,
  ) {
    if (distanceMeters <= 0 ||
        coordinates.length < 2 ||
        coordinates.any(
          (point) =>
              point.length < 2 ||
              !point[0].isFinite ||
              !point[1].isFinite ||
              point[0] < -180 ||
              point[0] > 180 ||
              point[1] < -90 ||
              point[1] > 90,
        )) {
      throw const FormatException(
        'Route provider returned invalid coordinates.',
      );
    }
  }

  static String checkpointsHash(List<TrailCheckpoint> checkpoints) {
    final sorted = [...checkpoints]..sort((a, b) => a.order.compareTo(b.order));
    final canonical = sorted
        .map(
          (c) =>
              '${c.latitude.toStringAsFixed(6)},${c.longitude.toStringAsFixed(6)}',
        )
        .join(';');
    return 'sha256:${sha256.convert(utf8.encode(canonical))}';
  }

  static bool savedRouteMatchesCheckpoints(Trail trail) {
    final saved = trail.routeCheckpointsHash?.trim() ?? '';
    return saved.isEmpty ||
        saved == checkpointsHash(trail.checkpoints) ||
        saved == _legacyCheckpointsHash(trail.checkpoints);
  }

  static String _legacyCheckpointsHash(List<TrailCheckpoint> checkpoints) {
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
    final currentHash = checkpointsHash(trail.checkpoints);
    if (_isUsablePolyline(savedPolyline) &&
        savedRouteMatchesCheckpoints(trail)) {
      return HikingRouteResult(
        distanceMeters: (trail.distanceKm * 1000).round(),
        duration: Duration(minutes: trail.estimatedDurationMinutes),
        encodedPolyline: savedPolyline,
        elevationGainMeters: trail.elevationGainMeters.toDouble(),
        minElevationMeters: trail.minElevationMeters?.toDouble(),
        maxElevationMeters: trail.maxElevationMeters?.toDouble(),
        sourceLabel: 'Saved trail route',
      );
    }

    final db = _localDatabase;
    if (db != null) {
      try {
        final cached = await db.loadRouteCache(
          trailId: trail.trailId,
          checkpointsHash: currentHash,
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
              minElevationMeters: trail.minElevationMeters?.toDouble(),
              maxElevationMeters: trail.maxElevationMeters?.toDouble(),
              sourceLabel: '${cached['source_label']} (cached)',
            );
          }
        }
      } catch (_) {
        // Cache lookup failure is non-fatal; proceed to fetch route.
      }
    }

    if (trail.checkpoints.length < 2 ||
        trail.checkpoints.length > 12 ||
        trail.checkpoints.any((point) => !point.hasValidCoordinate)) {
      throw const HikingRouteServiceException(
        'A route requires between 2 and 12 checkpoints.',
      );
    }

    final result = await findHikingRouteForTrail(trail);

    if (db != null) {
      try {
        await db.saveRouteCache(
          trailId: trail.trailId,
          checkpointsHash: currentHash,
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

  Future<OpenTopoDataResult?> _elevationProfile(
    List<List<double>> coordinates,
  ) async {
    if (coordinates.isEmpty) return null;
    const maximumSamples = 100;
    final sampled = coordinates.length <= maximumSamples
        ? coordinates
        : List<List<double>>.generate(maximumSamples, (index) {
            final sourceIndex =
                ((coordinates.length - 1) * index / (maximumSamples - 1))
                    .round();
            return coordinates[sourceIndex];
          }, growable: false);
    try {
      return await _openTopoDataService
          .getElevations(coordinates: sampled)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      // Route creation remains usable if optional elevation sampling is down.
      return null;
    }
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
      if (!point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180) {
        throw const FormatException('Polyline coordinate is out of range.');
      }
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
    if (encoded.length > 2000000) {
      throw const FormatException('Polyline is too large.');
    }
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    int readDelta() {
      var shift = 0;
      var result = 0;
      while (true) {
        if (index >= encoded.length || shift > 30) {
          throw const FormatException(
            'Polyline contains a truncated coordinate.',
          );
        }
        final byte = encoded.codeUnitAt(index++) - 63;
        if (byte < 0 || byte > 63) {
          throw const FormatException(
            'Polyline contains an invalid character.',
          );
        }
        result |= (byte & 0x1f) << shift;
        if (byte < 0x20) {
          return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
        }
        shift += 5;
      }
    }

    while (index < encoded.length) {
      latitude += readDelta();
      longitude += readDelta();
      final point = LatLng(latitude / 100000.0, longitude / 100000.0);
      if (point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180) {
        throw const FormatException('Polyline coordinate is out of range.');
      }
      points.add(point);
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
