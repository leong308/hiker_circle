part of '../device_notifications_page_feature.dart';

/// Defines the read filter choices.
enum _ReadFilter { all, unread, read }

/// Defines the notification category choices.
enum _NotificationCategory {
  all,
  safety,
  hikes,
  messages,
  community,
  achievements,
  account,
  other,
}

/// Defines the notification action choices.
enum _NotificationAction { toggleRead, remove }

/// Defines the notification bulk action choices.
enum _NotificationBulkAction { readAll, clearAll }

/// Provides helpers for `_ReadFilter`.
extension on _ReadFilter {
  /// Returns label.
  String get label => switch (this) {
    _ReadFilter.all => 'All notifications',
    _ReadFilter.unread => 'Unread',
    _ReadFilter.read => 'Read',
  };
}

/// Provides helpers for `_NotificationCategory`.
extension on _NotificationCategory {
  /// Returns label.
  String get label => switch (this) {
    _NotificationCategory.all => 'All types',
    _NotificationCategory.safety => 'Safety alerts',
    _NotificationCategory.hikes => 'Hikes & reminders',
    _NotificationCategory.messages => 'Messages',
    _NotificationCategory.community => 'Buddies & circle',
    _NotificationCategory.achievements => 'Achievements',
    _NotificationCategory.account => 'Account & security',
    _NotificationCategory.other => 'Other updates',
  };

  /// Returns icon.
  IconData get icon => switch (this) {
    _NotificationCategory.safety => Icons.health_and_safety_outlined,
    _NotificationCategory.hikes => Icons.hiking_rounded,
    _NotificationCategory.messages => Icons.chat_bubble_outline_rounded,
    _NotificationCategory.community => Icons.people_outline_rounded,
    _NotificationCategory.achievements => Icons.emoji_events_outlined,
    _NotificationCategory.account => Icons.shield_outlined,
    _ => Icons.notifications_none_rounded,
  };
}

/// Computes category for.
_NotificationCategory _categoryFor(String type) {
  final value = type.toLowerCase();

  /// Computes contains any.
  bool containsAny(List<String> words) => words.any(value.contains);
  if (value.contains('achievement')) return _NotificationCategory.achievements;
  if (containsAny([
    'sos',
    'alert',
    'safety',
    'hazard',
    'deviation',
    'warning',
  ])) {
    return _NotificationCategory.safety;
  }
  if (containsAny(['account', 'security', 'login', 'password', 'mfa'])) {
    return _NotificationCategory.account;
  }
  if (value.contains('chat')) return _NotificationCategory.messages;
  if (containsAny(['buddy', 'friend', 'circle'])) {
    return _NotificationCategory.community;
  }
  if (containsAny(['hike', 'team', 'reminder', 'weather'])) {
    return _NotificationCategory.hikes;
  }
  return _NotificationCategory.other;
}

/// Displays the device notifications page.
class DeviceNotificationsPage extends StatefulWidget {
  /// Creates device notifications page.
  const DeviceNotificationsPage({
    super.key,
    required this.phoneNumber,
    this.onOpenDeepLink,
    this.database,
  });
  final String phoneNumber;
  final Future<void> Function(String link)? onOpenDeepLink;
  final LocalSessionDatabase? database;

  /// Creates the presentation state for this widget.
  @override
  State<DeviceNotificationsPage> createState() =>
      _DeviceNotificationsPageState();
}

