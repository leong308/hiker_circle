import 'dart:async';
import '../../sos/Model/sos_models.dart';
import '../Data/hike_briefing_weather_service.dart';
import '../Model/hike_preparation_sharing.dart';
import 'hiking_forecast_sheet.dart';
import 'preparation_conditions.dart';
import 'preparation_safety_details_page.dart';
import '../Model/route_gear_assessment.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/hike_weather_briefing.dart';
import '../../core/widgets/page_header_style.dart';
import 'package:flutter/material.dart';
import '../Model/hike_session_models.dart';

/// Full-page final pack and safety review before a session can start.
class FinalPreparationReviewPage extends StatefulWidget {
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
    this.onReady,
    this.immediate = false,
    this.primaryActionLabel,
    this.initialContacts = const [],
    this.loadContacts,
    this.onEditContacts,
    this.loadBatteryLevel,
    this.loadSharing,
    this.saveSharing,
  });
  final UpcomingHike hike;
  final bool immediate;
  final String? primaryActionLabel;
  final ValueChanged<PlannedHike>? onReady;
  final Future<TrailWeather> Function()? loadWeather;
  final bool isHost, canStart;
  final PlannedHike? plan;
  final Future<void> Function(PlannedHike)? onPlanChanged;
  final Future<void> Function()? onCancel;
  final Future<RouteGearAssessment> Function(bool force)? loadRouteAnalysis;
  final List<EmergencyContact> initialContacts;
  final Future<List<EmergencyContact>> Function()? loadContacts;
  final Future<void> Function()? onEditContacts;
  final Future<int?> Function()? loadBatteryLevel;
  final Future<HikePreparationSharing?> Function()? loadSharing;
  final Future<void> Function(HikePreparationSharing)? saveSharing;
  @override
  State<FinalPreparationReviewPage> createState() => _PreparationState();
}

