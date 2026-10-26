part of '../start_hike_wizard_page_feature.dart';

/// Owns the state and non-visual actions of StartHikeWizardPage.
class _StartHikeWizardPageStateViewModel extends ChangeNotifier {
  /// Creates start hike wizard page state view model.
  _StartHikeWizardPageStateViewModel({required this.readPreselectedTrail});
  final Trail? Function() readPreselectedTrail;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late HikeSessionDraft stateDraft;

  int stateStepIndex = 0;

  bool stateStartNow = true;

  /// Returns command is upcoming hike.
  bool get commandIsUpcomingHike => !stateStartNow;

  /// Returns command steps.
  List<_StartHikeWizardStep> get commandSteps => [
    if (readPreselectedTrail() == null && !stateDraft.trail.isUnlisted)
      _StartHikeWizardStep.trail,
    _StartHikeWizardStep.type,
    _StartHikeWizardStep.timing,
    if (commandIsUpcomingHike) _StartHikeWizardStep.reminder,
    if (!commandIsUpcomingHike) _StartHikeWizardStep.safety,
  ];

  /// Returns command last step.
  int get commandLastStep => commandSteps.length - 1;

  /// Returns command step count.
  int get commandStepCount => commandSteps.length;

  /// Returns command visible step index.
  int get commandVisibleStepIndex => stateStepIndex;

  /// Returns command is final step.
  bool get commandIsFinalStep => stateStepIndex == commandLastStep;

  /// Updates draft.
  void commandUpdateDraft(HikeSessionDraft draft) {
    _publish(() {
      if (draft.fallDetectionSettings.sensorSensitivity !=
          stateDraft.fallDetectionSettings.sensorSensitivity) {
        AppSettingsController.instance.setFallSensorSensitivity(
          draft.fallDetectionSettings.sensorSensitivity,
        );
      }
      if (draft.pathDeviationDistanceMeters !=
          stateDraft.pathDeviationDistanceMeters) {
        AppSettingsController.instance.setPathDeviationDistanceMeters(
          draft.pathDeviationDistanceMeters,
        );
      }
      if (draft.locationRecordingInterval !=
          stateDraft.locationRecordingInterval) {
        unawaited(
          LocationUpdateIntervalController.instance.setInterval(
            draft.locationRecordingInterval,
          ),
        );
      }
      stateDraft = _withPlatformSafetyPolicy(_withSafeRecordingInterval(draft));
      commandClampStepIndex();
    });
  }

  /// Updates start now.
  void commandUpdateStartNow(bool startNow) {
    _publish(() {
      stateStartNow = startNow;
      commandClampStepIndex();
    });
  }

  /// Computes clamp step index.
  void commandClampStepIndex() {
    if (stateStepIndex < 0) {
      stateStepIndex = 0;
    }
    if (stateStepIndex > commandLastStep) {
      stateStepIndex = commandLastStep;
    }
  }

