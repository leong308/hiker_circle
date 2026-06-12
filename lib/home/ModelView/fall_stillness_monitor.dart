import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../Model/hike_session_models.dart';

typedef FallStillnessEmergencyCallback =
    Future<void> Function(FallStillnessMonitorSnapshot snapshot);

class FallStillnessMonitor extends ChangeNotifier {
  FallStillnessMonitor({
    FallStillnessEmergencyCallback? onEmergencyReady,
    DateTime Function()? clock,
  }) : _onEmergencyReady = onEmergencyReady,
       _clock = clock ?? DateTime.now;

  static const Duration _sensorSamplingPeriod = Duration(milliseconds: 100);
  static const Duration _barometerSamplingPeriod = Duration(milliseconds: 500);
  static const Duration _stillnessVarianceWindow = Duration(seconds: 1);
  static const Duration _stillnessWarmupDuration = Duration(seconds: 1);
  static const double _seaLevelPressureHpa = 1013.25;
  static const double _gravityLowPassAlpha = 0.82;

  final FallStillnessEmergencyCallback? _onEmergencyReady;
  final DateTime Function() _clock;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;
  Timer? _countdownTimer;
  FallDetectionSettings? _settings;
  FallStillnessMonitorSnapshot _snapshot =
      const FallStillnessMonitorSnapshot.inactive();
  _FallDetectionPhase _phase = _FallDetectionPhase.normal;
  DateTime? _freeFallObservedAt;
  DateTime? _impactWindowEndsAt;
  DateTime? _bounceGraceEndsAt;
  DateTime? _stillnessStartedAt;
  DateTime? _lastCandidateAt;
  double? _latestImpactAcceleration;
  double? _lastAltitudeDropMeters;
  bool _isBackpackTrapLikely = false;
  bool _isStarted = false;
  bool _isHandlingEmergency = false;
  bool _isDisposed = false;
  double? _gravityX;
  double? _gravityY;
  double? _gravityZ;
  final List<_TimedValue> _linearAccelerationWindow = <_TimedValue>[];
  final List<_TimedValue> _altitudeHistory = <_TimedValue>[];

  FallStillnessMonitorSnapshot get snapshot => _snapshot;

  bool get isAwaitingResponse {
    return _snapshot.status == FallStillnessMonitorStatus.awaitingResponse;
  }

  Future<void> start(FallDetectionSettings settings) async {
    if (_isStarted && _settings == settings) {
      return;
    }

    await stop();
    _settings = settings;
    _isStarted = true;
    _setSnapshot(
      FallStillnessMonitorSnapshot.listening(
        settings: settings,
        message:
            'Tracking at 10 Hz for free fall, impact, and stillness patterns.',
      ),
    );

    _accelerometerSubscription =
        accelerometerEventStream(samplingPeriod: _sensorSamplingPeriod).listen(
          _handleAccelerometer,
          onError: (Object error) {
            _setSnapshot(
              FallStillnessMonitorSnapshot.unavailable(
                settings: settings,
                message: 'Accelerometer unavailable: $error',
              ),
            );
          },
          cancelOnError: true,
        );

    _barometerSubscription =
        barometerEventStream(samplingPeriod: _barometerSamplingPeriod).listen(
          _handleBarometer,
          onError: (_) {
            _barometerSubscription?.cancel();
            _barometerSubscription = null;
          },
          cancelOnError: true,
        );
  }

  Future<void> stop({bool notify = true}) async {
    _isStarted = false;
    _settings = null;
    _isHandlingEmergency = false;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    await _accelerometerSubscription?.cancel();
    await _barometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _barometerSubscription = null;
    _resetTransientState();
    if (notify) {
      _setSnapshot(const FallStillnessMonitorSnapshot.inactive());
    } else {
      _snapshot = const FallStillnessMonitorSnapshot.inactive();
    }
  }

  void cancelPendingEmergency(String reason) {
    final settings = _settings;
    if (settings == null || !isAwaitingResponse) {
      return;
    }

    _countdownTimer?.cancel();
    _countdownTimer = null;
    _resetToNormal(
      settings: settings,
      message: '$reason. Fall SOS response countdown cancelled.',
      lastCancelledAt: _clock(),
    );
  }

