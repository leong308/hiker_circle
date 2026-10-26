part of '../device_notifications_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _DeviceNotificationsPageDataActions {
  /// Binds mark device notification opened to the selected data source.
  static Future<void> Function({
    required int id,
    required String ownerPhoneNumber,
  })
  markDeviceNotificationOpened(LocalSessionDatabase receiver) =>
      receiver.markDeviceNotificationOpened;
}
