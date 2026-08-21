import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../home/View/first_aid_guide_page.dart';
import '../../home/View/gear_checklist_page.dart';
import '../../me/View/location_sharing_page.dart';
import '../../core/services/hiker_ble_service.dart';
import '../../core/services/network_reachability_service.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/location_snapshot_service.dart';
import '../Data/nearby_sos_event_repository.dart';
import '../Data/sos_alert_repository.dart';
import '../Data/sos_device_alert_service.dart';
import '../Model/sos_models.dart';
import '../Model/nearby_sos_event.dart';
import '../ModelView/sos_view_model.dart';
import 'emergency_contacts_page.dart';
import 'ios_sos_volume_guard.dart';
import 'nearby_sos_map_page.dart';
import 'paired_sos_button_page.dart';

class _QueuedSosRequest {
  const _QueuedSosRequest({
    required this.mode,
    required this.triggeredAt,
    required this.triggerSource,
  });

  final SosAlertMode mode;
  final DateTime triggeredAt;
  final SosAlertTriggerSource triggerSource;
}

class SosPage extends StatefulWidget {
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
    this.nearbySosRevision = 0,
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
  final int nearbySosRevision;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  final HikerBleService _bleService = const HikerBleService();
  final Queue<_QueuedSosRequest> _queuedSosRequests = Queue();
  late final NearbySosEventRepository _nearbySosEventRepository;
  Future<void>? _sosRequestDrain;
  late final SosViewModel viewModel;
  int _handledManualSosRequestId = 0;
  int _handledImmediateSosRequestId = 0;
  String _handledSosAcknowledgementKey = '';
  bool _isManualSosPatternActive = false;
  Map<SosAlertMode, String> _customWhatsAppNotes = _defaultWhatsAppNotes();
  List<Map<String, dynamic>> _adminSosSystemLogs = const [];
  bool _isLoadingAdminSosSystemLogs = false;
  String? _adminSosSystemLogsError;
  List<NearbySosEvent> _nearbySosEvents = const [];
  SosTriggerLocation? _nearbyEventsPhoneLocation;
  bool _isLoadingNearbySosEvents = false;
  bool _nearbySosReloadPending = false;
  Timer? _nearbySosRefreshTimer;
  StreamSubscription<NetworkReachabilitySnapshot>? _networkSubscription;
  NetworkReachabilitySnapshot _networkSnapshot =
      const NetworkReachabilitySnapshot(
        state: NetworkReachabilityState.checking,
      );

