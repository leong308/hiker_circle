part of '../start_hike_wizard_page_feature.dart';

/// Defines the start hike wizard step choices.
enum _StartHikeWizardStep { trail, type, timing, reminder, safety }

/// Displays the start hike wizard page.
class StartHikeWizardPage extends StatefulWidget {
  /// Creates start hike wizard page.
  const StartHikeWizardPage({
    super.key,
    this.preselectedTrail,
    this.availableTrails = const [],
    this.repository,
    this.session,
    this.emergencyContactNames = const [],
    this.initialShareLiveLocation = false,
    this.startWithSchedule = false,
    this.rescheduleFrom,
    this.onScheduled,
    this.onStartNow,
    this.onLocationSelected,
    this.onEditEmergencyContacts,
  });

  final Trail? preselectedTrail;
  final List<Trail> availableTrails;
  final HikerCircleFirebaseRepository? repository;
  final AppSession? session;
  final List<String> emergencyContactNames;
  final bool initialShareLiveLocation;
  final bool startWithSchedule;
  final UpcomingHike? rescheduleFrom;
  final Future<void> Function(HikeSessionDraft draft)? onScheduled;
  final Future<bool> Function(HikeSessionDraft draft)? onStartNow;
  final Future<List<String>> Function()? onEditEmergencyContacts;
  final Future<TrailHazardAlertAction> Function(Trail trail)?
  onLocationSelected;

  /// Creates the presentation state for this widget.
  @override
  State<StartHikeWizardPage> createState() => _StartHikeWizardPageState();
}

/// Manages the start hike wizard page presentation and lifecycle.
class _StartHikeWizardPageState extends State<StartHikeWizardPage> {
  /// Returns checking hazards.
  bool get _checkingHazards => _screenModel.stateCheckingHazards;

  /// Returns initial reports checked.
  bool get _initialReportsChecked => _screenModel.stateInitialReportsChecked;

  /// Updates initial reports checked.
  set _initialReportsChecked(bool value) =>
      _screenModel.stateInitialReportsChecked = value;

  /// Returns editing contacts.
  bool get _editingContacts => _screenModel.stateEditingContacts;

  late final _StartHikeWizardPageStateViewModel _screenModel;

  /// Returns draft.
  HikeSessionDraft get _draft => _screenModel.stateDraft;

  /// Updates draft.
  set _draft(HikeSessionDraft value) => _screenModel.stateDraft = value;

  /// Returns step index.
  int get _stepIndex => _screenModel.stateStepIndex;

  /// Updates step index.
  set _stepIndex(int value) => _screenModel.stateStepIndex = value;

  /// Returns start now.
  bool get _startNow => _screenModel.stateStartNow;

  /// Updates start now.
  set _startNow(bool value) => _screenModel.stateStartNow = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final HikerBleService _bleService = const HikerBleService();
  late final List<Trail> _trails;

  bool _isScheduling = false;
  bool _isStarting = false;

  HikeReminderPreference _reminderPreference = const HikeReminderPreference();
  String _joinPolicy = 'approval';

  /// Returns is upcoming hike.
  bool get _isUpcomingHike => _screenModel.commandIsUpcomingHike;

  /// Returns steps.
  List<_StartHikeWizardStep> get _steps => _screenModel.commandSteps;

  /// Returns step count.
  int get _stepCount => _screenModel.commandStepCount;

  /// Returns visible step index.
  int get _visibleStepIndex => _screenModel.commandVisibleStepIndex;

  /// Returns is final step.
  bool get _isFinalStep => _screenModel.commandIsFinalStep;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _StartHikeWizardPageStateViewModel(
      readPreselectedTrail: () => widget.preselectedTrail,
    )..addListener(_renderScreenModel);
    _screenModel.readOnLocationSelected = () => widget.onLocationSelected;
    _screenModel.readOnEditEmergencyContacts = () =>
        widget.onEditEmergencyContacts;
    _screenModel.effectPresentCheckLocationEffect2 =
        _presentCheckLocationEffect2;
    _screenModel.effectPresentEditSafetyContactsEffect1 =
        _presentEditSafetyContactsEffect1;
    _screenModel.effectPresentCheckLocationEffect1 =
        _presentCheckLocationEffect1;

