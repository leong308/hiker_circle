import 'package:flutter/material.dart';

/// The compact section labels used on the homepage and trail creation form.
class SectionLabel extends StatelessWidget {
  /// Creates section label.
  const SectionLabel({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.only(left: 14),
  });

  final String label;
  final EdgeInsetsGeometry padding;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFA8B8AE)
              : const Color(0xFF6E6E73),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
