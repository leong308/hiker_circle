part of '../device_notifications_page_feature.dart';

/// Owns the state and non-visual actions of DeviceNotificationsPage.
class _DeviceNotificationsPageStateViewModel extends ChangeNotifier {
  /// Creates device notifications page state view model.
  _DeviceNotificationsPageStateViewModel({
    required this.readPhoneNumber,
    required this.effectRefresh,
    required this.effectShowMessage,
  });
  final String Function() readPhoneNumber;
  final Future<void> Function() effectRefresh;
  final void Function(String message) effectShowMessage;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final LocalSessionDatabase stateDatabase;

  final stateBusyIds = <int>{};

  Timer? stateNextNotificationTimer;

  int stateLoadGeneration = 0;

  bool stateBulkBusy = false;

  /// Loads notifications.
  Future<List<DeviceNotificationRecord>> commandLoadNotifications() async {
    final generation = ++stateLoadGeneration;
    final asOf = DateTime.now();
    final rows = await stateDatabase.loadDeviceNotifications(
      ownerPhoneNumber: readPhoneNumber(),
      limit: 500,
      asOf: asOf,
    );
    final next = await stateDatabase.nextDeviceNotificationAt(
      readPhoneNumber(),
      asOf: asOf,
    );
    if (mounted && generation == stateLoadGeneration) {
      stateNextNotificationTimer?.cancel();
      if (next != null) {
        final delay =
            next.difference(DateTime.now()) + const Duration(milliseconds: 10);
        stateNextNotificationTimer = Timer(
          delay.isNegative ? Duration.zero : delay,
          () {
            if (mounted) unawaited(effectRefresh());
          },
        );
      }
    }
    return rows;
  }

  /// Updates notification.
  Future<void> commandUpdateNotification(
    DeviceNotificationRecord notification,
    Future<void> Function() action,
  ) async {
    if (stateBulkBusy || !stateBusyIds.add(notification.id)) return;
    _publish(() {});
    try {
      await action();
      if (mounted) await effectRefresh();
    } catch (_) {
      effectShowMessage(
        'This notification couldn’t be updated. Please try again.',
      );
    } finally {
      if (mounted) _publish(() => stateBusyIds.remove(notification.id));
    }
  }

  /// Toggles favourite.
  Future<void> commandToggleFavourite(DeviceNotificationRecord notification) =>
      commandUpdateNotification(
        notification,
        () => stateDatabase.setDeviceNotificationStarred(
          ownerPhoneNumber: readPhoneNumber(),
          id: notification.id,
          isStarred: !notification.isStarred,
        ),
      );

  /// Handles action.
  Future<void> commandHandleAction(
    DeviceNotificationRecord notification,
    _NotificationAction action,
  ) => commandUpdateNotification(
    notification,
    () => switch (action) {
      _NotificationAction.remove => stateDatabase.deleteDeviceNotification(
        ownerPhoneNumber: readPhoneNumber(),
        id: notification.id,
      ),
      _NotificationAction.toggleRead =>
        notification.isOpened
            ? stateDatabase.markDeviceNotificationUnread(
                ownerPhoneNumber: readPhoneNumber(),
                id: notification.id,
              )
            : stateDatabase.markDeviceNotificationOpened(
                ownerPhoneNumber: readPhoneNumber(),
                id: notification.id,
              ),
    },
  );

  /// Handles bulk action.
  Future<void> commandHandleBulkAction(_NotificationBulkAction action) async {
    if (stateBulkBusy || stateBusyIds.isNotEmpty) return;
    _publish(() => stateBulkBusy = true);
    try {
      if (action == _NotificationBulkAction.readAll) {
        await stateDatabase.markAllDeviceNotificationsOpened(
          ownerPhoneNumber: readPhoneNumber(),
        );
      } else {
        await stateDatabase.clearDeviceNotifications(
          ownerPhoneNumber: readPhoneNumber(),
        );
        effectShowMessage('Notifications cleared.');
      }
      if (mounted) await effectRefresh();
    } catch (_) {
      effectShowMessage('Notifications couldn’t be updated. Please try again.');
    } finally {
      if (mounted) _publish(() => stateBulkBusy = false);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<_NotificationFilters?> Function(
    List<DeviceNotificationRecord> notifications,
  )
  effectPresentOpenFiltersEffect1;

  late final void Function(_NotificationFilters filters) effectSetFilters;

  /// Opens filters.
  Future<void> commandOpenFilters(
    List<DeviceNotificationRecord> notifications,
  ) async {
    final filters = await effectPresentOpenFiltersEffect1(notifications);
    if (filters != null && mounted) effectSetFilters(filters);
  }
}
