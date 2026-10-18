/// One upload cadence for live sharing and the saved footprint batch.
abstract final class LocationUpdateInterval {
  static const defaultValue = Duration(seconds: 30);
  static const options = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  static Duration normalize(Duration value) =>
      options.contains(value) ? value : defaultValue;

  static String label(Duration value) => value == const Duration(minutes: 1)
      ? 'Every 1 minute'
      : 'Every ${value.inSeconds} seconds';
}
