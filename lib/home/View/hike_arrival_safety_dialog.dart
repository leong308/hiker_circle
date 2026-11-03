import 'package:flutter/material.dart';
import '../ModelView/hike_arrival_safety_coordinator.dart';

/// Presents only the overdue-arrival confirmation, independently of SOS or fall-detection controls.
class HikeArrivalSafetyDialog extends StatefulWidget {
  /// Binds the countdown and explicit safe action to the arrival coordinator.
  const HikeArrivalSafetyDialog({super.key, required this.coordinator});
  final HikeArrivalSafetyCoordinator coordinator;

  /// Closes the owned route once the response is saved on the phone.
  @override
  State<HikeArrivalSafetyDialog> createState() =>
      _HikeArrivalSafetyDialogState();
}

/// Keeps the confirmation open until its response is saved or recorded arrival is established.
class _HikeArrivalSafetyDialogState extends State<HikeArrivalSafetyDialog> {
  bool _closing = false;

  /// Removes this owned route without popping a newer SOS or safety route above it.
  void _closeWhenSettled() {
    if (_closing || widget.coordinator.needsPrompt) return;
    _closing = true;
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true) route?.navigator?.removeRoute(route);
    });
  }

  /// Rebuilds the live countdown and the local-first cancellation status.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.coordinator,
    builder: (context, _) {
      final state = widget.coordinator;
      _closeWhenSettled();
      final colors = Theme.of(context).colorScheme;
      final seconds = state.remainingSeconds;
      final remaining =
          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
      return PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: Icon(
            Icons.health_and_safety_outlined,
            color: colors.primary,
            size: 34,
          ),
          title: const Text('Is everything okay?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.trailName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(state.detail),
              if (!state.cancellationPending && !state.dispatchStarted) ...[
                const SizedBox(height: 18),
                Text(
                  seconds > 0
                      ? 'Emergency contacts will be alerted in'
                      : 'Preparing the emergency-contact alert',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (seconds > 0)
                  Text(
                    remaining,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.error,
                    ),
                  ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(state.error!, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: state.busy ? null : state.confirmEverythingOkay,
              child: Text(state.busy ? 'Confirming…' : 'Everything is okay!'),
            ),
          ],
        ),
      );
    },
  );
}
