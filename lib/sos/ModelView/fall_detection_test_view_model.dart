import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../app/Data/app_settings_controller.dart';
import '../../home/Data/location_update_interval_controller.dart';
import '../../home/Model/fall_detection_test_policy.dart';

/// Describe the sensor test without depending on a widget or navigator.
enum FallDetectionTestPhase {
  idle,
  running,
  passed,
  stopped,
  timedOut,
  unavailable,
}

/// Own the sensor subscription, fixed target and test lifecycle.
class FallDetectionTestViewModel extends ChangeNotifier {
  /// Creates fall detection test view model.
  FallDetectionTestViewModel({
    double? Function()? sensitivity,
    Stream<AccelerometerEvent>? Function()? events,
    LocationUpdateIntervalController? intervals,
  }) : _sensitivity = sensitivity,
       _events = events,
       _intervals = intervals ?? LocationUpdateIntervalController.instance {
    _intervals.addListener(_activeHikeChanged);
  }

  final double? Function()? _sensitivity;
  final Stream<AccelerometerEvent>? Function()? _events;
  final LocationUpdateIntervalController _intervals;
  StreamSubscription<AccelerometerEvent>? _subscription;
  Timer? _timeout;
  int _generation = 0;
  bool _disposed = false;
  FallDetectionTestPhase _phase = FallDetectionTestPhase.idle;
  double _acceleration = 0;
  double _targetAcceleration = 1;

  /// Returns phase.
  FallDetectionTestPhase get phase => _phase;

  /// Returns active.
  bool get active => _phase == FallDetectionTestPhase.running;

  /// Returns passed.
  bool get passed => _phase == FallDetectionTestPhase.passed;

  /// Returns has active hike.
  bool get hasActiveHike => _intervals.hasActiveHike;

  /// Returns progress.
  double get progress => (_acceleration / _targetAcceleration).clamp(0, 1);

  /// Returns selected sensitivity.
  double get _selectedSensitivity {
    final value =
        _sensitivity?.call() ??
        AppSettingsController.instance.fallSensorSensitivity;
    return value.isFinite ? value.clamp(1, 10) : 5;
  }

  /// Apply a state change before publishing it to the view.
  void _update(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  /// Stop an isolated test when real hike monitoring takes ownership.
  void _activeHikeChanged() {
    if (_disposed) return;
    _update(() {
      if (_intervals.hasActiveHike && active) {
        _stop(FallDetectionTestPhase.stopped);
      }
    });
  }

  /// Stop background tests without restarting them on resume.
  void setForeground(bool foreground) {
    if (!foreground && active && !_disposed) {
      _update(() => _stop(FallDetectionTestPhase.stopped));
    }
  }

  /// Cancel this attempt and invalidate any late sensor events.
  void _stop(FallDetectionTestPhase phase) {
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    _timeout?.cancel();
    _timeout = null;
    _phase = phase;
  }

  /// Stop the running attempt at the user's request.
  void stop() => _update(() => _stop(FallDetectionTestPhase.stopped));

  /// Capture the selected sensitivity and start the same twenty-second test.
  void start() {
    if (_intervals.hasActiveHike || active) return;
    _stop(FallDetectionTestPhase.idle);
    final generation = _generation;
    _update(() {
      _targetAcceleration = fallTestImpactThreshold(_selectedSensitivity);
      _acceleration = 0;
      _phase = FallDetectionTestPhase.running;
    });
    try {
      final events =
          _events?.call() ??
          accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 100),
          );
      final subscription = events.listen(
        (event) {
          if (_disposed || !active || generation != _generation) return;
          final magnitude = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          if (!magnitude.isFinite) return;
          _update(() {
            _acceleration = magnitude;
            if (magnitude >= _targetAcceleration) {
              _stop(FallDetectionTestPhase.passed);
            }
          });
        },
        onError: (Object _) {
          if (!_disposed && active && generation == _generation) {
            _update(() => _stop(FallDetectionTestPhase.unavailable));
          }
        },
        onDone: () {
          if (!_disposed && active && generation == _generation) {
            _update(() => _stop(FallDetectionTestPhase.unavailable));
          }
        },
        cancelOnError: true,
      );
      if (!active || generation != _generation) {
        unawaited(subscription.cancel());
        return;
      }
      _subscription = subscription;
      _timeout = Timer(const Duration(seconds: 20), () {
        if (!_disposed && active && generation == _generation) {
          _update(() => _stop(FallDetectionTestPhase.timedOut));
        }
      });
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _update(() => _stop(FallDetectionTestPhase.unavailable));
      }
    }
  }

  /// Keep the existing user-facing messages for every test outcome.
  String get status {
    if (_intervals.hasActiveHike) {
      return 'Finish your current hike before testing sensors. Live fall detection remains active.';
    }
    return switch (_phase) {
      FallDetectionTestPhase.idle =>
        'Uses your selected sensitivity. Hold your phone securely and move it gently. Never drop or strike it.',
      FallDetectionTestPhase.running =>
        'Watch the live meter as you move your phone. The test stops when it reaches the target.',
      FallDetectionTestPhase.passed =>
        'Test passed. Your selected sensitivity detected the movement.',
      FallDetectionTestPhase.stopped =>
        'Test stopped. You can try again when you are ready.',
      FallDetectionTestPhase.timedOut =>
        'Test finished. The target was not reached. You can try again.',
      FallDetectionTestPhase.unavailable =>
        'Motion readings are unavailable. Check motion access and try again.',
    };
  }

  /// Release listeners, readings and the timeout when the owner closes.
  @override
  void dispose() {
    _intervals.removeListener(_activeHikeChanged);
    _stop(FallDetectionTestPhase.stopped);
    _disposed = true;
    super.dispose();
  }
}
