// Records device-generated and push messages in account-scoped local history.
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../app/Data/local_session_database.dart';

/// Represents device notification log service.
abstract final class DeviceNotificationLogService {
  /// Records local notification.
  static Future<void> recordLocalNotification({
    required String ownerPhoneNumber,
    required String messageId,
    required String title,
    required String body,
    required String type,
    required String deepLink,
    Map<String, dynamic> data = const {},
    DateTime? receivedAt,
  }) async {
    try {
      await LocalSessionDatabase().saveDeviceNotification(
        ownerPhoneNumber: ownerPhoneNumber,
        messageId: messageId,
        title: title,
        body: body,
        type: type,
        deepLink: deepLink,
        data: data,
        receivedAt: receivedAt,
        source: 'local',
      );
    } catch (_) {
      // History must not prevent an urgent device notification or speech alert.
    }
  }

  /// Records fcm message.
  static Future<void> recordFcmMessage(
    RemoteMessage message, {
    String? ownerPhoneNumber,
    bool opened = false,
    String source = 'fcm',
  }) async {
    try {
      final database = LocalSessionDatabase();
      final phoneNumber =
          ownerPhoneNumber ?? (await database.loadSession())?.phoneNumber;
      if (phoneNumber == null || phoneNumber.trim().isEmpty) {
        return;
      }
      final data = <String, String>{
        for (final entry in message.data.entries)
          entry.key: entry.value?.toString() ?? '',
      };
      await database.saveDeviceNotification(
        ownerPhoneNumber: phoneNumber,
        messageId: message.messageId ?? '',
        title: _stringFromMessageData(
          data['title'],
          message.notification?.title ?? 'HikerCircle update',
        ),
        body: _stringFromMessageData(
          data['body'],
          message.notification?.body ?? 'Tap to view details.',
        ),
        type: _stringFromMessageData(data['type'], ''),
        deepLink: _stringFromMessageData(data['deepLink'], ''),
        data: data,
        receivedAt: message.sentTime ?? DateTime.now(),
        openedAt: opened ? DateTime.now() : null,
        source: source,
      );
    } catch (_) {
      return;
    }
  }

  /// Computes string from message data.
  static String _stringFromMessageData(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }
}
