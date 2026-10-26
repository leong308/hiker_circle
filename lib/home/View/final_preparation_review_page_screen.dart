part of '../final_preparation_review_page_feature.dart';

/// Final packing and conditions review after the hiker confirms safety settings.
class FinalPreparationReviewPage extends StatefulWidget {
  /// Creates final preparation review page.
  const FinalPreparationReviewPage({
    super.key,
    required this.hike,
    required this.isHost,
    required this.canStart,
    this.plan,
    this.onPlanChanged,
    this.onCancel,
    this.loadRouteAnalysis,
    this.loadWeather,
    required this.onStart,
    this.immediate = false,
    this.primaryActionLabel,
    this.loadBatteryLevel,
  });
  final UpcomingHike hike;
  final bool immediate;
  final String? primaryActionLabel;
  final Future<bool> Function(PlannedHike) onStart;
  final Future<TrailWeather> Function()? loadWeather;
  final bool isHost, canStart;
  final PlannedHike? plan;
  final Future<void> Function(PlannedHike)? onPlanChanged;
  final Future<void> Function()? onCancel;
  final Future<RouteGearAssessment> Function(bool force)? loadRouteAnalysis;
  final Future<int?> Function()? loadBatteryLevel;

  /// Creates the presentation state for this widget.
  @override
  State<FinalPreparationReviewPage> createState() => _PreparationState();
}

