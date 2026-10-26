part of '../device_notifications_page_feature.dart';

/// Represents notification filters.
class _NotificationFilters {
  /// Creates notification filters.
  const _NotificationFilters({
    this.read = _ReadFilter.all,
    this.favouritesOnly = false,
    this.category = _NotificationCategory.all,
  });
  final _ReadFilter read;
  final bool favouritesOnly;
  final _NotificationCategory category;

  /// Returns is active.
  bool get isActive =>
      read != _ReadFilter.all ||
      favouritesOnly ||
      category != _NotificationCategory.all;

  /// Returns description.
  String get description => !isActive
      ? 'All notifications'
      : [
          if (read != _ReadFilter.all) read.label,
          if (favouritesOnly) 'Favourites',
          if (category != _NotificationCategory.all) category.label,
        ].join(' · ');

  /// Computes matches.
  bool matches(DeviceNotificationRecord notification) =>
      (read == _ReadFilter.all ||
          (read == _ReadFilter.read) == notification.isOpened) &&
      (!favouritesOnly || notification.isStarred) &&
      (category == _NotificationCategory.all ||
          _categoryFor(notification.type) == category);
}
