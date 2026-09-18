import 'package:flutter/material.dart';
import '../../core/widgets/page_header_style.dart';

/// Shared surfaces and hierarchy for admin management and device diagnostics.
abstract final class AdminUi {
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color background(BuildContext context) =>
      dark(context) ? const Color(0xFF101714) : const Color(0xFFF4F6F5);
  static Color surface(BuildContext context) =>
      dark(context) ? const Color(0xFF19231E) : Colors.white;
  static Color border(BuildContext context) =>
      dark(context) ? const Color(0xFF304038) : const Color(0xFFE0E8E3);
  static Color muted(BuildContext context) =>
      dark(context) ? const Color(0xFFA9BCB1) : const Color(0xFF64756B);
  static Color green(BuildContext context) =>
      dark(context) ? const Color(0xFF8BD4AD) : const Color(0xFF26754F);
  static Color blue(BuildContext context) =>
      dark(context) ? const Color(0xFF9BC8FF) : const Color(0xFF2969AF);
}

class AdminPanel extends StatelessWidget {
  const AdminPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AdminUi.surface(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: AdminUi.border(context)),
    ),
    clipBehavior: Clip.antiAlias,
    child: onTap == null
        ? Padding(padding: padding, child: child)
        : InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
  );
}

class AdminHeading extends StatelessWidget {
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

class AdminSectionHeading extends StatelessWidget {
  const AdminSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
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

class AdminTag extends StatelessWidget {
  const AdminTag({super.key, required this.label, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;
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

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AdminPanel(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AdminUi.green(context).withValues(alpha: .07),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 26, color: AdminUi.green(context)),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AdminUi.muted(context),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
