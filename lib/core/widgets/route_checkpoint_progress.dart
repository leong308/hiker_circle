// RouteCheckpointProgress exposes the route animation playhead and ordered checkpoint fractions to
// synchronized UI panels.
/// A snapshot of the map animation's own playhead. Checkpoint fractions follow
/// traversal order, so an out-and-back route can revisit the same coordinate.
class RouteCheckpointProgress {
  /// Creates route checkpoint progress.
  const RouteCheckpointProgress({
    this.progress = 0,
    this.checkpointFractions = const {},
    this.checkpointDistancesMeters = const {},
    this.distanceMeters = 0,
    this.estimatedDuration = Duration.zero,
  });
  final Map<int, double> checkpointDistancesMeters;
  final double distanceMeters;
  final Duration estimatedDuration;

  /// Computes leg distance meters.
  double? legDistanceMeters(int from, int to) {
    final start = checkpointDistancesMeters[from];
    final end = checkpointDistancesMeters[to];
    if (start == null ||
        end == null ||
        !start.isFinite ||
        !end.isFinite ||
        end < start) {
      return null;
    }
    return end - start;
  }

  /// Computes leg progress.
  double legProgress(int from, int to) {
    final length = legDistanceMeters(from, to);
    if (length == null) return 0;
    final start = checkpointDistancesMeters[from]!;
    if (length == 0) return distanceMeters >= start ? 1 : 0;
    return ((distanceMeters - start) / length).clamp(0.0, 1.0);
  }

  final double progress;
  final Map<int, double> checkpointFractions;

  /// Returns is ready.
  bool get isReady => checkpointFractions.isNotEmpty;

  /// Returns is complete.
  bool get isComplete => isReady && progress >= 1;

  /// Returns next index.
  int? get nextIndex {
    for (final entry in checkpointFractions.entries) {
      if (entry.value > progress + 1e-6) return entry.key;
    }
    return null;
  }

  /// Convert actual route progress to a position along equally spaced cards.
  double positionIn(List<int> displayOrder) {
    final entries = checkpointFractions.entries.toList();
    if (entries.isEmpty || displayOrder.isEmpty) return 0;
    var previous = entries.first;
    for (final next in entries.skip(1)) {
      if (progress < next.value) {
        final span = next.value - previous.value;
        final t = span <= 0
            ? 0.0
            : ((progress - previous.value) / span).clamp(0.0, 1.0);
        final from = displayOrder.indexOf(previous.key);
        final to = displayOrder.indexOf(next.key);
        return from + (to - from) * t;
      }
      previous = next;
    }
    return displayOrder.indexOf(entries.last.key).toDouble();
  }
}
