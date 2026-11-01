import 'package:flutter/material.dart';
import '../../../core/widgets/section_label.dart';
import '../../Model/hike_join_request_stats.dart';

/// Shows aggregate activity without contact, location or private route information.
class HikeJoinRequestStatsCard extends StatelessWidget {
  /// Binds the review to the server's privacy-filtered totals.
  const HikeJoinRequestStatsCard({super.key, required this.stats});
  final HikeJoinRequestStats stats;

  /// Highlights essential totals and keeps the rest in an optional drawer.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    if (!stats.available) {
      return Text(
        'Hiking stats are temporarily unavailable.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }
    final highlights = [
      ('${stats.completedHikes}', 'Completed hikes', Icons.hiking_rounded),
      (
        '${stats.totalDistanceKm.toStringAsFixed(1)} km',
        'Total distance',
        Icons.route_rounded,
      ),
    ];
    final details = [
      ('Longest hike', '${stats.longestHikeKm.toStringAsFixed(1)} km'),
      ('Group hikes', '${stats.groupHikes}'),
      ('Solo hikes', '${stats.soloHikes}'),
      ('Achievements', '${stats.unlockedAchievements}'),
      ('Hiker level', '${stats.hikerLevel}'),
      ('Achievement points', '${stats.achievementPoints}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(label: 'Hiking record', padding: EdgeInsets.zero),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 250 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in highlights)
                  SizedBox(
                    width: stacked
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(entry.$3, color: colors.primary, size: 20),
                          const SizedBox(height: 10),
                          Text(
                            entry.$1,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(entry.$2, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 10),
            title: Text(
              'More hiking stats',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              for (final entry in details)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.$1,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        entry.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Text(
          'HikerCircle activity only. Personal details and private routes stay hidden.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
