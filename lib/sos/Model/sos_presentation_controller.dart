import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sos_models.dart';

/// Defines the sos presentation phase choices.
enum SosPresentationPhase { sending, sent, partial, queued, noContacts, failed }

// Native audio is process-wide. This scalar lease prevents an old account's
// delayed cleanup from stopping a newer account's alarm; it stores no identity.
int _latestAlarmOutputGeneration = 0;

/// Native output startup is independent of emergency dispatch. A late native
/// completion must honour a slide response, timeout or account disposal.
void startSosAlarmOutput({
  required SosPresentationController controller,
  required int eventId,
  required Future<void> Function() start,
  required Future<void> Function() stop,
  VoidCallback? onStarted,
  VoidCallback? onUnavailable,
  Duration startupTimeout = const Duration(seconds: 4),
}) {
  if (!controller.isAlarmRequested(eventId)) return;
  final outputGeneration = controller._alarmOutputGeneration;

  /// Computes still owns output.
  bool stillOwnsOutput() {
    final current = controller.current;
    return outputGeneration == _latestAlarmOutputGeneration &&
        (current == null ||
            current.eventId == eventId ||
            !current.mode.usesLoudEmergencyPattern);
  }

  /// Stops owned output.
  Future<void> stopOwnedOutput() async {
    if (!stillOwnsOutput()) return;
    try {
      await stop();
    } catch (_) {
      // The explicit slide control retains its own, visible cleanup retry.
    }
  }

  var startupPending = true;
  final timer = Timer(startupTimeout, () {
    if (!startupPending || !stillOwnsOutput()) return;
    if (controller.current?.eventId == eventId) {
      controller.markAlarmUnavailable(eventId);
      onUnavailable?.call();
    }
    unawaited(stopOwnedOutput());
  });
  unawaited(() async {
    try {
      await start();
      if (stillOwnsOutput() && controller.isAlarmRequested(eventId)) {
        onStarted?.call();
      } else {
        await stopOwnedOutput();
      }
    } catch (_) {
      if (controller.current?.eventId == eventId) {
        controller.markAlarmUnavailable(eventId);
        onUnavailable?.call();
      }
    } finally {
      startupPending = false;
      timer.cancel();
    }
  }());
}

/// The current, explicitly triggered SOS, scoped to one signed-in home shell.
/// Queue retries and historic log updates never create a presentation.
@immutable
class SosPresentation {
  /// Creates sos presentation.
  const SosPresentation({
    required this.eventId,
    required this.mode,
    required this.triggeredAt,
    required this.phase,
    required this.message,
    required this.alarmActive,
    this.isStopping = false,
  });

  final int eventId;
  final SosAlertMode mode;
  final DateTime triggeredAt;
  final SosPresentationPhase phase;
  final String message;
  final bool alarmActive;
  final bool isStopping;

  /// Returns a copy with the supplied fields changed.
  SosPresentation _copyWith({
    SosPresentationPhase? phase,
    String? message,
    bool? alarmActive,
    bool? isStopping,
  }) => SosPresentation(
    eventId: eventId,
    mode: mode,
    triggeredAt: triggeredAt,
    phase: phase ?? this.phase,
    message: message ?? this.message,
    alarmActive: alarmActive ?? this.alarmActive,
    isStopping: isStopping ?? this.isStopping,
  );
}

/// Represents sos presentation controller.
class SosPresentationController extends ChangeNotifier {
  SosPresentation? _current;
  Future<void> Function()? _onStopAlarm;
  int _nextEventId = 0;
  int _alarmOutputGeneration = 0;
  bool _disposed = false;
  String? _alertId;
  int _confirmedSentCount = 0;

  /// Returns current.
  SosPresentation? get current => _current;

  /// Publish before waiting for GPS, native hardware, local storage or delivery.
  int begin({
    required SosAlertMode mode,
    DateTime? triggeredAt,
    required Future<void> Function() onStopAlarm,
  }) {
    if (_disposed) return -1;
    final eventId = ++_nextEventId;
    if (mode.usesLoudEmergencyPattern) {
      _alarmOutputGeneration = ++_latestAlarmOutputGeneration;
    }
    _onStopAlarm = onStopAlarm;
    _alertId = null;
    _confirmedSentCount = 0;
    _current = SosPresentation(
      eventId: eventId,
      mode: mode,
      triggeredAt: triggeredAt ?? DateTime.now().toUtc(),
      phase: SosPresentationPhase.sending,
      message: 'Preparing your alert for emergency contacts…',
      alarmActive: mode.usesLoudEmergencyPattern,
    );
    notifyListeners();
    return eventId;
  }