    _startNow = !widget.startWithSchedule && widget.rescheduleFrom == null;
    final trailsById = <String, Trail>{};
    for (final trail in widget.availableTrails) {
      trailsById.putIfAbsent(trail.trailId, () => trail);
    }
    final preselectedTrail = widget.preselectedTrail;
    if (preselectedTrail != null) {
      trailsById[preselectedTrail.trailId] = preselectedTrail;
    }
    _trails = trailsById.values.toList();
    if (_trails.isEmpty) {
      return;
    }
    final selectedTrail = _trails.firstWhere(
      (trail) => trail.trailId == widget.preselectedTrail?.trailId,
      orElse: () => _trails.first,
    );
    _draft = _withPlatformSafetyPolicy(
      HikeSessionDraft.fromTrail(selectedTrail).copyWith(
        emergencyContactNames: {
          for (final name in widget.emergencyContactNames)
            if (name.trim().isNotEmpty) name.trim(),
        }.toList(),
        shareLiveLocation: widget.initialShareLiveLocation,
        locationRecordingInterval:
            LocationUpdateIntervalController.instance.preferredInterval,
      ),
    );
    final previous = widget.rescheduleFrom;
    if (previous != null) {
      _joinPolicy = previous.joinPolicy == 'open' ? 'open' : 'approval';
      final departure = _minimumScheduledDepartureTime();
      final arrival = departure.add(_safePlannedHikeDuration(_draft));
      _draft = _draft.copyWith(
        hikeType:
            previous.hikeType.trim().toLowerCase() == HikeType.team.name ||
                previous.participantCount > 1
            ? HikeType.team
            : HikeType.solo,
        departureTime: departure,
        expectedArrivalTime: arrival,
        expectedReturnTime: arrival.add(const Duration(hours: 2)),
      );
      _stepIndex = _steps.indexOf(_StartHikeWizardStep.timing);
    }
    if (preselectedTrail != null &&
        !selectedTrail.isUnlisted &&
        widget.onLocationSelected != null) {
      _initialReportsChecked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkLocation());
      });
    }
  }

  /// Delegates check location to the ViewModel.
  Future<bool> _checkLocation() => _screenModel.commandCheckLocation();

  bool _checkingDistance = false;

  /// Validate the current wizard step and keep the draft within the active step sequence.
  Future<void> _next() async {
    if (_isScheduling || _isStarting || _checkingDistance || _checkingHazards) {
      return;
    }
    if (!_initialReportsChecked) {
      await _checkLocation();
      return;
    }
    final currentStep = _steps[_stepIndex];
    if (currentStep == _StartHikeWizardStep.trail && !await _checkLocation()) {
      return;
    }
    if (!mounted) return;

    if (currentStep == _StartHikeWizardStep.timing &&
        _isUpcomingHike &&
        _draft.departureTime.isBefore(_minimumScheduledDepartureTime())) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Scheduled hikes must start at least 10 minutes from now.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    if (currentStep == _StartHikeWizardStep.trail &&
        (_draft.effectiveCheckpoints.length < 3 ||
            _draft.effectiveCheckpoints.length > 12)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Add between 3 and 12 checkpoints before continuing.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    if (currentStep == _StartHikeWizardStep.type || _isFinalStep) {
      _checkingDistance = true;
      final checked = await confirmSoloHikeDistance(
        context,
        _draft,
        onChooseGroup: () => setState(() {
          _draft = _draft.copyWith(hikeType: HikeType.team);
          _stepIndex = _steps.indexOf(_StartHikeWizardStep.type);
        }),
      );
      _checkingDistance = false;
      if (!mounted || checked == null) {
        return;
      }
      _draft = checked;
    }

    if (_isFinalStep) {
      if (_isUpcomingHike) {
        unawaited(_scheduleAndFinish());
        return;
      }
      if (widget.onStartNow != null) {
        unawaited(_startNowAndFinish());
        return;
      }
      _presentNextEffect1();
      return;
    }

    setState(() {
      _stepIndex += 1;
    });
  }

  /// Starts now and finish.
  Future<void> _startNowAndFinish() async {
    if (_isStarting) {
      return;
    }
    final route = ModalRoute.of(context);
    setState(() => _isStarting = true);
    try {
      final safetyAccepted = await _confirmPreHikeSafety();
      if (!safetyAccepted || !mounted) {
        return;
      }
      final started = await widget.onStartNow!.call(_draftForNow());
      if (started) {
        _presentStartNowAndFinishEffect1(route);
      }
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  /// Gate starting on the current draft's safety checks and required user acknowledgements.
  Future<bool> _confirmPreHikeSafety() async {
    SosButtonReadiness? readiness;
    String? inspectionError;
    try {
      await _bleService.restartSosButtonMonitor();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      readiness = await _bleService.getSosButtonReadiness();
    } on HikerBleException catch (error) {
      inspectionError = error.message;
    }
    if (!mounted) {
      return false;
    }

    final value = readiness;
    final warnings = <String>[
      if (inspectionError != null) inspectionError,
      if (value != null) ...value.blockingWarnings,
      if (value != null && !value.batteryOptimizationExempt)
        'Android battery optimization may interrupt background monitoring.',
      if (value != null && !value.hasPairedButton)
        'No SOS button is paired. Phone SOS remains available.',
    ];
    final ready = warnings.isEmpty;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: Icon(
              ready
                  ? Icons.verified_user_rounded
                  : Icons.health_and_safety_rounded,
              color: ready
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            title: Text(
              ready
                  ? 'Pre-hike safety check passed'
                  : 'Review safety readiness',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => showFallDetectionTest(
                    context,
                    sensitivity: _draft.fallDetectionSettings.sensorSensitivity,
                  ),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Fall detection test'),
                ),
                _preHikeCheckLine('Bluetooth', value?.bluetoothEnabled == true),
                _preHikeCheckLine(
                  'Background SOS monitor',
                  value?.monitorHealthy == true,
                ),
                _preHikeCheckLine(
                  'Alert notifications',
                  value != null &&
                      value.notificationPermissionGranted &&
                      value.notificationsEnabled,
                ),
                _preHikeCheckLine(
                  'Paired button recently seen',
                  value != null &&
                      value.hasPairedButton &&
                      value.buttonSeenRecently(),
                ),
                if (warnings.isNotEmpty) ...[
                  const Divider(height: 24),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $warning'),
                    ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Starting the hike never disables the phone’s built-in SOS controls.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(ready ? 'Start hike' : 'Start anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Computes pre hike check line.
  Widget _preHikeCheckLine(String label, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: passed ? Colors.green : Colors.red,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  /// Persist the scheduled hike before completing this wizard route.
  Future<void> _scheduleAndFinish() async {
    final repo = widget.repository;
    final session = widget.session;
    if (repo == null || session == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Scheduling is unavailable. Please sign in again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() => _isScheduling = true);
    try {
      final safeDraft = _withPlatformSafetyPolicy(
        _withSafeRecordingInterval(_draft),
      );
      await _StartHikeWizardPageDataActions.scheduleUpcomingHike(repo)(
        session: session,
        draft: safeDraft,
        joinPolicy: _joinPolicy,
        reminderPreference: _reminderPreference,
      );
      try {
        await widget.onScheduled?.call(safeDraft);
      } catch (error) {
        debugPrint('Unable to cache the newly scheduled hike: $error');
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Hike saved for ${_formatDate(_draft.departureTime)} at ${_formatTime(_draft.departureTime)}. It will sync when connected.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      _presentScheduleAndFinishEffect1();
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to schedule this hike. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isScheduling = false);
      }
    }
  }

  /// Computes back.
  void _back() {
    if (_stepIndex <= 0) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _stepIndex -= 1;
    });
  }

  /// Delegates update draft to the ViewModel.
  void _updateDraft(HikeSessionDraft draft) =>
      _screenModel.commandUpdateDraft(draft);

  /// Delegates edit safety contacts to the ViewModel.
  Future<void> _editSafetyContacts() =>
      _screenModel.commandEditSafetyContacts();

  /// Delegates update start now to the ViewModel.
  void _updateStartNow(bool startNow) =>
      _screenModel.commandUpdateStartNow(startNow);

  /// Delegates draft for now to the ViewModel.
  HikeSessionDraft _draftForNow() => _screenModel.commandDraftForNow();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (_trails.isEmpty) {
      return Scaffold(
        backgroundColor: _WizardColors.backgroundFor(context),
        appBar: PageHeaderAppBar(title: const Text('Create Hiking Session')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_rounded, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'No trails are available to plan a hike.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final step = _initialReportsChecked
        ? _stepForIndex(_stepIndex)
        : const _StepCard(
            title: 'Check trail reports',
            subtitle:
                'Review current cautions before choosing your hike settings.',
            children: [
              Text(
                'Use Continue to retry if the report check could not be completed.',
              ),
            ],
          );

    return Scaffold(
      backgroundColor: _WizardColors.backgroundFor(context),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        onBack: _isScheduling || _isStarting || _checkingHazards
                            ? () {}
                            : _back,
                      ),
                      const SizedBox(height: 16),
                      _StepProgress(
                        currentStep: _visibleStepIndex,
                        totalSteps: _stepCount,
                      ),
                      const SizedBox(height: 18),
                      KeyedSubtree(key: ValueKey(_stepIndex), child: step),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: OutlinedButton(
                              onPressed:
                                  _isScheduling ||
                                      _isStarting ||
                                      _checkingHazards
                                  ? null
                                  : _back,
                              child: Text(_stepIndex <= 0 ? 'Cancel' : 'Back'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: FilledButton.icon(
                              onPressed:
                                  _isScheduling ||
                                      _isStarting ||
                                      _checkingHazards
                                  ? null
                                  : _next,
                              icon: Icon(
                                _isFinalStep
                                    ? _isUpcomingHike
                                          ? Icons.event_available_rounded
                                          : Icons.play_arrow_rounded
                                    : Icons.arrow_forward_rounded,
                              ),
                              label: Text(
                                _isScheduling
                                    ? 'Scheduling...'
                                    : _isStarting
                                    ? 'Starting...'
                                    : _isFinalStep
                                    ? _isUpcomingHike
                                          ? 'Schedule Hike'
                                          : 'Start Hiking Session'
                                    : 'Continue',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_checkingHazards)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: _WizardColors.backgroundFor(
                    context,
                  ).withValues(alpha: .96),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HikerCircleMinorLoadingIndicator(size: 70),
                        SizedBox(height: 12),
                        Text('Checking trail reports…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isScheduling)
            HikerCircleLoadingToastOverlay(
              message: 'Scheduling your hike…',
              detail: 'Saving the route, reminders, and join settings.',
              timeout: const Duration(seconds: 30),
              onTimeout: _handleRequestTimeout,
            ),
          if (_isStarting)
            GpsStartingOverlay(
              title: 'Starting your hike…',
              message: 'Completing safety checks and preparing live tracking.',
              timeout: const Duration(seconds: 30),
              onTimeout: _handleRequestTimeout,
            ),
        ],
      ),
    );
  }

  /// Handles request timeout.
  void _handleRequestTimeout() {
    if (!mounted) return;
    setState(() {
      _isScheduling = false;
      _isStarting = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('The request timed out. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Computes step for index.
  Widget _stepForIndex(int index) {
    switch (_steps[index]) {
      case _StartHikeWizardStep.type:
        return _HikeTypeStep(
          draft: _draft,
          isUpcomingHike: _isUpcomingHike,
          joinPolicy: _joinPolicy,
          onJoinPolicyChanged: (value) => setState(() => _joinPolicy = value),
          onChanged: _updateDraft,
        );
      case _StartHikeWizardStep.timing:
        if (_draft.trail.isUnlisted) {
          return _StepCard(
            title: 'Your location hike',
            subtitle:
                'No planned pathway is available. GPS records where you actually walk; weather follows your current location.',
            children: [
              Text(
                'Starting point: ${_draft.trail.latitude.toStringAsFixed(5)}, ${_draft.trail.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _draft.trail.estimatedDurationMinutes,
                decoration: const InputDecoration(
                  labelText: 'Planned hike duration',
                ),
                items: [
                  for (final minutes in [
                    30,
                    60,
                    120,
                    180,
                    240,
                    360,
                    480,
                    720,
                    1440,
                  ])
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        minutes < 60
                            ? '$minutes minutes'
                            : '${minutes / 60} hours',
                      ),
                    ),
                ],
                onChanged: (minutes) {
                  if (minutes != null) {
                    _updateDraft(
                      _draft.copyWith(
                        trail: _draft.trail.copyWith(
                          estimatedDurationMinutes: minutes,
                        ),
                        expectedArrivalTime: _draft.departureTime.add(
                          Duration(minutes: minutes),
                        ),
                        expectedReturnTime: _draft.departureTime.add(
                          Duration(minutes: minutes),
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Starts now. Set a realistic return time and tell your emergency contact where you plan to go. Distance, terrain and weather farther ahead are unknown.',
              ),
            ],
          );
        }
        return _TimingStep(
          draft: _draft,
          startNow: _startNow,
          onStartNowChanged: _updateStartNow,
          onChanged: _updateDraft,
        );
      case _StartHikeWizardStep.trail:
        return _TrailSelectionStep(
          draft: _draft,
          trails: _trails,
          onChanged: _updateDraft,
        );
      case _StartHikeWizardStep.reminder:
        return _StepCard(
          title: 'Your Hike Reminders',
          subtitle:
              'These choices apply only to you. Every invited hiker can choose their own reminder schedule after joining.',
          children: [
            if (_draft.hikeType == HikeType.team) ...[
              _JoinPolicySelector(
                joinPolicy: _joinPolicy,
                onChanged: (value) => setState(() => _joinPolicy = value),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),
            ],
            HikeReminderPreferencesEditor(
              preference: _reminderPreference,
              departureTime: _draft.departureTime,
              onChanged: (value) {
                setState(() => _reminderPreference = value);
              },
            ),
          ],
        );
      case _StartHikeWizardStep.safety:
        return _SafetySettingsStep(
          draft: _draft,
          onChanged: _updateDraft,
          onEditContacts:
              widget.onEditEmergencyContacts == null || _editingContacts
              ? null
              : _editSafetyContacts,
        );
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Presents the check location effect1 UI.
  void _presentCheckLocationEffect1() =>
      HikeStartNavigation.closeOwnedRoute(ModalRoute.of(context));

  /// Presents the check location effect2 UI.
  void _presentCheckLocationEffect2() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to check trail reports. Try again before continuing.',
          ),
        ),
      );

  /// Presents the next effect1 UI.
  void _presentNextEffect1() =>
      Navigator.of(context).pop(ActiveHikeSession.fromDraft(_draftForNow()));

  /// Presents the start now and finish effect1 UI.
  void _presentStartNowAndFinishEffect1(ModalRoute<Object?>? route) =>
      HikeStartNavigation.closeOwnedRoute(route);

  /// Presents the schedule and finish effect1 UI.
  void _presentScheduleAndFinishEffect1() => Navigator.of(context).pop();

  /// Presents the edit safety contacts effect1 UI.
  void _presentEditSafetyContactsEffect1() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not refresh emergency contacts. Please try again.',
          ),
        ),
      );
}

/// Displays the step progress.
class _StepProgress extends StatelessWidget {
  /// Creates step progress.
  const _StepProgress({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < totalSteps; index++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 5,
              decoration: BoxDecoration(
                color: index <= currentStep
                    ? _WizardColors.green
                    : _WizardColors.separatorFor(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (index != totalSteps - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Displays the hike type step.
class _HikeTypeStep extends StatelessWidget {
  /// Creates hike type step.
  const _HikeTypeStep({
    required this.draft,
    required this.isUpcomingHike,
    required this.joinPolicy,
    required this.onJoinPolicyChanged,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final bool isUpcomingHike;
  final String joinPolicy;
  final ValueChanged<String> onJoinPolicyChanged;
  final ValueChanged<HikeSessionDraft> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Choose your hiking mode',
      subtitle: 'Choose solo or group tracking for this route.',
      children: [
        if (draft.trail.distanceKm > 10)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              draft.trail.distanceKm > 20
                  ? '${draft.trail.distanceKm.toStringAsFixed(1)} km · Group setup required above 20 km'
                  : '${draft.trail.distanceKm.toStringAsFixed(1)} km · Solo acknowledgement required above 10 km',
            ),
          ),
        _ChoiceTile(
          selected: draft.hikeType == HikeType.solo,
          icon: Icons.person_pin_circle_rounded,
          title: 'Solo Hike',
          subtitle: 'Track your own route and optionally share location.',
          onTap: () => onChanged(
            draft.copyWith(hikeType: HikeType.solo, teamBuddies: const []),
          ),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: draft.hikeType == HikeType.team,
          icon: Icons.groups_2_rounded,
          title: 'Team Hike',
          subtitle: 'Create a session for friends or join an existing group.',
          onTap: () => onChanged(
            draft.copyWith(hikeType: HikeType.team, teamBuddies: const []),
          ),
        ),
        if (isUpcomingHike && draft.hikeType == HikeType.team) ...[
          const SizedBox(height: 18),
          _JoinPolicySelector(
            joinPolicy: joinPolicy,
            onChanged: onJoinPolicyChanged,
          ),
        ],
      ],
    );
  }
}

/// Displays the join policy selector.
class _JoinPolicySelector extends StatelessWidget {
  /// Creates join policy selector.
  const _JoinPolicySelector({
    required this.joinPolicy,
    required this.onChanged,
  });

  final String joinPolicy;
  final ValueChanged<String> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How people join',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'approval',
              icon: Icon(Icons.verified_user_outlined),
              label: Text('Needs approval'),
            ),
            ButtonSegment<String>(
              value: 'open',
              icon: Icon(Icons.group_add_rounded),
              label: Text('Open to join'),
            ),
          ],
          selected: <String>{joinPolicy},
          onSelectionChanged: (values) => onChanged(values.single),
        ),
        const SizedBox(height: 6),
        Text(
          joinPolicy == 'open'
              ? 'Signed-in hikers can join immediately.'
              : 'You will review each request before the hiker is added.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Displays the trail selection step.
class _TrailSelectionStep extends StatefulWidget {
  /// Creates trail selection step.
  const _TrailSelectionStep({
    required this.draft,
    required this.trails,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final List<Trail> trails;
  final ValueChanged<HikeSessionDraft> onChanged;

  /// Creates the presentation state for this widget.
  @override
  State<_TrailSelectionStep> createState() => _TrailSelectionStepState();
}

/// Manages the trail selection step presentation and lifecycle.
class _TrailSelectionStepState extends State<_TrailSelectionStep> {
  late final _TrailSelectionStepStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  bool _editMode = false;
  int? _highlightedCheckpointIndex;
  late Future<HikingRouteResult> _routeFuture;

  /// Returns checkpoints.
  List<TrailCheckpoint> get _checkpoints => _screenModel.commandCheckpoints;

  /// Returns route trail.
  Trail get _routeTrail => _screenModel.commandRouteTrail;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _TrailSelectionStepStateViewModel(
      readDraft: () => widget.draft,
      readOnChanged: () => widget.onChanged,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentAddCheckpointEffect1 =
        _presentAddCheckpointEffect1;

    _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
      _routeTrail,
    );
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _TrailSelectionStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.trail.trailId != widget.draft.trail.trailId ||
        HikingRouteService.checkpointsHash(
              oldWidget.draft.effectiveCheckpoints,
            ) !=
            HikingRouteService.checkpointsHash(_checkpoints)) {
      _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
        _routeTrail,
      );
      _highlightedCheckpointIndex = null;
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final cpsSorted = [..._checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));

    return _StepCard(
      title: 'Select Trail',
      subtitle:
          'Use 3–12 checkpoints. Start and end stay fixed; middle stops are optimized.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: widget.draft.trail.trailId,
          decoration: const InputDecoration(labelText: 'Selected Trail'),
          items: [
            for (final trail in widget.trails)
              DropdownMenuItem<String>(
                value: trail.trailId,
                child: Text(trail.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (trailId) {
            if (trailId == null) {
              return;
            }
            final nextTrail = widget.trails.firstWhere(
              (trail) => trail.trailId == trailId,
            );
            final current = widget.draft;
            final arrival = current.departureTime.add(
              Duration(
                minutes: math.max(0, nextTrail.estimatedDurationMinutes),
              ),
            );
            widget.onChanged(
              HikeSessionDraft.fromTrail(nextTrail).copyWith(
                hikeType: current.hikeType,
                departureTime: current.departureTime,
                expectedArrivalTime: arrival,
                expectedReturnTime: arrival.add(const Duration(hours: 2)),
                safetyCheckInInterval: current.safetyCheckInInterval,
                locationRecordingInterval: current.locationRecordingInterval,
                emergencyContactNames: current.emergencyContactNames,
                shareLiveLocation: current.shareLiveLocation,
                fallDetectionEnabled: current.fallDetectionEnabled,
                fallDetectionSettings: current.fallDetectionSettings,
                pathDeviationEnabled: current.pathDeviationEnabled,
                pathDeviationDistanceMeters:
                    current.pathDeviationDistanceMeters,
                offlinePhysicalAlertEnabled:
                    current.offlinePhysicalAlertEnabled,
                duressEnabled: current.duressEnabled,
                completedChecklistItems: current.completedChecklistItems,
                teamBuddies: current.teamBuddies,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _TrailSummary(trail: widget.draft.trail),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: FutureBuilder<HikingRouteResult>(
            future: _routeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _PreparingRouteLoader();
              }
              return RoutePreviewMap(
                trail: widget.draft.trail,
                route: snapshot.data,
                customCheckpoints: widget.draft.customCheckpoints,
                highlightedCheckpointIndex: _highlightedCheckpointIndex,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${cpsSorted.length} checkpoints',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${12 - cpsSorted.length} of 12 checkpoint slots remaining',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cpsSorted.length >= 12
                ? _WizardColors.orange
                : _WizardColors.secondaryTextFor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _WizardCheckpointTimeline(
          checkpoints: cpsSorted,
          editMode: _editMode,
          onShowOnMap: (index) {
            setState(() {
              _highlightedCheckpointIndex = _highlightedCheckpointIndex == index
                  ? null
                  : index;
            });
          },
          onEdit: _showEditCheckpointDialog,
          onRemove: _removeCheckpoint,
          onReorder: _reorderCheckpoint,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cpsSorted.length >= 12 ? null : _addCheckpoint,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Checkpoint'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => setState(() => _editMode = !_editMode),
              icon: Icon(
                _editMode ? Icons.edit_rounded : Icons.edit_note_rounded,
              ),
              isSelected: _editMode,
              tooltip: _editMode ? 'Done editing' : 'Edit checkpoints',
            ),
          ],
        ),
      ],
    );
  }

  /// Delegates add checkpoint to the ViewModel.
  Future<void> _addCheckpoint() => _screenModel.commandAddCheckpoint();

  /// Delegates remove checkpoint to the ViewModel.
  void _removeCheckpoint(int index) =>
      _screenModel.commandRemoveCheckpoint(index);

  /// Delegates reorder checkpoint to the ViewModel.
  void _reorderCheckpoint(int oldIndex, int newIndex) =>
      _screenModel.commandReorderCheckpoint(oldIndex, newIndex);

  /// Shows edit checkpoint dialog.
  Future<void> _showEditCheckpointDialog(int index) async {
    final cp = _checkpoints.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final checkpoint = cp[index];
    var editedName = checkpoint.name;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Checkpoint'),
        content: TextFormField(
          initialValue: checkpoint.name,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
          onChanged: (value) => editedName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editedName.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      final sorted = [..._checkpoints]
        ..sort((a, b) => a.order.compareTo(b.order));
      final updated = [...sorted];
      updated[index] = checkpoint.copyWith(name: newName);
      widget.onChanged(widget.draft.copyWith(customCheckpoints: updated));
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Presents the add checkpoint effect1 UI.
  Future<TrailCheckpoint?> _presentAddCheckpointEffect1() =>
      showModalBottomSheet<TrailCheckpoint>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: _WizardColors.surfaceFor(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: mediaQuery.size.height * 0.84,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  child: _CheckpointPickerSheet(
                    trail: widget.draft.trail,
                    existingCheckpoints: _checkpoints,
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// Displays the checkpoint step.
class _CheckpointStep extends StatefulWidget {
  /// Creates checkpoint step.
  const _CheckpointStep({required this.draft, required this.onChanged});

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  /// Creates the presentation state for this widget.
  @override
  State<_CheckpointStep> createState() => _CheckpointStepState();
}

/// Manages the checkpoint step presentation and lifecycle.
class _CheckpointStepState extends State<_CheckpointStep> {
  late final _CheckpointStepStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  bool _editMode = false;
  int? _highlightedCheckpointIndex;
  late Future<HikingRouteResult> _routeFuture;

  /// Returns checkpoints.
  List<TrailCheckpoint> get _checkpoints => _screenModel.commandCheckpoints;

  /// Returns route trail.
  Trail get _routeTrail => _screenModel.commandRouteTrail;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CheckpointStepStateViewModel(
      readDraft: () => widget.draft,
      readOnChanged: () => widget.onChanged,
    )..addListener(_renderScreenModel);

    _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
      _routeTrail,
    );
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _CheckpointStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.trail.trailId != widget.draft.trail.trailId ||
        HikingRouteService.checkpointsHash(
              oldWidget.draft.effectiveCheckpoints,
            ) !=
            HikingRouteService.checkpointsHash(_checkpoints)) {
      _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
        _routeTrail,
      );
    }
  }

  /// Adds checkpoint.
  void _addCheckpoint() {
    if (_checkpoints.length >= 12) {
      return;
    }
    showModalBottomSheet<TrailCheckpoint>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _WizardColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.84,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                child: _CheckpointPickerSheet(
                  trail: widget.draft.trail,
                  existingCheckpoints: _checkpoints,
                ),
              ),
            ),
          ),
        );
      },
    ).then((checkpoint) {
      if (checkpoint == null || !mounted) {
        return;
      }
      widget.onChanged(widget.draft.addCheckpoint(checkpoint));
    });
  }

  /// Delegates remove checkpoint to the ViewModel.
  void _removeCheckpoint(int index) =>
      _screenModel.commandRemoveCheckpoint(index);

  /// Delegates reorder checkpoint to the ViewModel.
  void _reorderCheckpoint(int oldIndex, int newIndex) =>
      _screenModel.commandReorderCheckpoint(oldIndex, newIndex);

  /// Shows edit checkpoint dialog.
  Future<void> _showEditCheckpointDialog(int index) async {
    final sorted = [..._checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    final checkpoint = sorted[index];
    var editedName = checkpoint.name;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Checkpoint'),
        content: TextFormField(
          initialValue: checkpoint.name,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
          onChanged: (value) => editedName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editedName.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      final updated = [...sorted];
      updated[index] = checkpoint.copyWith(name: newName);
      widget.onChanged(widget.draft.copyWith(customCheckpoints: updated));
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final cps = _checkpoints;
    final cpsSorted = [...cps]..sort((a, b) => a.order.compareTo(b.order));

    return _StepCard(
      title: 'Checkpoints',
      subtitle:
          'Use 3–12 checkpoints. Trailhead and trail end are fixed; middle stops are optimized.',
      children: [
        SizedBox(
          height: 220,
          child: FutureBuilder<HikingRouteResult>(
            future: _routeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _PreparingRouteLoader();
              }
              return RoutePreviewMap(
                trail: widget.draft.trail,
                route: snapshot.data,
                customCheckpoints: widget.draft.customCheckpoints,
                highlightedCheckpointIndex: _highlightedCheckpointIndex,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${cpsSorted.length} checkpoints',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        _WizardCheckpointTimeline(
          checkpoints: cpsSorted,
          editMode: _editMode,
          onShowOnMap: (index) {
            setState(() {
              _highlightedCheckpointIndex = _highlightedCheckpointIndex == index
                  ? null
                  : index;
            });
          },
          onEdit: _showEditCheckpointDialog,
          onRemove: _removeCheckpoint,
          onReorder: _reorderCheckpoint,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cpsSorted.length >= 12 ? null : _addCheckpoint,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Checkpoint'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => setState(() => _editMode = !_editMode),
              icon: Icon(
                _editMode ? Icons.edit_rounded : Icons.edit_note_rounded,
              ),
              isSelected: _editMode,
              tooltip: _editMode ? 'Done editing' : 'Edit checkpoints',
            ),
          ],
        ),
      ],
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the preparing route loader.
class _PreparingRouteLoader extends StatelessWidget {
  /// Creates preparing route loader.
  const _PreparingRouteLoader();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HikerCircleMinorLoadingIndicator(
            size: 108,
            semanticsLabel: 'Preparing route map',
          ),
          SizedBox(height: 6),
          Text(
            'Preparing your route…',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 3),
          Text(
            'Calculating the trail and checkpoints.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Displays the timing step.
class _TimingStep extends StatelessWidget {
  /// Creates timing step.
  const _TimingStep({
    required this.draft,
    required this.startNow,
    required this.onStartNowChanged,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final bool startNow;
  final ValueChanged<bool> onStartNowChanged;
  final ValueChanged<HikeSessionDraft> onChanged;

  /// Selects start now.
  void _selectStartNow() {
    onStartNowChanged(true);
    final now = DateTime.now();
    final hikeDuration = _safePlannedHikeDuration(draft);
    final expectedArrival = now.add(hikeDuration);
    onChanged(
      draft.copyWith(
        departureTime: now,
        expectedArrivalTime: expectedArrival,
        expectedReturnTime: expectedArrival.add(const Duration(hours: 2)),
      ),
    );
  }

  /// Selects scheduled start.
  void _selectScheduledStart(BuildContext context) {
    onStartNowChanged(false);
    final departure =
        draft.departureTime.isBefore(_minimumScheduledDepartureTime())
        ? _minimumScheduledDepartureTime()
        : draft.departureTime;
    _updateDeparture(context, departure, notifyIfAdjusted: false);
  }

  /// Updates departure.
  void _updateDeparture(
    BuildContext context,
    DateTime candidate, {
    bool notifyIfAdjusted = true,
  }) {
    var updated = candidate;
    final minimum = _minimumScheduledDepartureTime();
    if (updated.isBefore(minimum)) {
      updated = minimum;
      if (notifyIfAdjusted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Scheduled hikes must start at least 10 minutes from now.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
    final diff = _safePlannedHikeDuration(draft);
    onChanged(
      draft.copyWith(
        departureTime: updated,
        expectedArrivalTime: updated.add(diff),
        expectedReturnTime: updated.add(diff).add(const Duration(hours: 2)),
      ),
    );
  }

  /// Computes pick departure date.
  Future<void> _pickDepartureDate(BuildContext context) async {
    final minimum = _minimumScheduledDepartureTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.departureTime.isBefore(minimum)
          ? minimum
          : draft.departureTime,
      firstDate: DateTime(minimum.year, minimum.month, minimum.day),
      lastDate: minimum.add(const Duration(days: 365)),
    );
    if (picked == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final updated = DateTime(
      picked.year,
      picked.month,
      picked.day,
      draft.departureTime.hour,
      draft.departureTime.minute,
    );
    _updateDeparture(context, updated);
  }

  /// Computes pick departure time.
  Future<void> _pickDepartureTime(BuildContext context) async {
    final minimum = _minimumScheduledDepartureTime();
    final initial = draft.departureTime.isBefore(minimum)
        ? minimum
        : draft.departureTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final updated = DateTime(
      draft.departureTime.year,
      draft.departureTime.month,
      draft.departureTime.day,
      picked.hour,
      picked.minute,
    );
    _updateDeparture(context, updated);
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Timing and Tracking',
      subtitle: 'Choose when to start and how long you expect to hike.',
      children: [
        _ChoiceTile(
          selected: startNow,
          icon: Icons.play_circle_fill_rounded,
          title: 'Start Now',
          subtitle:
              'Continue through safety settings and start the active hike immediately.',
          onTap: _selectStartNow,
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: !startNow,
          icon: Icons.event_available_rounded,
          title: 'Schedule Time',
          subtitle:
              'Create an upcoming hike. Safety settings are chosen when it starts.',
          onTap: () => _selectScheduledStart(context),
        ),
        if (!startNow) ...[
          const SizedBox(height: 12),
          _TappableField(
            label: 'Departure Date',
            value: _formatDate(draft.departureTime),
            icon: Icons.calendar_today_rounded,
            onTap: () => _pickDepartureDate(context),
          ),
          const SizedBox(height: 12),
          _TappableField(
            label: 'Departure Time',
            value: _formatTime(draft.departureTime),
            icon: Icons.schedule_rounded,
            onTap: () => _pickDepartureTime(context),
          ),
          const SizedBox(height: 8),
          _InlineHint(
            icon: Icons.info_outline_rounded,
            text:
                'Earliest scheduled start: ${_formatDate(_minimumScheduledDepartureTime())} at ${_formatTime(_minimumScheduledDepartureTime())}.',
          ),
        ],
        const SizedBox(height: 12),
        _DurationPickerField(
          label: 'Estimated Hike Duration',
          value: draft.expectedArrivalTime.difference(draft.departureTime),
          onChanged: (duration) {
            final arrival = draft.departureTime.add(duration);
            onChanged(
              draft.copyWith(
                expectedArrivalTime: arrival,
                expectedReturnTime: arrival.add(const Duration(hours: 2)),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Estimated Time of Arrival',
          value: _formatTime(draft.expectedArrivalTime),
          icon: Icons.flag_rounded,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Estimated Return Time',
          value: _formatTime(draft.expectedReturnTime),
          icon: Icons.assignment_return_rounded,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Displays the safety settings step.
class _SafetySettingsStep extends StatelessWidget {
  /// Creates safety settings step.
  const _SafetySettingsStep({
    required this.draft,
    required this.onChanged,
    this.onEditContacts,
  });
  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;
  final VoidCallback? onEditContacts;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => _StepCard(
    title: 'Safety Settings',
    subtitle: 'Choose who receives updates and which monitors are active.',
    children: [
      HikeSafetySettingsForm(
        draft: draft,
        onChanged: onChanged,
        onEditContacts: onEditContacts,
      ),
    ],
  );
}

/// Displays the inline hint.
class _InlineHint extends StatelessWidget {
  /// Creates inline hint.
  const _InlineHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: _WizardColors.secondaryTextFor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _WizardColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays the trail summary.
class _TrailSummary extends StatelessWidget {
  /// Creates trail summary.
  const _TrailSummary({required this.trail});

  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _WizardColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trail.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              [
                trail.locationLabel,
                trail.distanceLabel,
                if (trail.hasCommunityDifficulty) trail.difficulty,
              ].join(' - '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the checkpoint picker sheet.
class _CheckpointPickerSheet extends StatefulWidget {
  /// Creates checkpoint picker sheet.
  const _CheckpointPickerSheet({
    required this.trail,
    required this.existingCheckpoints,
  });

  final Trail trail;
  final List<TrailCheckpoint> existingCheckpoints;

  /// Creates the presentation state for this widget.
  @override
  State<_CheckpointPickerSheet> createState() => _CheckpointPickerSheetState();
}

/// Manages the checkpoint picker sheet presentation and lifecycle.
class _CheckpointPickerSheetState extends State<_CheckpointPickerSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final int _nextOrder;
  late double _latitude;
  late double _longitude;

  /// Returns has valid coordinate input.
  bool get _hasValidCoordinateInput {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    return latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    final checkpoints = widget.existingCheckpoints;
    _nextOrder =
        checkpoints.fold<int>(
          0,
          (maxOrder, checkpoint) => math.max(maxOrder, checkpoint.order),
        ) +
        1;
    _nameController = TextEditingController(text: 'Checkpoint $_nextOrder');
    final initialCoordinate = _defaultCheckpointCoordinate(widget.trail);
    _latitude = initialCoordinate.latitude;
    _longitude = initialCoordinate.longitude;
    _latitudeController = TextEditingController(
      text: _latitude.toStringAsFixed(6),
    );
    _longitudeController = TextEditingController(
      text: _longitude.toStringAsFixed(6),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  /// Updates coordinate.
  void _updateCoordinate() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    setState(() {
      if (latitude != null &&
          longitude != null &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180) {
        _latitude = latitude;
        _longitude = longitude;
      }
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final selected = TrailCheckpoint(
      name: _nameController.text.trim().isEmpty
          ? 'Checkpoint $_nextOrder'
          : _nameController.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
      order: _nextOrder,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pin Checkpoint',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter the checkpoint coordinates and verify its position in the route preview.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Checkpoint Name',
            prefixIcon: Icon(Icons.flag_rounded),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitude'),
                onChanged: (_) => _updateCoordinate(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _longitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
                onChanged: (_) => _updateCoordinate(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: RoutePreviewMap(
            trail: widget.trail,
            customCheckpoints: [...widget.existingCheckpoints, selected],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        if (!_hasValidCoordinateInput) ...[
          const SizedBox(height: 6),
          Text(
            'Enter a latitude from -90 to 90 and longitude from -180 to 180.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _hasValidCoordinateInput
              ? () => Navigator.of(context).pop(selected)
              : null,
          icon: const Icon(Icons.add_location_alt_rounded),
          label: const Text('Add Checkpoint'),
        ),
      ],
    );
  }
}

/// Computes default checkpoint coordinate.
({double latitude, double longitude}) _defaultCheckpointCoordinate(
  Trail trail,
) {
  final checkpoints = [...trail.checkpoints]
    ..sort((a, b) => a.order.compareTo(b.order));
  if (checkpoints.isEmpty) {
    return (latitude: trail.latitude, longitude: trail.longitude);
  }

  final middleCheckpoint = checkpoints[checkpoints.length ~/ 2];
  return (
    latitude: middleCheckpoint.latitude,
    longitude: middleCheckpoint.longitude,
  );
}

/// Computes reorder draft checkpoints.
HikeSessionDraft _reorderDraftCheckpoints(
  HikeSessionDraft draft,
  int oldIndex,
  int newIndex,
) {
  final checkpoints = [...draft.effectiveCheckpoints]
    ..sort((a, b) => a.order.compareTo(b.order));
  if (oldIndex < 0 || oldIndex >= checkpoints.length) {
    return draft;
  }
  if (oldIndex < newIndex) {
    newIndex--;
  }
  newIndex = newIndex.clamp(0, checkpoints.length - 1);
  if (oldIndex == newIndex) {
    return draft;
  }
  final moved = checkpoints.removeAt(oldIndex);
  checkpoints.insert(newIndex, moved);
  final reindexed = checkpoints
      .asMap()
      .entries
      .map((entry) => entry.value.copyWith(order: entry.key + 1))
      .toList();
  return draft.copyWith(
    customCheckpoints: reindexed,
    startPointName: reindexed.first.name,
    destinationName: reindexed.last.name,
  );
}

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon, this.color = _WizardColors.green});

  final IconData icon;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _WizardColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

/// Displays the wizard checkpoint timeline.
class _WizardCheckpointTimeline extends StatelessWidget {
  /// Creates wizard checkpoint timeline.
  const _WizardCheckpointTimeline({
    required this.checkpoints,
    required this.editMode,
    required this.onShowOnMap,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  final List<TrailCheckpoint> checkpoints;
  final bool editMode;
  final void Function(int index) onShowOnMap;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (editMode) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: checkpoints.length,
        onReorderItem: (int oldIndex, int newIndex) {
          onReorder(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) => Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
        itemBuilder: (context, index) => _buildEditRow(context, index),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < checkpoints.length; index++)
          _buildNormalRow(context, index),
      ],
    );
  }

  /// Builds normal row.
  Widget _buildNormalRow(BuildContext context, int index) {
    final cp = checkpoints[index];
    final isLast = index == checkpoints.length - 1;
    return IntrinsicHeight(
      key: ValueKey('cp_$index'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: _WizardColors.greenSoftFor(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _WizardColors.green,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: _WizardColors.separatorFor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cp.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _WizardColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cp.latitude.toStringAsFixed(5)}, ${cp.longitude.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _WizardColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: IconButton(
              onPressed: () => onShowOnMap(index),
              icon: Icon(
                Icons.near_me_rounded,
                size: 20,
                color: _WizardColors.secondaryTextFor(context),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Show on map',
            ),
          ),
        ],
      ),
    );
  }

  /// Builds edit row.
  Widget _buildEditRow(BuildContext context, int index) {
    final cp = checkpoints[index];
    final canRemove =
        checkpoints.length > 3 && index > 0 && index < checkpoints.length - 1;
    return Padding(
      key: ValueKey('edit_cp_$index'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: _WizardColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: _WizardColors.secondaryTextFor(context),
                    size: 24,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cp.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _WizardColors.textFor(context),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cp.latitude.toStringAsFixed(5)}, ${cp.longitude.toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _WizardColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onEdit(index),
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: _WizardColors.green,
                tooltip: 'Edit name',
              ),
              if (canRemove)
                IconButton(
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: _WizardColors.red,
                  tooltip: 'Remove',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Computes minimum scheduled departure time.
DateTime _minimumScheduledDepartureTime() {
  final minimum = DateTime.now().add(const Duration(minutes: 10));
  final minutePrecision = DateTime(
    minimum.year,
    minimum.month,
    minimum.day,
    minimum.hour,
    minimum.minute,
  );
  if (minimum.second == 0 &&
      minimum.millisecond == 0 &&
      minimum.microsecond == 0) {
    return minutePrecision;
  }
  return minutePrecision.add(const Duration(minutes: 1));
}

/// Computes safe planned hike duration.
Duration _safePlannedHikeDuration(HikeSessionDraft draft) {
  final duration = draft.expectedArrivalTime.difference(draft.departureTime);
  if (!duration.isNegative && duration > Duration.zero) {
    return duration;
  }
  return Duration(minutes: math.max(1, draft.trail.estimatedDurationMinutes));
}

/// Applies safe recording interval.
HikeSessionDraft _withSafeRecordingInterval(HikeSessionDraft draft) {
  final interval = draft.locationRecordingInterval;
  final safeInterval = interval <= Duration.zero
      ? HikeSessionDraft.defaultLocationRecordingInterval
      : interval > const Duration(minutes: 1)
      ? const Duration(minutes: 1)
      : interval;
  return safeInterval == interval
      ? draft
      : draft.copyWith(locationRecordingInterval: safeInterval);
}

/// Applies platform safety policy.
HikeSessionDraft _withPlatformSafetyPolicy(HikeSessionDraft draft) {
  if (draft.trail.isUnlisted && draft.pathDeviationEnabled) {
    draft = draft.copyWith(pathDeviationEnabled: false);
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return draft;
  }
  final settings = draft.fallDetectionSettings;
  const androidWarningWindow = Duration(seconds: 15);
  if (settings.fallResponseDuration == androidWarningWindow) {
    return draft;
  }
  return draft.copyWith(
    fallDetectionSettings: FallDetectionSettings(
      sensorSensitivity: settings.sensorSensitivity,
      fallResponseDuration: androidWarningWindow,
      longestRestDuration: settings.longestRestDuration,
    ),
  );
}

/// Formats date.
String _formatDate(DateTime dateTime) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
}

/// Formats time.
String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

/// Computes duration label.
String _durationLabel(Duration duration) {
  if (duration.inSeconds < 60) {
    final seconds = duration.inSeconds;
    return '$seconds sec';
  }
  if (duration.inMinutes < 60) {
    final minutes = duration.inMinutes;
    return '$minutes min';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

/// Represents wizard colors.
abstract final class _WizardColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color orange = Color(0xFFF59E0B);
  static const Color red = Color(0xFFE11D48);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;
}
