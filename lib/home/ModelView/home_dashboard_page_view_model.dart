part of '../home_dashboard_page_feature.dart';

/// Owns the state and non-visual actions of _BestMatchesSection.
class _BestMatchesSectionStateViewModel extends ChangeNotifier {
  /// Creates best matches section state view model.
  _BestMatchesSectionStateViewModel({
    required this.effectChooseRadius,
    required this.effectUseNearest,
  });
  final Future<double?> Function() effectChooseRadius;
  final Future<void> Function({bool select}) effectUseNearest;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  _TrailFilterMode stateFilterMode = _TrailFilterMode.nearest;

  WorldwideRegion? stateRegion;

  double stateNearestRadiusKm = 50;

  /// Computes destinations.
  List<TravelDestination> commandDestinations(List<Trail> trails) => [
    for (final trail in trails)
      (() {
        final checkpoints = [...trail.checkpoints]
          ..sort((a, b) => a.order.compareTo(b.order));
        return (
          id: trail.trailId,
          latitude: checkpoints.isEmpty
              ? trail.latitude
              : checkpoints.first.latitude,
          longitude: checkpoints.isEmpty
              ? trail.longitude
              : checkpoints.first.longitude,
        );
      })(),
  ];

  /// Computes matches region.
  bool commandMatchesRegion(Trail trail) {
    final region = stateRegion;
    if (stateFilterMode != _TrailFilterMode.state || region == null) {
      return true;
    }
    return trail.country.trim().toLowerCase() == region.country.toLowerCase() &&
        trail.state.trim().toLowerCase() == region.state.toLowerCase();
  }

  /// Computes choose nearest.
  Future<void> commandChooseNearest() async {
    final radius = await effectChooseRadius();
    if (!mounted || radius == null) return;
    _publish(() => stateNearestRadiusKm = radius);
    await effectUseNearest();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _MyUpcomingHikesSection.
class _MyUpcomingHikesSectionStateViewModel extends ChangeNotifier {
  /// Creates my upcoming hikes section state view model.
  _MyUpcomingHikesSectionStateViewModel({required this.readHikes});
  final List<UpcomingHike> Function() readHikes;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes ordered hikes.
  List<UpcomingHike> commandOrderedHikes() {
    final now = DateTime.now();
    return readHikes().where((hike) => hike.isUpcomingAt(now)).toList()
      ..sort((a, b) {
        final byTime = a.departureTime.compareTo(b.departureTime);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
