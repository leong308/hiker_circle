import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/Data/local_session_database.dart';
import '../../core/services/content_hash.dart';
import '../Model/hike_session_models.dart';

abstract interface class HikeReminderNotifications {
  Future<Map<int, String?>> pending();
  Future<void> schedule(
    int id,
    DateTime at,
    String title,
    String body,
    String payload,
  );
  Future<void> show(int id, String title, String body, String payload);
  Future<void> cancel(int id);
}

class DeviceHikeReminderNotifications implements HikeReminderNotifications {
  DeviceHikeReminderNotifications(this.plugin);
  final FlutterLocalNotificationsPlugin plugin;

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

  @override
  Future<void> show(int id, String title, String body, String payload) =>
      plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: details,
      );
  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);
}

/// SQLite is the durable ledger; the OS owns delivery while the app is closed.
class UpcomingHikeReminderService {
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

  static DateTime reminderTime(DateTime departure, DateTime now) {
    final oneHourBefore = departure.toUtc().subtract(const Duration(hours: 1));
    return oneHourBefore.isAfter(now.toUtc()) ? oneHourBefore : now.toUtc();
  }

  // Keep the key independent of the temporary/cloud ID and preparation edits.
  static String reminderKey(UpcomingHike hike) => stableContentHash([
    hike.creatorPhone.replaceAll(RegExp(r'[^0-9]'), ''),
    hike.trailId,
    hike.departureTime.toUtc().toIso8601String(),
  ]);

  Future<void> synchronize() {
    if (!_active) return Future.value();
    final next = _work.catchError((Object _) {}).then((_) => _synchronize());
    _work = next;
    return next;
  }

  Future<void> _synchronize() async {
    if (!_active) return;
    final now = _now().toUtc();
    final states =
        (await database.loadPlannedHikeStates(
              ownerPhoneNumber: ownerPhoneNumber,
            ))
            .where(
              (state) =>
                  !state.isConsumed &&
                  !state.upcomingHike.isDeleted &&
                  state.upcomingHike.departureTime.isAfter(now) &&
                  state.reminderPreference?.enabled != false,
            )
            .toList()
          ..sort(
            (a, b) => a.upcomingHike.departureTime.compareTo(
              b.upcomingHike.departureTime,
            ),
          );
    final pending = await notifications.pending();
    final rows = await database.loadHikeReminders();
    // Leave capacity for native safety/check-in notifications on iOS (64 total).
    final ownIds = rows.map((row) => row.notificationId).toSet();
    final capacity =
        (48 - pending.keys.where((id) => !ownIds.contains(id)).length).clamp(
          0,
          48,
        );
    final desired = <String, LocalPlannedHikeState>{};
    for (final state in states) {
      if (desired.length >= capacity) break;
      desired.putIfAbsent(reminderKey(state.upcomingHike), () => state);
    }
    for (final row in rows) {
      if (!_active) return;
      if (row.ownerPhoneNumber == ownerPhoneNumber &&
          desired.containsKey(row.reminderKey)) {
        continue;
      }
      if (row.status == 'scheduled' ||
          pending.containsKey(row.notificationId)) {
        await notifications.cancel(row.notificationId);
      }
      if (row.status != 'delivered') {
        await database.setHikeReminderStatus(row.notificationId, 'cancelled');
      }
    }
    for (final entry in desired.entries) {
      if (!_active) return;
      final hike = entry.value.upcomingHike;
      final title = 'Your hike is coming up';
      final start = hike.departureTime.toLocal();
      final time =
          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
      final body =
          '${hike.trailName} starts ${start.day}/${start.month}/${start.year} at $time. Remember to charge your phone to 100% before your hike.';
      final payload = jsonEncode({
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
      });
      final hash = stableContentHash([title, body, payload]);
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
        remindAt: reminderTime(hike.departureTime, now),
        contentHash: hash,
      );
      if (!_active || row.status == 'delivered') continue;
      if (row.status == 'scheduled' &&
          !row.remindAt.isAfter(now) &&
          !pending.containsKey(row.notificationId)) {
        await database.setHikeReminderStatus(row.notificationId, 'delivered');
        continue;
      }
      if (row.status == 'scheduled' &&
          pending[row.notificationId] == payload &&
          previous?.contentHash == hash) {
        continue;
      }
      // Local creation, identity reconciliation and repeated refreshes share an ID.
      if (row.remindAt.isAfter(now)) {
        await notifications.schedule(
          row.notificationId,
          row.remindAt,
          title,
          body,
          payload,
        );
        await database.setHikeReminderStatus(row.notificationId, 'scheduled');
      } else {
        if (pending.containsKey(row.notificationId)) {
          await notifications.cancel(row.notificationId);
        }
        await notifications.show(row.notificationId, title, body, payload);
        await database.setHikeReminderStatus(row.notificationId, 'delivered');
      }
    }
  }

  Future<void> stopForSignOut() async {
    _active = false;
    await _work.catchError((Object _) {});
    for (final row in await database.loadHikeReminders()) {
      if (row.ownerPhoneNumber != ownerPhoneNumber) continue;
      await notifications.cancel(row.notificationId);
      if (row.status != 'delivered') {
        await database.setHikeReminderStatus(row.notificationId, 'cancelled');
      }
    }
  }
}