  void markEmergencyHandled({String? message}) {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    _isHandlingEmergency = false;
    _resetToNormal(
      settings: settings,
      message: message ?? 'Fall SOS escalated. Listening restarted.',
    );
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    final settings = _settings;
    if (!_isStarted || settings == null || _isHandlingEmergency) {
      return;
    }

    final now = _clock();
    final accelerationMagnitude = _magnitude(event.x, event.y, event.z);

    switch (_phase) {
      case _FallDetectionPhase.normal:
        _handleNormalTracking(
          settings: settings,
          now: now,
          accelerationMagnitude: accelerationMagnitude,
        );
      case _FallDetectionPhase.impactWindow:
        _handleImpactWindow(
          settings: settings,
          now: now,
          accelerationMagnitude: accelerationMagnitude,
        );
      case _FallDetectionPhase.bounceGrace:
        if (_bounceGraceEndsAt != null && !now.isBefore(_bounceGraceEndsAt!)) {
          _startStillnessVerification(settings: settings, now: now);
        }
      case _FallDetectionPhase.stillnessVerification:
        _handleStillnessVerification(
          settings: settings,
          now: now,
          event: event,
        );
      case _FallDetectionPhase.responseCountdown:
        break;
    }
  }

  void _handleNormalTracking({
    required FallDetectionSettings settings,
    required DateTime now,
    required double accelerationMagnitude,
  }) {
    if (accelerationMagnitude > settings.freeFallAccelerationThreshold) {
      return;
    }

    _phase = _FallDetectionPhase.impactWindow;
    _freeFallObservedAt = now;
    _impactWindowEndsAt = now.add(FallDetectionSettings.impactWindowDuration);
    _setSnapshot(
      FallStillnessMonitorSnapshot.impactWindow(
        settings: settings,
        detectedAt: now,
        countdownEndsAt: _impactWindowEndsAt!,
        accelerationMagnitude: accelerationMagnitude,
      ),
    );
  }

  void _handleImpactWindow({
    required FallDetectionSettings settings,
    required DateTime now,
    required double accelerationMagnitude,
  }) {
    if (_impactWindowEndsAt == null || now.isAfter(_impactWindowEndsAt!)) {
      _resetToNormal(
        settings: settings,
        message: 'Free fall ended without impact. Listening restarted.',
      );
      return;
    }

    if (accelerationMagnitude < settings.impactAccelerationThreshold) {
      return;
    }

    _phase = _FallDetectionPhase.bounceGrace;
    _lastCandidateAt = _freeFallObservedAt ?? now;
    _latestImpactAcceleration = accelerationMagnitude;
    _lastAltitudeDropMeters = _altitudeDropBefore(now);
    _isBackpackTrapLikely =
        _lastAltitudeDropMeters != null &&
        _lastAltitudeDropMeters! < settings.altitudeDropThresholdMeters;
    _bounceGraceEndsAt = now.add(
      FallDetectionSettings.postImpactBounceDuration,
    );
    _setSnapshot(
      FallStillnessMonitorSnapshot.impactDetected(
        settings: settings,
        detectedAt: _lastCandidateAt ?? now,
        countdownEndsAt: _bounceGraceEndsAt!,
        accelerationMagnitude: accelerationMagnitude,
        altitudeDropMeters: _lastAltitudeDropMeters,
        isBackpackTrapLikely: _isBackpackTrapLikely,
      ),
    );
  }

  void _startStillnessVerification({
    required FallDetectionSettings settings,
    required DateTime now,
  }) {
    _phase = _FallDetectionPhase.stillnessVerification;
    _stillnessStartedAt = now;
    _resetLinearAccelerationFilter();
    final stillnessDuration = _stillnessDurationFor(settings);
    final stillnessEndsAt = now.add(stillnessDuration);
    _setSnapshot(
      FallStillnessMonitorSnapshot.verifyingStillness(
        settings: settings,
        detectedAt: _lastCandidateAt ?? now,
        countdownEndsAt: stillnessEndsAt,
        secondsRemaining: stillnessDuration.inSeconds,
        accelerationMagnitude: _latestImpactAcceleration,
        altitudeDropMeters: _lastAltitudeDropMeters,
        isBackpackTrapLikely: _isBackpackTrapLikely,
      ),
    );
    _startCountdownTimer();
  }

