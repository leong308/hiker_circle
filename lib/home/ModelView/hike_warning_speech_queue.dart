import 'dart:async';

/// Serializes routine hike warnings so a new alert does not interrupt a
/// precaution that is still being read. Native SOS speech retains priority.
class HikeWarningSpeechQueue {
  HikeWarningSpeechQueue({required this.speak, required this.stop});

  final Future<bool> Function(String requestId, String message) speak;
  final Future<void> Function(String requestId) stop;
  final Map<String, _WarningSpeech> _pending = {};
  Future<void> _tail = Future<void>.value();
  _WarningSpeech? _playing;
  String? _sessionKey;
  bool _disposed = false;

  void synchronizeSession(String? key) {
    if (_disposed || key == _sessionKey) return;
    _sessionKey = key;
    for (final request in _pending.values.toList()) {
      unawaited(cancel(request.id));
    }
  }

  Future<bool> enqueue({
    required String requestId,
    required String message,
    required bool Function() canSpeak,
  }) {
    if (_disposed) return Future<bool>.value(false);
    final existing = _pending[requestId];
    if (existing != null) return existing.result.future;
    final request = _WarningSpeech(requestId);
    _pending[requestId] = request;
    _tail = _tail.then((_) async {
      if (_disposed || request.cancelled || !canSpeak()) {
        _finish(request, false);
        return;
      }
      _playing = request;
      var completed = false;
      try {
        completed = await Future.any<bool>([
          speak(requestId, message).timeout(const Duration(minutes: 5)),
          request.stopped.future.then((_) => false),
        ]);
        if (request.cancelled) await request.stopped.future;
      } catch (_) {
        await _stop(requestId);
      } finally {
        if (identical(_playing, request)) _playing = null;
        _finish(request, completed && !request.cancelled);
      }
    });
    return request.result.future;
  }

  Future<void> cancel(String requestId) async {
    final request = _pending[requestId];
    if (request == null || request.cancelled) return;
    request.cancelled = true;
    if (identical(_playing, request)) {
      // Await scoped native cleanup before allowing the next warning to speak.
      await _stop(requestId);
      if (!request.stopped.isCompleted) request.stopped.complete();
    }
    _finish(request, false);
  }

  Future<void> _stop(String requestId) async {
    try {
      await stop(requestId).timeout(const Duration(seconds: 2));
    } catch (_) {
      // An unavailable speech engine must never block hike tracking.
    }
  }

  void _finish(_WarningSpeech request, bool completed) {
    if (identical(_pending[request.id], request)) _pending.remove(request.id);
    if (!request.result.isCompleted) request.result.complete(completed);
  }

  void dispose() {
    _disposed = true;
    for (final request in _pending.values.toList()) {
      unawaited(cancel(request.id));
    }
  }
}

class _WarningSpeech {
  _WarningSpeech(this.id);
  final String id;
  final result = Completer<bool>();
  final stopped = Completer<void>();
  bool cancelled = false;
}

class PathDeviationAlertMessage {
  PathDeviationAlertMessage(double distanceMeters)
    : distanceMeters = distanceMeters.round();

  static const title = 'You may be off the planned trail';
  final int distanceMeters;
  String get body =>
      'Your location has deviated about $distanceMeters m from the route. '
      'Check the map and retrace safely.';
  String get speech =>
      '$title. Your location has deviated about $distanceMeters meters from '
      'the route. Check the map and retrace safely.';
}
