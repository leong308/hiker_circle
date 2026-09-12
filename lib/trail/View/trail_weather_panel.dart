import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Model/trail_models.dart';
import '../Model/trail_precautions.dart';
import '../../core/widgets/running_border.dart';

/// Forecast dates use the trail timezone, never the viewing phone's timezone.
class TrailWeatherPanel extends StatefulWidget {
  const TrailWeatherPanel({
    super.key,
    required this.weather,
    this.elevationGainMeters = 0,
    this.durationMinutes = 0,
  });
  final TrailWeather weather;
  final int elevationGainMeters;
  final int durationMinutes;
  @override
  State<TrailWeatherPanel> createState() => _TrailWeatherPanelState();
}

class _TrailWeatherPanelState extends State<TrailWeatherPanel> {
  int selected = 0;
  int chartMetric = 0;
  TimeOfDay? departure;
  bool showAllPrecautions = false;
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrailWeatherPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.elevationGainMeters <= 250 && chartMetric == 3) chartMetric = 0;
  }

  IconData weatherIcon(num? code) {
    if (code == null) return Icons.cloud_queue_rounded;
    if (code >= 95) return Icons.thunderstorm_outlined;
    if (code >= 51) return Icons.water_drop_outlined;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code <= 1) return Icons.wb_sunny_outlined;
    return Icons.cloud_outlined;
  }

  Map get data => widget.weather.forecastData;
  Map get daily => data['daily'] is Map ? data['daily'] as Map : const {};
  Map get hourly => data['hourly'] is Map ? data['hourly'] as Map : const {};
  List get days => daily['time'] is List ? daily['time'] as List : const [];
  num? value(Map source, String key, int i) {
    final values = source[key];
    if (values is! List || i >= values.length || values[i] is! num) return null;
    final n = values[i] as num;
    return n.isFinite ? n : null;
  }

  DateTime local(num epoch) => DateTime.fromMillisecondsSinceEpoch(
    ((epoch + ((data['utc_offset_seconds'] as num?) ?? 0)) * 1000).round(),
    isUtc: true,
  );
  String clock(num epoch) {
    final t = local(epoch);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String date(num epoch) {
    final t = local(epoch);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[t.weekday - 1]} ${t.day}/${t.month}';
  }

  String condition(num? code) => code == null
      ? 'Conditions unavailable'
      : HourlyForecast(
          time: DateTime(2000),
          temperature: 0,
          precipitationProbability: 0,
          weatherCode: code.toInt(),
        ).weatherLabel;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Before you set off',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final caution in trailPrecautions(
                weather: widget.weather,
                day: 0,
                now: DateTime.now(),
                elevationGain: widget.elevationGainMeters,
                durationMinutes: widget.durationMinutes,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${caution.title}\n${caution.message}'),
                ),
              const Text(
                'Forecast guidance, not a safety clearance. Check official warnings and trail closures.',
              ),
            ],
          ),
        ),
      );
    }
    final i = selected.clamp(0, days.length - 1);
    final theme = Theme.of(context);
    final d = daily;
    final code = value(d, 'weather_code', i);
    final daylight = value(d, 'daylight_duration', i);
    final cautions = trailPrecautions(
      weather: widget.weather,
      day: i,
      now: DateTime.now(),
      elevationGain: widget.elevationGainMeters,
      durationMinutes: widget.durationMinutes,
      departureMinute: departure == null
          ? null
          : departure!.hour * 60 + departure!.minute,
    );
    final visibleCautions = showAllPrecautions
        ? cautions
        : cautions
              .where((c) => c.priority >= 3 || cautions.indexOf(c) < 3)
              .toList();
    final times = hourly['time'] is List ? hourly['time'] as List : const [];
    final indices = <int>[];
    for (var h = 0; h < times.length; h++) {
      if (times[h] is num && date(times[h] as num) == date(days[i] as num)) {
        indices.add(h);
      }
    }
    final low = value(d, 'temperature_2m_min', i);
    final high = value(d, 'temperature_2m_max', i);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var j = 0; j < days.length; j++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(
                          weatherIcon(value(d, 'weather_code', j)),
                          size: 18,
                        ),
                        label: Text(date(days[j] as num)),
                        selected: i == j,
                        onSelected: (_) => setState(() => selected = j),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  weatherIcon(code),
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        condition(code),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (low != null || high != null)
                        Text(
                          [
                            if (low != null) '${low.toStringAsFixed(1)} °C',
                            if (high != null) '${high.toStringAsFixed(1)} °C',
                          ].join(' – '),
                          style: theme.textTheme.titleMedium,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (value(d, 'precipitation_probability_max', i)
                    case final num rain)
                  _metric(
                    context,
                    Icons.water_drop_outlined,
                    'Rain chance',
                    '${rain.round()}%',
                  ),
                if (value(d, 'wind_gusts_10m_max', i) case final num gust)
                  _metric(
                    context,
                    Icons.air_rounded,
                    'Peak gusts',
                    '${gust.round()} km/h',
                  ),
                if (value(d, 'uv_index_max', i) case final num uv)
                  _metric(
                    context,
                    Icons.wb_sunny_outlined,
                    'Peak UV',
                    uv.toStringAsFixed(1),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _chart(context, indices, times),
            if (value(d, 'sunrise', i) != null ||
                value(d, 'sunset', i) != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  if (value(d, 'sunrise', i) case final num rise)
                    _metric(context, Icons.wb_twilight, 'Sunrise', clock(rise)),
                  if (value(d, 'sunset', i) case final num set)
                    _metric(
                      context,
                      Icons.nights_stay_outlined,
                      'Sunset',
                      clock(set),
                    ),
                ],
              ),
              if (daylight != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${(daylight / 3600).toStringAsFixed(1)}h daylight · leave a return buffer',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 24),
            _detailSection(
              context,
              Icons.shield_outlined,
              'Before you set off',
              cautions.isEmpty
                  ? 'Check local conditions before departure'
                  : '${cautions.length} relevant precautions',
              [
                Text(
                  departure == null
                      ? 'Daily outlook · select a departure time for hike-specific advice'
                      : 'Hiking window · ${departure!.format(context)} departure · includes a 60-minute delay buffer',
                ),
                Wrap(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        departure == null
                            ? 'Set departure time'
                            : 'Change departure time',
                      ),
                      onPressed: widget.durationMinutes <= 0
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime:
                                    departure ??
                                    const TimeOfDay(hour: 8, minute: 0),
                              );
                              if (mounted && picked != null) {
                                setState(() {
                                  departure = picked;
                                });
                              }
                            },
                    ),
                    if (departure != null)
                      TextButton(
                        onPressed: () => setState(() => departure = null),
                        child: const Text('Daily outlook'),
                      ),
                  ],
                ),
                if (cautions.isEmpty)
                  const Text(
                    'No specific advisories identified from the available data. Conditions can change.',
                  ),
                for (final caution in visibleCautions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 19,
                          color: caution.priority >= 3
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                caution.title,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                caution.message,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (cautions.length > visibleCautions.length ||
                    showAllPrecautions)
                  TextButton(
                    onPressed: () => setState(
                      () => showAllPrecautions = !showAllPrecautions,
                    ),
                    child: Text(
                      showAllPrecautions
                          ? 'Show fewer'
                          : 'View all ${cautions.length} precautions',
                    ),
                  ),
                Text(
                  'Forecast guidance, not a safety clearance. Water crossings, steep sections, route altitude, air quality and official alerts are not assessed here. Check official warnings and local trail closures.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
              initiallyExpanded: cautions.isNotEmpty,
            ),
            const SizedBox(height: 14),
            _detailSection(
              context,
              Icons.tune_rounded,
              'Daily details',
              'Rainfall, wet hours and wind',
              [
                for (final entry in const {
                  'precipitation_sum': 'Precipitation · mm',
                  'precipitation_hours': 'Wet hours · h',
                  'wind_speed_10m_max': 'Maximum wind · km/h',
                }.entries)
                  if (value(d, entry.key, i) case final num n)
                    _reading(context, entry.value, n.toStringAsFixed(1)),
              ],
            ),
            if (data['current'] is Map) ...[
              const SizedBox(height: 14),
              _detailSection(
                context,
                Icons.wb_cloudy_outlined,
                'Current conditions',
                'Latest model snapshot · separate from selected day',
                [
                  for (final entry in const {
                    'temperature_2m': 'Temperature · °C',
                    'apparent_temperature': 'Feels like · °C',
                    'relative_humidity_2m': 'Humidity · %',
                    'wind_speed_10m': 'Wind · km/h',
                    'wind_gusts_10m': 'Gusts · km/h',
                    'uv_index': 'UV',
                  }.entries)
                    if ((data['current'] as Map)[entry.key] is num)
                      _reading(
                        context,
                        entry.value,
                        '${(data['current'] as Map)[entry.key]}',
                      ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.weather.isStale
                      ? Icons.history_rounded
                      : Icons.update_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.weather.isStale
                            ? 'Cached forecast · check before departure'
                            : 'Forecast updated',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${date(widget.weather.cachedAt.millisecondsSinceEpoch / 1000)} · ${clock(widget.weather.cachedAt.millisecondsSinceEpoch / 1000)}\n${data['timezone'] ?? 'Trail local time'}',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://open-meteo.com/')),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                textStyle: theme.textTheme.bodySmall,
              ),
              child: const Text('Weather data: Open-Meteo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    List<Widget> children, {
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    final card = Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('$title-$selected'),
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
    return title == 'Before you set off'
        ? RunningBorder(color: theme.colorScheme.primary, child: card)
        : card;
  }

  Widget _reading(BuildContext context, String label, String reading) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 16),
          Text(reading, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }

  Widget _metric(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reading, style: Theme.of(context).textTheme.titleSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context, List<int> indices, List times) {
    final keys = [
      'temperature_2m',
      'precipitation_probability',
      'relative_humidity_2m',
      if (widget.elevationGainMeters > 250) 'wind_speed_10m',
    ];
    final labels = [
      'Temperature',
      'Rain',
      'Humidity',
      if (widget.elevationGainMeters > 250) 'Wind',
    ];
    final units = [
      '°C',
      '%',
      '%',
      if (widget.elevationGainMeters > 250) 'km/h',
    ];
    final spots = <FlSpot>[
      for (final h in indices)
        value(hourly, keys[chartMetric], h) == null
            ? FlSpot.nullSpot
            : FlSpot(
                local(times[h] as num).hour.toDouble(),
                value(hourly, keys[chartMetric], h)!.toDouble(),
              ),
    ];
    final available = spots.where((s) => !s.isNull()).toList();
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (var m = 0; m < labels.length; m++)
              ChoiceChip(
                label: Text(labels[m]),
                selected: chartMetric == m,
                onSelected: (_) => setState(() => chartMetric = m),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${labels[chartMetric]} · ${units[chartMetric]} · touch graph for values',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (available.length < 2)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Not enough hourly data for this graph.'),
          )
        else
          Semantics(
            label:
                '${labels[chartMetric]} hourly graph. Touch the graph to inspect values.',
            child: SizedBox(
              height: 145,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 23,
                  minY: chartMetric == 0 ? null : 0,
                  maxY: chartMetric == 1 || chartMetric == 2 ? 100 : null,
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize:
                            44 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1.0, 1.25),
                        minIncluded: false,
                        maxIncluded: false,
                        getTitlesWidget: (v, meta) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 6,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) => Text(
                          '${v.toInt().toString().padLeft(2, '0')}:00',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (points) => points
                          .map(
                            (p) => LineTooltipItem(
                              '${p.x.toInt().toString().padLeft(2, '0')}:00\n${p.y.toStringAsFixed(1)} ${units[chartMetric]}',
                              const TextStyle(color: Colors.white),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: color,
                      barWidth: 2.5,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: .09),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
