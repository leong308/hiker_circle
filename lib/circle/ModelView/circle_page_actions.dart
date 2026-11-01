part of '../circle_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _CirclePageDataActions {
  /// Binds load group chat muted until to the selected data source.
  static Future<DateTime?> Function({
    required String chatId,
    required AppSession session,
  })
  loadGroupChatMutedUntil(HikerCircleFirebaseRepository receiver) =>
      receiver.loadGroupChatMutedUntil;

  /// Binds set group chat muted until to the selected data source.
  static Future<void> Function({
    required String chatId,
    DateTime? mutedUntil,
    required AppSession session,
  })
  setGroupChatMutedUntil(HikerCircleFirebaseRepository receiver) =>
      receiver.setGroupChatMutedUntil;

  /// Binds delete chat for user to the selected data source.
  static Future<void> Function({
    required String chatId,
    required List<String> participantPhones,
    required String senderName,
    required AppSession session,
  })
  deleteChatForUser(HikerCircleFirebaseRepository receiver) =>
      receiver.deleteChatForUser;

  /// Binds send buddy request to the selected data source.
  static Future<void> Function({
    required String buddyPhoneNumber,
    required AppSession session,
  })
  sendBuddyRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.sendBuddyRequest;

  /// Binds open direct chat to the selected data source.
  static Future<GroupChat> Function({
    required String otherDisplayName,
    required String otherPhoneNumber,
    required AppSession session,
  })
  openDirectChat(HikerCircleFirebaseRepository receiver) =>
      receiver.openDirectChat;

  /// Binds load community profile to the selected data source.
  static Future<Map<String, dynamic>?> Function({
    String phoneNumber,
    String userId,
  })
  loadCommunityProfile(HikerCircleFirebaseRepository receiver) =>
      receiver.loadCommunityProfile;

  /// Binds load public hiker profile to the selected data source.
  static Future<Map<String, dynamic>> Function({
    String phoneNumber,
    String userId,
  })
  loadPublicHikerProfile(HikerCircleFirebaseRepository receiver) =>
      receiver.loadPublicHikerProfile;

  /// Binds load community post draft to the selected data source.
  static Future<CommunityPostDraftData?> Function({
    required String draftKey,
    required AppSession session,
  })
  loadCommunityPostDraft(HikerCircleFirebaseRepository receiver) =>
      receiver.loadCommunityPostDraft;

  /// Binds save community post draft to the selected data source.
  static Future<void> Function({
    required String caption,
    required String draftKey,
    required List<CommunityPostImageUpload> images,
    required bool includeHike,
    required String postId,
    required AppSession session,
  })
  saveCommunityPostDraft(HikerCircleFirebaseRepository receiver) =>
      receiver.saveCommunityPostDraft;

  /// Binds delete community post draft to the selected data source.
  static Future<void> Function({
    required String draftKey,
    required AppSession session,
  })
  deleteCommunityPostDraft(HikerCircleFirebaseRepository receiver) =>
      receiver.deleteCommunityPostDraft;

  /// Binds create community post to the selected data source.
  static Future<void> Function({
    ActiveHikeSession? activeHike,
    required String caption,
    List<CommunityPostImageUpload> images,
    String? postId,
    required AppSession session,
    String? trailId,
  })
  createCommunityPost(HikerCircleFirebaseRepository receiver) =>
      receiver.createCommunityPost;

  /// Binds watch buddy relationships to the selected data source.
  static Stream<BuddyRelationships> Function({required AppSession session})
  watchBuddyRelationships(HikerCircleFirebaseRepository receiver) =>
      receiver.watchBuddyRelationships;

  /// Binds add community comment to the selected data source.
  static Future<void> Function({
    required String body,
    String? commentId,
    required String postId,
    required AppSession session,
  })
  addCommunityComment(HikerCircleFirebaseRepository receiver) =>
      receiver.addCommunityComment;

  /// Binds remove admin community comment to the selected data source.
  static Future<void> Function({
    required String commentId,
    required String postId,
    required AppSession session,
  })
  removeAdminCommunityComment(HikerCircleFirebaseRepository receiver) =>
      receiver.removeAdminCommunityComment;

  /// Binds set group chat notifications enabled to the selected data source.
  static Future<void> Function({
    required bool enabled,
    required AppSession session,
  })
  setGroupChatNotificationsEnabled(HikerCircleFirebaseRepository receiver) =>
      receiver.setGroupChatNotificationsEnabled;
}
