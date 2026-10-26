/// One cadence for saved GPS footprints, uploads and live sharing.
abstract final class LocationUpdateInterval {
  static const defaultValue = Duration(seconds: 30);
  static const options = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  /// Normalizes.
  static Duration normalize(Duration value) =>
      options.contains(value) ? value : defaultValue;

  /// Computes label.
  static String label(Duration value) => value == const Duration(minutes: 1)
      ? 'Every 1 minute'
      : 'Every ${value.inSeconds} seconds';
}
