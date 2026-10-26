// FallStillnessMonitor combines motion sensors, response countdowns and emergency readiness state.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../Model/hike_session_models.dart';

typedef FallStillnessEmergencyCallback =
    Future<void> Function(FallStillnessMonitorSnapshot snapshot);

/// Represents fall stillness monitor.
class FallStillnessMonitor extends ChangeNotifier {
  /// Creates fall stillness monitor.
  FallStillnessMonitor({
    FallStillnessEmergencyCallback? onEmergencyReady,
    DateTime Function()? clock,
  }) : _onEmergencyReady = onEmergencyReady,
       _clock = clock ?? DateTime.now;

  static const Duration _sensorSamplingPeriod = Duration(milliseconds: 100);
  static const Duration _barometerSamplingPeriod = Duration(milliseconds: 500);
  static const double _seaLevelPressureHpa = 1013.25;

  final FallStillnessEmergencyCallback? _onEmergencyReady;
  final DateTime Function() _clock;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;
  Timer? _countdownTimer;
  FallDetectionSettings? _settings;
  FallStillnessMonitorSnapshot _snapshot =
      const FallStillnessMonitorSnapshot.inactive();
  _FallDetectionPhase _phase = _FallDetectionPhase.normal;
  DateTime? _freeFallObservedAt;
  DateTime? _impactWindowEndsAt;
  DateTime? _bounceGraceEndsAt;
  DateTime? _gyroscopeQuietStartedAt;
  DateTime? _gyroscopeMonitoringEndsAt;
  DateTime? _lastCandidateAt;
  double? _latestImpactAcceleration;
  double? _lastAltitudeDropMeters;
  bool _isBackpackTrapLikely = false;
  bool _isStationaryLocationWatch = false;
  bool _isStarted = false;
  bool _isHandlingEmergency = false;
  bool _isDisposed = false;
  final List<_TimedValue> _altitudeHistory = <_TimedValue>[];

  /// Returns snapshot.
  FallStillnessMonitorSnapshot get snapshot => _snapshot;

  /// Returns is awaiting response.
  bool get isAwaitingResponse {
    return _snapshot.status == FallStillnessMonitorStatus.awaitingResponse;
  }

  /// Restart the sensor subscriptions with one active detection configuration.
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
            'Tracking at 10 Hz for free fall, direct impact, and stillness patterns.',
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

    _gyroscopeSubscription =
        gyroscopeEventStream(samplingPeriod: _sensorSamplingPeriod).listen(
          _handleGyroscope,
          onError: (_) {
            _gyroscopeSubscription?.cancel();
            _gyroscopeSubscription = null;
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

  /// Stops.
  Future<void> stop({bool notify = true}) async {
    _isStarted = false;
    _settings = null;
    _isHandlingEmergency = false;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _barometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _barometerSubscription = null;
    _resetTransientState();
    if (notify) {
      _setSnapshot(const FallStillnessMonitorSnapshot.inactive());
    } else {
      _snapshot = const FallStillnessMonitorSnapshot.inactive();
    }
  }

  /// Cancels pending emergency.
  void cancelPendingEmergency(String reason) {
    final settings = _settings;
    if (settings == null || !isAwaitingResponse) {
      return;
    }

    _countdownTimer?.cancel();
    _countdownTimer = null;
    final alertName = _snapshot.isProlongedStillnessDetection
        ? 'Prolonged-stillness SOS'
        : 'Fall SOS';
    _resetToNormal(
      settings: settings,
      message: '$reason. $alertName response countdown cancelled.',
      lastCancelledAt: _clock(),
    );
  }

  /// Begins stationary location watch.
  void beginStationaryLocationWatch(FallDetectionSettings settings) {
    if (!_isStarted || _isHandlingEmergency) {
      return;
    }
    _settings = settings;
    final now = _clock();
    _phase = _FallDetectionPhase.stillnessVerification;
    _isStationaryLocationWatch = true;
    _lastCandidateAt = now;
    _latestImpactAcceleration = null;
    _lastAltitudeDropMeters = null;
    _isBackpackTrapLikely = false;
    _gyroscopeQuietStartedAt = null;
    _gyroscopeMonitoringEndsAt = null;
    _setSnapshot(
      FallStillnessMonitorSnapshot.verifyingStillness(
        settings: settings,
        detectedAt: now,
        countdownEndsAt: now.add(const Duration(minutes: 1)),
        secondsRemaining: 60,
        accelerationMagnitude: null,
        altitudeDropMeters: null,
        isBackpackTrapLikely: false,
        isProlongedStillnessDetection: true,
        message:
            'Location has not changed for ${settings.longestRestDurationLabel}. Checking phone movement with gyroscope.',
      ),
    );
    _startCountdownTimer();
  }

  /// Cancels stationary location watch.
  void cancelStationaryLocationWatch(String reason) {
    final settings = _settings;
    if (settings == null ||
        !_isStationaryLocationWatch ||
        _phase != _FallDetectionPhase.stillnessVerification) {
      return;
    }
    _resetToNormal(
      settings: settings,
      message: '$reason. Stationary movement check ended.',
      lastCancelledAt: _clock(),
    );
  }

  /// Marks emergency handled.
  void markEmergencyHandled({String? message}) {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    _isHandlingEmergency = false;
    final alertName = _snapshot.isProlongedStillnessDetection
        ? 'Prolonged-stillness SOS'
        : 'Fall SOS';
    _resetToNormal(
      settings: settings,
      message: message ?? '$alertName escalated. Listening restarted.',
    );
  }

  /// Handles accelerometer.
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
        break;
      case _FallDetectionPhase.responseCountdown:
        break;
    }
  }

