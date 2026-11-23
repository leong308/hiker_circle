import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/Data/local_session_database.dart';
import '../../core/services/content_hash.dart';
import '../Model/hike_session_models.dart';

/// Represents hike reminder notifications.
abstract interface class HikeReminderNotifications {
  /// Computes pending.
  Future<Map<int, String?>> pending();

  /// Computes schedule.
  Future<void> schedule(
    int id,
    DateTime at,
    String title,
    String body,
    String payload,
  );

  /// Shows.
  Future<void> show(int id, String title, String body, String payload);

  /// Cancels.
  Future<void> cancel(int id);
}

/// A permission change must upgrade existing inexact alarms as well as new ones.
abstract interface class HikeReminderSchedulingPolicy {
  Future<String> schedulingPolicyKey();
}

/// Cloud departure pushes are fallbacks for slots not owned by this phone's OS.
abstract interface class HikeReminderScheduleAcknowledgements {
  Future<void> reportLocalSchedules(Map<String, Object?> report);
}

/// Represents device hike reminder notifications.
class DeviceHikeReminderNotifications
    implements
        HikeReminderNotifications,
        HikeReminderSchedulingPolicy,
        HikeReminderScheduleAcknowledgements {
  /// Creates device hike reminder notifications.
  DeviceHikeReminderNotifications(this.plugin, {FirebaseFunctions? functions})
    : _functions = functions;
  final FlutterLocalNotificationsPlugin plugin;
  final FirebaseFunctions? _functions;

  @override
  Future<void> reportLocalSchedules(Map<String, Object?> report) async {
    // Update cloud: acknowledge scheduled reminder slots
    final response = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable(
          'acknowledgeLocalHikeReminderSlots',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call(report);
    final data = response.data;
    if (data is! Map ||
        data['retryNeeded'] is! bool ||
        data['retryNeeded'] == true) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message:
            'Local reminder ownership is waiting for cloud reconciliation.',
      );
    }
  }

  @override
  Future<String> schedulingPolicyKey() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return 'platform-scheduled';
    return await android.canScheduleExactNotifications() == true
        ? 'android-exact'
        : 'android-inexact';
  }

  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'hiker_circle_hike_reminders',
      'Hike reminders',
      channelDescription: 'Reminders before your scheduled hikes',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  /// Computes pending.
  @override
  Future<Map<int, String?>> pending() async {
    // Native iOS safety requests have no plugin integer ID. Its typed API
    // throws on those entries; retain them as capacity reservations instead.
    final requests =
        await const MethodChannel(
          'dexterous.com/flutter/local_notifications',
        ).invokeListMethod<dynamic>('pendingNotificationRequests') ??
        [];
    final result = <int, String?>{};
    var nativeId = -1;
    for (final request in requests.whereType<Map>()) {
      final id = request['id'];
      result[id is int ? id : nativeId--] = request['payload'] as String?;
    }
    return result;
  }

  /// Computes schedule.
  @override
  Future<void> schedule(
    int id,
    DateTime at,
    String title,
    String body,
    String payload,
  ) async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    try {
      await plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      if (!exact) rethrow;
      // Permission may be revoked between the capability check and scheduling.
      await plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Shows.
  @override
  Future<void> show(int id, String title, String body, String payload) =>
      plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: details,
      );

  /// Cancels.
  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);
}

