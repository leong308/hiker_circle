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