  void _handleStillnessVerification({
    required FallDetectionSettings settings,
    required DateTime now,
    required AccelerometerEvent event,
  }) {
    final current = _snapshot;
    if (current.countdownEndsAt == null) {
      _resetToNormal(settings: settings);
      return;
    }

    final linearMagnitude = _linearAccelerationMagnitude(event);
    _linearAccelerationWindow.add(_TimedValue(now, linearMagnitude));
    _linearAccelerationWindow.removeWhere(
      (sample) => now.difference(sample.recordedAt) > _stillnessVarianceWindow,
    );

    final elapsed = _stillnessStartedAt == null
        ? Duration.zero
        : now.difference(_stillnessStartedAt!);
    final variance = _variance(_linearAccelerationWindow);
    final movedSignificantly =
        linearMagnitude > settings.significantLinearMovementThreshold;
    final varianceExceeded =
        elapsed >= _stillnessWarmupDuration &&
        variance > settings.stillnessVarianceThreshold;

    if (movedSignificantly || varianceExceeded) {
      _resetToNormal(
        settings: settings,
        message: 'Movement detected after impact. Listening restarted.',
        lastCancelledAt: now,
      );
      return;
    }

    if (!now.isBefore(current.countdownEndsAt!)) {
      _startResponseCountdown(settings: settings, now: now);
    }
  }

  void _startResponseCountdown({
    required FallDetectionSettings settings,
    required DateTime now,
  }) {
    _phase = _FallDetectionPhase.responseCountdown;
    final responseEndsAt = now.add(settings.stillnessDuration);
    _setSnapshot(
      FallStillnessMonitorSnapshot.awaitingResponse(
        settings: settings,
        detectedAt: _lastCandidateAt ?? now,
        countdownEndsAt: responseEndsAt,
        secondsRemaining: settings.stillnessDuration.inSeconds,
        accelerationMagnitude: _latestImpactAcceleration,
        altitudeDropMeters: _lastAltitudeDropMeters,
        isBackpackTrapLikely: _isBackpackTrapLikely,
      ),
    );
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    final settings = _settings;
    final current = _snapshot;
    if (settings == null || current.countdownEndsAt == null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }

    final remaining = current.countdownEndsAt!.difference(_clock()).inSeconds;
    if (remaining > 0) {
      _setSnapshot(current.copyWith(secondsRemaining: remaining));
      return;
    }

    if (_phase == _FallDetectionPhase.stillnessVerification) {
      _startResponseCountdown(settings: settings, now: _clock());
      return;
    }

    if (_phase == _FallDetectionPhase.responseCountdown) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      unawaited(_confirmEmergency(settings));
      return;
    }

    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _confirmEmergency(FallDetectionSettings settings) async {
    if (_isHandlingEmergency) {
      return;
    }

    _isHandlingEmergency = true;
    final triggeredAt = _clock();
    _setSnapshot(
      FallStillnessMonitorSnapshot.triggering(
        settings: settings,
        detectedAt: _lastCandidateAt ?? triggeredAt,
        triggeredAt: triggeredAt,
        accelerationMagnitude: _latestImpactAcceleration,
        altitudeDropMeters: _lastAltitudeDropMeters,
        isBackpackTrapLikely: _isBackpackTrapLikely,
        message: 'Response countdown ended. Sending Fall SOS.',
      ),
    );

    try {
      await _onEmergencyReady?.call(_snapshot);
    } finally {
      if (_isStarted) {
        markEmergencyHandled();
      }
    }
  }

  void _handleBarometer(BarometerEvent event) {
    final now = _clock();
    final altitude = _altitudeFromPressure(event.pressure);
    _altitudeHistory.add(_TimedValue(now, altitude));
    _altitudeHistory.removeWhere(
      (sample) =>
          now.difference(sample.recordedAt) > const Duration(seconds: 5),
    );
  }

  double? _altitudeDropBefore(DateTime impactAt) {
    final recent = _altitudeHistory
        .where(
          (sample) =>
              !sample.recordedAt.isAfter(impactAt) &&
              impactAt.difference(sample.recordedAt) <=
                  const Duration(seconds: 3),
        )
        .toList();
    if (recent.length < 2) {
      return null;
    }

    final highestBeforeImpact = recent
        .map((sample) => sample.value)
        .reduce(math.max);
    final latestAltitude = recent.last.value;
    return math.max(0, highestBeforeImpact - latestAltitude);
  }

  Duration _stillnessDurationFor(FallDetectionSettings settings) {
    if (_isBackpackTrapLikely) {
      return FallDetectionSettings.backpackTrapStillnessDuration;
    }
    return FallDetectionSettings.stillnessVerificationDuration;
  }