  /// Handles gyroscope.
  void _handleGyroscope(GyroscopeEvent event) {
    final settings = _settings;
    if (!_isStarted ||
        settings == null ||
        _isHandlingEmergency ||
        _phase != _FallDetectionPhase.stillnessVerification) {
      return;
    }

    final now = _clock();
    final current = _snapshot;
    final axisMoved =
        event.x.abs() > 0.05 || event.y.abs() > 0.05 || event.z.abs() > 0.05;

    if (axisMoved) {
      _gyroscopeQuietStartedAt = null;
      final monitoringEndsAt = _gyroscopeMonitoringEndsAt;
      if (!_isStationaryLocationWatch &&
          monitoringEndsAt != null &&
          !now.isBefore(monitoringEndsAt)) {
        _resetToNormal(
          settings: settings,
          message:
              'Gyroscope movement continued for 1 minute. Fall alert cancelled.',
          lastCancelledAt: now,
        );
        return;
      }
      if (current.countdownEndsAt != null) {
        _setSnapshot(
          current.copyWith(
            secondsRemaining: math.max(
              0,
              current.countdownEndsAt!.difference(now).inSeconds,
            ),
            message:
                'Phone is still moving. Monitoring gyroscope before starting SOS countdown.',
          ),
        );
      }
      return;
    }

    _gyroscopeQuietStartedAt ??= now;
    final quietDuration = now.difference(_gyroscopeQuietStartedAt!);
    final secondsUntilResponse =
        FallDetectionSettings.stillnessVerificationDuration.inSeconds -
        quietDuration.inSeconds;
    _setSnapshot(
      current.copyWith(
        secondsRemaining: math.max(0, secondsUntilResponse),
        message: _isStationaryLocationWatch
            ? 'No phone movement detected. The SOS response timer starts if stillness continues.'
            : 'Phone is still after the impact. The SOS response timer starts if stillness continues.',
      ),
    );
    if (quietDuration >= FallDetectionSettings.stillnessVerificationDuration) {
      _startResponseCountdown(settings: settings, now: now);
    }
  }

