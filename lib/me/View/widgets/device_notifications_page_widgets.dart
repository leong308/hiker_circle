part of '../../device_notifications_page_feature.dart';

/// Displays the device notification tile.
class _DeviceNotificationTile extends StatelessWidget {
  /// Creates device notification tile.
  const _DeviceNotificationTile({
    super.key,
    required this.notification,
    required this.busy,
    required this.onTap,
    required this.onFavourite,
    required this.onAction,
  });
  final DeviceNotificationRecord notification;
  final bool busy;
  final VoidCallback onTap, onFavourite;
  final ValueChanged<_NotificationAction> onAction;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final unread = !notification.isOpened;
    final title = notification.title.trim().isEmpty
        ? 'HikerCircle update'
        : notification.title.trim();
    final body = notification.body.trim();
    final accent = unread ? colors.primary : colors.onSurfaceVariant;
    final card = Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: unread
            ? BorderSide.none
            : BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _categoryFor(notification.type).icon,
                    color: accent,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: colors.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _notificationTimeLabel(notification.receivedAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: notification.isStarred
                              ? 'Remove from favourites'
                              : 'Add to favourites',
                          onPressed: busy ? null : onFavourite,
                          isSelected: notification.isStarred,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          iconSize: 20,
                          icon: Icon(
                            Icons.star_border_rounded,
                            color: colors.onSurfaceVariant,
                          ),
                          selectedIcon: const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFE5A027),
                          ),
                        ),
                        SizedBox.square(
                          dimension: 44,
                          child: PopupMenuButton<_NotificationAction>(
                            tooltip: 'Notification options',
                            enabled: !busy,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                            onSelected: onAction,
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: _NotificationAction.toggleRead,
                                child: Text(
                                  unread ? 'Mark as read' : 'Mark as unread',
                                ),
                              ),
                              PopupMenuItem(
                                value: _NotificationAction.remove,
                                child: Text(
                                  'Remove notification',
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: unread ? 'Unread notification' : 'Read notification',
      child: unread
          ? RunningBorder(
              color: const Color(0xFF34A853),
              radius: 14,
              child: card,
            )
          : card,
    );
  }
}

/// Displays the notification empty state.
class _NotificationEmptyState extends StatelessWidget {
  /// Creates notification empty state.
  const _NotificationEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title, message, actionLabel;
  final VoidCallback onAction;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colors.primary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
