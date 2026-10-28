part of '../admin_ui_feature.dart';

/// Shared surfaces and hierarchy for admin management and device diagnostics.
abstract final class AdminUi {
  /// Computes dark.
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background.
  static Color background(BuildContext context) =>
      dark(context) ? const Color(0xFF101714) : const Color(0xFFF4F6F5);

  /// Computes surface.
  static Color surface(BuildContext context) =>
      dark(context) ? const Color(0xFF19231E) : Colors.white;

  /// Computes border.
  static Color border(BuildContext context) =>
      dark(context) ? const Color(0xFF304038) : const Color(0xFFE0E8E3);

  /// Computes muted.
  static Color muted(BuildContext context) =>
      dark(context) ? const Color(0xFFA9BCB1) : const Color(0xFF64756B);

  /// Computes green.
  static Color green(BuildContext context) =>
      dark(context) ? const Color(0xFF8BD4AD) : const Color(0xFF26754F);

  /// Computes blue.
  static Color blue(BuildContext context) =>
      dark(context) ? const Color(0xFF9BC8FF) : const Color(0xFF2969AF);
}

/// Displays the admin heading.
class AdminHeading extends StatelessWidget {
  /// Creates admin heading.
  const AdminHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.action,
  });
  final String title, subtitle;
  final VoidCallback? onBack;
  final Widget? action;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
    child: Row(
      children: [
        if (onBack != null) ...[
          PageHeaderAction(
            tooltip: 'Back',
            icon: Icons.arrow_back_rounded,
            onPressed: onBack,
            color: AdminUi.green(context),
            surface: AdminUi.surface(context),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PageHeaderStyle.title(
                  context,
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: PageHeaderStyle.subtitle(
                  context,
                  AdminUi.muted(context),
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    ),
  );
}

/// Displays the admin section heading.
class AdminSectionHeading extends StatelessWidget {
  /// Creates admin section heading.
  const AdminSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(label: title, padding: EdgeInsets.zero),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: TextStyle(
                  color: AdminUi.muted(context),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

/// Displays the admin tag.
class AdminTag extends StatelessWidget {
  /// Creates admin tag.
  const AdminTag({super.key, required this.label, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final tint = color ?? AdminUi.green(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: tint,
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
