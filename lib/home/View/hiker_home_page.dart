import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../circle/View/circle_page.dart';
import '../../me/Data/live_location_sharing_service.dart';
import '../../me/View/me_page.dart';
import '../../navigation/View/hiker_bottom_nav_bar.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Data/sos_alert_repository.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../../sos/View/ios_sos_volume_guard.dart';
import '../../sos/View/sos_page.dart';
import '../../trail/Data/trail_repository.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';
import '../Model/hike_session_models.dart';
import '../ModelView/fall_stillness_monitor.dart';
import 'home_dashboard_page.dart';
import 'start_hike_wizard_page.dart';

class HikerHomePage extends StatefulWidget {
  const HikerHomePage({
    super.key,
    required this.session,
    required this.onSignOut,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final VoidCallback onSignOut;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<HikerHomePage> createState() => _HikerHomePageState();
}

class _HikerHomePageState extends State<HikerHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _deepLinkChannel = MethodChannel(
    'hiker_circle/deeplinks',
  );
  static const String _fallStillnessPrompt =
      'Are you okay? Do you need help? Please respond by tapping the phone three times to cancel SOS.';

  late final TabController tabController;
  late final List<Trail> trails;
  late final HikerCircleFirebaseRepository hikerCircleRepository;
  late final EmergencyContactsRepository emergencyContactsRepository;
  late final SosAlertRepository sosAlertRepository;
  late final FallStillnessMonitor fallStillnessMonitor;
  final SosDeviceAlertService _sosDeviceAlertService =
      const SosDeviceAlertService();
  late PlannedHike plannedHike;
  bool isLoadingLiveData = false;
  bool isSendingFallStillnessSos = false;
  bool isFallStillnessDialogVisible = false;
  bool isFallStillnessLocalAlarmActive = false;
  bool fallStillnessCountdownWasBackgrounded = false;
  FallStillnessMonitorStatus lastFallStillnessStatus =
      FallStillnessMonitorStatus.inactive;
  ActiveHikeSession? activeHike;
  int selectedTabIndex = 0;
  int manualSosRequestId = 0;
  final List<DateTime> fallStillnessCancelTaps = <DateTime>[];
  List<EmergencyContact> emergencyContacts = const [
    EmergencyContact(
      name: 'Mother',
      phoneNumber: '+60123456789',
      relationship: 'Family',
    ),
    EmergencyContact(
      name: 'Brother',
      phoneNumber: '+60198765432',
      relationship: 'Family',
    ),
  ];

  final List<HikerBottomNavDestination> tabs =
      HikerBottomNavBar.standardDestinations;

  @override
  void initState() {
    super.initState();
    trails = const TrailRepository().loadTrails();
    hikerCircleRepository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    plannedHike = PlannedHike(
      trail: trails.first,
      plannedStartTime: DateTime(2026, 6, 5, 6, 30),
      expectedReturnTime: DateTime(2026, 6, 5, 11, 30),
      weatherCached: true,
      offlineMapDownloaded: trails.first.offlineMapDownloaded,
      emergencyContactsSelected: true,
      checklistCompleted: 4,
      checklistTotal: 8,
      phoneBatteryLevel: 67,
      liveLocationConfigured: false,
    );
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    sosAlertRepository = SosAlertRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    fallStillnessMonitor = FallStillnessMonitor(
      onEmergencyReady: _handleFallStillnessEmergencyReady,
    );
    fallStillnessMonitor.addListener(_handleFallStillnessMonitorChanged);
    WidgetsBinding.instance.addObserver(this);
    tabController = TabController(length: tabs.length, vsync: this);
    tabController.addListener(updateTabIndex);
    _deepLinkChannel.setMethodCallHandler(_handleDeepLinkMethodCall);
    unawaited(LocationSnapshotService.instance.start());
    unawaited(loadLiveData());
    unawaited(_loadInitialDeepLink());
  }

  Future<void> _loadInitialDeepLink() async {
    try {
      final link = await _deepLinkChannel.invokeMethod<String>(
        'consumeInitialDeepLink',
      );
      if (link != null) {
        _handleDeepLink(link);
      }
    } catch (_) {
      // Deep links are optional on platforms that do not expose a native hook.
    }
  }

  Future<void> _handleDeepLinkMethodCall(MethodCall call) async {
    if (call.method != 'onDeepLink') {
      return;
    }
    final link = call.arguments;
    if (link is String) {
      _handleDeepLink(link);
    }
  }

  void _handleDeepLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'hikercircle') {
      return;
    }
    if (uri.host == 'sos' && uri.path == '/manual') {
      requestManualSos();
      return;
    }
    if (uri.host != 'buddy' || uri.path != '/add') {
      return;
    }

