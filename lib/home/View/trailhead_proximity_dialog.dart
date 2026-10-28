import 'package:flutter/material.dart';

import '../../core/widgets/location_destination_map.dart';
import '../Model/trailhead_proximity.dart';

/// Shows the trailhead warning while keeping its map and actions scroll-safe.
class TrailheadProximityDialog extends StatelessWidget {
  /// A missing comparison asks for a retry instead of claiming the hiker is close.
  const TrailheadProximityDialog({super.key, required this.proximity});

  final TrailheadProximity? proximity;

  /// Highlights Waze as the recommended action, with a plain continue option.
  @override
  Widget build(BuildContext context) {
    final comparison = proximity;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      title: Text(
        comparison == null
            ? 'Location unavailable'
            : 'You’re away from the trail start',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comparison == null
                  ? 'We couldn’t check your distance from the trail start. Check that location is enabled and try again.'
                  : 'You’re ${comparison.distanceLabel} from ${comparison.trail.name}’s starting point, more than 100 metres away.',
            ),
            if (comparison != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 280,
                  child: LocationDestinationMap(
                    current: comparison.currentPoint,
                    destination: comparison.destinationPoint,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _MapLegend(
                    icon: Icons.circle,
                    color: Color(0xFF007AFF),
                    label: 'Your location',
                  ),
                  _MapLegend(
                    icon: Icons.location_on_rounded,
                    color: Color(0xFFE53935),
                    label: 'Trail start',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, TrailheadProximityAction.proceed),
          child: const Text('Proceed anyway'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            comparison == null
                ? TrailheadProximityAction.retry
                : TrailheadProximityAction.directions,
          ),
          icon: Icon(
            comparison == null
                ? Icons.my_location_rounded
                : Icons.navigation_rounded,
          ),
          label: Text(comparison == null ? 'Try again' : 'Get Directions'),
        ),
      ],
    );
  }
}

/// Labels the two marker colors without placing captions over the map controls.
class _MapLegend extends StatelessWidget {
  /// Keeps marker labels readable when the phone uses larger text.
  const _MapLegend({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  /// Builds one compact marker key.
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}
