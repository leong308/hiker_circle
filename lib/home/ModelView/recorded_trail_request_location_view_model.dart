import 'package:flutter/foundation.dart';

import '../../trail/Data/trail_start_location_resolver.dart';
import '../../trail/Model/trail_start_location.dart';

/// Resolves the recorded trailhead without using the current GPS or selected checkpoint.
class RecordedTrailRequestLocationViewModel extends ChangeNotifier {
  /// Binds lookup and retries to the first valid recorded coordinate.
  RecordedTrailRequestLocationViewModel({
    required this.latitude,
    required this.longitude,
    TrailStartLocationResolver? resolver,
  }) : _resolver = resolver ?? TrailStartLocationResolver();

  final double latitude, longitude;
  final TrailStartLocationResolver _resolver;
  TrailStartLocation? location;
  bool isLoading = false;
  bool hasError = false;
  bool _resolving = false;
  bool _disposed = false;

  /// Prevents submission with an unresolved or failed starting-point location.
  bool get canSubmit => !isLoading && !hasError && location != null;

  /// Retries failed lookups and ignores completions after the page is closed.
  Future<void> resolve() async {
    if (_disposed || _resolving) return;
    _resolving = true;
    isLoading = true;
    hasError = false;
    location = null;
    notifyListeners();
    try {
      final result = await _resolver.resolve(
        latitude: latitude,
        longitude: longitude,
      );
      if (!_disposed) location = result;
    } catch (_) {
      if (!_disposed) hasError = true;
    } finally {
      _resolving = false;
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Stops publishing when the owning suggestion page leaves the screen.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
