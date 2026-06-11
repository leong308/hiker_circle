import 'dart:async';

import 'package:flutter/widgets.dart';

import '../Model/sos_models.dart';
import 'sos_device_alert_service.dart';

class LocationSnapshotService with WidgetsBindingObserver {
  LocationSnapshotService._();

  static final LocationSnapshotService instance = LocationSnapshotService._();
  static const Duration snapshotInterval = Duration(seconds: 30);

  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();

  Timer? _timer;
  SosTriggerLocation? _latestLocation;
  Future<SosTriggerLocation?>? _refreshFuture;
  bool _isStarted = false;

  SosTriggerLocation? get latestLocation => _latestLocation;

  Future<void> start() async {
    if (_isStarted) {
      return;
    }

    _isStarted = true;
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
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _startTimer();
        unawaited(refresh());
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
    }
  }

  void _startTimer() {
    if (_timer?.isActive == true) {
      return;
    }

    _timer = Timer.periodic(snapshotInterval, (_) {
      unawaited(refresh());
    });
  }
}