  /// Distinguish direct impact from free fall before opening the impact or bounce-grace phase.
  void _handleNormalTracking({
    required FallDetectionSettings settings,
    required DateTime now,
    required double accelerationMagnitude,
  }) {
    if (accelerationMagnitude >= settings.directImpactAccelerationThreshold) {
      _phase = _FallDetectionPhase.bounceGrace;
      _lastCandidateAt = now;
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
          detectedAt: now,
          countdownEndsAt: _bounceGraceEndsAt!,
          accelerationMagnitude: accelerationMagnitude,
          altitudeDropMeters: _lastAltitudeDropMeters,
          isBackpackTrapLikely: _isBackpackTrapLikely,
        ),
      );
      return;
    }

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

  /// Handles impact window.
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

  /// Require the post-impact gyroscope stillness window before starting the response countdown.
  void _startStillnessVerification({
    required FallDetectionSettings settings,
    required DateTime now,
  }) {
    _phase = _FallDetectionPhase.stillnessVerification;
    _isStationaryLocationWatch = false;
    _gyroscopeQuietStartedAt = null;
    final monitoringDuration = const Duration(minutes: 1);
    _gyroscopeMonitoringEndsAt = now.add(monitoringDuration);
    _setSnapshot(
      FallStillnessMonitorSnapshot.verifyingStillness(
        settings: settings,
        detectedAt: _lastCandidateAt ?? now,
        countdownEndsAt: _gyroscopeMonitoringEndsAt!,
        secondsRemaining: monitoringDuration.inSeconds,
        accelerationMagnitude: _latestImpactAcceleration,
        altitudeDropMeters: _lastAltitudeDropMeters,
        isBackpackTrapLikely: _isBackpackTrapLikely,
        message:
            'Impact confirmed. Monitoring gyroscope for stillness before alerting.',
      ),
    );
    _startCountdownTimer();
  }

  /// Starts response countdown.
  void _startResponseCountdown({
    required FallDetectionSettings settings,
    required DateTime now,
  }) {
    _phase = _FallDetectionPhase.responseCountdown;
    final responseEndsAt = now.add(settings.fallResponseDuration);
    _setSnapshot(
      FallStillnessMonitorSnapshot.awaitingResponse(
        settings: settings,
        detectedAt: _lastCandidateAt ?? now,
        countdownEndsAt: responseEndsAt,
        secondsRemaining: settings.fallResponseDuration.inSeconds,
        accelerationMagnitude: _latestImpactAcceleration,
        altitudeDropMeters: _lastAltitudeDropMeters,
        isBackpackTrapLikely: _isBackpackTrapLikely,
        isProlongedStillnessDetection: _isStationaryLocationWatch,
      ),
    );
    _startCountdownTimer();
  }

  /// Starts countdown timer.
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  /// Updates countdown.
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
      if (_isStationaryLocationWatch) {
        _setSnapshot(
          current.copyWith(
            secondsRemaining: 0,
            message:
                'Still checking phone movement. Monitoring continues until location changes.',
          ),
        );
      } else {
        _resetToNormal(
          settings: settings,
          message:
              'Gyroscope movement continued for 1 minute. Listening restarted.',
          lastCancelledAt: _clock(),
        );
      }
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

  /// Prevent concurrent emergency callbacks when the response countdown expires.
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
        isProlongedStillnessDetection: _isStationaryLocationWatch,
        message: _isStationaryLocationWatch
            ? 'Response countdown ended. Sending prolonged-stillness SOS.'
            : 'Response countdown ended. Sending Fall SOS.',
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

  /// Handles barometer.
  void _handleBarometer(BarometerEvent event) {
    final now = _clock();
    final altitude = _altitudeFromPressure(event.pressure);
    _altitudeHistory.add(_TimedValue(now, altitude));
    _altitudeHistory.removeWhere(
      (sample) =>
          now.difference(sample.recordedAt) > const Duration(seconds: 5),
    );
  }

  /// Computes altitude drop before.
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

  /// Computes altitude from pressure.
  double _altitudeFromPressure(double pressureHpa) {
    return 44330.0 *
        (1 - math.pow(pressureHpa / _seaLevelPressureHpa, 1 / 5.255))
            .toDouble();
  }

  /// Resets transient state.
  void _resetTransientState() {
    _phase = _FallDetectionPhase.normal;
    _freeFallObservedAt = null;
    _impactWindowEndsAt = null;
    _bounceGraceEndsAt = null;
    _gyroscopeQuietStartedAt = null;
    _gyroscopeMonitoringEndsAt = null;
    _lastCandidateAt = null;
    _latestImpactAcceleration = null;
    _lastAltitudeDropMeters = null;
    _isBackpackTrapLikely = false;
    _isStationaryLocationWatch = false;
  }

  /// Resets to normal.
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

  /// Sets snapshot.
  void _setSnapshot(FallStillnessMonitorSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Computes magnitude.
  double _magnitude(double x, double y, double z) {
    return math.sqrt(x * x + y * y + z * z);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    unawaited(_accelerometerSubscription?.cancel());
    unawaited(_gyroscopeSubscription?.cancel());
    unawaited(_barometerSubscription?.cancel());
    super.dispose();
  }
}

