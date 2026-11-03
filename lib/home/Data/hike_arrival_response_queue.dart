import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../../core/services/network_reachability_service.dart';
import '../Model/hike_arrival_safety.dart';
import 'hike_arrival_safety_service.dart';

/// Local safety acknowledgement and remote watchdog cancellation have separate
/// lifetimes. Pending cancellations must never own or reopen a dialog route.
class HikeArrivalResponseQueue {
  HikeArrivalResponseQueue({
    required this.owner,
    LocalSessionDatabase? database,
    this.repository = const HikeArrivalSafetyRepository(),
    bool Function()? isOnline,
    DateTime Function()? clock,
  }) : database = database ?? LocalSessionDatabase(),
       isOnline =
           isOnline ??
           (() => NetworkReachabilityService.instance.latest.isOnline),
       clock = clock ?? DateTime.now;
  final String owner;
  final LocalSessionDatabase database;
  final HikeArrivalSafetyRepository repository;
  final bool Function() isOnline;
  final DateTime Function() clock;
  Future<void>? _work;
  bool _forceRequested = false;
  DateTime? _lastAttempt;
  static const prefix = 'pending_arrival_response:';

  /// Native storage has already saved the response. Transfer its minimal
  /// cancellation identity before clearing/replacing an ended hike's record.
  Future<void> enqueue(Map<String, dynamic> state, {String? reason}) async {
    final tracking = state['trackingKey'] as String?;
    final session = state['sessionId'] as String?;
    final latest = (state['plan'] as Map?)?['latestArrivalAtMillis'] as num?;
    if (tracking == null ||
        session == null ||
        latest == null ||
        state['owner'] != owner ||
        state['cloudAcknowledged'] == true) {
      return;
    }
    await database.saveLocalPreference(
      ownerPhoneNumber: owner,
      key: '$prefix$tracking',
      value: {
        'trackingKey': tracking,
        'sessionId': session,
        'eventId': HikeArrivalPlan.eventForSession(session, latest.toInt()),
        'reason': state['safe'] == true
            ? 'hiker_confirmation'
            : state['arrived'] == true
            ? 'recorded_arrival'
            : reason ?? 'hike_ended',
      },
    );
  }

  Future<void> flush({bool force = false}) {
    if (_work != null) {
      _forceRequested = _forceRequested || force;
      return _work!;
    }
    // Set ownership before starting the async pass, including passes which
    // return immediately while offline. Ordinary one-second ticks coalesce.
    final completion = Completer<void>();
    _work = completion.future;
    unawaited(_run(completion, force));
    return completion.future;
  }

  Future<void> _run(Completer<void> completion, bool force) async {
    try {
      var nextForce = force;
      do {
        _forceRequested = false;
        await _flush(nextForce);
        nextForce = _forceRequested;
      } while (nextForce);
    } catch (error) {
      debugPrint(
        'Arrival response will retry in the background: ${error.runtimeType}',
      );
    } finally {
      _work = null;
      completion.complete();
    }
  }

  Future<void> _flush(bool force) async {
    if (!force &&
        (!isOnline() ||
            _lastAttempt != null &&
                clock().difference(_lastAttempt!) <
                    const Duration(seconds: 15))) {
      return;
    }
    final rows = await database.loadPendingArrivalResponses(owner: owner);
    if (rows.isEmpty) return;
    _lastAttempt = clock();
    for (final entry in rows.entries) {
      try {
        final result = await repository.call('confirmHikeArrivalSafety', {
          ...entry.value,
          'expectedOwner': owner,
        });
        if (result == null ||
            !const {
              'safe',
              'arrived',
              'completed',
              'superseded',
            }.contains(result['status'])) {
          continue;
        }
        await database.clearLocalPreferenceIfValue(
          ownerPhoneNumber: owner,
          key: entry.key,
          expectedValue: entry.value,
        );
      } on FirebaseFunctionsException catch (error) {
        // An older event is no longer eligible for dispatch after its plan was
        // replaced. Auth/network failures retain the owner-scoped response.
        if (error.code == 'failed-precondition' || error.code == 'not-found') {
          await database.clearLocalPreferenceIfValue(
            ownerPhoneNumber: owner,
            key: entry.key,
            expectedValue: entry.value,
          );
        }
      }
    }
  }
}
