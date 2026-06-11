import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../circle/View/circle_page.dart';
import '../../me/Data/live_location_sharing_service.dart';
import '../../me/View/me_page.dart';
import '../../navigation/View/hiker_bottom_nav_bar.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../../sos/View/sos_page.dart';
import '../../trail/Data/trail_repository.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';
import '../Model/hike_session_models.dart';
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
    with SingleTickerProviderStateMixin {
  late final TabController tabController;
  late final List<Trail> trails;
  late final HikerCircleFirebaseRepository hikerCircleRepository;
  late final EmergencyContactsRepository emergencyContactsRepository;
  late PlannedHike plannedHike;
  bool isLoadingLiveData = false;
  ActiveHikeSession? activeHike;
  int selectedTabIndex = 0;
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
    tabController = TabController(length: tabs.length, vsync: this);
    tabController.addListener(updateTabIndex);
    unawaited(LocationSnapshotService.instance.start());
    unawaited(loadLiveData());
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
            setState(() {
              activeHike = null;
            });
          },
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
          phoneNumber: widget.session.phoneNumber,
          onSignOut: widget.onSignOut,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    tabController.removeListener(updateTabIndex);
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
      body: TabBarView(
        controller: tabController,
        children: tabs.map(pageFor).toList(),
      ),
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: selectedTabIndex,
        onDestinationSelected: onTabTap,
      ),
    );
  }
}
