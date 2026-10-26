import 'package:flutter/material.dart';

/// Returns true only when the hiker chooses to open their achievements.
Future<bool> showAchievementUnlockedPopup(
  BuildContext context,
  Map<String, dynamic> row,
) async {
  final rawColor = row['accentColorValue'];
  final color = rawColor is int && rawColor != 0
      ? Color(rawColor)
      : const Color(0xFF34A853);
  final icon = switch (row['iconName']) {
    'hiking' => Icons.hiking_rounded,
    'verified_user' => Icons.verified_user_rounded,
    'map' => Icons.map_rounded,
    'terrain' => Icons.terrain_rounded,
    'route' => Icons.route_rounded,
    'groups' => Icons.groups_2_rounded,
    'task_alt' => Icons.task_alt_rounded,
    'forum' => Icons.forum_rounded,
    'volunteer_activism' => Icons.volunteer_activism_rounded,
    'health_and_safety' => Icons.health_and_safety_rounded,
    'military_tech' => Icons.military_tech_rounded,
    'explore' => Icons.explore_rounded,
    'travel_explore' => Icons.travel_explore_rounded,
    'public' => Icons.public_rounded,
    'warning' => Icons.warning_amber_rounded,
    _ => Icons.emoji_events_rounded,
  };
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          icon: CircleAvatar(
            radius: 36,
            backgroundColor: color.withValues(alpha: .14),
            child: Icon(icon, color: color, size: 38),
          ),
          title: Text(row['title']?.toString() ?? 'Achievement unlocked'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Achievement unlocked',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                row['condition']?.toString() ?? '',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '+${row['pointsAwarded'] ?? row['rewardPoints'] ?? 0} points',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Go to achievements'),
            ),
          ],
        ),
      ) ??
      false;
}