/// Keep the final review's draft answers local until the caller accepts the preparation result.
class _PreparationState extends State<FinalPreparationReviewPage>
    with WidgetsBindingObserver {
  /// Returns start in flight.
  bool get _startInFlight => _screenModel.stateStartInFlight;

  /// Updates start in flight.
  set _startInFlight(bool value) => _screenModel.stateStartInFlight = value;

  /// Returns completion delivered.
  bool get _completionDelivered => _screenModel.stateCompletionDelivered;

  late final _PreparationStateViewModel _screenModel;

  /// Returns busy.
  bool get _busy => _screenModel.stateBusy;

  /// Updates busy.
  set _busy(bool value) => _screenModel.stateBusy = value;

  /// Returns start requested.
  bool get _startRequested => _screenModel.stateStartRequested;

  /// Updates start requested.
  set _startRequested(bool value) => _screenModel.stateStartRequested = value;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Updates error.
  set _error(String? value) => _screenModel.stateError = value;

  /// Returns analyzing.
  bool get _analyzing => _screenModel.stateAnalyzing;

  /// Updates analyzing.
  set _analyzing(bool value) => _screenModel.stateAnalyzing = value;

  /// Returns checking weather.
  bool get _checkingWeather => _screenModel.stateCheckingWeather;

  /// Updates checking weather.
  set _checkingWeather(bool value) => _screenModel.stateCheckingWeather = value;

  /// Returns pending gear saves.
  int get _pendingGearSaves => _screenModel.statePendingGearSaves;

  /// Updates pending gear saves.
  set _pendingGearSaves(int value) =>
      _screenModel.statePendingGearSaves = value;

  /// Returns opening details.
  bool get _openingDetails => _screenModel.stateOpeningDetails;

  /// Returns loading battery.
  bool get _loadingBattery => _screenModel.stateLoadingBattery;

  /// Updates loading battery.
  set _loadingBattery(bool value) => _screenModel.stateLoadingBattery = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late PlannedHike? _plan = widget.plan;

  String? _weatherNotice;
  bool _routeFailed = false;

  int _gearEditRevision = 0;
  Future<void> _gearSaveQueue = Future.value();
  late Set<String> _confirmedGearItems;
  final ScrollController _scroll = ScrollController();

  Timer? _batteryTimer;

  /// Returns interaction busy.
  bool get _interactionBusy => _screenModel.commandInteractionBusy;

  /// Returns saving gear.
  bool get _savingGear => _screenModel.commandSavingGear;

  /// Returns checking conditions.
  bool get _checkingConditions => _screenModel.commandCheckingConditions;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _PreparationStateViewModel(
      readHike: () => widget.hike,
      readImmediate: () => widget.immediate,
      readIsHost: () => widget.isHost,
      readPrimaryActionLabel: () => widget.primaryActionLabel,
    )..addListener(_renderScreenModel);
    _screenModel.readOnStart = () => widget.onStart;
    _screenModel.effectPresentStartHikeEffect1 = _presentStartHikeEffect1;

    _confirmedGearItems = {...?_plan?.completedChecklistItems};
    WidgetsBinding.instance.addObserver(this);
    _analyzeRoute();
    _refreshWeather();
    _refreshBattery();
    _batteryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_plan != null) {
        unawaited(_refreshBattery());
      }
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryTimer?.cancel();
    _scroll.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_completionDelivered) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBattery());
      if (_plan != null &&
          DateTime.now().difference(_plan!.trail.weather.cachedAt) >
              const Duration(minutes: 15)) {
        unawaited(_refreshWeather());
      }
    }
  }

  /// Refreshes battery.
  Future<void> _refreshBattery() async {
    if (widget.loadBatteryLevel == null || _loadingBattery) {
      return;
    }
    setState(() => _loadingBattery = true);
    int? level;
    try {
      level = await widget.loadBatteryLevel!().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      /* Display unavailable. */
    }
    if (mounted) {
      setState(() {
        _plan = _plan?.copyWith(
          phoneBatteryLevel: level?.clamp(0, 100) ?? 0,
          hasKnownBatteryLevel: level != null,
        );
        _loadingBattery = false;
      });
    }
  }

  /// Delegates open details to the ViewModel.
  Future<void> _openDetails(
    Future<void> Function() open, {
    Future<void> Function()? refresh,
  }) => _screenModel.commandOpenDetails(open, refresh: refresh);

  /// Opens forecast.
  Future<void> _openForecast() => _openDetails(
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HikingForecastSheet(
        hike: widget.hike,
        weather: _plan!.trail.weather,
        service: HikeBriefingWeatherService.shared,
        elevationGain: _plan!.trail.elevationGainMeters,
        onWeatherChanged: (weather) {
          if (mounted) {
            setState(() {
              _plan = _plan!
                  .copyWith(trail: _plan!.trail.copyWith(weather: weather))
                  .withGearProgress();
              _weatherNotice = null;
            });
          }
        },
      ),
    ),
  );

  /// Refreshes weather.
  Future<void> _refreshWeather() async {
    if (_plan == null || widget.loadWeather == null || _checkingWeather) {
      return;
    }
    setState(() => _checkingWeather = true);
    try {
      final weather = await widget.loadWeather!();
      if (!mounted) {
        return;
      }
      setState(() {
        _plan = _plan!
            .copyWith(trail: _plan!.trail.copyWith(weather: weather))
            .withGearProgress();
        final forecast = HikeWeatherBriefing.fromWeather(
          weather,
          _plan!.plannedStartTime,
          _plan!.expectedReturnTime,
        );
        _weatherNotice =
            !forecast.covered ||
                forecast.minTemperature == null ||
                forecast.peakRainChance == null
            ? 'Forecast coverage is incomplete. Cold and wet requirements may need extra checking.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _weatherNotice =
              'Weather could not be refreshed. Check current conditions before departure.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checkingWeather = false);
        _completeRequestedStart();
      }
    }
  }

  /// Computes analyze route.
  Future<void> _analyzeRoute({bool force = false}) async {
    if (_analyzing || widget.loadRouteAnalysis == null || _plan == null) {
      return;
    }
    setState(() {
      _analyzing = true;
      _routeFailed = false;
    });
    try {
      final result = await widget.loadRouteAnalysis!(force);
      if (mounted) {
        setState(
          () => _plan = _plan!
              .copyWith(gearAssessment: result)
              .withGearProgress(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _routeFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
        _completeRequestedStart();
      }
    }
  }

  /// Saves gear.
  Future<bool> _saveGear(Set<String> items) {
    final plan = _plan;
    if (plan == null || widget.onPlanChanged == null || _interactionBusy) {
      return Future.value(false);
    }
    final revision = ++_gearEditRevision;
    final updated = plan
        .copyWith(completedChecklistItems: Set<String>.unmodifiable(items))
        .withGearProgress();
    setState(() {
      _pendingGearSaves++;
      _error = null;
      _plan = updated;
    });
    final result = Completer<bool>();
    // Keep fast taps responsive while committing each local snapshot in order.
    _gearSaveQueue = _gearSaveQueue.then((_) async {
      try {
        await widget.onPlanChanged!(updated);
        _confirmedGearItems = {...updated.completedChecklistItems};
        result.complete(true);
      } catch (_) {
        if (mounted && revision == _gearEditRevision) {
          setState(() {
            _plan = _plan!
                .copyWith(completedChecklistItems: _confirmedGearItems)
                .withGearProgress();
            _error = 'Could not save your checklist. Please try again.';
          });
        }
        result.complete(false);
      } finally {
        if (mounted) {
          setState(() => _pendingGearSaves--);
          _completeRequestedStart();
        }
      }
    });
    return result.future;
  }

  /// Toggles packed.
  void _togglePacked(String item) {
    final items = {..._plan!.completedChecklistItems};
    items.contains(item) ? items.remove(item) : items.add(item);
    unawaited(_saveGear(items));
  }

  /// Cancels.
  Future<void> _cancel() async {
    if (_interactionBusy || _savingGear || widget.onCancel == null) {
      return;
    }
    final confirmed = await _presentCancelEffect1();
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCancel!();
      if (mounted) {
        Navigator.pop(context, 'cancelled');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Delegates time to the ViewModel.
  String _time(DateTime date) => _screenModel.commandTime(date);

  /// Returns selected shirt color.
  HikeShirtColor? get _selectedShirtColor => _plan == null
      ? null
      : HikeShirtColor.fromPreferences(_plan!.completedChecklistItems);

  /// Returns shirt weather briefing.
  HikeWeatherBriefing get _shirtWeatherBriefing =>
      HikeWeatherBriefing.fromWeather(
        _plan!.trail.weather,
        _plan!.plannedStartTime,
        _plan!.expectedReturnTime,
      );

  /// Returns shirt choice overlaps daylight.
  bool get _shirtChoiceOverlapsDaylight =>
      HikeShirtColorAdvice.overlapsDaylight(
        departure: _plan!.plannedStartTime,
        returning: _plan!.expectedReturnTime,
        briefing: _shirtWeatherBriefing,
      );

  /// Selects shirt color.
  Future<void> _selectShirtColor(HikeShirtColor color) async {
    final plan = _plan;
    if (plan == null || _busy) {
      return;
    }
    final updated = HikeShirtColor.setPreference(
      plan.completedChecklistItems,
      color,
    );
    await _saveGear(updated);
  }

  /// Shows shirt color advice.
  Future<void> _showShirtColorAdvice(HikeShirtColor color) async {
    final advice = HikeShirtColorAdvice.forSelection(
      color: color,
      overlapsDaylight: _shirtChoiceOverlapsDaylight,
    );
    await _presentShowShirtColorAdviceEffect1(color, advice);
  }

  /// Finishes preparation.
  void _finishPreparation() {
    if (_interactionBusy ||
        _completionDelivered ||
        !widget.canStart ||
        _plan == null) {
      return;
    }
    // A lifecycle refresh can begin between pointer-down and pointer-up, before
    // the enabled button has rebuilt. Keep that tap rather than discarding it.
    setState(() {
      _startRequested = true;
      _error = null;
    });
    _completeRequestedStart();
  }

  /// Computes complete requested start.
  void _completeRequestedStart() {
    if (!mounted ||
        !_startRequested ||
        _startInFlight ||
        _completionDelivered ||
        _busy ||
        _openingDetails ||
        _savingGear ||
        _checkingConditions) {
      return;
    }
    final plan = _plan;
    if (plan == null ||
        !widget.canStart ||
        _selectedShirtColor == null ||
        !plan.requiredGearReady) {
      setState(() {
        _startRequested = false;
        _error = (plan?.requiredGearReady == false
            ? 'The latest checks require more gear. Review the missing items before starting.'
            : _selectedShirtColor == null
            ? 'Choose your shirt colour before starting.'
            : 'This hike cannot start yet. Review your preparation.');
      });
      return;
    }
    final route = ModalRoute.of<String>(context);
    if (route == null || !route.isActive) {
      return;
    }
    // Keep this page and its answers until the caller confirms a started hike.
    // Condition refreshes and repeated taps must not create another attempt.
    setState(() => _startInFlight = true);
    unawaited(_startHike(plan, route));
  }

  /// Delegates start hike to the ViewModel.
  Future<void> _startHike(PlannedHike plan, Route<String> route) =>
      _screenModel.commandStartHike(plan, route);

  /// Returns route status.
  String get _routeStatus {
    if (_plan?.trail.isUnlisted == true) {
      return 'Unlisted route. Terrain ahead is unknown; the forecast covers the starting location only.';
    }
    final assessment = _plan?.gearAssessment;
    if (_analyzing) {
      return 'Checking your route…';
    }
    if (_routeFailed || assessment?.usable != true) {
      return 'Route conditions are unavailable. Check the terrain locally; known gear requirements still apply.';
    }
    if (!assessment!.isFresh) {
      return 'Using saved route findings. Check current conditions.';
    }
    return 'Route checked. Map data © OpenStreetMap contributors.';
  }

  /// Returns weather status.
  String get _weatherStatus {
    if (_checkingWeather) {
      return 'Checking the forecast…';
    }
    if (_weatherNotice != null) {
      return _weatherNotice!;
    }
    final plan = _plan!;
    final forecast = HikeWeatherBriefing.fromWeather(
      plan.trail.weather,
      plan.plannedStartTime,
      plan.expectedReturnTime,
    );
    if (plan.trail.weather.isStale ||
        !forecast.covered ||
        forecast.minTemperature == null ||
        forecast.peakRainChance == null) {
      return 'A complete, fresh forecast is unavailable. Check the weather before departure.';
    }
    return 'Forecast checked for your planned hike time.';
  }

  /// Returns start label.
  String get _startLabel => _screenModel.commandStartLabel;

  /// Returns departure hint.
  String get _departureHint {
    if (!widget.canStart) {
      if (!widget.immediate && widget.hike.isLocalPendingSync) {
        return 'Reconnect and let this hike finish syncing, then reopen this review.';
      }
      if (!widget.isHost) {
        return 'Your preparation is saved. The organizer starts the session.';
      }
      return 'The trail is unavailable. Return to your hike and reload it before starting.';
    }
    if (widget.primaryActionLabel != null || widget.hike.participantCount > 1) {
      return 'Next, everyone confirms their readiness before the team session starts.';
    }
    return 'Start when you are at the trailhead and ready to go.';
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;
    return PopScope(
      canPop: _completionDelivered || (!_interactionBusy && !_savingGear),
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    PageHeaderAction(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Leave preparation',
                      onPressed: _interactionBusy || _savingGear
                          ? null
                          : () => Navigator.pop(context),
                      color: scheme.onSurface,
                      surface: scheme.surface,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Get ready to hike',
                        style: PageHeaderStyle.title(context, scheme.onSurface),
                      ),
                    ),
                    if (widget.isHost && widget.onCancel != null)
                      PageHeaderControl(
                        child: PopupMenuButton<String>(
                          enabled: !_interactionBusy && !_savingGear,
                          tooltip: 'Hike options',
                          onSelected: (_) => _cancel(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'cancel',
                              child: Text('Cancel upcoming hike'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('preparation-overview'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    if (plan == null)
                      const Text(
                        'The trail preparation could not be loaded. Return and try again.',
                      )
                    else ...[
                      _hikeSummary(plan),
                      const SizedBox(height: 18),
                      _gearChoices(plan, required: true),
                      const SizedBox(height: 18),
                      _gearChoices(plan, required: false),
                      const SizedBox(height: 18),
                      _section('Phone battery', _batteryOverview(plan)),
                      const SizedBox(height: 12),
                      _section(
                        'Shirt colour',
                        _ShirtColorSelector(
                          selected: _selectedShirtColor,
                          overlapsDaylight: _shirtChoiceOverlapsDaylight,
                          enabled:
                              widget.onPlanChanged != null && !_interactionBusy,
                          onSelected: _selectShirtColor,
                          onShowAdvice: _showShirtColorAdvice,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _conditionsOverview(plan),
                    ],
                  ],
                ),
              ),
              if (plan != null) _actions(),
            ],
          ),
        ),
      ),
    );
  }

  /// Computes hike summary.
  Widget _hikeSummary(PlannedHike plan) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final required = plan.gearPlan.requiredItems.length;
    final packed = required - plan.missingRequiredGear.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hike.trailName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_time(widget.hike.departureTime)} → ${_time(widget.hike.expectedReturnTime)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                plan.requiredGearReady
                    ? Icons.check_circle_outline_rounded
                    : Icons.backpack_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$packed/$required required items packed',
                  style: theme.textTheme.labelMedium,
                ),
              ),
              if (_savingGear)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: required == 0 ? 1 : packed / required,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            semanticsLabel: '$packed of $required required items packed',
          ),
        ],
      ),
    );
  }

  /// Computes gear choices.
  Widget _gearChoices(PlannedHike plan, {required bool required}) {
    final theme = Theme.of(context), gear = plan.gearPlan;
    final items = required
        ? gear.requiredItems
        : gear.items.difference(gear.requiredItems);
    final packed = items.where(plan.completedChecklistItems.contains).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                required ? 'Required gear' : 'Recommended extras',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text('$packed/${items.length}', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          required
              ? 'Tap each item as you pack it.'
              : 'Optional — pack what suits your hike.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        PreparationGearGrid(
          key: ValueKey(required ? 'required-gear-grid' : 'optional-gear-grid'),
          items: items,
          selectedItems: plan.completedChecklistItems,
          reasons: gear.requiredReasons,
          onToggle: _interactionBusy || widget.onPlanChanged == null
              ? null
              : _togglePacked,
        ),
      ],
    );
  }

  /// Computes section.
  Widget _section(String title, Widget child) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Computes battery overview.
  Widget _batteryOverview(PlannedHike plan) {
    final battery = _readinessTile(
      icon: plan.hasKnownBatteryLevel
          ? Icons.battery_charging_full_rounded
          : Icons.battery_unknown_rounded,
      label: 'Phone battery',
      value: _loadingBattery
          ? 'Checking…'
          : plan.hasKnownBatteryLevel
          ? '${plan.phoneBatteryLevel}%'
          : 'Check phone',
      detail: !plan.hasKnownBatteryLevel
          ? 'Check the charge manually'
          : plan.phoneBatteryLevel < 60
          ? '60% or more recommended'
          : 'Ready for the trail',
      warning: !plan.hasKnownBatteryLevel || plan.phoneBatteryLevel < 60,
      onTap:
          _interactionBusy || _loadingBattery || widget.loadBatteryLevel == null
          ? null
          : _refreshBattery,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        battery,
        if (plan.expectedReturnTime.difference(plan.plannedStartTime) >
            const Duration(hours: 3)) ...[
          const SizedBox(height: 10),
          Text(
            'Over 3 hours planned — bring a charged power bank.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  /// Computes readiness tile.
  Widget _readinessTile({
    required IconData icon,
    required String label,
    required String value,
    required String detail,
    required bool warning,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final accent = warning ? scheme.error : scheme.primary;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: accent),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 3),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Computes conditions overview.
  Widget _conditionsOverview(PlannedHike plan) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final forecast = _shirtWeatherBriefing;
    final summary =
        forecast.minTemperature != null &&
            forecast.maxTemperature != null &&
            forecast.peakRainChance != null
        ? '${forecast.minTemperature!.round()}–${forecast.maxTemperature!.round()}°C · ${forecast.peakRainChance!.round()}% rain chance'
        : 'Check local weather before departure';
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('preparation-conditions'),
            tilePadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_outlined, color: scheme.primary),
            title: Text(
              'Weather & route',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              _analyzing || _checkingWeather ? 'Checking conditions…' : summary,
              style: theme.textTheme.bodySmall,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_routeStatus, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(_weatherStatus, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 14),
                    PreparationConditions(
                      weather: plan.trail.weather,
                      departure: plan.plannedStartTime,
                      returning: plan.expectedReturnTime,
                      assessment: plan.gearAssessment,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed:
                              _interactionBusy || _analyzing || _checkingWeather
                              ? null
                              : () {
                                  unawaited(_analyzeRoute(force: true));
                                  unawaited(_refreshWeather());
                                },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Refresh'),
                        ),
                        TextButton.icon(
                          onPressed: _interactionBusy || _checkingWeather
                              ? null
                              : _openForecast,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Full forecast'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Computes actions.
  Widget _actions() {
    final theme = Theme.of(context), scheme = theme.colorScheme, plan = _plan!;
    final missing = plan.missingRequiredGear.length;
    final ready = missing == 0 && _selectedShirtColor != null;
    final waiting = _checkingConditions || _savingGear;
    final label = missing > 0
        ? '$missing required item${missing == 1 ? '' : 's'} left'
        : _selectedShirtColor == null
        ? 'Choose a shirt colour'
        : _startLabel;
    final hint = missing > 0
        ? 'Pack the required items above.'
        : _selectedShirtColor == null
        ? 'Select your shirt colour on this page.'
        : waiting
        ? 'Finishing your saved checks…'
        : _departureHint;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            ),
          Text(hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('preparation-continue'),
            onPressed: _interactionBusy || waiting || !ready || !widget.canStart
                ? null
                : _finishPreparation,
            icon: _busy || _startRequested || (ready && waiting)
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.hiking_rounded),
            label: Text(
              _busy || _savingGear
                  ? 'Saving…'
                  : _startRequested
                  ? 'Starting…'
                  : ready && waiting
                  ? 'Checking conditions…'
                  : label,
            ),
          ),
        ],
      ),
    );
  }

  /// Presents the cancel effect1 UI.
  Future<bool?> _presentCancelEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel this hike?'),
      content: Text(
        'Remove ${widget.hike.trailName} from upcoming hikes for everyone joining. Your past hikes will stay unchanged.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep hike'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Cancel hike'),
        ),
      ],
    ),
  );

  /// Presents the show shirt color advice effect1 UI.
  Future<void> _presentShowShirtColorAdviceEffect1(
    HikeShirtColor color,
    HikeShirtColorAdvice advice,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ShirtColorAdviceSheet(color: color, advice: advice),
  );

  /// Presents the start hike effect1 UI.
  void _presentStartHikeEffect1(Route<String> route) =>
      HikeStartNavigation.closeOwnedRoute(route, 'start');
}