/// SQLite is the durable ledger; the OS owns delivery while the app is closed.
class UpcomingHikeReminderService {
  /// Creates upcoming hike reminder service.
  UpcomingHikeReminderService({
    required this.database,
    required this.notifications,
    required this.ownerPhoneNumber,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LocalSessionDatabase database;
  final HikeReminderNotifications notifications;
  final String ownerPhoneNumber;
  final DateTime Function() _now;
  Future<void> _work = Future.value();
  bool _active = true;
  String? _lastAcknowledgedHash;
  ({String hash, Map<String, Object?> report})? _nextAcknowledgement;
  Future<void>? _acknowledgementWork;

  @visibleForTesting
  Future<void> get acknowledgementWork =>
      _acknowledgementWork ?? Future<void>.value();

  // Keep the key independent of the temporary/cloud ID and preparation edits.
  /// Computes reminder key.
  static String reminderKey(UpcomingHike hike) => stableContentHash([
    hike.creatorPhone.replaceAll(RegExp(r'[^0-9]'), ''),
    hike.trailId,
    hike.departureTime.toUtc().toIso8601String(),
  ]);

  /// One durable notification per fixed slot, unaffected by local/cloud ID remaps.
  static String occurrenceKey(UpcomingHike hike, DateTime at) =>
      stableContentHash([
        'departure-reminder-v2',
        reminderKey(hike),
        at.toUtc().toIso8601String(),
      ]);

  /// Synchronizes.
  Future<void> synchronize() {
    if (!_active) return Future.value();
    final next = _work.catchError((Object _) {}).then((_) => _synchronize());
    _work = next;
    return next;
  }

  /// Synchronizes.
  Future<void> _synchronize() async {
    if (!_active) return;
    final now = _now().toUtc();
    final states =
        (await database.loadPlannedHikeStates(
          ownerPhoneNumber: ownerPhoneNumber,
        )).where(
          (state) =>
              !state.isConsumed &&
              !state.upcomingHike.isDeleted &&
              !state.upcomingHike.teamLaunchConsumed &&
              state.upcomingHike.departureTime.isAfter(now) &&
              state.reminderPreference?.enabled != false,
        );
    final pending = await notifications.pending();
    final transport = notifications;
    final schedulingPolicy = transport is HikeReminderSchedulingPolicy
        ? await (transport as HikeReminderSchedulingPolicy)
              .schedulingPolicyKey()
        : 'platform-scheduled';
    final rows = await database.loadHikeReminders();
    final occurrences =
        <String, ({LocalPlannedHikeState state, DateTime at})>{};
    for (final state in states) {
      final hike = state.upcomingHike;
      final preference =
          state.reminderPreference ??
          const HikeReminderPreference(
            firstReminderMinutesBefore: 60,
            repeatIntervalMinutes: 0,
          );
      for (final at in preference.scheduledTimes(hike.departureTime)) {
        final key = occurrenceKey(hike, at);
        final previous = occurrences[key];
        // A remap can briefly expose both snapshots. Prefer a real cloud link
        // without creating another notification for the same occurrence.
        if (previous == null ||
            (previous.state.upcomingHike.id.startsWith('local_pending_') &&
                !hike.id.startsWith('local_pending_'))) {
          occurrences[key] = (state: state, at: at.toUtc());
        }
      }
    }

    // Keep an already queued, still-valid elapsed slot for OS delivery. It may
    // be inexact/late; never replay it with show() when the app next opens.
    final elapsedPending = rows
        .where(
          (row) =>
              row.ownerPhoneNumber == ownerPhoneNumber &&
              occurrences.containsKey(row.reminderKey) &&
              !row.remindAt.isAfter(now) &&
              pending.containsKey(row.notificationId),
        )
        .map((row) => row.notificationId)
        .toSet();
    // Reserve native safety/check-in capacity on iOS (64 total), and count
    // occurrences rather than hikes when allocating the next 48 reminders.
    final ownIds = rows.map((row) => row.notificationId).toSet();
    final capacity =
        (48 -
                pending.keys.where((id) => !ownIds.contains(id)).length -
                elapsedPending.length)
            .clamp(0, 48);
    final future =
        occurrences.entries
            .where((entry) => entry.value.at.isAfter(now))
            .toList()
          ..sort((a, b) {
            final byTime = a.value.at.compareTo(b.value.at);
            return byTime != 0 ? byTime : a.key.compareTo(b.key);
          });
    final desired = Map.fromEntries(future.take(capacity));
    for (final row in rows) {
      if (!_active) return;
      if (row.ownerPhoneNumber == ownerPhoneNumber &&
          desired.containsKey(row.reminderKey)) {
        continue;
      }
      if (row.ownerPhoneNumber == ownerPhoneNumber &&
          occurrences.containsKey(row.reminderKey) &&
          !row.remindAt.isAfter(now)) {
        if (!pending.containsKey(row.notificationId) &&
            row.status == 'scheduled') {
          // Pending-list removal establishes expiry, not confirmed display.
          await database.setHikeReminderStatus(row.notificationId, 'elapsed');
        } else if (!pending.containsKey(row.notificationId) &&
            row.status == 'pending') {
          await database.setHikeReminderStatus(row.notificationId, 'missed');
        }
        continue;
      }
      if (row.status == 'scheduled' ||
          pending.containsKey(row.notificationId)) {
        await notifications.cancel(row.notificationId);
      }
      if (row.status != 'delivered' && row.status != 'elapsed') {
        await database.setHikeReminderStatus(row.notificationId, 'cancelled');
      }
      await database.deleteScheduledDeviceNotification(
        ownerPhoneNumber: row.ownerPhoneNumber,
        messageId: 'hike-reminder:${row.reminderKey}',
      );
    }
    for (final entry in desired.entries) {
      if (!_active) return;
      final hike = entry.value.state.upcomingHike;
      final at = entry.value.at;
      final title = 'Your hike is coming up';
      final start = hike.departureTime.toLocal();
      final time =
          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
      final body =
          '${hike.trailName} starts ${start.day}/${start.month}/${start.year} at $time. Remember to charge your phone to 100% before your hike.';
      final data = <String, dynamic>{
        'messageId': 'hike-reminder:${entry.key}',
        'type': 'local_upcoming_hike_reminder',
        'upcomingHikeId': hike.id,
        'ownerPhoneNumber': ownerPhoneNumber,
        'title': title,
        'body': body,
        'deepLink': Uri(
          scheme: 'hikercircle',
          host: 'upcoming-hike',
          path: '/view',
          queryParameters: {'upcomingHikeId': hike.id, 'chargePhone': '1'},
        ).toString(),
      };
      final payload = jsonEncode(data);
      final hash = stableContentHash([title, body, payload, schedulingPolicy]);
      final previous = rows
          .where(
            (row) =>
                row.ownerPhoneNumber == ownerPhoneNumber &&
                row.reminderKey == entry.key,
          )
          .firstOrNull;
      final row = await database.saveHikeReminder(
        ownerPhoneNumber: ownerPhoneNumber,
        reminderKey: entry.key,
        hikeId: hike.id,
        departureAt: hike.departureTime,
        remindAt: at,
        contentHash: hash,
      );

      /// Records history.
      Future<void> recordHistory() => database.saveDeviceNotification(
        ownerPhoneNumber: ownerPhoneNumber,
        messageId: 'hike-reminder:${entry.key}',
        title: title,
        body: body,
        type: 'local_upcoming_hike_reminder',
        deepLink: data['deepLink'] as String,
        data: data,
        receivedAt: row.remindAt,
        source: 'local_reminder',
      );
      if (!_active || row.status == 'delivered' || row.status == 'elapsed') {
        continue;
      }
      if (!row.remindAt.isAfter(_now().toUtc())) {
        // The slot may pass while SQLite/OS work is in flight. Do not turn a
        // missed departure reminder into an immediate notification/backlog.
        await database.setHikeReminderStatus(row.notificationId, 'missed');
        continue;
      }
      if (row.status == 'scheduled' &&
          pending[row.notificationId] == payload &&
          previous?.contentHash == hash) {
        await recordHistory();
        continue;
      }
      // The OS owns delivery after this call, including when Flutter is closed.
      await notifications.schedule(
        row.notificationId,
        row.remindAt,
        title,
        body,
        payload,
      );
      await recordHistory();
      await database.setHikeReminderStatus(row.notificationId, 'scheduled');
    }
    await _queueAcknowledgement(occurrences, now);
  }

  /// Report only actual OS-owned jobs; never hold the local scheduler on cloud IO.
  Future<void> _queueAcknowledgement(
    Map<String, ({LocalPlannedHikeState state, DateTime at})> occurrences,
    DateTime now,
  ) async {
    if (!_active || notifications is! HikeReminderScheduleAcknowledgements) {
      return;
    }
    try {
      final pending = await notifications.pending();
      final rows = await database.loadHikeReminders();
      final grouped = <String, Map<String, Object?>>{};
      final groupedSlots = <String, Set<int>>{};
      for (final row in rows) {
        final occurrence = occurrences[row.reminderKey];
        if (row.ownerPhoneNumber != ownerPhoneNumber || occurrence == null) {
          continue;
        }
        final future = row.remindAt.isAfter(now);
        final queued =
            row.status == 'scheduled' &&
            pending.containsKey(row.notificationId);
        final elapsed =
            !future &&
            const {'scheduled', 'elapsed', 'delivered'}.contains(row.status);
        if (!(future ? queued : elapsed)) continue;
        final hike = occurrence.state.upcomingHike;
        if (hike.id.startsWith('local_pending_') ||
            occurrence.state.scheduleSyncPending ||
            occurrence.state.reminderSyncPending ||
            occurrence.state.reminderPreference == null) {
          continue;
        }
        final preference = occurrence.state.reminderPreference!.normalized();
        grouped.putIfAbsent(
          hike.id,
          () => {
            'hikeId': hike.id,
            'departureAtMillis': hike.departureTime
                .toUtc()
                .millisecondsSinceEpoch,
            'firstReminderMinutesBefore': preference.firstReminderMinutesBefore,
            'repeatIntervalMinutes': preference.repeatIntervalMinutes,
          },
        );
        groupedSlots
            .putIfAbsent(hike.id, () => <int>{})
            .add(row.remindAt.toUtc().millisecondsSinceEpoch);
      }
      final totalSlots = groupedSlots.values.fold<int>(
        0,
        (total, slots) => total + slots.length,
      );
      // A truncated replacement could release ownership of an already due slot.
      // Leave the prior acknowledgement intact and retry on the next sync.
      if (grouped.length > 96 ||
          totalSlots > 512 ||
          groupedSlots.values.any((slots) => slots.length > 128)) {
        return;
      }
      final schedules = <Map<String, Object?>>[];
      final hikeIds = grouped.keys.toList()..sort();
      for (final id in hikeIds) {
        final slots = groupedSlots[id]!.toList()..sort();
        schedules.add({...grouped[id]!, 'slots': slots});
      }
      final installationId = await database.loadOrCreateAppInstanceId();
      if (!_active) return;
      final report = <String, Object?>{
        'expectedOwner': ownerPhoneNumber,
        'installationId': installationId,
        'schedules': schedules,
      };
      final hash = stableContentHash(report);
      if (_acknowledgementWork == null && hash == _lastAcknowledgedHash) return;
      _nextAcknowledgement = (hash: hash, report: report);
      if (_acknowledgementWork != null) return;
      final work = _flushAcknowledgements();
      _acknowledgementWork = work;
      unawaited(
        work.whenComplete(() {
          if (identical(_acknowledgementWork, work)) {
            _acknowledgementWork = null;
          }
        }),
      );
    } catch (_) {
      // Offline/local reporting failures must never undo OS scheduling.
    }
  }

  Future<void> _flushAcknowledgements() async {
    while (_active && _nextAcknowledgement != null) {
      final next = _nextAcknowledgement!;
      _nextAcknowledgement = null;
      if (next.hash == _lastAcknowledgedHash) continue;
      try {
        await (notifications as HikeReminderScheduleAcknowledgements)
            .reportLocalSchedules(next.report);
        if (_active) _lastAcknowledgedHash = next.hash;
      } catch (_) {
        // Do not cache a failed/uncertain acknowledgement. A later local sync
        // supplies the newest complete snapshot and retries it.
        return;
      }
    }
  }

  /// Stops for sign out.
  Future<void> stopForSignOut() async {
    _active = false;
    await _work.catchError((Object _) {});
    for (final row in await database.loadHikeReminders()) {
      if (row.ownerPhoneNumber != ownerPhoneNumber) continue;
      await notifications.cancel(row.notificationId);
      await database.deleteScheduledDeviceNotification(
        ownerPhoneNumber: row.ownerPhoneNumber,
        messageId: 'hike-reminder:${row.reminderKey}',
      );
      if (row.status != 'delivered') {
        await database.setHikeReminderStatus(row.notificationId, 'cancelled');
      }
    }
  }
}
