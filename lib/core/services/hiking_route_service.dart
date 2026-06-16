import '../../trail/Model/trail_models.dart';
import 'geoapify_service.dart';
import 'google_routes_service.dart';
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
    OpenTopoDataService? openTopoDataService,
  })  : _openRouteService = openRouteService ?? OpenRouteService(),
        _geoapifyService = geoapifyService ?? GeoapifyService(),
        _googleRoutesService =
            googleRoutesService ?? GoogleRoutesService(),
        _openTopoDataService =
            openTopoDataService ?? OpenTopoDataService();

  final OpenRouteService _openRouteService;
  final GeoapifyService _geoapifyService;
  final GoogleRoutesService _googleRoutesService;
  final OpenTopoDataService _openTopoDataService;

  Future<HikingRouteResult> findHikingRouteForTrail(Trail trail) async {
    if (trail.checkpoints.length < 2) {
      throw const HikingRouteServiceException(
        'Trail needs at least a start and destination point.',
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

    try {
      final ors = await _openRouteService.computeFootHikingRoute(
        startLatitude: startLat,
        startLongitude: startLng,
        endLatitude: endLat,
        endLongitude: endLng,
      );

      double elevation = ors.ascentMeters;
      List<List<double>> coords = ors.coordinates;

      if (elevation <= 0) {
        try {
          final topo = await _openTopoDataService.getElevations(
            coordinates: coords,
          );
          elevation = topo.elevationGainMeters;
        } catch (_) {}
      }

      final durationMin = hikingDurationMinutes(
        ors.distanceMeters,
        elevationGainMeters: elevation,
      );

      final points = coords.map((c) => _LatLng(c[1], c[0])).toList();
      final polyline = _PolylineEncoder.encode(points);

      return HikingRouteResult(
        distanceMeters: ors.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: polyline,
        elevationGainMeters: elevation,
        sourceLabel: 'ORS foot-hiking',
      );
    } on OpenRouteServiceException {
      // fall through to Geoapify
    }

    try {
      final geoapify = await _geoapifyService.computeHikingRoute(
        startLatitude: startLat,
        startLongitude: startLng,
        endLatitude: endLat,
        endLongitude: endLng,
      );

      double elevation = geoapify.elevationGainMeters ?? 0;
      List<List<double>> coords = geoapify.coordinates;

      if (elevation <= 0) {
        try {
          final topo = await _openTopoDataService.getElevations(
            coordinates: coords,
          );
          elevation = topo.elevationGainMeters;
        } catch (_) {}
      }

      final durationMin = hikingDurationMinutes(
        geoapify.distanceMeters,
        elevationGainMeters: elevation,
      );

      final points = coords.map((c) => _LatLng(c[1], c[0])).toList();
      final polyline = _PolylineEncoder.encode(points);

      return HikingRouteResult(
        distanceMeters: geoapify.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: polyline,
        elevationGainMeters: elevation,
        sourceLabel: 'Geoapify hiking route',
      );
    } on GeoapifyException {
      // fall through to Google
    }

    try {
      final googleRoute =
          await _googleRoutesService.computeWalkingRouteForTrail(trail);
      if (!_routeDistanceLooksUsable(trail, googleRoute.distanceMeters)) {
        throw GoogleRoutesServiceException(
          'Google route distance ${googleRoute.distanceLabel} does not match ${trail.distanceLabel}.',
        );
      }

      final durationMin = hikingDurationMinutes(
        googleRoute.distanceMeters,
      );

      return HikingRouteResult(
        distanceMeters: googleRoute.distanceMeters,
        duration: Duration(minutes: durationMin),
        encodedPolyline: googleRoute.encodedPolyline,
        elevationGainMeters: googleRoute.elevationGainMeters,
        sourceLabel: 'Google Walking Route',
      );
    } on GoogleRoutesServiceException catch (googleError) {
      throw HikingRouteServiceException(
        'No route found. ORS: unavailable. Geoapify: unavailable. '
        'Google: ${googleError.message}',
      );
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

class _LatLng {
  const _LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

abstract final class _PolylineEncoder {
  static String encode(List<_LatLng> points) {
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
