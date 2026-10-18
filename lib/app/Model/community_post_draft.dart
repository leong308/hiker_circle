// CommunityPostDraftData preserves a stable publish ID, caption and ordered CommunityPostImageUpload
// bytes for durable composer retries.
import 'dart:typed_data';

class CommunityPostImageUpload {
  const CommunityPostImageUpload({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}

class CommunityPostDraftData {
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
