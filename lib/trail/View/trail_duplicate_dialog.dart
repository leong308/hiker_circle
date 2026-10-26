import 'package:flutter/material.dart';

import '../Data/trail_duplicate_checker.dart';

/// Defines the trail duplicate decision choices.
enum TrailDuplicateDecision { startOver, unapprove, proceedReview }

/// Shows trail duplicate dialog.
Future<TrailDuplicateDecision?> showTrailDuplicateDialog(
  BuildContext context, {
  required TrailDuplicateMatch match,
  bool reviewingSubmission = false,
}) => showDialog<TrailDuplicateDecision>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PopScope(
    canPop: false,
    child: AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.route_rounded),
      title: const Text('This trail seems repeated'),
      content: Text(
        '${match.percentage}% of this route follows “${match.trailName}” '
        '(within ${TrailRouteSimilarity.toleranceMeters.round()} m). '
        '${reviewingSubmission ? 'Unapprove this request, or proceed with the review?' : 'Start over and choose a new starting point.'}',
      ),
      actions: reviewingSubmission
          ? [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, TrailDuplicateDecision.unapprove),
                child: const Text('Unapprove'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  TrailDuplicateDecision.proceedReview,
                ),
                child: const Text('Proceed review'),
              ),
            ]
          : [
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, TrailDuplicateDecision.startOver),
                child: const Text('Start over'),
              ),
            ],
    ),
  ),
);
