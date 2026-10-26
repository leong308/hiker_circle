import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../../core/services/hiking_route_service.dart';
import 'local_trail_paths.dart';

/// Represents trail duplicate match.
class TrailDuplicateMatch {
  /// Creates trail duplicate match.
  const TrailDuplicateMatch({
    required this.trailId,
    required this.trailName,
    required this.similarity,
  });
  final String trailId, trailName;
  final double similarity;

  /// Returns percentage.
  String get percentage {
    final rounded = (similarity * 100).toStringAsFixed(1);
    return similarity > TrailRouteSimilarity.threshold && rounded == '70.0'
        ? '>70'
        : rounded;
  }
}

/// Represents trail duplicate checker.
class TrailDuplicateChecker {
  /// Creates trail duplicate checker.
  const TrailDuplicateChecker(this.database);
  final LocalSessionDatabase database;

  /// Checks polyline.
  Future<TrailDuplicateMatch?> checkPolyline(String encoded) => check([
    for (final p in PolylineCodec.decode(encoded))
      (latitude: p.latitude, longitude: p.longitude),
  ]);

  /// Checks.
  Future<TrailDuplicateMatch?> check(List<TrailPathCoordinate> proposed) async {
    final catalog = await LocalTrailPaths(database).load();
    // Keep large recorded GPS tracks off the UI isolate. No routing/cloud read.
    return compute(_compareRoutes, (proposed, catalog.paths));
  }
}

/// Computes compare routes.
TrailDuplicateMatch? _compareRoutes(
  (List<TrailPathCoordinate>, List<LocalTrailPath>) input,
) => TrailRouteSimilarity.findDuplicate(input.$1, input.$2);

/// Direction-independent coverage of the proposed route by one saved route.
/// Samples represent equal route lengths, never equal numbers of GPS fixes.
abstract final class TrailRouteSimilarity {
  static const threshold = .70;
  static const toleranceMeters = 25.0;
  static const _sampleSpacing = 10.0;
  static const _earthRadius = 6371000.0;

  /// Finds duplicate.
  static TrailDuplicateMatch? findDuplicate(
    List<TrailPathCoordinate> proposed,
    List<LocalTrailPath> existing,
  ) {
    _validate(proposed);
    final origin = proposed.first;
    final xScale = _earthRadius * math.cos(origin.latitude * math.pi / 180);

    /// Computes project.
    List<math.Point<double>> project(List<TrailPathCoordinate> points) => [
      for (final p in points)
        math.Point(
          (p.longitude - origin.longitude) * math.pi / 180 * xScale,
          (p.latitude - origin.latitude) * math.pi / 180 * _earthRadius,
        ),
    ];
    final candidate = project(proposed);
    final samples = _samples(candidate);
    if (samples.isEmpty) {
      throw const FormatException('The proposed route has no usable length.');
    }
    final bounds = _Bounds(candidate);
    TrailDuplicateMatch? best;
    for (final path in existing) {
      try {
        _validate(path.coordinates);
      } on FormatException {
        continue;
      }
      final stored = project(path.coordinates);
      if (!bounds.near(_Bounds(stored), toleranceMeters)) continue;
      final index = _SegmentIndex(stored);
      final covered = samples.where(index.contains).length;
      final similarity = covered / samples.length;
      // Strictly greater than 70%, including protection against rounding noise.
      if (similarity > threshold + 1e-9 &&
          (best == null || similarity > best.similarity)) {
        best = TrailDuplicateMatch(
          trailId: path.trailId,
          trailName: path.name,
          similarity: similarity,
        );
        if (similarity == 1) break;
      }
    }
    return best;
  }

  /// Validates.
  static void _validate(List<TrailPathCoordinate> points) {
    if (points.length < 2 ||
        points.any(
          (p) =>
              !p.latitude.isFinite ||
              !p.longitude.isFinite ||
              p.latitude.abs() > 90 ||
              p.longitude.abs() > 180,
        )) {
      throw const FormatException(
        'The complete route coordinates are unavailable.',
      );
    }
  }

