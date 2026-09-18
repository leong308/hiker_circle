import 'package:flutter/material.dart';
import '../Model/hike_session_models.dart';
import '../Model/solo_hike_policy.dart';

/// Returns an acknowledged draft, or null when the user must revise the plan.
Future<HikeSessionDraft?> confirmSoloHikeDistance(
  BuildContext context,
  HikeSessionDraft draft, {
  VoidCallback? onChooseGroup,
  bool starting = false,
}) async {
  final km = draft.trail.distanceKm;
  final group = draft.hikeType == HikeType.team;
  if (group &&
      !(starting &&
          SoloHikePolicy.requiresGroup(km) &&
          draft.teamBuddies.isEmpty)) {
    return draft;
  }
  final blocked = SoloHikePolicy.requiresGroup(km);
  if (!blocked &&
      (!SoloHikePolicy.requiresAcknowledgement(km) ||
          SoloHikePolicy.isAcknowledged(
            km,
            draft.soloDistanceAcknowledgedKm,
          ))) {
    return draft;
  }
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        blocked ? Icons.groups_rounded : Icons.hiking_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(blocked ? 'Group hike required' : 'Review this solo hike'),
      content: Text(
        blocked
            ? '${draft.trail.name} is ${km.toStringAsFixed(1)} km. HikerCircle requires group setup for routes over 20 km. ${group ? 'Invite at least one hiking partner before starting.' : 'Choose Team Hike to continue.'}'
            : '${draft.trail.name} is ${km.toStringAsFixed(1)} km. Solo hikes over 10 km need extra preparation. Review the route, daylight, supplies and your ability; share your plan with an emergency contact. You can choose a group hike instead.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Go back'),
        ),
        if (blocked && onChooseGroup != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(context, false);
              onChooseGroup();
            },
            child: const Text('Choose Team Hike'),
          ),
        if (!blocked)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Acknowledge & continue solo'),
          ),
      ],
    ),
  );
  return accepted == true
      ? draft.copyWith(soloDistanceAcknowledgedKm: km)
      : null;
}
