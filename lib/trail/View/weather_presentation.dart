// Weather presentation helpers share forecast icons, metric rows and chart styling.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/widgets/running_border.dart';
import '../Model/trail_precautions.dart';

/// Shows a draggable scroll thumb below horizontally arranged forecast choices.
class ForecastScrollRow extends StatefulWidget {
  /// Reuses the same visible scrolling affordance for dates and summary metrics.
  const ForecastScrollRow({super.key, required this.children});
  final List<Widget> children;

  /// Creates the strip's scroll-controller owner.
  @override
  State<ForecastScrollRow> createState() => _ForecastScrollRowState();
}

/// Keeps each forecast strip's scrollbar attached to exactly one scroll position.
class _ForecastScrollRowState extends State<ForecastScrollRow> {
  final _controller = ScrollController();

  /// Releases the scroll position when the forecast leaves the page.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Places the visible track below the content without covering the cards.
  @override
  Widget build(BuildContext context) => RawScrollbar(
    controller: _controller,
    thumbVisibility: true,
    trackVisibility: true,
    interactive: true,
    thumbColor: Theme.of(context).colorScheme.primary.withValues(alpha: .65),
    trackColor: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
    trackBorderColor: Colors.transparent,
    thickness: 4,
    radius: const Radius.circular(4),
    scrollbarOrientation: ScrollbarOrientation.bottom,
    child: SingleChildScrollView(
      controller: _controller,
      primary: false,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          for (var i = 0; i < widget.children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            widget.children[i],
          ],
        ],
      ),
    ),
  );
}

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

/// Computes weather detail section.
Widget weatherDetailSection(
  BuildContext context,
  IconData icon,
  String title,
  String subtitle,
  List<Widget> children, {
  bool initiallyExpanded = false,
  bool emphasize = false,
  Key? sectionKey,
  TextStyle? titleStyle,
  ValueChanged<bool>? onExpansionChanged,
}) {
  final theme = Theme.of(context);
  final card = Material(
    color: theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: sectionKey,
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      childrenPadding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(icon, color: theme.colorScheme.primary, size: 22),
      title: Text(title, style: titleStyle ?? theme.textTheme.titleSmall),
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

/// Computes weather chart line.
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

/// Computes forecast weather icon.
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
    return Icons.bolt_rounded;
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
