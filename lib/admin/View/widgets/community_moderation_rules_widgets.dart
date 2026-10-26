part of '../../community_moderation_rules_feature.dart';

/// Displays the community moderation rules button.
class CommunityModerationRulesButton extends StatelessWidget {
  /// Creates community moderation rules button.
  const CommunityModerationRulesButton({super.key, this.compact = false});
  final bool compact;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    /// Opens rules.
    void openRules() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AdminUi.surface(context),
      showDragHandle: true,
      builder: (_) => const _ModerationRulesSheet(),
    );
    return compact
        ? IconButton(
            tooltip: 'Moderation rules',
            onPressed: openRules,
            icon: const Icon(Icons.policy_outlined),
          )
        : OutlinedButton.icon(
            icon: const Icon(Icons.policy_outlined),
            label: const Text('Moderation rules'),
            onPressed: openRules,
          );
  }
}

/// Displays the source label.
class _SourceLabel extends StatelessWidget {
  /// Creates source label.
  const _SourceLabel({
    required this.icon,
    required this.label,
    required this.description,
  });
  final IconData icon;
  final String label, description;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: AdminUi.green(context)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(color: AdminUi.muted(context), height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Displays the rule section.
class _RuleSection extends StatelessWidget {
  /// Creates rule section.
  const _RuleSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });
  final IconData icon;
  final String title, description;
  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: AdminUi.green(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: TextStyle(color: AdminUi.muted(context), height: 1.5),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}
