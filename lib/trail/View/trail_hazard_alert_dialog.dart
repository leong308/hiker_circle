import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/caution_icon.dart';
import '../Model/trail_hazard_alert.dart';
import '../Model/trail_hazard_categories.dart';

/// Defines the trail hazard alert action choices.
enum TrailHazardAlertAction {
  acknowledge,
  proceed,
  abort,
  reschedule,
  cancelHike,
}

/// Shows trail hazard alert dialog.
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

/// Displays the trail hazard alert dialog.
class TrailHazardAlertDialog extends StatelessWidget {
  /// Creates trail hazard alert dialog.
  const TrailHazardAlertDialog({
    super.key,
    required this.alerts,
    required this.beforeStart,
    this.canCancelHike = false,
  });

  final List<TrailHazardAlert> alerts;
  final bool beforeStart;
  final bool canCancelHike;

  /// Builds this widget from its current presentation state.
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

    /// Closes.
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
                    child: CautionIcon(
                      icon: trailHazardIconFor(lead.type),
                      seriousRisk: fatal,
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
                if (alerts.any((alert) => alert.isCriticalWeather)) ...[
                  _WeatherReportTimes(alerts: alerts),
                  const SizedBox(height: 12),
                ],
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

/// Computes weather hazard report time.
String weatherHazardReportTime(DateTime value) {
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Computes two.
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year} · ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// Displays the weather report times.
class _WeatherReportTimes extends StatelessWidget {
  /// Creates weather report times.
  const _WeatherReportTimes({required this.alerts});
  final List<TrailHazardAlert> alerts;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final weather = alerts.where((alert) => alert.isCriticalWeather).toList();
    final types = weather.map((alert) => alert.type).toSet();
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('critical-weather-report-times'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reported and confirmed at',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text('Your local time', style: theme.textTheme.bodySmall),
          for (final type in types) ...[
            const SizedBox(height: 10),
            Text(
              type,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            ..._timesFor(weather.where((alert) => alert.type == type)).map(
              (time) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '• ${weatherHazardReportTime(time)}',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ),
            if (_timesFor(weather.where((alert) => alert.type == type)).isEmpty)
              const Text('Report time unavailable.'),
          ],
          if (weather.any((alert) => !alert.reportTimesComplete)) ...[
            const SizedBox(height: 8),
            Text(
              'Additional report times could not be loaded.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Computes times for.
  List<DateTime> _timesFor(Iterable<TrailHazardAlert> reports) =>
      (<int, DateTime>{
        for (final alert in reports)
          for (final time in alert.reportTimes)
            time.microsecondsSinceEpoch: time,
      }.values.toList()..sort((a, b) => b.compareTo(a)));
}

/// Displays the caution summary.
class _CautionSummary extends StatelessWidget {
  /// Creates caution summary.
  const _CautionSummary({required this.alert});
  final TrailHazardAlert alert;

  /// Builds this widget from its current presentation state.
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
          Row(
            children: [
              CautionIcon(
                icon: trailHazardIconFor(alert.type),
                seriousRisk: alert.isFatal,
                color: alert.isFatal ? colors.error : colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert.type,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
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