  /// Computes samples.
  static List<math.Point<double>> _samples(List<math.Point<double>> points) {
    final segments = <_Segment>[];
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final segment = _Segment(points[i - 1], points[i]);
      if (segment.length <= 1e-6) continue;
      segments.add(segment);
      total += segment.length;
    }
    if (segments.isEmpty) return [];
    final count = (total / _sampleSpacing).ceil().clamp(1, 100000);
    final spacing = total / count;
    var segmentIndex = 0, consumed = 0.0;
    final result = <math.Point<double>>[];
    for (var i = 0; i < count; i++) {
      final distance = (i + .5) * spacing;
      while (segmentIndex < segments.length - 1 &&
          consumed + segments[segmentIndex].length < distance) {
        consumed += segments[segmentIndex++].length;
      }
      final segment = segments[segmentIndex];
      result.add(segment.at((distance - consumed) / segment.length));
    }
    return result;
  }
}

/// Represents segment.
class _Segment {
  /// Creates segment.
  _Segment(this.start, this.end) : length = start.distanceTo(end);
  final math.Point<double> start, end;
  final double length;

  /// Computes at.
  math.Point<double> at(double t) => math.Point(
    start.x + (end.x - start.x) * t,
    start.y + (end.y - start.y) * t,
  );

  /// Computes squared distance.
  double squaredDistance(math.Point<double> p) {
    final dx = end.x - start.x, dy = end.y - start.y;
    final t =
        (((p.x - start.x) * dx + (p.y - start.y) * dy) / (dx * dx + dy * dy))
            .clamp(0.0, 1.0);
    final x = p.x - start.x - t * dx, y = p.y - start.y - t * dy;
    return x * x + y * y;
  }
}

/// Represents bounds.
class _Bounds {
  /// Creates bounds.
  _Bounds(List<math.Point<double>> points)
    : west = points.map((p) => p.x).reduce(math.min),
      east = points.map((p) => p.x).reduce(math.max),
      south = points.map((p) => p.y).reduce(math.min),
      north = points.map((p) => p.y).reduce(math.max);
  final double west, east, south, north;

  /// Computes near.
  bool near(_Bounds other, double tolerance) =>
      west <= other.east + tolerance &&
      east + tolerance >= other.west &&
      south <= other.north + tolerance &&
      north + tolerance >= other.south;
}

/// Represents segment index.
class _SegmentIndex {
  /// Creates segment index.
  _SegmentIndex(List<math.Point<double>> points) {
    for (var i = 1; i < points.length; i++) {
      final full = _Segment(points[i - 1], points[i]);
      if (full.length <= 1e-6) continue;
      // Bound each grid insertion even when stored geometry is very sparse.
      final pieces = (full.length / _cellSize).ceil();
      for (var j = 0; j < pieces; j++) {
        final segment = _Segment(
          full.at(j / pieces),
          full.at((j + 1) / pieces),
        );
        final left =
            ((math.min(segment.start.x, segment.end.x) - _tolerance) /
                    _cellSize)
                .floor();
        final right =
            ((math.max(segment.start.x, segment.end.x) + _tolerance) /
                    _cellSize)
                .floor();
        final bottom =
            ((math.min(segment.start.y, segment.end.y) - _tolerance) /
                    _cellSize)
                .floor();
        final top =
            ((math.max(segment.start.y, segment.end.y) + _tolerance) /
                    _cellSize)
                .floor();
        for (var x = left; x <= right; x++) {
          for (var y = bottom; y <= top; y++) {
            (_cells[(x, y)] ??= []).add(segment);
          }
        }
      }
    }
  }
  static const _cellSize = 50.0;
  static const _tolerance = TrailRouteSimilarity.toleranceMeters;
  final _cells = <(int, int), List<_Segment>>{};

  /// Computes contains.
  bool contains(math.Point<double> point) {
    final key = ((point.x / _cellSize).floor(), (point.y / _cellSize).floor());
    return _cells[key]?.any(
          (s) => s.squaredDistance(point) <= _tolerance * _tolerance,
        ) ??
        false;
  }
}
