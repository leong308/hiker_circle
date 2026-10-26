import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Displays hiking time beside route length, followed by distance from the hiker.
class TrailCardMetrics extends StatelessWidget {
  /// Creates trail metadata for a list or grid card.
  const TrailCardMetrics({
    super.key,
    required this.distanceLabel,
    required this.durationLabel,
    required this.grid,
    required this.color,
    this.nearbyDistanceKm,
  });

  final String distanceLabel;
  final String durationLabel;
  final bool grid;
  final Color color;
  final double? nearbyDistanceKm;

  /// Keeps grid route metrics on one row and proximity on its own row.
  @override
  Widget build(BuildContext context) {
    final distance = _TrailMetric(
      key: const ValueKey('trail-route-distance'),
      icon: Icons.route_rounded,
      label: distanceLabel,
      color: color,
    );
    final duration = _TrailMetric(
      key: const ValueKey('trail-duration'),
      icon: CupertinoIcons.clock_fill,
      label: durationLabel,
      color: color,
    );
    final nearby = nearbyDistanceKm;
    final proximity = nearby == null || !nearby.isFinite
        ? null
        : _TrailMetric(
            key: const ValueKey('trail-nearby-distance'),
            icon: Icons.near_me_rounded,
            label: '${nearby.toStringAsFixed(1)} km from you',
            color: color,
          );
    if (!grid) {
      return Wrap(
        spacing: 10,
        runSpacing: 5,
        children: [distance, duration, if (proximity != null) proximity],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: distance),
            const SizedBox(width: 10),
            Flexible(child: duration),
          ],
        ),
        if (proximity != null) ...[const SizedBox(height: 5), proximity],
      ],
    );
  }
}

/// Renders a compact icon and single-line metric within the available card width.
class _TrailMetric extends StatelessWidget {
  /// Creates one trail metric.
  const _TrailMetric({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// Truncates long values without overflowing narrow grid cards.
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
