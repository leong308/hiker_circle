import 'package:flutter/material.dart';

/// Keeps an open source chooser in sync with the loading trail catalog.
class HikeSourceChooser extends StatelessWidget {
  const HikeSourceChooser({
    super.key,
    required this.trailAvailability,
    required this.hasRecordedTrails,
  });

  final Listenable trailAvailability;
  final bool Function() hasRecordedTrails;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: trailAvailability,
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Where are you hiking?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('start-catalog-hike'),
              enabled: hasRecordedTrails(),
              leading: const Icon(Icons.route_rounded),
              title: const Text('Choose a recorded trail'),
              subtitle: const Text('Use an existing route and checkpoints'),
              onTap: () => Navigator.pop(context, 'catalog'),
            ),
            ListTile(
              key: const ValueKey('start-location-hike'),
              leading: const Icon(Icons.my_location_rounded),
              title: const Text('Hike from my current location'),
              subtitle: const Text('Record a route that is not in HikerCircle'),
              onTap: () => Navigator.pop(context, 'location'),
            ),
          ],
        ),
      ),
    ),
  );
}
