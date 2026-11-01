// ActiveHikeWeatherController owns forecast refresh state for one account and active hike.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../../core/services/network_reachability_service.dart';
import '../Model/hike_session_models.dart';
import 'active_hike_weather_service.dart';

/// Represents active hike weather view state.
class ActiveHikeWeatherViewState {
  /// Creates active hike weather view state.
  const ActiveHikeWeatherViewState({
    this.snapshot,
    this.isLoading = false,
    this.error,
    this.nextRefreshAt,
  });
  final ActiveHikeWeatherSnapshot? snapshot;
  final bool isLoading;
  final String? error;
  final DateTime? nextRefreshAt;
}

/// One persisted forecast and request clock per owner/hike. Movement, reopening
/// the sheet and cloud ID remaps do not bypass the fifteen-minute interval.
class ActiveHikeWeatherController
    extends ValueNotifier<ActiveHikeWeatherViewState> {
  /// Creates active hike weather controller.
  ActiveHikeWeatherController({
    required this.database,
    required this.ownerPhoneNumber,
    ActiveHikeWeatherService? service,
    DateTime Function()? now,
    bool Function()? isNetworkAvailable,
    Stream<bool>? networkChanges,
  }) : service = service ?? const ActiveHikeWeatherService(),
       _now = now ?? DateTime.now,
       _isNetworkAvailable = isNetworkAvailable ?? _networkMayBeAvailable,
       super(const ActiveHikeWeatherViewState()) {
    _networkSubscription =
        (networkChanges ??
                NetworkReachabilityService.instance.snapshots.map(
                  (snapshot) => snapshot.isOnline,
                ))
            .listen((online) {
              if (online && !_disposed) unawaited(refresh());
            });
  }

  static const refreshInterval = Duration(minutes: 15);
  static const cacheEntityType = 'active_hike_weather';
  final LocalSessionDatabase database;
  final String ownerPhoneNumber;
  final ActiveHikeWeatherService service;
  final DateTime Function() _now;
  final bool Function() _isNetworkAvailable;
  late final StreamSubscription<bool> _networkSubscription;
  ActiveHikeSession? _hike;
  String? _key;
  DateTime? _lastAttempt;
  ActiveHikeWeatherSnapshot? _fallbackSnapshot;
  Future<void>? _restore;
  Future<void>? _pending;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  static bool _networkMayBeAvailable() =>
      NetworkReachabilityService.instance.latest.state !=
      NetworkReachabilityState.offline;

  bool get _refreshDue =>
      _lastAttempt == null ||
      _now().toUtc().difference(_lastAttempt!.toUtc()) >= refreshInterval;

  /// Computes cache key.
  static String cacheKey(ActiveHikeSession hike) =>
      '${hike.trail.trailId}:${hike.startedAt.toUtc().microsecondsSinceEpoch}';

  /// Bind the cache and request clock to one owner/hike; generation checks reject results from an older binding.
  Future<void> bind(ActiveHikeSession hike) async {
    if (_disposed) return;
    _hike = hike;
    final key = cacheKey(hike);
    if (_key == key) return;
    _key = key;
    final generation = ++_generation;
    _timer?.cancel();
    _pending = null;
    _lastAttempt = null;
    _fallbackSnapshot = null;
    value = const ActiveHikeWeatherViewState(isLoading: true);
    final restoring = _restoreCache(key, generation);
    _restore = restoring;
    await restoring;
    if (_current(generation)) await refresh();
  }

  /// Computes current.
  bool _current(int generation) => !_disposed && generation == _generation;

  /// Restores cache.
  Future<void> _restoreCache(String key, int generation) async {
    try {
      final cached = await database.loadCachedEntity(
        ownerPhoneNumber: ownerPhoneNumber,
        entityType: cacheEntityType,
        entityId: key,
        includeExpired: true,
      );
      if (!_current(generation)) return;
      ActiveHikeWeatherSnapshot? snapshot;
      if (cached != null) {
        _lastAttempt = DateTime.tryParse(
          cached.payload['lastAttemptAt'] as String? ?? '',
        );
        if (cached.payload['snapshot'] is Map) {
          snapshot = ActiveHikeWeatherSnapshot.fromPersistence(
            Map<String, dynamic>.from(cached.payload['snapshot'] as Map),
          );
        }
      }
      _fallbackSnapshot = snapshot;
      // A due refresh attempts the provider first. Retain this device copy
      // privately until that attempt fails, or use it within its request window.
      if (_refreshDue) {
        value = const ActiveHikeWeatherViewState(isLoading: true);
      } else {
        value = ActiveHikeWeatherViewState(
          snapshot: snapshot,
          error: cached?.payload['lastRefreshFailed'] == true
              ? 'Latest refresh failed.'
              : null,
          nextRefreshAt: _lastAttempt?.add(refreshInterval),
        );
      }
    } catch (_) {
      if (_current(generation)) {
        value = const ActiveHikeWeatherViewState(isLoading: true);
      }
    }
  }

  /// Refreshes.
  Future<void> refresh() async {
    if (_disposed || _hike == null) return;
    final generation = _generation;
    await _restore;
    if (!_current(generation)) return;
    if (_pending != null) return _pending;
    if (!_refreshDue) {
      _schedule();
      return;
    }
    if (!_isNetworkAvailable()) {
      // No request was attempted, so do not consume the persisted interval.
      // The shared connectivity event will retry as soon as the network returns.
      _timer?.cancel();
      value = ActiveHikeWeatherViewState(
        snapshot: _cachedFallback(value.snapshot ?? _fallbackSnapshot),
        error: 'No connection. Latest weather could not be checked.',
      );
      return;
    }
    final request = _fetch(_hike!, _key!, generation);
    _pending = request;
    await request;
    if (_current(generation)) _pending = null;
  }

  /// Preserve the current binding while refreshing and persist only results that still belong to it.
  Future<void> _fetch(
    ActiveHikeSession hike,
    String key,
    int generation,
  ) async {
    final attemptedAt = _now().toUtc();
    _lastAttempt = attemptedAt;
    final previous = value.snapshot ?? _fallbackSnapshot;
    value = ActiveHikeWeatherViewState(
      isLoading: true,
      nextRefreshAt: attemptedAt.add(refreshInterval),
    );
    // Persist the attempt too, so a failed request or page restart cannot cause
    // a rapid retry. This write never deletes the last successful readings.
    await _persist(key, previous, attemptedAt, failed: true);
    if (!_current(generation)) return;
    ActiveHikeWeatherSnapshot? snapshot = previous;
    String? error;
    try {
      final fetched = await service.fetchForHike(hike);
      if (!fetched.isCachedFallback) {
        snapshot = fetched;
      } else {
        snapshot = _cachedFallback(snapshot) ?? fetched;
        error = 'Latest refresh failed.';
      }
    } catch (_) {
      snapshot = _cachedFallback(snapshot);
      error = 'Latest refresh failed.';
    }
    if (!_current(generation)) return;
    await _persist(key, snapshot, attemptedAt, failed: error != null);
    if (!_current(generation)) return;
    _fallbackSnapshot = snapshot;
    value = ActiveHikeWeatherViewState(
      snapshot: snapshot,
      error: error,
      nextRefreshAt: attemptedAt.add(refreshInterval),
    );
    _schedule();
  }

  ActiveHikeWeatherSnapshot? _cachedFallback(
    ActiveHikeWeatherSnapshot? snapshot,
  ) => snapshot == null
      ? null
      : ActiveHikeWeatherSnapshot(
          samples: snapshot.samples,
          fetchedAt: snapshot.fetchedAt,
          isCachedFallback: true,
        );

  /// Persists.
  Future<void> _persist(
    String key,
    ActiveHikeWeatherSnapshot? snapshot,
    DateTime attemptedAt, {
    required bool failed,
  }) async {
    try {
      await database.saveCachedEntity(
        LocalCachedEntity(
          ownerPhoneNumber: ownerPhoneNumber,
          entityType: cacheEntityType,
          entityId: key,
          parentId: key,
          cachedAt: snapshot?.fetchedAt ?? attemptedAt,
          payload: {
            'lastAttemptAt': attemptedAt.toUtc().toIso8601String(),
            'lastRefreshFailed': failed,
            if (snapshot != null) 'snapshot': snapshot.toPersistence(),
          },
        ),
      );
    } catch (error) {
      debugPrint('Active hike weather cache could not be saved: $error');
    }
  }

  /// Computes schedule.
  void _schedule() {
    if (_disposed || _lastAttempt == null) return;
    _timer?.cancel();
    final delay = _lastAttempt!.add(refreshInterval).difference(_now());
    _timer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(refresh()),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_networkSubscription.cancel());
    super.dispose();
  }
}
