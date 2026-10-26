part of '../../admin_ui_feature.dart';

/// Displays the admin panel.
class AdminPanel extends StatelessWidget {
  /// Creates admin panel.
  const AdminPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
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

/// Displays the admin empty state.
class AdminEmptyState extends StatelessWidget {
  /// Creates admin empty state.
  const AdminEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });
  final String title, message;
  final IconData icon;

  /// Builds this widget from its current presentation state.
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
