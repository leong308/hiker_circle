import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../Model/hike_session_models.dart';
import 'active_hike_weather_service.dart';

class ActiveHikeWeatherViewState {
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
  ActiveHikeWeatherController({
    required this.database,
    required this.ownerPhoneNumber,
    ActiveHikeWeatherService? service,
    DateTime Function()? now,
  }) : service = service ?? const ActiveHikeWeatherService(),
       _now = now ?? DateTime.now,
       super(const ActiveHikeWeatherViewState());

  static const refreshInterval = Duration(minutes: 15);
  static const cacheEntityType = 'active_hike_weather';
  final LocalSessionDatabase database;
  final String ownerPhoneNumber;
  final ActiveHikeWeatherService service;
  final DateTime Function() _now;
  ActiveHikeSession? _hike;
  String? _key;
  DateTime? _lastAttempt;
  Future<void>? _restore;
  Future<void>? _pending;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  static String cacheKey(ActiveHikeSession hike) =>
      '${hike.trail.trailId}:${hike.startedAt.toUtc().microsecondsSinceEpoch}';

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
    value = const ActiveHikeWeatherViewState(isLoading: true);
    final restoring = _restoreCache(key, generation);
    _restore = restoring;
    await restoring;
    if (_current(generation)) await refresh();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

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
      value = ActiveHikeWeatherViewState(
        snapshot: snapshot,
        error: cached?.payload['lastRefreshFailed'] == true
            ? 'Latest refresh failed.'
            : null,
        nextRefreshAt: _lastAttempt?.add(refreshInterval),
      );
    } catch (_) {
      if (_current(generation)) value = const ActiveHikeWeatherViewState();
    }
  }

  Future<void> refresh() async {
    if (_disposed || _hike == null) return;
    final generation = _generation;
    await _restore;
    if (!_current(generation)) return;
    if (_pending != null) return _pending;
    final lastAttempt = _lastAttempt;
    if (lastAttempt != null &&
        _now().difference(lastAttempt) < refreshInterval) {
      _schedule();
      return;
    }
    final request = _fetch(_hike!, _key!, generation);
    _pending = request;
    await request;
    if (_current(generation)) _pending = null;
  }

  Future<void> _fetch(
    ActiveHikeSession hike,
    String key,
    int generation,
  ) async {
    final attemptedAt = _now().toUtc();
    _lastAttempt = attemptedAt;
    final previous = value.snapshot;
    final previousFailed = value.error != null;
    value = ActiveHikeWeatherViewState(
      snapshot: previous,
      isLoading: true,
      nextRefreshAt: attemptedAt.add(refreshInterval),
    );
    // Persist the attempt too, so a failed request or page restart cannot cause
    // a rapid retry. This write never deletes the last successful readings.
    await _persist(key, previous, attemptedAt, failed: previousFailed);
    if (!_current(generation)) return;
    ActiveHikeWeatherSnapshot? snapshot = previous;
    String? error;
    try {
      final fetched = await service.fetchForHike(hike);
      if (!fetched.isCachedFallback) {
        snapshot = fetched;
      } else {
        snapshot ??= fetched;
        error = 'Latest refresh failed.';
      }
    } catch (_) {
      error = 'Latest refresh failed.';
    }
    await _persist(key, snapshot, attemptedAt, failed: error != null);
    if (!_current(generation)) return;
    value = ActiveHikeWeatherViewState(
      snapshot: snapshot,
      error: error,
      nextRefreshAt: attemptedAt.add(refreshInterval),
    );
    _schedule();
  }

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

  void _schedule() {
    if (_disposed || _lastAttempt == null) return;
    _timer?.cancel();
    final delay = _lastAttempt!.add(refreshInterval).difference(_now());
    _timer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
