import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../admin/View/admin_page.dart';
import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../circle/View/circle_page.dart';
import '../../me/Data/live_location_sharing_service.dart';
import '../../me/View/me_page.dart';
import '../../navigation/View/hiker_bottom_nav_bar.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Data/location_snapshot_service.dart';
import 'find_hike_page.dart';
import '../../sos/Data/sos_alert_repository.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../../sos/View/ios_sos_volume_guard.dart';
import '../../sos/View/sos_page.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';
import '../Data/active_hike_live_status_service.dart';
import '../Model/hike_session_models.dart';
import 'active_tracking_map_view.dart';
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
  PlannedHike? plannedHike;
  List<UpcomingHike> myUpcomingHikes = const [];
  bool isLoadingLiveData = false;
  bool isSendingFallStillnessSos = false;
  bool isRecordingActiveHikeLocation = false;
  bool isFallStillnessDialogVisible = false;
  bool isFallStillnessLocalAlarmActive = false;
  bool fallStillnessCountdownWasBackgrounded = false;
  Timer? activeHikeRecordingTimer;
  Timer? batteryLevelTimer;
  StreamSubscription<TeamHikeSession?>? teamHikeSessionSubscription;
  String? teamHikeWatchSessionId;
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
  List<EmergencyContact> emergencyContacts = const [];

  late final List<HikerBottomNavDestination> tabs;

  @override
  void initState() {
    super.initState();
    tabs = [
      ...HikerBottomNavBar.standardDestinations,
      if (widget.session.isAdmin)
        const HikerBottomNavDestination(
          label: 'Admin',
          icon: Icons.admin_panel_settings_rounded,
        ),
    ];
    trails = <Trail>[];
    hikerCircleRepository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    unawaited(_loadEmergencyContacts());
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

  Future<void> _loadEmergencyContacts() async {
    try {
      final contacts = await emergencyContactsRepository.loadEmergencyContacts(
        session: widget.session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        emergencyContacts = contacts;
      });
    } catch (_) {
      return;
    }
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
    if (uri.host == 'team-hike' && uri.path == '/join') {
      final teamHikeSessionId = uri.queryParameters['teamSessionId'] ?? '';
      if (teamHikeSessionId.isNotEmpty) {
        unawaited(_openTeamHikeInvite(teamHikeSessionId));
      }
      return;
    }
    if (uri.host == 'team-hike' && uri.path == '/ping') {
      final teamHikeSessionId = uri.queryParameters['teamSessionId'] ?? '';
      if (teamHikeSessionId.isNotEmpty) {
        unawaited(_respondToTeamPing(teamHikeSessionId));
      }
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
      selectedTabIndex = 2;
    });
    tabController.animateTo(2);
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
      if (widget.session.isAdmin) {
        try {
          await hikerCircleRepository.deleteLegacyFirebaseDummyData(
            session: widget.session,
          );
        } catch (_) {
          // Cleanup should not block normal trail loading.
        }
      }
      final liveTrails = await hikerCircleRepository.loadTrails();
      if (!mounted) {
        return;
      }
      setState(() {
        trails
          ..clear()
          ..addAll(liveTrails);
      });
      final upcomingHikes = await hikerCircleRepository.loadMyUpcomingHikes(
        widget.session.phoneNumber,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        myUpcomingHikes = upcomingHikes;
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

  Future<void> addTrailByAdminFromHome() async {
    if (!widget.session.isAdmin) {
      return;
    }

    final trail = await showAddTrailSheet(context);
    if (trail == null || !mounted) {
      return;
    }

    setState(() {
      isLoadingLiveData = true;
    });
    try {
      await hikerCircleRepository.createTrailByAdmin(
        session: widget.session,
        trail: trail,
      );
      await loadLiveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${trail.name} added to Firebase trails.'),
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
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          isLoadingLiveData = false;
        });
      }
    }
  }

  Future<void> editTrailByAdminFromHome(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final updatedTrail = await showEditTrailSheet(context, trail);
    if (updatedTrail == null || !mounted) {
      return;
    }

    setState(() {
      isLoadingLiveData = true;
    });
    try {
      await hikerCircleRepository.updateTrailByAdmin(
        session: widget.session,
        trail: updatedTrail,
      );
      await loadLiveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Trail updated.'),
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
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          isLoadingLiveData = false;
        });
      }
    }
  }

  Future<void> deleteTrailByAdminFromHome(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Delete trail?'),
          content: Text('${trail.name} will be removed from Firebase trails.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      isLoadingLiveData = true;
      if (plannedHike?.trail.trailId == trail.trailId) {
        plannedHike = null;
      }
    });
    try {
      await hikerCircleRepository.deleteTrailByAdmin(
        session: widget.session,
        trail: trail,
      );
      await loadLiveData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${trail.name} deleted.'),
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
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
    final currentPlan = plannedHike;
    setState(() {
      if (currentPlan != null) {
        plannedHike = PlannedHike(
          trail: currentPlan.trail,
          plannedStartTime: currentPlan.plannedStartTime,
          expectedReturnTime: currentPlan.expectedReturnTime,
          weatherCached: currentPlan.weatherCached,
          offlineMapDownloaded: currentPlan.offlineMapDownloaded,
          emergencyContactsSelected: currentPlan.emergencyContactsSelected,
          checklistCompleted: currentPlan.checklistCompleted,
          checklistTotal: currentPlan.checklistTotal,
          phoneBatteryLevel: batteryLevel,
          liveLocationConfigured: currentPlan.liveLocationConfigured,
        );
      }
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
    if (activeHike != null) {
      final visible = _visibleTabs();
      if (index < 0 || index >= visible.length) return;
      final label = visible[index].label;
      final actualIndex = tabs.indexWhere((t) => t.label == label);
      if (actualIndex < 0) return;
      setState(() {
        selectedTabIndex = actualIndex;
      });
      tabController.animateTo(actualIndex);
      return;
    }
    setState(() {
      selectedTabIndex = index;
    });
    tabController.animateTo(index);
  }

  Future<void> openStartHikeWizard([Trail? trail]) async {
    if (trail == null && trails.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No trails are available to start yet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final startedHike = await Navigator.of(context).push<ActiveHikeSession>(
      MaterialPageRoute<ActiveHikeSession>(
        builder: (context) => StartHikeWizardPage(
          preselectedTrail: trail,
          availableTrails: trails,
          repository: hikerCircleRepository,
          session: widget.session,
        ),
      ),
    );

    if (!mounted) return;
    final upcomingHikes = await hikerCircleRepository.loadMyUpcomingHikes(
      widget.session.phoneNumber,
    );
    if (!mounted) return;
    setState(() {
      myUpcomingHikes = upcomingHikes;
    });

    if (startedHike == null) return;
    var hikeToStart = startedHike;
    if (hikeToStart.draft.hikeType == HikeType.team) {
      final teamSession = await _coordinateTeamHikeStart(hikeToStart.draft);
      if (teamSession == null || !mounted) {
        return;
      }
      hikeToStart = hikeToStart.copyWith(
        teamHikeSessionId: teamSession.id,
        teamHikeSession: teamSession,
      );
    }

    if (hikeToStart.draft.fallDetectionEnabled ||
        hikeToStart.draft.offlinePhysicalAlertEnabled) {
      final volumeReady = await ensureIosSosOutputVolumeReady(
        context: context,
        deviceAlertService: _sosDeviceAlertService,
        title: 'Turn Up iPhone Volume',
        message:
            'Fall SOS and offline audio SOS use iPhone media volume for the local alarm. Turn it up before starting your hike.',
        proceedLabel: 'Create Hike',
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

    ActiveHikeSession liveHike = hikeToStart;
    try {
      startProgress.value = const _HikeStartProgress(
        title: 'Creating hike session',
        message: 'Saving your active hike and emergency settings.',
        progress: 0.38,
        icon: Icons.route_rounded,
      );
      liveHike = await hikerCircleRepository.createActiveHikeSession(
        session: widget.session,
        draft: hikeToStart.draft,
        teamHikeSessionId: hikeToStart.teamHikeSessionId,
      );
      liveHike = liveHike.copyWith(
        teamHikeSession: hikeToStart.teamHikeSession,
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

  Future<TeamHikeSession?> _coordinateTeamHikeStart(
    HikeSessionDraft draft,
  ) async {
    TeamHikeSession teamSession;
    try {
      teamSession = await hikerCircleRepository.createTeamHikeSession(
        session: widget.session,
        draft: draft,
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
      return null;
    }

    if (!mounted) {
      return null;
    }

    return Navigator.of(context).push<TeamHikeSession>(
      MaterialPageRoute<TeamHikeSession>(
        fullscreenDialog: true,
        builder: (context) {
          return _TeamHikeLaunchPage(
            session: widget.session,
            repository: hikerCircleRepository,
            initialTeamSession: teamSession,
          );
        },
      ),
    );
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
      _syncTeamHikeLocation(updatedHike, location);
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
      final updatedHike = _hikeWithRecordedLocation(
        hikeWithBattery,
        location,
        checkIns: currentHike.checkIns + 1,
        queuedUpdates: queuedUpdates,
      );
      _syncTeamHikeLocation(updatedHike, location);
      return updatedHike;
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
    _syncTeamHikeLocation(updatedHike, location);
    return PinLocationResult(
      hike: updatedHike,
      status: PinLocationStatus.pinned,
    );
  }

  Future<TeamHikeSession?> _pingTeamMember(String phoneNumber) async {
    final currentHike = activeHike;
    if (currentHike == null || currentHike.teamHikeSessionId.isEmpty) {
      return null;
    }
    try {
      final teamSession = await hikerCircleRepository.pingTeamParticipant(
        session: widget.session,
        teamHikeSessionId: currentHike.teamHikeSessionId,
        participantPhoneNumber: phoneNumber,
      );
      if (mounted) {
        setState(() {
          activeHike = currentHike.copyWith(teamHikeSession: teamSession);
        });
      }
      return teamSession;
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
      return null;
    }
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

  Future<void> _showUpcomingHikeDetails(UpcomingHike hike) async {
    Trail? trail;
    for (final t in trails) {
      if (t.trailId == hike.trailId) {
        trail = t;
        break;
      }
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UpcomingHikeDetailSheet(
        hike: hike,
        trail: trail,
        phoneNumber: widget.session.phoneNumber,
      ),
    );
    if (!mounted) return;
    if (result == 'viewTrail' && trail != null) {
      openTrailDetail(trail);
    } else if (result == 'start' && trail != null) {
      final hikeType = hike.hikeType == 'team' ? HikeType.team : HikeType.solo;
      final draft = HikeSessionDraft.fromTrail(trail).copyWith(
        hikeType: hikeType,
        departureTime: hike.departureTime,
        expectedReturnTime: hike.expectedReturnTime,
      );
      await _startUpcomingHikeNow(draft);
    }
  }

  Future<void> _startUpcomingHikeNow(HikeSessionDraft draft) async {
    var hikeToStart = ActiveHikeSession.fromDraft(draft);
    if (draft.hikeType == HikeType.team) {
      final teamSession = await _coordinateTeamHikeStart(draft);
      if (teamSession == null || !mounted) return;
      hikeToStart = hikeToStart.copyWith(
        teamHikeSessionId: teamSession.id,
        teamHikeSession: teamSession,
      );
    }
    if (draft.fallDetectionEnabled || draft.offlinePhysicalAlertEnabled) {
      final volumeReady = await ensureIosSosOutputVolumeReady(
        context: context,
        deviceAlertService: _sosDeviceAlertService,
        title: 'Turn Up iPhone Volume',
        message:
            'Fall SOS and offline audio SOS use iPhone media volume for the local alarm. Turn it up before starting your hike.',
        proceedLabel: 'Start Hike',
      );
      if (!volumeReady || !mounted) return;
    }
    ActiveHikeSession liveHike = hikeToStart;
    try {
      liveHike = await hikerCircleRepository.createActiveHikeSession(
        session: widget.session,
        draft: draft,
        teamHikeSessionId: hikeToStart.teamHikeSessionId,
      );
      final batteryLevel = await _readBatteryLevel(fallback: 100);
      liveHike = liveHike.copyWith(batteryLevel: batteryLevel, batteryStartedLevel: batteryLevel);
    } on HikerCircleFirebaseRepositoryException catch (_) {
      // Proceed in offline mode
    }
    if (!mounted) return;
    setState(() {
      activeHike = liveHike;
      selectedTabIndex = 0;
    });
    _syncActiveHikeServices(liveHike, forceLiveStatus: true);
    tabController.animateTo(0);
    unawaited(_recordInitialActiveHikeLocation(liveHike));
  }

  Future<void> _openFindHike() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FindHikePage(
          session: widget.session,
          repository: hikerCircleRepository,
        ),
      ),
    );
    if (!mounted) return;
    final upcomingHikes = await hikerCircleRepository.loadMyUpcomingHikes(
      widget.session.phoneNumber,
    );
    if (!mounted) return;
    setState(() {
      myUpcomingHikes = upcomingHikes;
    });
  }

  void openJoinTeamHike() {
    setState(() {
      selectedTabIndex = 2;
    });
    tabController.animateTo(2);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Team hike invitations are in Circle > Teams.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openTeamHikeInvite(String teamHikeSessionId) async {
    try {
      final acceptedSession = await hikerCircleRepository.acceptTeamHikeInvite(
        session: widget.session,
        teamHikeSessionId: teamHikeSessionId,
      );
      if (!mounted) {
        return;
      }
      Trail? trail;
      for (final candidate in trails) {
        if (candidate.trailId == acceptedSession.trailId) {
          trail = candidate;
          break;
        }
      }
      trail ??= plannedHike?.trail;
      if (trail == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'This team hike trail is not available from Firebase yet.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      final draft = HikeSessionDraft.fromTrail(trail).copyWith(
        hikeType: HikeType.team,
        teamBuddies: acceptedSession.participants
            .where(
              (participant) => !_sameTeamPhone(
                participant.phoneNumber,
                widget.session.phoneNumber,
              ),
            )
            .map((participant) => participant.buddy)
            .toList(),
      );
      final launchedSession = await Navigator.of(context).push<TeamHikeSession>(
        MaterialPageRoute<TeamHikeSession>(
          fullscreenDialog: true,
          builder: (context) {
            return _TeamHikeLaunchPage(
              session: widget.session,
              repository: hikerCircleRepository,
              initialTeamSession: acceptedSession,
            );
          },
        ),
      );
      if (launchedSession == null || !mounted) {
        return;
      }
      final preparedHike = ActiveHikeSession.fromDraft(
        draft,
        teamHikeSessionId: launchedSession.id,
        teamHikeSession: launchedSession,
      );
      var liveHike = await hikerCircleRepository.createActiveHikeSession(
        session: widget.session,
        draft: preparedHike.draft,
        teamHikeSessionId: launchedSession.id,
      );
      final batteryLevel = await _readBatteryLevel(
        fallback: liveHike.batteryLevel,
      );
      liveHike = liveHike.copyWith(
        batteryLevel: batteryLevel,
        batteryStartedLevel: batteryLevel,
        teamHikeSession: launchedSession,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        activeHike = liveHike;
        selectedTabIndex = 0;
      });
      _syncActiveHikeServices(liveHike, forceLiveStatus: true);
      tabController.animateTo(0);
      unawaited(_recordInitialActiveHikeLocation(liveHike));
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
    }
  }

  Future<void> _respondToTeamPing(String teamHikeSessionId) async {
    try {
      final teamSession = await hikerCircleRepository.respondToTeamPing(
        session: widget.session,
        teamHikeSessionId: teamHikeSessionId,
      );
      if (!mounted) {
        return;
      }
      final currentHike = activeHike;
      if (currentHike != null &&
          currentHike.teamHikeSessionId == teamHikeSessionId) {
        setState(() {
          activeHike = currentHike.copyWith(teamHikeSession: teamSession);
          selectedTabIndex = 0;
        });
        tabController.animateTo(0);
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('OK response sent to your team.'),
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
    }
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
      final currentPlan = plannedHike;
      if (currentPlan != null) {
        plannedHike = PlannedHike(
          trail: currentPlan.trail,
          plannedStartTime: currentPlan.plannedStartTime,
          expectedReturnTime: currentPlan.expectedReturnTime,
          weatherCached: currentPlan.weatherCached,
          offlineMapDownloaded: currentPlan.offlineMapDownloaded,
          emergencyContactsSelected: contacts.isNotEmpty,
          checklistCompleted: currentPlan.checklistCompleted,
          checklistTotal: currentPlan.checklistTotal,
          phoneBatteryLevel: currentPlan.phoneBatteryLevel,
          liveLocationConfigured: currentPlan.liveLocationConfigured,
        );
      }
    });
  }

  void openTrailDetail(Trail trail) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrailDetailPage(
          session: widget.session,
          hikerCircleRepository: hikerCircleRepository,
          trail: trail,
          onStartHike: (trail) => openStartHikeWizard(trail),
        ),
      ),
    );
  }


  void openSosTab() {
    setState(() {
      selectedTabIndex = 1;
    });
    tabController.animateTo(1);
  }

  void requestManualSos() {
    setState(() {
      selectedTabIndex = 1;
      manualSosRequestId += 1;
    });
    tabController.animateTo(1);
  }

  void requestImmediateSos(SosAlertMode mode) {
    setState(() {
      selectedTabIndex = 1;
      immediateSosRequestMode = mode;
      immediateSosRequestId += 1;
    });
    tabController.animateTo(1);
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
      await _sosDeviceAlertService.stopFallStillnessCountdownVibration();
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
    final isActive = activeHike != null;
    switch (tab.label) {
      case 'Home':
        if (isActive) {
          return ActiveHikeHomePage(
            activeHike: activeHike!,
            onEndHike: () => unawaited(_endActiveHikeSession()),
            onCheckIn: () => unawaited(checkInActiveHike(activeHike!)),
            onPinLocation: () => unawaited(pinCurrentLocation(activeHike!)),
            fallStillnessSnapshot: fallStillnessMonitor.snapshot,
            onCancelFallStillnessSos: () =>
                _cancelFallStillnessSos('Phone tap response received'),
          );
        }
        final now = DateTime.now();
        final activePlannedHike = (plannedHike != null &&
                !now.isAfter(
                    plannedHike!.plannedStartTime.add(const Duration(minutes: 10))))
            ? plannedHike
            : null;
        return HomeDashboardPage(
          phoneNumber: widget.session.phoneNumber,
          myUpcomingHikes: myUpcomingHikes,
          plannedHike: activePlannedHike,
          trails: trails,
          isLoadingTrails: isLoadingLiveData,
          activeHike: activeHike,
          isVisible: selectedTabIndex == 0,
          onStartHike: (trail) => openStartHikeWizard(trail),
          onFindHike: () => _openFindHike(),
          onTapUpcomingHike: _showUpcomingHikeDetails,
          onOpenTrailDetail: openTrailDetail,
          onAddTrailByAdmin: widget.session.isAdmin
              ? () => unawaited(addTrailByAdminFromHome())
              : null,
          onEditTrailByAdmin: widget.session.isAdmin
              ? editTrailByAdminFromHome
              : null,
          onDeleteTrailByAdmin: widget.session.isAdmin
              ? deleteTrailByAdminFromHome
              : null,
          onActiveHikeChanged: (updatedHike) {
            setState(() {
              activeHike = updatedHike;
            });
            _syncActiveHikeServices(updatedHike, forceLiveStatus: true);
          },
          onCheckInRequested: checkInActiveHike,
          onPinLocationRequested: pinCurrentLocation,
          onPingTeamMember: _pingTeamMember,
          onEndHike: () => unawaited(_endActiveHikeSession()),
          fallStillnessSnapshot: fallStillnessMonitor.snapshot,
          onCancelFallStillnessSos: () =>
              _cancelFallStillnessSos('Phone tap response received'),
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
      case 'Admin':
        return AdminPage(
          session: widget.session,
          hikerCircleRepository: hikerCircleRepository,
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
      await _sosDeviceAlertService.startFallStillnessCountdownVibration();
    } catch (_) {
      _showFallStillnessSnackBar(
        'Fall SOS countdown started, but vibration could not start.',
        isError: true,
      );
    }

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
    unawaited(_sosDeviceAlertService.stopFallStillnessCountdownVibration());
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
      unawaited(_sosDeviceAlertService.stopFallStillnessCountdownVibration());
      return;
    }

    unawaited(fallStillnessMonitor.start(hike.draft.fallDetectionSettings));
  }

  void _syncActiveHikeServices(
    ActiveHikeSession? hike, {
    bool forceLiveStatus = false,
  }) {
    _syncFallStillnessMonitor(hike);
    _syncTeamHikeSessionWatch(hike);
    if (hike == null) {
      _stopActiveHikeLocationRecording();
      unawaited(_activeHikeLiveStatusService.stop());
      return;
    }

    _startActiveHikeLocationRecording(hike);
    _syncActiveHikeLiveStatus(hike, force: forceLiveStatus);
  }

  void _syncTeamHikeSessionWatch(ActiveHikeSession? hike) {
    final teamHikeSessionId = hike?.teamHikeSessionId ?? '';
    if (teamHikeSessionId.isEmpty) {
      teamHikeSessionSubscription?.cancel();
      teamHikeSessionSubscription = null;
      teamHikeWatchSessionId = null;
      return;
    }
    if (teamHikeWatchSessionId == teamHikeSessionId &&
        teamHikeSessionSubscription != null) {
      return;
    }

    teamHikeSessionSubscription?.cancel();
    teamHikeWatchSessionId = teamHikeSessionId;
    teamHikeSessionSubscription = hikerCircleRepository
        .watchTeamHikeSession(teamHikeSessionId)
        .listen((teamSession) {
          if (!mounted || teamSession == null) {
            return;
          }
          final currentHike = activeHike;
          if (currentHike == null ||
              currentHike.teamHikeSessionId != teamSession.id) {
            return;
          }
          setState(() {
            activeHike = currentHike.copyWith(teamHikeSession: teamSession);
          });
        });
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
      _syncTeamHikeLocation(updatedHike, location);
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

  void _syncTeamHikeLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location,
  ) {
    if (hike.teamHikeSessionId.isEmpty) {
      return;
    }
    unawaited(() async {
      try {
        final teamSession = await hikerCircleRepository
            .syncTeamHikeParticipantLocation(
              session: widget.session,
              activeHike: hike,
              location: location,
            );
        if (!mounted || teamSession == null) {
          return;
        }
        final currentHike = activeHike;
        if (currentHike == null ||
            currentHike.teamHikeSessionId != teamSession.id) {
          return;
        }
        setState(() {
          activeHike = currentHike.copyWith(teamHikeSession: teamSession);
        });
      } catch (_) {
        // Team position sync should never stop the local tracking loop.
      }
    }());
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
    unawaited(_sosDeviceAlertService.stopFallStillnessCountdownVibration());
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
    teamHikeSessionSubscription?.cancel();
    teamHikeWatchSessionId = null;
    batteryLevelTimer?.cancel();
    unawaited(_sosDeviceAlertService.stopFallStillnessCountdownVibration());
    unawaited(_sosDeviceAlertService.stopSpokenPrompt());
    unawaited(_sosDeviceAlertService.stopManualSosPattern());
    tabController.removeListener(updateTabIndex);
    _deepLinkChannel.setMethodCallHandler(null);
    tabController.dispose();
    LocationSnapshotService.instance.stop();
    LiveLocationSharingService.instance.reset();
    super.dispose();
  }

  List<HikerBottomNavDestination> _visibleTabs() {
    if (activeHike != null) {
      return tabs.where((t) => t.label == 'Home' || t.label == 'SOS' || t.label == 'Profile').toList();
    }
    return tabs;
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
        destinations: _visibleTabs(),
      ),
    );
  }
}

class _TeamHikeLaunchPage extends StatefulWidget {
  const _TeamHikeLaunchPage({
    required this.session,
    required this.repository,
    required this.initialTeamSession,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final TeamHikeSession initialTeamSession;

  @override
  State<_TeamHikeLaunchPage> createState() => _TeamHikeLaunchPageState();
}

class _TeamHikeLaunchPageState extends State<_TeamHikeLaunchPage> {
  Timer? _countdownTicker;
  bool _isMarkingReady = false;
  bool _isActivating = false;

  @override
  void initState() {
    super.initState();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07140D),
      body: SafeArea(
        child: StreamBuilder<TeamHikeSession?>(
          initialData: widget.initialTeamSession,
          stream: widget.repository.watchTeamHikeSession(
            widget.initialTeamSession.id,
          ),
          builder: (context, snapshot) {
            final teamSession = snapshot.data ?? widget.initialTeamSession;
            _closeWhenReady(teamSession);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Tooltip(
                            message: 'Cancel',
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size.square(38),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.xmark,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Team Hike Launch',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F5132), Color(0xFF34A853)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF34A853,
                              ).withValues(alpha: 0.24),
                              blurRadius: 24,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                teamSession.trailName,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _launchSubtitle(teamSession),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      letterSpacing: 0,
                                    ),
                              ),
                              const SizedBox(height: 18),
                              _ReadyLaunchButton(
                                label: _readyButtonLabel(teamSession),
                                enabled: _canMarkReady(teamSession),
                                busy: _isMarkingReady,
                                countdown:
                                    teamSession.phase == TeamHikePhase.countdown
                                    ? teamSession.countdownRemainingSeconds
                                    : null,
                                onPressed: () => unawaited(
                                  _markCurrentParticipantReady(teamSession),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _TeamLaunchStatusCard(
                        teamSession: teamSession,
                        currentPhoneNumber: widget.session.phoneNumber,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _launchSubtitle(TeamHikeSession teamSession) {
    if (teamSession.phase == TeamHikePhase.countdown) {
      return 'Everyone is ready. Starting together in ${teamSession.countdownRemainingSeconds} seconds.';
    }
    if (teamSession.invitedCount > 0) {
      return '${teamSession.invitedCount} buddy invite${teamSession.invitedCount == 1 ? '' : 's'} still need to be opened before READY appears.';
    }
    return 'The team hike session is going to start. Press READY when your gear and GPS are set.';
  }

  String _readyButtonLabel(TeamHikeSession teamSession) {
    final participant = _currentParticipant(teamSession);
    if (teamSession.phase == TeamHikePhase.countdown) {
      return 'STARTING';
    }
    if (participant?.status.isReadyForStart == true) {
      return 'READY SENT';
    }
    if (teamSession.invitedCount > 0) {
      return 'WAITING';
    }
    return 'READY';
  }

  bool _canMarkReady(TeamHikeSession teamSession) {
    if (_isMarkingReady ||
        teamSession.invitedCount > 0 ||
        teamSession.phase == TeamHikePhase.countdown ||
        teamSession.phase == TeamHikePhase.active) {
      return false;
    }
    final participant = _currentParticipant(teamSession);
    return participant?.status.isReadyForStart != true;
  }

  TeamHikeParticipant? _currentParticipant(TeamHikeSession teamSession) {
    for (final participant in teamSession.participants) {
      if (_sameTeamPhone(participant.phoneNumber, widget.session.phoneNumber)) {
        return participant;
      }
    }
    return null;
  }

  Future<void> _markCurrentParticipantReady(TeamHikeSession teamSession) async {
    if (!_canMarkReady(teamSession)) {
      return;
    }
    setState(() {
      _isMarkingReady = true;
    });
    try {
      await widget.repository.markTeamParticipantReady(
        session: widget.session,
        teamHikeSessionId: teamSession.id,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingReady = false;
        });
      }
    }
  }

  void _closeWhenReady(TeamHikeSession teamSession) {
    if (_isActivating) {
      return;
    }
    if (teamSession.phase == TeamHikePhase.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(teamSession);
        }
      });
      return;
    }
    if (teamSession.phase != TeamHikePhase.countdown ||
        teamSession.countdownRemainingSeconds > 0) {
      return;
    }
    _isActivating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_activateAndClose(teamSession));
    });
  }

  Future<void> _activateAndClose(TeamHikeSession teamSession) async {
    final activeSession = await widget.repository.activateTeamHikeSession(
      teamHikeSessionId: teamSession.id,
    );
    if (mounted) {
      Navigator.of(context).pop(activeSession);
    }
  }
}

