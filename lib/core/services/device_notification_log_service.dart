import 'package:firebase_messaging/firebase_messaging.dart';

import '../../app/Data/local_session_database.dart';

abstract final class DeviceNotificationLogService {
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

  static String _stringFromMessageData(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }
}