    final handle =
        uri.queryParameters['handle'] ?? uri.queryParameters['h'] ?? '';
    final name =
        uri.queryParameters['name'] ??
        uri.queryParameters['n'] ??
        'Trail buddy';
    final phone =
        uri.queryParameters['phone'] ?? uri.queryParameters['p'] ?? '';
    final ownHandle = _profileHandleForPhone(widget.session.phoneNumber);
    final isOwnLink =
        handle.toLowerCase() == ownHandle.toLowerCase() ||
        (phone.isNotEmpty && phone == widget.session.phoneNumber);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (isOwnLink) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'That is your own HikerCircle QR. No action taken.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      _showAddBuddyPrompt(name: name, handle: handle);
    });
  }

  Future<void> _showAddBuddyPrompt({
    required String name,
    required String handle,
  }) async {
    final shouldAdd = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF7EE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Color(0xFF34A853),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Add $name as a buddy?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  handle.isEmpty
                      ? 'This QR belongs to a HikerCircle profile.'
                      : '$handle can be added to your Trail Buddies for future team hikes and shared trail plans.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6E6E73),
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Not Now'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Add Buddy'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldAdd != true || !mounted) {
      return;
    }

    setState(() {
      selectedTabIndex = 3;
    });
    tabController.animateTo(3);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$name added to your buddies.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> loadLiveData() async {
    setState(() {
      isLoadingLiveData = true;
    });
    try {
      final liveTrails = await hikerCircleRepository.loadTrails();
      if (!mounted || liveTrails.isEmpty) {
        return;
      }
      setState(() {
        trails
          ..clear()
          ..addAll(liveTrails);
        plannedHike = PlannedHike(
          trail: liveTrails.first,
          plannedStartTime: plannedHike.plannedStartTime,
          expectedReturnTime: plannedHike.expectedReturnTime,
          weatherCached: true,
          offlineMapDownloaded: liveTrails.first.offlineMapDownloaded,
          emergencyContactsSelected: emergencyContacts.isNotEmpty,
          checklistCompleted: plannedHike.checklistCompleted,
          checklistTotal: plannedHike.checklistTotal,
          phoneBatteryLevel: plannedHike.phoneBatteryLevel,
          liveLocationConfigured: plannedHike.liveLocationConfigured,
        );
      });
      await hikerCircleRepository.ensureAchievementSeeds();
    } finally {
      if (mounted) {
        setState(() {
          isLoadingLiveData = false;
        });
      }
    }
  }

  void updateTabIndex() {
    if (tabController.index != selectedTabIndex) {
      setState(() {
        selectedTabIndex = tabController.index;
      });
    }
  }

  void onTabTap(int index) {
    _recordFallStillnessCancelTap();
    setState(() {
      selectedTabIndex = index;
    });
    tabController.animateTo(index);
  }

  Future<void> openStartHikeWizard(Trail trail) async {
    final startedHike = await Navigator.of(context).push<ActiveHikeSession>(
      MaterialPageRoute<ActiveHikeSession>(
        builder: (context) => StartHikeWizardPage(preselectedTrail: trail),
      ),
    );

    if (startedHike == null || !mounted) {
      return;
    }

    if (startedHike.draft.fallDetectionEnabled ||
        startedHike.draft.offlinePhysicalAlertEnabled) {
      final volumeReady = await ensureIosSosOutputVolumeReady(
        context: context,
        deviceAlertService: _sosDeviceAlertService,
        title: 'Turn Up iPhone Volume',
        message:
            'Fall SOS and offline audio SOS use iPhone media volume for the local alarm. Turn it up before starting your hike.',
        proceedLabel: 'Start Hike',
      );
      if (!volumeReady || !mounted) {
        return;
      }
    }

    ActiveHikeSession liveHike = startedHike;
    try {
      liveHike = await hikerCircleRepository.createActiveHikeSession(
        session: widget.session,
        draft: startedHike.draft,
      );
      final location = await LocationSnapshotService.instance.refresh();
      if (location != null) {
        await hikerCircleRepository.recordLocationPoint(
          session: widget.session,
          activeHike: liveHike,
          location: location,
          pointType: 'session_start',
        );
      }
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error.message),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }

    setState(() {
      activeHike = liveHike;
      selectedTabIndex = 0;
    });
    _syncFallStillnessMonitor(liveHike);
    tabController.animateTo(0);
  }

  Future<ActiveHikeSession> checkInActiveHike(
    ActiveHikeSession currentHike,
  ) async {
    final location = await LocationSnapshotService.instance.refresh();
    await hikerCircleRepository.recordCheckIn(
      session: widget.session,
      activeHike: currentHike,
      location: location,
    );
    if (location != null) {
      final queuedUpdates = await hikerCircleRepository.recordLocationPoint(
        session: widget.session,
        activeHike: currentHike,
        location: location,
        pointType: 'check_in',
      );
      await hikerCircleRepository.recordNetworkObservation(
        session: widget.session,
        activeHike: currentHike,
        location: location,
        apiRequestSuccess: widget.firebaseBootstrapResult.isAvailable,
      );
      return currentHike.copyWith(
        checkIns: currentHike.checkIns + 1,
        queuedUpdates: queuedUpdates,
      );
    }

    return currentHike.copyWith(
      checkIns: currentHike.checkIns + 1,
      queuedUpdates: currentHike.queuedUpdates + 1,
    );
  }

  Future<ActiveHikeSession> pinCurrentLocation(
    ActiveHikeSession currentHike,
  ) async {
    final location = await LocationSnapshotService.instance.refresh();
    if (location == null) {
      return currentHike.copyWith(
        manualPins: currentHike.manualPins + 1,
        queuedUpdates: currentHike.queuedUpdates + 1,
      );
    }

    final queuedUpdates = await hikerCircleRepository.recordLocationPoint(
      session: widget.session,
      activeHike: currentHike,
      location: location,
      pointType: 'manual',
    );
    await hikerCircleRepository.recordNetworkObservation(
      session: widget.session,
      activeHike: currentHike,
      location: location,
      apiRequestSuccess: widget.firebaseBootstrapResult.isAvailable,
    );
    return currentHike.copyWith(
      manualPins: currentHike.manualPins + 1,
      queuedUpdates: queuedUpdates,
    );
  }

  void openJoinTeamHike() {
    setState(() {
      selectedTabIndex = 3;
    });
    tabController.animateTo(3);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Team hike invitations are in Circle > Teams.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> openEmergencyContacts() async {
    final contacts = await Navigator.of(context).push<List<EmergencyContact>>(
      MaterialPageRoute<List<EmergencyContact>>(
        builder: (context) => EmergencyContactsPage(
          session: widget.session,
          initialContacts: emergencyContacts,
          repository: emergencyContactsRepository,
        ),
      ),
    );

    if (contacts == null || !mounted) {
      return;
    }

    setState(() {
      emergencyContacts = contacts;
      plannedHike = PlannedHike(
        trail: plannedHike.trail,
        plannedStartTime: plannedHike.plannedStartTime,
        expectedReturnTime: plannedHike.expectedReturnTime,
        weatherCached: plannedHike.weatherCached,
        offlineMapDownloaded: plannedHike.offlineMapDownloaded,
        emergencyContactsSelected: contacts.isNotEmpty,
        checklistCompleted: plannedHike.checklistCompleted,
        checklistTotal: plannedHike.checklistTotal,
        phoneBatteryLevel: plannedHike.phoneBatteryLevel,
        liveLocationConfigured: plannedHike.liveLocationConfigured,
      );
    });
  }

  void openTrailDetail(Trail trail) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrailDetailPage(
          session: widget.session,
          hikerCircleRepository: hikerCircleRepository,
          trail: trail,
          isOfflineDownloaded:
              trail.offlineMapDownloaded ||
              (plannedHike.trail.trailId == trail.trailId &&
                  plannedHike.offlineMapDownloaded),
          onMapDownloaded: () => markPlannedMapDownloaded(trail),
          onStartHike: openStartHikeWizard,
        ),
      ),
    );
  }

  void markPlannedMapDownloaded(Trail trail) {
    if (plannedHike.trail.trailId != trail.trailId) {
      return;
    }

    setState(() {
      plannedHike = PlannedHike(
        trail: plannedHike.trail,
        plannedStartTime: plannedHike.plannedStartTime,
        expectedReturnTime: plannedHike.expectedReturnTime,
        weatherCached: plannedHike.weatherCached,
        offlineMapDownloaded: true,
        emergencyContactsSelected: plannedHike.emergencyContactsSelected,
        checklistCompleted: plannedHike.checklistCompleted,
        checklistTotal: plannedHike.checklistTotal,
        phoneBatteryLevel: plannedHike.phoneBatteryLevel,
        liveLocationConfigured: plannedHike.liveLocationConfigured,
      );
    });
    unawaited(
      hikerCircleRepository.recordOfflineMapDownloaded(
        session: widget.session,
        trail: trail,
      ),
    );
  }

  void openSosTab() {
    setState(() {
      selectedTabIndex = 2;
    });
    tabController.animateTo(2);
  }

  void requestManualSos() {
    setState(() {
      selectedTabIndex = 2;
      manualSosRequestId += 1;
    });
    tabController.animateTo(2);
  }

  Widget pageFor(HikerBottomNavDestination tab) {
    switch (tab.label) {
      case 'Home':
        return HomeDashboardPage(
          phoneNumber: widget.session.phoneNumber,
          plannedHike: plannedHike,
          activeHike: activeHike,
          onStartHike: openStartHikeWizard,
          onJoinTeamHike: openJoinTeamHike,
          onOpenEmergencyContacts: () => unawaited(openEmergencyContacts()),
          onOpenTrailDetail: openTrailDetail,
          onOpenSosTab: openSosTab,
          onTriggerManualSos: requestManualSos,
          onActiveHikeChanged: (updatedHike) {
            setState(() {
              activeHike = updatedHike;
            });
          },
          onCheckInRequested: checkInActiveHike,
          onPinLocationRequested: pinCurrentLocation,
          onEndHike: () {
            final hikeToEnd = activeHike;
            if (hikeToEnd != null) {
              unawaited(
                hikerCircleRepository.endHikeSession(
                  session: widget.session,
                  activeHike: hikeToEnd,
                ),
              );
              unawaited(
                hikerCircleRepository.createCompletedHikePost(
                  session: widget.session,
                  activeHike: hikeToEnd,
                ),
              );
            }
            unawaited(fallStillnessMonitor.stop());
            unawaited(_sosDeviceAlertService.stopSpokenPrompt());
            unawaited(_sosDeviceAlertService.stopManualSosPattern());
            isFallStillnessLocalAlarmActive = false;
            setState(() {
              activeHike = null;
            });
          },
          fallStillnessSnapshot: fallStillnessMonitor.snapshot,
          onCancelFallStillnessSos: () =>
              _cancelFallStillnessSos('Phone tap response received'),
        );
      case 'Trail':
        return TrailPage(
          session: widget.session,
          hikerCircleRepository: hikerCircleRepository,
          initialTrails: trails,
          onStartHike: openStartHikeWizard,
        );
      case 'SOS':
        return SosPage(
          session: widget.session,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
          manualSosRequestId: manualSosRequestId,
        );
      case 'Circle':
        return CirclePage(
          session: widget.session,
          activeHike: activeHike,
          hikerCircleRepository: hikerCircleRepository,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
      case 'Profile':
        return MePage(
          session: widget.session,
          phoneNumber: widget.session.phoneNumber,
          onSignOut: widget.onSignOut,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      fallStillnessCountdownWasBackgrounded =
          fallStillnessMonitor.isAwaitingResponse;
      return;
    }

    if (state == AppLifecycleState.resumed &&
        fallStillnessCountdownWasBackgrounded &&
        fallStillnessMonitor.isAwaitingResponse) {
      fallStillnessCountdownWasBackgrounded = false;
      _cancelFallStillnessSos('App opened');
    }
  }

  void _handleFallStillnessMonitorChanged() {
    if (!mounted) {
      return;
    }

    final status = fallStillnessMonitor.snapshot.status;
    final didStartCountdown =
        status == FallStillnessMonitorStatus.awaitingResponse &&
        lastFallStillnessStatus != FallStillnessMonitorStatus.awaitingResponse;
    lastFallStillnessStatus = status;

    setState(() {});

    if (didStartCountdown) {
      unawaited(_handleFallStillnessCountdownStarted());
    }
  }

  Future<void> _handleFallStillnessCountdownStarted() async {
    unawaited(HapticFeedback.heavyImpact());
    try {
      await _sosDeviceAlertService.startManualSosPattern();
      isFallStillnessLocalAlarmActive = true;
    } catch (_) {
      _showFallStillnessSnackBar(
        'Fall SOS countdown started, but the phone alarm or flashlight could not start.',
        isError: true,
      );
    }
    unawaited(
      _sosDeviceAlertService.speakFallStillnessPrompt(
        message: _fallStillnessPrompt,
      ),
    );

    if (!mounted || isFallStillnessDialogVisible) {
      return;
    }

    isFallStillnessDialogVisible = true;
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _FallStillnessCountdownDialog(
          monitor: fallStillnessMonitor,
          onCancel: () =>
              _cancelFallStillnessSos('Phone tap response received'),
        );
      },
    );
    isFallStillnessDialogVisible = false;
  }

  Future<void> _handleFallStillnessEmergencyReady(
    FallStillnessMonitorSnapshot snapshot,
  ) async {
    fallStillnessCancelTaps.clear();
    unawaited(_sosDeviceAlertService.stopSpokenPrompt());
    await _triggerFallStillnessSos(snapshot);
  }

  Future<void> _triggerFallStillnessSos(
    FallStillnessMonitorSnapshot snapshot,
  ) async {
    if (isSendingFallStillnessSos) {
      return;
    }

    isSendingFallStillnessSos = true;
    var didStartLocalAlarm = isFallStillnessLocalAlarmActive;
    if (!didStartLocalAlarm) {
      try {
        await _sosDeviceAlertService.startManualSosPattern();
        didStartLocalAlarm = true;
        isFallStillnessLocalAlarmActive = true;
      } catch (_) {
        _showFallStillnessSnackBar(
          'Fall SOS detected, but the phone alarm or flashlight could not start.',
          isError: true,
        );
      }
    }

    try {
      final triggerLocation = await _captureTriggerLocation();
      final result = await sosAlertRepository.triggerAlert(
        session: widget.session,
        mode: SosAlertMode.fallStillness,
        triggeredAt: snapshot.triggeredAt ?? DateTime.now().toUtc(),
        triggerLocation: triggerLocation,
        contacts: emergencyContacts,
      );
      _showFallStillnessSnackBar(
        _messageForSosResult(result),
        includeStopAlarmAction: didStartLocalAlarm,
      );
    } on SosAlertRepositoryException catch (error) {
      _showFallStillnessSnackBar(
        didStartLocalAlarm
            ? 'Fall SOS local alarm started, but network alert failed: ${error.message}'
            : 'Fall SOS could not be sent: ${error.message}',
        isError: true,
        includeStopAlarmAction: didStartLocalAlarm,
      );
    } catch (_) {
      _showFallStillnessSnackBar(
        didStartLocalAlarm
            ? 'Fall SOS local alarm started, but contact notification failed.'
            : 'Fall SOS could not be sent.',
        isError: true,
        includeStopAlarmAction: didStartLocalAlarm,
      );
    } finally {
      isSendingFallStillnessSos = false;
    }
  }

  Future<SosTriggerLocation?> _captureTriggerLocation() async {
    try {
      return LocationSnapshotService.instance.latestLocation ??
          await LocationSnapshotService.instance.refresh();
    } catch (_) {
      return null;
    }
  }

  String _messageForSosResult(SosAlertResult result) {
    final alert = result.alert;
    if (alert.status == SosAlertStatus.noContacts) {
      return 'Fall SOS logged, but no emergency contacts are saved.';
    }
    if (alert.status == SosAlertStatus.sent) {
      return 'Fall SOS sent to ${alert.sentCount} contacts.';
    }
    if (alert.status == SosAlertStatus.partial) {
      return 'Fall SOS sent to ${alert.sentCount} contacts; ${alert.failedCount} failed.';
    }
    return 'Fall SOS could not be sent to your contacts.';
  }

  void _showFallStillnessSnackBar(
    String message, {
    bool isError = false,
    bool includeStopAlarmAction = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFE11D48)
              : const Color(0xFF34A853),
          action: includeStopAlarmAction
              ? SnackBarAction(
                  label: 'Stop alarm',
                  textColor: Colors.white,
                  onPressed: () {
                    isFallStillnessLocalAlarmActive = false;
                    unawaited(_sosDeviceAlertService.stopManualSosPattern());
                  },
                )
              : null,
        ),
      );
  }

  void _syncFallStillnessMonitor(ActiveHikeSession? hike) {
    if (hike == null || !hike.draft.fallDetectionEnabled) {
      unawaited(fallStillnessMonitor.stop());
      return;
    }

    unawaited(fallStillnessMonitor.start(hike.draft.fallDetectionSettings));
  }

  void _recordFallStillnessCancelTap() {
    if (!fallStillnessMonitor.isAwaitingResponse) {
      fallStillnessCancelTaps.clear();
      return;
    }

    final now = DateTime.now();
    fallStillnessCancelTaps.removeWhere(
      (tapTime) => now.difference(tapTime) > const Duration(seconds: 2),
    );
    fallStillnessCancelTaps.add(now);
    if (fallStillnessCancelTaps.length >= 3) {
      fallStillnessCancelTaps.clear();
      _cancelFallStillnessSos('Triple tap received');
    }
  }

  void _cancelFallStillnessSos(String reason) {
    fallStillnessMonitor.cancelPendingEmergency(reason);
    fallStillnessCancelTaps.clear();
    unawaited(_sosDeviceAlertService.stopSpokenPrompt());
    unawaited(_sosDeviceAlertService.stopManualSosPattern());
    isFallStillnessLocalAlarmActive = false;
    _showFallStillnessSnackBar('$reason. Fall SOS countdown cancelled.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    fallStillnessMonitor.removeListener(_handleFallStillnessMonitorChanged);
    fallStillnessMonitor.dispose();
    unawaited(_sosDeviceAlertService.stopSpokenPrompt());
    unawaited(_sosDeviceAlertService.stopManualSosPattern());
    tabController.removeListener(updateTabIndex);
    _deepLinkChannel.setMethodCallHandler(null);
    tabController.dispose();
    LocationSnapshotService.instance.stop();
    LiveLocationSharingService.instance.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _recordFallStillnessCancelTap(),
        child: TabBarView(
          controller: tabController,
          children: tabs.map(pageFor).toList(),
        ),
      ),
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: selectedTabIndex,
        onDestinationSelected: onTabTap,
      ),
    );
  }
}

