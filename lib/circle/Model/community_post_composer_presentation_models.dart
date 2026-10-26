part of '../community_post_composer_feature.dart';

/// Carry caption, selected image bytes and the optional hike attachment as one editor value.
class CommunityPostDraft {
  /// Creates community post draft.
  const CommunityPostDraft({
    required this.caption,
    required this.images,
    required this.includeHike,
  });

  final String caption;
  final List<CommunityPostImageUpload> images;
  final bool includeHike;
}
