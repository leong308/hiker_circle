// ActiveHikePrecautionAnnouncer keeps a visible hike warning synchronized with its spoken message.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../trail/Model/trail_precautions.dart';
import '../Model/hike_session_models.dart';

/// Owns the visible warning and its speech together. Ordinary snackbars cannot
/// replace it, and an accepted warning is claimed before asynchronous playback.
class ActiveHikePrecautionAnnouncer extends ChangeNotifier {
  ActiveHikePrecautionAnnouncer({required this.speak, required this.stop});

  final Future<bool> Function(String requestId, String message) speak;
  final Future<void> Function(String requestId) stop;
  final Map<String, int> _announced = {};
  String? _sessionKey;
  ActiveHikePrecautionNotice? _notice;
  Completer<void>? _closed;
  Timer? _closeTimer;
  bool _disposed = false;
  int _sequence = 0;

  ActiveHikePrecautionNotice? get notice => _notice;

  // A cloud ID remap does not create a new hike or reset warning history.
  static String sessionKey(ActiveHikeSession hike) =>
      '${hike.trail.trailId}:${hike.startedAt.toUtc().microsecondsSinceEpoch}';

  void synchronizeSession(String? key) {
    if (_disposed || key == _sessionKey) return;
    dismiss();
    _sessionKey = key;
    _announced.clear();
  }

  Future<void> announce({
    required String sessionKey,
    required List<TrailPrecaution> cautions,
    required bool Function() canPresent,
  }) async {
    if (_disposed ||
        _sessionKey != sessionKey ||
        _notice != null ||
        !canPresent()) {
      return;
    }
    final fresh = cautions
        .where((c) => (_announced[c.id] ?? 0) < c.priority)
        .toList();
    if (fresh.isEmpty) return;

    final current = ActiveHikePrecautionNotice(
      requestId:
          'hike-precaution-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      message: fresh.map((c) => '${c.title}. ${c.message}').join(' '),
    );
    for (final caution in fresh) {
      _announced[caution.id] = caution.priority;
    }
    final closed = Completer<void>();
    _closed = closed;
    _notice = current;
    notifyListeners();

    final completed = await Future.any<bool>([
      _play(current),
      closed.future.then((_) => false),
    ]);
    if (_disposed || !identical(_notice, current)) return;
    if (!canPresent()) {
      dismiss();
      return;
    }
    if (completed) {
      // Give the user a moment after the last spoken word. Missing or failed
      // speech leaves the written warning available until explicitly closed.
      _closeTimer = Timer(const Duration(seconds: 3), () {
        _dismiss(stopSpeech: false);
      });
    }
    await closed.future;
  }

  Future<bool> _play(ActiveHikePrecautionNotice current) async {
    try {
      return await speak(
        current.requestId,
        'Hike precaution. ${current.message}',
      ).timeout(const Duration(minutes: 5));
    } catch (_) {
      await _stop(current.requestId);
      return false;
    }
  }

  Future<void> _stop(String requestId) async {
    try {
      await stop(requestId);
    } catch (_) {
      // Speech is optional; cleanup must not interfere with hike tracking.
    }
  }

  void dismiss() => _dismiss(stopSpeech: true);

  void _dismiss({required bool stopSpeech}) {
    _closeTimer?.cancel();
    _closeTimer = null;
    final current = _notice;
    _notice = null;
    final closed = _closed;
    _closed = null;
    if (closed != null && !closed.isCompleted) closed.complete();
    if (current == null) return;
    if (!_disposed) notifyListeners();
    if (stopSpeech) unawaited(_stop(current.requestId));
  }

  @override
  void dispose() {
    _disposed = true;
    dismiss();
    super.dispose();
  }
}

class ActiveHikePrecautionNotice {
  const ActiveHikePrecautionNotice({
    required this.requestId,
    required this.message,
  });
  final String requestId;
  final String message;
}
