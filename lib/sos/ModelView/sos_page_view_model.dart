part of '../sos_page_feature.dart';

/// Owns the state and non-visual actions of SosPage.
class _SosPageStateViewModel extends ChangeNotifier {
  /// Creates sos page state view model.
  _SosPageStateViewModel({
    required this.readFirebaseBootstrapResult,
    required this.readPresentationController,
    required this.readSession,
    required this.effectCustomWhatsAppNoteFor,
  });
  final FirebaseBootstrapResult Function() readFirebaseBootstrapResult;
  final SosPresentationController? Function() readPresentationController;
  final AppSession Function() readSession;
  final String Function(SosAlertMode mode) effectCustomWhatsAppNoteFor;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final SosDeviceAlertService stateDeviceAlertService =
      const SosDeviceAlertService();

  final Queue<_QueuedSosRequest> stateQueuedSosRequests = Queue();

  final SosPresentationController stateOwnedPresentationController =
      SosPresentationController();

  late final NearbySosEventRepository stateNearbySosEventRepository;

  Future<void>? stateSosRequestDrain;

  late final SosViewModel stateViewModel;

  bool stateIsManualSosPatternActive = false;

  List<Map<String, dynamic>> stateAdminSosSystemLogs = const [];

  bool stateIsLoadingAdminSosSystemLogs = false;

  String? stateAdminSosSystemLogsError;

  List<NearbySosEvent> stateNearbySosEvents = const [];

  SosTriggerLocation? stateNearbyEventsPhoneLocation;

  bool stateIsLoadingNearbySosEvents = false;

  bool stateNearbySosReloadPending = false;

  final ValueNotifier<int> stateEventsRevision = ValueNotifier(0);

  bool stateIsRefreshingEvents = false;

  NetworkReachabilitySnapshot stateNetworkSnapshot =
      const NetworkReachabilitySnapshot(
        state: NetworkReachabilityState.checking,
      );

  /// Returns command presentation controller.
  SosPresentationController get commandPresentationController =>
      readPresentationController() ?? stateOwnedPresentationController;

  /// Refreshes.
  void commandRefresh() {
    if (!mounted) return;
    final result = stateViewModel.latestSosAlertResult;
    if (result != null) {
      commandPresentationController.updateDelivery(
        result.alert,
        queuedForRetry: result.queuedForRetry,
      );
    }
    _publish(() {});
    stateEventsRevision.value++;
  }

  /// Loads nearby sos events.
  Future<void> commandLoadNearbySosEvents() async {
    if (stateIsLoadingNearbySosEvents) {
      stateNearbySosReloadPending = true;
      return;
    }
    stateIsLoadingNearbySosEvents = true;
    try {
      final events = await stateNearbySosEventRepository.load(
        ownerPhoneNumber: readSession().phoneNumber,
      );
      if (!mounted) return;
      _publish(() {
        stateNearbySosEvents = events;
        stateNearbyEventsPhoneLocation =
            LocationSnapshotService.instance.latestLocation;
      });
      final phoneLocation = await commandCurrentPhoneLocation();
      if (!mounted) return;
      _publish(() {
        stateNearbyEventsPhoneLocation = phoneLocation;
      });
    } catch (error) {
      debugPrint('Unable to load nearby SOS events: $error');
    } finally {
      stateIsLoadingNearbySosEvents = false;
      if (mounted) stateEventsRevision.value++;
      if (stateNearbySosReloadPending && mounted) {
        stateNearbySosReloadPending = false;
        unawaited(commandLoadNearbySosEvents());
      }
    }
  }

  /// Computes current phone location.
  Future<SosTriggerLocation?> commandCurrentPhoneLocation() async {
    try {
      final snapshots = LocationSnapshotService.instance;
      return await snapshots.refresh() ?? snapshots.latestLocation;
    } catch (_) {
      return LocationSnapshotService.instance.latestLocation;
    }
  }

  /// Returns command active nearby sos events.
  List<NearbySosEvent> get commandActiveNearbySosEvents {
    final now = DateTime.now().toUtc();
    return stateNearbySosEvents
        .where(
          (event) => event.isActiveAt(
            now: now,
            phoneLocation: stateNearbyEventsPhoneLocation,
          ),
        )
        .toList(growable: false);
  }

  /// Returns command archived nearby sos events.
  List<NearbySosEvent> get commandArchivedNearbySosEvents {
    final now = DateTime.now().toUtc();
    return stateNearbySosEvents
        .where(
          (event) => !event.isActiveAt(
            now: now,
            phoneLocation: stateNearbyEventsPhoneLocation,
          ),
        )
        .toList(growable: false);
  }

