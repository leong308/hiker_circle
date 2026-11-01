import 'package:flutter/material.dart';

/// Provides the same directional editing gesture as trail cards without permanently deleting rewards.
class AchievementRuleSwipeCard extends StatefulWidget {
  /// Wraps an admin's card; ordinary hikers receive the unwrapped card instead.
  const AchievementRuleSwipeCard({
    super.key,
    required this.achievementId,
    required this.isActive,
    required this.onEdit,
    required this.onToggleActive,
    required this.child,
    this.enabled = true,
  });

  final String achievementId;
  final bool isActive, enabled;
  final Future<void> Function() onEdit, onToggleActive;
  final Widget child;

  /// Creates the guard that prevents overlapping swipe operations.
  @override
  State<AchievementRuleSwipeCard> createState() =>
      _AchievementRuleSwipeCardState();
}

/// Keeps the card in its grid cell while an edit or confirmation popup is open.
class _AchievementRuleSwipeCardState extends State<AchievementRuleSwipeCard> {
  bool _busy = false;

  /// Runs a single action and always restores the card rather than dismissing it.
  Future<bool> _act(DismissDirection direction) async {
    if (_busy || !widget.enabled) return false;
    setState(() => _busy = true);
    try {
      if (direction == DismissDirection.startToEnd) {
        await widget.onEdit();
      } else {
        await widget.onToggleActive();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  /// Renders edit on the leading side and the current archive action on the trailing side.
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(25),
    child: Dismissible(
      key: ValueKey('achievement-swipe-${widget.achievementId}'),
      direction: widget.enabled && !_busy
          ? DismissDirection.horizontal
          : DismissDirection.none,
      confirmDismiss: _act,
      background: const _AchievementSwipeBackground(
        leading: true,
        label: 'Edit',
        icon: Icons.edit_rounded,
        color: Color(0xff34a853),
      ),
      secondaryBackground: _AchievementSwipeBackground(
        leading: false,
        label: widget.isActive ? 'Archive' : 'Unarchive',
        icon: widget.isActive ? Icons.archive_rounded : Icons.unarchive_rounded,
        color: widget.isActive
            ? const Color(0xffba6710)
            : const Color(0xff34a853),
      ),
      child: widget.child,
    ),
  );
}

/// Shows the available operation while the admin drags a card.
class _AchievementSwipeBackground extends StatelessWidget {
  /// Creates one side of the swipe affordance.
  const _AchievementSwipeBackground({
    required this.leading,
    required this.label,
    required this.icon,
    required this.color,
  });
  final bool leading;
  final String label;
  final IconData icon;
  final Color color;

  /// Keeps labels readable within the narrow achievement grid columns.
  @override
  Widget build(BuildContext context) => Container(
    color: color,
    alignment: leading
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
