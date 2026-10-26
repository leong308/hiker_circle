import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../app/Data/local_session_database.dart';
import '../Model/achievement_notification.dart';

/// Represents achievement notifications.
abstract interface class AchievementNotifications {
  /// Shows.
  Future<void> show(AchievementNotification notification);
}

/// Represents device achievement notifications.
class DeviceAchievementNotifications implements AchievementNotifications {
  /// Creates device achievement notifications.
  DeviceAchievementNotifications(this.plugin);
  final FlutterLocalNotificationsPlugin plugin;

  /// Shows.
  @override
  Future<void> show(AchievementNotification notification) => plugin.show(
    id: notification.id,
    title: notification.title,
    body: notification.body,
    payload: notification.payload,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'hiker_circle_achievements',
        'Achievements',
        channelDescription: 'New achievements earned on this device',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      ),
    ),
  );
}

/// Delivers the durable local outbox without FCM or network access.
class AchievementNotificationDelivery {
  /// Creates achievement notification delivery.
  AchievementNotificationDelivery({
    required this.database,
    required this.owner,
    required this.notifications,
  });
  final LocalSessionDatabase database;
  final String owner;
  final AchievementNotifications notifications;
  Future<void> _tail = Future.value();
  bool _active = true;

  /// Flushes.
  Future<void> flush({bool showBanners = true}) {
    final next = _tail
        .catchError((Object _) {})
        .then((_) => _flush(showBanners));
    _tail = next;
    return next;
  }

  /// Flushes.
  Future<void> _flush(bool showBanners) async {
    if (!_active) return;
    await database.recordPendingAchievementNotificationHistory(owner);
    if (!showBanners) return;
    for (final row in await database.pendingAchievementNotifications(owner)) {
      if (!_active) return;
      final notification = AchievementNotification(owner: owner, row: row);
      await notifications.show(notification);
      await database.markAchievementNotificationDelivered(
        owner,
        notification.achievementId,
      );
    }
  }

  /// Releases resources owned by this instance.
  void dispose() => _active = false;
}
