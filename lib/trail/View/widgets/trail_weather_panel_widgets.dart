part of '../../trail_weather_panel_feature.dart';

/// Forecast dates use the trail timezone, never the viewing phone's timezone.
class TrailWeatherPanel extends StatefulWidget {
  /// Creates trail weather panel.
  const TrailWeatherPanel({
    super.key,
    required this.weather,
    this.trail,
    this.loadLocationWeather,
    this.elevationGainMeters = 0,
    this.durationMinutes = 0,
    this.onDepartureChanged,
  });
  final ValueChanged<DateTime?>? onDepartureChanged;
  final TrailWeather weather;
  final Trail? trail;
  final Stream<TrailWeather> Function(Trail, TrailWeatherLocation)?
  loadLocationWeather;
  final int elevationGainMeters;
  final int durationMinutes;

  /// Creates the presentation state for this widget.
  @override
  State<TrailWeatherPanel> createState() => _TrailWeatherPanelState();
}

/// Manages the trail weather panel presentation and lifecycle.
class _TrailWeatherPanelState extends State<TrailWeatherPanel> {
  late final _TrailWeatherPanelStateViewModel _screenModel;

  /// Returns selected.
  int get selected => _screenModel.stateSelected;

  /// Updates selected.
  set selected(int value) => _screenModel.stateSelected = value;

  /// Returns departure.
  TimeOfDay? get departure => _screenModel.stateDeparture;

  /// Updates departure.
  set departure(TimeOfDay? value) => _screenModel.stateDeparture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  int chartMetric = 0;

  final Set<String> _expandedCautions = {};
  Timer? _freshnessTimer;