/// Defines the fall detection phase choices.
enum _FallDetectionPhase {
  normal,
  impactWindow,
  bounceGrace,
  stillnessVerification,
  responseCountdown,
}

/// Represents timed value.
class _TimedValue {
  /// Creates timed value.
  const _TimedValue(this.recordedAt, this.value);

  final DateTime recordedAt;
  final double value;
}

/// Defines the fall stillness monitor status choices.
enum FallStillnessMonitorStatus {
  inactive,
  listening,
  impactWindow,
  impactDetected,
  verifyingStillness,
  awaitingResponse,
  triggering,
  unavailable;

  /// Returns label.
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

/// Represents fall stillness monitor snapshot.
class FallStillnessMonitorSnapshot {
  /// Creates fall stillness monitor snapshot.
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
    this.isProlongedStillnessDetection = false,
    this.message,
  });

  /// Creates fall stillness monitor snapshot using inactive.
  const FallStillnessMonitorSnapshot.inactive()
    : this(status: FallStillnessMonitorStatus.inactive);

  /// Creates fall stillness monitor snapshot using listening.
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

  /// Creates fall stillness monitor snapshot using impact window.
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

  /// Creates fall stillness monitor snapshot using impact detected.
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

  /// Creates fall stillness monitor snapshot using verifying stillness.
  factory FallStillnessMonitorSnapshot.verifyingStillness({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime countdownEndsAt,
    required int secondsRemaining,
    required double? accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
    bool isProlongedStillnessDetection = false,
    String? message,
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
      isProlongedStillnessDetection: isProlongedStillnessDetection,
      message:
          message ??
          (isBackpackTrapLikely
              ? 'Impact had little altitude drop. Extending stillness check.'
              : 'Impact confirmed. Verifying stillness before alerting.'),
    );
  }

  /// Creates fall stillness monitor snapshot using awaiting response.
  factory FallStillnessMonitorSnapshot.awaitingResponse({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime countdownEndsAt,
    required int secondsRemaining,
    required double? accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
    required bool isProlongedStillnessDetection,
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
      isProlongedStillnessDetection: isProlongedStillnessDetection,
      message: isProlongedStillnessDetection
          ? 'Unusually long stillness detected. Cancel now if you are resting safely.'
          : 'Severe fall suspected. Cancel now if you are okay.',
    );
  }

  /// Creates fall stillness monitor snapshot using triggering.
  factory FallStillnessMonitorSnapshot.triggering({
    required FallDetectionSettings settings,
    required DateTime detectedAt,
    required DateTime triggeredAt,
    required double? accelerationMagnitude,
    required double? altitudeDropMeters,
    required bool isBackpackTrapLikely,
    required bool isProlongedStillnessDetection,
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
      isProlongedStillnessDetection: isProlongedStillnessDetection,
      message: message,
    );
  }

  /// Creates fall stillness monitor snapshot using unavailable.
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
  final bool isProlongedStillnessDetection;
  final String? message;

  /// Returns a copy with the supplied fields changed.
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
    bool? isProlongedStillnessDetection,
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
      isProlongedStillnessDetection:
          isProlongedStillnessDetection ?? this.isProlongedStillnessDetection,
      message: message ?? this.message,
    );
  }
}
