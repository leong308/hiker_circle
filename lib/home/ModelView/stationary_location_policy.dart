import 'dart:math' as math;

/// Accuracy-aware movement policy used by the prolonged-stillness watch.
///
/// A fixed five-metre boundary treats ordinary GPS uncertainty as real hiker
/// movement. The policy keeps five metres as the best-case threshold and
/// expands it only as far as the reported uncertainty requires.
abstract final class StationaryLocationPolicy {
  /// Computes movement threshold meters.
  static double movementThresholdMeters({
    double? referenceAccuracyMeters,
    double? currentAccuracyMeters,
  }) {
    final reference = _normalizedAccuracy(referenceAccuracyMeters);
    final current = _normalizedAccuracy(currentAccuracyMeters);
    return math.max(5.0, math.min(100.0, math.max(reference, current) * 1.5));
  }

  /// Checks whether meaningful movement.
  static bool isMeaningfulMovement({
    required double distanceMeters,
    double? referenceAccuracyMeters,
    double? currentAccuracyMeters,
  }) {
    if (!distanceMeters.isFinite || distanceMeters < 0) return false;
    return distanceMeters >
        movementThresholdMeters(
          referenceAccuracyMeters: referenceAccuracyMeters,
          currentAccuracyMeters: currentAccuracyMeters,
        );
  }

  /// Computes normalized accuracy.
  static double _normalizedAccuracy(double? value) {
    if (value == null || !value.isFinite || value < 0) return 0;
    return value.clamp(0, 500).toDouble();
  }
}
