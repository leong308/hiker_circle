part of '../community_post_management_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _CommunityPostManagementPageDataActions {
  /// Binds edit admin community post to the selected data source.
  static Future<void> Function({
    required String caption,
    required List<String> imageUrls,
    required Map<String, dynamic> original,
    required AppSession session,
  })
  editAdminCommunityPost(HikerCircleFirebaseRepository receiver) =>
      receiver.editAdminCommunityPost;
}
