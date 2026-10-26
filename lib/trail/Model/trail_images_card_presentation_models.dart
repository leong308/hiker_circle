part of '../trail_images_card_feature.dart';

/// Represents trail image preview.
@immutable
class TrailImagePreview {
  /// Creates trail image preview.
  const TrailImagePreview({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}