class _PreparationState extends State<FinalPreparationReviewPage>
    with WidgetsBindingObserver {
  late PlannedHike? _plan = widget.plan;
  bool _busy = false;
  String? _error;
  bool _analyzing = false;
  bool _checkingWeather = false;
  String? _weatherNotice;
  bool _routeFailed = false;
  bool _includeExtras = false;
  bool _returnToReview = false;
  bool _reviewPacked = false;
  late String _stepId;
  final List<String> _history = [];
  final ScrollController _scroll = ScrollController();
  late List<EmergencyContact> _contacts = List.of(widget.initialContacts);
  bool _openingDetails = false,
      _loadingContacts = false,
      _loadingBattery = false,
      _loadingSharing = false;
  String? _contactsError, _sharingError;
  Timer? _batteryTimer;
  bool get _interactionBusy => _busy || _openingDetails;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final missing = _plan?.missingRequiredGear;
    _stepId = missing?.isNotEmpty == true ? 'gear:${missing!.first}' : 'extras';
    _analyzeRoute();
    _refreshWeather();
    _refreshContacts();
    _refreshBattery();
    _restoreSharing();
    _batteryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_plan != null && _currentStep.id == 'battery') {
        unawaited(_refreshBattery());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBattery());
      if (_plan != null &&
          DateTime.now().difference(_plan!.trail.weather.cachedAt) >
              const Duration(minutes: 15)) {
        unawaited(_refreshWeather());
      }
    }
  }

  Future<void> _refreshContacts() async {
    if (widget.loadContacts == null || _loadingContacts) return;
    setState(() {
      _loadingContacts = true;
      _contactsError = null;
    });
    try {
      final contacts = await widget.loadContacts!().timeout(
        const Duration(seconds: 12),
      );
      if (mounted) {
        setState(() {
          _contacts = List.of(contacts);
          _plan = _plan?.copyWith(
            emergencyContactsSelected: contacts.isNotEmpty,
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _contactsError =
              'Could not refresh contacts. The saved list is shown below.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Future<void> _refreshBattery() async {
    if (widget.loadBatteryLevel == null || _loadingBattery) return;
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

  Future<void> _restoreSharing() async {
    if (widget.loadSharing == null || _loadingSharing) return;
    setState(() {
      _loadingSharing = true;
      _sharingError = null;
    });
    try {
      final choice = await widget.loadSharing!().timeout(
        const Duration(seconds: 5),
      );
      if (mounted && choice != null) {
        setState(
          () => _plan = _plan?.copyWith(
            liveLocationConfigured: choice.enabled,
            locationRecordingInterval: choice.interval,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sharingError =
              'Could not load your saved sharing choices. Retry or modify them before starting.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSharing = false);
    }
  }

  Future<void> _openDetails(
    Future<void> Function() open, {
    Future<void> Function()? refresh,
  }) async {
    if (_interactionBusy) return;
    setState(() {
      _openingDetails = true;
      _error = null;
    });
    try {
      await open();
      if (mounted) await refresh?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open these details. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingDetails = false);
    }
  }

  Future<void> _editSharing() => _openDetails(() async {
    final choice = await Navigator.of(context).push<HikePreparationSharing>(
      MaterialPageRoute(
        builder: (_) => PreparationSharingPage(
          initial: HikePreparationSharing.fromPlan(_plan!),
          onSave: widget.saveSharing,
        ),
      ),
    );
    if (mounted && choice != null) {
      setState(() {
        _sharingError = null;
        _plan = _plan!.copyWith(
          liveLocationConfigured: choice.enabled,
          locationRecordingInterval: choice.interval,
        );
      });
    }
  });

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

  Future<void> _refreshWeather() async {
    if (_plan == null || widget.loadWeather == null || _checkingWeather) return;
    setState(() => _checkingWeather = true);
    try {
      final weather = await widget.loadWeather!();
      if (!mounted) return;
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
      if (mounted) setState(() => _checkingWeather = false);
    }
  }

  Future<void> _analyzeRoute({bool force = false}) async {
    if (_analyzing || widget.loadRouteAnalysis == null || _plan == null) return;
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
      if (mounted) setState(() => _routeFailed = true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<bool> _saveGear(Set<String> items) async {
    final plan = _plan;
    if (plan == null || widget.onPlanChanged == null || _busy) return false;
    final updated = plan
        .copyWith(
          completedChecklistItems: items,
          checklistCompleted: items.length,
          checklistTotal: GearChecklistCatalog.itemCount,
        )
        .withGearProgress();
    setState(() {
      _busy = true;
      _error = null;
      _plan = updated;
    });
    try {
      await widget.onPlanChanged!(updated);
      if (mounted) {
        setState(
          () => _plan = _plan!
              .copyWith(
                completedChecklistItems: updated.completedChecklistItems,
              )
              .withGearProgress(),
        );
      }
      return mounted;
    } catch (_) {
      if (mounted) {
        setState(() {
          _plan = _plan!
              .copyWith(completedChecklistItems: plan.completedChecklistItems)
              .withGearProgress();
          _error = 'Could not save your checklist. Please try again.';
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy || widget.onCancel == null) return;
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCancel!();
      if (mounted) Navigator.pop(context, 'cancelled');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(DateTime date) {
    final d = date.toLocal();
    return '${d.day}/${d.month} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  List<_PreparationStep> get _steps {
    final plan = _plan;
    if (plan == null) return const [];
    final gear = plan.gearPlan;
    _PreparationStep itemStep(String item, bool required) => _PreparationStep(
      id: 'gear:$item',
      stage: required ? 0 : 1,
      eyebrow: required ? 'REQUIRED FOR THIS HIKE' : 'OPTIONAL EXTRA',
      title: item,
      body: required
          ? gear.requiredReasons[item]!
          : gear.reasons[gear.sections.keys.firstWhere(
              (section) => gear.sections[section]!.contains(item),
            )]!,
      icon: _itemIcon(item),
      item: item,
    );
    return [
      for (final item in gear.requiredItems) itemStep(item, true),
      _PreparationStep(
        id: 'extras',
        stage: 1,
        eyebrow: 'MAKE THE PACK YOURS',
        title: 'A few useful extras?',
        body: plan.requiredGearReady
            ? 'Your required items are packed. We can walk through a few recommendations for this route, or continue to safety.'
            : 'We have saved your answers. You can review optional gear now; we will come back to anything required that is still missing.',
        icon: Icons.backpack_outlined,
      ),
      if (_includeExtras)
        for (final item in gear.items.difference(gear.requiredItems))
          itemStep(item, false),
      _PreparationStep(
        id: 'contacts',
        stage: 2,
        eyebrow: 'SAFETY CHECK · 1 OF 4',
        title: 'Who can help if you need it?',
        body: _contacts.isNotEmpty
            ? 'Your emergency contacts are available. Make sure someone knows your route and expected return time.'
            : 'No emergency contacts are available. Add or review them in SOS before departure, and let someone know your plans.',
        icon: Icons.contact_phone_outlined,
      ),
      _PreparationStep(
        id: 'battery',
        stage: 2,
        eyebrow: 'SAFETY CHECK · 2 OF 4',
        title: 'Is your phone ready for the trail?',
        body:
            'Check your charge before leaving, and consider a power bank for longer hikes.',
        icon: Icons.battery_charging_full_rounded,
      ),
      _PreparationStep(
        id: 'sharing',
        stage: 2,
        eyebrow: 'SAFETY CHECK · 3 OF 4',
        title: 'How will you share your location?',
        body: plan.liveLocationConfigured
            ? 'Live location sharing is on for this hike.'
            : 'Live location sharing is off for this hike.',
        icon: Icons.my_location_rounded,
      ),
      _PreparationStep(
        id: 'conditions',
        stage: 2,
        eyebrow: 'SAFETY CHECK · 4 OF 4',
        title: 'Have you checked the conditions?',
        body:
            'Your pack adapts to the route and forecast. Check conditions at the trail too, and adjust your plans if needed.',
        icon: Icons.cloud_outlined,
      ),
      _PreparationStep(
        id: 'ready',
        stage: 3,
        eyebrow: 'FINAL REVIEW',
        title: plan.requiredGearReady
            ? 'Your pack is ready'
            : 'Let’s finish your pack',
        body: plan.requiredGearReady
            ? 'Your required gear is saved. Take a moment to check your hike details before you go.'
            : 'These items are still required before you can start. We will guide you through them next.',
        icon: plan.requiredGearReady
            ? Icons.check_circle_outline_rounded
            : Icons.backpack_outlined,
      ),
    ];
  }

  _PreparationStep get _currentStep {
    final steps = _steps;
    return steps.firstWhere(
      (step) => step.id == _stepId,
      // A refreshed forecast can remove the requirement being displayed.
      orElse: () => steps.firstWhere(
        (step) =>
            step.item != null && _plan!.missingRequiredGear.contains(step.item),
        orElse: () => steps.firstWhere((step) => step.id == 'extras'),
      ),
    );
  }

  void _showStep(String id, {bool remember = true}) {
    if (_interactionBusy) return;
    final previous = _currentStep.id;
    setState(() {
      if (remember && previous != id) _history.add(previous);
      _stepId = id;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (id == 'battery') unawaited(_refreshBattery());
  }

  void _previousStep() {
    if (_busy) return;
    final ids = _steps.map((step) => step.id).toSet();
    while (_history.isNotEmpty) {
      final previous = _history.removeLast();
      if (ids.contains(previous)) {
        _returnToReview = false;
        _reviewPacked = false;
        _showStep(previous, remember: false);
        return;
      }
    }
  }

  void _advance() {
    final steps = _steps;
    final index = steps.indexWhere((step) => step.id == _currentStep.id);
    for (final step in steps.skip(index + 1)) {
      if (_returnToReview && step.stage != 0) break;
      if (!_reviewPacked &&
          step.item != null &&
          _plan!.completedChecklistItems.contains(step.item)) {
        continue;
      }
      _showStep(step.id);
      return;
    }
    _showStep('ready');
  }

  Future<void> _answerGear(bool packed) async {
    final step = _currentStep;
    final plan = _plan;
    if (_busy || plan == null || step.item == null) return;
    final items = {...plan.completedChecklistItems};
    final changed = packed ? items.add(step.item!) : items.remove(step.item);
    if (changed && !await _saveGear(items)) return;
    if (!mounted) return;
    if (_returnToReview && !_reviewPacked) {
      final missing = _plan!.missingRequiredGear;
      _showStep(
        packed && missing.isNotEmpty ? 'gear:${missing.first}' : 'ready',
      );
    } else {
      _advance();
    }
  }

  void _reviewMissing() {
    _returnToReview = true;
    _reviewPacked = false;
    _showStep('gear:${_plan!.missingRequiredGear.first}');
  }

  void _finishPreparation() {
    final plan = _plan;
    if (_interactionBusy ||
        _loadingSharing ||
        _sharingError != null ||
        _loadingContacts ||
        _analyzing ||
        _checkingWeather ||
        !widget.canStart ||
        plan == null ||
        !plan.requiredGearReady) {
      return;
    }
    setState(() => _busy = true);
    widget.onReady?.call(plan);
    Navigator.pop(context, 'start');
  }

  String get _routeStatus {
    final assessment = _plan?.gearAssessment;
    if (_analyzing) return 'Checking your route…';
    if (_routeFailed || assessment?.usable != true) {
      return 'Route conditions are unavailable. Check the terrain locally; known gear requirements still apply.';
    }
    if (!assessment!.isFresh) {
      return 'Using saved route findings. Check current conditions.';
    }
    return 'Route checked. Map data © OpenStreetMap contributors.';
  }

  String get _weatherStatus {
    if (_checkingWeather) return 'Checking the forecast…';
    if (_weatherNotice != null) return _weatherNotice!;
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

  String get _startLabel =>
      widget.primaryActionLabel ??
      (!widget.immediate && widget.hike.isLocalPendingSync
          ? 'Waiting for sync'
          : !widget.isHost
          ? 'Waiting for organizer'
          : widget.hike.participantCount > 1
          ? 'Start team readiness'
          : 'Start hike');

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final plan = _plan;
    final step = plan == null ? null : _currentStep;
    return PopScope(
      canPop: !_interactionBusy,
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
                      onPressed: _interactionBusy
                          ? null
                          : () => Navigator.pop(context),
                      color: scheme.onSurface,
                      surface: scheme.surface,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Get ready to hike',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.isHost && widget.onCancel != null)
                      PopupMenuButton<String>(
                        enabled: !_interactionBusy,
                        tooltip: 'Hike options',
                        onSelected: (_) => _cancel(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'cancel',
                            child: Text('Cancel upcoming hike'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (step != null) _progress(step),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    if (step == null)
                      const Text(
                        'The trail preparation could not be loaded. Please return and try again.',
                      )
                    else
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: _question(step),
                      ),
                  ],
                ),
              ),
              if (step != null) _actions(step),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress(_PreparationStep step) {
    final theme = Theme.of(context);
    const phases = [
      'Pack essentials',
      'Optional extras',
      'Safety check',
      'Ready to go',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hike.trailName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Step ${step.stage + 1} of 4 · ${phases[step.stage]}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Previous question',
                onPressed: _interactionBusy || _history.isEmpty
                    ? null
                    : _previousStep,
                icon: const Icon(Icons.undo_rounded),
              ),
            ],
          ),
          LinearProgressIndicator(
            value: (step.stage + 1) / 4,
            semanticsLabel: 'Preparation step ${step.stage + 1} of 4',
            borderRadius: BorderRadius.circular(4),
            minHeight: 5,
          ),
        ],
      ),
    );
  }

  Widget _question(_PreparationStep step) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final compact =
        MediaQuery.sizeOf(context).height < 740 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    final plan = _plan!;
    final packed =
        step.item != null && plan.completedChecklistItems.contains(step.item);
    final missing = plan.missingRequiredGear;
    return Container(
      key: ValueKey(step.id),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Row(
              children: [
                Icon(
                  packed ? Icons.check_circle_outline_rounded : step.icon,
                  size: 28,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                packed ? Icons.check_rounded : step.icon,
                size: 32,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              step.eyebrow,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (step.item != null && (!compact || packed)) ...[
            Text(
              packed ? 'Already in your pack' : 'Have you packed this?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
          ],
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              step.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(step.body, style: theme.textTheme.bodyLarge),
          if (step.stage == 2) ...[
            const SizedBox(height: 18),
            _safetyDetails(step.id),
          ],
          if (step.item != null) ...[
            const SizedBox(height: 20),
            Text(
              step.stage == 0
                  ? '${plan.gearPlan.requiredItems.length - missing.length} of ${plan.gearPlan.requiredItems.length} required items packed'
                  : 'Optional · skipping this will not prevent you from starting.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (step.id == 'conditions' || step.id == 'ready') ...[
            const SizedBox(height: 20),
            _status(Icons.cloud_outlined, _weatherStatus),
            _status(Icons.route_rounded, _routeStatus),
            if (step.id == 'conditions' &&
                (widget.loadWeather != null ||
                    widget.loadRouteAnalysis != null))
              TextButton.icon(
                onPressed: _interactionBusy || _analyzing || _checkingWeather
                    ? null
                    : () {
                        _analyzeRoute(force: true);
                        _refreshWeather();
                      },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh conditions'),
              ),
          ],
          if (step.id == 'ready') ...[
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final item in missing)
                _status(Icons.backpack_outlined, item),
            ],
            const Divider(height: 28),
            _schedule('Departure', _time(widget.hike.departureTime)),
            const SizedBox(height: 12),
            _schedule(
              'Estimated finish',
              _time(widget.hike.expectedReturnTime),
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.hike.distanceKm.toStringAsFixed(1)} km · ${plan.trail.difficultyDisplayLabel}',
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _returnToReview = true;
                      _reviewPacked = true;
                      _showStep('gear:${plan.gearPlan.requiredItems.first}');
                    },
              child: const Text('Recheck required gear'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _safetyDetails(String id) {
    final plan = _plan!, theme = Theme.of(context);
    switch (id) {
      case 'contacts':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadingContacts) const LinearProgressIndicator(),
            if (_contactsError != null)
              Text(
                _contactsError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            for (final contact in _contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.person_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contact.name, style: theme.textTheme.titleSmall),
                          if (contact.relationship.trim().isNotEmpty)
                            Text(contact.relationship),
                          Text(contact.phoneNumber),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_contacts.isEmpty && !_loadingContacts)
              const Text('No emergency contacts saved.'),
            if (widget.onEditContacts != null)
              OutlinedButton.icon(
                onPressed: _interactionBusy || _loadingContacts
                    ? null
                    : () => _openDetails(
                        widget.onEditContacts!,
                        refresh: _refreshContacts,
                      ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modify contacts'),
              ),
            if (_contactsError != null)
              TextButton(
                onPressed: _loadingContacts ? null : _refreshContacts,
                child: const Text('Retry contacts'),
              ),
          ],
        );
      case 'battery':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              plan.hasKnownBatteryLevel
                  ? 'Phone battery · ${plan.phoneBatteryLevel}%'
                  : 'Phone battery unavailable',
              style: theme.textTheme.titleLarge,
            ),
            if (_loadingBattery) const LinearProgressIndicator(),
            if (widget.loadBatteryLevel != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _interactionBusy
                    ? null
                    : () => _openDetails(
                        () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => PreparationBatteryPage(
                              loadBattery: widget.loadBatteryLevel!,
                              initialLevel: plan.hasKnownBatteryLevel
                                  ? plan.phoneBatteryLevel
                                  : null,
                            ),
                          ),
                        ),
                        refresh: _refreshBattery,
                      ),
                icon: const Icon(Icons.battery_std),
                label: const Text('Battery details'),
              ),
            ],
          ],
        );
      case 'sharing':
        final choice = HikePreparationSharing.fromPlan(plan);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadingSharing) const LinearProgressIndicator(),
            Text(
              'Cloud upload · ${choice.intervalLabel}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'GPS is recorded on this phone every 5 seconds. All new points are sent together at your chosen upload interval.',
            ),
            if (_sharingError != null) ...[
              Text(
                _sharingError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              TextButton(
                onPressed: _loadingSharing ? null : _restoreSharing,
                child: const Text('Retry sharing choices'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _interactionBusy || _loadingSharing
                  ? null
                  : _editSharing,
              icon: const Icon(Icons.tune),
              label: const Text('Modify sharing'),
            ),
          ],
        );
      case 'conditions':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PreparationConditions(
              weather: plan.trail.weather,
              departure: plan.plannedStartTime,
              returning: plan.expectedReturnTime,
              assessment: plan.gearAssessment,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _interactionBusy || _checkingWeather
                  ? null
                  : _openForecast,
              icon: const Icon(Icons.open_in_new),
              label: const Text('View full forecast'),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _status(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );

  Widget _actions(_PreparationStep step) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final plan = _plan!;
    final checking =
        _analyzing || _checkingWeather || _loadingSharing || _loadingContacts;
    String label = 'Continue';
    String? secondary;
    String hint = 'Take a moment to review, then continue.';
    VoidCallback? action = _advance;
    VoidCallback? secondaryAction;
    if (step.item != null) {
      final packed = plan.completedChecklistItems.contains(step.item);
      label = packed ? 'Keep packed' : 'Yes, packed';
      hint = step.stage == 0
          ? 'Not ready yet? We will come back to it before you start.'
          : 'Bring it if it suits your hike.';
      action = widget.onPlanChanged == null && !packed
          ? null
          : () => _answerGear(true);
      secondary = step.stage == 0 ? 'Not yet' : 'Skip this item';
      secondaryAction = widget.onPlanChanged == null && packed
          ? null
          : () => _answerGear(false);
      if (widget.onPlanChanged == null && !packed) {
        hint =
            'Packing changes are unavailable. Return to the hike and reopen preparation.';
      }
    } else if (step.id == 'extras') {
      label = 'Review optional gear';
      secondary = 'Skip extras';
      hint = 'Optional gear will not prevent you from starting.';
      action = () {
        _includeExtras = true;
        _advance();
      };
      secondaryAction = () => _showStep('contacts');
    } else if (step.id == 'ready') {
      final missing = plan.missingRequiredGear;
      if (_sharingError != null) {
        label = 'Review sharing choices';
        hint = _sharingError!;
        action = () => _showStep('sharing');
      } else if (missing.isNotEmpty) {
        label =
            'Pack ${missing.length} missing item${missing.length == 1 ? '' : 's'}';
        hint = 'Next up: ${missing.first}';
        action = _reviewMissing;
      } else {
        label = _loadingSharing || _loadingContacts
            ? 'Loading safety details…'
            : checking
            ? 'Checking conditions…'
            : _startLabel;
        hint = checking
            ? 'Waiting for route and forecast checks before starting.'
            : _departureHint;
        action = checking || !widget.canStart ? null : _finishPreparation;
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            ),
          Text(hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('preparation-continue'),
            onPressed: _interactionBusy ? null : action,
            icon:
                _busy ||
                    (step.id == 'ready' && checking && plan.requiredGearReady)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    step.item != null
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                  ),
            label: Text(_busy ? 'Saving…' : label),
          ),
          if (secondary != null)
            TextButton(
              onPressed: _interactionBusy ? null : secondaryAction,
              child: Text(secondary),
            ),
        ],
      ),
    );
  }

  Widget _schedule(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );

  IconData _itemIcon(String item) {
    final name = item.toLowerCase();
    if (name.contains('water')) return Icons.water_drop_outlined;
    if (name.contains('snack') || name.contains('food')) {
      return Icons.restaurant_outlined;
    }
    if (name.contains('aid')) return Icons.medical_services_outlined;
    if (name.contains('sun')) return Icons.wb_sunny_outlined;
    if (name.contains('rain')) return Icons.umbrella_outlined;
    if (name.contains('blanket')) return Icons.layers_outlined;
    if (name.contains('poles') || name.contains('socks')) {
      return Icons.hiking_rounded;
    }
    return Icons.backpack_outlined;
  }
}

class _PreparationStep {
  const _PreparationStep({
    required this.id,
    required this.stage,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    this.item,
  });
  final String id, eyebrow, title, body;
  final int stage;
  final IconData icon;
  final String? item;
}
