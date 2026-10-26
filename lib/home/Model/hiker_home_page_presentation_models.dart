part of '../hiker_home_page_feature.dart';

/// Represents pending fcm open.
class _PendingFcmOpen {
  /// Creates pending fcm open.
  const _PendingFcmOpen({
    required this.key,
    required this.deepLink,
    required this.title,
    required this.body,
  });

  final String key;
  final String? deepLink;
  final String? title;
  final String? body;
}
