// Weather presentation helpers share forecast icons, metric rows and chart styling.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/widgets/running_border.dart';
import '../Model/trail_precautions.dart';

/// Shared presentation for trail outlooks and scheduled hiking forecasts.
Widget weatherMetric(
  BuildContext context,
  IconData icon,
  String label,
  String reading,
) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reading, style: Theme.of(context).textTheme.titleSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget weatherDetailSection(
  BuildContext context,
  IconData icon,
  String title,
  String subtitle,
  List<Widget> children, {
  bool initiallyExpanded = false,
  bool emphasize = false,
  Key? sectionKey,
}) {
  final theme = Theme.of(context);
  final card = Material(
    color: theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: sectionKey,
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      childrenPadding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(icon, color: theme.colorScheme.primary, size: 22),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
      ),
      children: children,
    ),
  );
  return emphasize
      ? RunningBorder(color: theme.colorScheme.primary, child: card)
      : card;
}

LineChartBarData weatherChartLine(BuildContext context, List<FlSpot> spots) {
  final color = Theme.of(context).colorScheme.primary;
  return LineChartBarData(
    spots: spots,
    color: color,
    barWidth: 2.5,
    isCurved: false,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .09)),
  );
}

IconData forecastWeatherIcon(num? code) {
  if (code == null) return Icons.cloud_queue_rounded;
  if (code >= 95) return Icons.thunderstorm_outlined;
  if (code >= 51) return Icons.water_drop_outlined;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code <= 1) return Icons.wb_sunny_outlined;
  return Icons.cloud_outlined;
}

/// Shared hazard-specific symbols, including buffer-prefixed caution IDs.
IconData precautionIcon(TrailPrecaution caution) {
  final id = caution.id;
  if (id == 'daylight-data') return Icons.brightness_auto_rounded;
  if (id == 'buffer-data') return Icons.history_rounded;
  if (id == 'data') return Icons.cloud_off_rounded;
  if (id == 'storm' || id.endsWith('-storm')) {
    return Icons.thunderstorm_outlined;
  }
  if (id == 'rain' || id.endsWith('-rain')) return Icons.water_drop_outlined;
  if (id == 'heat' || id.endsWith('-heat')) return Icons.thermostat_rounded;
  if (id == 'cold' || id.endsWith('-cold')) return Icons.ac_unit_rounded;
  if (id == 'wind' || id.endsWith('-wind')) return Icons.air_rounded;
  if (id == 'ascent') return Icons.terrain_outlined;
  if (id == 'uv' || id.endsWith('-uv')) return Icons.wb_sunny_outlined;
  if (id == 'visibility' || id.endsWith('-visibility')) return Icons.foggy;
  if (id == 'dark') return Icons.nights_stay_outlined;
  if (id == 'sunset') return Icons.wb_twilight_rounded;
  if (id == 'duration') return Icons.timelapse_rounded;
  return Icons.warning_amber_rounded;
}
