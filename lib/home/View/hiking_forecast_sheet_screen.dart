part of '../hiking_forecast_sheet_feature.dart';

/// Present the requested hike window without changing the active hike's tracking weather controller.
class HikingForecastSheet extends StatefulWidget {
  /// Creates hiking forecast sheet.
  const HikingForecastSheet({
    super.key,
    required this.hike,
    this.weather,
    required this.service,
    this.elevationGain = 0,
    this.onWeatherChanged,
    this.autoplay = true,
  });
  final UpcomingHike hike;
  final TrailWeather? weather;
  final HikeBriefingWeatherService service;
  final int elevationGain;
  final bool autoplay;
  final ValueChanged<TrailWeather>? onWeatherChanged;

  /// Creates the presentation state for this widget.
  @override
  State<HikingForecastSheet> createState() => _ForecastState();
}

/// Manages the hiking forecast sheet presentation and lifecycle.
class _ForecastState extends State<HikingForecastSheet>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final _ForecastStateViewModel _screenModel;

  /// Returns selected.
  DateTime? get _selected => _screenModel.stateSelected;

  /// Updates selected.
  set _selected(DateTime? value) => _screenModel.stateSelected = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Reads forecast state owned by the ViewModel.
  TrailWeather get _weather => _screenModel.stateWeather;
  bool get _loading => _screenModel.stateLoading;
  String? get _error => _screenModel.stateError;

  /// Returns whether the session falls beyond the shared trail forecast range.
  bool get _beyondForecast => _screenModel.commandBeyondForecast;
  int _metric = 0;
  bool _detailsExpanded = false;
  bool _precautionsExpanded = false;
  bool _detailsForHour = false;

  Timer? _previewTimer;
  bool _playing = false;
  bool _autoStarted = false;
  late final AnimationController _timeline;
  late int _renderedHour;

  static const _metrics = [
    ('Temperature', 'temperature_2m', '°C'),
    ('Rain', 'precipitation_probability', '%'),
    ('Wind', 'wind_speed_10m', ' km/h'),
    ('Humidity', 'relative_humidity_2m', '%'),
    ('Rainfall', 'precipitation', 'mm'),
  ];

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ForecastStateViewModel(
      readHike: () => widget.hike,
      readService: () => widget.service,
      weather: widget.weather,
      onWeatherChanged: (value) => widget.onWeatherChanged?.call(value),
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    _renderedHour = widget.hike.departureTime.millisecondsSinceEpoch ~/ 3600000;
    _timeline =
        AnimationController.unbounded(
            vsync: this,
            value: widget.hike.departureTime.millisecondsSinceEpoch.toDouble(),
          )
          ..addListener(_onTimelineFrame)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _playing && mounted) {
              setState(() => _playing = false);
            }
          });
    _scheduleAutoplay();
    final hourly = _weather.forecastData['hourly'];
    if (!_beyondForecast &&
        (widget.weather == null ||
            _weather.isStale ||
            hourly is! Map ||
            !hourly.containsKey('wind_speed_10m') ||
            !HikeWeatherBriefing.fromWeather(
              _weather,
              widget.hike.departureTime,
              widget.hike.expectedReturnTime,
            ).covered)) {
      _refresh(force: false);
    }
  }

  /// Refreshes.
  Future<void> _refresh({bool force = true}) async {
    _stopPreview();
    await _screenModel.commandLoad(force: force);
    if (mounted) _scheduleAutoplay();
  }

  /// Delegates clock to the ViewModel.
  String _clock(DateTime time, Duration offset) =>
      _screenModel.commandClock(time, offset);

  /// Delegates date to the ViewModel.
  String _date(DateTime time, Duration offset) =>
      _screenModel.commandDate(time, offset);

  /// Delegates session time to the ViewModel.
  String _sessionTime(SessionWeatherForecast forecast) =>
      _screenModel.commandSessionTime(forecast);

  /// Delegates temperature range to the ViewModel.
  String _temperatureRange(HikeWeatherBriefing session) =>
      _screenModel.commandTemperatureRange(session);

  /// Delegates value to the ViewModel.
  String _value(double? value, String unit) =>
      _screenModel.commandValue(value, unit);

  /// Delegates range to the ViewModel.
  String _range(({double min, double max})? values, String unit) =>
      _screenModel.commandRange(values, unit);

  /// Returns motion.
  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final forecast = SessionWeatherForecast(
      _weather,
      widget.hike.departureTime,
      widget.hike.expectedReturnTime,
      elevationGain: widget.elevationGain,
    );
    final session = forecast.session, offset = session.utcOffset;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final cautions = forecast.cautions(DateTime.now());
    return DraggableScrollableSheet(
      initialChildSize: .88,
      minChildSize: .55,
      maxChildSize: .96,
      expand: false,
      builder: (context, controller) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your hiking forecast',
                      style: PageHeaderStyle.title(context, scheme.onSurface),
                    ),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: _screenModel.commandCanReload
                          ? 'Reload trail forecast'
                          : 'Reload available after 15 minutes',
                      onPressed: _screenModel.commandCanReload
                          ? _refresh
                          : null,
                      icon: const Icon(Icons.refresh),
                    ),
                  IconButton(
                    tooltip: 'Close forecast',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: _motion,
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - value)),
                    child: child,
                  ),
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(
                      widget.hike.trailName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _sessionTime(forecast),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (session.hours.isEmpty) ...[
                      const SizedBox(height: 24),
                      _notice(
                        _beyondForecast
                            ? 'Forecasts are available up to ${HikeBriefingWeatherService.forecastDays} days ahead. Check again closer to departure.'
                            : _loading
                            ? 'Loading weather for your scheduled hike…'
                            : _error ??
                                  'Forecast data does not cover these hike dates yet. Check again closer to departure.',
                      ),
                      if (!_loading && _screenModel.commandCanReload)
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry forecast'),
                        ),
                    ] else ...[
                      const SizedBox(height: 16),
                      weatherDetailSection(
                        context,
                        Icons.shield_outlined,
                        'Before you set off',
                        '${cautions.length} relevant precautions',
                        [
                          Text(
                            'Hiking window · ${_clock(forecast.departure, offset)} departure · includes two-hour weather buffers',
                          ),
                          const SizedBox(height: 16),
                          if (cautions.isEmpty)
                            const Text(
                              'No specific advisories identified from the available data. Conditions can change.',
                            ),
                          for (final caution in cautions)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CautionIcon(
                                    icon: precautionIcon(caution),
                                    seriousRisk: caution.priority >= 3,
                                    size: 19,
                                    color: caution.priority >= 3
                                        ? scheme.error
                                        : scheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          caution.title,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          caution.message,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(height: 1.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        sectionKey: ValueKey(
                          'forecast-precautions-${widget.hike.id}',
                        ),
                        initiallyExpanded: _precautionsExpanded,
                        onExpansionChanged: (expanded) =>
                            setState(() => _precautionsExpanded = expanded),
                        titleStyle: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        emphasize: true,
                      ),
                      const SizedBox(height: 14),
                      _explorer(forecast),
                      if (!session.covered)
                        _notice(
                          'The forecast does not cover the full session. Summary values are unavailable.',
                        ),
                      if (_weather.isStale)
                        _notice(
                          'Outdated forecast · refresh before making plans.',
                        ),
                      if (_error != null) _notice(_error!),
                      const SizedBox(height: 20),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          _daylight(
                            Icons.wb_twilight,
                            'Sunrise',
                            session.sunrise == null
                                ? 'Unavailable'
                                : _clock(session.sunrise!, offset),
                          ),
                          _daylight(
                            Icons.nights_stay_outlined,
                            'Sunset',
                            session.sunset == null
                                ? 'Unavailable'
                                : _clock(session.sunset!, offset),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _conditionsPanel(forecast),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _previewTimer?.cancel();
    _timeline.dispose();
    WidgetsBinding.instance.removeObserver(this);

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopPreview();
  }

  /// Stops preview.
  void _stopPreview() {
    _timeline.stop();
    _previewTimer?.cancel();
    _previewTimer = null;
    if (_playing && mounted) setState(() => _playing = false);
  }

  /// Selects time.
  void _selectTime(DateTime time) {
    _stopPreview();
    _timeline.value = time.millisecondsSinceEpoch.toDouble();
  }

  /// Computes change metric.
  void _changeMetric(int delta) =>
      setState(() => _metric = (_metric + delta) % _metrics.length);

  // The graph cursor and slider listen directly to the timeline. Rebuild the
  // readings only at hourly boundaries, not the entire sheet on every frame.
  /// Computes on timeline frame.
  void _onTimelineFrame() {
    _selected = DateTime.fromMillisecondsSinceEpoch(
      _timeline.value.round(),
      isUtc: true,
    );
    final hour = _timeline.value ~/ 3600000;
    if (hour != _renderedHour && mounted) {
      setState(() => _renderedHour = hour);
    }
  }

  /// Computes schedule autoplay.
  void _scheduleAutoplay() {
    if (!widget.autoplay || _autoStarted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || _autoStarted) return;
      final forecast = SessionWeatherForecast(
        _weather,
        widget.hike.departureTime,
        widget.hike.expectedReturnTime,
      );
      if (forecast.buffer.hours.length < 2) return;
      _autoStarted = true;
      _togglePreview(forecast);
    });
  }

  /// Toggles preview.
  void _togglePreview(SessionWeatherForecast forecast) {
    if (_playing) {
      _stopPreview();
      return;
    }
    if (forecast.buffer.hours.length < 2) return;
    final from = forecast.from.millisecondsSinceEpoch.toDouble();
    final end = forecast.to.millisecondsSinceEpoch.toDouble();
    var start = _selected == null ? from : _timeline.value.clamp(from, end);
    if (start >= end) start = from;
    setState(() => _playing = true);
    _timeline.value = start;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Retain explicit playback controls without continuous motion.
      _previewTimer = Timer.periodic(const Duration(milliseconds: 1200), (
        timer,
      ) {
        _timeline.value = math.min(_timeline.value + 3600000, end);
        if (_timeline.value >= end) _stopPreview();
      });
    } else {
      _timeline.animateTo(
        end,
        duration: Duration(
          milliseconds: ((end - start) / 3600000 * 1200).round(),
        ),
        curve: Curves.linear,
      );
    }
  }

  /// Delegates phase to the ViewModel.
  String _phase(HikeWeatherHour hour, SessionWeatherForecast forecast) =>
      _screenModel.commandPhase(hour, forecast);

  /// Computes explorer.
  Widget _explorer(SessionWeatherForecast forecast) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final hours = forecast.buffer.hours;
    final hour = hours.isEmpty ? null : _selectedHour(forecast);
    final metric = _metrics[_metric];
    final summary = _metric == 0
        ? 'Hike range · ${_temperatureRange(forecast.session)}'
        : 'Hike peak · ${_value(forecast.peak(metric.$2), metric.$3)}';
    final icons = [
      Icons.thermostat_outlined,
      Icons.water_drop_outlined,
      Icons.air_rounded,
      Icons.water_outlined,
      Icons.grain_rounded,
    ];
    return Container(
      key: const ValueKey('forecast-explorer'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _scheduleButton(
                  'Departure',
                  forecast.departure,
                  Icons.play_circle_outline_rounded,
                  forecast,
                  'Jump to departure',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _scheduleButton(
                  'Estimated finish',
                  forecast.returning,
                  Icons.flag_outlined,
                  forecast,
                  'Jump to estimated finish',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const ValueKey('forecast-metric-swipe'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final speed = details.primaryVelocity ?? 0;
              if (speed.abs() > 80) _changeMetric(speed < 0 ? 1 : -1);
            },
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous weather metric',
                      onPressed: () => _changeMetric(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            metric.$1,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _metrics.length; i++)
                                AnimatedContainer(
                                  duration: _motion,
                                  height: 4,
                                  width: _metric == i ? 16 : 4,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: _metric == i
                                        ? scheme.primary
                                        : scheme.outlineVariant,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next weather metric',
                      onPressed: () => _changeMetric(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: _motion,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Row(
                    key: ValueKey('$_metric-${hour?.value(metric.$2)}'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[_metric], size: 30, color: scheme.primary),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _value(hour?.value(metric.$2), metric.$3),
                          key: const ValueKey('forecast-hour-value'),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hour == null
                ? '${_date(_selected ?? forecast.departure, forecast.session.utcOffset)} · No hourly data available'
                : '${_date(hour.time, forecast.session.utcOffset)}–${_clock(hour.time.add(const Duration(hours: 1)), forecast.session.utcOffset)} · ${_phase(hour, forecast)}',
            key: const ValueKey('forecast-selected-time'),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: _motion,
            child: KeyedSubtree(
              key: ValueKey('forecast-chart-$_metric'),
              child: _chart(forecast),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: _playing
                    ? 'Pause hourly preview'
                    : 'Play hourly preview',
                onPressed: hours.length < 2
                    ? null
                    : () => _togglePreview(forecast),
                icon: AnimatedSwitcher(
                  duration: _motion,
                  child: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey(_playing),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _timeline,
                  builder: (context, child) {
                    final from = forecast.from.millisecondsSinceEpoch
                        .toDouble();
                    final to = forecast.to.millisecondsSinceEpoch.toDouble();
                    return Slider(
                      key: const ValueKey('forecast-time-slider'),
                      value: _timeline.value.clamp(from, to),
                      min: from,
                      max: math.max(from + 1, to),
                      semanticFormatterCallback: (value) => _date(
                        DateTime.fromMillisecondsSinceEpoch(
                          value.round(),
                          isUtc: true,
                        ),
                        forecast.session.utcOffset,
                      ),
                      onChangeStart: hours.length < 2
                          ? null
                          : (_) => _stopPreview(),
                      onChanged: hours.length < 2
                          ? null
                          : (value) => _selectTime(
                              DateTime.fromMillisecondsSinceEpoch(
                                value.round(),
                                isUtc: true,
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
          Text(
            'Hourly · 2h before + after · shaded area is your hike',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Computes schedule button.
  Widget _scheduleButton(
    String label,
    DateTime time,
    IconData icon,
    SessionWeatherForecast forecast,
    String tooltip,
  ) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: forecast.buffer.hours.isEmpty ? null : () => _selectTime(time),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(label, style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _clock(time, forecast.session.utcOffset),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _date(time, forecast.session.utcOffset).split(' · ').first,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Computes notice.
  Widget _notice(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );

  /// Computes daylight.
  Widget _daylight(IconData icon, String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          '$label $value',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  /// Computes chart.
  Widget _chart(SessionWeatherForecast forecast) {
    final key = _metrics[_metric].$2;
    final percent = _metrics[_metric].$3 == '%';
    final total = forecast.to.difference(forecast.from).inSeconds / 3600;
    final points = <FlSpot>[];
    final values = <double>[];
    DateTime? previous;
    for (final hour in forecast.buffer.hours) {
      if (previous != null &&
          hour.time.difference(previous) != const Duration(hours: 1)) {
        points.add(FlSpot.nullSpot);
      }
      previous = hour.time;
      final value = hour.value(key);
      final x = hour.time.difference(forecast.from).inSeconds / 3600;
      if (value == null) {
        points.add(FlSpot.nullSpot);
        continue;
      }
      values.add(value);
      // Connect hourly samples like the trail graph. This is a visual trend,
      // not a higher-frequency forecast. Gaps remain explicit.
      points.add(FlSpot(x.clamp(0, total), value));
    }
    if (points.isNotEmpty &&
        !points.last.isNull() &&
        previous != null &&
        !previous.add(const Duration(hours: 1)).isBefore(forecast.to)) {
      points.add(FlSpot(total, points.last.y));
    }
    if (values.isEmpty || total <= 0) {
      return SizedBox(
        height: 130,
        child: Center(
          child: Text(
            'No ${_metrics[_metric].$1.toLowerCase()} data for this window.',
          ),
        ),
      );
    }
    final min = _metric == 0
        ? values.reduce(math.min).floorToDouble() - 2
        : 0.0;
    final max = percent
        ? 100.0
        : math.max(min + 4, values.reduce(math.max) * 1.15).ceilToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: LayoutBuilder(
            builder: (context, constraints) {
              /// Computes inspect.
              void inspect(Offset point) {
                final left =
                    44 *
                    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.25);
                final fraction =
                    ((point.dx - left) /
                            math.max(1, constraints.maxWidth - left))
                        .clamp(0.0, 1.0);
                _selectTime(
                  forecast.from.add(
                    Duration(
                      milliseconds:
                          (forecast.to
                                      .difference(forecast.from)
                                      .inMilliseconds *
                                  fraction)
                              .round(),
                    ),
                  ),
                );
              }

              return MouseRegion(
                onHover: (event) => inspect(event.localPosition),
                child: Listener(
                  key: const ValueKey('forecast-touch-surface'),
                  onPointerDown: (event) => inspect(event.localPosition),
                  onPointerMove: (event) => inspect(event.localPosition),
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: LineChart(
                          duration: _motion,
                          curve: Curves.easeOutCubic,
                          LineChartData(
                            minX: 0,
                            maxX: total,
                            minY: min,
                            maxY: max,
                            clipData: const FlClipData.all(),
                            rangeAnnotations: RangeAnnotations(
                              verticalRangeAnnotations: [
                                VerticalRangeAnnotation(
                                  x1: 2,
                                  x2: total - 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .10),
                                ),
                              ],
                            ),
                            extraLinesData: ExtraLinesData(
                              verticalLines: [
                                VerticalLine(
                                  x: 2,
                                  label: VerticalLineLabel(
                                    show: true,
                                    alignment: Alignment.topLeft,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    labelResolver: (_) =>
                                        'Departure\n${_clock(forecast.departure, forecast.session.utcOffset)}',
                                  ),
                                  color: Theme.of(context).colorScheme.primary,
                                  strokeWidth: 1,
                                  dashArray: [4, 4],
                                ),
                                VerticalLine(
                                  x: total - 2,
                                  label: VerticalLineLabel(
                                    show: true,
                                    alignment: Alignment.topRight,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    labelResolver: (_) =>
                                        'Finish\n${_clock(forecast.returning, forecast.session.utcOffset)}',
                                  ),
                                  color: Theme.of(context).colorScheme.primary,
                                  strokeWidth: 1,
                                  dashArray: [4, 4],
                                ),
                              ],
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              horizontalInterval: percent ? 25 : null,
                            ),
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
                                  interval: percent ? 25 : null,
                                  getTitlesWidget: (v, _) => Text(
                                    v.toStringAsFixed(0),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  interval: math.max(
                                    1,
                                    (total / 3).ceilToDouble(),
                                  ),
                                  minIncluded: false,
                                  maxIncluded: false,
                                  getTitlesWidget: (v, _) => Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      _clock(
                                        forecast.from.add(
                                          Duration(seconds: (v * 3600).round()),
                                        ),
                                        forecast.session.utcOffset,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            lineBarsData: [weatherChartLine(context, points)],
                            lineTouchData: const LineTouchData(enabled: false),
                          ),
                        ),
                      ),
                      Positioned(
                        left:
                            44 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1.0, 1.25),
                        right: 0,
                        top: 0,
                        bottom: 28,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _timeline,
                            builder: (context, child) {
                              final from = forecast.from.millisecondsSinceEpoch
                                  .toDouble();
                              final span = forecast.to
                                  .difference(forecast.from)
                                  .inMilliseconds;
                              final progress = ((_timeline.value - from) / span)
                                  .clamp(0.0, 1.0);
                              return Align(
                                key: const ValueKey('forecast-time-cursor'),
                                alignment: Alignment(progress * 2 - 1, 0),
                                child: child,
                              );
                            },
                            child: Container(
                              width: 1.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .55),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Delegates selected hour to the ViewModel.
  HikeWeatherHour? _selectedHour(SessionWeatherForecast forecast) =>
      _screenModel.commandSelectedHour(forecast);

  /// Computes conditions panel.
  Widget _conditionsPanel(SessionWeatherForecast forecast) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'More session conditions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Explore comfort, wind and visibility',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _detailsExpanded ? .5 : 0,
                      duration: _motion,
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_motion == Duration.zero)
            if (_detailsExpanded) _extraDetails(forecast),
          if (_motion != Duration.zero)
            AnimatedSize(
              duration: _motion,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _detailsExpanded
                  ? _extraDetails(forecast)
                  : const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
  }

  /// Computes extra details.
  Widget _extraDetails(SessionWeatherForecast forecast) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final hour = _selectedHour(forecast);
    final metrics = _detailsForHour
        ? [
            (
              'Feels like',
              _value(hour?.value('apparent_temperature'), '°C'),
              Icons.thermostat_outlined,
            ),
            (
              'Rain chance',
              _value(hour?.rainChance, '%'),
              Icons.water_drop_outlined,
            ),
            (
              'Rainfall',
              _value(hour?.value('precipitation'), 'mm'),
              Icons.grain_rounded,
            ),
            (
              'Wind',
              _value(hour?.value('wind_speed_10m'), ' km/h'),
              Icons.air_rounded,
            ),
            (
              'Gusts',
              _value(hour?.value('wind_gusts_10m'), ' km/h'),
              Icons.speed_rounded,
            ),
            (
              'Humidity',
              _value(hour?.value('relative_humidity_2m'), '%'),
              Icons.water_outlined,
            ),
            (
              'UV index',
              _value(hour?.value('uv_index'), ''),
              Icons.wb_sunny_outlined,
            ),
            (
              'Visibility',
              _value(
                hour?.value('visibility') == null
                    ? null
                    : hour!.value('visibility')! / 1000,
                ' km',
              ),
              Icons.visibility_outlined,
            ),
          ]
        : [
            (
              'Feels like',
              _range(forecast.range('apparent_temperature'), '°C'),
              Icons.thermostat_outlined,
            ),
            (
              'Gusts',
              _range(forecast.range('wind_gusts_10m'), ' km/h'),
              Icons.speed_rounded,
            ),
            (
              'Humidity',
              _range(forecast.range('relative_humidity_2m'), '%'),
              Icons.water_outlined,
            ),
            (
              'UV index',
              _range(forecast.range('uv_index'), ''),
              Icons.wb_sunny_outlined,
            ),
            (
              'Hourly rainfall',
              _range(forecast.range('precipitation'), 'mm'),
              Icons.grain_rounded,
            ),
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Hike summary'),
                selected: !_detailsForHour,
                onSelected: (_) => setState(() => _detailsForHour = false),
              ),
              ChoiceChip(
                label: const Text('Selected hour'),
                selected: _detailsForHour,
                onSelected: (_) => setState(() => _detailsForHour = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _detailsForHour
                ? hour == null
                      ? 'No data for the selected hour'
                      : '${_date(hour.time, forecast.session.utcOffset)} · ${_condition(hour)}'
                : 'Ranges during your planned hike',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 260 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.4
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(metric.$3, size: 20, color: scheme.primary),
                            const SizedBox(height: 8),
                            Text(
                              metric.$2,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              metric.$1,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Delegates condition to the ViewModel.
  String _condition(HikeWeatherHour hour) =>
      _screenModel.commandCondition(hour);
}
