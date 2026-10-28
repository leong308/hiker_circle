import 'trail_models.dart';

/// Identifies a saved forecast location without changing the trail's starting point.
class TrailWeatherLocation {
  /// Keeps the coordinate key aligned with the server's checkpoint documents.
  const TrailWeatherLocation({
    required this.key,
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  static const trailheadKey = 'trailhead';
  final String key;
  final String label;
  final double latitude;
  final double longitude;

  /// Uses coordinate identity so renaming or reordering a checkpoint retains its forecast.
  static String coordinateKey(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(5)}_${longitude.toStringAsFixed(5)}';

  /// Lists unique saved checkpoints only when the trail is longer than 3 km.
  static List<TrailWeatherLocation> forTrail(Trail trail) {
    final head = TrailWeatherLocation(
      key: trailheadKey,
      label: 'Trailhead',
      latitude: trail.latitude,
      longitude: trail.longitude,
    );
    if (trail.distanceKm <= 3) return [head];
    final seen = {coordinateKey(trail.latitude, trail.longitude)};
    final checkpoints = [...trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    return [
      head,
      for (final point in checkpoints)
        if (point.hasValidCoordinate &&
            seen.add(coordinateKey(point.latitude, point.longitude)))
          TrailWeatherLocation(
            key: coordinateKey(point.latitude, point.longitude),
            label: point.name.trim().isEmpty
                ? 'Checkpoint ${point.order + 1}'
                : point.name.trim(),
            latitude: point.latitude,
            longitude: point.longitude,
          ),
    ];
  }
}
