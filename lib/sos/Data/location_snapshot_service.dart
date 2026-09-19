import 'dart:async';

import 'package:flutter/widgets.dart';

import '../Model/sos_models.dart';
import 'sos_device_alert_service.dart';

class LocationSnapshotService with WidgetsBindingObserver {
  LocationSnapshotService._();

  static final LocationSnapshotService instance = LocationSnapshotService._();
  static const Duration passiveSnapshotInterval = Duration(minutes: 2);
  static const Duration liveSnapshotInterval = Duration(seconds: 30);
  static const Duration snapshotInterval = liveSnapshotInterval;
  static const Duration maximumEmergencySnapshotAge = Duration(minutes: 5);

  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();

  Timer? _timer;
  SosTriggerLocation? _latestLocation;
  Future<SosTriggerLocation?>? _refreshFuture;
  Duration _refreshInterval = passiveSnapshotInterval;
  bool _isStarted = false;

  SosTriggerLocation? get latestLocation => _freshLocation(_latestLocation);

  Map<String, Object?> get debugSnapshot => {
    'storageType': 'In-memory location snapshot service',
    'persistence': 'Cleared when the service stops or the process exits',
    'isStarted': _isStarted,
    'timerActive': _timer?.isActive == true,
    'refreshInProgress': _refreshFuture != null,
    'refreshIntervalSeconds': _refreshInterval.inSeconds,
    'latestLocation': _latestLocation?.toFirestore(),
    'latestLocationFresh': latestLocation != null,
    'maximumEmergencySnapshotAgeSeconds': maximumEmergencySnapshotAge.inSeconds,
  };

  Future<void> start({Duration interval = passiveSnapshotInterval}) async {
    final normalizedInterval = _normalizeInterval(interval);
    if (_isStarted) {
      setRefreshInterval(normalizedInterval);
      return;
    }

    _isStarted = true;
    _refreshInterval = normalizedInterval;
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    await refresh();
  }

  void stop() {
    if (!_isStarted) {
      return;
    }

    _isStarted = false;
    _timer?.cancel();
    _timer = null;
    _latestLocation = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void setRefreshInterval(Duration interval) {
    final normalizedInterval = _normalizeInterval(interval);
    if (_refreshInterval == normalizedInterval) {
      return;
    }

    _refreshInterval = normalizedInterval;
    if (!_isStarted) {
      return;
    }

    _timer?.cancel();
    _timer = null;
    _startTimer();
  }

  Future<SosTriggerLocation?> refresh() async {
    return _refreshFuture ??= _refreshNow();
  }

  Future<SosTriggerLocation?> _refreshNow() async {
    try {
      final location = await _deviceAlertService
          .getCurrentTriggerLocation(
            allowLastKnown: true,
            requirePrecise: _refreshInterval <= const Duration(seconds: 5),
          )
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => _freshLocation(_latestLocation),
          );
      if (_isValidLocation(location) && _isNewerThanCached(location!)) {
        _latestLocation = location;
      }
    } catch (_) {
      return latestLocation;
    } finally {
      _refreshFuture = null;
    }

    return latestLocation;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isStarted) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _startTimer();
        unawaited(refresh());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Keep the schedule installed while mobile background-location modes
        // are active. The OS may throttle Dart timers while suspended, but
        // cancelling here guaranteed that SOS/live-hike snapshots went stale.
        _startTimer();
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
    }
  }

  void _startTimer() {
    if (_timer?.isActive == true) {
      return;
    }

    _timer = Timer.periodic(_refreshInterval, (_) {
      unawaited(refresh());
    });
  }

  Duration _normalizeInterval(Duration interval) {
    if (interval < liveSnapshotInterval) {
      return liveSnapshotInterval;
    }
    return interval;
  }

  bool _isNewerThanCached(SosTriggerLocation location) {
    final cachedAt = _latestLocation?.capturedAt;
    final capturedAt = location.capturedAt;
    return cachedAt == null ||
        (capturedAt != null && capturedAt.isAfter(cachedAt));
  }

  bool _isValidLocation(SosTriggerLocation? location) {
    if (location == null ||
        !location.latitude.isFinite ||
        !location.longitude.isFinite ||
        location.latitude < -90 ||
        location.latitude > 90 ||
        location.longitude < -180 ||
        location.longitude > 180) {
      return false;
    }
    return location.capturedAt != null;
  }

  SosTriggerLocation? _freshLocation(SosTriggerLocation? location) {
    if (!_isValidLocation(location)) {
      return null;
    }
    final capturedAt = location!.capturedAt!.toUtc();
    final now = DateTime.now().toUtc();
    if (capturedAt.isAfter(now.add(const Duration(minutes: 2))) ||
        now.difference(capturedAt) > maximumEmergencySnapshotAge) {
      return null;
    }
    return location;
  }
}
