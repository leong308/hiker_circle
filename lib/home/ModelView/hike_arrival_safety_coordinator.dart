import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final String owner;
  final ActiveHikeSession? Function() readHike;
  final bool Function() isReady, canPresent;
  final Future<void> Function() present, speak;
  final Future<void> Function(String key, String link, DateTime warnedAt)
  logWarning;
  final HikeArrivalSafetyService native;
  final HikeArrivalSafetyRepository repository;
  final DateTime Function() _clock;
  Timer? _timer;
  bool _disposed = false,
      _refreshing = false,
      _presenting = false,
      _syncing = false;
  bool _sawActiveHike = false;
  bool busy = false;
  bool receiptNeedsAcknowledgement = false;
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

  /// Preserves the popup until confirmation or actual recorded arrival.
  bool get needsPrompt =>
      busy ||
      receiptNeedsAcknowledgement ||
      _local != null &&
          _local?['arrived'] != true &&
          (_local?['overdue'] == true || cancellationPending);

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
    if (cancellationPending) {
      return 'Your safe response is saved on this phone. Connecting to cancel the pending contact alert.';
    }
    if (dispatchStarted) {
      return 'A contact alert has already been submitted or may be sending. Confirming now stops any remaining messages; it cannot recall one already sent.';
    }
    if (_cloud?['status'] == 'dispatch_failed') {
      return 'The automatic contact alert could not be sent. Please contact your emergency contacts directly.';
    }
    if (_cloud?['status'] == 'no_contacts') {
      return 'No emergency contacts are saved in your cloud account. Go to SOS page and add now!';
    }
    return 'Your recorded footprints have not confirmed arrival at a saved peak or the trail end. Confirm that you are okay to cancel the pending alert to your emergency contacts.';
  }

  /// Starts after the home shell can restore its active session.
  void start() {
    native.onChanged(refresh);
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
        _sawActiveHike = true;
        final plan = HikeArrivalPlan.fromHike(hike);
        if (plan == null) {
          await native.stop(owner);
          _local = null;
          return;
        }
        final key = plan.trackingKey(owner);
        if (_trackingKey != key || _sessionId != hike.sessionId) {
          final restored = await native.read(owner);
          if (_disposed) return;
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
        // Retain an offline safe response until the server acknowledges it, including after app termination.
        final restored = await native.read(owner);
        if (_disposed) return;
        if (_sawActiveHike && restored != null && restored['safe'] != true) {
          _local = await native.confirmSafe(
            owner,
            restored['trackingKey'] as String,
          );
        } else {
          _local = restored;
        }
        _sawActiveHike = false;
        _sessionId ??= _local?['sessionId'] as String?;
        _trackingKey ??= _local?['trackingKey'] as String?;
      }
      if (_local == null) return;
      unawaited(
        _synchronize().whenComplete(_publish).catchError((Object _) {}),
      );
      if (_disposed) return;
      if (_local?['overdue'] == true || _local?['notifiedAtMillis'] is num) {
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
      error =
          'Unable to refresh the arrival check. Your saved response will retry when connected.';
      _publish();
    } finally {
      _refreshing = false;
    }
  }

  /// Serializes routine cloud refreshes while allowing an explicit safe response to interrupt sending work.
  Future<void> _synchronize() async {
    if (_disposed || _syncing || _sessionId == null || _local == null) return;
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
      final plan = _local!['plan'] as Map;
      final event = HikeArrivalPlan.eventForSession(
        session,
        (plan['latestArrivalAtMillis'] as num).toInt(),
      );
      if ((_local?['safe'] == true || _local?['arrived'] == true) &&
          !const {'safe', 'arrived', 'completed'}.contains(result['status'])) {
        result = await repository.call('confirmHikeArrivalSafety', {
          'sessionId': session,
          'eventId': event,
          if (_local?['arrived'] == true) 'reason': 'recorded_arrival',
        });
      } else if (_local?['overdue'] == true && result['enabled'] == true) {
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
        error = 'The cloud check will retry when connected.';
      }
    } catch (_) {
      if (!_disposed && generation == _cloudGeneration) {
        error = 'The cloud check will retry when connected.';
      }
    } finally {
      _syncing = false;
    }
  }

  /// A button press first commits the native safe flag, then cancels authenticated cloud work.
  Future<void> confirmEverythingOkay() async {
    if (_disposed || busy || _local == null || _trackingKey == null) return;
    busy = true;
    error = null;
    _cloudGeneration++;
    final generation = _cloudGeneration;
    final tracking = _trackingKey!;
    final session = _sessionId;
    _publish();
    try {
      final saved = await native.confirmSafe(owner, tracking);
      if (_disposed || generation != _cloudGeneration) return;
      _local = saved;
      _publish();
      if (_local == null || session == null) return;
      final armed =
          _cloud ??
          await repository.call('armHikeArrivalSafety', {
            'sessionId': session,
            'warningAtMillis': _local!['warningAtMillis'],
          });
      if (_disposed || generation != _cloudGeneration) return;
      if (armed == null) {
        error = 'Saved on this phone. Cloud cancellation is unavailable.';
        return;
      }
      final confirmed = await repository.call('confirmHikeArrivalSafety', {
        'sessionId': session,
        'eventId': armed['eventId'],
      });
      if (_disposed || generation != _cloudGeneration) return;
      _cloud = confirmed;
      receiptNeedsAcknowledgement = dispatchStarted;
      _local = await native.configure({..._local!, 'cloud': _cloud});
      _lastCloudAttempt = _clock();
    } catch (_) {
      if (_disposed || generation != _cloudGeneration) return;
      error =
          'Your response is saved on this phone. Connecting to cancel the contact alert.';
      _lastCloudAttempt = null;
    } finally {
      busy = false;
      _publish();
    }
  }

  /// Notifies UI listeners without retaining a BuildContext.
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  /// Closes a late confirmation receipt after explaining that an already-started message cannot be recalled.
  void dismissReceipt() {
    receiptNeedsAcknowledgement = false;
    _publish();
  }

  /// Releases only this feature's listeners; the persisted native warning survives process/UI disposal.
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    native.onChanged(null);
    super.dispose();
  }
}
