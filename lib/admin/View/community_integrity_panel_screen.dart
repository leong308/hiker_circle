part of '../community_integrity_panel_feature.dart';

/// Presents the same flagged-content queue from Circle with shared page styling.
class CommunityFlaggedContentPage extends StatelessWidget {
  /// Keeps the administrator guard in front of any queue subscription.
  const CommunityFlaggedContentPage({
    super.key,
    required this.isAdmin,
    this.onOpenHistory,
    this.panel = const CommunityIntegrityPanel(),
  });

  final bool isAdmin;
  final VoidCallback? onOpenHistory;
  final CommunityIntegrityPanel panel;

  /// Uses Profile's header spacing, background and readable content width.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0C120F)
        : const Color(0xFFF2F2F7),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Flagged content',
                  subtitle: 'Review community posts and comments',
                  onBack: () => Navigator.of(context).maybePop(),
                  actions: [
                    if (isAdmin && onOpenHistory != null)
                      PageHeaderAction(
                        tooltip: 'Moderation history',
                        icon: Icons.history_rounded,
                        onPressed: onOpenHistory,
                        color: Theme.of(context).colorScheme.primary,
                        surface: Theme.of(context).colorScheme.surface,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                if (isAdmin)
                  panel
                else
                  const AdminEmptyState(
                    title: 'Administrator access required',
                    message:
                        'Only administrators can review flagged community content.',
                    icon: Icons.lock_outline_rounded,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