  @override
  void initState() {
    super.initState();
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

  Future<void> _activateSosAccount() async {
    try {
      await _bleService.setActiveSosAccount(widget.session.phoneNumber);
    } on HikerBleException catch (error) {
      debugPrint('Unable to scope paired SOS buttons to this account: $error');
    }
  }

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

  @override
  void dispose() {
    if (_isManualSosPatternActive) {
      unawaited(_deviceAlertService.stopManualSosPattern());
    }
    _networkSubscription?.cancel();
    _nearbySosRefreshTimer?.cancel();
    unawaited(NetworkReachabilityService.instance.stop());
    viewModel.removeListener(_refresh);
    viewModel.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final acknowledgement = viewModel.latestSosAcknowledgement;
    final acknowledgementKey = acknowledgement == null
        ? ''
        : '${acknowledgement.alert.id}:${acknowledgement.alert.status.firestoreValue}:${acknowledgement.queuedForRetry}:${acknowledgement.alert.sentCount}:${acknowledgement.alert.failedCount}';
    final shouldReportAcknowledgementFailure =
        acknowledgement != null &&
        acknowledgementKey != _handledSosAcknowledgementKey &&
        (acknowledgement.queuedForRetry ||
            acknowledgement.alert.status == SosAlertStatus.failed ||
            acknowledgement.alert.status == SosAlertStatus.partial ||
            acknowledgement.alert.status == SosAlertStatus.queued);
    if (acknowledgementKey.isNotEmpty) {
      _handledSosAcknowledgementKey = acknowledgementKey;
    }
    setState(() {});
    if (shouldReportAcknowledgementFailure) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_messageForResult(acknowledgement)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: _SosColors.destructiveFor(context),
            ),
          );
      });
    }
  }

  Future<void> _loadNearbySosEvents() async {
    if (_isLoadingNearbySosEvents) {
      _nearbySosReloadPending = true;
      return;
    }
    _isLoadingNearbySosEvents = true;
    try {
      final events = await _nearbySosEventRepository.load(
        ownerPhoneNumber: widget.session.phoneNumber,
      );
      if (!mounted) return;
      setState(() {
        _nearbySosEvents = events;
        _nearbyEventsPhoneLocation =
            LocationSnapshotService.instance.latestLocation;
      });
      final phoneLocation = await _currentPhoneLocation();
      if (!mounted) return;
      setState(() {
        _nearbyEventsPhoneLocation = phoneLocation;
      });
    } catch (error) {
      debugPrint('Unable to load nearby SOS events: $error');
    } finally {
      _isLoadingNearbySosEvents = false;
      if (_nearbySosReloadPending && mounted) {
        _nearbySosReloadPending = false;
        unawaited(_loadNearbySosEvents());
      }
    }
  }

  Future<SosTriggerLocation?> _currentPhoneLocation() async {
    try {
      final snapshots = LocationSnapshotService.instance;
      return await snapshots.refresh() ?? snapshots.latestLocation;
    } catch (_) {
      return LocationSnapshotService.instance.latestLocation;
    }
  }

  List<NearbySosEvent> get _activeNearbySosEvents {
    final now = DateTime.now().toUtc();
    return _nearbySosEvents
        .where(
          (event) => event.isActiveAt(
            now: now,
            phoneLocation: _nearbyEventsPhoneLocation,
          ),
        )
        .toList(growable: false);
  }

  List<NearbySosEvent> get _archivedNearbySosEvents {
    final now = DateTime.now().toUtc();
    return _nearbySosEvents
        .where(
          (event) => !event.isActiveAt(
            now: now,
            phoneLocation: _nearbyEventsPhoneLocation,
          ),
        )
        .toList(growable: false);
  }

  static Map<SosAlertMode, String> _defaultWhatsAppNotes() {
    return const {
      SosAlertMode.manual: SosAlertMessageComposer.defaultCustomNote,
      SosAlertMode.duress:
          'I may be under pressure and cannot speak safely. Please watch my live location, avoid calling if it may increase risk, and contact local emergency services if I stop responding.',
      SosAlertMode.medical:
          'I need medical help during my hike. Please call me, use the map link, and share this alert with medical responders if I do not answer.',
    };
  }

  Future<void> _loadCustomWhatsAppNotes() async {
    await viewModel.loadCustomWhatsAppNotes();
    if (!mounted) {
      return;
    }
    setState(() {
      _customWhatsAppNotes = {
        ..._defaultWhatsAppNotes(),
        ...viewModel.customWhatsAppNotes,
      };
    });
  }

  Future<void> _loadEmergencyContactsAndFlushQueue() async {
    await viewModel.loadEmergencyContacts();
    final network = await NetworkReachabilityService.instance.refresh();
    if (mounted) {
      setState(() {
        _networkSnapshot = network;
      });
    }
    if (network.isOnline) {
      await viewModel.flushQueuedAlerts();
    }
  }

  void _handleNetworkReachabilityChanged(NetworkReachabilitySnapshot snapshot) {
    final wasOnline = _networkSnapshot.isOnline;
    if (!mounted) {
      _networkSnapshot = snapshot;
      return;
    }
    setState(() {
      _networkSnapshot = snapshot;
    });
    if (!wasOnline && snapshot.isOnline) {
      unawaited(_flushQueueAfterNetworkRestore());
    }
  }

  Future<void> _flushQueueAfterNetworkRestore() async {
    if (viewModel.queuedAlertCount == 0) {
      await viewModel.loadQueuedAlertCount();
    }
    if (viewModel.queuedAlertCount > 0) {
      await viewModel.flushQueuedAlerts();
    }
  }

  String _customWhatsAppNoteFor(SosAlertMode mode) {
    return _customWhatsAppNotes[mode] ??
        SosAlertMessageComposer.defaultCustomNoteFor(mode);
  }

  Future<void> _loadAdminSosSystemLogs() async {
    if (_isLoadingAdminSosSystemLogs) {
      return;
    }
    setState(() {
      _isLoadingAdminSosSystemLogs = true;
      _adminSosSystemLogsError = null;
    });

    try {
      final logs = await HikerCircleFirebaseRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ).loadAdminSosAlerts(session: widget.session);
      if (!mounted) {
        return;
      }
      setState(() {
        _adminSosSystemLogs = logs;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        setState(() {
          _adminSosSystemLogsError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _adminSosSystemLogsError = 'Unable to load SOS events.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdminSosSystemLogs = false;
        });
      }
    }
  }

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

  Future<void> _handleManualSos() async {
    unawaited(HapticFeedback.heavyImpact());
    final shouldSend = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _ManualSosCountdownDialog();
      },
    );

    if (shouldSend != true || !mounted) {
      return;
    }

    // A user-initiated alert may offer an alarm-volume check, but that dialog
    // stays outside the dispatch queue so a hardware SOS can still be sent
    // while the dialog is open.
    final volumeReady = await ensureIosSosOutputVolumeReady(
      context: context,
      deviceAlertService: _deviceAlertService,
      message:
          '${SosAlertMode.manual.label} uses iPhone media volume for the local alarm. Turn it up before continuing.',
    );
    if (!volumeReady || !mounted) return;
    await _enqueueAlert(SosAlertMode.manual);
  }

  Future<void> _handleImmediateSos(
    SosAlertMode mode,
    SosAlertTriggerSource triggerSource,
  ) async {
    unawaited(
      mode == SosAlertMode.duress
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.heavyImpact(),
    );
    await _enqueueAlert(mode, triggerSource: triggerSource);
  }

  Future<void> _handleDuressSos() async {
    unawaited(HapticFeedback.mediumImpact());
    await _enqueueAlert(SosAlertMode.duress);
  }

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

  void _openPairedSosButton() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            PairedSosButtonPage(accountId: widget.session.phoneNumber),
      ),
    );
  }

  void _openSosGestureGuide() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const _SosGestureGuidePage()),
    );
  }

  void _openQueuedDispatches() {
    if (viewModel.queuedAlertCount <= 0) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _QueuedSosDispatchesPage(
          loadDispatches: viewModel.loadQueuedDispatches,
        ),
      ),
    );
  }

  Future<void> _openFirstAidGuide() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const FirstAidGuidePage(),
      ),
    );

    if (result == 'sos' && mounted) {
      unawaited(_handleManualSos());
    }
  }

  void _openGearChecklist() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const GearChecklistPage()),
    );
  }

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

  Future<void> _enqueueAlert(
    SosAlertMode mode, {
    SosAlertTriggerSource? triggerSource,
  }) async {
    _queuedSosRequests.add(
      _QueuedSosRequest(
        mode: mode,
        triggeredAt: DateTime.now().toUtc(),
        triggerSource: triggerSource ?? SosAlertTriggerSource.mobilePhone,
      ),
    );

    // Keep checking after an existing worker completes. An alert can arrive in
    // the small interval between that worker emptying the queue and clearing
    // its Future, and it must start another worker instead of being stranded.
    while (mounted && _queuedSosRequests.isNotEmpty) {
      final activeDrain = _sosRequestDrain;
      if (activeDrain != null) {
        await activeDrain;
        continue;
      }

      final drain = _drainSosRequests();
      _sosRequestDrain = drain;
      try {
        await drain;
      } finally {
        if (identical(_sosRequestDrain, drain)) {
          _sosRequestDrain = null;
        }
      }
    }
  }

  Future<void> _drainSosRequests() async {
    while (mounted && _queuedSosRequests.isNotEmpty) {
      final request = _queuedSosRequests.removeFirst();
      await _triggerAlert(request);
    }
    if (!mounted) {
      _queuedSosRequests.clear();
    }
  }

  Future<void> _triggerAlert(_QueuedSosRequest request) async {
    final mode = request.mode;
    if (mode.usesLoudEmergencyPattern) {
      unawaited(_startManualSosPattern(mode));
    }

    final triggerLocation = await _captureTriggerLocation();
    final result = await viewModel.triggerAlert(
      mode: mode,
      triggeredAt: request.triggeredAt,
      triggerLocation: triggerLocation,
      customMessageNote: _customWhatsAppNoteFor(mode),
      triggerSource: request.triggerSource,
    );
    if (!mounted) {
      return;
    }

    final message = result == null
        ? viewModel.sosAlertErrorMessage ?? 'SOS alert was not sent.'
        : _messageForResult(result);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result == null || result.alert.failedCount > 0
              ? _SosColors.destructiveFor(context)
              : _SosColors.green,
        ),
      );
  }

  Future<SosTriggerLocation?> _captureTriggerLocation() async {
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

  Future<void> _startManualSosPattern(SosAlertMode mode) async {
    if (mounted) {
      setState(() {
        _isManualSosPatternActive = true;
      });
    }
    try {
      await _deviceAlertService.startSosPatternForMode(mode);
      if (!mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isManualSosPatternActive = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to start phone alarm or flashlight.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _stopManualSosPattern() async {
    try {
      await _deviceAlertService.stopManualSosPattern();
    } finally {
      if (mounted) {
        setState(() {
          _isManualSosPatternActive = false;
        });
      }
    }
  }

  String _messageForResult(SosAlertResult result) {
    final alert = result.alert;
    if (alert.status == SosAlertStatus.noContacts) {
      return result.queuedForRetry
          ? '${alert.mode.label} queued until emergency contacts are available.'
          : '${alert.mode.label} logged, but no emergency contacts are saved.';
    }
    if (alert.status == SosAlertStatus.sent) {
      return result.queuedForRetry
          ? '${alert.mode.label} sent to ${alert.sentCount} contacts; cloud sync is queued.'
          : '${alert.mode.label} sent to ${alert.sentCount} contacts.';
    }
    if (alert.status == SosAlertStatus.partial) {
      return '${alert.mode.label} sent to ${alert.sentCount} contacts; ${alert.failedCount} queued for retry.';
    }
    if (alert.status == SosAlertStatus.queued) {
      return '${alert.mode.label} was saved offline and queued for retry.';
    }
    return '${alert.mode.label} could not be sent to your contacts.';
  }

  Map<String, dynamic> _eventLogForAlert(SosAlert alert) {
    return <String, dynamic>{
      ...alert.toFirestore(),
      'alertId': alert.id,
      'phoneNumber': alert.triggeredByPhoneNumber,
    };
  }

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
                    session: widget.session,
                    emergencyContacts: viewModel.emergencyContacts,
                    emergencyContactsRepository:
                        viewModel.emergencyContactsRepository,
                    onEmergencyContactsChanged:
                        viewModel.replaceEmergencyContacts,
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
                        _networkSnapshot.isOnline,
                    isCheckingNetwork:
                        _networkSnapshot.state ==
                        NetworkReachabilityState.checking,
                    errorMessage:
                        widget.firebaseBootstrapResult.errorMessage ??
                        _networkSnapshot.message,
                  ),
                  const SizedBox(height: 14),
                  _MetricsGroup(
                    metrics: viewModel.metrics,
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
                  const _SectionTitle(label: 'Safety Tools'),
                  const SizedBox(height: 8),
                  _SosSafetyToolsGrid(
                    onOpenFirstAid: () => unawaited(_openFirstAidGuide()),
                    onOpenGearChecklist: () => _openGearChecklist(),
                  ),
                  const SizedBox(height: 22),
                  if (widget.session.isAdmin)
                    _AdminSosSystemLogsPanel(
                      logs: _adminSosSystemLogs,
                      nearbyEvents: archivedNearbyEvents,
                      phoneLocation: _nearbyEventsPhoneLocation,
                      isLoading: _isLoadingAdminSosSystemLogs,
                      errorMessage: _adminSosSystemLogsError,
                      onNearbyEventTap: _openNearbySosEvent,
                      onRefresh: () {
                        unawaited(_loadAdminSosSystemLogs());
                        unawaited(_loadNearbySosEvents());
                      },
                    )
                  else ...[
                    _SosTriggerLogPanel(
                      isNetworkAvailable:
                          widget.firebaseBootstrapResult.isAvailable &&
                          _networkSnapshot.isOnline,
                      session: widget.session,
                      latestResult: viewModel.latestSosAlertResult,
                      customWhatsAppNotes: _customWhatsAppNotes,
                      cloudAlertLogs: viewModel.cloudAlertLogs,
                      onCustomWhatsAppNoteChanged: (mode, note) {
                        setState(() {
                          _customWhatsAppNotes = {
                            ..._customWhatsAppNotes,
                            mode: note,
                          };
                        });
                        unawaited(
                          viewModel
                              .saveCustomWhatsAppNote(mode: mode, note: note)
                              .catchError((_) {}),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _AdminSosSystemLogsPanel(
                      logs: userEventLogs,
                      nearbyEvents: archivedNearbyEvents,
                      phoneLocation: _nearbyEventsPhoneLocation,
                      isLoading: false,
                      errorMessage: null,
                      onNearbyEventTap: _openNearbySosEvent,
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
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.emergencyContacts,
    required this.emergencyContactsRepository,
    required this.onEmergencyContactsChanged,
    required this.onOpenTestSettings,
    required this.onOpenPairedButton,
  });

  final AppSession session;
  final List<EmergencyContact> emergencyContacts;
  final EmergencyContactsRepository emergencyContactsRepository;
  final ValueChanged<List<EmergencyContact>> onEmergencyContactsChanged;
  final VoidCallback onOpenTestSettings;
  final VoidCallback onOpenPairedButton;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _SosColors.textFor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Emergency controls and safety checks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            tooltip: 'Emergency contacts',
            icon: Icons.contacts_rounded,
            onPressed: () => unawaited(_openEmergencyContacts(context)),
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Paired SOS button',
            icon: Icons.settings_remote_rounded,
            onPressed: onOpenPairedButton,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Test settings',
            icon: Icons.science_rounded,
            onPressed: onOpenTestSettings,
          ),
        ],
      ),
    );
  }

  Future<void> _openEmergencyContacts(BuildContext context) async {
    final contacts = await Navigator.of(context).push<List<EmergencyContact>>(
      MaterialPageRoute<List<EmergencyContact>>(
        builder: (context) {
          return EmergencyContactsPage(
            session: session,
            initialContacts: emergencyContacts,
            repository: emergencyContactsRepository,
          );
        },
      ),
    );

    if (contacts == null || !context.mounted) {
      return;
    }

    onEmergencyContactsChanged(contacts);
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        onPressed: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _SosColors.surfaceFor(context),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _SosColors.green, size: 19),
        ),
      ),
    );
  }
}

