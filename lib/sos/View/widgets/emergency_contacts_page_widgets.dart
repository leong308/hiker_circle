part of '../../emergency_contacts_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({
    required this.onAction,
    required this.onboardingRequired,
    required this.canContinue,
  });

  final VoidCallback onAction;
  final bool onboardingRequired;
  final bool canContinue;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = !onboardingRequired || canContinue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: PageHeader(
        title: 'Emergency Contacts',
        subtitle: 'Add up to 3 people for SOS alerts',
        leading: onboardingRequired
            ? null
            : PageHeaderAction(
                tooltip: 'Back',
                icon: CupertinoIcons.chevron_back,
                onPressed: onAction,
                color: colors.primary,
                surface: colors.surface,
              ),
        actions: [
          if (onboardingRequired)
            PageHeaderAction(
              tooltip: 'Continue',
              icon: CupertinoIcons.check_mark,
              onPressed: enabled ? onAction : null,
              color: enabled ? colors.primary : colors.onSurfaceVariant,
              surface: colors.surface,
            ),
        ],
      ),
    );
  }
}

/// Displays the summary card.
class _SummaryCard extends StatelessWidget {
  /// Creates summary card.
  const _SummaryCard({
    required this.count,
    required this.max,
    required this.isSaving,
    required this.saveErrorMessage,
  });

  final int count;
  final int max;
  final bool isSaving;
  final String? saveErrorMessage;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.contacts_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count/$max contacts added',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _ContactsColors.textFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isSaving
                            ? 'Saving emergency contacts...'
                            : 'These contacts receive emergency SOS messages first.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _ContactsColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSaving) ...[
              const SizedBox(height: 12),
              const Center(child: HikerCircleMinorLoadingIndicator(size: 24)),
            ],
            if (saveErrorMessage case final message?) ...[
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _ContactsColors.destructiveFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays the status pill.
class _StatusPill extends StatelessWidget {
  /// Creates status pill.
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
