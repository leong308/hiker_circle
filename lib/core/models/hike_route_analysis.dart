// HikeRouteAnalysis derives checkpoint progress, moving/stopped time and pace samples from
// chronological recorded GPS coordinates.
import 'dart:math' as math;

import '../../home/Model/hike_session_models.dart';

/// Represents hike checkpoint analysis.
class HikeCheckpointAnalysis {
  /// Creates hike checkpoint analysis.
  const HikeCheckpointAnalysis({
    required this.name,
    required this.order,
    required this.reached,
    required this.distanceFromTrackMeters,
    required this.routeIndex,
    required this.reachedAt,
    required this.elapsedFromStart,
    required this.timeFromPrevious,
    required this.distanceFromPreviousKm,
    required this.paceMinutesPerKm,
    required this.speedKmh,
  });

  final String name;
  final int order;
  final bool reached;
  final double distanceFromTrackMeters;
  final int routeIndex;
  final DateTime? reachedAt;
  final Duration? elapsedFromStart;
  final Duration? timeFromPrevious;
  final double distanceFromPreviousKm;
  final double paceMinutesPerKm;
  final double speedKmh;
}

/// Represents hike pace sample.
class HikePaceSample {
  /// Creates hike pace sample.
  const HikePaceSample({
    required this.distanceKm,
    required this.paceMinutesPerKm,
    required this.speedKmh,
    required this.elapsed,
    this.altitudeMeters,
  });

  final double distanceKm;
  final double paceMinutesPerKm;
  final double speedKmh;
  final Duration elapsed;
  final double? altitudeMeters;
}

/// Represents hike route analysis.
class HikeRouteAnalysis {
  /// Creates hike route analysis.
  const HikeRouteAnalysis({
    required this.checkpoints,
    required this.samples,
    required this.totalDistanceKm,
    required this.movingDuration,
    required this.stoppedDuration,
    required this.fastestPaceMinutesPerKm,
  });

  final List<HikeCheckpointAnalysis> checkpoints;
  final List<HikePaceSample> samples;
  final double totalDistanceKm;
  final Duration movingDuration;
  final Duration stoppedDuration;
  final double fastestPaceMinutesPerKm;
}

