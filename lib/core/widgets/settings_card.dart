import 'package:flutter/material.dart';

// Keeps closed cards aligned regardless of the leading control or summary length.
const double _settingsRowMinHeight = 84;
const double _settingsRowHorizontalPadding = 12;
const double _settingsLeadingWidth = 32;
const double _settingsIconTextGap = 12;

/// The shared rounded surface used by navigation, drawer and toggle settings.
class SettingsCard extends StatelessWidget {
  /// Keeps all settings on the same surface and border treatment.
  const SettingsCard({super.key, required this.child});
  final Widget child;

  /// Provides the Material ancestor for row taps and expanded controls.
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .65),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// A compact settings row with aligned text and a consistently sized leading control.
class SettingsNavigationCard extends StatelessWidget {
  /// Creates a navigation row or a custom trailing busy indicator.
  const SettingsNavigationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.footer,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing, footer;

  /// Matches the Login security card across the settings page.
  @override
  Widget build(BuildContext context) => SettingsCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsRow(
          title: title,
          subtitle: subtitle,
          onTap: onTap,
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          trailing:
              trailing ?? const Icon(Icons.chevron_right_rounded, size: 22),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: footer!,
          ),
      ],
    ),
  );
}

/// A direct on/off setting with a leading icon and trailing adaptive switch.
class SettingsToggleCard extends StatelessWidget {
  /// Leaves preference updates and confirmation behavior with the caller.
  const SettingsToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Keeps the existing confirmation callback on both the row and its switch.
  @override
  Widget build(BuildContext context) => SettingsCard(
    child: MergeSemantics(
      child: _SettingsRow(
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      ),
    ),
  );
}

/// An initially closed drawer with a right-pointing chevron and a current-value summary.
class SettingsDisclosureCard extends StatefulWidget {
  /// Retains expanded controls while their owning settings page remains open.
  const SettingsDisclosureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final Widget icon, child;
  final String title, subtitle;

  /// Owns only the drawer's local presentation state.
  @override
  State<SettingsDisclosureCard> createState() => _SettingsDisclosureCardState();
}

/// Rotates the shared right chevron after an explicit expansion tap.
class _SettingsDisclosureCardState extends State<SettingsDisclosureCard> {
  bool _expanded = false;

  /// Resets to closed with each new settings page and preserves user taps on rebuilds.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsCard(
      child: ListTileTheme.merge(
        minLeadingWidth: _settingsLeadingWidth,
        horizontalTitleGap: _settingsIconTextGap,
        minVerticalPadding: 12,
        child: ExpansionTile(
          initiallyExpanded: false,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: _settingsRowHorizontalPadding,
          ),
          minTileHeight: _settingsRowMinHeight,
          visualDensity: VisualDensity.standard,
          // Keep floating field labels inside the drawer's clipped content area.
          childrenPadding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.textScalerOf(context).scale(16),
            16,
            16,
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          onExpansionChanged: (value) => setState(() => _expanded = value),
          leading: SizedBox(
            width: _settingsLeadingWidth,
            child: IconTheme(
              data: IconThemeData(color: theme.colorScheme.primary, size: 24),
              child: widget.icon,
            ),
          ),
          title: _SettingsLabel(title: widget.title, subtitle: widget.subtitle),
          trailing: AnimatedRotation(
            key: ValueKey('settings-chevron-${widget.title}'),
            turns: _expanded ? .25 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: const Icon(Icons.chevron_right_rounded, size: 22),
          ),
          children: [widget.child],
        ),
      ),
    );
  }
}

/// Shares row spacing and typography without coupling cards to preference storage.
class _SettingsRow extends StatelessWidget {
  /// Creates a row with a leading icon and an optional trailing control.
  const _SettingsRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final Widget leading;
  final Widget? trailing;
  final String title, subtitle;
  final VoidCallback? onTap;

  /// Lets long labels wrap naturally on small screens and with larger text.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _settingsRowMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _settingsRowHorizontalPadding,
            vertical: 12,
          ),
          child: Row(
            children: [
              SizedBox(
                width: _settingsLeadingWidth,
                child: Center(child: leading),
              ),
              const SizedBox(width: _settingsIconTextGap),
              Expanded(
                child: _SettingsLabel(title: title, subtitle: subtitle),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups titles and summaries so every settings row centers the same text block.
class _SettingsLabel extends StatelessWidget {
  /// Shares typography and title-to-summary spacing across all card types.
  const _SettingsLabel({required this.title, required this.subtitle});
  final String title, subtitle;

  /// Allows wrapped text to grow while keeping short labels vertically centered.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
