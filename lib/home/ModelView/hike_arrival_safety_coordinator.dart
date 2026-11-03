import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/services/network_reachability_service.dart';
import '../Data/hike_arrival_response_queue.dart';

import '../Data/hike_arrival_safety_service.dart';
import '../Model/hike_arrival_safety.dart';
import '../Model/hike_session_models.dart';

/// Coordinates durable local arrival checks and server cancellation without owning UI or fall/SOS state.
class HikeArrivalSafetyCoordinator extends ChangeNotifier {
  /// Supplies account/session readers and presentation boundaries for deterministic tests.
  HikeArrivalSafetyCoordinator({
    required this.owner,
    required this.readHike,
    required this.isReady,
    required this.canPresent,
    required this.present,
    required this.logWarning,
    required this.speak,
    this.native = const HikeArrivalSafetyService(),
    this.repository = const HikeArrivalSafetyRepository(),
    HikeArrivalResponseQueue? responses,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _responses =
           responses ??
           HikeArrivalResponseQueue(
             owner: owner,
             repository: repository,
             clock: clock,
           );
  final String owner;
  final ActiveHikeSession? Function() readHike;
  final bool Function() isReady, canPresent;
  final Future<void> Function() present, speak;
  final Future<void> Function(String key, String link, DateTime warnedAt)
  logWarning;
  final HikeArrivalSafetyService native;
  final HikeArrivalSafetyRepository repository;
  final DateTime Function() _clock;
  final HikeArrivalResponseQueue _responses;
  StreamSubscription<void>? _connection;
  final _closedLocally = <String>{};
  final _retainedResponses = <String>{};
  Timer? _timer;
  bool _disposed = false,
      _refreshing = false,
      _presenting = false,
      _syncing = false;
  bool busy = false;
  String? error;
  Map<String, dynamic>? _local, _cloud;
  Map<String, dynamic> _proof = {};
  String? _trackingKey, _sessionId;
  int _processedPoints = 0, _cloudGeneration = 0;
  DateTime? _lastCloudAttempt;
  final _logged = <String>{};

  /// Exposes only presentation data; a notification cannot declare the hiker safe.
  String get trailName =>
      readHike()?.trail.name ?? _local?['trailName']?.toString() ?? 'Your hike';

  /// Distinguishes a queued local response from acknowledged cancellation.
  bool get cancellationPending =>
      _local?['safe'] == true && _local?['cloudAcknowledged'] != true;

  /// Pending cloud work never reopens a locally answered or ended hike.
  bool get needsPrompt {
    final hike = readHike();
    if (hike == null ||
        _local == null ||
        _local?['safe'] == true ||
        _local?['arrived'] == true ||
        _closedLocally.contains(_trackingKey) ||
        const {'safe', 'arrived', 'completed'}.contains(_cloud?['status'])) {
      return false;
    }
    final plan = HikeArrivalPlan.fromHike(hike);
    return plan != null &&
        plan.trackingKey(owner) == _local?['trackingKey'] &&
        _local?['overdue'] == true;
  }

  /// Uses the authoritative deadline once cloud arming has completed.
  int get remainingSeconds {
    final deadline =
        (_cloud?['responseDeadlineMillis'] ?? _local?['responseDeadlineMillis'])
            as num?;
    if (deadline == null) return 0;
    return ((deadline.toInt() - _clock().millisecondsSinceEpoch) / 1000)
        .ceil()
        .clamp(0, 86400);
  }

  /// Reports confirmed and uncertain external work without claiming that it can be recalled.
  bool get dispatchStarted =>
      (_cloud?['sentCount'] as num? ?? 0) > 0 ||
      (_cloud?['uncertainCount'] as num? ?? 0) > 0 ||
      _cloud?['status'] == 'dispatched';

  /// Gives an accurate explanation during local-first cancellation or delivery failure.
  String get detail {
    if (dispatchStarted) {
      return 'A contact alert has already been submitted or may be sending. Confirming now stops any remaining messages; it cannot recall one already sent.';
    }
    if (_cloud?['status'] == 'dispatch_failed') {
      return 'The automatic contact alert could not be sent. Please contact your emergency contacts directly.';
    }
    if (_cloud?['status'] == 'no_contacts') {
      return 'No emergency contacts are saved in your cloud account. Go to SOS page and add now!';
    }
    return 'Your latest planned arrival time has passed and your recorded location has not confirmed arrival at a saved peak or the trail end. Please confirm that you are okay.';
  }

  /// Starts after the home shell can restore its active session.
  void start() {
    native.onChanged(refresh);
    _connection ??= NetworkReachabilityService.instance.connectionAvailable
        .listen((_) {
          unawaited(_responses.flush(force: true));
        });
    _timer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  /// Restores native state even when the app was opened manually rather than through its notification.
  Future<void> refresh() async {
    if (_disposed || _refreshing || !isReady()) return;
    _refreshing = true;
    try {
      final hike = readHike();
      if (hike != null) {
        final plan = HikeArrivalPlan.fromHike(hike);
        if (plan == null) {
          await _retire(await native.read(owner));
          _local = null;
          unawaited(_responses.flush());
          return;
        }
        final key = plan.trackingKey(owner);
        if (_trackingKey != key || _sessionId != hike.sessionId) {
          final restored = await native.read(owner);
          if (_disposed) return;
          if (restored != null && restored['trackingKey'] != key) {
            await _retainResponse(restored, reason: 'hike_ended');
          }
          _proof = restored?['trackingKey'] == key
              ? Map<String, dynamic>.from(
                  restored?['proof'] as Map? ?? const {},
                )
              : {};
          _processedPoints = 0;
          _cloud = null;
          _lastCloudAttempt = null;
          _cloudGeneration++;
          _trackingKey = key;
          _sessionId = hike.sessionId;
        }
        if (_processedPoints > hike.routePoints.length) _processedPoints = 0;
        _proof = plan.advance(
          hike.routePoints.skip(_processedPoints),
          _proof,
          _clock(),
        );
        _processedPoints = hike.routePoints.length;
        _local = await native.configure({
          'owner': owner,
          'trackingKey': key,
          'sessionId': hike.sessionId,
          'eventId': plan.eventId(hike.sessionId),
          'trailName': hike.trail.name,
          'plan': plan.toJson(),
          'proof': _proof,
          'responseWindowMillis': HikeArrivalPlan.responseWindow.inMilliseconds,
          if (_cloud != null) 'cloud': _cloud,
        });
        if (_disposed) return;
      } else {
        // A legacy native record must not become a modal on an ended hike.
        // Transfer cancellation to SQLite before clearing its warning state.
        final restored = await native.read(owner);
        if (_disposed) return;
        _local = null;
        _cloud = null;
        _sessionId = null;
        _trackingKey = null;
        _cloudGeneration++;
        _publish();
        await _retire(restored);
        unawaited(_responses.flush());
        return;
      }
      if (_local == null) return;
      if (_local?['safe'] == true || _local?['arrived'] == true) {
        _closedLocally.add(_trackingKey!);
        await _retainResponse(_local!);
      }
      unawaited(_responses.flush());
      unawaited(
        _synchronize().whenComplete(_publish).catchError((Object _) {}),
      );
      if (_disposed) return;
      if (needsPrompt) {
        final key = _trackingKey!;
        if (_logged.add(key)) {
          unawaited(
            logWarning(
              'arrival_$key',
              Uri(
                scheme: 'hikercircle',
                host: 'hike',
                path: '/arrival',
                queryParameters: {'sessionId': _sessionId!},
              ).toString(),
              DateTime.fromMillisecondsSinceEpoch(
                (_local!['warningAtMillis'] as num).toInt(),
              ),
            ).catchError((Object _) {}),
          );
        }
      }
      _publish();
      if (needsPrompt && canPresent() && !_presenting) {
        _presenting = true;
        final warned = (_local?['warningAtMillis'] as num?)?.toInt() ?? 0;
        // The bundled local-notification sound already speaks at the deadline. A late manual launch repeats the question.
        if (_clock().millisecondsSinceEpoch - warned > 30000 &&
            !cancellationPending) {
          unawaited(speak().catchError((Object _) {}));
        }
        unawaited(
          present()
              .whenComplete(() {
                _presenting = false;
              })
              .catchError((Object _) {}),
        );
      }
    } on MissingPluginException {
      // Unsupported platforms cannot arm a cloud escalation without the local warning surface.
    } catch (failure) {
      debugPrint('Arrival safety recovery will retry: ${failure.runtimeType}');
    } finally {
      _refreshing = false;
      _publish();
    }
  }

  Future<void> _retainResponse(
    Map<String, dynamic> state, {
    String? reason,
  }) async {
    final identity = '${state['trackingKey']}:${state['sessionId']}';
    if (_retainedResponses.contains(identity)) return;
    await _responses.enqueue(state, reason: reason);
    _retainedResponses.add(identity);
  }

  Future<void> _retire(Map<String, dynamic>? state) async {
    if (state != null) await _retainResponse(state, reason: 'hike_ended');
    await native.stop(owner);
  }

  /// Serializes routine cloud refreshes while allowing an explicit safe response to interrupt sending work.
  Future<void> _synchronize() async {
    if (_disposed ||
        _syncing ||
        _sessionId == null ||
        _local == null ||
        readHike() == null ||
        _local?['safe'] == true ||
        _local?['arrived'] == true ||
        _closedLocally.contains(_trackingKey) ||
        !NetworkReachabilityService.instance.latest.isOnline) {
      return;
    }
    if (_lastCloudAttempt != null &&
        _clock().difference(_lastCloudAttempt!) < const Duration(seconds: 15)) {
      return;
    }
    _syncing = true;
    _lastCloudAttempt = _clock();
    final generation = _cloudGeneration, session = _sessionId!;
    try {
      var result =
          _cloud ??
          await repository.call('armHikeArrivalSafety', {
            'sessionId': session,
            'warningAtMillis': _local!['warningAtMillis'],
          });
      if (_disposed || generation != _cloudGeneration) return;
      if (result == null) return;
      if (_local?['safe'] == true ||
          _local?['arrived'] == true ||
          _closedLocally.contains(_trackingKey) ||
          readHike() == null) {
        return;
      }
      if (_local?['overdue'] == true && result['enabled'] == true) {
        result = await repository.call('checkHikeArrivalSafety', {
          'sessionId': session,
        });
      }
      if (_disposed || generation != _cloudGeneration) return;
      _cloud = result;
      error = null;
      if (readHike() != null) {
        final native = _local!;
        _local = await this.native.configure({...native, 'cloud': result});
      } else if (const {
        'safe',
        'arrived',
        'completed',
      }.contains(result?['status'])) {
        await native.stop(owner);
        _local = null;
      }
    } on FirebaseFunctionsException catch (failure) {
      if (_disposed || generation != _cloudGeneration) return;
      if (readHike() == null &&
          const {'not-found', 'failed-precondition'}.contains(failure.code)) {
        await native.stop(owner);
        _local = null;
      } else {
        debugPrint('Arrival watchdog synchronization will retry.');
      }
    } catch (_) {
      if (!_disposed && generation == _cloudGeneration) {
        debugPrint('Arrival watchdog synchronization will retry.');
      }
    } finally {
      _syncing = false;
    }
  }

  /// The native commit settles the question; cloud cancellation is background work.
  Future<void> confirmEverythingOkay() async {
    if (_disposed || busy || !needsPrompt || _trackingKey == null) return;
    busy = true;
    error = null;
    _cloudGeneration++;
    final tracking = _trackingKey!;
    _publish();
    try {
      final saved = await native.confirmSafe(owner, tracking);
      if (_disposed) return;
      if (saved == null || saved['safe'] != true) {
        throw StateError('Local response was not saved.');
      }
      if (_trackingKey == tracking) _local = saved;
      _closedLocally.add(tracking);
      // The native safe flag survives termination even if SQLite transfer has
      // not finished. Recovery migrates it without showing another question.
      unawaited(
        _retainResponse(saved)
            .then(
              (_) => _responses.flush(
                force: NetworkReachabilityService.instance.latest.isOnline,
              ),
            )
            .catchError((Object _) {
              debugPrint('Saved arrival response will reconcile on recovery.');
            }),
      );
    } catch (_) {
      error = 'Unable to save your response on this phone. Please try again.';
    } finally {
      busy = false;
      _publish();
    }
  }

  /// Notifies UI listeners without retaining a BuildContext.
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  /// Releases only this feature's listeners; the persisted native warning survives process/UI disposal.
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connection?.cancel();
    native.onChanged(null);
    super.dispose();
  }
}
