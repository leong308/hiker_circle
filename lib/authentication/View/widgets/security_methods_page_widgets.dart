part of '../../security_methods_page_feature.dart';

/// Matches Profile's inset settings surfaces in light and dark appearances.
class _SecurityCard extends StatelessWidget {
  /// Creates a rounded card with consistent padding and an optional soft tint.
  const _SecurityCard({required this.child, this.tinted = false});

  final Widget child;
  final bool tinted;

  /// Builds the shared surface used by security summaries and method groups.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: tinted
          ? colors.primaryContainer.withValues(alpha: 0.42)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Explains current login protection without exposing build configuration.
class _SecurityOverview extends StatelessWidget {
  /// Creates the account's enrollment summary.
  const _SecurityOverview({required this.presentation});

  final SecurityMethodsPresentation presentation;

  /// Presents the same icon, title and supporting-text hierarchy as settings.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _SecurityCard(
      tinted: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecurityGlyph(icon: Icons.verified_user_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    presentation.description,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    presentation.countLabel,
                    style: text.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gives each method the same soft green icon treatment as Profile settings.
class _SecurityGlyph extends StatelessWidget {
  /// Creates one fixed-size method icon.
  const _SecurityGlyph({required this.icon});

  final IconData icon;

  /// Builds a readable icon for either theme.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: colors.primary),
    );
  }
}

/// Reuses the settings row layout for enrolled methods and enrollment actions.
class _SecurityMethodTile extends StatelessWidget {
  /// Creates a row whose action preserves the existing enrollment behaviour.
  const _SecurityMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Allows labels and descriptions to wrap at larger accessibility sizes.
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    leading: _SecurityGlyph(icon: icon),
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    ),
    onTap: onTap,
    trailing: trailing,
  );
}

/// Keeps the requested future-method notice clearly informational.
class _MoreSecurityMethodsCard extends StatelessWidget {
  /// Creates the coming-soon notice without an unavailable action.
  const _MoreSecurityMethodsCard();

  /// Uses the same inset card and icon style as the working method rows.
  @override
  Widget build(BuildContext context) => const _SecurityCard(
    child: _SecurityMethodTile(
      icon: Icons.more_horiz_rounded,
      title: 'More methods coming soon',
      subtitle: 'Additional ways to verify your login will appear here.',
    ),
  );
}

/// Renders every enrolled factor without changing removal permissions.
class _BoundSecurityMethods extends StatelessWidget {
  /// Receives the server's removal policy and the existing removal command.
  const _BoundSecurityMethods({
    required this.status,
    required this.busy,
    required this.onRemove,
  });

  final MfaStatus status;
  final bool busy;
  final void Function(MfaFactor factor, bool canRemove) onRemove;

  /// Separates factors with the same subtle dividers as Profile settings.
  @override
  Widget build(BuildContext context) => _SecurityCard(
    child: Column(
      children: [
        if (status.factors.isEmpty)
          const _SecurityMethodTile(
            icon: Icons.lock_outline_rounded,
            title: 'No methods set up',
            subtitle: 'Add a verification method below to protect your login.',
          ),
        for (var index = 0; index < status.factors.length; index++) ...[
          if (index > 0)
            const Padding(
              padding: EdgeInsets.only(left: 72),
              child: Divider(height: 1),
            ),
          _SecurityMethodTile(
            icon: status.factors[index].type == 'passkey'
                ? Icons.fingerprint_rounded
                : Icons.password_rounded,
            title: status.factors[index].label,
            subtitle: status.factors[index].type == 'passkey'
                ? 'Passkey · verified with device security'
                : 'Authenticator · a new code every 30 seconds',
            trailing: IconButton(
              tooltip: status.canRemove
                  ? 'Remove ${status.factors[index].label}'
                  : 'Add another method first',
              onPressed: busy
                  ? null
                  : () => onRemove(status.factors[index], status.canRemove),
              icon: Icon(
                status.canRemove
                    ? Icons.delete_outline_rounded
                    : Icons.lock_outline_rounded,
              ),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}
