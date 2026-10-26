import 'fall_sensitivity_setting.dart';
// PathDeviationDistanceSetting edits the bounded off-route warning distance.
import 'package:flutter/material.dart';

import '../../Model/path_deviation_policy.dart';

/// Displays the path deviation distance setting.
class PathDeviationDistanceSetting extends StatelessWidget {
  /// Creates path deviation distance setting.
  const PathDeviationDistanceSetting({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  static const accuracyHint =
      'GPS may drift under dense trees, near cliffs or in narrow valleys. '
      'This is an approximate reminder to check your route; poor GPS accuracy '
      'can delay warnings.';

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final distance = PathDeviationPolicy.normalizeDistance(value);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.alt_route_rounded,
                color: enabled ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Maximum deviation',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$distance m',
                key: const ValueKey('path-deviation-distance-value'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: enabled ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            key: const ValueKey('path-deviation-distance-slider'),
            value: distance.toDouble(),
            min: PathDeviationPolicy.minimumDistanceMeters.toDouble(),
            max: PathDeviationPolicy.maximumDistanceMeters.toDouble(),
            divisions:
                PathDeviationPolicy.maximumDistanceMeters -
                PathDeviationPolicy.minimumDistanceMeters,
            label: '$distance metres',
            semanticFormatterCallback: (value) => '${value.round()} metres',
            onChanged: enabled ? (value) => onChanged(value.round()) : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('10 m', style: theme.textTheme.labelSmall),
              Text('50 m', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            enabled
                ? 'Warns after about 2 minutes beyond this distance.'
                : 'Alerts are off. Your selected distance is kept.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.gps_not_fixed_rounded,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  accuracyHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            lowBatterySafetyHint,
            key: const ValueKey('low-battery-safety-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