class _ManualSosCountdownDialog extends StatefulWidget {
  const _ManualSosCountdownDialog();

  @override
  State<_ManualSosCountdownDialog> createState() =>
      _ManualSosCountdownDialogState();
}

class _ManualSosCountdownDialogState extends State<_ManualSosCountdownDialog> {
  static const int _totalSeconds = 10;

  Timer? _timer;
  int _secondsRemaining = _totalSeconds;
  bool _didComplete = false;

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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _completeCountdown() {
    if (_didComplete || !mounted) {
      return;
    }

    _didComplete = true;
    _timer?.cancel();
    Navigator.of(context).pop(true);
  }

  void _cancel() {
    if (_didComplete) {
      return;
    }

    _didComplete = true;
    _timer?.cancel();
    Navigator.of(context).pop(false);
  }

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

class _NetworkSosStatusCard extends StatelessWidget {
  const _NetworkSosStatusCard({
    required this.isNetworkAvailable,
    required this.isCheckingNetwork,
    required this.errorMessage,
  });

  final bool isNetworkAvailable;
  final bool isCheckingNetwork;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final color = isCheckingNetwork
        ? _SosColors.orange
        : isNetworkAvailable
        ? _SosColors.green
        : _SosColors.orange;
    final title = isCheckingNetwork
        ? 'Checking network SOS'
        : isNetworkAvailable
        ? 'Network SOS available'
        : 'Cloud SOS unavailable';
    final subtitle = isCheckingNetwork
        ? 'Checking internet reachability before cloud SOS delivery.'
        : isNetworkAvailable
        ? 'Alerts can use cloud logging and WhatsApp delivery when sent.'
        : 'No backend connection right now. WhatsApp dispatch and Firebase cloud logging may fail until connection is restored.';

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: isCheckingNetwork
                  ? Icons.sync_rounded
                  : isNetworkAvailable
                  ? Icons.cloud_done_rounded
                  : Icons.signal_wifi_connected_no_internet_4_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _SosColors.textFor(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      _StatusPill(
                        label: isCheckingNetwork
                            ? 'Checking'
                            : isNetworkAvailable
                            ? 'Online'
                            : 'Offline',
                        color: color,
                        surface: color.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorMessage == null ? subtitle : '$subtitle $errorMessage',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsGroup extends StatelessWidget {
  const _MetricsGroup({
    required this.metrics,
    required this.onLiveTap,
    required this.onQueuedTap,
  });

  final List<SosMetric> metrics;
  final VoidCallback onLiveTap;
  final VoidCallback onQueuedTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              Expanded(
                child: _MetricCell(
                  metric: metrics[index],
                  onTap: switch (metrics[index].label) {
                    'Live' => onLiveTap,
                    'Queued' when metrics[index].value != '0' => onQueuedTap,
                    _ => null,
                  },
                ),
              ),
              if (index != metrics.length - 1) const _VerticalSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, this.onTap});

  final SosMetric metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _SosColors.textFor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: onTap == null
                  ? _SosColors.secondaryTextFor(context)
                  : _SosColors.green,
              fontWeight: onTap == null ? FontWeight.w400 : FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveNearbySosEventsPanel extends StatelessWidget {
  const _ActiveNearbySosEventsPanel({
    required this.events,
    required this.phoneLocation,
    required this.onTap,
  });

  final List<NearbySosEvent> events;
  final SosTriggerLocation? phoneLocation;
  final ValueChanged<NearbySosEvent> onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const _Glyph(icon: Icons.sos_rounded, color: _SosColors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby SOS needed',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _SosColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        events.length == 1
                            ? '1 active nearby event'
                            : '${events.length} active nearby events',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _SosColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: 'Active',
                  color: _SosColors.orange,
                  surface: _SosColors.orange.withValues(alpha: 0.12),
                ),
              ],
            ),
          ),
          const _HorizontalSeparator(),
          for (var index = 0; index < events.length; index++) ...[
            _TapSurface(
              onTap: () => onTap(events[index]),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_searching_rounded,
                      color: _SosColors.orange,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            events[index].hasReportedLocation
                                ? 'Reported location available'
                                : 'Approximate nearby area',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _nearbySosEventSummary(
                              events[index],
                              phoneLocation,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.secondaryTextFor(context),
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_forward,
                      color: _SosColors.chevronFor(context),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            if (index != events.length - 1) const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }
}

class _NearbySosHistoryRow extends StatelessWidget {
  const _NearbySosHistoryRow({
    required this.event,
    required this.phoneLocation,
    required this.onTap,
  });

  final NearbySosEvent event;
  final SosTriggerLocation? phoneLocation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distance = event.distanceMetersFrom(phoneLocation);
    final archivedByAge =
        event.ageAt(DateTime.now().toUtc()) > NearbySosEvent.activeDuration;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Glyph(icon: Icons.sos_rounded, color: _SosColors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEARBY SOS',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _nearbySosTimestamp(event.receivedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: event.hasReportedLocation
                            ? 'Location reported'
                            : 'Approximate area',
                        color: _SosColors.orange,
                        surface: _SosColors.orange.withValues(alpha: 0.12),
                      ),
                      _StatusPill(
                        label: archivedByAge
                            ? 'Over 1 hour old'
                            : distance == null
                            ? 'Distance unavailable'
                            : _nearbySosDistance(distance),
                        color: _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

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

String _nearbySosDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

String _nearbySosTimestamp(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  return '$date $time';
}

class _AdminSosSystemLogsPanel extends StatelessWidget {
  const _AdminSosSystemLogsPanel({
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
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final eventCount = logs.length + nearbyEvents.length;
    final subtitle = errorMessage != null && eventCount == 0
        ? 'Unable to load events. Tap to inspect the status.'
        : eventCount == 0
        ? 'No SOS events found yet.'
        : '$eventCount event${eventCount == 1 ? '' : 's'} available. Tap to view all.';

    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSosSystemLogsSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                _Glyph(
                  icon: Icons.receipt_long_rounded,
                  color: errorMessage == null
                      ? _SosColors.green
                      : _SosColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS events',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _SosColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _SosColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh SOS events',
                  onPressed: isLoading ? null : onRefresh,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSosSystemLogsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _SosColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.36,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                children: [
                  Row(
                    children: [
                      const Expanded(child: _SectionTitle(label: 'SOS events')),
                      IconButton(
                        tooltip: 'Refresh SOS events',
                        onPressed: isLoading ? null : onRefresh,
                        icon: isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Column(
                      children: [
                        if (errorMessage != null) ...[
                          _SosSystemLogEmptyState(
                            icon: Icons.cloud_off_rounded,
                            message: errorMessage!,
                          ),
                          if (logs.isNotEmpty || nearbyEvents.isNotEmpty)
                            const _HorizontalSeparator(),
                        ],
                        if (logs.isEmpty &&
                            nearbyEvents.isEmpty &&
                            errorMessage == null)
                          const _SosSystemLogEmptyState(
                            icon: Icons.fact_check_rounded,
                            message: 'No SOS events found yet.',
                          )
                        else if (logs.isNotEmpty ||
                            nearbyEvents.isNotEmpty) ...[
                          for (
                            var index = 0;
                            index < nearbyEvents.length;
                            index++
                          ) ...[
                            _NearbySosHistoryRow(
                              event: nearbyEvents[index],
                              phoneLocation: phoneLocation,
                              onTap: () =>
                                  onNearbyEventTap(nearbyEvents[index]),
                            ),
                            if (index != nearbyEvents.length - 1 ||
                                logs.isNotEmpty)
                              const _HorizontalSeparator(),
                          ],
                          for (var index = 0; index < logs.length; index++) ...[
                            _SosSystemLogRow(log: logs[index]),
                            if (index != logs.length - 1)
                              const _HorizontalSeparator(),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SosSystemLogRow extends StatelessWidget {
  const _SosSystemLogRow({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final status = _sosLogString(log['status'], fallback: 'unknown');
    final mode = _sosLogString(log['mode'], fallback: 'sos');
    final sent = _sosLogInt(log['sentCount']);
    final failed = _sosLogInt(log['failedCount']);
    final contactCount = _sosLogInt(log['contactCount']);
    final color = failed > 0 || status == 'failed'
        ? _SosColors.orange
        : _SosColors.green;

    return InkWell(
      onTap: () => _showSosSystemLogDetails(context, log),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: failed > 0 || status == 'failed'
                  ? Icons.warning_amber_rounded
                  : Icons.verified_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${mode.toUpperCase()} - ${status.toUpperCase()}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _sosLogDateLabel(log['triggeredAtLocal']),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: '$sent sent',
                        color: _SosColors.green,
                        surface: _SosColors.greenSoftFor(context),
                      ),
                      _StatusPill(
                        label: '$failed failed',
                        color: failed > 0
                            ? _SosColors.orange
                            : _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                      _StatusPill(
                        label: '$contactCount contacts',
                        color: _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _SosSystemLogEmptyState extends StatelessWidget {
  const _SosSystemLogEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Glyph(icon: icon, color: _SosColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _SosColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showSosSystemLogDetails(BuildContext context, Map<String, dynamic> log) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: _SosColors.surfaceFor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return _SosSystemLogDetailSheet(log: log);
    },
  );
}

class _SosSystemLogDetailSheet extends StatelessWidget {
  const _SosSystemLogDetailSheet({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final location = _sosLogLocationSummary(log['triggerLocation']);
    final dispatches = log['dispatches'];
    final dispatchCount = dispatches is Iterable ? dispatches.length : 0;

    return SafeArea(
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
                const _Glyph(icon: Icons.sos_rounded, color: _SosColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS event',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _SosColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        _sosLogDateLabel(log['triggeredAtLocal']),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    _StatusRow(
                      label: 'Alert ID',
                      value: _sosLogString(log['alertId'], fallback: '-'),
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Type',
                      value: _sosLogString(log['mode'], fallback: 'SOS'),
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Status',
                      value: _sosLogString(log['status'], fallback: 'unknown'),
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
                    _StatusRow(label: 'Location', value: location),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Contacts',
                      value:
                          '${_sosLogInt(log['sentCount'])}/${_sosLogInt(log['contactCount'])} sent, ${_sosLogInt(log['failedCount'])} failed',
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Dispatch records',
                      value: '$dispatchCount',
                    ),
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
    );
  }
}

class _EmergencySosControlCard extends StatefulWidget {
  const _EmergencySosControlCard({
    required this.isSending,
    required this.isAlarmActive,
    required this.onTrigger,
    required this.onStopAlarm,
    required this.onShowGuide,
    required this.onDuressLongPress,
  });

  final bool isSending;
  final bool isAlarmActive;
  final VoidCallback onTrigger;
  final VoidCallback onStopAlarm;
  final VoidCallback onShowGuide;
  final VoidCallback onDuressLongPress;

  @override
  State<_EmergencySosControlCard> createState() =>
      _EmergencySosControlCardState();
}

class _EmergencySosControlCardState extends State<_EmergencySosControlCard>
    with SingleTickerProviderStateMixin {
  static const Duration _duressHoldDuration = Duration(milliseconds: 1200);

  late final AnimationController _holdController;
  bool _isPressing = false;
  bool _duressTriggered = false;

  @override
  void initState() {
    super.initState();
    _holdController =
        AnimationController(vsync: this, duration: _duressHoldDuration)
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed ||
                _duressTriggered ||
                widget.isSending ||
                widget.isAlarmActive) {
              return;
            }
            _duressTriggered = true;
            if (mounted) setState(() {});
            widget.onDuressLongPress();
          });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.isSending && !widget.isAlarmActive) return;
    _duressTriggered = false;
    setState(() => _isPressing = true);
    if (!widget.isAlarmActive) {
      _holdController.forward(from: 0);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final shouldStopAlarm = widget.isAlarmActive;
    if (shouldStopAlarm) {
      _cancelPress();
      widget.onStopAlarm();
      return;
    }
    if (widget.isSending) {
      _cancelPress();
      return;
    }
    final didTriggerDuress = _duressTriggered;
    _cancelPress();
    if (didTriggerDuress) return;
    widget.onTrigger();
  }

  void _cancelPress() {
    _holdController.stop();
    _holdController.value = 0;
    if (mounted && (_isPressing || _duressTriggered)) {
      setState(() {
        _isPressing = false;
        _duressTriggered = false;
      });
    } else {
      _isPressing = false;
      _duressTriggered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Emergency SOS',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _SosColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                key: const Key('sos-emergency-button'),
                behavior: HitTestBehavior.opaque,
                onTapDown: _handleTapDown,
                onTapUp: _handleTapUp,
                onTapCancel: _cancelPress,
                child: AnimatedBuilder(
                  animation: _holdController,
                  builder: (context, child) {
                    final holdProgress = widget.isAlarmActive
                        ? 0.0
                        : _holdController.value;
                    final idleColor = _SosColors.destructiveFor(context);
                    final buttonColor = widget.isAlarmActive
                        ? _SosColors.green
                        : widget.isSending
                        ? idleColor.withValues(alpha: 0.58)
                        : Color.lerp(
                            idleColor,
                            _SosColors.duress,
                            holdProgress,
                          )!;
                    final actionLabel = widget.isAlarmActive
                        ? 'STOP'
                        : widget.isSending
                        ? 'SENDING'
                        : _duressTriggered
                        ? 'DURESS'
                        : _isPressing
                        ? 'HOLD…'
                        : null;
                    final helperLabel = widget.isAlarmActive
                        ? 'Alarm active'
                        : widget.isSending
                        ? 'Notifying contacts'
                        : _duressTriggered
                        ? 'Silent alert started'
                        : _isPressing
                        ? 'Keep holding for Duress'
                        : 'Tap or hold';
                    return SizedBox.square(
                      dimension: 208,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (holdProgress > 0)
                            SizedBox.square(
                              dimension: 204,
                              child: CircularProgressIndicator(
                                value: holdProgress,
                                strokeWidth: 5,
                                color: _SosColors.duress,
                                backgroundColor: _SosColors.duress.withValues(
                                  alpha: 0.14,
                                ),
                              ),
                            ),
                          AnimatedScale(
                            scale: _isPressing ? 0.96 : 1,
                            duration: const Duration(milliseconds: 140),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 188,
                              height: 188,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: buttonColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: buttonColor.withValues(alpha: 0.26),
                                    blurRadius: 26,
                                    spreadRadius: 8,
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  width: 7,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.isAlarmActive
                                        ? Icons.notifications_off_rounded
                                        : _duressTriggered
                                        ? Icons.visibility_off_rounded
                                        : Icons.sos_rounded,
                                    color: Colors.white,
                                    size: 46,
                                  ),
                                  SizedBox(
                                    height: actionLabel == null ? 12 : 8,
                                  ),
                                  if (actionLabel != null) ...[
                                    Text(
                                      actionLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    helperLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.88,
                                          ),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: _SosColors.backgroundFor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _SosColors.separatorFor(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Tap: ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const TextSpan(
                            text:
                                'Manual SOS with a loud alarm and cancel time.\n',
                          ),
                          TextSpan(
                            text: 'Hold: ',
                            style: TextStyle(
                              color: _SosColors.duress,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text: 'silent Duress SOS sent without a countdown.',
                          ),
                        ],
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        height: 1.45,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -5),
                    child: IconButton(
                      key: const Key('sos-gesture-info-button'),
                      tooltip: 'How Manual and Duress SOS work',
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onShowGuide,
                      icon: const Icon(Icons.info_outline_rounded),
                      color: _SosColors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SosGestureDemoResult { waiting, manual, duress }

class _SosGestureGuidePage extends StatefulWidget {
  const _SosGestureGuidePage();

  @override
  State<_SosGestureGuidePage> createState() => _SosGestureGuidePageState();
}

class _SosGestureGuidePageState extends State<_SosGestureGuidePage> {
  _SosGestureDemoResult _demoResult = _SosGestureDemoResult.waiting;
  bool _isHoldingDemo = false;

  void _showManualDemo() {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _isHoldingDemo = false;
      _demoResult = _SosGestureDemoResult.manual;
    });
  }

  void _showDuressDemo() {
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _isHoldingDemo = false;
      _demoResult = _SosGestureDemoResult.duress;
    });
  }

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
                  const _SectionTitle(label: 'Try the gesture safely'),
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
}

class _SosGestureExplanationCard extends StatelessWidget {
  const _SosGestureExplanationCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      height: 1.4,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosDemoResultPanel extends StatelessWidget {
  const _SosDemoResultPanel({super.key, required this.result});

  final _SosGestureDemoResult result;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, message) = switch (result) {
      _SosGestureDemoResult.manual => (
        Icons.notifications_active_rounded,
        _SosColors.destructiveFor(context),
        'Manual SOS gesture',
        'A 10-second cancel screen would appear before the loud alert starts.',
      ),
      _SosGestureDemoResult.duress => (
        Icons.visibility_off_rounded,
        _SosColors.duress,
        'Duress SOS gesture',
        'A silent alert would be sent immediately without showing a countdown.',
      ),
      _SosGestureDemoResult.waiting => (
        Icons.touch_app_rounded,
        _SosColors.green,
        'Tap or hold the demo button',
        'The result will appear here. This demo never contacts anyone.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuedSosDispatchesPage extends StatefulWidget {
  const _QueuedSosDispatchesPage({required this.loadDispatches});

  final Future<List<SosQueuedDispatch>> Function() loadDispatches;

  @override
  State<_QueuedSosDispatchesPage> createState() =>
      _QueuedSosDispatchesPageState();
}

class _QueuedSosDispatchesPageState extends State<_QueuedSosDispatchesPage> {
  late Future<List<SosQueuedDispatch>> _dispatches;

  @override
  void initState() {
    super.initState();
    _dispatches = widget.loadDispatches();
  }

  void _refresh() {
    setState(() => _dispatches = widget.loadDispatches());
  }

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
                    subtitle: 'Protected alerts waiting for delivery',
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
                                  'Queued SOS alerts cannot be removed here. HikerCircle retries them automatically when delivery becomes available.',
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
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return _QueuedSosEmptyState(
                            icon: Icons.sync_problem_rounded,
                            title: 'Queue unavailable',
                            subtitle:
                                'The protected queue could not be read right now.',
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

class _QueuedSosDispatchCard extends StatelessWidget {
  const _QueuedSosDispatchCard({required this.dispatch, required this.onTap});

  final SosQueuedDispatch dispatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Glyph(
                icon: dispatch.mode == SosAlertMode.duress
                    ? Icons.visibility_off_rounded
                    : Icons.outbox_rounded,
                color: dispatch.mode == SosAlertMode.duress
                    ? _SosColors.duress
                    : _SosColors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dispatch.mode.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _SosColors.textFor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _queuedSosTimeLabel(dispatch.triggeredAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dispatch.pendingContactCount} contact dispatches waiting'
                      '${dispatch.retryCount == 0 ? '' : ' · ${dispatch.retryCount} retries'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.orange,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _SosColors.chevronFor(context),
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueuedSosDispatchDetailPage extends StatelessWidget {
  const _QueuedSosDispatchDetailPage({required this.dispatch});

  final SosQueuedDispatch dispatch;

  @override
  Widget build(BuildContext context) {
    final status = dispatch.sendStatus == 'retry'
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
                    subtitle: 'Read-only dispatch record',
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
                            color: _SosColors.orange,
                            surface: _SosColors.orange.withValues(alpha: 0.1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InsetGroup(
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
                              '${dispatch.pendingContactCount}/${dispatch.contactCount}',
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
                        if (dispatch.lastError.isNotEmpty) ...[
                          const _HorizontalSeparator(),
                          _StatusRow(
                            label: 'Last delivery result',
                            value: dispatch.lastError,
                          ),
                        ],
                      ],
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
                              'Message snapshot',
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
                    'This record is protected from manual removal and will leave the queue only after HikerCircle confirms it no longer needs dispatch.',
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

class _QueuedSosEmptyState extends StatelessWidget {
  const _QueuedSosEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Glyph(icon: icon, color: _SosColors.green),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _SosColors.textFor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _SosColors.secondaryTextFor(context),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

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

class _SosSafetyToolsGrid extends StatelessWidget {
  const _SosSafetyToolsGrid({
    required this.onOpenFirstAid,
    required this.onOpenGearChecklist,
  });

  final VoidCallback onOpenFirstAid;
  final VoidCallback onOpenGearChecklist;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.62,
      children: [
        _SosSafetyToolTile(
          icon: Icons.medical_services_rounded,
          title: 'First-Aid Guide',
          subtitle: 'Offline steps',
          onTap: onOpenFirstAid,
        ),
        _SosSafetyToolTile(
          icon: Icons.checklist_rounded,
          title: 'Gear Checklist',
          subtitle: 'Pre-hike essentials',
          onTap: onOpenGearChecklist,
        ),
      ],
    );
  }
}

class _SosSafetyToolTile extends StatelessWidget {
  const _SosSafetyToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Glyph(icon: icon, color: _SosColors.green),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _SosColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
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

class _SosTriggerLogPanel extends StatelessWidget {
  const _SosTriggerLogPanel({
    required this.isNetworkAvailable,
    required this.session,
    required this.latestResult,
    required this.customWhatsAppNotes,
    required this.cloudAlertLogs,
    required this.onCustomWhatsAppNoteChanged,
  });

  final bool isNetworkAvailable;
  final AppSession session;
  final SosAlertResult? latestResult;
  final Map<SosAlertMode, String> customWhatsAppNotes;
  final List<SosAlert> cloudAlertLogs;
  final void Function(SosAlertMode mode, String note)
  onCustomWhatsAppNoteChanged;

  @override
  Widget build(BuildContext context) {
    final latestAlert = latestResult?.alert;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(label: 'SOS Trigger Log'),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.chat_bubble_rounded,
          title: 'WhatsApp notification',
          subtitle: 'Edit Manual, Duress, and Medical SOS notes.',
          trailing: 'Edit',
          onTap: () => unawaited(_openWhatsAppMessageEditor(context)),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.cloud_done_rounded,
          title: 'Cloud alert log',
          subtitle: latestAlert == null
              ? 'Cloud logs load from Firebase when alerts exist.'
              : 'Latest ${latestAlert.mode.label} is logged with audit fields.',
          trailing: isNetworkAvailable ? '${cloudAlertLogs.length}' : 'Offline',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'Cloud alert log',
            icon: Icons.cloud_done_rounded,
            description:
                'SOS alerts are read from the top-level sosAlerts Firebase collection and mirrored to the user profile latest alert.',
            rows: _cloudLogRows(),
          ),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.fact_check_rounded,
          title: 'SOS trigger log',
          subtitle: latestAlert == null
              ? 'Trigger results appear after an SOS alert is sent.'
              : '${latestAlert.sentCount} sent, ${latestAlert.failedCount} failed.',
          trailing: latestAlert?.status.label ?? 'View',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'SOS trigger log',
            icon: Icons.fact_check_rounded,
            description:
                'Each contact dispatch records the normalized recipient, send state, and any WhatsApp/Green API error returned by the delivery layer.',
            rows: _deliveryResultRows(),
          ),
        ),
      ],
    );
  }

  Future<void> _openWhatsAppMessageEditor(BuildContext context) async {
    final latestAlert = latestResult?.alert;
    final update = await Navigator.of(context).push<_WhatsAppNoteUpdate>(
      MaterialPageRoute<_WhatsAppNoteUpdate>(
        builder: (context) {
          return _WhatsAppMessageDetailPage(
            session: session,
            initialNotes: customWhatsAppNotes,
            previewMode: latestAlert?.mode ?? SosAlertMode.manual,
            previewTriggeredAt: latestAlert?.triggeredAt ?? DateTime.now(),
            previewLocation: latestAlert?.triggerLocation,
          );
        },
      ),
    );

    if (update != null && context.mounted) {
      onCustomWhatsAppNoteChanged(update.mode, update.note);
    }
  }

  List<(String, String)> _cloudLogRows() {
    final latestAlert = latestResult?.alert;
    final userDocumentId = FirebaseUserRepository.documentIdForPhoneNumber(
      session.phoneNumber,
    );
    if (latestAlert == null) {
      return [
        ('Network status', isNetworkAvailable ? 'Ready' : 'Offline'),
        ('User latest path', 'users/$userDocumentId/latest_sos_alert'),
        ('Audit collection', 'sosAlerts/{alertId}'),
        ('Loaded cloud logs', '${cloudAlertLogs.length}'),
        for (final alert in cloudAlertLogs.take(8))
          (
            '${alert.mode.label} ${_shortTime(alert.triggeredAt)}',
            alert.status.label,
          ),
        ('Stored fields', 'Mode, timestamp, GPS, message, status, dispatches'),
      ];
    }

    return [
      if (cloudAlertLogs.isNotEmpty)
        ('Loaded cloud logs', '${cloudAlertLogs.length}'),
      for (final alert in cloudAlertLogs.take(8))
        (
          '${alert.mode.label} ${_shortTime(alert.triggeredAt)}',
          alert.status.label,
        ),
      ('Alert ID', latestAlert.id),
      ('Status', latestAlert.status.label),
      ('Triggered', latestAlert.triggeredAt.toUtc().toIso8601String()),
      ('User latest path', 'users/$userDocumentId/latest_sos_alert'),
      ('Audit path', 'sosAlerts/${latestAlert.id}'),
      (
        'Location',
        latestAlert.triggerLocation?.universalMapLink ?? 'Unavailable',
      ),
    ];
  }

  String _shortTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  List<(String, String)> _deliveryResultRows() {
    final latestAlert = latestResult?.alert;
    if (latestAlert == null) {
      return const [
        ('Latest alert', 'No SOS alert sent yet'),
        ('Sent', '0 contacts'),
        ('Failed', '0 contacts'),
      ];
    }

    return [
      ('Alert mode', latestAlert.mode.label),
      ('Overall status', latestAlert.status.label),
      ('Contacts', '${latestAlert.contactCount} selected'),
      ('Sent', '${latestAlert.sentCount} contacts'),
      ('Failed', '${latestAlert.failedCount} contacts'),
      for (final dispatch in latestAlert.dispatches)
        (
          dispatch.contactName,
          dispatch.wasSent
              ? 'Sent to ${dispatch.phoneNumber}'
              : 'Failed: ${dispatch.errorMessage ?? dispatch.phoneNumber}',
        ),
    ];
  }

  void _openDeliveryDetail(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String description,
    required List<(String, String)> rows,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AlertDeliveryDetailPage(
          title: title,
          icon: icon,
          description: description,
          rows: rows,
        ),
      ),
    );
  }
}

class _DeliveryActionCard extends StatelessWidget {
  const _DeliveryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              _Glyph(icon: icon, color: _SosColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _SosColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: trailing,
                color: _SosColors.green,
                surface: _SosColors.greenSoftFor(context),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _SosColors.chevronFor(context),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatsAppNoteUpdate {
  const _WhatsAppNoteUpdate({required this.mode, required this.note});

  final SosAlertMode mode;
  final String note;
}

class _WhatsAppMessageDetailPage extends StatefulWidget {
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

  @override
  State<_WhatsAppMessageDetailPage> createState() =>
      _WhatsAppMessageDetailPageState();
}

class _WhatsAppMessageDetailPageState
    extends State<_WhatsAppMessageDetailPage> {
  late final TextEditingController _noteController;
  late SosAlertMode _selectedMode;
  late Map<SosAlertMode, String> _notes;

  @override
  void initState() {
    super.initState();
    _notes = {..._SosPageState._defaultWhatsAppNotes(), ...widget.initialNotes};
    _selectedMode = _editableModeFor(widget.previewMode);
    _noteController = TextEditingController(text: _noteFor(_selectedMode));
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

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
                    title: 'WhatsApp Message',
                    subtitle: 'Custom SOS notification payload',
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
                            'Custom note',
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
                          SelectableText(
                            preview,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  height: 1.35,
                                  letterSpacing: 0,
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

  SosAlertMode _editableModeFor(SosAlertMode mode) {
    if (mode == SosAlertMode.duress ||
        mode == SosAlertMode.medical ||
        mode == SosAlertMode.manual) {
      return mode;
    }
    return SosAlertMode.manual;
  }

  String _noteFor(SosAlertMode mode) {
    return _notes[mode] ?? SosAlertMessageComposer.defaultCustomNoteFor(mode);
  }

  void _saveCurrentNote() {
    _notes = {..._notes, _selectedMode: _noteController.text.trim()};
  }
}

class _AlertDeliveryDetailPage extends StatelessWidget {
  const _AlertDeliveryDetailPage({
    required this.title,
    required this.icon,
    required this.description,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final String description;
  final List<(String, String)> rows;

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
                    title: title,
                    subtitle: 'Alert delivery settings',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Glyph(icon: icon, color: _SosColors.green),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.secondaryTextFor(context),
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          for (final row in rows) ...[
                            _StatusRow(label: row.$1, value: row.$2),
                            if (row != rows.last) const _HorizontalSeparator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Done'),
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

class _SosTestSettingsPage extends StatefulWidget {
  const _SosTestSettingsPage({
    required this.phoneNumber,
    required this.onSendWhatsAppTest,
  });

  final String phoneNumber;
  final Future<List<SosContactDispatch>> Function() onSendWhatsAppTest;

  @override
  State<_SosTestSettingsPage> createState() => _SosTestSettingsPageState();
}

class _SosTestSettingsPageState extends State<_SosTestSettingsPage> {
  static const Duration _bleSosTestDuration = Duration(seconds: 5);

  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  final HikerBleService _bleService = const HikerBleService();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  Timer? _testStopTimer;
  bool _isFlashlightActive = false;
  bool _isEmergencySirenActive = false;
  bool _isMedicalSirenActive = false;
  bool _isBroadcastingBleSosTest = false;
  bool _legacyUnpairedButtonEnabled = false;
  bool _isAccelerometerTestActive = false;
  bool _isGyroscopeTestActive = false;
  double _accelerometerTestProgress = 0;
  double _gyroscopeTestProgress = 0;
  String _accelerometerTestStatus =
      'Tap Start, hold the phone securely, then do one quick downward shake.';
  String _gyroscopeTestStatus =
      'Tap Start, then rotate your wrist left-right and tilt forward-back.';

  @override
  void initState() {
    super.initState();
    unawaited(_loadLegacyButtonSetting());
    _accelerometerSubscription =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 200),
        ).listen(
          (event) {
            if (!mounted) {
              return;
            }
            _handleAccelerometerTestEvent(event);
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _accelerometerTestStatus = 'Accelerometer unavailable.';
              });
            }
          },
        );
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

  Future<void> _loadLegacyButtonSetting() async {
    final enabled = await _bleService.isLegacyUnpairedSosButtonEnabled();
    if (mounted) {
      setState(() => _legacyUnpairedButtonEnabled = enabled);
    }
  }

  Future<void> _toggleLegacyButtonSetting() async {
    final enabled = !_legacyUnpairedButtonEnabled;
    try {
      await _bleService.setLegacyUnpairedSosButtonEnabled(enabled);
      if (mounted) {
        setState(() => _legacyUnpairedButtonEnabled = enabled);
      }
    } on HikerBleException catch (error) {
      _showTestResult(error.message);
    }
  }

  @override
  void dispose() {
    _testStopTimer?.cancel();
    unawaited(_accelerometerSubscription?.cancel());
    unawaited(_gyroscopeSubscription?.cancel());
    unawaited(_deviceAlertService.stopFlashlightPattern());
    unawaited(_deviceAlertService.stopManualSosPattern());
    super.dispose();
  }

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
                          _SensorTestCard(
                            icon: Icons.sensors_rounded,
                            title: 'Accelerometer free-fall mimic',
                            instruction:
                                'Quickly shake downward once while holding the phone securely.',
                            progress: _accelerometerTestProgress,
                            status: _accelerometerTestStatus,
                            isActive: _isAccelerometerTestActive,
                            onStart: _startAccelerometerTest,
                          ),
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

  Future<void> _sendWhatsAppTestMessage() async {
    try {
      final dispatches = await widget.onSendWhatsAppTest();
      final sent = dispatches.where((dispatch) => dispatch.wasSent).length;
      final firstFailure = dispatches
          .where((dispatch) => !dispatch.wasSent)
          .map((dispatch) => dispatch.errorMessage?.trim() ?? '')
          .where((message) => message.isNotEmpty)
          .firstOrNull;
      _showTestResult(
        sent == dispatches.length
            ? 'WhatsApp cloud test sent to $sent/${dispatches.length} contacts.'
            : 'WhatsApp cloud test sent to $sent/${dispatches.length} contacts.'
                  '${firstFailure == null ? '' : ' $firstFailure'}',
      );
    } catch (error) {
      _showTestResult('Unable to send WhatsApp cloud test. $error');
    }
  }

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
        'BLE SOS test broadcast for 5 seconds. Nearby HikerCircle phones should show a help popup.',
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

  Future<void> _stopAllTests() async {
    _testStopTimer?.cancel();
    try {
      await _deviceAlertService.stopFlashlightPattern();
      await _deviceAlertService.stopManualSosPattern();
    } finally {
      if (mounted) {
        setState(() {
          _isFlashlightActive = false;
          _isEmergencySirenActive = false;
          _isMedicalSirenActive = false;
        });
      }
    }
  }

  void _scheduleAutoStop() {
    _testStopTimer?.cancel();
    _testStopTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_stopAllTests());
    });
  }

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

  void _startAccelerometerTest() {
    setState(() {
      _isAccelerometerTestActive = true;
      _accelerometerTestProgress = 0;
      _accelerometerTestStatus =
          'Ready. Do one quick downward shake while gripping the phone.';
    });
  }

  void _startGyroscopeTest() {
    setState(() {
      _isGyroscopeTestActive = true;
      _gyroscopeTestProgress = 0;
      _gyroscopeTestStatus =
          'Ready. Rotate and tilt the phone for a few seconds.';
    });
  }

  void _handleAccelerometerTestEvent(AccelerometerEvent event) {
    if (!_isAccelerometerTestActive || !mounted) {
      return;
    }
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final detected = magnitude < 4 || event.z < -8 || event.y < -8;
    if (!detected) {
      return;
    }
    setState(() {
      _accelerometerTestProgress = (_accelerometerTestProgress + 0.34)
          .clamp(0, 1)
          .toDouble();
      _accelerometerTestStatus = _accelerometerTestProgress >= 1
          ? 'Passed. Accelerometer detected the fast downward motion.'
          : 'Motion detected. Repeat once more to confirm.';
      if (_accelerometerTestProgress >= 1) {
        _isAccelerometerTestActive = false;
      }
    });
  }

  void _handleGyroscopeTestEvent(GyroscopeEvent event) {
    if (!_isGyroscopeTestActive || !mounted) {
      return;
    }
    final angularMotion = event.x.abs() + event.y.abs() + event.z.abs();
    if (angularMotion < 1.4) {
      return;
    }
    setState(() {
      _gyroscopeTestProgress = (_gyroscopeTestProgress + 0.18)
          .clamp(0, 1)
          .toDouble();
      _gyroscopeTestStatus = _gyroscopeTestProgress >= 1
          ? 'Passed. Gyroscope detected rotation on the phone.'
          : 'Rotation detected. Keep rotating briefly.';
      if (_gyroscopeTestProgress >= 1) {
        _isGyroscopeTestActive = false;
      }
    });
  }
}

class _FlashPatternPreview extends StatefulWidget {
  const _FlashPatternPreview({required this.active});

  final bool active;

  @override
  State<_FlashPatternPreview> createState() => _FlashPatternPreviewState();
}

class _FlashPatternPreviewState extends State<_FlashPatternPreview> {
  Timer? _timer;
  bool _isOn = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _FlashPatternPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.active) {
      setState(() {
        _isOn = false;
      });
      return;
    }

    _timer = Timer.periodic(const Duration(milliseconds: 260), (_) {
      if (mounted) {
        setState(() {
          _isOn = !_isOn;
        });
      }
    });
  }

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

class _SensorTestCard extends StatelessWidget {
  const _SensorTestCard({
    required this.icon,
    required this.title,
    required this.instruction,
    required this.progress,
    required this.status,
    required this.isActive,
    required this.onStart,
  });

  final IconData icon;
  final String title;
  final String instruction;
  final double progress;
  final String status;
  final bool isActive;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _Glyph(icon: icon, color: _SosColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _SosColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  instruction,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: _SosColors.green,
                    backgroundColor: _SosColors.greenSoftFor(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: isActive ? null : onStart,
            child: Text(progress >= 1 ? 'Retest' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class _SosTestRow extends StatelessWidget {
  const _SosTestRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon, color: _SosColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: _SosColors.chevronFor(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _SosDetailHeader extends StatelessWidget {
  const _SosDetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _SosColors.surfaceFor(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.chevron_back,
                color: _SosColors.green,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _SosColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _SosColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 11, 0, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _SosColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _SosColors.secondaryTextFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.surface,
  });

  final String label;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

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

class _TapSurface extends StatelessWidget {
  const _TapSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

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

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _SosColors.separatorFor(context),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _SosColors.separatorFor(context),
      ),
    );
  }
}

String _sosLogString(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

int _sosLogInt(Object? value) {
  return value is num && value.isFinite ? value.toInt() : 0;
}

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

String _sosLogLocationSummary(Object? value) {
  if (value is! Map || value.isEmpty) {
    return 'Unavailable';
  }
  final latitude = value['latitude'];
  final longitude = value['longitude'];
  final accuracy = value['accuracyMeters'];
  if (latitude is! num || longitude is! num) {
    return 'Captured';
  }
  final coordinate =
      '${latitude.toDouble().toStringAsFixed(5)}, ${longitude.toDouble().toStringAsFixed(5)}';
  if (accuracy is num) {
    return '$coordinate (+/- ${accuracy.round()} m)';
  }
  return coordinate;
}

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

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color destructiveSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF3C1B1B) : destructiveSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