class _FallStillnessCountdownDialog extends StatelessWidget {
  const _FallStillnessCountdownDialog({
    required this.monitor,
    required this.onCancel,
  });

  final FallStillnessMonitor monitor;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        final snapshot = monitor.snapshot;
        if (snapshot.status != FallStillnessMonitorStatus.awaitingResponse) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }

        final seconds = snapshot.secondsRemaining ?? 0;
        final settings = snapshot.settings;
        final totalSeconds = settings?.stillnessDuration.inSeconds ?? seconds;
        final progress = totalSeconds <= 0
            ? 0.0
            : 1 - (seconds / totalSeconds).clamp(0, 1);

        return CupertinoAlertDialog(
          title: const Text('Possible Fall Detected'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                const Text(
                  'Are you okay? Do you need help? Triple-tap the phone or cancel below to stop SOS.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Fall SOS in $seconds seconds',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 3,
                  color: const Color(0xFFE11D48),
                  backgroundColor: const Color(0xFFFFE4E6),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: onCancel,
              child: const Text('I am OK - Cancel SOS'),
            ),
          ],
        );
      },
    );
  }
}

String _profileHandleForPhone(String phoneNumber) {
  final digits = phoneNumber.replaceAll(RegExp('[^0-9]'), '');
  if (digits.length <= 4) {
    return 'hiker$digits';
  }
  return 'hiker${digits.substring(digits.length - 4)}';
}
