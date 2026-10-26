part of '../../community_moderation_controls_feature.dart';

/// Displays the option label.
class _OptionLabel extends StatelessWidget {
  /// Creates option label.
  const _OptionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 10),
      Flexible(child: Text(label)),
    ],
  );
}