  /// Checks whether alarm requested.
  bool isAlarmRequested(int eventId) =>
      !_disposed &&
      _current?.eventId == eventId &&
      _current?.alarmActive == true;

  /// Updates status.
  void updateStatus(
    int eventId, {
    required SosPresentationPhase phase,
    required String message,
  }) {
    if (_disposed || _current?.eventId != eventId) return;
    if (_current!.phase == phase && _current!.message == message) return;
    _current = _current!._copyWith(phase: phase, message: message);
    notifyListeners();
  }

  /// Checks whether there is delivery status.
  bool hasDeliveryStatus(int eventId) =>
      !_disposed && _current?.eventId == eventId && _alertId != null;

  /// Queue retries can finish after the original trigger future completes.
  /// Update only the currently visible emergency; never open a historic alert.
  void updateDelivery(SosAlert alert, {bool queuedForRetry = false}) {
    final current = _current;
    if (_disposed ||
        current == null ||
        alert.mode != current.mode ||
        !alert.triggeredAt.isAtSameMomentAs(current.triggeredAt) ||
        (_alertId != null && _alertId != alert.id)) {
      return;
    }
    updateResult(
      current.eventId,
      SosAlertResult(alert: alert, queuedForRetry: queuedForRetry),
    );
  }

  /// Updates result.
  void updateResult(
    int eventId,
    SosAlertResult? result, {
    String? errorMessage,
  }) {
    if (_disposed || _current?.eventId != eventId) return;
    if (result == null) {
      if (_confirmedSentCount > 0) return;
      updateStatus(
        eventId,
        phase: SosPresentationPhase.failed,
        message: errorMessage ?? 'Your alert could not be saved or sent.',
      );
      return;
    }
    final alert = result.alert;
    if ((_alertId != null && _alertId != alert.id) ||
        alert.sentCount < _confirmedSentCount ||
        (_current!.phase == SosPresentationPhase.sent &&
            _alertId != null &&
            alert.status != SosAlertStatus.sent)) {
      return;
    }
    _alertId = alert.id;
    _confirmedSentCount = alert.sentCount;

    /// Computes contacts.
    String contacts(int count) => count == 1 ? 'contact' : 'contacts';
    final (phase, message) = switch (alert.status) {
      SosAlertStatus.sent => (
        SosPresentationPhase.sent,
        '${alert.sentCount} emergency ${contacts(alert.sentCount)} notified.',
      ),
      SosAlertStatus.partial => (
        SosPresentationPhase.partial,
        '${alert.sentCount} of ${alert.contactCount} emergency ${contacts(alert.contactCount)} notified.',
      ),
      SosAlertStatus.queued => (
        result.queuedForRetry
            ? SosPresentationPhase.queued
            : SosPresentationPhase.sending,
        result.queuedForRetry
            ? 'Your alert is saved. HikerCircle will retry when a connection is available.'
            : 'Your alert is saved. Sending to your emergency contacts…',
      ),
      SosAlertStatus.noContacts => (
        SosPresentationPhase.noContacts,
        result.queuedForRetry
            ? 'Your alert is saved, but no emergency contacts are available yet.'
            : 'No emergency contacts are saved. Your alert was logged.',
      ),
      SosAlertStatus.failed => (
        SosPresentationPhase.failed,
        'Your alert could not be sent to your contacts.',
      ),
    };
    updateStatus(eventId, phase: phase, message: message);
  }

  /// Marks alarm unavailable.
  void markAlarmUnavailable(int eventId) {
    if (_disposed || _current?.eventId != eventId) return;
    _current = _current!._copyWith(alarmActive: false);
    notifyListeners();
  }

  /// Stops local output only. The durable emergency dispatch is never removed.
  Future<void> stopAlarm() async {
    final current = _current;
    if (_disposed || current == null || current.isStopping) return;
    final callback = _onStopAlarm;
    _current = current._copyWith(alarmActive: false, isStopping: true);
    notifyListeners();
    try {
      await callback?.call();
    } finally {
      if (!_disposed && _current?.eventId == current.eventId) {
        _current = _current!._copyWith(isStopping: false);
        notifyListeners();
      }
    }
  }

  /// Computes dismiss.
  void dismiss(int eventId) {
    if (_disposed || _current?.eventId != eventId) return;
    _current = null;
    _onStopAlarm = null;
    _alertId = null;
    _confirmedSentCount = 0;
    notifyListeners();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _current = null;
    _onStopAlarm = null;
    super.dispose();
  }
}
