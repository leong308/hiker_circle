part of '../trail_page_feature.dart';

/// Represents pending trail image.
class _PendingTrailImage {
  /// Creates pending trail image.
  const _PendingTrailImage({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}