/// Displays the shirt color selector.
class _ShirtColorSelector extends StatelessWidget {
  /// Creates shirt color selector.
  const _ShirtColorSelector({
    required this.selected,
    required this.overlapsDaylight,
    required this.enabled,
    required this.onSelected,
    required this.onShowAdvice,
  });

  final HikeShirtColor? selected;
  final bool overlapsDaylight;
  final bool enabled;
  final Future<void> Function(HikeShirtColor) onSelected;
  final Future<void> Function(HikeShirtColor) onShowAdvice;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in HikeShirtColor.values)
              _ShirtColorChoice(
                color: color,
                selected: selected == color,
                enabled: enabled,
                onTap: () => unawaited(onSelected(color)),
              ),
          ],
        ),
        if (selected == null) ...[
          const SizedBox(height: 12),
          Text(
            'Choose the closest colour. Long-press for its name.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          _SelectedShirtColorStatus(
            color: selected!,
            advice: HikeShirtColorAdvice.forSelection(
              color: selected!,
              overlapsDaylight: overlapsDaylight,
            ),
            onTap: () => unawaited(onShowAdvice(selected!)),
          ),
        ],
      ],
    );
  }
}

/// Displays the shirt color choice.
class _ShirtColorChoice extends StatelessWidget {
  /// Creates shirt color choice.
  const _ShirtColorChoice({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final HikeShirtColor color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatch = Color(color.colorValue);
    final foreground = swatch.computeLuminance() > .5
        ? const Color(0xFF152019)
        : Colors.white;
    return Tooltip(
      message: color.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${color.label} shirt',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('shirt-color-${color.name}'),
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: .45),
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 21, color: foreground)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the selected shirt color status.
class _SelectedShirtColorStatus extends StatelessWidget {
  /// Creates selected shirt color status.
  const _SelectedShirtColorStatus({
    required this.color,
    required this.advice,
    required this.onTap,
  });

  final HikeShirtColor color;
  final HikeShirtColorAdvice advice;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final accent = switch (advice.tone) {
      HikeShirtColorSuitability.recommended => scheme.primary,
      HikeShirtColorSuitability.visible => scheme.tertiary,
      HikeShirtColorSuitability.avoidInDaylight => scheme.error,
    };
    return Material(
      color: accent.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('shirt-color-guidance'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: .45)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(color.colorValue),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      color.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      advice.title,
                      style: theme.textTheme.bodySmall?.copyWith(color: accent),
                    ),
                  ],
                ),
              ),
              Icon(Icons.info_outline_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the shirt color advice sheet.
class _ShirtColorAdviceSheet extends StatelessWidget {
  /// Creates shirt color advice sheet.
  const _ShirtColorAdviceSheet({required this.color, required this.advice});

  final HikeShirtColor color;
  final HikeShirtColorAdvice advice;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(color.colorValue),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${color.label} shirt',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Hike clothing guidance',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ShirtColorAdviceCard(advice: advice),
            const SizedBox(height: 12),
            Text(
              'Colour is only one layer of protection. Wear suitable coverage and use an effective insect repellent where needed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('close-shirt-color-guidance'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}
