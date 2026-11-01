part of '../group_chat_detail_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _GroupChatDetailPageDataActions {
  /// Binds delete chat for user to the selected data source.
  static Future<void> Function({
    required String chatId,
    required List<String> participantPhones,
    required String senderName,
    required AppSession session,
  })
  deleteChatForUser(HikerCircleFirebaseRepository receiver) =>
      receiver.deleteChatForUser;

  /// Binds set group chat muted until to the selected data source.
  static Future<void> Function({
    required String chatId,
    DateTime? mutedUntil,
    required AppSession session,
  })
  setGroupChatMutedUntil(HikerCircleFirebaseRepository receiver) =>
      receiver.setGroupChatMutedUntil;

  /// Binds send group chat message to the selected data source.
  static Future<void> Function({
    ChatAttachment? attachment,
    required String chatId,
    required String localId,
    required String senderName,
    required String senderPhone,
    required DateTime sentAt,
    required String text,
  })
  sendGroupChatMessage(HikerCircleFirebaseRepository receiver) =>
      receiver.sendGroupChatMessage;

  /// Binds flush pending messages to the selected data source.
  static Future<void> Function({String? ownerPhoneNumber}) flushPendingMessages(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.flushPendingMessages;

  /// Binds send chat reminder to the selected data source.
  static Future<Map<String, dynamic>> Function({
    required String chatId,
    required String recipientPhone,
  })
  sendChatReminder(HikerCircleFirebaseRepository receiver) =>
      receiver.sendChatReminder;
}