  /// Computes draft for now.
  HikeSessionDraft commandDraftForNow() {
    final now = DateTime.now();
    final hikeDuration = _safePlannedHikeDuration(stateDraft);
    final expectedArrival = now.add(hikeDuration);
    return _withPlatformSafetyPolicy(
      _withSafeRecordingInterval(stateDraft),
    ).copyWith(
      departureTime: now,
      expectedArrivalTime: expectedArrival,
      expectedReturnTime: stateDraft.trail.isUnlisted
          ? expectedArrival
          : expectedArrival.add(const Duration(hours: 2)),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<TrailHazardAlertAction> Function(Trail trail)? Function()
  readOnLocationSelected;

  late final Future<List<String>> Function()? Function()
  readOnEditEmergencyContacts;

  late final void Function() effectPresentCheckLocationEffect2;

  late final void Function() effectPresentEditSafetyContactsEffect1;

  late final void Function() effectPresentCheckLocationEffect1;

  bool stateCheckingHazards = false;

  bool stateInitialReportsChecked = true;

  bool stateEditingContacts = false;

  /// Checks location.
  Future<bool> commandCheckLocation() async {
    final check = readOnLocationSelected();
    if (check == null || stateDraft.trail.isUnlisted) return true;
    if (stateCheckingHazards) return false;
    _publish(() => stateCheckingHazards = true);
    try {
      final action = await check(stateDraft.trail);
      if (!mounted) return false;
      if (const {
        TrailHazardAlertAction.proceed,
        TrailHazardAlertAction.acknowledge,
        TrailHazardAlertAction.reschedule,
      }.contains(action)) {
        _publish(() {
          stateInitialReportsChecked = true;
          if (action == TrailHazardAlertAction.reschedule) {
            stateStartNow = false;
            final departure = _minimumScheduledDepartureTime();
            final arrival = departure.add(_safePlannedHikeDuration(stateDraft));
            stateDraft = stateDraft.copyWith(
              departureTime: departure,
              expectedArrivalTime: arrival,
              expectedReturnTime: arrival.add(const Duration(hours: 2)),
            );
          }
        });
        return true;
      }
      effectPresentCheckLocationEffect1();
      return false;
    } catch (_) {
      if (mounted) {
        effectPresentCheckLocationEffect2();
      }
      return false;
    } finally {
      if (mounted) _publish(() => stateCheckingHazards = false);
    }
  }

  /// Computes edit safety contacts.
  Future<void> commandEditSafetyContacts() async {
    if (stateEditingContacts || readOnEditEmergencyContacts() == null) return;
    _publish(() => stateEditingContacts = true);
    try {
      final names = await readOnEditEmergencyContacts()!();
      if (mounted) {
        commandUpdateDraft(stateDraft.copyWith(emergencyContactNames: names));
      }
    } catch (_) {
      if (mounted) {
        effectPresentEditSafetyContactsEffect1();
      }
    } finally {
      if (mounted) _publish(() => stateEditingContacts = false);
    }
  }
}

/// Owns the state and non-visual actions of _TrailSelectionStep.
class _TrailSelectionStepStateViewModel extends ChangeNotifier {
  /// Creates trail selection step state view model.
  _TrailSelectionStepStateViewModel({
    required this.readDraft,
    required this.readOnChanged,
  });
  final HikeSessionDraft Function() readDraft;
  final ValueChanged<HikeSessionDraft> Function() readOnChanged;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Returns command checkpoints.
  List<TrailCheckpoint> get commandCheckpoints =>
      readDraft().effectiveCheckpoints;

  /// Returns command route trail.
  Trail get commandRouteTrail =>
      readDraft().trail.copyWith(checkpoints: commandCheckpoints);

  /// Removes checkpoint.
  void commandRemoveCheckpoint(int index) {
    readOnChanged()(readDraft().removeCheckpointAt(index));
  }

  /// Computes reorder checkpoint.
  void commandReorderCheckpoint(int oldIndex, int newIndex) {
    readOnChanged()(_reorderDraftCheckpoints(readDraft(), oldIndex, newIndex));
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<TrailCheckpoint?> Function()
  effectPresentAddCheckpointEffect1;

  /// Adds checkpoint.
  Future<void> commandAddCheckpoint() async {
    if (commandCheckpoints.length >= 12) {
      return;
    }
    final checkpoint = await effectPresentAddCheckpointEffect1();
    if (checkpoint == null || !mounted) {
      return;
    }
    readOnChanged()(readDraft().addCheckpoint(checkpoint));
  }
}

/// Owns the state and non-visual actions of _CheckpointStep.
class _CheckpointStepStateViewModel extends ChangeNotifier {
  /// Creates checkpoint step state view model.
  _CheckpointStepStateViewModel({
    required this.readDraft,
    required this.readOnChanged,
  });
  final HikeSessionDraft Function() readDraft;
  final ValueChanged<HikeSessionDraft> Function() readOnChanged;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Returns command checkpoints.
  List<TrailCheckpoint> get commandCheckpoints =>
      readDraft().effectiveCheckpoints;

  /// Returns command route trail.
  Trail get commandRouteTrail =>
      readDraft().trail.copyWith(checkpoints: commandCheckpoints);

  /// Removes checkpoint.
  void commandRemoveCheckpoint(int index) {
    readOnChanged()(readDraft().removeCheckpointAt(index));
  }

  /// Computes reorder checkpoint.
  void commandReorderCheckpoint(int oldIndex, int newIndex) {
    readOnChanged()(_reorderDraftCheckpoints(readDraft(), oldIndex, newIndex));
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