class _ReadyLaunchButton extends StatelessWidget {
  const _ReadyLaunchButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
    this.countdown,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final int? countdown;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final countdownValue = countdown;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? Colors.white
                : Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      countdownValue == null ? label : '$countdownValue',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: enabled
                            ? const Color(0xFF0F5132)
                            : Colors.white.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    Text(
                      countdownValue == null ? 'press when ready' : label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: enabled
                            ? const Color(0xFF0F5132)
                            : Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w800,
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

class _TeamLaunchStatusCard extends StatelessWidget {
  const _TeamLaunchStatusCard({
    required this.teamSession,
    required this.currentPhoneNumber,
  });

  final TeamHikeSession teamSession;
  final String currentPhoneNumber;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${teamSession.readyCount}/${teamSession.participants.length} ready',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Text(
                  teamSession.phase.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF7EE0A0),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          for (
            var index = 0;
            index < teamSession.participants.length;
            index++
          ) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
            _TeamLaunchParticipantRow(
              participant: teamSession.participants[index],
              isSelf: _sameTeamPhone(
                teamSession.participants[index].phoneNumber,
                currentPhoneNumber,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamLaunchParticipantRow extends StatelessWidget {
  const _TeamLaunchParticipantRow({
    required this.participant,
    required this.isSelf,
  });

  final TeamHikeParticipant participant;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final statusColor = participant.status.isReadyForStart
        ? const Color(0xFF7EE0A0)
        : participant.status == TeamHikeParticipantStatus.invited
        ? const Color(0xFFFBBF24)
        : Colors.white.withValues(alpha: 0.78);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(participant.buddy.avatarColorValue),
              shape: BoxShape.circle,
            ),
            child: Text(
              participant.buddy.shortName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? 'You' : participant.buddy.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  participant.buddy.handle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Text(
            participant.status.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
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
      backgroundColor: _SummaryColors.backgroundFor(context),
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
                            decoration: BoxDecoration(
                              color: _SummaryColors.surfaceFor(context),
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
                                    color: _SummaryColors.textFor(context),
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
                                    color: _SummaryColors.secondaryTextFor(
                                      context,
                                    ),
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
                        Divider(
                          height: 1,
                          color: _SummaryColors.separatorFor(context),
                        ),
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
                        Divider(
                          height: 1,
                          color: _SummaryColors.separatorFor(context),
                        ),
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
                      color: _SummaryColors.secondaryTextFor(context),
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
                            Divider(
                              height: 1,
                              color: _SummaryColors.separatorFor(context),
                            ),
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
        decoration: BoxDecoration(color: _SummaryColors.surfaceFor(context)),
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
                color: _SummaryColors.textFor(context),
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
                                    color: _SummaryColors.secondaryTextFor(
                                      context,
                                    ),
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
                            color: _SummaryColors.green,
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
                color: _SummaryColors.secondaryTextFor(context),
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

abstract final class _SummaryColors {
  static const Color green = Color(0xFF34A853);
  static const Color background = Color(0xFFF2F2F7);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color separator = Color(0xFFD9E1DC);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;
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
              color: _SummaryColors.textFor(context),
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
              color: _SummaryColors.secondaryTextFor(context),
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
    return SizedBox(
      height: 68,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _SummaryColors.separatorFor(context),
      ),
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
            color: _SummaryColors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SummaryColors.textFor(context),
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

class ActiveHikeHomePage extends StatelessWidget {
  const ActiveHikeHomePage({
    super.key,
    required this.activeHike,
    required this.onEndHike,
    required this.onCheckIn,
    required this.onPinLocation,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
  });

  final ActiveHikeSession activeHike;
  final VoidCallback onEndHike;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;

  @override
  Widget build(BuildContext context) {
    final expectedReturn = activeHike.draft.expectedReturnTime;
    final elapsed = DateTime.now().difference(activeHike.startedAt);
    final elapsedLabel = '${elapsed.inHours}h ${elapsed.inMinutes.remainder(60)}m';
    final returnLabel =
        '${expectedReturn.hour.toString().padLeft(2, '0')}:${expectedReturn.minute.toString().padLeft(2, '0')}';
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        _ActiveHikeTopBar(
          trailName: activeHike.draft.trail.name,
          elapsedLabel: elapsedLabel,
          returnLabel: returnLabel,
          batteryLevel: activeHike.batteryLevel,
          gpsPointCount: activeHike.routePointCount,
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: ActiveTrackingMapView(
              activeHike: activeHike,
              showLegend: false,
            ),
          ),
        ),
        _ActiveHikeBottomBar(
          onEndHike: onEndHike,
          onCheckIn: onCheckIn,
          onPinLocation: onPinLocation,
          bottomInset: bottomInset,
        ),
      ],
    );
  }
}

class _ActiveHikeTopBar extends StatelessWidget {
  const _ActiveHikeTopBar({
    required this.trailName,
    required this.elapsedLabel,
    required this.returnLabel,
    required this.batteryLevel,
    required this.gpsPointCount,
  });

  final String trailName;
  final String elapsedLabel;
  final String returnLabel;
  final int batteryLevel;
  final int gpsPointCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trailName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetricChip(
                  icon: Icons.timer_outlined,
                  label: elapsedLabel,
                ),
                const SizedBox(width: 8),
                _MetricChip(
                  icon: Icons.schedule_rounded,
                  label: 'Expected $returnLabel',
                ),
                const SizedBox(width: 8),
                _MetricChip(
                  icon: Icons.battery_std_rounded,
                  label: '$batteryLevel%',
                ),
                const SizedBox(width: 8),
                _MetricChip(
                  icon: Icons.gps_fixed_rounded,
                  label: '$gpsPointCount pts',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveHikeBottomBar extends StatelessWidget {
  const _ActiveHikeBottomBar({
    required this.onEndHike,
    required this.onCheckIn,
    required this.onPinLocation,
    this.bottomInset = 0,
  });

  final VoidCallback onEndHike;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCheckIn,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Check In'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPinLocation,
                    icon: const Icon(Icons.push_pin_rounded, size: 18),
                    label: const Text('Pin Location'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE11D48),
                side: const BorderSide(color: Color(0xFFE11D48)),
              ),
              onPressed: onEndHike,
              icon: const Icon(Icons.stop_circle_rounded, size: 18),
              label: const Text('End Hike Session'),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameTeamPhone(String first, String second) {
  final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
  final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
  return firstKey.isNotEmpty && firstKey == secondKey;
}

class _UpcomingHikeDetailSheet extends StatelessWidget {
  const _UpcomingHikeDetailSheet({
    required this.hike,
    required this.trail,
    required this.phoneNumber,
  });

  final UpcomingHike hike;
  final Trail? trail;
  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    final isCreator = hike.creatorPhone == phoneNumber;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCreator
                        ? const Color(0xFF34A853).withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.hiking_rounded,
                    color: isCreator
                        ? const Color(0xFF34A853)
                        : Colors.grey.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hike.trailName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        isCreator ? 'Created by you' : 'Joined by you',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isCreator
                                  ? const Color(0xFF34A853)
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _DetailRow(
              icon: Icons.location_on_rounded,
              label: 'Start Point',
              value: hike.startPointName,
            ),
            _DetailRow(
              icon: Icons.flag_rounded,
              label: 'Destination',
              value: hike.destinationName,
            ),
            _DetailRow(
              icon: Icons.schedule_rounded,
              label: 'Departure',
              value:
                  '${_formatDate(hike.departureTime)} at ${_formatTime(hike.departureTime)}',
            ),
            _DetailRow(
              icon: Icons.timer_outlined,
              label: 'Expected Return',
              value: _formatTime(hike.expectedReturnTime),
            ),
            const Divider(height: 24),
            _DetailRow(
              icon: Icons.straighten_rounded,
              label: 'Distance',
              value: '${hike.distanceKm.toStringAsFixed(1)} km',
            ),
            _DetailRow(
              icon: Icons.terrain_rounded,
              label: 'Difficulty',
              value: hike.difficulty,
            ),
            _DetailRow(
              icon: Icons.place_rounded,
              label: 'Location',
              value: '${hike.area}, ${hike.state}',
            ),
            _DetailRow(
              icon: Icons.group_rounded,
              label: 'Participants',
              value: '${hike.participantCount}',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: trail != null
                        ? () => Navigator.of(context).pop('viewTrail')
                        : null,
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('View Trail'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop('start'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      hike.hikeType == 'team'
                          ? 'Start Now (Team)'
                          : 'Start Now (Solo)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$minute $ampm';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
