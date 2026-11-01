part of '../community_moderation_controls_feature.dart';

/// Keeps moderation within reach of the feed without changing the hiker tools.
class CommunityModerationToolbar extends StatelessWidget {
  /// Creates community moderation toolbar.
  const CommunityModerationToolbar({
    super.key,
    required this.isAdmin,
    required this.onManagePosts,
    required this.onReviewFlags,
  });

  final bool isAdmin;
  final VoidCallback onManagePosts;
  final VoidCallback onReviewFlags;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (!isAdmin) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Community moderation',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Review flagged content or manage posts. Use a story’s menu to moderate it here.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onReviewFlags,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Flagged content'),
              ),
              OutlinedButton.icon(
                onPressed: onManagePosts,
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('Manage posts'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single story menu separates admin moderation from the author's deletion.
class CommunityPostOptions extends StatelessWidget {
  /// Creates community post options.
  const CommunityPostOptions({
    super.key,
    required this.isAdmin,
    this.isOwnPost = false,
    this.onEdit,
    this.onHide,
    this.onRemove,
    this.onDelete,
    this.busy = false,
  });

  final bool isAdmin;
  final bool isOwnPost;
  final VoidCallback? onEdit;
  final VoidCallback? onHide;
  final VoidCallback? onRemove;
  final VoidCallback? onDelete;
  final bool busy;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final canModerate =
        isAdmin && !isOwnPost && (onHide != null || onRemove != null);
    if (!canModerate && onDelete == null && onEdit == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: canModerate ? 'Moderate story' : 'Story options',
      enabled: !busy,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_horiz_rounded),
      onSelected: (action) {
        switch (action) {
          case 'edit':
            onEdit?.call();
          case 'hide':
            if (isAdmin) onHide?.call();
          case 'remove':
            if (isAdmin) onRemove?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        if (onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: _OptionLabel(icon: Icons.edit_outlined, label: 'Edit story'),
          ),
        if (canModerate) ...[
          const PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text('Admin moderation'),
          ),
          if (onHide != null)
            const PopupMenuItem(
              value: 'hide',
              child: _OptionLabel(
                icon: Icons.visibility_off_outlined,
                label: 'Hide from community',
              ),
            ),
          if (onRemove != null)
            const PopupMenuItem(
              value: 'remove',
              child: _OptionLabel(
                icon: Icons.remove_circle_outline,
                label: 'Remove from community',
              ),
            ),
        ],
        if (canModerate && onDelete != null) const PopupMenuDivider(),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: _OptionLabel(
              icon: Icons.delete_outline_rounded,
              label: 'Delete story',
            ),
          ),
      ],
    );
  }
}
