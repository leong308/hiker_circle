import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/widgets/colored_location_map.dart';
import '../../../core/widgets/section_label.dart';
import '../../Model/shared_team_hike_summary.dart';

/// The common result layout used immediately after ending and in every member's history.
class TeamHikeSummaryPanel extends StatelessWidget {
  /// Accepts a frozen snapshot; marker positions never follow later movement until it is replaced.
  const TeamHikeSummaryPanel({
    super.key,
    required this.summary,
    this.mapBuilder,
  });
  final SharedTeamHikeSummary summary;
  final Widget Function(mapbox.MapWidget)? mapBuilder;

  /// Shows completion progress, the shared map, aggregate metrics and a colour-matched roster.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final points = summary.members
        .where((p) => p.location?.hasValidPosition == true)
        .map(
          (p) => ColoredLocationPoint(
            id: p.id,
            label: p.name,
            latitude: p.location!.latitude,
            longitude: p.location!.longitude,
            color: p.color,
          ),
        )
        .toList();
    final hours = summary.duration.inHours,
        minutes = summary.duration.inMinutes.remainder(60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  summary.finalized
                      ? Icons.task_alt_rounded
                      : Icons.groups_rounded,
                  color: colors.primary,
                  size: 30,
                ),
                const SizedBox(height: 10),
                Text(
                  summary.finalized
                      ? 'Team hike complete'
                      : 'Your hike is saved',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${summary.finishedCount}/${summary.members.length} hikers finished',
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: summary.members.isEmpty
                      ? 0
                      : summary.finishedCount / summary.members.length,
                ),
                const SizedBox(height: 12),
                Text(
                  summary.finalized
                      ? 'The final team map is saved in everyone’s hike history.'
                      : 'You can leave now. The shared map will update in history when the rest of the team finishes.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel(label: 'TEAM MAP'),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 300,
            child: ColoredLocationMap(
              points: points,
              fallback:
                  points.firstOrNull?.geometry ??
                  mapbox.Point(coordinates: mapbox.Position(101.97, 4.21)),
              mapBuilder: mapBuilder,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Recorded locations when this summary was saved. ${points.length}/${summary.members.length} hikers located.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                _TeamSummaryMetric(
                  label: 'Combined distance',
                  value: '${summary.distanceKm.toStringAsFixed(2)} km',
                ),
                _TeamSummaryMetric(
                  label: 'Team elapsed time',
                  value: '${hours}h ${minutes}m',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel(label: 'HIKERS'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final member in summary.members)
                ListTile(
                  leading: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(member.color),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.outline),
                    ),
                  ),
                  title: Text(member.name),
                  subtitle: Text(
                    member.location == null
                        ? 'No recorded location'
                        : member.ended
                        ? 'Finished · location saved'
                        : 'Still hiking · location saved',
                  ),
                  trailing: Icon(
                    member.ended ? Icons.check_circle_outline : Icons.hiking,
                    color: member.ended
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact result metric that wraps on small screens and large text sizes.
class _TeamSummaryMetric extends StatelessWidget {
  /// Keeps the number and its meaning together in responsive summary cards.
  const _TeamSummaryMetric({required this.label, required this.value});
  final String label, value;

  /// Uses the application typography for both shared summary entry points.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
