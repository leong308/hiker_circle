// CommunityPostDraftData preserves a stable publish ID, caption and ordered CommunityPostImageUpload
// bytes for durable composer retries.
import 'dart:typed_data';

/// Represents community post image upload.
class CommunityPostImageUpload {
  /// Creates community post image upload.
  const CommunityPostImageUpload({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}

/// Represents community post draft data.
class CommunityPostDraftData {
  /// Creates community post draft data.
  const CommunityPostDraftData({
    required this.postId,
    required this.caption,
    this.images = const [],
    this.includeHike = false,
  });

  final String postId;
  final String caption;
  final List<CommunityPostImageUpload> images;
  final bool includeHike;
}
