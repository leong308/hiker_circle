// SoloHikePolicy defines the distance acknowledgement threshold for starting a solo hike.
/// Represents solo hike policy.
class SoloHikePolicy {
  /// Creates solo hike policy using .
  const SoloHikePolicy._();

  /// Computes requires group.
  static bool requiresGroup(double km) => km > 20;

  /// Computes requires acknowledgement.
  static bool requiresAcknowledgement(double km) => km > 10 && km <= 20;

  /// Checks whether acknowledged.
  static bool isAcknowledged(double km, double? acknowledgedKm) =>
      acknowledgedKm != null &&
      acknowledgedKm.isFinite &&
      (km - acknowledgedKm).abs() < .001;
}
