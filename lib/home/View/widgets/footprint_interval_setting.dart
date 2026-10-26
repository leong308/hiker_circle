import '../../../core/widgets/footprint_icon.dart';
import 'package:flutter/material.dart';
import '../../Model/location_update_interval.dart';

/// Displays the footprint interval setting.
class FootprintIntervalSetting extends StatelessWidget {
  /// Creates footprint interval setting.
  const FootprintIntervalSetting({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final Duration value;
  final ValueChanged<Duration> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<Duration>(
        key: ValueKey('footprint-interval-${value.inSeconds}'),
        isExpanded: true,
        initialValue: LocationUpdateInterval.normalize(value),
        decoration: const InputDecoration(
          labelText: 'Footprint record interval',
          prefixIcon: FootprintIcon(),
        ),
        items: [
          for (final interval in LocationUpdateInterval.options)
            DropdownMenuItem(
              value: interval,
              child: Text(
                LocationUpdateInterval.label(interval),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (interval) {
          if (interval != null) onChanged(interval);
        },
      ),
      const SizedBox(height: 8),
      Text(
        'Controls saved GPS footprints and route uploads. Longer intervals can reduce battery use but record fewer route details.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