  /// Delegates notify departure changed to the ViewModel.
  void _notifyDepartureChanged() =>
      _screenModel.commandNotifyDepartureChanged();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _TrailWeatherPanelStateViewModel(
      readOnDepartureChanged: () => widget.onDepartureChanged,
      readWeather: () => widget.weather,
      readTrail: () => widget.trail,
      readLocationWeather: () => widget.loadLocationWeather,
    )..addListener(_renderScreenModel);

    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _freshnessTimer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant TrailWeatherPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trail?.trailId != widget.trail?.trailId ||
        !_screenModel.commandLocations.any(
          (point) => point.key == _screenModel.stateLocationKey,
        )) {
      _screenModel.commandResetLocations();
    }
  }

  /// Returns data.
  Map get data => _screenModel.commandData;

  /// Returns daily.
  Map get daily => _screenModel.commandDaily;

  /// Returns hourly.
  Map get hourly => _screenModel.commandHourly;

  /// Returns days.
  List get days => _screenModel.commandDays;

  /// Delegates value to the ViewModel.
  num? value(Map source, String key, int i) =>
      _screenModel.commandValue(source, key, i);

  /// Delegates local to the ViewModel.
  DateTime local(num epoch) => _screenModel.commandLocal(epoch);

  /// Delegates clock to the ViewModel.
  String clock(num epoch) => _screenModel.commandClock(epoch);

  /// Delegates date to the ViewModel.
  String date(num epoch) => _screenModel.commandDate(epoch);

  /// Delegates condition to the ViewModel.
  String condition(num? code) => _screenModel.commandCondition(code);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (!_screenModel.commandHasLocationWeather) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _locationPicker(),
              const SizedBox(height: 16),
              if (_screenModel.stateLoadingLocation) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                const Text('Loading checkpoint forecast…'),
              ],
              if (_screenModel.stateLocationError != null) _locationError(),
            ],
          ),
        ),
      );
    }
    if (days.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.trail != null && widget.trail!.distanceKm > 3) ...[
                _locationPicker(),
                const SizedBox(height: 16),
              ],
              Text(
                'Before you set off now',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final caution in trailPrecautions(
                weather: _screenModel.commandWeather,
                day: 0,
                now: DateTime.now(),
                elevationGain: widget.elevationGainMeters,
                durationMinutes: widget.durationMinutes,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _precautionCard(caution, 'unavailable'),
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
      weather: _screenModel.commandWeather,
      day: i,
      now: DateTime.now(),
      elevationGain: widget.elevationGainMeters,
      durationMinutes: widget.durationMinutes,
      departureMinute: departure == null
          ? null
          : departure!.hour * 60 + departure!.minute,
    );
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
            if (widget.trail != null && widget.trail!.distanceKm > 3) ...[
              _locationPicker(),
              const SizedBox(height: 16),
            ],
            if (_screenModel.stateLocationError != null) _locationError(),
            if (_screenModel.stateRefreshingLocation) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Text('Select day', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ForecastScrollRow(
              key: const ValueKey('forecast-dates-scroll'),
              children: [
                for (var j = 0; j < days.length; j++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        forecastWeatherIcon(value(d, 'weather_code', j)),
                        size: 18,
                      ),
                      label: Text(date(days[j] as num)),
                      selected: i == j,
                      onSelected: (_) {
                        setState(() => selected = j);
                        _notifyDepartureChanged();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  forecastWeatherIcon(code),
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
            _chart(context, indices, times),
            if (value(d, 'sunrise', i) != null ||
                value(d, 'sunset', i) != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  if (value(d, 'sunrise', i) case final num rise)
                    weatherMetric(
                      context,
                      Icons.wb_twilight,
                      'Sunrise',
                      clock(rise),
                    ),
                  if (value(d, 'sunset', i) case final num set)
                    weatherMetric(
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
            const SizedBox(height: 14),
            ForecastScrollRow(
              key: const ValueKey('forecast-summary-scroll'),
              children: [
                if (value(d, 'precipitation_probability_max', i)
                    case final num rain)
                  weatherMetric(
                    context,
                    Icons.water_drop_outlined,
                    'Rain chance',
                    '${rain.round()}%',
                  ),
                if (value(d, 'wind_gusts_10m_max', i) case final num gust)
                  weatherMetric(
                    context,
                    Icons.air_rounded,
                    'Peak gusts',
                    '${gust.round()} km/h',
                  ),
                if (value(d, 'uv_index_max', i) case final num uv)
                  weatherMetric(
                    context,
                    Icons.wb_sunny_outlined,
                    'Peak UV',
                    uv.toStringAsFixed(1),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _precautionsSection(context, [
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
                              _notifyDepartureChanged();
                            }
                          },
                  ),
                  if (departure != null)
                    TextButton(
                      onPressed: () {
                        setState(() => departure = null);
                        _notifyDepartureChanged();
                      },
                      child: const Text('Daily outlook'),
                    ),
                ],
              ),
              if (cautions.isEmpty)
                const Text(
                  'No specific advisories identified from the available data. Conditions can change.',
                ),
              for (final caution in cautions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _precautionCard(
                    caution,
                    '${value(d, 'time', i)?.toInt() ?? i}',
                  ),
                ),
              Text(
                'Forecast guidance, not a safety clearance. Water crossings, steep sections, route altitude, air quality and official alerts are not assessed here. Check official warnings and local trail closures.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ]),
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
            _forecastFreshnessCard(context),
          ],
        ),
      ),
    );
  }

  /// Places the forecast coordinate selector before the day picker.
  Widget _locationPicker() => DropdownButtonFormField<String>(
    key: ValueKey(
      'forecast-location-${widget.trail?.trailId}-${_screenModel.stateLocationKey}',
    ),
    initialValue: _screenModel.stateLocationKey,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Forecast location',
      prefixIcon: Icon(Icons.location_on_outlined),
    ),
    items: [
      for (final location in _screenModel.commandLocations)
        DropdownMenuItem(
          value: location.key,
          child: Text(
            location.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (key) {
      if (key != null) _screenModel.commandSelectLocation(key);
    },
  );

  /// Keeps retry beside the affected forecast instead of silently changing locations.
  Widget _locationError() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _screenModel.stateLocationError!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      TextButton.icon(
        onPressed: () => _screenModel.commandSelectLocation(
          _screenModel.stateLocationKey,
          retry: true,
        ),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry forecast'),
      ),
    ],
  );

  /// Computes precaution card.
  Widget _precautionCard(TrailPrecaution caution, String scope) {
    final id = '$scope:${caution.id}';
    return TrailPrecautionCard(
      key: ValueKey('trail-precaution-$id'),
      caution: caution,
      initiallyExpanded: _expandedCautions.contains(id),
      onExpansionChanged: (expanded) => setState(() {
        if (expanded) {
          _expandedCautions.add(id);
        } else {
          _expandedCautions.remove(id);
        }
      }),
    );
  }

  /// Computes precautions section.
  Widget _precautionsSection(BuildContext context, List<Widget> children) {
    final theme = Theme.of(context);
    return RunningBorder(
      color: theme.colorScheme.primary,
      radius: 18,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Before you set off now',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Computes detail section.
  Widget _detailSection(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    List<Widget> children, {
    bool initiallyExpanded = false,
  }) => weatherDetailSection(
    context,
    icon,
    title,
    subtitle,
    children,
    initiallyExpanded: initiallyExpanded,
    emphasize: title == 'Before you set off now',
    sectionKey: ValueKey('$title-$selected'),
    titleStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  );

  /// Computes forecast freshness card.
  Widget _forecastFreshnessCard(BuildContext context) {
    final theme = Theme.of(context);
    final cachedEpoch =
        _screenModel.commandWeather.cachedAt.millisecondsSinceEpoch / 1000;
    final timezone = data['timezone']?.toString().trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _screenModel.commandWeather.isStale
                  ? Icons.history_rounded
                  : Icons.cloud_done_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _screenModel.commandWeather.isStale
                      ? 'Forecast expired'
                      : 'Forecast is up to date',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Updated ${date(cachedEpoch)} at ${clock(cachedEpoch)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (timezone != null && timezone.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          timezone.replaceAll('_', ' '),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_screenModel.stateLocationKey !=
                        TrailWeatherLocation.trailheadKey &&
                    _screenModel.commandWeather.isStale)
                  TextButton.icon(
                    onPressed: _screenModel.stateRefreshingLocation
                        ? null
                        : () => _screenModel.commandSelectLocation(
                            _screenModel.stateLocationKey,
                            retry: true,
                          ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh forecast'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Computes reading.
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

  /// Computes chart.
  Widget _chart(BuildContext context, List<int> indices, List times) {
    final keys = [
      'temperature_2m',
      'precipitation_probability',
      'relative_humidity_2m',
      'wind_speed_10m',
    ];
    final labels = ['Temperature', 'Rain', 'Humidity', 'Wind'];
    final units = ['°C', '%', '%', 'km/h'];
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (var m = 0; m < labels.length; m++)
              Tooltip(
                message: labels[m],
                child: Semantics(
                  label: labels[m],
                  selected: chartMetric == m,
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Icon(
                      const [
                        Icons.thermostat_rounded,
                        Icons.water_drop_outlined,
                        Icons.water_outlined,
                        Icons.air_rounded,
                      ][m],
                      size: 22,
                    ),
                    selected: chartMetric == m,
                    onSelected: (_) => setState(() => chartMetric = m),
                  ),
                ),
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
                  lineBarsData: [weatherChartLine(context, spots)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