  double _linearAccelerationMagnitude(AccelerometerEvent event) {
    if (_gravityX == null || _gravityY == null || _gravityZ == null) {
      _gravityX = event.x;
      _gravityY = event.y;
      _gravityZ = event.z;
      return 0;
    }

    _gravityX =
        _gravityLowPassAlpha * _gravityX! +
        (1 - _gravityLowPassAlpha) * event.x;
    _gravityY =
        _gravityLowPassAlpha * _gravityY! +
        (1 - _gravityLowPassAlpha) * event.y;
    _gravityZ =
        _gravityLowPassAlpha * _gravityZ! +
        (1 - _gravityLowPassAlpha) * event.z;

    return _magnitude(
      event.x - _gravityX!,
      event.y - _gravityY!,
      event.z - _gravityZ!,
    );
  }

  double _variance(List<_TimedValue> samples) {
    if (samples.length < 2) {
      return 0;
    }

    final mean =
        samples.fold<double>(0, (sum, sample) => sum + sample.value) /
        samples.length;
    return samples.fold<double>(0, (sum, sample) {
          final delta = sample.value - mean;
          return sum + delta * delta;
        }) /
        samples.length;
  }

  double _altitudeFromPressure(double pressureHpa) {
    return 44330.0 *
        (1 - math.pow(pressureHpa / _seaLevelPressureHpa, 1 / 5.255))
            .toDouble();
  }

  void _resetLinearAccelerationFilter() {
    _gravityX = null;
    _gravityY = null;
    _gravityZ = null;
    _linearAccelerationWindow.clear();
  }

  void _resetTransientState() {
    _phase = _FallDetectionPhase.normal;
    _freeFallObservedAt = null;
    _impactWindowEndsAt = null;
    _bounceGraceEndsAt = null;
    _stillnessStartedAt = null;
    _lastCandidateAt = null;
    _latestImpactAcceleration = null;
    _lastAltitudeDropMeters = null;
    _isBackpackTrapLikely = false;
    _resetLinearAccelerationFilter();
  }

  void _resetToNormal({
    required FallDetectionSettings settings,
    String? message,
    DateTime? lastCancelledAt,
  }) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _resetTransientState();
    _setSnapshot(
      FallStillnessMonitorSnapshot.listening(
        settings: settings,
        message: message ?? 'Listening for free fall and impact.',
        lastCancelledAt: lastCancelledAt,
      ),
    );
  }

  void _setSnapshot(FallStillnessMonitorSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  double _magnitude(double x, double y, double z) {
    return math.sqrt(x * x + y * y + z * z);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    unawaited(_accelerometerSubscription?.cancel());
    unawaited(_barometerSubscription?.cancel());
    super.dispose();
  }
}

enum _FallDetectionPhase {
  normal,
  impactWindow,
  bounceGrace,
  stillnessVerification,
  responseCountdown,
}

class _TimedValue {
  const _TimedValue(this.recordedAt, this.value);

  final DateTime recordedAt;
  final double value;
}

enum FallStillnessMonitorStatus {
  inactive,
  listening,
  impactWindow,
  impactDetected,
  verifyingStillness,
  awaitingResponse,
  triggering,
  unavailable;

  String get label {
    switch (this) {
      case FallStillnessMonitorStatus.inactive:
        return 'Inactive';
      case FallStillnessMonitorStatus.listening:
        return 'Listening';
      case FallStillnessMonitorStatus.impactWindow:
        return 'Free fall detected';
      case FallStillnessMonitorStatus.impactDetected:
        return 'Impact detected';
      case FallStillnessMonitorStatus.verifyingStillness:
        return 'Checking stillness';
      case FallStillnessMonitorStatus.awaitingResponse:
        return 'Respond now';
      case FallStillnessMonitorStatus.triggering:
        return 'Triggering SOS';
      case FallStillnessMonitorStatus.unavailable:
        return 'Unavailable';
    }
  }
}

class FallStillnessMonitorSnapshot {
  const FallStillnessMonitorSnapshot({
    required this.status,
    this.settings,
    this.detectedAt,
    this.countdownEndsAt,
    this.triggeredAt,
    this.lastCancelledAt,
    this.secondsRemaining,
    this.accelerationMagnitude,
    this.altitudeDropMeters,
    this.isBackpackTrapLikely = false,
    this.message,
  });

  const FallStillnessMonitorSnapshot.inactive()
    : this(status: FallStillnessMonitorStatus.inactive);

  factory FallStillnessMonitorSnapshot.listening({
    required FallDetectionSettings settings,
    String? message,
    DateTime? lastCancelledAt,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.listening,
      settings: settings,
      message: message,
      lastCancelledAt: lastCancelledAt,
    );
  }

