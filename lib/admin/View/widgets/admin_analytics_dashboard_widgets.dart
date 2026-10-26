part of '../../admin_analytics_dashboard_feature.dart';

/// Displays the metric.
class _Metric extends StatelessWidget {
  /// Creates metric.
  const _Metric({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.tint,
    this.onTap,
  });
  final String title, value, detail;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AdminPanel(
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const Spacer(),
            if (onTap != null)
              Icon(
                Icons.arrow_outward_rounded,
                size: 16,
                color: AdminUi.muted(context),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          style: TextStyle(
            fontSize: 11,
            color: AdminUi.muted(context),
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

/// Displays the queue row.
class _QueueRow extends StatelessWidget {
  /// Creates queue row.
  const _QueueRow({
    required this.title,
    required this.detail,
    required this.count,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  final String title, detail;
  final num count;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: tint, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AdminUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 30),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: count > 0
                  ? tint.withValues(alpha: .12)
                  : AdminUi.background(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              _fmt(count),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AdminUi.muted(context),
          ),
        ],
      ),
    ),
  );
}
