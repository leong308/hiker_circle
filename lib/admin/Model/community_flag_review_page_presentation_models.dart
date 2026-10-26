part of '../community_flag_review_page_feature.dart';

/// Represents review content.
class _ReviewContent {
  /// Creates review content.
  const _ReviewContent({
    required this.source,
    this.parent,
    this.parentUnavailable = false,
  });
  final Map<String, dynamic>? source, parent;
  final bool parentUnavailable;
}