  factory FallStillnessMonitorSnapshot.impactWindow({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime countdownEndsAt,
    required double accelerationMagnitude,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.impactWindow,
      settings: settings,
      detectedAt: detectedAt,
      countdownEndsAt: countdownEndsAt,
      accelerationMagnitude: accelerationMagnitude,
      message: 'Free fall detected. Watching for impact for 500 ms.',
    );
  }

  factory FallStillnessMonitorSnapshot.impactDetected({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime countdownEndsAt,
    required double accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.impactDetected,
      settings: settings,
      detectedAt: detectedAt,
      countdownEndsAt: countdownEndsAt,
      accelerationMagnitude: accelerationMagnitude,
      altitudeDropMeters: altitudeDropMeters,
      isBackpackTrapLikely: isBackpackTrapLikely,
      message: 'Impact detected. Waiting for phone bounce to settle.',
    );
  }

  factory FallStillnessMonitorSnapshot.verifyingStillness({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime countdownEndsAt,
    required int secondsRemaining,
    required double? accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.verifyingStillness,
      settings: settings,
      detectedAt: detectedAt,
      countdownEndsAt: countdownEndsAt,
      secondsRemaining: secondsRemaining,
      accelerationMagnitude: accelerationMagnitude,
      altitudeDropMeters: altitudeDropMeters,
      isBackpackTrapLikely: isBackpackTrapLikely,
      message: isBackpackTrapLikely
          ? 'Impact had little altitude drop. Extending stillness check.'
          : 'Impact confirmed. Verifying stillness before alerting.',
    );
  }

  factory FallStillnessMonitorSnapshot.awaitingResponse({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime countdownEndsAt,
    required int secondsRemaining,
    required double? accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.awaitingResponse,
      settings: settings,
      detectedAt: detectedAt,
      countdownEndsAt: countdownEndsAt,
      secondsRemaining: secondsRemaining,
      accelerationMagnitude: accelerationMagnitude,
      altitudeDropMeters: altitudeDropMeters,
      isBackpackTrapLikely: isBackpackTrapLikely,
      message: 'Severe fall suspected. Cancel now if you are okay.',
    );
  }

  factory FallStillnessMonitorSnapshot.triggering({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime triggeredAt,
    required double? accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
    String? message,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.triggering,
      settings: settings,
      detectedAt: detectedAt,
      triggeredAt: triggeredAt,
      accelerationMagnitude: accelerationMagnitude,
      altitudeDropMeters: altitudeDropMeters,
      isBackpackTrapLikely: isBackpackTrapLikely,
      message: message,
    );
  }

  factory FallStillnessMonitorSnapshot.unavailable({
    required FallDetectionSettings settings,
    required String message,
  }) {
    return FallStillnessMonitorSnapshot(
      status: FallStillnessMonitorStatus.unavailable,
      settings: settings,
      message: message,
    );
  }

  final FallStillnessMonitorStatus status;
  final FallDetectionSettings? settings;
  final DateTime? detectedAt;
  final DateTime? countdownEndsAt;
  final DateTime? triggeredAt;
  final DateTime? lastCancelledAt;
  final int? secondsRemaining;
  final double? accelerationMagnitude;
  final double? altitudeDropMeters;
  final bool isBackpackTrapLikely;
  final String? message;

  FallStillnessMonitorSnapshot copyWith({
    FallStillnessMonitorStatus? status,
    FallDetectionSettings? settings,
    DateTime? detectedAt,
    DateTime? countdownEndsAt,
    DateTime? triggeredAt,
    DateTime? lastCancelledAt,
    int? secondsRemaining,
    double? accelerationMagnitude,
    double? altitudeDropMeters,
    bool? isBackpackTrapLikely,
    String? message,
  }) {
    return FallStillnessMonitorSnapshot(
      status: status ?? this.status,
      settings: settings ?? this.settings,
      detectedAt: detectedAt ?? this.detectedAt,
      countdownEndsAt: countdownEndsAt ?? this.countdownEndsAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      lastCancelledAt: lastCancelledAt ?? this.lastCancelledAt,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      accelerationMagnitude:
          accelerationMagnitude ?? this.accelerationMagnitude,
      altitudeDropMeters: altitudeDropMeters ?? this.altitudeDropMeters,
      isBackpackTrapLikely: isBackpackTrapLikely ?? this.isBackpackTrapLikely,
      message: message ?? this.message,
    );
  }
}
