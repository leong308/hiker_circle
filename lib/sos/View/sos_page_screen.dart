part of '../sos_page_feature.dart';

/// Displays the sos page.
class SosPage extends StatefulWidget {
  /// Creates sos page.
  const SosPage({
    super.key,
    required this.session,
    this.manualSosRequestId = 0,
    this.onManualSosRequestConsumed,
    this.immediateSosRequestId = 0,
    this.immediateSosMode,
    this.immediateSosTriggerSource,
    this.onImmediateSosRequestConsumed,
    this.nearbySosEventRepository,
    this.sosAlertRepository,
    this.emergencyContactsRepository,
    this.presentationController,
    this.nearbySosRevision = 0,
    this.networkStatusOverride,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final int manualSosRequestId;
  final ValueChanged<int>? onManualSosRequestConsumed;
  final int immediateSosRequestId;
  final SosAlertMode? immediateSosMode;
  final SosAlertTriggerSource? immediateSosTriggerSource;
  final ValueChanged<int>? onImmediateSosRequestConsumed;
  final NearbySosEventRepository? nearbySosEventRepository;
  final SosAlertRepository? sosAlertRepository;
  final EmergencyContactsRepository? emergencyContactsRepository;
  final SosPresentationController? presentationController;
  final int nearbySosRevision;

  /// Optional presentation state for isolated previews; dispatch is unchanged.
  final NetworkReachabilitySnapshot? networkStatusOverride;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  /// Creates the presentation state for this widget.
  @override
  State<SosPage> createState() => _SosPageState();
}

/// Manages the sos page presentation and lifecycle.
class _SosPageState extends State<SosPage> {
  late final _SosPageStateViewModel _screenModel;

  /// Returns device alert service.
  SosDeviceAlertService get _deviceAlertService =>
      _screenModel.stateDeviceAlertService;

  /// Returns owned presentation controller.
  SosPresentationController get _ownedPresentationController =>
      _screenModel.stateOwnedPresentationController;

  /// Updates nearby sos event repository.
  set _nearbySosEventRepository(NearbySosEventRepository value) =>
      _screenModel.stateNearbySosEventRepository = value;

  /// Returns view model.
  SosViewModel get viewModel => _screenModel.stateViewModel;

  /// Updates view model.
  set viewModel(SosViewModel value) => _screenModel.stateViewModel = value;

  /// Returns is manual sos pattern active.
  bool get _isManualSosPatternActive =>
      _screenModel.stateIsManualSosPatternActive;

  /// Returns admin sos system logs.
  List<Map<String, dynamic>> get _adminSosSystemLogs =>
      _screenModel.stateAdminSosSystemLogs;

  /// Returns is loading admin sos system logs.
  bool get _isLoadingAdminSosSystemLogs =>
      _screenModel.stateIsLoadingAdminSosSystemLogs;

  /// Returns admin sos system logs error.
  String? get _adminSosSystemLogsError =>
      _screenModel.stateAdminSosSystemLogsError;

  /// Returns nearby events phone location.
  SosTriggerLocation? get _nearbyEventsPhoneLocation =>
      _screenModel.stateNearbyEventsPhoneLocation;

  /// Returns events revision.
  ValueNotifier<int> get _eventsRevision => _screenModel.stateEventsRevision;

  /// Returns is refreshing events.
  bool get _isRefreshingEvents => _screenModel.stateIsRefreshingEvents;

  /// Returns network snapshot.
  NetworkReachabilitySnapshot get _networkSnapshot =>
      _screenModel.stateNetworkSnapshot;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final HikerBleService _bleService = const HikerBleService();

  int _handledManualSosRequestId = 0;
  int _handledImmediateSosRequestId = 0;

  Map<SosAlertMode, String> get _customWhatsAppNotes => {
    ..._defaultWhatsAppNotes(),
    ...viewModel.customWhatsAppNotes,
  };

  Timer? _nearbySosRefreshTimer;
  StreamSubscription<NetworkReachabilitySnapshot>? _networkSubscription;
  StreamSubscription<void>? _connectionSubscription;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SosPageStateViewModel(
      readFirebaseBootstrapResult: () => widget.firebaseBootstrapResult,
      readPresentationController: () => widget.presentationController,
      readSession: () => widget.session,
      effectCustomWhatsAppNoteFor: _customWhatsAppNoteFor,
    )..addListener(_renderScreenModel);
    _screenModel.effectHandleManualSos = _handleManualSos;
    _screenModel.effectPresentOpenFirstAidGuideEffect1 =
        _presentOpenFirstAidGuideEffect1;
    _screenModel.effectPresentOpenEmergencyContactsEffect1 =
        _presentOpenEmergencyContactsEffect1;

    _nearbySosEventRepository =
        widget.nearbySosEventRepository ?? NearbySosEventRepository();
    unawaited(_activateSosAccount());
    viewModel = SosViewModel(
      session: widget.session,
      emergencyContactsRepository:
          widget.emergencyContactsRepository ??
          EmergencyContactsRepository(
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
          ),
      sosAlertRepository:
          widget.sosAlertRepository ??
          SosAlertRepository(
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
          ),
    );
    viewModel.addListener(_refresh);
    _networkSubscription = NetworkReachabilityService.instance.snapshots.listen(
      _handleNetworkReachabilityChanged,
    );
    _connectionSubscription = NetworkReachabilityService
        .instance
        .connectionAvailable
        .listen((_) {
          unawaited(viewModel.flushQueuedAlerts());
        });
    unawaited(NetworkReachabilityService.instance.start());
    unawaited(_loadEmergencyContactsAndFlushQueue());
    unawaited(_loadCustomWhatsAppNotes());
    unawaited(viewModel.loadCloudAlertLogs());
    unawaited(viewModel.loadQueuedAlertCount());
    unawaited(_loadNearbySosEvents());
    _nearbySosRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_loadNearbySosEvents());
    });
    if (widget.session.isAdmin) {
      unawaited(_loadAdminSosSystemLogs());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingManualSosRequest();
    });
  }

  /// Computes activate sos account.
  Future<void> _activateSosAccount() async {
    try {
      await _bleService.setActiveSosAccount(widget.session.phoneNumber);
    } on HikerBleException catch (error) {
      debugPrint('Unable to scope paired SOS buttons to this account: $error');
    }
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant SosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nearbySosRevision != oldWidget.nearbySosRevision) {
      unawaited(_loadNearbySosEvents());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingManualSosRequest();
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    if (_isManualSosPatternActive) {
      unawaited(_deviceAlertService.stopManualSosPattern());
    }
    _networkSubscription?.cancel();
    _connectionSubscription?.cancel();
    _eventsRevision.dispose();
    _nearbySosRefreshTimer?.cancel();
    unawaited(NetworkReachabilityService.instance.stop());
    viewModel.removeListener(_refresh);
    viewModel.dispose();
    _ownedPresentationController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates refresh to the ViewModel.
  void _refresh() => _screenModel.commandRefresh();

  /// Delegates load nearby sos events to the ViewModel.
  Future<void> _loadNearbySosEvents() =>
      _screenModel.commandLoadNearbySosEvents();

  /// Returns active nearby sos events.
  List<NearbySosEvent> get _activeNearbySosEvents =>
      _screenModel.commandActiveNearbySosEvents;

  /// Returns archived nearby sos events.
  List<NearbySosEvent> get _archivedNearbySosEvents =>
      _screenModel.commandArchivedNearbySosEvents;

  /// Computes default whats app notes.
  static Map<SosAlertMode, String> _defaultWhatsAppNotes() {
    return const {
      SosAlertMode.manual: SosAlertMessageComposer.defaultCustomNote,
      SosAlertMode.duress:
          'I may be under pressure and cannot speak safely. Please watch my live location, avoid calling if it may increase risk, and contact local emergency services if I stop responding.',
      SosAlertMode.medical:
          'I need medical help during my hike. Please call me, use the map link, and share this alert with medical responders if I do not answer.',
    };
  }

  /// Loads custom whats app notes.
  Future<void> _loadCustomWhatsAppNotes() async {
    await viewModel.loadCustomWhatsAppNotes();
  }

  /// Delegates load emergency contacts and flush queue to the ViewModel.
  Future<void> _loadEmergencyContactsAndFlushQueue() =>
      _screenModel.commandLoadEmergencyContactsAndFlushQueue();

  /// Delegates handle network reachability changed to the ViewModel.
  void _handleNetworkReachabilityChanged(
    NetworkReachabilitySnapshot snapshot,
  ) => _screenModel.commandHandleNetworkReachabilityChanged(snapshot);

  /// Computes custom whats app note for.
  String _customWhatsAppNoteFor(SosAlertMode mode) {
    return _customWhatsAppNotes[mode] ??
        SosAlertMessageComposer.defaultCustomNoteFor(mode);
  }

  /// Delegates load admin sos system logs to the ViewModel.
  Future<void> _loadAdminSosSystemLogs() =>
      _screenModel.commandLoadAdminSosSystemLogs();

  /// Handles pending manual sos request.
  void _handlePendingManualSosRequest() {
    final immediateMode = widget.immediateSosMode;
    if (mounted &&
        immediateMode != null &&
        widget.immediateSosRequestId > 0 &&
        widget.immediateSosRequestId != _handledImmediateSosRequestId) {
      final requestId = widget.immediateSosRequestId;
      _handledImmediateSosRequestId = requestId;
      unawaited(
        _handleImmediateSos(
          immediateMode,
          widget.immediateSosTriggerSource ?? SosAlertTriggerSource.mobilePhone,
        ),
      );
      // Claim the request synchronously after it has entered this page's
      // dispatch queue. The home shell can then clear its pending latch so a
      // later recreation of this widget cannot replay the same SOS.
      widget.onImmediateSosRequestConsumed?.call(requestId);
      return;
    }

    if (!mounted ||
        widget.manualSosRequestId <= 0 ||
        widget.manualSosRequestId == _handledManualSosRequestId) {
      return;
    }

    final requestId = widget.manualSosRequestId;
    _handledManualSosRequestId = requestId;
    unawaited(_handleManualSos());
    // The confirmation countdown is already presented before this callback
    // runs. Clear the parent latch now so rebuilding the page cannot present
    // another countdown for the same external request.
    widget.onManualSosRequestConsumed?.call(requestId);
  }

  /// Handles manual sos.
  Future<void> _handleManualSos() async {
    // This is a preflight check: once the countdown expires, the triggered
    // surface and local alarm must not wait behind another volume dialog.
    final volumeReady = await ensureIosSosOutputVolumeReady(
      context: context,
      deviceAlertService: _deviceAlertService,
      message:
          '${SosAlertMode.manual.label} uses iPhone media volume for the local alarm. Turn it up before continuing.',
    );
    if (!volumeReady || !mounted) return;
    unawaited(HapticFeedback.heavyImpact());
    final shouldSend = await _presentHandleManualSosEffect1();

    if (shouldSend != true || !mounted) {
      return;
    }

    await _enqueueAlert(SosAlertMode.manual);
  }

  /// Delegates handle immediate sos to the ViewModel.
  Future<void> _handleImmediateSos(
    SosAlertMode mode,
    SosAlertTriggerSource triggerSource,
  ) => _screenModel.commandHandleImmediateSos(mode, triggerSource);

  /// Delegates handle duress sos to the ViewModel.
  Future<void> _handleDuressSos() => _screenModel.commandHandleDuressSos();

  /// Opens test settings.
  void _openTestSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SosTestSettingsPage(
          phoneNumber: widget.session.phoneNumber,
          onSendWhatsAppTest: viewModel.sendWhatsAppTestMessage,
        ),
      ),
    );
  }

  /// Opens paired sos button.
  void _openPairedSosButton() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            PairedSosButtonPage(accountId: widget.session.phoneNumber),
      ),
    );
  }

  /// Opens sos gesture guide.
  void _openSosGestureGuide() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const _SosGestureGuidePage()),
    );
  }

  /// Opens queued dispatches.
  void _openQueuedDispatches() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _QueuedSosDispatchesPage(
          phoneNumber: widget.session.phoneNumber,
          loadDispatches: viewModel.loadQueuedDispatches,
        ),
      ),
    );
  }

  /// Delegates open emergency contacts to the ViewModel.
  Future<void> _openEmergencyContacts() =>
      _screenModel.commandOpenEmergencyContacts();

  /// Delegates refresh sos events to the ViewModel.
  Future<void> _refreshSosEvents() => _screenModel.commandRefreshSosEvents();

  /// Opens sos events.
  void _openSosEvents() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AnimatedBuilder(
          animation: Listenable.merge([viewModel, _eventsRevision]),
          builder: (context, _) => _SosEventsPage(
            logs: widget.session.isAdmin
                ? _adminSosSystemLogs
                : viewModel.cloudAlertLogs.map(_eventLogForAlert).toList(),
            nearbyEvents: _archivedNearbySosEvents,
            phoneLocation: _nearbyEventsPhoneLocation,
            isLoading: _isRefreshingEvents || _isLoadingAdminSosSystemLogs,
            errorMessage: widget.session.isAdmin
                ? _adminSosSystemLogsError
                : null,
            onNearbyEventTap: _openNearbySosEvent,
            onRefresh: _refreshSosEvents,
          ),
        ),
      ),
    );
  }

  /// Delegates open first aid guide to the ViewModel.
  Future<void> _openFirstAidGuide() => _screenModel.commandOpenFirstAidGuide();

  /// Opens gears required.
  void _openGearsRequired() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const GearsRequiredPage()),
    );
  }

  /// Opens live location page.
  void _openLiveLocationPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocationSharingPage(
          phoneNumber: widget.session.phoneNumber,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
  }

  /// Opens nearby sos event.
  void _openNearbySosEvent(NearbySosEvent event) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NearbySosMapPage(
          event: event,
          initialPhoneLocation: _nearbyEventsPhoneLocation,
        ),
      ),
    );
  }

  /// Serialize incoming SOS requests instead of letting multiple trigger sources race the same UI flow.
  Future<void> _enqueueAlert(
    SosAlertMode mode, {
    SosAlertTriggerSource? triggerSource,
  }) => _screenModel.commandEnqueueAlert(mode, triggerSource: triggerSource);

  /// Delegates stop manual sos pattern to the ViewModel.
  Future<void> _stopManualSosPattern({bool strict = false}) =>
      _screenModel.commandStopManualSosPattern(strict: strict);

  /// Delegates event log for alert to the ViewModel.
  Map<String, dynamic> _eventLogForAlert(SosAlert alert) =>
      _screenModel.commandEventLogForAlert(alert);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final activeNearbyEvents = _activeNearbySosEvents;
    final archivedNearbyEvents = _archivedNearbySosEvents;
    final userEventLogs = viewModel.cloudAlertLogs
        .map(_eventLogForAlert)
        .toList(growable: false);
    return ColoredBox(
      color: _SosColors.backgroundFor(context),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    onOpenTestSettings: _openTestSettings,
                    onOpenPairedButton: _openPairedSosButton,
                  ),
                  if (activeNearbyEvents.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ActiveNearbySosEventsPanel(
                      events: activeNearbyEvents,
                      phoneLocation: _nearbyEventsPhoneLocation,
                      onTap: _openNearbySosEvent,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _NetworkSosStatusCard(
                    isNetworkAvailable:
                        widget.firebaseBootstrapResult.isAvailable &&
                        (widget.networkStatusOverride ?? _networkSnapshot)
                            .isOnline,
                    isCheckingNetwork:
                        (widget.networkStatusOverride ?? _networkSnapshot)
                            .state ==
                        NetworkReachabilityState.checking,
                    errorMessage:
                        widget.firebaseBootstrapResult.errorMessage ??
                        (widget.networkStatusOverride ?? _networkSnapshot)
                            .message,
                  ),
                  const SizedBox(height: 14),
                  _MetricsGroup(
                    metrics: viewModel.metrics,
                    onContactsTap: () => unawaited(_openEmergencyContacts()),
                    onLiveTap: _openLiveLocationPage,
                    onQueuedTap: _openQueuedDispatches,
                  ),
                  const SizedBox(height: 14),
                  _EmergencySosControlCard(
                    isSending: viewModel.isSendingSosAlert,
                    isAlarmActive: _isManualSosPatternActive,
                    onTrigger: () => unawaited(_handleManualSos()),
                    onStopAlarm: () => unawaited(_stopManualSosPattern()),
                    onShowGuide: _openSosGestureGuide,
                    onDuressLongPress: () => unawaited(_handleDuressSos()),
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel(label: 'Safety Tools'),
                  const SizedBox(height: 8),
                  _SosSafetyToolsGrid(
                    onOpenFirstAid: () => unawaited(_openFirstAidGuide()),
                    onOpenGearsRequired: _openGearsRequired,
                  ),
                  const SizedBox(height: 22),
                  if (widget.session.isAdmin)
                    _AdminSosSystemLogsPanel(
                      onOpen: _openSosEvents,
                      logs: _adminSosSystemLogs,
                      nearbyEvents: archivedNearbyEvents,
                      isLoading: _isLoadingAdminSosSystemLogs,
                      errorMessage: _adminSosSystemLogsError,
                      onRefresh: () {
                        unawaited(_loadAdminSosSystemLogs());
                        unawaited(_loadNearbySosEvents());
                      },
                    )
                  else ...[
                    _SosTriggerLogPanel(
                      session: widget.session,
                      latestResult: viewModel.latestSosAlertResult,
                      customWhatsAppNotes: _customWhatsAppNotes,
                      onCustomWhatsAppNoteChanged: (mode, note) {
                        unawaited(
                          viewModel
                              .saveCustomWhatsAppNote(mode: mode, note: note)
                              .catchError((_) {}),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _AdminSosSystemLogsPanel(
                      onOpen: _openSosEvents,
                      logs: userEventLogs,
                      nearbyEvents: archivedNearbyEvents,
                      isLoading: false,
                      errorMessage: null,
                      onRefresh: () {
                        unawaited(viewModel.loadCloudAlertLogs());
                        unawaited(_loadNearbySosEvents());
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the handle manual sos effect1 UI.
  Future<bool?> _presentHandleManualSosEffect1() => showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return const _ManualSosCountdownDialog();
    },
  );

  /// Presents the open emergency contacts effect1 UI.
  Future<List<EmergencyContact>?> _presentOpenEmergencyContactsEffect1() =>
      Navigator.of(context).push<List<EmergencyContact>>(
        MaterialPageRoute<List<EmergencyContact>>(
          builder: (_) => EmergencyContactsPage(
            session: widget.session,
            initialContacts: viewModel.emergencyContacts,
            repository: viewModel.emergencyContactsRepository,
          ),
        ),
      );

  /// Presents the open first aid guide effect1 UI.
  Future<String?> _presentOpenFirstAidGuideEffect1() =>
      Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (context) => const FirstAidGuidePage(),
        ),
      );
}

/// Displays the header action.
class _HeaderAction extends StatelessWidget {
  /// Creates header action.
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PageHeaderAction(
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    color: _SosColors.green,
    surface: _SosColors.surfaceFor(context),
  );
}

/// Displays the manual sos countdown dialog.
class _ManualSosCountdownDialog extends StatefulWidget {
  /// Creates manual sos countdown dialog.
  const _ManualSosCountdownDialog();

  /// Creates the presentation state for this widget.
  @override
  State<_ManualSosCountdownDialog> createState() =>
      _ManualSosCountdownDialogState();
}

/// Manages the manual sos countdown dialog presentation and lifecycle.
class _ManualSosCountdownDialogState extends State<_ManualSosCountdownDialog> {
  static const int _totalSeconds = 10;

  Timer? _timer;
  int _secondsRemaining = _totalSeconds;
  bool _didComplete = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final nextSecond = _secondsRemaining - 1;
      if (nextSecond <= 0) {
        _completeCountdown();
        return;
      }

      setState(() {
        _secondsRemaining = nextSecond;
      });
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Computes complete countdown.
  void _completeCountdown() {
    if (_didComplete || !mounted) {
      return;
    }

    _didComplete = true;
    _timer?.cancel();
    HikeStartNavigation.closeOwnedRoute<bool>(
      ModalRoute.of<bool>(context),
      true,
    );
  }

  /// Cancels.
  void _cancel() {
    if (_didComplete) {
      return;
    }

    _didComplete = true;
    _timer?.cancel();
    HikeStartNavigation.closeOwnedRoute<bool>(
      ModalRoute.of<bool>(context),
      false,
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final progress = (_totalSeconds - _secondsRemaining) / _totalSeconds;

    return CupertinoAlertDialog(
      title: const Text('Emergency SOS'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(
              'Sending in $_secondsRemaining seconds',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: _SosColors.destructiveFor(context),
              backgroundColor: _SosColors.destructiveSoftFor(context),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: _cancel,
          child: const Text('Cancel SOS'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _completeCountdown,
          child: const Text('Send Now'),
        ),
      ],
    );
  }
}

/// Displays the metrics group.
class _MetricsGroup extends StatelessWidget {
  /// Creates metrics group.
  const _MetricsGroup({
    required this.metrics,
    required this.onContactsTap,
    required this.onLiveTap,
    required this.onQueuedTap,
  });

  final List<SosMetric> metrics;
  final VoidCallback onContactsTap;
  final VoidCallback onLiveTap;
  final VoidCallback onQueuedTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final height = math.max(
      56.0,
      textScaler.scale(17) * 1.1 + textScaler.scale(11.5) * 1.2 + 17,
    );
    return Material(
      color: _SosColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const ValueKey('sos-status-row'),
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0)
                Center(
                  child: Container(
                    width: 1,
                    height: 24,
                    color: _SosColors.separatorFor(context),
                  ),
                ),
              Expanded(
                child: _MetricCell(
                  metric: metrics[index],
                  onTap: switch (metrics[index].label) {
                    'Contacts' => onContactsTap,
                    'Live' => onLiveTap,
                    'Queued' => onQueuedTap,
                    _ => null,
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays the metric cell.
class _MetricCell extends StatelessWidget {
  /// Creates metric cell.
  const _MetricCell({required this.metric, this.onTap});

  final SosMetric metric;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final queued =
        metric.label == 'Queued' && (int.tryParse(metric.value) ?? 0) > 0;
    final inactive =
        metric.label == 'Live' && metric.value.toLowerCase() == 'off';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = queued
        ? isDark
              ? const Color(0xFFFFC578)
              : const Color(0xFF995600)
        : inactive
        ? _SosColors.secondaryTextFor(context)
        : isDark
        ? const Color(0xFF9AD7AF)
        : const Color(0xFF287844);
    final icon = switch (metric.label) {
      'Contacts' => Icons.people_outline_rounded,
      'Queued' => Icons.outbox_outlined,
      _ => Icons.share_location_rounded,
    };
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: queued
                            ? accent
                            : inactive
                            ? _SosColors.secondaryTextFor(context)
                            : _SosColors.textFor(context),
                        fontSize: 17,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _SosColors.secondaryTextFor(context),
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Computes nearby sos event summary.
String _nearbySosEventSummary(
  NearbySosEvent event,
  SosTriggerLocation? phoneLocation,
) {
  final age = event.ageAt(DateTime.now().toUtc());
  final ageLabel = age.inMinutes < 1
      ? 'Just now'
      : age.inMinutes == 1
      ? '1 minute ago'
      : '${age.inMinutes} minutes ago';
  final distance = event.distanceMetersFrom(phoneLocation);
  if (distance == null) return ageLabel;
  return '$ageLabel • ${_nearbySosDistance(distance)}';
}

/// Computes nearby sos distance.
String _nearbySosDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

/// Computes nearby sos timestamp.
String _nearbySosTimestamp(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  return '$date $time';
}

/// Displays the sos events page.
class _SosEventsPage extends StatelessWidget {
  /// Creates sos events page.
  const _SosEventsPage({
    required this.logs,
    required this.nearbyEvents,
    required this.phoneLocation,
    required this.isLoading,
    required this.errorMessage,
    required this.onNearbyEventTap,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> logs;
  final List<NearbySosEvent> nearbyEvents;
  final SosTriggerLocation? phoneLocation;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<NearbySosEvent> onNearbyEventTap;
  final Future<void> Function() onRefresh;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      appBar: PageHeaderAppBar(
        title: const Text('SOS events'),
        actions: [
          IconButton(
            tooltip: 'Refresh SOS events',
            onPressed: isLoading ? null : () => unawaited(onRefresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              if (isLoading) const LinearProgressIndicator(),
              if (isLoading) const SizedBox(height: 12),
              _InsetGroup(
                child: Column(
                  children: [
                    if (errorMessage != null)
                      _SosSystemLogEmptyState(
                        icon: Icons.cloud_off_rounded,
                        message: errorMessage!,
                      ),
                    if (logs.isEmpty &&
                        nearbyEvents.isEmpty &&
                        !isLoading &&
                        errorMessage == null)
                      const _SosSystemLogEmptyState(
                        icon: Icons.fact_check_rounded,
                        message: 'No SOS events yet.',
                      ),
                    for (
                      var index = 0;
                      index < nearbyEvents.length;
                      index++
                    ) ...[
                      _NearbySosHistoryRow(
                        event: nearbyEvents[index],
                        phoneLocation: phoneLocation,
                        onTap: () => onNearbyEventTap(nearbyEvents[index]),
                      ),
                      if (index != nearbyEvents.length - 1 || logs.isNotEmpty)
                        const _HorizontalSeparator(),
                    ],
                    for (var index = 0; index < logs.length; index++) ...[
                      _SosSystemLogRow(log: logs[index]),
                      if (index != logs.length - 1)
                        const _HorizontalSeparator(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows sos system log details.
void _showSosSystemLogDetails(BuildContext context, Map<String, dynamic> log) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => _SosSystemLogDetailPage(log: log)),
  );
}

/// Displays the sos system log detail page.
class _SosSystemLogDetailPage extends StatelessWidget {
  /// Creates sos system log detail page.
  const _SosSystemLogDetailPage({required this.log});

  final Map<String, dynamic> log;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => StreamBuilder<SosQueueChange>(
    stream: SosAlertRepository.queueChanges.where(
      (change) => change.alert?.id == log['id'],
    ),
    builder: (context, snapshot) => _buildDetails(
      context,
      snapshot.data?.alert == null
          ? log
          : {...log, ...snapshot.data!.alert!.toFirestore()},
    ),
  );

  /// Presents the newest contact receipts without changing the original emergency details.
  Widget _buildDetails(BuildContext context, Map<String, dynamic> log) {
    final alert = SosAlert.fromFirestore(log);
    final location = _sosLogLocation(log['triggerLocation']);
    final mode = _sosLogString(log['mode'], fallback: 'sos');
    final status = _sosLogString(log['status'], fallback: 'unknown');

    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      appBar: PageHeaderAppBar(title: const Text('SOS event')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            6,
            18,
            18 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const _Glyph(
                    icon: Icons.sos_rounded,
                    color: _SosColors.green,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _friendlySosType(mode),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _SosColors.textFor(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                        Text(
                          _sosLogDateLabel(log['triggeredAtLocal']),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _SosColors.secondaryTextFor(context),
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InsetGroup(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _StatusRow(label: 'Type', value: _friendlySosType(mode)),
                      const _HorizontalSeparator(),
                      _StatusRow(
                        label: 'Status',
                        value: status == 'partial'
                            ? alert.confirmationLabel
                            : _friendlySosStatus(status),
                      ),
                      const _HorizontalSeparator(),
                      _StatusRow(
                        label: 'Hiker',
                        value: _sosLogString(
                          log['phoneNumber'],
                          fallback: _sosLogString(
                            log['triggeredByPhoneNumber'],
                            fallback: '-',
                          ),
                        ),
                      ),
                      const _HorizontalSeparator(),
                      _StatusRow(
                        label: 'Location',
                        value: location == null
                            ? 'Location unavailable'
                            : location.accuracyMeters == null
                            ? 'Location captured'
                            : 'Captured within about ${location.accuracyMeters!.round()} m',
                      ),
                      if (location != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(location.universalMapLink),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.map_rounded),
                            label: const Text('View on map'),
                          ),
                        ),
                      ],
                      const _HorizontalSeparator(),
                      _StatusRow(
                        label: 'Contacts',
                        value: alert.confirmationLabel,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Confirmed means accepted by the messaging service; it does not mean read.',
                      ),
                      SosContactDeliveryList(dispatches: alert.dispatches),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Defines the sos gesture demo result choices.
enum _SosGestureDemoResult { waiting, manual, duress }

/// Displays the sos gesture guide page.
class _SosGestureGuidePage extends StatefulWidget {
  /// Creates sos gesture guide page.
  const _SosGestureGuidePage();

  /// Creates the presentation state for this widget.
  @override
  State<_SosGestureGuidePage> createState() => _SosGestureGuidePageState();
}

/// Manages the sos gesture guide page presentation and lifecycle.
class _SosGestureGuidePageState extends State<_SosGestureGuidePage> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SosGestureGuidePageStateViewModel()
      ..addListener(_renderScreenModel);
  }

  late final _SosGestureGuidePageStateViewModel _screenModel;

  /// Returns demo result.
  _SosGestureDemoResult get _demoResult => _screenModel.stateDemoResult;

  /// Returns is holding demo.
  bool get _isHoldingDemo => _screenModel.stateIsHoldingDemo;

  /// Updates is holding demo.
  set _isHoldingDemo(bool value) => _screenModel.stateIsHoldingDemo = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Delegates show manual demo to the ViewModel.
  void _showManualDemo() => _screenModel.commandShowManualDemo();

  /// Delegates show duress demo to the ViewModel.
  void _showDuressDemo() => _screenModel.commandShowDuressDemo();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'Manual & Duress SOS',
                    subtitle: 'One button, two emergency actions',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _SosGestureExplanationCard(
                    icon: Icons.touch_app_rounded,
                    color: _SosColors.destructiveFor(context),
                    title: 'Tap for Manual SOS',
                    subtitle:
                        'Shows a 10-second cancel window, then starts the phone alarm and flashlight while notifying your contacts.',
                  ),
                  const SizedBox(height: 10),
                  const _SosGestureExplanationCard(
                    icon: Icons.visibility_off_rounded,
                    color: _SosColors.duress,
                    title: 'Hold for Duress SOS',
                    subtitle:
                        'Hold for about one second. The alert is sent silently without an alarm or countdown, and contacts are warned not to call if that could increase danger.',
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel(label: 'Try the gesture safely'),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _SosColors.greenSoftFor(context),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'DEMO ONLY · NO ALERT WILL BE SENT',
                              style: TextStyle(
                                color: _SosColors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _showManualDemo,
                            onLongPressStart: (_) {
                              setState(() => _isHoldingDemo = true);
                            },
                            onLongPress: _showDuressDemo,
                            onLongPressEnd: (_) {
                              if (mounted) {
                                setState(() => _isHoldingDemo = false);
                              }
                            },
                            child: AnimatedContainer(
                              key: const Key('sos-gesture-demo-button'),
                              duration: const Duration(milliseconds: 180),
                              width: 144,
                              height: 144,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isHoldingDemo
                                    ? _SosColors.duress
                                    : _SosColors.destructiveFor(context),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isHoldingDemo
                                                ? _SosColors.duress
                                                : _SosColors.destructiveFor(
                                                    context,
                                                  ))
                                            .withValues(alpha: 0.22),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.sos_rounded,
                                    color: Colors.white,
                                    size: 38,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _isHoldingDemo ? 'KEEP HOLDING' : 'TRY IT',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _SosDemoResultPanel(
                              key: ValueKey(_demoResult),
                              result: _demoResult,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Glyph(
                            icon: Icons.shield_outlined,
                            color: _SosColors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'If you are unsure, tap and release. Only a continuous hold activates Duress SOS. Releasing early starts the Manual SOS cancel window.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _SosColors.secondaryTextFor(context),
                                    height: 1.45,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

/// Displays the queued sos dispatches page.
class _QueuedSosDispatchesPage extends StatefulWidget {
  /// Creates queued sos dispatches page.
  const _QueuedSosDispatchesPage({
    required this.loadDispatches,
    required this.phoneNumber,
  });

  final Future<List<SosQueuedDispatch>> Function() loadDispatches;
  final String phoneNumber;

  /// Creates the presentation state for this widget.
  @override
  State<_QueuedSosDispatchesPage> createState() =>
      _QueuedSosDispatchesPageState();
}

/// Manages the queued sos dispatches page presentation and lifecycle.
class _QueuedSosDispatchesPageState extends State<_QueuedSosDispatchesPage> {
  late final _QueuedSosDispatchesPageStateViewModel _screenModel;

  /// Returns dispatches.
  Future<List<SosQueuedDispatch>> get _dispatches =>
      _screenModel.stateDispatches;

  /// Updates dispatches.
  set _dispatches(Future<List<SosQueuedDispatch>> value) =>
      _screenModel.stateDispatches = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  StreamSubscription<SosQueueChange>? _queueSubscription;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _QueuedSosDispatchesPageStateViewModel(
      readLoadDispatches: () => widget.loadDispatches,
    )..addListener(_renderScreenModel);

    _dispatches = widget.loadDispatches();
    _queueSubscription = SosAlertRepository.queueChanges.listen((change) {
      if (change.phoneNumber == widget.phoneNumber) _refresh();
    });
  }

  /// Delegates refresh to the ViewModel.
  void _refresh() => _screenModel.commandRefresh();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _queueSubscription?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'Queued SOS dispatches',
                    subtitle: 'Alerts waiting to be sent',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 14),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Glyph(
                            icon: Icons.lock_outline_rounded,
                            color: _SosColors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'View only',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: _SosColors.textFor(context),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'HikerCircle will retry once network signal is available.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: _SosColors.secondaryTextFor(
                                          context,
                                        ),
                                        height: 1.4,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh queue',
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh_rounded),
                            color: _SosColors.green,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<SosQueuedDispatch>>(
                      future: _dispatches,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done &&
                            !snapshot.hasData) {
                          return const HikerCircleLoadingView(
                            message: 'Loading SOS queue…',
                            detail: 'Checking pending emergency messages.',
                            compact: true,
                          );
                        }
                        if (snapshot.hasError) {
                          return _QueuedSosEmptyState(
                            icon: Icons.sync_problem_rounded,
                            title: 'Queue unavailable',
                            subtitle:
                                'Unable to load queued alerts. Please try again.',
                            onRetry: _refresh,
                          );
                        }
                        final dispatches = snapshot.data ?? const [];
                        if (dispatches.isEmpty) {
                          return _QueuedSosEmptyState(
                            icon: Icons.outbox_rounded,
                            title: 'Queue is clear',
                            subtitle:
                                'There are no SOS dispatches waiting for delivery.',
                            onRetry: _refresh,
                          );
                        }
                        return ListView.separated(
                          itemCount: dispatches.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final dispatch = dispatches[index];
                            return _QueuedSosDispatchCard(
                              dispatch: dispatch,
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => _QueuedSosDispatchDetailPage(
                                    dispatch: dispatch,
                                    phoneNumber: widget.phoneNumber,
                                    loadDispatches: widget.loadDispatches,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the queued sos dispatch detail page.
class _QueuedSosDispatchDetailPage extends StatefulWidget {
  /// Creates queued sos dispatch detail page.
  const _QueuedSosDispatchDetailPage({
    required this.dispatch,
    required this.phoneNumber,
    required this.loadDispatches,
  });

  final SosQueuedDispatch dispatch;
  final String phoneNumber;
  final Future<List<SosQueuedDispatch>> Function() loadDispatches;

  /// Creates the presentation state for this widget.
  @override
  State<_QueuedSosDispatchDetailPage> createState() =>
      _QueuedSosDispatchDetailPageState();
}

/// Manages the queued sos dispatch detail page presentation and lifecycle.
class _QueuedSosDispatchDetailPageState
    extends State<_QueuedSosDispatchDetailPage> {
  late final _QueuedSosDispatchDetailPageStateViewModel _screenModel;

  /// Returns dispatch.
  SosQueuedDispatch get dispatch => _screenModel.stateDispatch;

  /// Updates dispatch.
  set dispatch(SosQueuedDispatch value) => _screenModel.stateDispatch = value;

  /// Returns is queued.
  bool get _isQueued => _screenModel.stateIsQueued;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  StreamSubscription<SosQueueChange>? _queueSubscription;

  SosAlert? _completedAlert;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _QueuedSosDispatchDetailPageStateViewModel(
      readLoadDispatches: () => widget.loadDispatches,
    )..addListener(_renderScreenModel);

    dispatch = widget.dispatch;
    _queueSubscription = SosAlertRepository.queueChanges.listen((change) {
      if (change.phoneNumber != widget.phoneNumber) return;
      if (change.alert?.id == dispatch.alertId && !change.queuedForRetry) {
        _completedAlert = change.alert;
      }
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  /// Delegates reload to the ViewModel.
  Future<void> _reload() => _screenModel.commandReload();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _queueSubscription?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final status = !_isQueued
        ? _completedAlert?.status == SosAlertStatus.sent
              ? 'Sent'
              : 'No longer queued'
        : dispatch.sendStatus == 'retry'
        ? 'Waiting to retry'
        : 'Waiting to send';
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'Queued SOS details',
                    subtitle: 'Delivery status',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const _Glyph(
                            icon: Icons.lock_outline_rounded,
                            color: _SosColors.green,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            dispatch.mode.label,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          _StatusPill(
                            label: status,
                            color: _isQueued
                                ? _SosColors.orange
                                : _SosColors.green,
                            surface:
                                (_isQueued
                                        ? _SosColors.orange
                                        : _SosColors.green)
                                    .withValues(alpha: 0.1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Column(
                        children: [
                          _StatusRow(
                            label: 'Triggered',
                            value: _queuedSosTimeLabel(dispatch.triggeredAt),
                          ),
                          const _HorizontalSeparator(),
                          _StatusRow(
                            label: 'Pending contacts',
                            value:
                                '${_isQueued ? dispatch.pendingContactCount : 0}/${dispatch.contactCount}',
                          ),
                          const _HorizontalSeparator(),
                          _StatusRow(
                            label: 'Retry attempts',
                            value: '${dispatch.retryCount}',
                          ),
                          const _HorizontalSeparator(),
                          _StatusRow(
                            label: 'Location',
                            value:
                                dispatch.triggerLocation?.universalMapLink ??
                                'Unavailable',
                          ),
                          if (_isQueued && dispatch.lastError.isNotEmpty) ...[
                            const _HorizontalSeparator(),
                            _StatusRow(
                              label: 'Last delivery result',
                              value: dispatch.lastError,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (dispatch.message.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _InsetGroup(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SOS message',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: _SosColors.textFor(context),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              dispatch.message,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _SosColors.secondaryTextFor(context),
                                    height: 1.45,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _isQueued
                        ? 'This alert will leave the queue once delivery is confirmed.'
                        : 'This alert is no longer waiting for delivery.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Computes queued sos time label.
String _queuedSosTimeLabel(DateTime value) {
  final local = value.toLocal();
  const months = <String>[
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
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${months[local.month - 1]} ${local.year}, '
      '$hour:$minute $period';
}

/// Displays the sos safety tools grid.
class _SosSafetyToolsGrid extends StatelessWidget {
  /// Creates sos safety tools grid.
  const _SosSafetyToolsGrid({
    required this.onOpenFirstAid,
    required this.onOpenGearsRequired,
  });

  final VoidCallback onOpenFirstAid;
  final VoidCallback onOpenGearsRequired;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio:
          1.62 / math.max(1, MediaQuery.textScalerOf(context).scale(1)),
      children: [
        _SosSafetyToolTile(
          icon: Icons.medical_services_rounded,
          title: 'First-Aid Guide',
          subtitle: 'Offline steps',
          onTap: onOpenFirstAid,
        ),
        _SosSafetyToolTile(
          icon: Icons.backpack_outlined,
          title: 'Gears required',
          subtitle: 'What to bring & why',
          onTap: onOpenGearsRequired,
        ),
      ],
    );
  }
}

/// Displays the whats app message detail page.
class _WhatsAppMessageDetailPage extends StatefulWidget {
  /// Creates whats app message detail page.
  const _WhatsAppMessageDetailPage({
    required this.session,
    required this.initialNotes,
    required this.previewMode,
    required this.previewTriggeredAt,
    required this.previewLocation,
  });

  final AppSession session;
  final Map<SosAlertMode, String> initialNotes;
  final SosAlertMode previewMode;
  final DateTime previewTriggeredAt;
  final SosTriggerLocation? previewLocation;

  /// Creates the presentation state for this widget.
  @override
  State<_WhatsAppMessageDetailPage> createState() =>
      _WhatsAppMessageDetailPageState();
}

/// Manages the whats app message detail page presentation and lifecycle.
class _WhatsAppMessageDetailPageState
    extends State<_WhatsAppMessageDetailPage> {
  late final _WhatsAppMessageDetailPageStateViewModel _screenModel;

  /// Returns notes.
  Map<SosAlertMode, String> get _notes => _screenModel.stateNotes;

  /// Updates notes.
  set _notes(Map<SosAlertMode, String> value) =>
      _screenModel.stateNotes = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final TextEditingController _noteController;
  late SosAlertMode _selectedMode;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _WhatsAppMessageDetailPageStateViewModel()
      ..addListener(_renderScreenModel);

    _notes = {..._SosPageState._defaultWhatsAppNotes(), ...widget.initialNotes};
    _selectedMode = _editableModeFor(widget.previewMode);
    _noteController = TextEditingController(text: _noteFor(_selectedMode));
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _noteController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final preview = SosAlertMessageComposer.compose(
      mode: _selectedMode,
      phoneNumber: widget.session.phoneNumber,
      triggeredAt: widget.previewTriggeredAt,
      triggerLocation: widget.previewLocation,
      customNote: _noteController.text,
    );

    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'Emergency WhatsApp',
                    subtitle: 'Make every emergency message clear and useful',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Glyph(
                            icon: Icons.chat_bubble_rounded,
                            color: _SosColors.green,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Message instructions',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoSlidingSegmentedControl<SosAlertMode>(
                            groupValue: _selectedMode,
                            children: const {
                              SosAlertMode.manual: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Manual'),
                              ),
                              SosAlertMode.duress: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Duress'),
                              ),
                              SosAlertMode.medical: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Medical'),
                              ),
                            },
                            onValueChanged: (mode) {
                              if (mode == null) {
                                return;
                              }
                              _saveCurrentNote();
                              setState(() {
                                _selectedMode = mode;
                                _noteController.text = _noteFor(mode);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _noteController,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 240,
                            decoration: const InputDecoration(
                              hintText:
                                  'Tell contacts what to do when they receive your SOS.',
                              alignLabelWithHint: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _noteController.text =
                                          _SosPageState._defaultWhatsAppNotes()[_selectedMode]!;
                                    });
                                  },
                                  child: const Text('Reset Default'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    _saveCurrentNote();
                                    Navigator.of(context).pop(
                                      _WhatsAppNoteUpdate(
                                        mode: _selectedMode,
                                        note:
                                            _notes[_selectedMode]?.trim() ?? '',
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('Use Message'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'WhatsApp preview',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _SosColors.greenSoftFor(context),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomLeft: Radius.circular(18),
                                bottomRight: Radius.circular(5),
                              ),
                            ),
                            child: SelectableText(
                              preview,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _SosColors.textFor(context),
                                    height: 1.4,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Delegates editable mode for to the ViewModel.
  SosAlertMode _editableModeFor(SosAlertMode mode) =>
      _screenModel.commandEditableModeFor(mode);

  /// Delegates note for to the ViewModel.
  String _noteFor(SosAlertMode mode) => _screenModel.commandNoteFor(mode);

  /// Saves current note.
  void _saveCurrentNote() {
    _notes = {..._notes, _selectedMode: _noteController.text.trim()};
  }
}

/// Displays the sos test settings page.
class _SosTestSettingsPage extends StatefulWidget {
  /// Creates sos test settings page.
  const _SosTestSettingsPage({
    required this.phoneNumber,
    required this.onSendWhatsAppTest,
  });

  final String phoneNumber;
  final Future<List<SosContactDispatch>> Function() onSendWhatsAppTest;

  /// Creates the presentation state for this widget.
  @override
  State<_SosTestSettingsPage> createState() => _SosTestSettingsPageState();
}

/// Manages the sos test settings page presentation and lifecycle.
class _SosTestSettingsPageState extends State<_SosTestSettingsPage> {
  late final _SosTestSettingsPageStateViewModel _screenModel;

  /// Returns device alert service.
  SosDeviceAlertService get _deviceAlertService =>
      _screenModel.stateDeviceAlertService;

  /// Returns ble service.
  HikerBleService get _bleService => _screenModel.stateBleService;

  /// Returns test stop timer.
  Timer? get _testStopTimer => _screenModel.stateTestStopTimer;

  /// Returns is flashlight active.
  bool get _isFlashlightActive => _screenModel.stateIsFlashlightActive;

  /// Updates is flashlight active.
  set _isFlashlightActive(bool value) =>
      _screenModel.stateIsFlashlightActive = value;

  /// Returns is emergency siren active.
  bool get _isEmergencySirenActive => _screenModel.stateIsEmergencySirenActive;

  /// Updates is emergency siren active.
  set _isEmergencySirenActive(bool value) =>
      _screenModel.stateIsEmergencySirenActive = value;

  /// Returns is medical siren active.
  bool get _isMedicalSirenActive => _screenModel.stateIsMedicalSirenActive;

  /// Updates is medical siren active.
  set _isMedicalSirenActive(bool value) =>
      _screenModel.stateIsMedicalSirenActive = value;

  /// Returns legacy unpaired button enabled.
  bool get _legacyUnpairedButtonEnabled =>
      _screenModel.stateLegacyUnpairedButtonEnabled;

  /// Returns is gyroscope test active.
  bool get _isGyroscopeTestActive => _screenModel.stateIsGyroscopeTestActive;

  /// Returns gyroscope test progress.
  double get _gyroscopeTestProgress => _screenModel.stateGyroscopeTestProgress;

  /// Returns gyroscope test status.
  String get _gyroscopeTestStatus => _screenModel.stateGyroscopeTestStatus;

  /// Updates gyroscope test status.
  set _gyroscopeTestStatus(String value) =>
      _screenModel.stateGyroscopeTestStatus = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const Duration _bleSosTestDuration = Duration(seconds: 5);

  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  bool _isBroadcastingBleSosTest = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SosTestSettingsPageStateViewModel(
      readOnSendWhatsAppTest: () => widget.onSendWhatsAppTest,
      effectShowTestResult: _showTestResult,
    )..addListener(_renderScreenModel);

    unawaited(_loadLegacyButtonSetting());
    _gyroscopeSubscription =
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 200),
        ).listen(
          (event) {
            if (!mounted) {
              return;
            }
            _handleGyroscopeTestEvent(event);
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _gyroscopeTestStatus = 'Gyroscope unavailable.';
              });
            }
          },
        );
  }

  /// Delegates load legacy button setting to the ViewModel.
  Future<void> _loadLegacyButtonSetting() =>
      _screenModel.commandLoadLegacyButtonSetting();

  /// Delegates toggle legacy button setting to the ViewModel.
  Future<void> _toggleLegacyButtonSetting() =>
      _screenModel.commandToggleLegacyButtonSetting();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _testStopTimer?.cancel();
    unawaited(_gyroscopeSubscription?.cancel());
    unawaited(_deviceAlertService.stopFlashlightPattern());
    unawaited(_deviceAlertService.stopManualSosPattern());

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'Test Settings',
                    subtitle: 'Run device, message, and sensor checks',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Column(
                      children: [
                        _SosTestRow(
                          icon: Icons.chat_bubble_rounded,
                          title: 'WhatsApp test message',
                          subtitle:
                              'Send a non-emergency cloud messaging test to your emergency contacts.',
                          onTap: () => unawaited(_sendWhatsAppTestMessage()),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.bluetooth_searching_rounded,
                          title: 'Physical SOS button broadcast',
                          subtitle: _isBroadcastingBleSosTest
                              ? 'Broadcasting a BLE help beacon for nearby phones.'
                              : 'Pretend this phone is the ESP32 button and broadcast your GPS help beacon.',
                          onTap: _isBroadcastingBleSosTest
                              ? null
                              : () => unawaited(_broadcastBleSosTest()),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.settings_remote_rounded,
                          title: 'Paired SOS button',
                          subtitle:
                              'Add a button, wait for physical confirmation, or manage paired buttons.',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PairedSosButtonPage(
                                accountId: widget.phoneNumber,
                              ),
                            ),
                          ),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.settings_remote_rounded,
                          title: 'Legacy unpaired button (migration)',
                          subtitle: _legacyUnpairedButtonEnabled
                              ? 'Enabled: v1 buttons can trigger this phone. Turn off after upgrading to a paired v2 button.'
                              : 'Disabled by default. Planned paired v2 buttons use authenticated type-4 packets.',
                          onTap: () => unawaited(_toggleLegacyButtonSetting()),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.flash_on_rounded,
                          title: 'SOS flashlight pattern',
                          subtitle: _isFlashlightActive
                              ? 'Tap to stop the active SOS flash pattern.'
                              : 'Short-short-short, long-long-long, short-short-short.',
                          onTap: () => unawaited(_toggleFlashlightTest()),
                        ),
                        if (_isFlashlightActive) ...[
                          const SizedBox(height: 4),
                          _FlashPatternPreview(active: true),
                        ],
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.sos_rounded,
                          title: 'Emergency siren test',
                          subtitle: _isEmergencySirenActive
                              ? 'Tap to stop the emergency siren.'
                              : 'Play the emergency siren only. No flashlight.',
                          onTap: () =>
                              unawaited(_toggleSirenTest(SosAlertMode.manual)),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.health_and_safety_rounded,
                          title: 'Medical siren test',
                          subtitle: _isMedicalSirenActive
                              ? 'Tap to stop the medical siren.'
                              : 'Play the medical siren only. No flashlight.',
                          onTap: () =>
                              unawaited(_toggleSirenTest(SosAlertMode.medical)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FallDetectionTestCard(),
                          const _HorizontalSeparator(),
                          _SensorTestCard(
                            icon: Icons.threesixty_rounded,
                            title: 'Gyroscope rotation test',
                            instruction:
                                'Rotate your wrist in a figure-eight or left-right tilt.',
                            progress: _gyroscopeTestProgress,
                            status: _gyroscopeTestStatus,
                            isActive: _isGyroscopeTestActive,
                            onStart: _startGyroscopeTest,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Delegates send whats app test message to the ViewModel.
  Future<void> _sendWhatsAppTestMessage() =>
      _screenModel.commandSendWhatsAppTestMessage();

  /// Computes broadcast ble sos test.
  Future<void> _broadcastBleSosTest() async {
    if (_isBroadcastingBleSosTest) {
      return;
    }
    setState(() {
      _isBroadcastingBleSosTest = true;
    });

    try {
      final snapshotService = LocationSnapshotService.instance;
      final location =
          await snapshotService.refresh() ?? snapshotService.latestLocation;
      if (location == null) {
        _showTestResult('Location unavailable. Turn on GPS and try again.');
        return;
      }
      await _bleService.broadcastPhysicalSosTest(
        phoneNumber: widget.phoneNumber,
        location: location,
        duration: _bleSosTestDuration,
      );
      _showTestResult(
        'BLE test broadcast for 5 seconds. Nearby HikerCircle phones can show a test preview.',
      );
      await Future<void>.delayed(_bleSosTestDuration);
    } on HikerBleException catch (error) {
      _showTestResult(error.message);
    } catch (_) {
      _showTestResult('Unable to broadcast the BLE SOS test right now.');
    } finally {
      if (mounted) {
        setState(() {
          _isBroadcastingBleSosTest = false;
        });
      }
    }
  }

  /// Toggles flashlight test.
  Future<void> _toggleFlashlightTest() async {
    try {
      if (_isFlashlightActive) {
        await _deviceAlertService.stopFlashlightPattern();
        if (mounted) {
          setState(() {
            _isFlashlightActive = false;
          });
        }
        return;
      }

      await _stopAllTests();
      await _deviceAlertService.startFlashlightPattern();
      if (!mounted) {
        return;
      }
      setState(() {
        _isFlashlightActive = true;
      });
      _scheduleAutoStop();
      _showTestResult('SOS flashlight pattern started.');
    } catch (_) {
      _showTestResult('Unable to start the flashlight test on this device.');
    }
  }

  /// Toggles siren test.
  Future<void> _toggleSirenTest(SosAlertMode mode) async {
    final isActive = mode == SosAlertMode.medical
        ? _isMedicalSirenActive
        : _isEmergencySirenActive;
    try {
      if (isActive) {
        await _stopAllTests();
        return;
      }

      await _stopAllTests();
      await _deviceAlertService.stopFlashlightPattern();
      await _deviceAlertService.startSirenOnlyForMode(mode);
      if (!mounted) {
        return;
      }
      setState(() {
        _isEmergencySirenActive = mode != SosAlertMode.medical;
        _isMedicalSirenActive = mode == SosAlertMode.medical;
      });
      _scheduleAutoStop();
      _showTestResult(
        mode == SosAlertMode.medical
            ? 'Medical siren test started.'
            : 'Emergency siren test started.',
      );
    } catch (_) {
      _showTestResult('Unable to start the siren test on this device.');
    }
  }

  /// Delegates stop all tests to the ViewModel.
  Future<void> _stopAllTests() => _screenModel.commandStopAllTests();

  /// Delegates schedule auto stop to the ViewModel.
  void _scheduleAutoStop() => _screenModel.commandScheduleAutoStop();

  /// Shows test result.
  void _showTestResult(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// Delegates start gyroscope test to the ViewModel.
  void _startGyroscopeTest() => _screenModel.commandStartGyroscopeTest();

  /// Delegates handle gyroscope test event to the ViewModel.
  void _handleGyroscopeTestEvent(GyroscopeEvent event) =>
      _screenModel.commandHandleGyroscopeTestEvent(event);
}

/// Displays the flash pattern preview.
class _FlashPatternPreview extends StatefulWidget {
  /// Creates flash pattern preview.
  const _FlashPatternPreview({required this.active});

  final bool active;

  /// Creates the presentation state for this widget.
  @override
  State<_FlashPatternPreview> createState() => _FlashPatternPreviewState();
}

/// Manages the flash pattern preview presentation and lifecycle.
class _FlashPatternPreviewState extends State<_FlashPatternPreview> {
  late final _FlashPatternPreviewStateViewModel _screenModel;

  /// Returns timer.
  Timer? get _timer => _screenModel.stateTimer;

  /// Returns is on.
  bool get _isOn => _screenModel.stateIsOn;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _FlashPatternPreviewStateViewModel(
      readActive: () => widget.active,
    )..addListener(_renderScreenModel);

    _syncTimer();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _FlashPatternPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncTimer();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _timer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates sync timer to the ViewModel.
  void _syncTimer() => _screenModel.commandSyncTimer();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isOn
            ? _SosColors.destructiveSoftFor(context)
            : _SosColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            color: _isOn
                ? _SosColors.destructiveFor(context)
                : _SosColors.green,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.active
                  ? 'SOS flash meaning: 3 short, 3 long, 3 short. Auto-stops after 8 seconds.'
                  : 'Flashlight preview is idle.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.textFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon, required this.color});

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

/// Displays the tap surface.
class _TapSurface extends StatelessWidget {
  /// Creates tap surface.
  const _TapSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: child),
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
          color: _SosColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _SosColors.separatorFor(context),
    );
  }
}

/// Computes sos log string.
String _sosLogString(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

/// Computes sos log int.
int _sosLogInt(Object? value) {
  return value is num && value.isFinite ? value.toInt() : 0;
}

/// Computes sos log date label.
String _sosLogDateLabel(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    return 'Time unavailable';
  }
  final local = parsed.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

/// Computes sos log location.
SosTriggerLocation? _sosLogLocation(Object? value) {
  if (value is! Map || value.isEmpty) {
    return null;
  }
  final latitude = value['latitude'];
  final longitude = value['longitude'];
  final accuracy = value['accuracyMeters'];
  if (latitude is! num || longitude is! num) {
    return null;
  }
  final location = SosTriggerLocation(
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
    accuracyMeters: accuracy is num ? accuracy.toDouble() : null,
    capturedAt: DateTime.now().toUtc(),
  );
  return location.hasValidPosition ? location : null;
}

/// Computes friendly sos type.
String _friendlySosType(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'manual' => 'Emergency button',
    'medical' => 'Medical assistance',
    'duress' => 'Discreet emergency',
    'fall' || 'fall_stillness' => 'Fall detected',
    'nearby' || 'nearby_ble' => 'Nearby hiker emergency',
    _ => 'SOS emergency',
  };
}

/// Computes friendly sos status.
String _friendlySosStatus(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'sent' => 'Contacts confirmed',
    'partial' => 'Contacts confirmed',
    'unconfirmed' => 'Unconfirmed',
    'failed' => 'Delivery needs attention',
    'queued' || 'retry' => 'Waiting for connection',
    'no_contacts' => 'No emergency contacts',
    'active' => 'Help requested',
    'resolved' => 'Resolved',
    _ => 'Status updating',
  };
}

/// Represents sos colors.
abstract final class _SosColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color orange = Color(0xFFF59E0B);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);
  static const Color destructiveSoft = Color(0xFFFFEDEC);
  static const Color duress = Color(0xFF8E4C5A);

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

  /// Computes destructive soft for.
  static Color destructiveSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF3C1B1B) : destructiveSoft;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes chevron for.
  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  /// Computes destructive for.
  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
