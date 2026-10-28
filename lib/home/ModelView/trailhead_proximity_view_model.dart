import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../sos/Model/sos_models.dart';
import '../../trail/Model/trail_models.dart';
import '../Data/trailhead_navigation_service.dart';
import '../Model/trailhead_proximity.dart';

/// Owns location requests and trailhead-distance decisions before hiking.
class TrailheadProximityViewModel extends ChangeNotifier {
  /// Accepts platform dependencies without coupling the wizard to native APIs.
  TrailheadProximityViewModel({
    TrailheadNavigationService service = const TrailheadNavigationService(),
    Future<SosTriggerLocation?> Function()? fetchLocation,
    DateTime Function()? now,
  }) : _fetchLocation = fetchLocation ?? service.fetchLocation,
       _openDirections = service.openDirections,
       _now = now ?? DateTime.now;

  final Future<SosTriggerLocation?> Function() _fetchLocation;
  final Future<bool> Function(Trail) _openDirections;
  final DateTime Function() _now;
  Future<void>? _pending;
  SosTriggerLocation? _location;
  bool _disposed = false;
  int _generation = 0;
  bool checking = false;
  bool continuing = false;

  /// Requests a fresh fix, sharing any native request that is already running.
  Future<void> requestCurrentLocation() {
    if (_disposed) return Future<void>.value();
    // The native location channel accepts one request at a time. A quick
    // Back/Continue sequence can reuse the fresh request that is still running.
    final pending = _pending;
    if (pending != null) return pending;
    _generation++;
    _location = null;
    return refresh();
  }

  /// Shares an in-flight request when Continue is pressed before GPS returns.
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _pending ??= _refresh(_generation);
  }

  /// Publishes only the result belonging to the current location request.
  Future<void> _refresh(int generation) async {
    checking = true;
    notifyListeners();
    // Install the shared future before invoking a platform dependency.
    await Future<void>.value();
    try {
      if (_disposed || generation != _generation) return;
      final location = await _fetchLocation().timeout(
        const Duration(seconds: 15),
      );
      if (_disposed || generation != _generation) return;
      _location = _isFresh(location) ? location : null;
    } catch (_) {
      if (!_disposed && generation == _generation) _location = null;
    } finally {
      if (!_disposed && generation == _generation) {
        checking = false;
        _pending = null;
        notifyListeners();
      }
    }
  }

  /// Rejects missing, invalid or stale fixes instead of treating them as nearby.
  bool _isFresh(SosTriggerLocation? location) {
    final time = location?.capturedAt;
    if (location == null || !location.hasValidPosition || time == null) {
      return false;
    }
    final age = _now().toUtc().difference(time.toUtc());
    return age >= const Duration(seconds: -10) &&
        age <= const Duration(minutes: 1);
  }

  /// Returns the current comparison, refreshing a fix that aged on this page.
  Future<TrailheadProximity?> compare(
    Trail trail, {
    bool refreshLocation = false,
  }) async {
    if (refreshLocation) {
      await requestCurrentLocation();
    } else if (_pending != null) {
      await _pending;
    } else if (!_isFresh(_location)) {
      await refresh();
    }
    if (_disposed || !_isFresh(_location)) return null;
    return TrailheadProximity(location: _location!, trail: trail);
  }

  /// Prevents double taps from opening multiple warning dialogs or advancing twice.
  bool beginContinue() {
    if (_disposed || continuing) return false;
    continuing = true;
    notifyListeners();
    return true;
  }

  /// Releases the navigation gate after a decision or a dismissed dialog.
  void finishContinue() {
    if (_disposed) return;
    continuing = false;
    notifyListeners();
  }

  /// Opens Waze without changing wizard steps.
  Future<bool> openDirections(Trail trail) => _openDirections(trail);

  /// Resolves the warning without advancing when navigation or dismissal is chosen.
  Future<bool> confirmContinue(
    Trail trail, {
    bool refreshLocation = false,
    required Future<TrailheadProximityAction?> Function(TrailheadProximity?)
    presentWarning,
    required VoidCallback onDirectionsUnavailable,
  }) async {
    if (!beginContinue()) return false;
    try {
      while (!_disposed) {
        final comparison = await compare(
          trail,
          refreshLocation: refreshLocation,
        );
        refreshLocation = false;
        if (_disposed) return false;
        if (comparison != null && !comparison.needsWarning) return true;
        final action = await presentWarning(comparison);
        if (_disposed) return false;
        if (action == TrailheadProximityAction.proceed) return true;
        if (action == TrailheadProximityAction.retry) continue;
        if (action == TrailheadProximityAction.directions) {
          final opened = await openDirections(trail);
          if (!opened && !_disposed) onDirectionsUnavailable();
        }
        return false;
      }
      return false;
    } finally {
      finishContinue();
    }
  }

  /// Ignores late platform results after the wizard closes.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