/// Represents hike analysis checkpoint.
class HikeAnalysisCheckpoint {
  /// Creates hike analysis checkpoint.
  const HikeAnalysisCheckpoint({
    required this.name,
    required this.order,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final int order;
  final double latitude;
  final double longitude;
}

// analyzeHikeRoute orders valid fixes, separates movement from stops and matches checkpoints
// against recorded progress.
/// Computes analyze hike route.
HikeRouteAnalysis analyzeHikeRoute({
  required List<HikeCoordinate> routePoints,
  required List<HikeAnalysisCheckpoint> checkpoints,
  DateTime? fallbackStartedAt,
  double checkpointRadiusMeters = 100,
}) {
  final points = routePoints.where((point) => point.hasValidPosition).toList()
    ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  if (points.isEmpty) {
    return const HikeRouteAnalysis(
      checkpoints: [],
      samples: [],
      totalDistanceKm: 0,
      movingDuration: Duration.zero,
      stoppedDuration: Duration.zero,
      fastestPaceMinutesPerKm: 0,
    );
  }

  var cumulativeMeters = 0.0;
  var movingSeconds = 0;
  var stoppedSeconds = 0;
  final cumulative = <double>[0];
  final samples = <HikePaceSample>[];
  for (var index = 1; index < points.length; index++) {
    final previous = points[index - 1];
    final current = points[index];
    final meters = previous.distanceTo(current);
    final seconds = current.capturedAt
        .difference(previous.capturedAt)
        .inSeconds;
    if (!meters.isFinite || seconds <= 0 || seconds > 3600) {
      cumulative.add(cumulativeMeters);
      continue;
    }
    cumulativeMeters += meters;
    cumulative.add(cumulativeMeters);
    final speedKmh = meters / seconds * 3.6;
    if (speedKmh >= 0.5) {
      movingSeconds += seconds;
    } else {
      stoppedSeconds += seconds;
    }
    if (meters >= 3 && speedKmh > 0 && speedKmh <= 25) {
      final pace = 60 / speedKmh;
      if (pace >= 2.4 && pace <= 120) {
        samples.add(
          HikePaceSample(
            distanceKm: cumulativeMeters / 1000,
            paceMinutesPerKm: pace,
            speedKmh: speedKmh,
            elapsed: current.capturedAt.difference(
              fallbackStartedAt ?? points.first.capturedAt,
            ),
            altitudeMeters: current.altitudeMeters,
          ),
        );
      }
    }
  }
  while (cumulative.length < points.length) {
    cumulative.add(cumulativeMeters);
  }

  final orderedCheckpoints = [...checkpoints]
    ..sort((left, right) => left.order.compareTo(right.order));
  final checkpointResults = <HikeCheckpointAnalysis>[];
  var searchFrom = 0;
  var previousMatchedIndex = 0;
  DateTime? previousReachedAt = fallbackStartedAt ?? points.first.capturedAt;
  for (final checkpoint in orderedCheckpoints) {
    var closestIndex = searchFrom.clamp(0, points.length - 1);
    var closestDistance = double.infinity;
    final target = HikeCoordinate(
      latitude: checkpoint.latitude,
      longitude: checkpoint.longitude,
      capturedAt: points.first.capturedAt,
    );
    for (var index = searchFrom; index < points.length; index++) {
      final distance = points[index].distanceTo(target);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    final reached = closestDistance <= checkpointRadiusMeters;
    final reachedAt = reached && points[closestIndex].capturedAt.year > 1971
        ? points[closestIndex].capturedAt
        : null;
    final segmentMeters = math.max(
      0,
      cumulative[closestIndex] - cumulative[previousMatchedIndex],
    );
    final segmentTime = reachedAt != null && previousReachedAt != null
        ? reachedAt.difference(previousReachedAt)
        : null;
    final validSeconds = segmentTime != null && !segmentTime.isNegative
        ? segmentTime.inSeconds
        : 0;
    final pace = segmentMeters > 0 && validSeconds > 0
        ? validSeconds / 60 / (segmentMeters / 1000)
        : 0.0;
    checkpointResults.add(
      HikeCheckpointAnalysis(
        name: checkpoint.name,
        order: checkpoint.order,
        reached: reached,
        distanceFromTrackMeters: closestDistance,
        routeIndex: closestIndex,
        reachedAt: reachedAt,
        elapsedFromStart: reachedAt?.difference(
          fallbackStartedAt ?? points.first.capturedAt,
        ),
        timeFromPrevious: validSeconds > 0 ? segmentTime : null,
        distanceFromPreviousKm: segmentMeters / 1000,
        paceMinutesPerKm: pace,
        speedKmh: validSeconds > 0 ? segmentMeters / validSeconds * 3.6 : 0,
      ),
    );
    if (reached) {
      searchFrom = closestIndex;
      previousMatchedIndex = closestIndex;
      previousReachedAt = reachedAt;
    }
  }

  final fastestPace = samples.isEmpty
      ? 0.0
      : samples.map((sample) => sample.paceMinutesPerKm).reduce(math.min);
  return HikeRouteAnalysis(
    checkpoints: checkpointResults,
    samples: _downsample(samples, 80),
    totalDistanceKm: cumulativeMeters / 1000,
    movingDuration: Duration(seconds: movingSeconds),
    stoppedDuration: Duration(seconds: stoppedSeconds),
    fastestPaceMinutesPerKm: fastestPace,
  );
}

/// Computes downsample.
List<HikePaceSample> _downsample(List<HikePaceSample> samples, int maximum) {
  if (samples.length <= maximum) return List.unmodifiable(samples);
  final result = <HikePaceSample>[];
  final step = samples.length / maximum;
  for (var index = 0; index < maximum; index++) {
    result.add(samples[(index * step).floor().clamp(0, samples.length - 1)]);
  }
  return List.unmodifiable(result);
}
