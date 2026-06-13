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

  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();

  Timer? _timer;
  SosTriggerLocation? _latestLocation;
  Future<SosTriggerLocation?>? _refreshFuture;
  Duration _refreshInterval = passiveSnapshotInterval;
  bool _isStarted = false;

  SosTriggerLocation? get latestLocation => _latestLocation;

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
      final location = await _deviceAlertService.getCurrentTriggerLocation(
        allowLastKnown: true,
      );
      if (location != null) {
        _latestLocation = location;
      }
    } catch (_) {
      return _latestLocation;
    } finally {
      _refreshFuture = null;
    }

    return _latestLocation;
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
}