/// Manages the device notifications page presentation and lifecycle.
class _DeviceNotificationsPageState extends State<DeviceNotificationsPage>
    with WidgetsBindingObserver {
  late final _DeviceNotificationsPageStateViewModel _screenModel;

  /// Returns database.
  LocalSessionDatabase get _database => _screenModel.stateDatabase;

  /// Updates database.
  set _database(LocalSessionDatabase value) =>
      _screenModel.stateDatabase = value;

  /// Returns busy ids.
  Set<int> get _busyIds => _screenModel.stateBusyIds;

  /// Returns next notification timer.
  Timer? get _nextNotificationTimer => _screenModel.stateNextNotificationTimer;

  /// Returns bulk busy.
  bool get _bulkBusy => _screenModel.stateBulkBusy;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late Future<List<DeviceNotificationRecord>> _notificationsFuture;
  final _scroll = ScrollController();

  StreamSubscription<String>? _changes;

  _NotificationFilters _filters = const _NotificationFilters();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _DeviceNotificationsPageStateViewModel(
      readPhoneNumber: () => widget.phoneNumber,
      effectRefresh: _refresh,
      effectShowMessage: _showMessage,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentOpenFiltersEffect1 = _presentOpenFiltersEffect1;
    _screenModel.effectSetFilters = _setFilters;

    _database = widget.database ?? LocalSessionDatabase();
    WidgetsBinding.instance.addObserver(this);
    _changes = LocalSessionDatabase.deviceNotificationChanges.listen((owner) {
      if (owner == widget.phoneNumber && mounted) unawaited(_refresh());
    });
    _notificationsFuture = _loadNotifications();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _nextNotificationTimer?.cancel();
    _scroll.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  /// Delegates load notifications to the ViewModel.
  Future<List<DeviceNotificationRecord>> _loadNotifications() =>
      _screenModel.commandLoadNotifications();

  /// Refreshes.
  Future<void> _refresh() async {
    if (!mounted) return;
    final next = _loadNotifications();
    setState(() {
      _notificationsFuture = next;
    });
    try {
      await next;
    } catch (_) {
      // The list provides a retry action for this failed load.
    }
  }

  /// Sets filters.
  void _setFilters(_NotificationFilters filters) {
    setState(() => _filters = filters);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Delegates open filters to the ViewModel.
  Future<void> _openFilters(List<DeviceNotificationRecord> notifications) =>
      _screenModel.commandOpenFilters(notifications);

  /// Delegates update notification to the ViewModel.
  Future<void> _updateNotification(
    DeviceNotificationRecord notification,
    Future<void> Function() action,
  ) => _screenModel.commandUpdateNotification(notification, action);

  /// Opens notification.
  Future<void> _openNotification(
    DeviceNotificationRecord notification,
  ) => _updateNotification(notification, () async {
    if (!notification.isOpened) {
      await _DeviceNotificationsPageDataActions.markDeviceNotificationOpened(
        _database,
      )(ownerPhoneNumber: widget.phoneNumber, id: notification.id);
    }
    if (!mounted) return;
    final open = widget.onOpenDeepLink;
    if (open != null && notification.deepLink.trim().isNotEmpty) {
      Navigator.of(context).pop();
      await open(notification.deepLink);
    }
  });

  /// Delegates toggle favourite to the ViewModel.
  Future<void> _toggleFavourite(DeviceNotificationRecord notification) =>
      _screenModel.commandToggleFavourite(notification);

  /// Delegates handle action to the ViewModel.
  Future<void> _handleAction(
    DeviceNotificationRecord notification,
    _NotificationAction action,
  ) => _screenModel.commandHandleAction(notification, action);

  /// Delegates handle bulk action to the ViewModel.
  Future<void> _handleBulkAction(_NotificationBulkAction action) =>
      _screenModel.commandHandleBulkAction(action);

  /// Shows message.
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Computes constrain.
  Widget _constrain(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0C120F)
          : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: FutureBuilder<List<DeviceNotificationRecord>>(
          future: _notificationsFuture,
          builder: (context, snapshot) {
            final notifications =
                snapshot.data ?? const <DeviceNotificationRecord>[];
            final unread = notifications.where((item) => !item.isOpened).length;
            final visible = notifications.where(_filters.matches).toList()
              ..sort((a, b) {
                final time = b.receivedAt.compareTo(a.receivedAt);
                return time == 0 ? b.id.compareTo(a.id) : time;
              });
            final loading =
                snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData;
            return RefreshIndicator(
              onRefresh: _refresh,
              color: colors.primary,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                    sliver: SliverToBoxAdapter(
                      child: _constrain(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PageHeader(
                              title: 'Notifications',
                              subtitle: !snapshot.hasData
                                  ? 'Updates from your hikes and circle'
                                  : unread == 0
                                  ? 'You’re all caught up'
                                  : '$unread unread',
                              onBack: () => Navigator.of(context).pop(),
                              actions: [
                                Semantics(
                                  selected: _filters.isActive,
                                  child: Badge(
                                    isLabelVisible: _filters.isActive,
                                    smallSize: 7,
                                    backgroundColor: colors.primary,
                                    child: PageHeaderAction(
                                      tooltip: 'Filter notifications',
                                      icon: Icons.filter_list_rounded,
                                      onPressed: () => unawaited(
                                        _openFilters(notifications),
                                      ),
                                      color: colors.primary,
                                      surface: colors.surface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!loading &&
                                !snapshot.hasError &&
                                notifications.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_filters.description} · ${visible.length}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                          ),
                                    ),
                                  ),
                                  SizedBox.square(
                                    dimension: 44,
                                    child:
                                        PopupMenuButton<
                                          _NotificationBulkAction
                                        >(
                                          tooltip: 'Notification actions',
                                          enabled:
                                              !_bulkBusy && _busyIds.isEmpty,
                                          icon: Icon(
                                            Icons.more_horiz_rounded,
                                            color: colors.onSurfaceVariant,
                                            size: 21,
                                          ),
                                          padding: EdgeInsets.zero,
                                          onSelected: (action) => unawaited(
                                            _handleBulkAction(action),
                                          ),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: _NotificationBulkAction
                                                  .readAll,
                                              enabled: unread > 0,
                                              child: const Text(
                                                'Mark all as read',
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: _NotificationBulkAction
                                                  .clearAll,
                                              child: Text(
                                                'Clear all notifications',
                                                style: TextStyle(
                                                  color: colors.error,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (loading)
                    SliverToBoxAdapter(
                      child: _constrain(
                        const HikerCircleLoadingView(
                          message: 'Loading notifications…',
                          padding: EdgeInsets.symmetric(vertical: 28),
                        ),
                      ),
                    )
                  else if (snapshot.hasError)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      sliver: SliverToBoxAdapter(
                        child: _constrain(
                          _NotificationEmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: 'Couldn’t load notifications',
                            message: 'Please try again.',
                            actionLabel: 'Retry',
                            onAction: () => unawaited(_refresh()),
                          ),
                        ),
                      ),
                    )
                  else if (visible.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      sliver: SliverToBoxAdapter(
                        child: _constrain(
                          _NotificationEmptyState(
                            icon: _filters.isActive
                                ? Icons.filter_list_off_rounded
                                : Icons.notifications_none_rounded,
                            title: _filters.isActive
                                ? 'No matching notifications'
                                : 'No notifications yet',
                            message: _filters.isActive
                                ? 'Try a different filter to see more updates.'
                                : 'Your hike reminders, messages and updates will appear here.',
                            actionLabel: _filters.isActive
                                ? 'Clear filters'
                                : 'Refresh',
                            onAction: _filters.isActive
                                ? () =>
                                      _setFilters(const _NotificationFilters())
                                : () => unawaited(_refresh()),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                      sliver: SliverList.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final notification = visible[index];
                          return _constrain(
                            _DeviceNotificationTile(
                              key: ValueKey('notification-${notification.id}'),
                              notification: notification,
                              busy:
                                  _bulkBusy ||
                                  _busyIds.contains(notification.id),
                              onTap: () =>
                                  unawaited(_openNotification(notification)),
                              onFavourite: () =>
                                  unawaited(_toggleFavourite(notification)),
                              onAction: (action) => unawaited(
                                _handleAction(notification, action),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Presents the open filters effect1 UI.
  Future<_NotificationFilters?> _presentOpenFiltersEffect1(
    List<DeviceNotificationRecord> notifications,
  ) => showModalBottomSheet<_NotificationFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _NotificationFiltersSheet(
      initial: _filters,
      notifications: notifications,
    ),
  );
}

/// Displays the notification filters sheet.
class _NotificationFiltersSheet extends StatefulWidget {
  /// Creates notification filters sheet.
  const _NotificationFiltersSheet({
    required this.initial,
    required this.notifications,
  });
  final _NotificationFilters initial;
  final List<DeviceNotificationRecord> notifications;

  /// Creates the presentation state for this widget.
  @override
  State<_NotificationFiltersSheet> createState() =>
      _NotificationFiltersSheetState();
}

/// Manages the notification filters sheet presentation and lifecycle.
class _NotificationFiltersSheetState extends State<_NotificationFiltersSheet> {
  late _ReadFilter _read = widget.initial.read;
  late bool _favouritesOnly = widget.initial.favouritesOnly;
  late _NotificationCategory _category = widget.initial.category;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final selection = _NotificationFilters(
      read: _read,
      favouritesOnly: _favouritesOnly,
      category: _category,
    );
    final count = widget.notifications.where(selection.matches).length;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter notifications',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _read = _ReadFilter.all;
                        _favouritesOnly = false;
                        _category = _NotificationCategory.all;
                      }),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<_ReadFilter>(
                  initialValue: _read,
                  key: ValueKey('notification-read-filter-$_read'),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Read status'),
                  items: [
                    for (final value in _ReadFilter.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _read = value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<_NotificationCategory>(
                  initialValue: _category,
                  key: ValueKey('notification-type-filter-$_category'),
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(
                    labelText: 'Notification type',
                  ),
                  selectedItemBuilder: (_) => [
                    for (final value in _NotificationCategory.values)
                      Text(
                        value.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                  items: [
                    for (final value in _NotificationCategory.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favourites only'),
                  value: _favouritesOnly,
                  onChanged: (value) => setState(() => _favouritesOnly = value),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(selection),
                  child: Text(
                    'Show $count ${count == 1 ? "notification" : "notifications"}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Computes notification time label.
String _notificationTimeLabel(DateTime receivedAt) {
  final local = receivedAt.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '${local.day}/${local.month} $hour:${local.minute.toString().padLeft(2, '0')}${local.hour >= 12 ? "PM" : "AM"}';
}
