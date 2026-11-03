import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Describes the local OS permissions needed for saved hike reminders.
class HikeReminderPermissionAccess {
  const HikeReminderPermissionAccess({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    this.checkFailed = false,
    this.isIOS = false,
    this.soundAllowed = true,
  });

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  final bool checkFailed;
  final bool isIOS;
  final bool soundAllowed;

  String? get warning => checkFailed
      ? (isIOS
            ? 'Reminder permissions could not be checked. Review HikerCircle notifications in iPhone Settings.'
            : 'Reminder permissions could not be checked. Review notifications and Alarms & reminders in Android settings.')
      : !notificationsAllowed
      ? 'Notifications are blocked. Enable notification alerts for HikerCircle in Settings to receive reminders.'
      : !exactAlarmsAllowed
      ? 'Android may delay your reminders. Allow Alarms & reminders for HikerCircle to receive them at the selected time.'
      : !soundAllowed
      ? 'Reminder alerts are enabled, but notification sounds are off for HikerCircle in iPhone Settings.'
      : null;
}

/// Ask only from the explicit save action, never during background scheduling.
/// Declining permission leaves the plan save available and returns an honest
/// explanation instead of claiming timely notification delivery.
Future<HikeReminderPermissionAccess> requestHikeReminderPermissions({
  required bool enabled,
  AndroidFlutterLocalNotificationsPlugin? android,
  IOSFlutterLocalNotificationsPlugin? ios,
  bool? isAndroid,
  bool? isIOS,
  Future<bool> Function()? openIosSettings,
}) async {
  final onAndroid =
      isAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  final onIOS =
      isIOS ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  if (!enabled || (!onAndroid && !onIOS)) {
    return const HikeReminderPermissionAccess(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
  }
  if (onIOS) {
    return _requestIosPermissions(ios, openIosSettings);
  }
  var notificationsAllowed = false;
  var exactAlarmsAllowed = false;
  var checkFailed = false;
  try {
    final platform =
        android ??
        FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (platform != null) {
      notificationsAllowed = await platform.areNotificationsEnabled() ?? false;
      if (!notificationsAllowed) {
        notificationsAllowed =
            await platform.requestNotificationsPermission() ?? false;
      }
      if (notificationsAllowed) {
        exactAlarmsAllowed =
            await platform.canScheduleExactNotifications() ?? false;
        if (!exactAlarmsAllowed) {
          exactAlarmsAllowed =
              await platform.requestExactAlarmsPermission() ?? false;
        }
      }
    } else {
      checkFailed = true;
    }
  } catch (_) {
    // A settings/permission failure must not discard the hiking plan.
    checkFailed = true;
  }
  return HikeReminderPermissionAccess(
    notificationsAllowed: notificationsAllowed,
    exactAlarmsAllowed: exactAlarmsAllowed,
    checkFailed: checkFailed,
  );
}

Future<HikeReminderPermissionAccess> _requestIosPermissions(
  IOSFlutterLocalNotificationsPlugin? ios,
  Future<bool> Function()? openSettings,
) async {
  try {
    final platform =
        ios ??
        FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
    if (platform == null) throw StateError('iOS notifications unavailable');
    var options = await platform.checkPermissions();
    if (options == null) throw StateError('Notification status unavailable');
    bool canAlert(NotificationsEnabledOptions value) =>
        value.isEnabled && value.isAlertEnabled && !value.isProvisionalEnabled;
    if (!canAlert(options)) {
      // iOS displays its prompt only when it can still ask. A previous denial
      // requires Settings; requesting again does not reset that denial.
      await platform.requestPermissions(alert: true, sound: true, badge: true);
      options = await platform.checkPermissions();
      if (options == null) throw StateError('Notification status unavailable');
      if (!canAlert(options)) {
        final opened = await (openSettings ?? _openIosNotificationSettings)();
        if (!opened) throw StateError('Notification settings unavailable');
        options = await platform.checkPermissions();
        if (options == null) {
          throw StateError('Notification status unavailable');
        }
      }
    }
    return HikeReminderPermissionAccess(
      notificationsAllowed: canAlert(options),
      // iOS has no separate Android-style exact alarm permission.
      exactAlarmsAllowed: true,
      isIOS: true,
      soundAllowed: options.isSoundEnabled,
    );
  } catch (_) {
    return const HikeReminderPermissionAccess(
      notificationsAllowed: false,
      exactAlarmsAllowed: true,
      checkFailed: true,
      isIOS: true,
    );
  }
}

/// Wait for the user to return before rechecking permissions and saving. All
/// operations use local OS APIs; opening Settings never requires connectivity.
Future<bool> _openIosNotificationSettings() async {
  final returned = Completer<void>();
  final listener = AppLifecycleListener(
    onResume: () {
      if (!returned.isCompleted) returned.complete();
    },
    onDetach: () {
      if (!returned.isCompleted) returned.complete();
    },
  );
  try {
    final opened = await const MethodChannel(
      'hiker_circle/active_hike_live_status',
    ).invokeMethod<bool>('openHikeReminderNotificationSettings');
    if (opened != true) return false;
    await returned.future;
    return true;
  } finally {
    listener.dispose();
  }
}
