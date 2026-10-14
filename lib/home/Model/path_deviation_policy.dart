import 'dart:math' as math;

abstract final class PathDeviationPolicy {
  static const int minimumDistanceMeters = 10;
  static const int maximumDistanceMeters = 50;
  static const int defaultDistanceMeters = 30;

  static int normalizeDistance(Object? value) {
    if (value is! num || !value.isFinite) return defaultDistanceMeters;
    return value.round().clamp(minimumDistanceMeters, maximumDistanceMeters);
  }

  /// Retain the GPS uncertainty guard so drift does not become a route warning.
  static double effectiveThreshold({
    required int selectedDistanceMeters,
    double? accuracyMeters,
  }) {
    final accuracy =
        accuracyMeters != null && accuracyMeters.isFinite && accuracyMeters >= 0
        ? accuracyMeters
        : 0.0;
    return math.max(
      normalizeDistance(selectedDistanceMeters).toDouble(),
      accuracy * 2,
    );
  }
}
