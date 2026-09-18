class SoloHikePolicy {
  const SoloHikePolicy._();
  static bool requiresGroup(double km) => km > 20;
  static bool requiresAcknowledgement(double km) => km > 10 && km <= 20;
  static bool isAcknowledged(double km, double? acknowledgedKm) =>
      acknowledgedKm != null &&
      acknowledgedKm.isFinite &&
      (km - acknowledgedKm).abs() < .001;
}
