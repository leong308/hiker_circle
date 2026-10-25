import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../Model/trail_hazard_alert.dart';

enum TrailHazardAlertAction {
  acknowledge,
  proceed,
  abort,
  reschedule,
  cancelHike,
}

Future<TrailHazardAlertAction> showTrailHazardAlertDialog(
  BuildContext context, {
  required List<TrailHazardAlert> alerts,
  required bool beforeStart,
  bool canCancelHike = false,
}) async {
  if (alerts.isEmpty) return TrailHazardAlertAction.acknowledge;
  final result = await showDialog<TrailHazardAlertAction>(
    context: context,
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: 'trail-hazard-alert'),
    builder: (_) => TrailHazardAlertDialog(
      alerts: alerts,
      beforeStart: beforeStart,
      canCancelHike: canCancelHike,
    ),
  );
  return result ??
      (beforeStart
          ? TrailHazardAlertAction.abort
          : TrailHazardAlertAction.acknowledge);
}

class TrailHazardAlertDialog extends StatelessWidget {
  const TrailHazardAlertDialog({
    super.key,
    required this.alerts,
    required this.beforeStart,
    this.canCancelHike = false,
  });

  final List<TrailHazardAlert> alerts;
  final bool beforeStart;
  final bool canCancelHike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fatal = alerts.any((alert) => alert.isFatal);
    final lead = alerts.firstWhere(
      (alert) => alert.isFatal,
      orElse: () => alerts.first,
    );
    final accent = fatal ? colors.error : colors.primary;
    final media = MediaQuery.of(context);
    void close(TrailHazardAlertAction action) =>
        Navigator.of(context).pop(action);

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: math.max(
              0,
              media.size.height -
                  media.padding.vertical -
                  media.viewInsets.vertical -
                  48,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      fatal
                          ? Icons.warning_rounded
                          : Icons.info_outline_rounded,
                      color: accent,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  fatal ? 'Reconsider this hike' : 'A caution on your trail',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  lead.trailName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                for (final alert in alerts) ...[
                  _CautionSummary(alert: alert),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                Text(
                  lead.injunctiveMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  lead.descriptiveMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (fatal) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: colors.onError,
                    ),
                    onPressed: () => close(
                      beforeStart
                          ? TrailHazardAlertAction.abort
                          : canCancelHike
                          ? TrailHazardAlertAction.cancelHike
                          : TrailHazardAlertAction.reschedule,
                    ),
                    child: Text(
                      beforeStart
                          ? 'Abort hike'
                          : canCancelHike
                          ? 'Cancel my hike'
                          : 'Choose another time',
                    ),
                  ),
                  if (beforeStart || canCancelHike) ...[
                    const SizedBox(height: 6),
                    OutlinedButton(
                      onPressed: () => close(TrailHazardAlertAction.reschedule),
                      child: const Text('Choose another time'),
                    ),
                  ],
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => close(
                      beforeStart
                          ? TrailHazardAlertAction.proceed
                          : TrailHazardAlertAction.acknowledge,
                    ),
                    child: Text(beforeStart ? 'Proceed anyway' : 'Done'),
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => close(
                      beforeStart
                          ? TrailHazardAlertAction.proceed
                          : TrailHazardAlertAction.acknowledge,
                    ),
                    child: Text(beforeStart ? 'Continue' : 'Got it'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CautionSummary extends StatelessWidget {
  const _CautionSummary({required this.alert});
  final TrailHazardAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            alert.type,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${alert.category} · ${alert.isFatal ? 'Serious risk' : 'Caution'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: alert.isFatal ? colors.error : colors.onSurfaceVariant,
            ),
          ),
          if (alert.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              alert.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            alert.verificationMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
