import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

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
import '../Data/active_hike_live_status_service.dart';
import '../Model/hike_session_models.dart';
import '../ModelView/fall_stillness_monitor.dart';
import 'active_hike_map_page.dart';
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
  static const Duration _minimumActiveHikeRecordingInterval = Duration(
    seconds: 5,
  );
  static const Duration _activeHikeLiveStatusThrottle = Duration(seconds: 20);
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
  final ActiveHikeLiveStatusService _activeHikeLiveStatusService =
      const ActiveHikeLiveStatusService();
  late PlannedHike plannedHike;
  bool isLoadingLiveData = false;
  bool isSendingFallStillnessSos = false;
  bool isRecordingActiveHikeLocation = false;
  bool isFallStillnessDialogVisible = false;
  bool isFallStillnessLocalAlarmActive = false;
  bool fallStillnessCountdownWasBackgrounded = false;
  Timer? activeHikeRecordingTimer;
  Timer? batteryLevelTimer;
  String? activeHikeRecordingSessionId;
  Duration? activeHikeRecordingInterval;
  DateTime? lastActiveHikeLocationRecordedAt;
  DateTime? lastActiveHikeLiveStatusSentAt;
  HikeCoordinate? stationaryWatchReferenceLocation;
  DateTime? stationaryWatchStartedAt;
  bool isStationaryLocationWatchActive = false;
  FallStillnessMonitorStatus lastFallStillnessStatus =
      FallStillnessMonitorStatus.inactive;
  ActiveHikeSession? activeHike;
  int selectedTabIndex = 0;
  int manualSosRequestId = 0;
  int immediateSosRequestId = 0;
  SosAlertMode? immediateSosRequestMode;
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
    unawaited(_refreshBatteryLevel());
    batteryLevelTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshBatteryLevel());
    });
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
    if (uri.host == 'sos' && uri.path == '/instant') {
      requestImmediateSos(SosAlertMode.manual);
      return;
    }
    if (uri.host == 'sos' && uri.path == '/medical') {
      requestImmediateSos(SosAlertMode.medical);
      return;
    }
    if (uri.host == 'sos' && uri.path == '/duress') {
      requestImmediateSos(SosAlertMode.duress);
      return;
    }
    if (uri.host == 'hike' && uri.path == '/active') {
      _openActiveHikeDetailsFromDeepLink();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/check-in') {
      _checkInFromLiveStatusAction();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/pin') {
      _pinLocationFromLiveStatusAction();
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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

  Future<int> _readBatteryLevel({required int fallback}) async {
    return await _sosDeviceAlertService.getBatteryLevel() ?? fallback;
  }

  Future<void> _refreshBatteryLevel() async {
    final batteryLevel = await _sosDeviceAlertService.getBatteryLevel();
    if (batteryLevel == null || !mounted) {
      return;
    }

    final currentActiveHike = activeHike;
    setState(() {
      plannedHike = PlannedHike(
        trail: plannedHike.trail,
        plannedStartTime: plannedHike.plannedStartTime,
        expectedReturnTime: plannedHike.expectedReturnTime,
        weatherCached: plannedHike.weatherCached,
        offlineMapDownloaded: plannedHike.offlineMapDownloaded,
        emergencyContactsSelected: plannedHike.emergencyContactsSelected,
        checklistCompleted: plannedHike.checklistCompleted,
        checklistTotal: plannedHike.checklistTotal,
        phoneBatteryLevel: batteryLevel,
        liveLocationConfigured: plannedHike.liveLocationConfigured,
      );
      if (currentActiveHike != null) {
        activeHike = currentActiveHike.copyWith(batteryLevel: batteryLevel);
      }
    });

    final updatedActiveHike = activeHike;
    if (updatedActiveHike != null) {
      _syncActiveHikeLiveStatus(updatedActiveHike, force: true);
    }
  }

  ActiveHikeSession _hikeWithRecordedLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location, {
    int? queuedUpdates,
    int? batteryLevel,
    int? checkIns,
  }) {
    final coordinate = HikeCoordinate.fromTriggerLocation(location);
    final routePoints = List<HikeCoordinate>.of(hike.routePoints);
    final shouldAppendPoint =
        routePoints.isEmpty || routePoints.last.distanceTo(coordinate) > 2;
    if (shouldAppendPoint) {
      routePoints.add(coordinate);
    }

    return hike.copyWith(
      batteryLevel: batteryLevel,
      queuedUpdates: queuedUpdates,
      checkIns: checkIns,
      latestLocation: coordinate,
      routePoints: routePoints,
    );
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

    final startProgress = ValueNotifier<_HikeStartProgress>(
      const _HikeStartProgress(
        title: 'Starting hike session',
        message: 'Preparing your hike safety tools.',
        progress: 0.18,
        icon: Icons.hiking_rounded,
      ),
    );
    Timer? startProgressDelayTimer;
    Future<void>? startProgressDialogFuture;
    var isStartProgressDialogOpen = false;
    startProgressDelayTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      isStartProgressDialogOpen = true;
      startProgressDialogFuture =
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return _HikeStartProgressDialog(progress: startProgress);
            },
          ).whenComplete(() {
            isStartProgressDialogOpen = false;
          });
      unawaited(startProgressDialogFuture);
    });

    void closeStartProgressDialog() {
      startProgressDelayTimer?.cancel();
      if (isStartProgressDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      final dialogFuture = startProgressDialogFuture;
      if (dialogFuture == null) {
        startProgress.dispose();
      } else {
        unawaited(dialogFuture.whenComplete(startProgress.dispose));
      }
    }

    ActiveHikeSession liveHike = startedHike;
    try {
      startProgress.value = const _HikeStartProgress(
        title: 'Creating hike session',
        message: 'Saving your active hike and emergency settings.',
        progress: 0.38,
        icon: Icons.route_rounded,
      );
      liveHike = await hikerCircleRepository.createActiveHikeSession(
        session: widget.session,
        draft: startedHike.draft,
      );
      final batteryLevel = await _readBatteryLevel(
        fallback: liveHike.batteryLevel,
      );
      liveHike = liveHike.copyWith(
        batteryLevel: batteryLevel,
        batteryStartedLevel: batteryLevel,
      );
      startProgress.value = const _HikeStartProgress(
        title: 'Activating live tracking',
        message: 'Starting fall detection and live hike status.',
        progress: 0.72,
        icon: Icons.sensors_rounded,
      );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      startProgress.value = const _HikeStartProgress(
        title: 'Starting offline mode',
        message: 'Cloud setup is unavailable, so this hike will run locally.',
        progress: 0.72,
        icon: Icons.cloud_off_rounded,
      );
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

    if (!mounted) {
      closeStartProgressDialog();
      return;
    }

    startProgress.value = const _HikeStartProgress(
      title: 'Opening hike dashboard',
      message: 'The first GPS point will be saved in the background.',
      progress: 1,
      icon: Icons.check_circle_rounded,
    );
    setState(() {
      activeHike = liveHike;
      selectedTabIndex = 0;
    });
    _syncActiveHikeServices(liveHike, forceLiveStatus: true);
    tabController.animateTo(0);
    closeStartProgressDialog();
    unawaited(_recordInitialActiveHikeLocation(liveHike));
  }

  Future<void> _recordInitialActiveHikeLocation(ActiveHikeSession hike) async {
    try {
      final location =
          LocationSnapshotService.instance.latestLocation ??
          await LocationSnapshotService.instance.refresh();
      if (location == null) {
        return;
      }
      final batteryLevel = await _readBatteryLevel(fallback: hike.batteryLevel);

      final queuedUpdates = await hikerCircleRepository.recordLocationPoint(
        session: widget.session,
        activeHike: hike,
        location: location,
        pointType: 'session_start',
        batteryLevel: batteryLevel,
      );
      if (!mounted) {
        return;
      }

      final latestHike = activeHike;
      if (latestHike == null || latestHike.sessionId != hike.sessionId) {
        return;
      }

      lastActiveHikeLocationRecordedAt = DateTime.now();
      final updatedHike = _hikeWithRecordedLocation(
        latestHike,
        location,
        queuedUpdates: queuedUpdates,
        batteryLevel: batteryLevel,
      );
      setState(() {
        activeHike = updatedHike;
      });
      _syncActiveHikeLiveStatus(updatedHike, force: true);
    } catch (_) {
      // The periodic active-hike recorder will try again at the configured
      // interval, so startup should never stall on the first GPS point.
    }
  }

  Future<ActiveHikeSession> checkInActiveHike(
    ActiveHikeSession currentHike,
  ) async {
    final location = await LocationSnapshotService.instance.refresh();
    final batteryLevel = await _readBatteryLevel(
      fallback: currentHike.batteryLevel,
    );
    final hikeWithBattery = currentHike.copyWith(batteryLevel: batteryLevel);
    await hikerCircleRepository.recordCheckIn(
      session: widget.session,
      activeHike: hikeWithBattery,
      location: location,
    );
    if (location != null) {
      final queuedUpdates = await hikerCircleRepository.recordLocationPoint(
        session: widget.session,
        activeHike: hikeWithBattery,
        location: location,
        pointType: 'check_in',
        batteryLevel: batteryLevel,
      );
      await hikerCircleRepository.recordNetworkObservation(
        session: widget.session,
        activeHike: hikeWithBattery,
        location: location,
        apiRequestSuccess: widget.firebaseBootstrapResult.isAvailable,
      );
      return _hikeWithRecordedLocation(
        hikeWithBattery,
        location,
        checkIns: currentHike.checkIns + 1,
        queuedUpdates: queuedUpdates,
      );
    }

    return hikeWithBattery.copyWith(
      checkIns: currentHike.checkIns + 1,
      queuedUpdates: currentHike.queuedUpdates + 1,
    );
  }

  Future<PinLocationResult> pinCurrentLocation(
    ActiveHikeSession currentHike,
  ) async {
    final location = await LocationSnapshotService.instance.refresh();
    final batteryLevel = await _readBatteryLevel(
      fallback: currentHike.batteryLevel,
    );
    final hikeWithBattery = currentHike.copyWith(batteryLevel: batteryLevel);
    if (location == null) {
      return PinLocationResult(
        hike: hikeWithBattery,
        status: PinLocationStatus.unavailable,
      );
    }

    final coordinate = HikeCoordinate.fromTriggerLocation(location);
    if (hikeWithBattery.hasPinnedNear(coordinate)) {
      return PinLocationResult(
        hike: hikeWithBattery.copyWith(latestLocation: coordinate),
        status: PinLocationStatus.duplicate,
      );
    }

    final queuedUpdates = await hikerCircleRepository.recordLocationPoint(
      session: widget.session,
      activeHike: hikeWithBattery,
      location: location,
      pointType: 'manual_pin',
      batteryLevel: batteryLevel,
    );
    await hikerCircleRepository.recordNetworkObservation(
      session: widget.session,
      activeHike: hikeWithBattery,
      location: location,
      apiRequestSuccess: widget.firebaseBootstrapResult.isAvailable,
    );
    final nextPins = [
      ...hikeWithBattery.manualPinLocations,
      HikeManualPin(
        id: 'pin_${DateTime.now().microsecondsSinceEpoch}',
        coordinate: coordinate,
        pinnedAt: DateTime.now().toUtc(),
      ),
    ];
    final updatedHike = _hikeWithRecordedLocation(
      hikeWithBattery,
      location,
      queuedUpdates: queuedUpdates,
      batteryLevel: batteryLevel,
    ).copyWith(manualPins: nextPins.length, manualPinLocations: nextPins);
    return PinLocationResult(
      hike: updatedHike,
      status: PinLocationStatus.pinned,
    );
  }

  void _openActiveHikeDetailsFromDeepLink() {
    final hike = activeHike;
    if (hike == null) {
      _showNoActiveHikeSnackBar();
      return;
    }

    setState(() {
      selectedTabIndex = 0;
    });
    tabController.animateTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ActiveHikeMapPage(activeHike: hike),
        ),
      );
    });
  }

  void _checkInFromLiveStatusAction() {
    final hike = activeHike;
    if (hike == null) {
      _showNoActiveHikeSnackBar();
      return;
    }

    setState(() {
      selectedTabIndex = 0;
    });
    tabController.animateTo(0);
    unawaited(_applyLiveStatusCheckIn(hike));
  }

  Future<void> _applyLiveStatusCheckIn(ActiveHikeSession hike) async {
    final updatedHike = await checkInActiveHike(hike);
    if (!mounted) {
      return;
    }

    setState(() {
      activeHike = updatedHike;
    });
    _syncActiveHikeServices(updatedHike, forceLiveStatus: true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Check-in saved from live hike status.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _pinLocationFromLiveStatusAction() {
    final hike = activeHike;
    if (hike == null) {
      _showNoActiveHikeSnackBar();
      return;
    }

    setState(() {
      selectedTabIndex = 0;
    });
    tabController.animateTo(0);
    unawaited(_applyLiveStatusPin(hike));
  }

  Future<void> _applyLiveStatusPin(ActiveHikeSession hike) async {
    final result = await pinCurrentLocation(hike);
    if (!mounted) {
      return;
    }

    setState(() {
      activeHike = result.hike;
    });
    _syncActiveHikeServices(result.hike, forceLiveStatus: true);
    final message = switch (result.status) {
      PinLocationStatus.pinned => 'Checkpoint pinned from live hike status.',
      PinLocationStatus.duplicate => 'This location is already pinned before.',
      PinLocationStatus.unavailable =>
        'GPS is unavailable, so no pin was added.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _showNoActiveHikeSnackBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No active hike session is running.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
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

  void requestImmediateSos(SosAlertMode mode) {
    setState(() {
      selectedTabIndex = 2;
      immediateSosRequestMode = mode;
      immediateSosRequestId += 1;
    });
    tabController.animateTo(2);
  }

  Future<void> _endActiveHikeSession() async {
    final hikeToEnd = activeHike;
    if (hikeToEnd == null) {
      return;
    }

    final endedAt = DateTime.now();
    final report = HikeSummaryReport.fromActiveHike(
      activeHike: hikeToEnd,
      endedAt: endedAt,
    );

    try {
      await hikerCircleRepository.endHikeSession(
        session: widget.session,
        activeHike: hikeToEnd,
        summary: report,
      );
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

    await fallStillnessMonitor.stop();
    try {
      await _sosDeviceAlertService.stopSpokenPrompt();
      await _sosDeviceAlertService.stopManualSosPattern();
    } catch (_) {
      // Native safety outputs are best effort when ending a hike.
    }
    _syncActiveHikeServices(null);
    isFallStillnessLocalAlarmActive = false;
    if (!mounted) {
      return;
    }

    setState(() {
      activeHike = null;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return _HikeSummaryReportPage(
            report: report,
            onShareReportText: () => _sosDeviceAlertService.shareText(
              subject: 'Hike summary: ${report.trailName}',
              text: report.shareText,
            ),
            onShareToCommunity: () async {
              await hikerCircleRepository.createCompletedHikePost(
                session: widget.session,
                activeHike: hikeToEnd,
                summary: report,
                caption: report.shareText,
              );
            },
          );
        },
      ),
    );
  }

  Widget pageFor(HikerBottomNavDestination tab) {
    switch (tab.label) {
      case 'Home':
        return HomeDashboardPage(
          phoneNumber: widget.session.phoneNumber,
          plannedHike: plannedHike,
          activeHike: activeHike,
          isVisible: selectedTabIndex == 0,
          onStartHike: openStartHikeWizard,
          onJoinTeamHike: openJoinTeamHike,
          onOpenEmergencyContacts: () => unawaited(openEmergencyContacts()),
          onOpenTrailDetail: openTrailDetail,
          onOpenSosTab: openSosTab,
          onActiveHikeChanged: (updatedHike) {
            setState(() {
              activeHike = updatedHike;
            });
            _syncActiveHikeServices(updatedHike, forceLiveStatus: true);
          },
          onCheckInRequested: checkInActiveHike,
          onPinLocationRequested: pinCurrentLocation,
          onEndHike: () => unawaited(_endActiveHikeSession()),
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
          immediateSosRequestId: immediateSosRequestId,
          immediateSosMode: immediateSosRequestMode,
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
      _pauseActiveHikeLocationRecording();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final hike = activeHike;
      if (hike != null) {
        _startActiveHikeLocationRecording(hike);
        if (_isActiveHikeLocationRecordDue(hike)) {
          unawaited(_recordActiveHikeLocationTick(force: true));
        }
      }

      if (fallStillnessCountdownWasBackgrounded &&
          fallStillnessMonitor.isAwaitingResponse) {
        fallStillnessCountdownWasBackgrounded = false;
        _cancelFallStillnessSos('App opened');
      }
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

  void _syncActiveHikeServices(
    ActiveHikeSession? hike, {
    bool forceLiveStatus = false,
  }) {
    _syncFallStillnessMonitor(hike);
    if (hike == null) {
      _stopActiveHikeLocationRecording();
      unawaited(_activeHikeLiveStatusService.stop());
      return;
    }

    _startActiveHikeLocationRecording(hike);
    _syncActiveHikeLiveStatus(hike, force: forceLiveStatus);
  }

  void _startActiveHikeLocationRecording(ActiveHikeSession hike) {
    final interval = _effectiveActiveHikeRecordingInterval(hike);
    final monitorInterval = interval < const Duration(seconds: 30)
        ? interval
        : const Duration(seconds: 30);
    final isSameRecordingLoop =
        activeHikeRecordingTimer?.isActive == true &&
        activeHikeRecordingSessionId == hike.sessionId &&
        activeHikeRecordingInterval == interval;
    if (isSameRecordingLoop) {
      return;
    }

    activeHikeRecordingTimer?.cancel();
    activeHikeRecordingSessionId = hike.sessionId;
    activeHikeRecordingInterval = interval;
    stationaryWatchReferenceLocation = null;
    stationaryWatchStartedAt = null;
    isStationaryLocationWatchActive = false;
    LocationSnapshotService.instance.setRefreshInterval(
      _snapshotIntervalForActiveHike(interval),
    );
    activeHikeRecordingTimer = Timer.periodic(monitorInterval, (_) {
      unawaited(_recordActiveHikeLocationTick());
    });
  }

  void _pauseActiveHikeLocationRecording() {
    activeHikeRecordingTimer?.cancel();
    activeHikeRecordingTimer = null;
  }

  void _stopActiveHikeLocationRecording() {
    activeHikeRecordingTimer?.cancel();
    activeHikeRecordingTimer = null;
    activeHikeRecordingSessionId = null;
    activeHikeRecordingInterval = null;
    lastActiveHikeLocationRecordedAt = null;
    lastActiveHikeLiveStatusSentAt = null;
    stationaryWatchReferenceLocation = null;
    stationaryWatchStartedAt = null;
    isStationaryLocationWatchActive = false;
    LocationSnapshotService.instance.setRefreshInterval(
      LiveLocationSharingService.instance.isActive
          ? LocationSnapshotService.liveSnapshotInterval
          : LocationSnapshotService.passiveSnapshotInterval,
    );
    isRecordingActiveHikeLocation = false;
  }

  Duration _snapshotIntervalForActiveHike(Duration recordingInterval) {
    if (LiveLocationSharingService.instance.isActive) {
      return LocationSnapshotService.liveSnapshotInterval;
    }
    return recordingInterval;
  }

  Duration _effectiveActiveHikeRecordingInterval(ActiveHikeSession hike) {
    final configured = hike.draft.locationRecordingInterval;
    if (configured < _minimumActiveHikeRecordingInterval) {
      return _minimumActiveHikeRecordingInterval;
    }
    return configured;
  }

  bool _isActiveHikeLocationRecordDue(ActiveHikeSession hike) {
    final lastRecordedAt = lastActiveHikeLocationRecordedAt;
    if (lastRecordedAt == null) {
      return true;
    }

    return DateTime.now().difference(lastRecordedAt) >=
        _effectiveActiveHikeRecordingInterval(hike);
  }

  Future<void> _recordActiveHikeLocationTick({bool force = false}) async {
    final hike = activeHike;
    if (hike == null || isRecordingActiveHikeLocation) {
      return;
    }

    final shouldRecord = force || _isActiveHikeLocationRecordDue(hike);
    if (!shouldRecord && !hike.draft.fallDetectionEnabled) {
      return;
    }

    isRecordingActiveHikeLocation = true;
    final sessionId = hike.sessionId;
    var didRecordLocation = false;
    try {
      final location = await LocationSnapshotService.instance.refresh();
      if (location == null) {
        return;
      }
      final coordinate = HikeCoordinate.fromTriggerLocation(location);
      _evaluateStationaryLocationWatch(hike, coordinate);
      if (!shouldRecord) {
        return;
      }

      final batteryLevel = await _readBatteryLevel(fallback: hike.batteryLevel);

      final queuedUpdates = await hikerCircleRepository.recordLocationPoint(
        session: widget.session,
        activeHike: hike,
        location: location,
        pointType: 'tracking',
        batteryLevel: batteryLevel,
      );
      if (!mounted) {
        return;
      }

      final latestHike = activeHike;
      if (latestHike == null || latestHike.sessionId != sessionId) {
        return;
      }

      final updatedHike = _hikeWithRecordedLocation(
        latestHike,
        location,
        queuedUpdates: queuedUpdates,
        batteryLevel: batteryLevel,
      );
      setState(() {
        activeHike = updatedHike;
      });
      _syncActiveHikeLiveStatus(updatedHike, force: true);
      didRecordLocation = true;
    } finally {
      if (didRecordLocation) {
        lastActiveHikeLocationRecordedAt = DateTime.now();
      }
      isRecordingActiveHikeLocation = false;
    }
  }

  void _evaluateStationaryLocationWatch(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
  ) {
    const stationaryMovementThresholdMeters = 5.0;
    const stationaryTriggerDuration = Duration(minutes: 3);
    final now = DateTime.now();
    final reference = stationaryWatchReferenceLocation;
    final movedEnough =
        reference == null ||
        reference.distanceTo(coordinate) > stationaryMovementThresholdMeters;

    if (movedEnough) {
      stationaryWatchReferenceLocation = coordinate;
      stationaryWatchStartedAt = now;
      if (isStationaryLocationWatchActive) {
        fallStillnessMonitor.cancelStationaryLocationWatch(
          'New location recorded',
        );
        isStationaryLocationWatchActive = false;
      }
      return;
    }

    stationaryWatchStartedAt ??= now;
    if (isStationaryLocationWatchActive ||
        now.difference(stationaryWatchStartedAt!) < stationaryTriggerDuration) {
      return;
    }

    fallStillnessMonitor.beginStationaryLocationWatch(
      hike.draft.fallDetectionSettings,
    );
    isStationaryLocationWatchActive = true;
  }

  void _syncActiveHikeLiveStatus(ActiveHikeSession hike, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        lastActiveHikeLiveStatusSentAt != null &&
        now.difference(lastActiveHikeLiveStatusSentAt!) <
            _activeHikeLiveStatusThrottle) {
      return;
    }

    lastActiveHikeLiveStatusSentAt = now;
    unawaited(_activeHikeLiveStatusService.startOrUpdate(hike));
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
    _stopActiveHikeLocationRecording();
    batteryLevelTimer?.cancel();
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

class _HikeStartProgress {
  const _HikeStartProgress({
    required this.title,
    required this.message,
    required this.progress,
    required this.icon,
  });

  final String title;
  final String message;
  final double progress;
  final IconData icon;
}

class _HikeStartProgressDialog extends StatelessWidget {
  const _HikeStartProgressDialog({required this.progress});

  final ValueListenable<_HikeStartProgress> progress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: ValueListenableBuilder<_HikeStartProgress>(
            valueListenable: progress,
            builder: (context, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulsingHikeIcon(icon: value.icon),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Column(
                      key: ValueKey(value.title),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          value.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF111111),
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          value.message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: const Color(0xFF6E6E73),
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: value.progress.clamp(0, 1).toDouble(),
                      minHeight: 6,
                      color: const Color(0xFF34A853),
                      backgroundColor: const Color(0xFFEAF7EE),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Keep HikerCircle open for a moment.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF6E6E73),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PulsingHikeIcon extends StatefulWidget {
  const _PulsingHikeIcon({required this.icon});

  final IconData icon;

  @override
  State<_PulsingHikeIcon> createState() => _PulsingHikeIconState();
}

class _PulsingHikeIconState extends State<_PulsingHikeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.94,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: Color(0xFFEAF7EE),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFF34A853),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class _HikeSummaryReportPage extends StatefulWidget {
  const _HikeSummaryReportPage({
    required this.report,
    required this.onShareToCommunity,
    required this.onShareReportText,
  });

  final HikeSummaryReport report;
  final Future<void> Function() onShareToCommunity;
  final Future<void> Function() onShareReportText;

  @override
  State<_HikeSummaryReportPage> createState() => _HikeSummaryReportPageState();
}

class _HikeSummaryReportPageState extends State<_HikeSummaryReportPage> {
  bool _isSharingCommunity = false;

  Future<void> _shareToCommunity() async {
    if (_isSharingCommunity) {
      return;
    }

    setState(() {
      _isSharingCommunity = true;
    });
    try {
      await widget.onShareToCommunity();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Hike summary shared to community.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
            content: Text('Unable to share this summary right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSharingCommunity = false;
        });
      }
    }
  }

  Future<void> _shareReportText() async {
    try {
      await widget.onShareReportText();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Share sheet is unavailable on this platform.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Tooltip(
                        message: 'Close',
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size.square(36),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.xmark,
                              color: Color(0xFF34A853),
                              size: 18,
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
                              'Hike Summary',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: const Color(0xFF111111),
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                  ),
                            ),
                            Text(
                              report.trailName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF6E6E73),
                                    letterSpacing: 0,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryMetric(
                                label: 'Distance',
                                value:
                                    '${report.distanceKm.toStringAsFixed(2)} km',
                              ),
                            ),
                            const _SummaryDivider(),
                            Expanded(
                              child: _SummaryMetric(
                                label: 'Duration',
                                value: _formatReportDuration(report.duration),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryMetric(
                                label: 'Check-ins',
                                value: '${report.checkIns}',
                              ),
                            ),
                            const _SummaryDivider(),
                            Expanded(
                              child: _SummaryMetric(
                                label: 'Pins',
                                value: '${report.manualPins}',
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryMetric(
                                label: 'Route Points',
                                value: '${report.routePointCount}',
                              ),
                            ),
                            const _SummaryDivider(),
                            Expanded(
                              child: _SummaryMetric(
                                label: 'Battery',
                                value:
                                    '${report.batteryStartPercent}% -> ${report.batteryEndPercent}%',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SummaryChartCard(report: report),
                  const SizedBox(height: 18),
                  Text(
                    'INSIGHTS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF6E6E73),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SummaryCard(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < report.insights.length;
                          index++
                        ) ...[
                          _InsightRow(text: report.insights[index]),
                          if (index != report.insights.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _isSharingCommunity ? null : _shareToCommunity,
                    icon: _isSharingCommunity
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.groups_2_rounded),
                    label: const Text('Share to Community'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_shareReportText()),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share Report Text'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatReportDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
        child: child,
      ),
    );
  }
}

class _SummaryChartCard extends StatelessWidget {
  const _SummaryChartCard({required this.report});

  final HikeSummaryReport report;

  @override
  Widget build(BuildContext context) {
    final batteryUsed = math.max(
      0,
      report.batteryStartPercent - report.batteryEndPercent,
    );
    final chartValues = [
      _ChartValue('KM', report.distanceKm),
      _ChartValue('HRS', math.max(report.duration.inMinutes / 60, 0.1)),
      _ChartValue('GPS', math.max(report.routePointCount / 10, 0.1)),
      _ChartValue('BAT', math.max(batteryUsed.toDouble(), 0.1)),
    ];
    final maxY =
        chartValues.map((value) => value.amount).reduce(math.max) * 1.25;

    return _SummaryCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hike Stats Chart',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF111111),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  minY: 0,
                  barTouchData: BarTouchData(enabled: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= chartValues.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              chartValues[index].label,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF6E6E73),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < chartValues.length; index++)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: chartValues[index].amount,
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                            color: const Color(0xFF34A853),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'GPS is scaled as points / 10. Battery is percentage used.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6E6E73),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartValue {
  const _ChartValue(this.label, this.amount);

  final String label;
  final double amount;
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF111111),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF6E6E73),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 68,
      child: VerticalDivider(width: 1, thickness: 0.7),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_graph_rounded,
            color: Color(0xFF34A853),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF111111),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
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
