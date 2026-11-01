part of '../next_hike_briefing_feature.dart';

/// A scheduled hike briefing; countdown is local, weather is at the trail.
class NextHikeBriefing extends StatefulWidget {
  /// Creates next hike briefing.
  const NextHikeBriefing({
    super.key,
    required this.hike,
    required this.phoneNumber,
    this.plannedHike,
    this.trail,
    this.onReview,
    this.isVisible = true,
    this.weatherService,
    this.isNextHike = true,
  });
  final UpcomingHike hike;
  final String phoneNumber;
  final PlannedHike? plannedHike;
  final Trail? trail;
  final Future<void> Function()? onReview;
  final bool isVisible;
  final HikeBriefingWeatherService? weatherService;
  final bool isNextHike;

  /// Creates the presentation state for this widget.
  @override
  State<NextHikeBriefing> createState() => _NextHikeBriefingState();
}

/// Manages the next hike briefing presentation and lifecycle.
class _NextHikeBriefingState extends State<NextHikeBriefing>
    with WidgetsBindingObserver {
  late final _NextHikeBriefingStateViewModel _screenModel;

  /// Returns weather.
  TrailWeather? get _weather => _screenModel.stateWeather;

  /// Updates weather.
  set _weather(TrailWeather? value) => _screenModel.stateWeather = value;

  /// Returns loading.
  bool get _loading => _screenModel.stateLoading;

  /// Updates loading.
  set _loading(bool value) => _screenModel.stateLoading = value;

  /// Returns failed.
  bool get _failed => _screenModel.stateFailed;

  /// Updates failed.
  set _failed(bool value) => _screenModel.stateFailed = value;

  /// Returns foreground.
  bool get _foreground => _screenModel.stateForeground;

  /// Updates foreground.
  set _foreground(bool value) => _screenModel.stateForeground = value;

  /// Updates retry at.
  set _retryAt(DateTime? value) => _screenModel.stateRetryAt = value;

  /// Returns generation.
  int get _generation => _screenModel.stateGeneration;

  /// Updates generation.
  set _generation(int value) => _screenModel.stateGeneration = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  Timer? _timer;

  /// Returns service.
  HikeBriefingWeatherService get _service => _screenModel.commandService;

  /// Returns beyond forecast.
  bool get _beyondForecast => _screenModel.commandBeyondForecast;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _NextHikeBriefingStateViewModel(
      readHike: () => widget.hike,
      readIsVisible: () => widget.isVisible,
      readTrail: () => widget.trail ?? widget.plannedHike?.trail,
      readWeatherService: () => widget.weatherService,
      readOnReview: () => widget.onReview,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    _seed();
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  /// Delegates seed to the ViewModel.
  void _seed() => _screenModel.commandSeed();

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant NextHikeBriefing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hike.id != widget.hike.id ||
        oldWidget.hike.latitude != widget.hike.latitude ||
        oldWidget.hike.longitude != widget.hike.longitude ||
        oldWidget.hike.departureTime != widget.hike.departureTime ||
        oldWidget.hike.expectedReturnTime != widget.hike.expectedReturnTime) {
      _generation++;
      _loading = false;
      _failed = false;
      _weather = null;
      _retryAt = null;
      _seed();
    }
    _seed();
    _tick();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _tick();
  }

  /// Delegates tick to the ViewModel.
  void _tick() => _screenModel.commandTick();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hike = widget.hike;
    final plan = widget.plannedHike?.withGearProgress();
    return Container(
      key: const ValueKey('next-hike-briefing'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hiking_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.isNextHike ? 'NEXT HIKE' : 'UPCOMING HIKE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .55,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      UpcomingHikePeopleButton(
                        hike: hike,
                        viewerPhone: widget.phoneNumber,
                      ),
                      HikeDepartureExpiryLabel(
                        departure: hike.departureTime,
                        expiresAt: hike.visibleUntil,
                        enabled: widget.isVisible,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hike.trailName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            _dateTime(hike.departureTime).split(' · ').first,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _scheduleTime(
                  context,
                  'Departure',
                  _clockTime(hike.departureTime),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              Expanded(
                child: _scheduleTime(
                  context,
                  'Estimated finish',
                  _returnTime(hike.departureTime, hike.expectedReturnTime),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${hike.distanceKm.toStringAsFixed(1)} km · ${(widget.trail ?? plan?.trail)?.difficultyDisplayLabel ?? 'Difficulty not rated'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          HikeDepartureCountdown(
            departure: hike.departureTime,
            enabled: widget.isVisible,
          ),
          const SizedBox(height: 14),
          _buildWeather(context),
          const SizedBox(height: 10),
          _BriefingAction(
            title: hike.hikeType == 'team'
                ? 'Start team readiness'
                : 'Final preparation review',
            onTap: widget.onReview == null || _screenModel.stateOpeningReview
                ? null
                : () => _screenModel.commandOpenReview(),
            leading: _screenModel.stateOpeningReview
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: plan == null || plan.checklistTotal == 0
                              ? 0
                              : plan.checklistCompleted / plan.checklistTotal,
                          strokeWidth: 3,
                          backgroundColor: scheme.outlineVariant,
                        ),
                      ),
                      Icon(
                        Icons.backpack_outlined,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ],
                  ),
            subtitle: Text(
              _screenModel.stateReviewError ??
                  (_screenModel.stateOpeningReview
                      ? 'Opening your hike…'
                      : hike.hikeType == 'team'
                      ? 'Prepare together and confirm when ready'
                      : plan == null
                      ? 'Build your trail-specific packing list'
                      : '${plan.checklistCompleted}/${plan.checklistTotal} packed · gear & safety'),
            ),
          ),
        ],
      ),
    );
  }

  /// Delegates clock time to the ViewModel.
  String _clockTime(DateTime value) => _screenModel.commandClockTime(value);

  /// Computes schedule time.
  Widget _scheduleTime(BuildContext context, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      );

  /// Builds weather.
  Widget _buildWeather(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weather = _weather;
    final briefing = weather == null
        ? null
        : HikeWeatherBriefing.fromWeather(
            weather,
            widget.hike.departureTime,
            widget.hike.expectedReturnTime,
          );
    final available = briefing?.covered == true;
    final message = _beyondForecast
        ? 'Forecast available closer to departure'
        : _loading
        ? 'Checking hike weather…'
        : _failed
        ? 'Couldn’t refresh weather. Retry.'
        : 'Forecast does not cover this hike yet';
    return _BriefingAction(
      title: 'Hike weather',
      onTap: () => _showForecast(context, weather),
      leading: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant, width: 3),
        ),
        child: Icon(Icons.cloud_outlined, size: 20, color: scheme.primary),
      ),
      subtitle: available
          ? Wrap(
              spacing: 6,
              runSpacing: 3,
              children: [
                Text(
                  briefing!.minTemperature == null
                      ? 'Temperature unavailable'
                      : '${briefing.minTemperature!.round()}–${briefing.maxTemperature!.round()}°C',
                ),
                const Text('·'),
                Text(
                  briefing.peakRainChance == null
                      ? 'Rain unavailable'
                      : '${briefing.peakRainChance!.round()}% peak chance',
                ),
                if (weather!.isStale)
                  Text('Outdated', style: TextStyle(color: scheme.error)),
              ],
            )
          : Text(message),
      trailing: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _screenModel.commandCanReload
          ? IconButton(
              tooltip: 'Reload trail forecast',
              onPressed: () => _screenModel.commandLoad(force: true),
              icon: const Icon(Icons.refresh_rounded),
              color: scheme.primary,
            )
          : null,
    );
  }

  /// Shows forecast.
  void _showForecast(BuildContext context, TrailWeather? weather) {
    final hikeId = widget.hike.id;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HikingForecastSheet(
        hike: widget.hike,
        weather: weather,
        service: _service,
        onWeatherChanged: (updated) {
          if (!mounted || widget.hike.id != hikeId) return;
          setState(() {
            _weather = updated;
            _failed = false;
          });
        },
        elevationGain:
            (widget.trail ?? widget.plannedHike?.trail)?.elevationGainMeters ??
            0,
      ),
    );
  }
}

/// Shared geometry keeps forecast and preparation equally prominent.
class _BriefingAction extends StatelessWidget {
  /// Creates briefing action.
  const _BriefingAction({
    required this.title,
    required this.leading,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });
  final String title;
  final Widget leading, subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 78),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(width: 38, height: 38, child: leading),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      DefaultTextStyle(
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        child: subtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: trailing is IconButton ? 48 : 24,
                  height: trailing is IconButton ? 48 : 24,
                  child: Center(
                    child:
                        trailing ??
                        Icon(
                          Icons.chevron_right_rounded,
                          color: onTap == null
                              ? scheme.outline
                              : scheme.primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Computes return time.
String _returnTime(DateTime start, DateTime end) {
  final a = start.toLocal(), b = end.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day
      ? _clock(b)
      : _dateTime(end);
}

/// Computes clock.
String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// Computes date time.
String _dateTime(DateTime time, {bool convertLocal = true}) {
  final local = convertLocal ? time.toLocal() : time;
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
  return '${local.day} ${months[local.month - 1]} · ${_clock(local)}';
}
