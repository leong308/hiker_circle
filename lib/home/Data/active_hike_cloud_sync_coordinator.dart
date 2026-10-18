import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../Model/hike_session_models.dart';

/// Serializes active-hike configuration writes and resolves the draft at execution
/// time. A newer choice is reconciled before a pending request releases the queue.
class ActiveHikeCloudSyncCoordinator {
  ActiveHikeCloudSyncCoordinator({
    required this.readCurrent,
    required this.ensure,
    required this.apply,
    required this.onSynchronized,
  });

  final ActiveHikeSession? Function() readCurrent;
  final Future<ActiveHikeCloudRestoreResult> Function(ActiveHikeSession) ensure;
  final Future<ActiveHikeSession?> Function(
    ActiveHikeSession,
    ActiveHikeCloudRestoreResult,
  )
  apply;
  final void Function(ActiveHikeSession) onSynchronized;

  Future<void> _tail = Future<void>.value();
  ({String sessionId, bool sharing, int seconds})? _lastSynchronized;

  void invalidate() => _lastSynchronized = null;

  Future<ActiveHikeSession?> synchronize(
    String sessionId, {
    bool force = false,
  }) {
    final operation = _tail.then((_) => _synchronizeCurrent(sessionId, force));
    // Callers may time out waiting, but this tail still awaits the actual RPC.
    // Releasing it on a caller timeout would let an older commit overtake a new one.
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<ActiveHikeSession?> _synchronizeCurrent(
    String sessionId,
    bool force,
  ) async {
    var expectedSessionId = sessionId;
    var current = readCurrent();
    if (current == null || current.sessionId != expectedSessionId) return null;
    if (!force && _lastSynchronized == _key(current)) return current;
    while (true) {
      current = readCurrent();
      if (current == null || current.sessionId != expectedSessionId) {
        return null;
      }
      final submitted = current;
      final result = await ensure(submitted);
      current = readCurrent();
      if (current == null || current.sessionId != expectedSessionId) {
        return null;
      }
      final applied = await apply(submitted, result);
      if (applied == null || !result.ensured || result.terminal) return null;
      expectedSessionId = applied.sessionId;
      current = readCurrent();
      if (current == null || current.sessionId != expectedSessionId) {
        return null;
      }
      if (current.draft.shareLiveLocation !=
              submitted.draft.shareLiveLocation ||
          current.draft.locationRecordingInterval !=
              submitted.draft.locationRecordingInterval) {
        // Keep ownership of the queue until the latest choice is acknowledged.
        continue;
      }
      _lastSynchronized = _key(current);
      onSynchronized(current);
      return current;
    }
  }

  ({String sessionId, bool sharing, int seconds}) _key(
    ActiveHikeSession hike,
  ) => (
    sessionId: hike.sessionId,
    sharing: hike.draft.shareLiveLocation,
    seconds: hike.draft.locationRecordingInterval.inSeconds,
  );
}
