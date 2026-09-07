import 'package:flutter/material.dart';
import '../Model/trail_models.dart';

class CheckpointFlow extends StatelessWidget {
  const CheckpointFlow({
    super.key,
    required this.checkpoints,
    required this.highlightedIndex,
    required this.onShowOnMap,
  });
  final List<TrailCheckpoint> checkpoints;
  final int? highlightedIndex;
  final ValueChanged<int> onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            for (var i = 0; i < checkpoints.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 25),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 10,
                      child: VerticalDivider(
                        width: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ListTile(
                key: ValueKey('checkpoint-stop-$i'),
                selected: highlightedIndex == i,
                selectedTileColor: theme.colorScheme.primary.withValues(
                  alpha: .08,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: .1,
                  ),
                  child: Icon(
                    i == 0
                        ? Icons.trip_origin_rounded
                        : i == checkpoints.length - 1
                        ? Icons.flag_outlined
                        : Icons.location_on_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: Text(
                  checkpoints[i].name,
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  '${checkpoints[i].latitude.toStringAsFixed(5)}, ${checkpoints[i].longitude.toStringAsFixed(5)}',
                ),
                trailing: IconButton(
                  tooltip: 'Show on map',
                  onPressed: checkpoints[i].hasValidCoordinate
                      ? () => onShowOnMap(i)
                      : null,
                  icon: const Icon(Icons.near_me_rounded),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
