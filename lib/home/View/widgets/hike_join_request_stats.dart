import 'package:flutter/material.dart';
import '../../../core/widgets/section_label.dart';
import '../../Model/hike_join_request_stats.dart';

/// Shows only aggregate activity, without profile, contact or route-history details.
class HikeJoinRequestStatsCard extends StatelessWidget {
  /// Binds the host's review to server-projected hiking totals.
  const HikeJoinRequestStatsCard({super.key, required this.stats});
  final HikeJoinRequestStats stats;

  /// Keeps the activity cards readable on narrow phones and with enlarged text.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    if (!stats.available) {
      return Text(
        'Hiking stats are temporarily unavailable.',
        style: theme.textTheme.bodyMedium,
      );
    }
    final entries = <({IconData icon, String label, String value})>[
      (
        icon: Icons.hiking_rounded,
        label: 'Completed hikes',
        value: '${stats.completedHikes}',
      ),
      (
        icon: Icons.route_rounded,
        label: 'Total recorded distance',
        value: '${stats.totalDistanceKm.toStringAsFixed(1)} km',
      ),
      (
        icon: Icons.landscape_outlined,
        label: 'Longest completed hike',
        value: '${stats.longestHikeKm.toStringAsFixed(1)} km',
      ),
      (
        icon: Icons.people_outline_rounded,
        label: 'Group hikes',
        value: '${stats.groupHikes}',
      ),
      (
        icon: Icons.person_outline_rounded,
        label: 'Solo hikes',
        value: '${stats.soloHikes}',
      ),
      (
        icon: Icons.workspace_premium_outlined,
        label: 'Achievements unlocked',
        value: '${stats.unlockedAchievements}',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(label: 'Hiking record', padding: EdgeInsets.zero),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 280 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.4
                ? 2
                : 1;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: .5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(entry.icon, size: 21, color: colors.primary),
                          const SizedBox(height: 8),
                          Text(
                            entry.value,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(entry.label, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Recorded activity in HikerCircle. Contact details, home area and private routes are not shared.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
