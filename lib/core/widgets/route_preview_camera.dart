import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'map_utils.dart';

/// The map position and heading used by the route preview's follow camera.
class RoutePreviewCameraFrame {
  const RoutePreviewCameraFrame({
    required this.center,
    required this.bearing,
    required this.distanceMeters,
  });

  final mapbox.Point center;
  final double bearing;
  final double distanceMeters;
}

class RoutePreviewCameraTuning {
  const RoutePreviewCameraTuning({
    required this.pitch,
    required this.zoomOffset,
    required this.lookAheadMeters,
  });

  final double pitch;
  final double zoomOffset;
  final double lookAheadMeters;
}

/// Returns a deliberately watchable FPV duration for a route.
///
/// At 1x the preview advances at roughly 30 metres per second, constrained so
/// short routes are not rushed and very long routes remain practical. The
/// selectable multiplier changes playback speed, not the hiker's ETA.
Duration routePreviewPlaybackDuration({
  required double totalDistanceMeters,
  required double speed,
}) {
  final safeDistance = totalDistanceMeters.isFinite
      ? math.max(0.0, totalDistanceMeters)
      : 0.0;
  final safeSpeed = speed.isFinite && speed > 0 ? speed : 1.0;
  final baseSeconds = (safeDistance / 30).clamp(60.0, 300.0);
  return Duration(
    milliseconds: math.max(1000, (baseSeconds * 1000 / safeSpeed).round()),
  );
}

/// Converts a trail grade percentage (rise / horizontal distance x 100) to its
/// equivalent incline angle in degrees.
double routePreviewSlopeDegrees(double gradePercent) {
  if (!gradePercent.isFinite) return 0;
  return math.atan(gradePercent / 100) * 180 / math.pi;
}

/// Adapts the route camera when descending so foreground terrain does not
/// obscure the path. Level and ascending sections retain the immersive view.
RoutePreviewCameraTuning routePreviewCameraTuning(double? gradePercent) {
  final slopeDegrees = gradePercent == null
      ? 0.0
      : routePreviewSlopeDegrees(gradePercent);
  final descentSeverity = (-slopeDegrees / 16).clamp(0.0, 1.0).toDouble();
  return RoutePreviewCameraTuning(
    pitch: 68 - (38 * descentSeverity),
    zoomOffset: -1.1 * descentSeverity,
    lookAheadMeters: 25 + (95 * descentSeverity),
  );
}

/// Returns an eight-point compass label for the FPV camera heading.
String routePreviewCardinalDirection(double bearing) {
  if (!bearing.isFinite) return 'N';
  const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final normalized = (bearing % 360 + 360) % 360;
  return directions[((normalized + 22.5) ~/ 45) % directions.length];
}

/// Builds a smooth camera frame for an index-based route animation.
///
/// The existing route reveal advances through encoded-polyline points. The
/// camera uses the same progression so that its position never races ahead of
/// the visible route, while its heading looks farther along the path by a real
/// distance in metres.
RoutePreviewCameraFrame? routePreviewCameraFrame({
  required List<mapbox.Point> points,
  required List<double> cumulativeDistances,
  required double progress,
  double lookAheadMeters = 35,
}) {
  if (points.length < 2 || cumulativeDistances.length != points.length) {
    return null;
  }
  if (cumulativeDistances.any((distance) => !distance.isFinite)) {
    return null;
  }

  final clampedProgress = progress.clamp(0.0, 1.0);
  final indexPosition = clampedProgress * (points.length - 1);
  final segmentIndex = indexPosition.floor().clamp(0, points.length - 2);
  final segmentFraction = (indexPosition - segmentIndex).clamp(0.0, 1.0);
  final center = _interpolatePoint(
    points[segmentIndex],
    points[segmentIndex + 1],
    segmentFraction,
  );
  if (center == null) return null;

  final segmentStartDistance = cumulativeDistances[segmentIndex];
  final segmentEndDistance = cumulativeDistances[segmentIndex + 1];
  final centerDistance =
      segmentStartDistance +
      (segmentEndDistance - segmentStartDistance) * segmentFraction;
  final totalDistance = cumulativeDistances.last;
  final safeLookAhead = math.max(8.0, lookAheadMeters);

  mapbox.Point? headingFrom = center;
  mapbox.Point? headingTo;
  if (centerDistance < totalDistance - 0.5) {
    headingTo = _pointAtDistance(
      points,
      cumulativeDistances,
      math.min(totalDistance, centerDistance + safeLookAhead),
    );
  } else {
    headingFrom = _pointAtDistance(
      points,
      cumulativeDistances,
      math.max(0, totalDistance - safeLookAhead),
    );
    headingTo = center;
  }
  if (headingFrom == null || headingTo == null) return null;

  return RoutePreviewCameraFrame(
    center: center,
    bearing: routePreviewBearing(headingFrom, headingTo),
    distanceMeters: centerDistance,
  );
}

/// Returns the route point at a cumulative distance from the start.
mapbox.Point? routePreviewPointAtDistance({
  required List<mapbox.Point> points,
  required List<double> cumulativeDistances,
  required double distanceMeters,
}) {
  if (points.length < 2 || cumulativeDistances.length != points.length) {
    return null;
  }
  return _pointAtDistance(points, cumulativeDistances, distanceMeters);
}

/// Returns a compass bearing in degrees clockwise from true north.
double routePreviewBearing(mapbox.Point from, mapbox.Point to) {
  final start = mapPointCoordinatesOrNull(from);
  final end = mapPointCoordinatesOrNull(to);
  if (start == null || end == null) return 0;

  final startLatitude = start.latitude * math.pi / 180;
  final endLatitude = end.latitude * math.pi / 180;
  final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
  final y = math.sin(longitudeDelta) * math.cos(endLatitude);
  final x =
      math.cos(startLatitude) * math.sin(endLatitude) -
      math.sin(startLatitude) *
          math.cos(endLatitude) *
          math.cos(longitudeDelta);
  if (x.abs() < 1e-12 && y.abs() < 1e-12) return 0;
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

mapbox.Point? _pointAtDistance(
  List<mapbox.Point> points,
  List<double> cumulativeDistances,
  double targetDistance,
) {
  if (targetDistance <= 0) return points.first;
  if (targetDistance >= cumulativeDistances.last) return points.last;

  var low = 1;
  var high = cumulativeDistances.length - 1;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (cumulativeDistances[middle] < targetDistance) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  final endIndex = low;
  final startIndex = endIndex - 1;
  final startDistance = cumulativeDistances[startIndex];
  final span = cumulativeDistances[endIndex] - startDistance;
  final fraction = span <= 0
      ? 0.0
      : ((targetDistance - startDistance) / span).clamp(0.0, 1.0);
  return _interpolatePoint(points[startIndex], points[endIndex], fraction);
}

mapbox.Point? _interpolatePoint(
  mapbox.Point start,
  mapbox.Point end,
  double fraction,
) {
  final a = mapPointCoordinatesOrNull(start);
  final b = mapPointCoordinatesOrNull(end);
  if (a == null || b == null) return null;
  return mapbox.Point(
    coordinates: mapbox.Position(
      a.longitude + (b.longitude - a.longitude) * fraction,
      a.latitude + (b.latitude - a.latitude) * fraction,
    ),
  );
}