  /// Loads emergency contacts and flush queue.
  Future<void> commandLoadEmergencyContactsAndFlushQueue() async {
    await stateViewModel.loadEmergencyContacts();
    final network = await NetworkReachabilityService.instance.refresh();
    if (mounted) {
      _publish(() {
        stateNetworkSnapshot = network;
      });
    }
    if (network.isOnline) {
      await stateViewModel.flushQueuedAlerts();
    }
  }

  /// Handles network reachability changed.
  void commandHandleNetworkReachabilityChanged(
    NetworkReachabilitySnapshot snapshot,
  ) {
    final wasOnline = stateNetworkSnapshot.isOnline;
    if (!mounted) {
      stateNetworkSnapshot = snapshot;
      return;
    }
    _publish(() {
      stateNetworkSnapshot = snapshot;
    });
    if (snapshot.isOnline &&
        (!wasOnline || stateViewModel.queuedAlertCount > 0)) {
      unawaited(commandFlushQueueAfterNetworkRestore());
    }
  }

  /// Retry queued SOS dispatch work after confirmed reachability returns.
  Future<void> commandFlushQueueAfterNetworkRestore() async {
    await stateViewModel.flushQueuedAlerts();
  }

  /// Loads admin sos system logs.
  Future<void> commandLoadAdminSosSystemLogs() async {
    if (stateIsLoadingAdminSosSystemLogs) {
      return;
    }
    _publish(() {
      stateIsLoadingAdminSosSystemLogs = true;
      stateAdminSosSystemLogsError = null;
    });

    try {
      final logs = await HikerCircleFirebaseRepository(
        firebaseBootstrapResult: readFirebaseBootstrapResult(),
      ).loadAdminSosAlerts(session: readSession());
      if (!mounted) {
        return;
      }
      _publish(() {
        stateAdminSosSystemLogs = logs;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        _publish(() {
          stateAdminSosSystemLogsError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        _publish(() {
          stateAdminSosSystemLogsError = 'Unable to load SOS events.';
        });
      }
    } finally {
      if (mounted) {
        _publish(() {
          stateIsLoadingAdminSosSystemLogs = false;
        });
        stateEventsRevision.value++;
      }
    }
  }

  /// Handles immediate sos.
  Future<void> commandHandleImmediateSos(
    SosAlertMode mode,
    SosAlertTriggerSource triggerSource,
  ) async {
    unawaited(
      mode == SosAlertMode.duress
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.heavyImpact(),
    );
    await commandEnqueueAlert(mode, triggerSource: triggerSource);
  }

  /// Handles duress sos.
  Future<void> commandHandleDuressSos() async {
    unawaited(HapticFeedback.mediumImpact());
    await commandEnqueueAlert(SosAlertMode.duress);
  }

  /// Refreshes sos events.
  Future<void> commandRefreshSosEvents() async {
    if (!mounted || stateIsRefreshingEvents) return;
    stateIsRefreshingEvents = true;
    stateEventsRevision.value++;
    try {
      await Future.wait([
        readSession().isAdmin
            ? commandLoadAdminSosSystemLogs()
            : stateViewModel.loadCloudAlertLogs(),
        commandLoadNearbySosEvents(),
      ]);
    } finally {
      stateIsRefreshingEvents = false;
      if (mounted) stateEventsRevision.value++;
    }
  }

  /// Serialize incoming SOS requests instead of letting multiple trigger sources race the same UI flow.
  Future<void> commandEnqueueAlert(
    SosAlertMode mode, {
    SosAlertTriggerSource? triggerSource,
  }) async {
    final triggeredAt = DateTime.now().toUtc();
    late final int presentationId;
    presentationId = commandPresentationController.begin(
      mode: mode,
      triggeredAt: triggeredAt,
      onStopAlarm: () => commandStopPresentedSosPattern(presentationId),
    );
    final request = _QueuedSosRequest(
      mode: mode,
      triggeredAt: triggeredAt,
      triggerSource: triggerSource ?? SosAlertTriggerSource.mobilePhone,
      presentationId: presentationId,
    );
    stateQueuedSosRequests.add(request);
    if (mode.usesLoudEmergencyPattern) {
      commandStartManualSosPattern(mode, presentationId);
    }

    // Keep checking after an existing worker completes. An alert can arrive in
    // the small interval between that worker emptying the queue and clearing
    // its Future, and it must start another worker instead of being stranded.
    while (mounted && stateQueuedSosRequests.isNotEmpty) {
      final activeDrain = stateSosRequestDrain;
      if (activeDrain != null) {
        await activeDrain;
        continue;
      }

      final drain = commandDrainSosRequests();
      stateSosRequestDrain = drain;
      try {
        await drain;
      } finally {
        if (identical(stateSosRequestDrain, drain)) {
          stateSosRequestDrain = null;
        }
      }
    }
  }

  /// Computes drain sos requests.
  Future<void> commandDrainSosRequests() async {
    while (mounted && stateQueuedSosRequests.isNotEmpty) {
      final request = stateQueuedSosRequests.removeFirst();
      await commandTriggerAlert(request);
    }
    if (!mounted) {
      stateQueuedSosRequests.clear();
    }
  }

  /// Capture trigger context and submit the selected mode while keeping local alarm output independent.
  Future<void> commandTriggerAlert(_QueuedSosRequest request) async {
    final mode = request.mode;
    final triggerLocation = await commandCaptureTriggerLocation();
    final result = await stateViewModel.triggerAlert(
      mode: mode,
      triggeredAt: request.triggeredAt,
      triggerLocation: triggerLocation,
      customMessageNote: effectCustomWhatsAppNoteFor(mode),
      triggerSource: request.triggerSource,
    );
    if (!mounted) {
      return;
    }

    final latestResult = stateViewModel.latestSosAlertResult;
    final matchingResult =
        latestResult != null &&
            latestResult.alert.mode == request.mode &&
            latestResult.alert.triggeredAt.isAtSameMomentAs(request.triggeredAt)
        ? latestResult
        : null;
    commandPresentationController.updateResult(
      request.presentationId,
      result ?? matchingResult,
      errorMessage: stateViewModel.sosAlertErrorMessage,
    );
  }

  /// Captures trigger location.
  Future<SosTriggerLocation?> commandCaptureTriggerLocation() async {
    final snapshotService = LocationSnapshotService.instance;
    final cached = snapshotService.latestLocation;
    if (cached != null) {
      // Do not hold emergency submission behind a new GPS fix. Refresh the
      // shared snapshot for subsequent safety events in the background.
      unawaited(snapshotService.refresh().catchError((_) => null));
      return cached;
    }
    try {
      return await snapshotService.refresh().timeout(
            const Duration(milliseconds: 600),
            onTimeout: () => snapshotService.latestLocation,
          ) ??
          snapshotService.latestLocation;
    } catch (_) {
      return snapshotService.latestLocation;
    }
  }

  /// Starts manual sos pattern.
  void commandStartManualSosPattern(SosAlertMode mode, int presentationId) {
    if (!commandPresentationController.isAlarmRequested(presentationId)) return;
    if (mounted) {
      _publish(() {
        stateIsManualSosPatternActive = true;
      });
    }
    startSosAlarmOutput(
      controller: commandPresentationController,
      eventId: presentationId,
      start: () => stateDeviceAlertService.startSosPatternForMode(mode),
      stop: stateDeviceAlertService.stopManualSosPattern,
      onUnavailable: () {
        if (mounted &&
            commandPresentationController.current?.eventId == presentationId) {
          _publish(() => stateIsManualSosPatternActive = false);
        }
      },
    );
  }

  /// Stops presented sos pattern.
  Future<void> commandStopPresentedSosPattern(int presentationId) async {
    if (commandPresentationController.current?.eventId != presentationId) {
      return;
    }
    await commandStopManualSosPattern(strict: true);
  }

  /// Stops manual sos pattern.
  Future<void> commandStopManualSosPattern({bool strict = false}) async {
    try {
      await stateDeviceAlertService.stopManualSosPattern(strict: strict);
    } finally {
      if (mounted) {
        _publish(() {
          stateIsManualSosPatternActive = false;
        });
      }
    }
  }

  /// Computes event log for alert.
  Map<String, dynamic> commandEventLogForAlert(SosAlert alert) {
    return <String, dynamic>{
      ...alert.toFirestore(),
      'alertId': alert.id,
      'phoneNumber': alert.triggeredByPhoneNumber,
    };
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<void> Function() effectHandleManualSos;

  late final Future<String?> Function() effectPresentOpenFirstAidGuideEffect1;

  late final Future<List<EmergencyContact>?> Function()
  effectPresentOpenEmergencyContactsEffect1;

  /// Opens emergency contacts.
  Future<void> commandOpenEmergencyContacts() async {
    final contacts = await effectPresentOpenEmergencyContactsEffect1();
    if (contacts != null && mounted) {
      stateViewModel.replaceEmergencyContacts(contacts);
    }
  }

  /// Opens first aid guide.
  Future<void> commandOpenFirstAidGuide() async {
    final result = await effectPresentOpenFirstAidGuideEffect1();

    if (result == 'sos' && mounted) {
      unawaited(effectHandleManualSos());
    }
  }
}

/// Owns the state and non-visual actions of _EmergencySosControlCard.
class _EmergencySosControlCardStateViewModel extends ChangeNotifier {
  /// Creates emergency sos control card state view model.
  _EmergencySosControlCardStateViewModel({
    required this.readIsAlarmActive,
    required this.readIsSending,
    required this.readOnStopAlarm,
    required this.readOnTrigger,
    required this.effectCancelPress,
  });
  final bool Function() readIsAlarmActive;
  final bool Function() readIsSending;
  final VoidCallback Function() readOnStopAlarm;
  final VoidCallback Function() readOnTrigger;
  final void Function() effectCancelPress;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  bool stateDuressTriggered = false;

  /// Handles tap up.
  void commandHandleTapUp(TapUpDetails details) {
    final shouldStopAlarm = readIsAlarmActive();
    if (shouldStopAlarm) {
      effectCancelPress();
      readOnStopAlarm()();
      return;
    }
    if (readIsSending()) {
      effectCancelPress();
      return;
    }
    final didTriggerDuress = stateDuressTriggered;
    effectCancelPress();
    if (didTriggerDuress) return;
    readOnTrigger()();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _SosGestureGuidePage.
class _SosGestureGuidePageStateViewModel extends ChangeNotifier {
  /// Creates sos gesture guide page state view model.
  _SosGestureGuidePageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  _SosGestureDemoResult stateDemoResult = _SosGestureDemoResult.waiting;

  bool stateIsHoldingDemo = false;

  /// Shows manual demo.
  void commandShowManualDemo() {
    unawaited(HapticFeedback.selectionClick());
    _publish(() {
      stateIsHoldingDemo = false;
      stateDemoResult = _SosGestureDemoResult.manual;
    });
  }

  /// Shows duress demo.
  void commandShowDuressDemo() {
    unawaited(HapticFeedback.mediumImpact());
    _publish(() {
      stateIsHoldingDemo = false;
      stateDemoResult = _SosGestureDemoResult.duress;
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _QueuedSosDispatchesPage.
class _QueuedSosDispatchesPageStateViewModel extends ChangeNotifier {
  /// Creates queued sos dispatches page state view model.
  _QueuedSosDispatchesPageStateViewModel({required this.readLoadDispatches});
  final Future<List<SosQueuedDispatch>> Function() Function()
  readLoadDispatches;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late Future<List<SosQueuedDispatch>> stateDispatches;

  /// Refreshes.
  void commandRefresh() {
    if (!mounted) return;
    final dispatches = readLoadDispatches()();
    _publish(() {
      stateDispatches = dispatches;
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _QueuedSosDispatchDetailPage.
class _QueuedSosDispatchDetailPageStateViewModel extends ChangeNotifier {
  /// Creates queued sos dispatch detail page state view model.
  _QueuedSosDispatchDetailPageStateViewModel({
    required this.readLoadDispatches,
  });
  final Future<List<SosQueuedDispatch>> Function() Function()
  readLoadDispatches;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late SosQueuedDispatch stateDispatch;

  bool stateIsQueued = true;

  int stateRevision = 0;

  /// Computes reload.
  Future<void> commandReload() async {
    final revision = ++stateRevision;
    try {
      final rows = await readLoadDispatches()();
      if (!mounted || revision != stateRevision) return;
      final updated = rows
          .where((row) => row.id == stateDispatch.id)
          .firstOrNull;
      _publish(() {
        stateIsQueued = updated != null;
        if (updated != null) stateDispatch = updated;
      });
    } catch (_) {
      // Retain the last known dispatch details while storage is unavailable.
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _WhatsAppMessageDetailPage.
class _WhatsAppMessageDetailPageStateViewModel extends ChangeNotifier {
  /// Creates whats app message detail page state view model.
  _WhatsAppMessageDetailPageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  late Map<SosAlertMode, String> stateNotes;

  /// Computes editable mode for.
  SosAlertMode commandEditableModeFor(SosAlertMode mode) {
    if (mode == SosAlertMode.duress ||
        mode == SosAlertMode.medical ||
        mode == SosAlertMode.manual) {
      return mode;
    }
    return SosAlertMode.manual;
  }

  /// Computes note for.
  String commandNoteFor(SosAlertMode mode) {
    return stateNotes[mode] ??
        SosAlertMessageComposer.defaultCustomNoteFor(mode);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _SosTestSettingsPage.
class _SosTestSettingsPageStateViewModel extends ChangeNotifier {
  /// Creates sos test settings page state view model.
  _SosTestSettingsPageStateViewModel({
    required this.readOnSendWhatsAppTest,
    required this.effectShowTestResult,
  });
  final Future<List<SosContactDispatch>> Function() Function()
  readOnSendWhatsAppTest;
  final void Function(String message) effectShowTestResult;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final SosDeviceAlertService stateDeviceAlertService =
      const SosDeviceAlertService();

  Timer? stateTestStopTimer;

  bool stateIsFlashlightActive = false;

  bool stateIsEmergencySirenActive = false;

  bool stateIsMedicalSirenActive = false;

  bool stateIsGyroscopeTestActive = false;

  double stateGyroscopeTestProgress = 0;

  String stateGyroscopeTestStatus =
      'Tap Start, then rotate your wrist left-right and tilt forward-back.';

  /// Sends whats app test message.
  Future<void> commandSendWhatsAppTestMessage() async {
    try {
      final dispatches = await readOnSendWhatsAppTest()();
      final sent = dispatches.where((dispatch) => dispatch.wasSent).length;
      final firstFailure = dispatches
          .where((dispatch) => !dispatch.wasSent)
          .map((dispatch) => dispatch.errorMessage?.trim() ?? '')
          .where((message) => message.isNotEmpty)
          .firstOrNull;
      effectShowTestResult(
        sent == dispatches.length
            ? 'WhatsApp cloud test sent to $sent/${dispatches.length} contacts.'
            : 'WhatsApp cloud test sent to $sent/${dispatches.length} contacts.'
                  '${firstFailure == null ? '' : ' $firstFailure'}',
      );
    } catch (error) {
      effectShowTestResult('Unable to send WhatsApp cloud test. $error');
    }
  }

  /// Stops all tests.
  Future<void> commandStopAllTests() async {
    stateTestStopTimer?.cancel();
    try {
      await stateDeviceAlertService.stopFlashlightPattern();
      await stateDeviceAlertService.stopManualSosPattern();
    } finally {
      if (mounted) {
        _publish(() {
          stateIsFlashlightActive = false;
          stateIsEmergencySirenActive = false;
          stateIsMedicalSirenActive = false;
        });
      }
    }
  }

  /// Computes schedule auto stop.
  void commandScheduleAutoStop() {
    stateTestStopTimer?.cancel();
    stateTestStopTimer = Timer(const Duration(seconds: 8), () {
      unawaited(commandStopAllTests());
    });
  }

  /// Starts gyroscope test.
  void commandStartGyroscopeTest() {
    _publish(() {
      stateIsGyroscopeTestActive = true;
      stateGyroscopeTestProgress = 0;
      stateGyroscopeTestStatus =
          'Ready. Rotate and tilt the phone for a few seconds.';
    });
  }

  /// Handles gyroscope test event.
  void commandHandleGyroscopeTestEvent(GyroscopeEvent event) {
    if (!stateIsGyroscopeTestActive || !mounted) {
      return;
    }
    final angularMotion = event.x.abs() + event.y.abs() + event.z.abs();
    if (angularMotion < 1.4) {
      return;
    }
    _publish(() {
      stateGyroscopeTestProgress = (stateGyroscopeTestProgress + 0.18)
          .clamp(0, 1)
          .toDouble();
      stateGyroscopeTestStatus = stateGyroscopeTestProgress >= 1
          ? 'Passed. Gyroscope detected rotation on the phone.'
          : 'Rotation detected. Keep rotating briefly.';
      if (stateGyroscopeTestProgress >= 1) {
        stateIsGyroscopeTestActive = false;
      }
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _FlashPatternPreview.
class _FlashPatternPreviewStateViewModel extends ChangeNotifier {
  /// Creates flash pattern preview state view model.
  _FlashPatternPreviewStateViewModel({required this.readActive});
  final bool Function() readActive;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  Timer? stateTimer;

  bool stateIsOn = false;

  /// Synchronizes timer.
  void commandSyncTimer() {
    stateTimer?.cancel();
    if (!readActive()) {
      _publish(() {
        stateIsOn = false;
      });
      return;
    }

    stateTimer = Timer.periodic(const Duration(milliseconds: 260), (_) {
      if (mounted) {
        _publish(() {
          stateIsOn = !stateIsOn;
        });
      }
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
