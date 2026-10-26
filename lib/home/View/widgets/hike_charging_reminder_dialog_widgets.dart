part of '../../hike_charging_reminder_dialog_feature.dart';

/// Displays the battery level card.
class _BatteryLevelCard extends StatelessWidget {
  /// Creates battery level card.
  const _BatteryLevelCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.secondary,
    required this.fill,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color secondary;
  final Color fill;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 9),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: value.contains('%') ? 29 : 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: secondary, height: 1.35),
        ),
      ],
    ),
  );
}
