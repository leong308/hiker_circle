import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:url_launcher/url_launcher.dart';

import '../../admin/View/admin_page.dart';
import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../circle/View/circle_page.dart';
import '../../circle/View/group_chat_detail_page.dart';
import '../../circle/View/team_formed_naming_dialog.dart';
import '../../me/Data/live_location_sharing_service.dart';
import '../../me/View/me_page.dart';
import '../../onboarding/Data/google_city_geocoding_service.dart';
import '../../navigation/View/hiker_bottom_nav_bar.dart';
import '../../core/services/device_notification_log_service.dart';
import '../../core/models/hike_route_analysis.dart';
import '../../core/services/fcm_notification_router.dart';
import '../../core/services/hiker_ble_service.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/services/network_reachability_service.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../core/widgets/worldwide_region_picker.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Data/nearby_sos_event_repository.dart';
import 'find_hike_page.dart';
import '../../sos/Data/sos_alert_repository.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/Model/nearby_sos_event.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../../sos/View/ios_sos_volume_guard.dart';
import '../../sos/View/sos_page.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';
import '../Data/active_hike_weather_service.dart';
import '../Data/active_hike_live_status_service.dart';
import '../Data/planned_hike_state_service.dart';
import '../Model/hike_session_models.dart';
import 'active_tracking_map_view.dart';
import '../ModelView/fall_stillness_monitor.dart';
import '../ModelView/stationary_location_policy.dart';
import 'active_hike_map_page.dart';
import 'home_dashboard_page.dart';
import 'hike_share_preview_page.dart';
import 'first_aid_guide_page.dart';
import 'start_hike_wizard_page.dart';
import 'trail_rating_dialog.dart';
import 'upcoming_hike_join_request_dialog.dart';

class HikerHomePage extends StatefulWidget {
  const HikerHomePage({
    super.key,
    required this.session,
    required this.onSignOut,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.initialDeepLink,
  });

  final AppSession session;
  final VoidCallback onSignOut;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final String? initialDeepLink;

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
  List<Trail> trails = [];
  late final HikerCircleFirebaseRepository hikerCircleRepository;
  late final EmergencyContactsRepository emergencyContactsRepository;
  late final SosAlertRepository sosAlertRepository;
  late final NearbySosEventRepository nearbySosEventRepository;
  late final FallStillnessMonitor fallStillnessMonitor;
  final SosDeviceAlertService _sosDeviceAlertService =
      const SosDeviceAlertService();
  final ActiveHikeLiveStatusService _activeHikeLiveStatusService =
      const ActiveHikeLiveStatusService();
  final HikerBleService _bleService = const HikerBleService();
  StreamSubscription<List<UpcomingHike>>? _myUpcomingHikesSubscription;
  StreamSubscription<List<Trail>>? _trailsSubscription;
  bool _trailRegionRepairStarted = false;
  StreamSubscription<HikerBleEvent>? _bleEventSubscription;
  StreamSubscription<NetworkReachabilitySnapshot>?
  _networkReachabilitySubscription;
  StreamSubscription<List<GroupChat>>? _formedTeamChatsSubscription;
  String? _activeTeamNamingChatId;
  String? _activeUpcomingJoinRequestReviewId;
  final Set<String> _completedUpcomingJoinRequestReviewIds = <String>{};
  List<GroupChat> _pendingFormedTeamChats = const [];
  NetworkReachabilitySnapshot _networkReachabilitySnapshot =
      const NetworkReachabilitySnapshot(
        state: NetworkReachabilityState.checking,
      );
  PlannedHike? plannedHike;
  List<UpcomingHike> myUpcomingHikes = const [];
  Map<String, Set<String>> _plannedChecklistByUpcomingId = const {};
  Set<String> _consumedUpcomingHikeIds = const {};
  int _upcomingPlanningRevision = 0;
  int? _latestPhoneBatteryLevel;
  bool isLoadingLiveData = false;
  bool isSendingFallStillnessSos = false;
  bool isRecordingActiveHikeLocation = false;
  bool _isCheckInBusy = false;
  bool _isPinLocationBusy = false;
  bool _isEndingActiveHike = false;
  bool _liveLocationActivatedForActiveHike = false;
  bool isFallStillnessDialogVisible = false;
  bool isFallStillnessLocalAlarmActive = false;
  bool fallStillnessCountdownWasBackgrounded = false;
  Timer? activeHikeRecordingTimer;
  Timer? batteryLevelTimer;
  Timer? activeHikeMonitoringHeartbeatTimer;
  StreamSubscription<String>? fcmTokenSubscription;
  StreamSubscription<RemoteMessage>? fcmOpenSubscription;
  StreamSubscription<RemoteMessage>? fcmForegroundSubscription;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final List<_PendingFcmOpen> _pendingFcmOpens = <_PendingFcmOpen>[];
  final Set<String> _handledFcmOpenKeys = <String>{};
  bool _notificationUiReady = false;
  bool _isDrainingFcmOpens = false;
  final List<HikerBleEvent> _pendingBleUiEvents = <HikerBleEvent>[];
  bool _isPresentingBleUiEvent = false;

  String? activeHikeMonitoringSessionId;
  String _fcmToken = '';
  StreamSubscription<TeamHikeSession?>? teamHikeSessionSubscription;
  String? teamHikeWatchSessionId;
  String? activeHikeRecordingSessionId;
  Duration? activeHikeRecordingInterval;
  DateTime? lastActiveHikeLocationRecordedAt;
  DateTime? lastActiveHikeLiveStatusSentAt;
  DateTime? _pathDeviationStartedAt;
  DateTime? _lastPathDeviationAlertAt;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  HikeCoordinate? stationaryWatchReferenceLocation;
  double? stationaryWatchReferenceAccuracyMeters;
  DateTime? stationaryWatchStartedAt;
  bool isStationaryLocationWatchActive = false;
  FallStillnessMonitorStatus lastFallStillnessStatus =
      FallStillnessMonitorStatus.inactive;
  ActiveHikeSession? activeHike;
  Future<void>? _activeHikeRestoreFuture;
  Future<void> _activeHikePersistenceQueue = Future<void>.value();
  Future<void> _fallStillnessSyncQueue = Future<void>.value();
  late final Future<void> _emergencyContactsLoadFuture;
  bool isNativeSafetyDialogVisible = false;
  String? _lastHandledNativeSafetyEventId;
  final Map<String, String> _activeHikeSessionIdRemaps = <String, String>{};
  final Set<String> _terminalCloudHikeSessionIds = <String>{};
  bool isRestoringActiveHike = true;
  int selectedTabIndex = 0;
  int _manualSosRequestSequence = 0;
  int _pendingManualSosRequestId = 0;
  int _immediateSosRequestSequence = 0;
  int _pendingImmediateSosRequestId = 0;
  SosAlertMode? immediateSosRequestMode;
  SosAlertTriggerSource immediateSosRequestTriggerSource =
      SosAlertTriggerSource.mobilePhone;
  String? _lastHandledDeepLink;
  DateTime? _lastHandledDeepLinkAt;
  String? _lastHandledPairedSosKey;
  final Set<String> _presentedNearbySosKeys = <String>{};
  final Set<String> _presentedExactNearbySosKeys = <String>{};
  final Set<String> _activeApproximateNearbySosKeys = <String>{};
  final Map<String, SosTriggerLocation> _exactNearbySosLocations = {};
  final Map<String, Timer> _nearbySosFallbackTimers = {};
  int _nearbySosRevision = 0;
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
    hikerCircleRepository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _listenForFormedTeamChats();
    unawaited(_restoreCachedUpcomingPlanningState());
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _emergencyContactsLoadFuture = _loadEmergencyContacts();
    sosAlertRepository = SosAlertRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    nearbySosEventRepository = NearbySosEventRepository();
    fallStillnessMonitor = FallStillnessMonitor(
      onEmergencyReady: _handleFallStillnessEmergencyReady,
    );
    fallStillnessMonitor.addListener(_handleFallStillnessMonitorChanged);
    _activeHikeLiveStatusService.setNativeSafetyEventHandler(
      _consumePendingNativeSafetyEvent,
    );
    WidgetsBinding.instance.addObserver(this);
    tabController = TabController(length: tabs.length, vsync: this);
    tabController.addListener(updateTabIndex);
    _activeHikeRestoreFuture = _restoreActiveHikeSession();
    _deepLinkChannel.setMethodCallHandler(_handleDeepLinkMethodCall);
    unawaited(LocationSnapshotService.instance.start());
    unawaited(_refreshBatteryLevel());
    batteryLevelTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshBatteryLevel());
    });
    unawaited(loadLiveData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notificationUiReady = true;
      unawaited(_drainPendingFcmOpens());
      unawaited(_drainPendingBleUiEvents());
    });
    unawaited(_loadInitialDeepLink());
    if (widget.initialDeepLink != null) {
      _handleDeepLinkAfterFirstFrame(widget.initialDeepLink!);
    }
    unawaited(_initializeFirebaseMessaging());
    unawaited(_initializeBleBridge());
    _networkReachabilitySubscription = NetworkReachabilityService
        .instance
        .snapshots
        .listen(_handleNetworkReachabilityChanged);
    unawaited(NetworkReachabilityService.instance.start());
  }

  void _listenForFormedTeamChats() {
    if (!widget.firebaseBootstrapResult.isAvailable) return;
    _formedTeamChatsSubscription = hikerCircleRepository
        .formedTeamChatsForHostStream(widget.session.phoneNumber)
        .listen(
          _promptForFormedTeamChatName,
          onError: (_) {
            // Circle provides a visible retry state if the chat stream fails.
          },
        );
  }

  void _promptForFormedTeamChatName(List<GroupChat> chats) {
    if (!mounted || _activeTeamNamingChatId != null) return;
    if (_activeUpcomingJoinRequestReviewId != null) {
      _pendingFormedTeamChats = chats;
      return;
    }
    final ownPhoneKey = _formedChatPhoneKey(widget.session.phoneNumber);
    for (final chat in chats) {
      final isHost = _formedChatPhoneKey(chat.creatorPhone) == ownPhoneKey;
      if (chat.isDirect ||
          !isHost ||
          !chat.requiresHostNaming ||
          chat.namingPromptShown ||
          chat.hikeEndedAt != null ||
          chat.participantPhones.length < 2 ||
          chat.isDeleted) {
        continue;
      }
      _activeTeamNamingChatId = chat.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _activeTeamNamingChatId = null;
          return;
        }
        unawaited(_showFormedTeamNamingDialog(chat));
      });
      return;
    }
  }

  String _formedChatPhoneKey(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _showFormedTeamNamingDialog(GroupChat chat) async {
    final trailName = chat.trailName.trim().isEmpty
        ? 'this hike'
        : chat.trailName.trim();
    final departure = chat.departureTime ?? chat.createdAt;
    final initialName = GroupChat.defaultGroupName(chat.trailName, departure);
    try {
      await hikerCircleRepository.markFormedHikeGroupNamingPromptShown(
        chatId: chat.id,
        defaultName: initialName,
      );
    } catch (_) {
      // The mandatory dialog still lets the host retry the final save. If the
      // app is killed before this acknowledgement reaches Firebase, the chat
      // remains pending and will be offered again instead of being lost.
    }
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TeamFormedNamingDialog(
        joinedHikerName: chat.latestJoinedName,
        trailName: trailName,
        initialName: initialName,
        onSubmit: (name) => hikerCircleRepository.nameFormedHikeGroupChat(
          chatId: chat.id,
          name: name,
        ),
      ),
    );
    if (!mounted) return;
    _activeTeamNamingChatId = null;
    if (created == true) {
      final circleTabIndex = tabs.indexWhere((tab) => tab.label == 'Circle');
      if (circleTabIndex >= 0 && activeHike == null) {
        onTabTap(circleTabIndex);
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Your group chat is ready.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _initializeFirebaseMessaging() async {
    if (!widget.firebaseBootstrapResult.isAvailable) {
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      // Install open listeners before any permission/token network work. A tap
      // that resumes the app must not be lost while initialization is waiting.
      fcmTokenSubscription = messaging.onTokenRefresh.listen(
        (token) => unawaited(_registerFcmTokenBestEffort(token)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('FCM token refresh stream stopped: $error');
        },
      );
      fcmOpenSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(_handleFcmOpenBestEffort(message)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('FCM open stream stopped: $error');
        },
      );
      fcmForegroundSubscription = FirebaseMessaging.onMessage.listen(
        _showForegroundNotification,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('FCM foreground stream stopped: $error');
        },
      );

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _handleFcmOpenFromLocal,
      );

      final localLaunchDetails = await _localNotifications
          .getNotificationAppLaunchDetails();
      final localLaunchResponse = localLaunchDetails?.notificationResponse;
      if (localLaunchDetails?.didNotificationLaunchApp == true &&
          localLaunchResponse != null) {
        _handleFcmOpenFromLocal(localLaunchResponse);
      }

      // Read the terminated-state message before token registration. This is
      // a one-shot value and is the critical path for notification cold starts.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        await _handleFcmOpen(initialMessage);
      }

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      try {
        final token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _registerFcmToken(token);
        }
      } catch (error) {
        debugPrint('FCM token is not available yet: $error');
      }
    } catch (error) {
      debugPrint('Unable to initialize Firebase Messaging: $error');
    }
  }

  Future<void> _initializeBleBridge() async {
    try {
      await _bleService.setActiveSosAccount(widget.session.phoneNumber);
      if (!mounted) return;
      await _bleEventSubscription?.cancel();
      if (!mounted) return;
      _bleEventSubscription = _bleService.events.listen(
        _handleBleEvent,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('BLE event stream stopped: $error');
        },
      );
      await _bleService.startSosButtonMonitor();
    } catch (error) {
      // BLE is an optional transport. A disabled adapter, denied permission,
      // or unavailable native bridge must not become an uncaught launch error.
      debugPrint('Unable to initialize the BLE SOS bridge: $error');
    }
  }

  void _handleBleEvent(HikerBleEvent event) {
    switch (event) {
      case HikerBlePairedButtonSetupEvent():
        break;
      case HikerBleSosButtonEvent():
        requestImmediateSos(
          SosAlertMode.manual,
          triggerSource: SosAlertTriggerSource.emergencyButton,
        );
      case HikerBlePairedSosButtonEvent():
        _handlePairedSosButtonEvent(event);
      case HikerBlePairedSosButtonTestEvent():
        // Native code has already consumed this authenticated press inside an
        // explicitly armed test window. Never route it into the SOS flow.
        break;
      case HikerBleNearbySosButtonEvent():
        _enqueueBleUiEvent(event);
      case HikerBleNearbySosLocationEvent():
        _enqueueBleUiEvent(event);
      case HikerBleSosHelpEvent():
        _enqueueBleUiEvent(event);
      case HikerBleTeamLocationEvent():
        _handleBleTeamLocation(event);
      case HikerBleStatusEvent():
        break;
    }
  }

  void _enqueueBleUiEvent(HikerBleEvent event) {
    final key = switch (event) {
      HikerBleNearbySosButtonEvent() =>
        '${event.deviceId}:${event.counter ?? event.receivedAt.millisecondsSinceEpoch ~/ 1000}',
      HikerBleNearbySosLocationEvent() =>
        '${event.deviceId}:${event.counter ?? event.receivedAt.millisecondsSinceEpoch ~/ 1000}',
      HikerBleSosHelpEvent() =>
        'help:${event.location.latitude.toStringAsFixed(5)}:${event.location.longitude.toStringAsFixed(5)}:${event.location.capturedAt?.millisecondsSinceEpoch ?? 0}',
      _ => '',
    };
    if (key.isEmpty) return;

    final matchingIndex = _pendingBleUiEvents.indexWhere((pending) {
      return switch (pending) {
        HikerBleNearbySosButtonEvent() =>
          '${pending.deviceId}:${pending.counter ?? pending.receivedAt.millisecondsSinceEpoch ~/ 1000}' ==
              key,
        HikerBleNearbySosLocationEvent() =>
          '${pending.deviceId}:${pending.counter ?? pending.receivedAt.millisecondsSinceEpoch ~/ 1000}' ==
              key,
        HikerBleSosHelpEvent() =>
          'help:${pending.location.latitude.toStringAsFixed(5)}:${pending.location.longitude.toStringAsFixed(5)}:${pending.location.capturedAt?.millisecondsSinceEpoch ?? 0}' ==
              key,
        _ => false,
      };
    });
    if (matchingIndex >= 0) {
      final existing = _pendingBleUiEvents[matchingIndex];
      if (existing is HikerBleNearbySosLocationEvent &&
          event is HikerBleNearbySosButtonEvent) {
        return;
      }
      _pendingBleUiEvents[matchingIndex] = event;
    } else {
      _pendingBleUiEvents.add(event);
      if (_pendingBleUiEvents.length > 16) {
        _pendingBleUiEvents.removeAt(0);
      }
    }
    unawaited(_drainPendingBleUiEvents());
  }

  Future<void> _drainPendingBleUiEvents() async {
    if (_isPresentingBleUiEvent ||
        !mounted ||
        !_notificationUiReady ||
        _appLifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _isPresentingBleUiEvent = true;
    try {
      while (mounted &&
          _appLifecycleState == AppLifecycleState.resumed &&
          _pendingBleUiEvents.isNotEmpty) {
        final event = _pendingBleUiEvents.removeAt(0);
        switch (event) {
          case HikerBleNearbySosButtonEvent():
            await _handleNearbySosButtonEvent(
              deviceId: event.deviceId,
              counter: event.counter,
              receivedAt: event.receivedAt,
              rssi: event.rssi,
            );
          case HikerBleNearbySosLocationEvent():
            await _handleNearbySosLocationEvent(event);
          case HikerBleSosHelpEvent():
            await _handleBleSosHelpEvent(event);
          default:
            break;
        }
      }
    } finally {
      _isPresentingBleUiEvent = false;
    }
  }

  void _handleNetworkReachabilityChanged(NetworkReachabilitySnapshot snapshot) {
    final wasOnline = _networkReachabilitySnapshot.isOnline;
    _networkReachabilitySnapshot = snapshot;
    if (!wasOnline && snapshot.isOnline) {
      unawaited(_synchronizeAfterReconnect());
    }
  }

  Future<void> _synchronizeAfterReconnect() async {
    // Each queue is independent: a failed chat or contact write must not block
    // critical SOS, hike-end, or GPS recovery work from being attempted.
    if (emergencyContacts.isNotEmpty) {
      await _runReconnectStep(
        'emergency contacts',
        () => emergencyContactsRepository.saveEmergencyContacts(
          session: widget.session,
          contacts: emergencyContacts,
        ),
      );
    }
    await _runReconnectStep(
      'SOS alerts',
      () => sosAlertRepository.flushQueuedAlerts(
        session: widget.session,
        contacts: emergencyContacts,
      ),
    );
    await _runReconnectStep('nearby SOS forwarding', () async {
      final events = await nearbySosEventRepository.load(
        ownerPhoneNumber: widget.session.phoneNumber,
        limit: 50,
      );
      final now = DateTime.now().toUtc();
      for (final event in events.where(
        (value) => value.ageAt(now) <= const Duration(hours: 1),
      )) {
        await hikerCircleRepository.forwardNearbySosIncident(event: event);
      }
    });
    await _runReconnectStep(
      'chat messages',
      hikerCircleRepository.flushPendingMessages,
    );
    await _runReconnectStep(
      'ended hikes',
      () => hikerCircleRepository.flushPendingHikeEnds(session: widget.session),
    );

    final currentHike = activeHike;
    if (currentHike != null) {
      final hike = await _restoreScheduledTeamSourceLink(currentHike);
      ActiveHikeCloudRestoreResult? restoreResult;
      await _runReconnectStep('active hike', () async {
        restoreResult = await hikerCircleRepository
            .ensureActiveHikeSessionInCloud(
              session: widget.session,
              activeHike: hike,
            );
      });
      final result = restoreResult;
      if (result != null) {
        ActiveHikeSession? cloudHike;
        await _runReconnectStep('active hike recovery result', () async {
          cloudHike = await _applyActiveHikeCloudRestoreResult(hike, result);
        });
        final hikeToFlush = cloudHike;
        if (hikeToFlush != null && result.ensured) {
          await _runReconnectStep('hike locations', () async {
            final remaining = await hikerCircleRepository.flushLocationPoints(
              session: widget.session,
              activeHike: hikeToFlush,
            );
            if (mounted && activeHike?.sessionId == hikeToFlush.sessionId) {
              final updatedHike = hikeToFlush.copyWith(
                queuedUpdates: remaining,
              );
              setState(() => activeHike = updatedHike);
              _persistActiveHikeSnapshot(updatedHike);
            }
          });
        }
      }
    }
    if (LiveLocationSharingService.instance.isActive) {
      await _runReconnectStep(
        'live location',
        LiveLocationSharingService.instance.publishLatest,
      );
    }
  }

  Future<ActiveHikeSession> _restoreScheduledTeamSourceLink(
    ActiveHikeSession hike,
  ) async {
    if (hike.sourceUpcomingHikeId.trim().isNotEmpty ||
        hike.teamHikeSessionId.trim().isEmpty) {
      return hike;
    }
    final teamSession = await hikerCircleRepository.loadTeamHikeSession(
      hike.teamHikeSessionId,
    );
    final sourceUpcomingHikeId = teamSession?.sourceUpcomingHikeId.trim() ?? '';
    if (teamSession == null || sourceUpcomingHikeId.isEmpty) {
      return hike;
    }
    final updatedHike = hike.copyWith(
      sourceUpcomingHikeId: sourceUpcomingHikeId,
      teamHikeSession: teamSession,
    );
    if (mounted && activeHike?.sessionId == hike.sessionId) {
      setState(() => activeHike = updatedHike);
      _persistActiveHikeSnapshot(updatedHike);
    }
    return updatedHike;
  }

  ActiveHikeSession _withTeamHikeSessionLink(
    ActiveHikeSession hike,
    TeamHikeSession teamSession,
  ) {
    return hike.copyWith(
      teamHikeSession: teamSession,
      sourceUpcomingHikeId: hike.sourceUpcomingHikeId.trim().isNotEmpty
          ? hike.sourceUpcomingHikeId
          : teamSession.sourceUpcomingHikeId,
    );
  }

  Future<ActiveHikeSession?> _applyActiveHikeCloudRestoreResult(
    ActiveHikeSession requestedHike,
    ActiveHikeCloudRestoreResult result,
  ) async {
    if (!mounted) return null;
    final currentHike = activeHike;
    if (currentHike == null ||
        currentHike.sessionId != requestedHike.sessionId) {
      return null;
    }

    var cloudHike = currentHike;
    final oldSessionId = currentHike.sessionId;
    final canonicalSessionId = result.sessionId;
    if (canonicalSessionId != oldSessionId) {
      _activeHikeSessionIdRemaps[oldSessionId] = canonicalSessionId;
      await _activeHikePersistenceQueue;
      cloudHike = await hikerCircleRepository.localDatabase
          .migrateActiveHikeSessionId(
            ownerPhoneNumber: widget.session.phoneNumber,
            activeHike: currentHike,
            newSessionId: canonicalSessionId,
          );
    }

    if (!mounted || activeHike?.sessionId != oldSessionId) {
      return activeHike?.sessionId == canonicalSessionId ? activeHike : null;
    }
    if (result.terminal) {
      _terminalCloudHikeSessionIds
        ..add(oldSessionId)
        ..add(canonicalSessionId);
      setState(() => activeHike = null);
      _syncActiveHikeServices(null);
      await _activeHikePersistenceQueue;
      await hikerCircleRepository.localDatabase.discardHikeTrackingTelemetry(
        sessionId: canonicalSessionId,
      );
      if (canonicalSessionId != oldSessionId) {
        await hikerCircleRepository.localDatabase.discardHikeTrackingTelemetry(
          sessionId: oldSessionId,
        );
      }
      if (mounted) {
        final statusLabel = result.status == 'abandoned'
            ? 'abandoned'
            : 'completed';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'This hike was already $statusLabel in the cloud, so local tracking was stopped.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return null;
    }
    if (!result.ensured) return null;

    if (canonicalSessionId != oldSessionId) {
      setState(() => activeHike = cloudHike);
      _syncActiveHikeServices(cloudHike, forceLiveStatus: true);
    }
    return cloudHike;
  }

  Future<void> _runReconnectStep(
    String label,
    Future<dynamic> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Reconnect $label synchronization will retry: $error');
    }
  }

  Future<void> _registerFcmToken(String token) async {
    _fcmToken = token;
    await hikerCircleRepository.registerFcmToken(
      session: widget.session,
      token: token,
    );
    final hike = activeHike;
    if (hike != null) {
      await _sendActiveHikeMonitoringHeartbeat(hike, lifecycleState: 'active');
    }
  }

  Future<void> _registerFcmTokenBestEffort(String token) async {
    try {
      await _registerFcmToken(token);
    } catch (error) {
      debugPrint('Unable to refresh the FCM registration: $error');
    }
  }

  Future<void> _handleFcmOpenBestEffort(RemoteMessage message) async {
    try {
      await _handleFcmOpen(message);
    } catch (error) {
      debugPrint('Unable to open the notification destination: $error');
    }
  }

  Future<void> _handleFcmOpen(RemoteMessage message) async {
    await DeviceNotificationLogService.recordFcmMessage(
      message,
      ownerPhoneNumber: widget.session.phoneNumber,
      opened: true,
    );
    final data = <String, dynamic>{...message.data};
    _enqueueFcmOpen(
      _PendingFcmOpen(
        key: message.messageId?.trim().isNotEmpty == true
            ? message.messageId!.trim()
            : '${message.sentTime?.millisecondsSinceEpoch ?? 0}:${data.hashCode}',
        deepLink: FcmNotificationRouter.deepLinkFor(data),
        title: message.notification?.title ?? data['title']?.toString(),
        body: message.notification?.body ?? data['body']?.toString(),
      ),
    );
  }

  void _enqueueFcmOpen(_PendingFcmOpen pending) {
    if (_handledFcmOpenKeys.contains(pending.key) ||
        _pendingFcmOpens.any((item) => item.key == pending.key)) {
      return;
    }
    _pendingFcmOpens.add(pending);
    unawaited(_drainPendingFcmOpens());
  }

  Future<void> _drainPendingFcmOpens() async {
    if (!_notificationUiReady ||
        _appLifecycleState != AppLifecycleState.resumed ||
        _isDrainingFcmOpens ||
        !mounted) {
      return;
    }
    _isDrainingFcmOpens = true;
    try {
      while (mounted &&
          _appLifecycleState == AppLifecycleState.resumed &&
          _pendingFcmOpens.isNotEmpty) {
        final pending = _pendingFcmOpens.removeAt(0);
        if (!_handledFcmOpenKeys.add(pending.key)) continue;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (pending.deepLink != null) {
          await _handleDeepLink(pending.deepLink!);
        } else {
          await _showOpenedNotificationPopup(pending);
        }
      }
    } finally {
      _isDrainingFcmOpens = false;
    }
  }

  Future<void> _showOpenedNotificationPopup(_PendingFcmOpen pending) async {
    final title = pending.title?.trim();
    final body = pending.body?.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded),
        title: Text(
          title == null || title.isEmpty ? 'HikerCircle update' : title,
        ),
        content: Text(
          body == null || body.isEmpty
              ? 'The notification was opened successfully.'
              : body,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showForegroundNotification(RemoteMessage message) {
    unawaited(
      DeviceNotificationLogService.recordFcmMessage(
        message,
        ownerPhoneNumber: widget.session.phoneNumber,
      ),
    );
    final title = message.notification?.title ?? 'HikerCircle update';
    final body = message.notification?.body ?? 'Tap to view details.';
    final type = message.data['type'];
    final deepLink = FcmNotificationRouter.deepLinkFor(<String, dynamic>{
      ...message.data,
    });

    if (type == 'active_hike_monitoring_stopped') return;

    // A team readiness request is actionable state, not just an informational
    // banner. Foreground users should see the ready interface immediately;
    // background and terminated users follow the same deep link after tapping
    // the FCM notification.
    if (type == 'team_hike_invite' && deepLink != null) {
      _enqueueFcmOpen(
        _PendingFcmOpen(
          key: message.messageId?.trim().isNotEmpty == true
              ? message.messageId!.trim()
              : 'foreground-team:${message.sentTime?.millisecondsSinceEpoch ?? 0}:${message.data.hashCode}',
          deepLink: deepLink,
          title: title,
          body: body,
        ),
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'hiker_circle_foreground',
      'HikerCircle notifications',
      channelDescription: 'In-app notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
    unawaited(
      _localNotifications
          .show(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: title,
            body: body,
            payload: jsonEncode({
              'deepLink': deepLink ?? '',
              'title': title,
              'body': body,
            }),
            notificationDetails: details,
          )
          .catchError((Object error) {
            debugPrint('Unable to show the foreground notification: $error');
          }),
    );
  }

  void _handleFcmOpenFromLocal(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) return;
    String? deepLink;
    String? title;
    String? body;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = <String, dynamic>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
        deepLink = FcmNotificationRouter.deepLinkFor(data);
        title = data['title']?.toString();
        body = data['body']?.toString();
      }
    } catch (_) {
      final uri = Uri.tryParse(payload.trim());
      if (uri?.scheme == 'hikercircle') deepLink = uri.toString();
    }
    _enqueueFcmOpen(
      _PendingFcmOpen(
        key: 'local:${response.id ?? 0}:${payload.hashCode}',
        deepLink: deepLink,
        title: title,
        body: body,
      ),
    );
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
        _rebuildPlannedHike();
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _restoreCachedUpcomingPlanningState() async {
    final revision = ++_upcomingPlanningRevision;
    try {
      final states = await hikerCircleRepository.localDatabase
          .loadPlannedHikeStates(ownerPhoneNumber: widget.session.phoneNumber);
      if (!mounted || revision != _upcomingPlanningRevision) return;
      final consumed = {
        for (final state in states)
          if (state.isConsumed) state.upcomingHike.id,
      };
      final checklist = {
        for (final state in states)
          state.upcomingHike.id: state.completedChecklistItems,
      };
      final cached = states
          .where((state) => !state.isConsumed)
          .map((state) => state.upcomingHike);
      setState(() {
        _consumedUpcomingHikeIds = Set<String>.unmodifiable(consumed);
        _plannedChecklistByUpcomingId = Map<String, Set<String>>.unmodifiable(
          checklist,
        );
        myUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
          remote: myUpcomingHikes,
          cached: cached,
          retainUnconfirmedCachedHikes: true,
          consumedHikeIds: _consumedUpcomingHikeIds,
        );
        _rebuildPlannedHike();
      });
    } catch (error) {
      debugPrint('Unable to restore planned hike state: $error');
    }
  }

  Future<void> _applyUpcomingHikeSnapshot(List<UpcomingHike> remote) async {
    final revision = ++_upcomingPlanningRevision;
    try {
      final isAuthoritative =
          widget.firebaseBootstrapResult.isAvailable &&
          NetworkReachabilityService.instance.latest.isOnline;
      await hikerCircleRepository.localDatabase.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: widget.session.phoneNumber,
        upcomingHikes: remote,
        pruneMissing: isAuthoritative,
      );
      final states = await hikerCircleRepository.localDatabase
          .loadPlannedHikeStates(ownerPhoneNumber: widget.session.phoneNumber);
      if (!mounted || revision != _upcomingPlanningRevision) return;
      final consumed = {
        for (final state in states)
          if (state.isConsumed) state.upcomingHike.id,
      };
      final checklist = {
        for (final state in states)
          state.upcomingHike.id: state.completedChecklistItems,
      };
      setState(() {
        _consumedUpcomingHikeIds = Set<String>.unmodifiable(consumed);
        _plannedChecklistByUpcomingId = Map<String, Set<String>>.unmodifiable(
          checklist,
        );
        myUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
          remote: remote,
          cached: states.map((state) => state.upcomingHike),
          retainUnconfirmedCachedHikes: !isAuthoritative,
          consumedHikeIds: _consumedUpcomingHikeIds,
        );
        _rebuildPlannedHike();
      });
    } catch (error) {
      debugPrint('Unable to reconcile planned hike state: $error');
      if (!mounted || revision != _upcomingPlanningRevision) return;
      setState(() {
        myUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
          remote: remote,
          cached: myUpcomingHikes,
          retainUnconfirmedCachedHikes: true,
          consumedHikeIds: _consumedUpcomingHikeIds,
        );
        _rebuildPlannedHike();
      });
    }
  }

  Future<void> _cacheConfirmedScheduledDraft(HikeSessionDraft draft) async {
    final pending = PlannedHikeStateResolver.provisionalFromConfirmedDraft(
      draft: draft,
      creatorPhone: widget.session.phoneNumber,
      creatorName: widget.session.username,
    );
    var snapshotToCache = pending;
    for (final existing in myUpcomingHikes) {
      if (!existing.isLocalPendingSync &&
          PlannedHikeStateResolver.representsSameSchedule(existing, pending)) {
        snapshotToCache = existing.withDraft(draft);
        break;
      }
    }
    await hikerCircleRepository.localDatabase.saveUpcomingHikesForPlanning(
      ownerPhoneNumber: widget.session.phoneNumber,
      upcomingHikes: [snapshotToCache],
    );
    final states = await hikerCircleRepository.localDatabase
        .loadPlannedHikeStates(ownerPhoneNumber: widget.session.phoneNumber);
    if (!mounted) return;
    setState(() {
      _plannedChecklistByUpcomingId = Map<String, Set<String>>.unmodifiable({
        for (final state in states)
          state.upcomingHike.id: state.completedChecklistItems,
      });
      myUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
        remote: myUpcomingHikes,
        cached: states
            .where((state) => !state.isConsumed)
            .map((state) => state.upcomingHike),
        retainUnconfirmedCachedHikes: true,
        consumedHikeIds: _consumedUpcomingHikeIds,
      );
      _rebuildPlannedHike();
    });
  }

  void _rebuildPlannedHike() {
    final next = PlannedHikeStateResolver.selectNext(myUpcomingHikes);
    plannedHike = next == null
        ? null
        : PlannedHikeStateResolver.resolve(
            upcomingHike: next,
            liveTrails: trails,
            emergencyContactsSelected: emergencyContacts.isNotEmpty,
            phoneBatteryLevel: _latestPhoneBatteryLevel,
            completedChecklistItems: _plannedChecklistByUpcomingId[next.id],
          );
  }

  Future<void> _updatePlannedHike(PlannedHike updatedPlan) async {
    final completed = GearChecklistCatalog.sanitize(
      updatedPlan.completedChecklistItems,
    );
    final normalized = updatedPlan.copyWith(
      completedChecklistItems: completed,
      checklistCompleted: completed.length,
      checklistTotal: GearChecklistCatalog.itemCount,
    );
    final hikeId = normalized.upcomingHikeId.trim();
    setState(() {
      plannedHike = normalized;
      if (hikeId.isNotEmpty) {
        _plannedChecklistByUpcomingId = Map<String, Set<String>>.unmodifiable({
          ..._plannedChecklistByUpcomingId,
          hikeId: completed,
        });
      }
    });
    if (hikeId.isNotEmpty) {
      try {
        await hikerCircleRepository.localDatabase.savePlannedHikeChecklist(
          ownerPhoneNumber: widget.session.phoneNumber,
          upcomingHikeId: hikeId,
          completedItems: completed,
        );
      } catch (error) {
        debugPrint('Unable to persist planned hike checklist: $error');
      }
    }
  }

  Future<void> _restoreActiveHikeSession() async {
    try {
      final restoredHike = await hikerCircleRepository.localDatabase
          .loadActiveHikeSession(phoneNumber: widget.session.phoneNumber);
      if (!mounted || restoredHike == null) {
        return;
      }
      setState(() {
        activeHike = restoredHike;
        selectedTabIndex = 0;
      });
      tabController.animateTo(0);
      _syncActiveHikeServices(restoredHike, forceLiveStatus: true);
      unawaited(_consumePendingNativeSafetyEvent());
    } catch (error) {
      debugPrint('Unable to restore active hike: $error');
    } finally {
      if (mounted) {
        setState(() {
          isRestoringActiveHike = false;
        });
      }
    }
  }

  Future<void> _waitForActiveHikeRestore() async {
    final restoreFuture = _activeHikeRestoreFuture;
    if (restoreFuture != null) {
      await restoreFuture;
    }
  }

  void _persistActiveHikeSnapshot(ActiveHikeSession? hike) {
    _activeHikePersistenceQueue = _activeHikePersistenceQueue.then((_) async {
      try {
        if (hike == null) {
          await hikerCircleRepository.localDatabase.clearActiveHikeSession(
            phoneNumber: widget.session.phoneNumber,
          );
        } else {
          await hikerCircleRepository.localDatabase.saveActiveHikeSession(
            phoneNumber: widget.session.phoneNumber,
            activeHike: hike,
          );
        }
      } catch (error) {
        debugPrint('Unable to persist active hike snapshot: $error');
      }
    });
  }

  Future<void> _loadInitialDeepLink() async {
    try {
      final link = await _deepLinkChannel.invokeMethod<String>(
        'consumeInitialDeepLink',
      );
      if (link != null) {
        _handleDeepLinkAfterFirstFrame(link);
      }
    } catch (_) {
      // Deep links are optional on platforms that do not expose a native hook.
    }
  }

  void _handleDeepLinkAfterFirstFrame(String link) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_handleDeepLink(link));
    });
  }

  Future<void> _handleDeepLinkMethodCall(MethodCall call) async {
    if (call.method != 'onDeepLink') {
      return;
    }
    final link = call.arguments;
    if (link is String) {
      await _handleDeepLink(link);
    }
  }

  Future<void> _handleDeepLink(String link) async {
    final now = DateTime.now();
    final lastHandledAt = _lastHandledDeepLinkAt;
    if (_lastHandledDeepLink == link &&
        lastHandledAt != null &&
        now.difference(lastHandledAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledDeepLink = link;
    _lastHandledDeepLinkAt = now;

    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'hikercircle') {
      return;
    }
    if (uri.host == 'hike') {
      await _waitForActiveHikeRestore();
      if (!mounted) {
        return;
      }
    }
    if (uri.host == 'sos' && uri.path == '/manual') {
      requestManualSos();
      return;
    }
    if (uri.host == 'sos' && uri.path == '/active') {
      // This route is intentionally non-triggering. The authenticated native
      // BLE event queue performs the SOS action; a notification tap only
      // restores the current SOS screen and its local STOP control.
      openSosTab();
      return;
    }
    if (uri.host == 'sos' && uri.path == '/help') {
      // Nearby-help coordinates are trusted only after native BLE packet
      // validation. A public custom URL must not be able to forge an SOS.
      return;
    }
    if (uri.host == 'sos' && uri.path == '/instant') {
      if (await _confirmExternalSosTrigger(SosAlertMode.manual)) {
        requestImmediateSos(SosAlertMode.manual);
      }
      return;
    }
    if (uri.host == 'sos' && uri.path == '/paired') {
      // Authenticated paired-button events are accepted only from the native
      // BLE event channel. Custom URL parameters are untrusted input.
      return;
    }
    if (uri.host == 'sos' && uri.path == '/nearby-button') {
      // Nearby button events must come from the native BLE scanner so their
      // packet validation, replay protection, and RSSI metadata are genuine.
      return;
    }
    if (uri.host == 'sos' && uri.path == '/nearby-button-location') {
      return;
    }
    if (uri.host == 'sos' && uri.path == '/medical') {
      if (await _confirmExternalSosTrigger(SosAlertMode.medical)) {
        requestImmediateSos(SosAlertMode.medical);
      }
      return;
    }
    if (uri.host == 'sos' && uri.path == '/duress') {
      if (await _confirmExternalSosTrigger(SosAlertMode.duress)) {
        requestImmediateSos(SosAlertMode.duress);
      }
      return;
    }
    if (uri.host == 'hike' && uri.path == '/active') {
      if (!_deepLinkMatchesActiveHike(uri)) return;
      _openActiveHikeDetailsFromDeepLink();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/safety') {
      await _consumePendingNativeSafetyEvent();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/safety-safe') {
      _cancelFallStillnessSos('Safety popup response received');
      return;
    }
    if (uri.host == 'hike' && uri.path == '/check-in') {
      if (!_deepLinkMatchesActiveHike(uri)) return;
      _checkInFromLiveStatusAction();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/pin') {
      if (!_deepLinkMatchesActiveHike(uri)) return;
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
    if (uri.host == 'upcoming-hike' && uri.path == '/view') {
      final hikeId = uri.queryParameters['upcomingHikeId'] ?? '';
      if (hikeId.isNotEmpty) {
        unawaited(_openUpcomingHikeFromDeepLink(hikeId));
      }
      return;
    }
    if (uri.host == 'upcoming-hike' && uri.path == '/join-request') {
      final requestId = uri.queryParameters['requestId'] ?? '';
      if (requestId.isNotEmpty) {
        unawaited(_openUpcomingHikeJoinRequest(requestId));
      }
      return;
    }
    if (uri.host == 'group-chat' && uri.path == '/view') {
      final chatId = uri.queryParameters['chatId'] ?? '';
      if (chatId.isNotEmpty) {
        unawaited(_openGroupChatFromDeepLink(chatId));
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
      _showAddBuddyPrompt(name: name, handle: handle, phoneNumber: phone);
    });
  }

  Future<bool> _confirmExternalSosTrigger(SosAlertMode mode) async {
    if (!mounted) return false;
    return await showCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: Text('Trigger ${mode.label}?'),
            content: const Text(
              'This request came from an app link. Confirm only if you intend '
              'to notify your emergency contacts now.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Trigger SOS'),
              ),
            ],
          ),
        ) ??
        false;
  }

  bool _deepLinkMatchesActiveHike(Uri uri) {
    final currentSessionId = activeHike?.sessionId ?? '';
    final requestedSessionId = uri.queryParameters['sessionId']?.trim() ?? '';
    final matches =
        currentSessionId.isNotEmpty &&
        requestedSessionId.isNotEmpty &&
        requestedSessionId == currentSessionId;
    if (!matches && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This action belongs to a different or ended hike.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    return matches;
  }

  Future<void> _openUpcomingHikeFromDeepLink(String hikeId) async {
    if (!mounted) {
      return;
    }
    final progressReady = Completer<BuildContext>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          if (!progressReady.isCompleted) {
            progressReady.complete(dialogContext);
          }
          return const PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: HikerCircleLoadingToast(
                message: 'Loading upcoming hike…',
                detail: 'Getting the latest hike and trail details.',
                compact: true,
              ),
            ),
          );
        },
      ),
    );
    final progressContext = await progressReady.future;
    List<Object?> results;
    try {
      results = await Future.wait<Object?>([
        hikerCircleRepository.loadUpcomingHikeById(hikeId),
        hikerCircleRepository.loadTrails().catchError((_) => <Trail>[]),
      ]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to load this hike. Check your connection.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    } finally {
      if (progressContext.mounted) {
        Navigator.of(progressContext).pop();
      }
    }
    if (!mounted) {
      return;
    }
    final hike = results[0] as UpcomingHike?;
    final notificationTrails = results[1] as List<Trail>;
    if (hike == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This upcoming hike is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    await _showUpcomingHikeDetails(hike, availableTrails: notificationTrails);
  }

  Future<void> _openUpcomingHikeJoinRequest(String requestId) async {
    final normalizedId = requestId.trim();
    if (!mounted ||
        !RegExp(r'^join_[a-f0-9]{48}$').hasMatch(normalizedId) ||
        _activeUpcomingJoinRequestReviewId == normalizedId ||
        _completedUpcomingJoinRequestReviewIds.contains(normalizedId)) {
      return;
    }
    _activeUpcomingJoinRequestReviewId = normalizedId;
    final progressReady = Completer<BuildContext>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          if (!progressReady.isCompleted) progressReady.complete(dialogContext);
          return const PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: HikerCircleLoadingToast(
                message: 'Checking join request…',
                detail: 'Confirming the hike and request status.',
                compact: true,
              ),
            ),
          );
        },
      ),
    );
    final progressContext = await progressReady.future;
    UpcomingHikeJoinRequestReview? review;
    try {
      review = await hikerCircleRepository.loadUpcomingHikeJoinRequest(
        normalizedId,
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
    } finally {
      if (progressContext.mounted) Navigator.of(progressContext).pop();
    }
    if (!mounted || review == null) {
      _finishUpcomingJoinRequestReview();
      return;
    }
    if (review.status != 'pending') {
      _completedUpcomingJoinRequestReviewIds.add(normalizedId);
      _finishUpcomingJoinRequestReview();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              review.status == 'accepted'
                  ? 'This join request was already accepted.'
                  : review.status == 'rejected'
                  ? 'This join request was already declined.'
                  : 'This join request is no longer available.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final result = await showDialog<UpcomingHikeJoinRequestReview>(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpcomingHikeJoinRequestDialog(
        review: review!,
        onResolve: (accept) =>
            hikerCircleRepository.resolveUpcomingHikeJoinRequest(
              requestId: normalizedId,
              accept: accept,
            ),
      ),
    );
    if (result != null && result.status != 'pending') {
      // Android/iOS can deliver the same universal link through the initial
      // intent, method channel and notification callback. Keep the resolved
      // request id for this app process so a late duplicate cannot reopen it.
      _completedUpcomingJoinRequestReviewIds.add(normalizedId);
    }
    _activeUpcomingJoinRequestReviewId = null;
    if (!mounted || result == null) {
      _finishUpcomingJoinRequestReview();
      return;
    }
    if (result.status == 'accepted') {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${result.requesterName} was added to the hike.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      if (result.needsJoinPolicyChoice) {
        await _chooseFutureJoinPolicy(result.hikeId);
      }
    } else if (result.status == 'rejected') {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Join request declined.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    _finishUpcomingJoinRequestReview();
  }

  Future<void> _chooseFutureJoinPolicy(String hikeId) async {
    if (!mounted) return;
    final policy = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.groups_2_rounded, color: Color(0xFF34A853)),
        title: const Text('Your group hike is ready'),
        content: const Text(
          'A team has now been formed. Choose how future hikers can join this upcoming hike.',
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop('approval'),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Needs approval'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop('open'),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Open to join'),
          ),
        ],
      ),
    );
    if (!mounted || policy == null) return;
    try {
      await hikerCircleRepository.setUpcomingHikeJoinPolicy(
        hikeId: hikeId,
        joinPolicy: policy,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              policy == 'open'
                  ? 'This hike is now open to join.'
                  : 'Future join requests will need your approval.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _finishUpcomingJoinRequestReview() {
    _activeUpcomingJoinRequestReviewId = null;
    final pendingChats = _pendingFormedTeamChats;
    _pendingFormedTeamChats = const [];
    if (pendingChats.isNotEmpty) {
      _promptForFormedTeamChatName(pendingChats);
    }
  }

  Future<void> _openGroupChatFromDeepLink(String chatId) async {
    if (!mounted) {
      return;
    }
    final progressReady = Completer<BuildContext>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          if (!progressReady.isCompleted) {
            progressReady.complete(dialogContext);
          }
          return const PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: HikerCircleLoadingToast(
                message: 'Opening group chat…',
                detail: 'Loading the hike team and recent messages.',
                compact: true,
              ),
            ),
          );
        },
      ),
    );
    final progressContext = await progressReady.future;
    GroupChat? chat;
    try {
      chat = await hikerCircleRepository.loadGroupChatById(chatId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to open this chat. Check your connection.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    } finally {
      if (progressContext.mounted) {
        Navigator.of(progressContext).pop();
      }
    }
    if (!mounted) {
      return;
    }
    if (chat == null ||
        !chat.participantPhones.contains(widget.session.phoneNumber)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('This group chat is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final availableChat = chat;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GroupChatDetailPage(
          chat: availableChat,
          session: widget.session,
          repository: hikerCircleRepository,
        ),
      ),
    );
  }

  Future<void> _showAddBuddyPrompt({
    required String name,
    required String handle,
    required String phoneNumber,
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
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Theme.of(context).colorScheme.primary,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

    if (phoneNumber.isNotEmpty) {
      try {
        await hikerCircleRepository.sendBuddyRequest(
          session: widget.session,
          buddyPhoneNumber: phoneNumber,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Unable to send buddy request: $error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
    }
    if (!mounted) return;

    setState(() {
      selectedTabIndex = 2;
    });
    tabController.animateTo(2);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            phoneNumber.isEmpty
                ? '$name added to your buddies.'
                : 'Friend request sent to $name.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> loadLiveData() async {
    setState(() {
      isLoadingLiveData = true;
    });
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) setState(() => isLoadingLiveData = false);
    });
    try {
      _trailsSubscription?.cancel();
      _trailsSubscription = hikerCircleRepository.watchTrails().listen(
        (liveTrails) {
          if (!mounted) return;
          setState(() {
            trails = liveTrails;
            isLoadingLiveData = false;
            _rebuildPlannedHike();
          });
          if (widget.session.isAdmin && !_trailRegionRepairStarted) {
            _trailRegionRepairStarted = true;
            unawaited(_repairTrailRegions(liveTrails));
          }
        },
        onError: (_) {
          if (mounted) setState(() => isLoadingLiveData = false);
        },
      );
      _myUpcomingHikesSubscription?.cancel();
      _myUpcomingHikesSubscription = hikerCircleRepository
          .watchMyUpcomingHikes(widget.session.phoneNumber)
          .listen(
            (hikes) {
              if (!mounted) return;
              unawaited(_applyUpcomingHikeSnapshot(hikes));
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Upcoming hike updates are unavailable: $error');
            },
          );
      unawaited(
        hikerCircleRepository.ensureAchievementSeeds().catchError((
          Object error,
        ) {
          debugPrint('Achievement seed sync was skipped: $error');
        }),
      );
    } catch (_) {
      if (mounted) {
        setState(() => isLoadingLiveData = false);
      }
    }
  }

  Future<void> _repairTrailRegions(List<Trail> liveTrails) async {
    for (final trail in liveTrails) {
      try {
        var region = await WorldwideRegionCatalog.normalize(
          country: trail.country,
          state: trail.state,
        );
        if (region == null &&
            trail.latitude.isFinite &&
            trail.longitude.isFinite) {
          final resolved = await GoogleCityGeocodingService().resolveCity(
            latitude: trail.latitude,
            longitude: trail.longitude,
          );
          region = await WorldwideRegionCatalog.normalize(
            country: resolved.country,
            state: resolved.state,
          );
        }
        if (region == null ||
            (region.country == trail.country && region.state == trail.state)) {
          continue;
        }
        await hikerCircleRepository.updateTrailByAdmin(
          session: widget.session,
          trail: trail.copyWith(country: region.country, state: region.state),
        );
      } catch (error) {
        debugPrint('Unable to normalize ${trail.name} region: $error');
      }
    }
  }

  Future<void> addTrailByAdminFromHome() async {
    if (!widget.session.isAdmin) {
      return;
    }

    final trail = await showAddTrailSheet(
      context,
      session: widget.session,
      repository: hikerCircleRepository,
    );
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

  Future<int?> _readBatteryLevel() => _sosDeviceAlertService.getBatteryLevel();

  Future<void> _refreshBatteryLevel() async {
    final batteryLevel = await _sosDeviceAlertService.getBatteryLevel();
    if (batteryLevel == null || !mounted) {
      return;
    }

    final currentActiveHike = activeHike;
    setState(() {
      _latestPhoneBatteryLevel = batteryLevel;
      _rebuildPlannedHike();
      if (currentActiveHike != null) {
        activeHike = currentActiveHike.copyWith(batteryLevel: batteryLevel);
      }
    });

    final updatedActiveHike = activeHike;
    if (updatedActiveHike != null) {
      _persistActiveHikeSnapshot(updatedActiveHike);
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
      if (activeHike != null) {
        final visible = _visibleTabs();
        final currentLabel = tabs[tabController.index].label;
        final visibleIndex = visible.indexWhere((t) => t.label == currentLabel);
        if (visibleIndex >= 0) {
          setState(() {
            selectedTabIndex = visibleIndex;
          });
        }
      } else {
        setState(() {
          selectedTabIndex = tabController.index;
        });
      }
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
        selectedTabIndex = index;
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

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StartHikeWizardPage(
          preselectedTrail: trail,
          availableTrails: trails,
          repository: hikerCircleRepository,
          session: widget.session,
          emergencyContactNames: emergencyContacts
              .map((contact) => contact.name)
              .toList(),
          onScheduled: _cacheConfirmedScheduledDraft,
          onStartNow: _startInstantHikeFromWizard,
        ),
      ),
    );
  }

  Future<bool> _startInstantHikeFromWizard(HikeSessionDraft draft) async {
    if (!mounted) return false;
    var hikeToStart = ActiveHikeSession.fromDraft(draft);
    if (hikeToStart.draft.hikeType == HikeType.team) {
      final teamSession = await _coordinateTeamHikeStart(hikeToStart.draft);
      if (teamSession == null || !mounted) {
        return false;
      }
      final preparedDraft = _applyTeamSafetySettings(
        hikeToStart.draft,
        teamSession,
      );
      hikeToStart = hikeToStart.copyWith(
        draft: preparedDraft,
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
        return false;
      }
    }
    if (!await _ensureBackgroundSafetyReady(hikeToStart.draft) || !mounted) {
      return false;
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
    final batteryFuture = _readBatteryLevel();
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
        teamHikeSession: hikeToStart.teamHikeSession,
      );
      liveHike = liveHike.copyWith(
        teamHikeSession: hikeToStart.teamHikeSession,
      );
      final batteryLevel = await batteryFuture;
      if (batteryLevel != null) {
        liveHike = liveHike.copyWith(
          batteryLevel: batteryLevel,
          batteryStartedLevel: batteryLevel,
        );
      }
      startProgress.value = const _HikeStartProgress(
        title: 'Activating live tracking',
        message: 'Starting fall detection and live hike status.',
        progress: 0.72,
        icon: Icons.sensors_rounded,
      );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!error.allowsOfflineFallback) {
        startProgress.value = _HikeStartProgress(
          title: 'Unable to start hike',
          message: error.message,
          progress: 1,
          icon: Icons.error_outline_rounded,
        );
        closeStartProgressDialog();
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(error.message),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
        }
        return false;
      }
      startProgress.value = const _HikeStartProgress(
        title: 'Starting offline mode',
        message: 'Network setup is unavailable, so this hike will run locally.',
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
      return false;
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
    return true;
  }

  Future<TeamHikeSession?> _coordinateTeamHikeStart(
    HikeSessionDraft draft, {
    String sourceUpcomingHikeId = '',
  }) async {
    TeamHikeSession teamSession;
    try {
      teamSession = await hikerCircleRepository.createTeamHikeSession(
        session: widget.session,
        draft: draft,
        sourceUpcomingHikeId: sourceUpcomingHikeId,
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

    _navigatingTeamSessionId = teamSession.id;
    try {
      final launchedSession = await Navigator.of(context).push<TeamHikeSession>(
        MaterialPageRoute<TeamHikeSession>(
          fullscreenDialog: true,
          builder: (context) {
            return _TeamHikeLaunchPage(
              session: widget.session,
              repository: hikerCircleRepository,
              deviceAlertService: _sosDeviceAlertService,
              initialTeamSession: teamSession,
            );
          },
        ),
      );
      if (launchedSession == null && sourceUpcomingHikeId.trim().isEmpty) {
        try {
          await hikerCircleRepository.cancelTeamHikeSession(
            session: widget.session,
            teamHikeSessionId: teamSession.id,
          );
        } catch (_) {
          // A concurrent start wins over cancellation; the session stream will
          // still deliver the active state to participants.
        }
      }
      return launchedSession;
    } finally {
      if (_navigatingTeamSessionId == teamSession.id) {
        _navigatingTeamSessionId = null;
      }
    }
  }

  Future<void> _recordInitialActiveHikeLocation(ActiveHikeSession hike) async {
    try {
      final location =
          await LocationSnapshotService.instance.refresh() ??
          LocationSnapshotService.instance.latestLocation;
      if (location == null || !_isAcceptableTrackingLocation(hike, location)) {
        return;
      }
      final batteryLevel = await _readBatteryLevel();

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
      _persistActiveHikeSnapshot(updatedHike);
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
    final refreshedLocation = await LocationSnapshotService.instance.refresh();
    final location =
        refreshedLocation != null &&
            _isAcceptableTrackingLocation(currentHike, refreshedLocation)
        ? refreshedLocation
        : null;
    final checkedInAt = DateTime.now();
    final batteryLevel = await _readBatteryLevel();
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
      final updatedHike =
          _hikeWithRecordedLocation(
            hikeWithBattery,
            location,
            checkIns: currentHike.checkIns + 1,
            queuedUpdates: queuedUpdates,
          ).copyWith(
            checkInRecords: [
              ...currentHike.checkInRecords,
              HikeCheckInRecord(
                id: 'check_in_${checkedInAt.microsecondsSinceEpoch}',
                checkedInAt: checkedInAt,
                coordinate: HikeCoordinate.fromTriggerLocation(location),
              ),
            ],
          );
      _syncTeamHikeLocation(updatedHike, location);
      return updatedHike;
    }

    return hikeWithBattery.copyWith(
      checkIns: currentHike.checkIns + 1,
      queuedUpdates: currentHike.queuedUpdates,
      checkInRecords: [
        ...currentHike.checkInRecords,
        HikeCheckInRecord(
          id: 'check_in_${checkedInAt.microsecondsSinceEpoch}',
          checkedInAt: checkedInAt,
        ),
      ],
    );
  }

  Future<PinLocationResult> pinCurrentLocation(
    ActiveHikeSession currentHike,
  ) async {
    final location = await LocationSnapshotService.instance.refresh();
    final batteryLevel = await _readBatteryLevel();
    final hikeWithBattery = currentHike.copyWith(batteryLevel: batteryLevel);
    if (location == null ||
        !_isAcceptableTrackingLocation(currentHike, location)) {
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
    await hikerCircleRepository.recordAchievementMetric(
      session: widget.session,
      metricKey: 'manual_pin_added',
    );
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
        final updatedHike = _withTeamHikeSessionLink(currentHike, teamSession);
        setState(() {
          activeHike = updatedHike;
        });
        _persistActiveHikeSnapshot(updatedHike);
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
          builder: (context) => ActiveHikeMapPage(
            activeHike: hike,
            currentPhoneNumber: widget.session.phoneNumber,
          ),
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
    if (_isCheckInBusy || activeHike?.sessionId != hike.sessionId) return;
    _isCheckInBusy = true;
    try {
      final updatedHike = await checkInActiveHike(hike);
      if (!mounted || activeHike?.sessionId != hike.sessionId) return;
      setState(() => activeHike = updatedHike);
      _syncActiveHikeServices(updatedHike, forceLiveStatus: true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Check-in saved from live hike status.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      _showActiveHikeActionError('Unable to save check-in', error);
    } finally {
      _isCheckInBusy = false;
    }
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
    if (_isPinLocationBusy || activeHike?.sessionId != hike.sessionId) return;
    _isPinLocationBusy = true;
    try {
      final result = await pinCurrentLocation(hike);
      if (!mounted || activeHike?.sessionId != hike.sessionId) return;
      setState(() => activeHike = result.hike);
      _syncActiveHikeServices(result.hike, forceLiveStatus: true);
      final message = switch (result.status) {
        PinLocationStatus.pinned => 'Checkpoint pinned from live hike status.',
        PinLocationStatus.duplicate =>
          'This location is already pinned before.',
        PinLocationStatus.unavailable =>
          'GPS is unavailable, so no pin was added.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } catch (error) {
      _showActiveHikeActionError('Unable to pin this location', error);
    } finally {
      _isPinLocationBusy = false;
    }
  }

  Future<void> _applyActiveHikeCheckIn(ActiveHikeSession hike) async {
    if (_isCheckInBusy || activeHike?.sessionId != hike.sessionId) return;
    _isCheckInBusy = true;
    try {
      final updatedHike = await checkInActiveHike(hike);
      if (!mounted || activeHike?.sessionId != hike.sessionId) return;
      setState(() => activeHike = updatedHike);
      _syncActiveHikeServices(updatedHike, forceLiveStatus: true);
    } catch (error) {
      _showActiveHikeActionError('Unable to save check-in', error);
    } finally {
      _isCheckInBusy = false;
    }
  }

  Future<void> _applyActiveHikePin(ActiveHikeSession hike) async {
    if (_isPinLocationBusy || activeHike?.sessionId != hike.sessionId) return;
    _isPinLocationBusy = true;
    try {
      final result = await pinCurrentLocation(hike);
      if (!mounted || activeHike?.sessionId != hike.sessionId) return;
      setState(() => activeHike = result.hike);
      _syncActiveHikeServices(result.hike, forceLiveStatus: true);
    } catch (error) {
      _showActiveHikeActionError('Unable to pin this location', error);
    } finally {
      _isPinLocationBusy = false;
    }
  }

  void _showActiveHikeActionError(String prefix, Object error) {
    if (!mounted) return;
    final detail = error is HikerCircleFirebaseRepositoryException
        ? error.message
        : 'Please check GPS and connectivity, then try again.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$prefix. $detail'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
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

  Future<void> _showUpcomingHikeDetails(
    UpcomingHike hike, {
    Iterable<Trail>? availableTrails,
  }) async {
    Trail? trail;
    for (final t in availableTrails ?? trails) {
      if (t.trailId == hike.trailId) {
        trail = t;
        break;
      }
    }
    if (trail == null && availableTrails != null) {
      for (final t in trails) {
        if (t.trailId == hike.trailId) {
          trail = t;
          break;
        }
      }
    }
    trail ??= hike.draft?.trail;
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
    } else if (result == 'directions') {
      await _openUpcomingHikeDirections(hike);
    } else if (result == 'start' && trail != null) {
      if (hike.isLocalPendingSync) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'This scheduled hike is still syncing. Reconnect before starting it.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      await _startUpcomingHikeNow(
        hike: hike,
        draft: _draftForUpcomingHike(hike, trail),
      );
    }
  }

  Future<void> _openUpcomingHikeDirections(UpcomingHike hike) async {
    if (!hike.latitude.isFinite ||
        !hike.longitude.isFinite ||
        hike.latitude < -90 ||
        hike.latitude > 90 ||
        hike.longitude < -180 ||
        hike.longitude > 180) {
      _showUpcomingHikeError(
        'Directions unavailable',
        'This hike does not have a valid trailhead location.',
      );
      return;
    }
    final destination = '${hike.latitude},${hike.longitude}';
    final googleUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
    });
    final wazeUri = Uri.https('waze.com', '/ul', {
      'll': destination,
      'navigate': 'yes',
    });
    try {
      var launched = false;
      if (await canLaunchUrl(googleUri)) {
        launched = await launchUrl(
          googleUri,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched && await canLaunchUrl(wazeUri)) {
        launched = await launchUrl(
          wazeUri,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched && mounted) {
        _showUpcomingHikeError(
          'Directions unavailable',
          'No compatible maps app is available on this phone.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showUpcomingHikeError(
          'Directions unavailable',
          'The phone could not open directions to this trailhead.',
        );
      }
    }
  }

  void _showUpcomingHikeError(String title, String detail) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$title. $detail'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
  }

  Future<void> _startHikeFromDashboard(Trail? trail) async {
    final plan = plannedHike;
    if (plan != null &&
        trail != null &&
        plan.trail.trailId == trail.trailId &&
        plan.upcomingHikeId.isNotEmpty) {
      UpcomingHike? upcoming;
      for (final hike in myUpcomingHikes) {
        if (hike.id == plan.upcomingHikeId) {
          upcoming = hike;
          break;
        }
      }
      if (upcoming != null) {
        if (upcoming.isLocalPendingSync) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'This scheduled hike is still syncing. Reconnect before starting it.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          return;
        }
        if (!_sameTeamPhone(
          upcoming.creatorPhone,
          widget.session.phoneNumber,
        )) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'The hike host must start team readiness. Open the hike details to follow its status.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          return;
        }
        await _startUpcomingHikeNow(
          hike: upcoming,
          draft: _draftForUpcomingHike(upcoming, plan.trail),
        );
        return;
      }
    }
    await openStartHikeWizard(trail);
  }

  HikeSessionDraft _draftForUpcomingHike(UpcomingHike hike, Trail trail) {
    final savedDraft = hike.draft;
    final hikeType =
        hike.hikeType.trim().toLowerCase() == HikeType.team.name ||
            hike.participantCount > 1
        ? HikeType.team
        : HikeType.solo;
    final savedBuddies = {
      for (final buddy in savedDraft?.teamBuddies ?? const <TeamHikeBuddy>[])
        buddy.phoneNumber.replaceAll(RegExp(r'[^0-9]'), ''): buddy,
    };
    final buddies = hike.participantPhones
        .where((phone) => !_sameTeamPhone(phone, widget.session.phoneNumber))
        .map((phone) {
          final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
          return savedBuddies[key] ??
              TeamHikeBuddy(name: phone, handle: '', phoneNumber: phone);
        })
        .toList();
    final base = savedDraft ?? HikeSessionDraft.fromTrail(trail);
    final completed = GearChecklistCatalog.sanitize(
      _plannedChecklistByUpcomingId[hike.id] ??
          savedDraft?.completedChecklistItems ??
          const <String>{},
    );
    return base.copyWith(
      hikeType: hikeType,
      trail: trail,
      startPointName: hike.startPointName.trim().isEmpty
          ? base.startPointName
          : hike.startPointName,
      destinationName: hike.destinationName.trim().isEmpty
          ? base.destinationName
          : hike.destinationName,
      departureTime: hike.departureTime,
      expectedArrivalTime:
          savedDraft?.expectedArrivalTime ??
          hike.departureTime.add(
            Duration(minutes: math.max(1, hike.durationMinutes)),
          ),
      expectedReturnTime: hike.expectedReturnTime,
      emergencyContactNames: emergencyContacts
          .map((contact) => contact.name.trim())
          .where((name) => name.isNotEmpty)
          .toList(),
      completedChecklistItems: completed,
      teamBuddies: buddies,
    );
  }

  Future<void> _startUpcomingHikeNow({
    required UpcomingHike hike,
    required HikeSessionDraft draft,
  }) async {
    var hikeToStart = ActiveHikeSession.fromDraft(
      draft,
      sourceUpcomingHikeId: hike.id,
    );
    if (draft.hikeType == HikeType.team && draft.teamBuddies.isNotEmpty) {
      final teamSession = await _coordinateTeamHikeStart(
        draft,
        sourceUpcomingHikeId: hike.id,
      );
      if (teamSession == null || !mounted) return;
      hikeToStart = hikeToStart.copyWith(
        draft: _applyTeamSafetySettings(draft, teamSession),
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
        proceedLabel: 'Start Hike',
      );
      if (!volumeReady || !mounted) return;
    }
    if (!await _ensureBackgroundSafetyReady(hikeToStart.draft) || !mounted) {
      return;
    }
    final startProgress = ValueNotifier<_HikeStartProgress>(
      const _HikeStartProgress(
        title: 'Starting scheduled hike',
        message: 'Preparing your route and safety tools.',
        progress: 0.18,
        icon: Icons.hiking_rounded,
      ),
    );
    final progressContextReady = Completer<BuildContext>();
    final progressDialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!progressContextReady.isCompleted) {
          progressContextReady.complete(dialogContext);
        }
        return _HikeStartProgressDialog(progress: startProgress);
      },
    );
    unawaited(progressDialogFuture);
    final progressContext = await progressContextReady.future;

    ActiveHikeSession liveHike = hikeToStart;
    var startedOffline = false;
    try {
      try {
        startProgress.value = const _HikeStartProgress(
          title: 'Creating live session',
          message: 'Saving the hike and emergency configuration.',
          progress: 0.42,
          icon: Icons.route_rounded,
        );
        liveHike = await hikerCircleRepository.createActiveHikeSession(
          session: widget.session,
          draft: hikeToStart.draft,
          teamHikeSessionId: hikeToStart.teamHikeSessionId,
          teamHikeSession: hikeToStart.teamHikeSession,
          sourceUpcomingHikeId: hike.id,
        );
      } on HikerCircleFirebaseRepositoryException catch (error) {
        if (!error.allowsOfflineFallback) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(error.message),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
          }
          return;
        }
        startedOffline = true;
      }

      startProgress.value = const _HikeStartProgress(
        title: 'Activating safety tracking',
        message: 'Checking battery and starting live monitoring.',
        progress: 0.68,
        icon: Icons.health_and_safety_rounded,
      );
      final batteryLevel = await _readBatteryLevel();
      if (batteryLevel != null) {
        liveHike = liveHike.copyWith(
          batteryLevel: batteryLevel,
          batteryStartedLevel: batteryLevel,
        );
      }
      if (!mounted) return;

      startProgress.value = const _HikeStartProgress(
        title: 'Opening active hike',
        message: 'Loading your navigation map and hike controls.',
        progress: 0.9,
        icon: Icons.map_rounded,
      );
      setState(() {
        activeHike = liveHike;
        selectedTabIndex = 0;
        _consumedUpcomingHikeIds = Set<String>.unmodifiable({
          ..._consumedUpcomingHikeIds,
          hike.id,
        });
        myUpcomingHikes = myUpcomingHikes
            .where((upcoming) => upcoming.id != hike.id)
            .toList(growable: false);
        _rebuildPlannedHike();
      });
      unawaited(
        hikerCircleRepository.localDatabase.markPlannedHikeConsumed(
          ownerPhoneNumber: widget.session.phoneNumber,
          upcomingHikeId: hike.id,
        ),
      );
      _syncActiveHikeServices(liveHike, forceLiveStatus: true);
      await _activeHikePersistenceQueue;
      if (!mounted) return;
      tabController.animateTo(0);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    } finally {
      if (progressContext.mounted) {
        Navigator.of(progressContext).pop();
      }
      unawaited(progressDialogFuture.whenComplete(startProgress.dispose));
    }
    if (!mounted) return;
    if (startedOffline) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Cloud connection is unavailable. Tracking started offline and will sync when you reconnect.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    unawaited(_recordInitialActiveHikeLocation(liveHike));
  }

  HikeSessionDraft _applyTeamSafetySettings(
    HikeSessionDraft draft,
    TeamHikeSession teamSession,
  ) {
    TeamHikeParticipant? participant;
    for (final item in teamSession.participants) {
      if (_sameTeamPhone(item.phoneNumber, widget.session.phoneNumber)) {
        participant = item;
        break;
      }
    }
    final safety = participant?.safetySettings ?? const <String, dynamic>{};
    return draft.copyWith(
      shareLiveLocation: true,
      pathDeviationEnabled: true,
      fallDetectionEnabled: true,
      fallDetectionSettings: FallDetectionSettings(
        sensorSensitivity:
            _finiteDoubleValue(safety['sensorSensitivity'])?.clamp(
              FallDetectionSettings.minSensorSensitivity,
              FallDetectionSettings.maxSensorSensitivity,
            ) ??
            draft.fallDetectionSettings.sensorSensitivity,
        fallResponseDuration: Duration(
          seconds:
              _boundedIntValue(
                safety['fallResponseDurationSeconds'],
                minimum: 5,
                maximum: 600,
              ) ??
              _boundedIntValue(
                safety['responseCountdownSeconds'],
                minimum: 5,
                maximum: 600,
              ) ??
              draft.fallDetectionSettings.fallResponseDuration.inSeconds,
        ),
        longestRestDuration: Duration(
          seconds:
              _boundedIntValue(
                safety['longestRestDurationSeconds'],
                minimum: 30,
                maximum: 86400,
              ) ??
              draft.fallDetectionSettings.longestRestDuration.inSeconds,
        ),
      ),
    );
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

  String? _navigatingTeamSessionId;

  Future<void> _openTeamHikeInvite(String teamHikeSessionId) async {
    if (_navigatingTeamSessionId == teamHikeSessionId) return;
    _navigatingTeamSessionId = teamHikeSessionId;
    try {
      if (!mounted) {
        _navigatingTeamSessionId = null;
        return;
      }
      final pendingSession = await hikerCircleRepository.loadTeamHikeSession(
        teamHikeSessionId,
      );
      if (pendingSession == null ||
          pendingSession.phase == TeamHikePhase.completed ||
          !pendingSession.participants.any(
            (participant) => _sameTeamPhone(
              participant.phoneNumber,
              widget.session.phoneNumber,
            ),
          )) {
        throw const HikerCircleFirebaseRepositoryException(
          'This team hike invitation is no longer available.',
        );
      }
      Trail? trail = pendingSession.sharedDraft?.trail;
      for (final candidate in trails) {
        if (candidate.trailId == pendingSession.trailId) {
          trail = candidate;
          break;
        }
      }
      if (trail == null || trail.trailId.trim().isEmpty) {
        throw const HikerCircleFirebaseRepositoryException(
          'This trail is unavailable, so the invitation was not accepted.',
        );
      }
      final acceptedSession = await hikerCircleRepository.acceptTeamHikeInvite(
        session: widget.session,
        teamHikeSessionId: teamHikeSessionId,
      );
      if (!mounted) {
        return;
      }
      final currentHike = activeHike;
      if (currentHike != null &&
          currentHike.teamHikeSessionId == teamHikeSessionId) {
        final updatedHike = currentHike.copyWith(
          teamHikeSession: acceptedSession,
        );
        setState(() {
          activeHike = updatedHike;
          selectedTabIndex = 0;
        });
        _persistActiveHikeSnapshot(updatedHike);
        tabController.animateTo(0);
        return;
      }
      final sharedDraft =
          acceptedSession.sharedDraft ?? pendingSession.sharedDraft;
      final draft = (sharedDraft ?? HikeSessionDraft.fromTrail(trail)).copyWith(
        trail: trail,
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
              deviceAlertService: _sosDeviceAlertService,
              initialTeamSession: acceptedSession,
            );
          },
        ),
      );
      if (launchedSession == null || !mounted) {
        return;
      }
      final participant = launchedSession.participants
          .where(
            (item) =>
                _sameTeamPhone(item.phoneNumber, widget.session.phoneNumber),
          )
          .firstOrNull;
      final safety = participant?.safetySettings ?? const <String, dynamic>{};
      final preparedDraft = draft.copyWith(
        shareLiveLocation: true,
        pathDeviationEnabled: true,
        fallDetectionEnabled: true,
        fallDetectionSettings: FallDetectionSettings(
          sensorSensitivity:
              _finiteDoubleValue(safety['sensorSensitivity'])?.clamp(
                FallDetectionSettings.minSensorSensitivity,
                FallDetectionSettings.maxSensorSensitivity,
              ) ??
              draft.fallDetectionSettings.sensorSensitivity,
          fallResponseDuration: Duration(
            seconds:
                _boundedIntValue(
                  safety['fallResponseDurationSeconds'],
                  minimum: 5,
                  maximum: 600,
                ) ??
                _boundedIntValue(
                  safety['responseCountdownSeconds'],
                  minimum: 5,
                  maximum: 600,
                ) ??
                draft.fallDetectionSettings.fallResponseDuration.inSeconds,
          ),
          longestRestDuration: Duration(
            seconds:
                _boundedIntValue(
                  safety['longestRestDurationSeconds'],
                  minimum: 30,
                  maximum: 86400,
                ) ??
                draft.fallDetectionSettings.longestRestDuration.inSeconds,
          ),
        ),
      );
      final preparedHike = ActiveHikeSession.fromDraft(
        preparedDraft,
        teamHikeSessionId: launchedSession.id,
        teamHikeSession: launchedSession,
        sourceUpcomingHikeId: launchedSession.sourceUpcomingHikeId,
      );
      ActiveHikeSession liveHike;
      try {
        liveHike = await hikerCircleRepository.createActiveHikeSession(
          session: widget.session,
          draft: preparedHike.draft,
          teamHikeSessionId: launchedSession.id,
          teamHikeSession: launchedSession,
          sourceUpcomingHikeId: launchedSession.sourceUpcomingHikeId,
        );
      } on HikerCircleFirebaseRepositoryException catch (error) {
        if (!error.allowsOfflineFallback) rethrow;
        liveHike = preparedHike;
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Cloud connection is unavailable. Team tracking started offline and will sync when you reconnect.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
      }
      final batteryLevel = await _readBatteryLevel();
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
      await _activeHikePersistenceQueue;
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
    } finally {
      _navigatingTeamSessionId = null;
    }
  }

  Future<void> _respondToTeamPing(String teamHikeSessionId) async {
    try {
      if (!mounted) return;
      final shouldRespond = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Your team is checking on you'),
          content: const Text(
            'Send “I’m OK” only after you have checked your situation.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('I’m OK'),
            ),
          ],
        ),
      );
      if (shouldRespond != true || !mounted) return;
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
        final updatedHike = _withTeamHikeSessionLink(currentHike, teamSession);
        setState(() {
          activeHike = updatedHike;
          selectedTabIndex = 0;
        });
        _persistActiveHikeSnapshot(updatedHike);
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
      _rebuildPlannedHike();
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
      _manualSosRequestSequence += 1;
      _pendingManualSosRequestId = _manualSosRequestSequence;
    });
    tabController.animateTo(1);
  }

  void requestImmediateSos(
    SosAlertMode mode, {
    SosAlertTriggerSource triggerSource = SosAlertTriggerSource.mobilePhone,
  }) {
    setState(() {
      selectedTabIndex = 1;
      immediateSosRequestMode = mode;
      immediateSosRequestTriggerSource = triggerSource;
      _immediateSosRequestSequence += 1;
      _pendingImmediateSosRequestId = _immediateSosRequestSequence;
    });
    tabController.animateTo(1);
  }

  void _consumeManualSosRequest(int requestId) {
    if (!mounted || requestId != _pendingManualSosRequestId) return;
    setState(() {
      _pendingManualSosRequestId = 0;
    });
  }

  void _consumeImmediateSosRequest(int requestId) {
    if (!mounted || requestId != _pendingImmediateSosRequestId) return;
    setState(() {
      _pendingImmediateSosRequestId = 0;
      immediateSosRequestMode = null;
      immediateSosRequestTriggerSource = SosAlertTriggerSource.mobilePhone;
    });
  }

  Future<void> _showBleSosHelpPopupForLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? sentAt,
    int? rssi,
  }) async {
    if (!mounted || !_isUsableBleCoordinate(latitude, longitude)) {
      return;
    }
    final safeAccuracyMeters =
        accuracyMeters != null && accuracyMeters.isFinite && accuracyMeters >= 0
        ? accuracyMeters
        : null;
    final mapUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.sos_rounded, color: Color(0xFFFF3B30)),
          title: const Text('Nearby SOS Needs Help'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A nearby HikerCircle BLE SOS test beacon was received.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: _BleSosHelpMap(
                      targetLatitude: latitude,
                      targetLongitude: longitude,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Location: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                  ),
                  if (safeAccuracyMeters != null)
                    Text('GPS accuracy: ${safeAccuracyMeters.round()} m'),
                  if (rssi != null) Text('BLE signal: $rssi dBm'),
                  if (sentAt != null)
                    Text('Sent: ${_formatBleSosHelpTime(sentAt)}'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Dismiss'),
            ),
            FilledButton.icon(
              onPressed: () {
                unawaited(_launchExternalUri(mapUri));
              },
              icon: const Icon(Icons.map_rounded),
              label: const Text('Open Map'),
            ),
          ],
        );
      },
    );
  }

  void _handlePairedSosButtonEvent(HikerBlePairedSosButtonEvent event) {
    if (event.mode != 1) {
      return;
    }
    final key = '${event.deviceId}:${event.counter ?? 'unknown'}';
    if (event.deviceId.isEmpty || _lastHandledPairedSosKey == key) {
      return;
    }
    _lastHandledPairedSosKey = key;
    requestImmediateSos(
      SosAlertMode.manual,
      triggerSource: SosAlertTriggerSource.emergencyButton,
    );
    final eventId = event.counter;
    if (eventId != null) {
      unawaited(_sendPairedSosLocation(event.deviceId, eventId));
    }
  }

  Future<void> _sendPairedSosLocation(String deviceId, int eventId) async {
    try {
      final snapshotService = LocationSnapshotService.instance;
      final preciseLocation = await const SosDeviceAlertService()
          .getCurrentTriggerLocation(
            allowLastKnown: false,
            requirePrecise: true,
          );
      final location =
          preciseLocation ??
          await snapshotService.refresh() ??
          snapshotService.latestLocation;
      if (location == null) {
        debugPrint('SOS location handoff stopped: no usable phone location.');
        return;
      }
      await _bleService.sendPairedSosLocation(
        deviceId: deviceId,
        eventId: eventId,
        location: location,
      );
    } catch (error) {
      debugPrint('Unable to return SOS location to button: $error');
    }
  }

  Future<void> _handleNearbySosButtonEvent({
    required String deviceId,
    int? counter,
    required DateTime receivedAt,
    int? rssi,
  }) async {
    final key =
        '$deviceId:${counter ?? receivedAt.millisecondsSinceEpoch ~/ 1000}';
    await _recordNearbySosEvent(
      deviceId: deviceId,
      counter: counter,
      receivedAt: receivedAt,
      rssi: rssi,
    );
    _nearbySosFallbackTimers.remove(key)?.cancel();
    _nearbySosFallbackTimers[key] = Timer(const Duration(seconds: 12), () {
      unawaited(_presentNearbySosAfterLocationWait(key, rssi));
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Nearby SOS received. Waiting briefly for the button’s exact phone location…',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _presentNearbySosAfterLocationWait(String key, int? rssi) async {
    _nearbySosFallbackTimers.remove(key)?.cancel();
    final exact = _exactNearbySosLocations[key];
    if (exact != null) {
      if (_presentedExactNearbySosKeys.add(key)) {
        _presentedNearbySosKeys.add(key);
        await _showNearbySosButtonPopup(rssi: rssi, location: exact);
      }
      return;
    }
    if (!_presentedNearbySosKeys.add(key)) return;
    _activeApproximateNearbySosKeys.add(key);
    await _showNearbySosButtonPopup(rssi: rssi);
    _activeApproximateNearbySosKeys.remove(key);
    final lateExact = _exactNearbySosLocations[key];
    if (lateExact != null && _presentedExactNearbySosKeys.add(key)) {
      await _showNearbySosButtonPopup(rssi: rssi, location: lateExact);
    }
  }

  Future<void> _handleNearbySosLocationEvent(
    HikerBleNearbySosLocationEvent event,
  ) async {
    final key =
        '${event.deviceId}:${event.counter ?? event.receivedAt.millisecondsSinceEpoch ~/ 1000}';
    final location =
        _isUsableBleCoordinate(
          event.location.latitude,
          event.location.longitude,
        )
        ? event.location
        : null;
    _nearbySosFallbackTimers.remove(key)?.cancel();
    if (location != null) _exactNearbySosLocations[key] = location;
    await _recordNearbySosEvent(
      deviceId: event.deviceId,
      counter: event.counter,
      receivedAt: event.receivedAt,
      rssi: event.rssi,
      location: location,
    );
    if (location == null) {
      await _presentNearbySosAfterLocationWait(key, event.rssi);
      return;
    }
    if (!_activeApproximateNearbySosKeys.contains(key) &&
        _presentedExactNearbySosKeys.add(key)) {
      _presentedNearbySosKeys.add(key);
      await _showNearbySosButtonPopup(rssi: event.rssi, location: location);
    }
  }

  Future<void> _handleBleSosHelpEvent(HikerBleSosHelpEvent event) async {
    final receivedAt = event.location.capturedAt ?? event.receivedAt;
    await _recordNearbySosEvent(
      deviceId: 'help_${event.phoneNumberHash.toRadixString(16)}',
      counter: receivedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      receivedAt: receivedAt,
      rssi: event.rssi,
      location: event.location,
    );
    await _showBleSosHelpPopupForLocation(
      latitude: event.location.latitude,
      longitude: event.location.longitude,
      accuracyMeters: event.location.accuracyMeters,
      sentAt: event.location.capturedAt,
      rssi: event.rssi,
    );
  }

  Future<void> _recordNearbySosEvent({
    required String deviceId,
    required DateTime receivedAt,
    int? counter,
    int? rssi,
    SosTriggerLocation? location,
  }) async {
    final event = NearbySosEvent(
      ownerPhoneNumber: widget.session.phoneNumber,
      eventKey: NearbySosEvent.eventKeyFor(
        deviceId: deviceId,
        counter: counter,
        receivedAt: receivedAt,
      ),
      deviceId: deviceId,
      counter: counter,
      rssi: rssi,
      receivedAt: receivedAt.toUtc(),
      updatedAt: DateTime.now().toUtc(),
      location: location,
      detectorLocation: LocationSnapshotService.instance.latestLocation,
    );
    try {
      await nearbySosEventRepository.save(event);
      if (mounted) {
        setState(() => _nearbySosRevision += 1);
      }
    } catch (error) {
      debugPrint('Unable to save nearby SOS event: $error');
    }
    unawaited(_forwardNearbySosEvent(event));
  }

  Future<void> _forwardNearbySosEvent(NearbySosEvent event) async {
    try {
      await hikerCircleRepository.forwardNearbySosIncident(event: event);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      // The local SQLite record is the durable retry source. Reconnect sync
      // replays it through the server's deterministic incident deduplicator.
      debugPrint('Nearby SOS forwarding deferred: ${error.message}');
    } catch (error) {
      debugPrint('Unable to forward nearby SOS observation: $error');
    }
  }

  // Retained for the legacy map widget below; nearby paired-button alerts no
  // longer display this estimate and use the relayed GPS coordinate instead.
  static double _bleRangeMeters(int rssi) {
    const referenceRssi = -59.0;
    const pathLossExponent = 2.3;
    final meters =
        30 *
        math
            .pow(10, (referenceRssi - rssi) / (10 * pathLossExponent))
            .toDouble();
    return meters.clamp(20.0, 500.0);
  }

  Future<void> _showNearbySosButtonPopup({
    int? rssi,
    SosTriggerLocation? location,
  }) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Nearby SOS needed'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (location == null) ...[
                  const Text(
                    'A nearby HikerCircle button was pressed. The blue area '
                    'below shows an approximate nearby range, not the hiker\'s '
                    'exact direction.',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 240,
                    child: _BleNearbyProximityMap(rssi: rssi),
                  ),
                ] else ...[
                  const Text(
                    'A nearby HikerCircle button was pressed. The map shows '
                    'the hiker\'s reported location.',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 280,
                    child: _BleSosHelpMap(
                      targetLatitude: location.latitude,
                      targetLongitude: location.longitude,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (location.accuracyMeters != null)
                    Text(
                      'Reported accuracy: about ${location.accuracyMeters!.round()} m',
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FirstAidGuidePage(
                    emergencyLatitude: location?.latitude,
                    emergencyLongitude: location?.longitude,
                  ),
                ),
              );
            },
            child: const Text('First aid guide'),
          ),
        ],
      ),
    );
  }

  String _formatBleSosHelpTime(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  static bool _isUsableBleCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('No compatible app is available for this action.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to open this action on the device.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _signOutAndClearActiveHike() {
    unawaited(_requestSignOut());
  }

  Future<void> _requestSignOut() async {
    if (_isEndingActiveHike) return;
    if (activeHike != null) {
      final shouldEnd = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('End active hike before signing out?'),
          content: const Text(
            'Signing out without closing tracking could orphan this solo or '
            'team session. HikerCircle will save and queue the completion first.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep hiking'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('End & Sign Out'),
            ),
          ],
        ),
      );
      if (shouldEnd == true) {
        await _endActiveHikeSession(signOutAfter: true);
      }
      return;
    }
    await _performSignOut();
  }

  Future<void> _performSignOut() async {
    try {
      await LiveLocationSharingService.instance.deactivate();
    } catch (_) {}
    try {
      await _bleService.setActiveSosAccount(null);
    } catch (_) {}
    try {
      await hikerCircleRepository.removeFcmToken(session: widget.session);
    } catch (_) {}
    if (mounted) widget.onSignOut();
  }

  int _lastMapStyleIndex = 0;

  Future<void> _promptForTrailRating(ActiveHikeSession completedHike) async {
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TrailRatingDialog(
        trailName: completedHike.trail.name,
        onSubmit: (feedback) => hikerCircleRepository.submitCompletedHikeRating(
          session: widget.session,
          sessionId: completedHike.sessionId,
          trailId: completedHike.trail.trailId,
          rating: feedback.rating,
          comment: feedback.comment,
        ),
      ),
    );
    if (!mounted || submitted != true) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Thanks — your trail rating is now included.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _endActiveHikeSession({bool signOutAfter = false}) async {
    final hikeToEnd = activeHike;
    if (hikeToEnd == null || _isEndingActiveHike) {
      return;
    }
    _isEndingActiveHike = true;

    final endedAt = DateTime.now();
    final report = HikeSummaryReport.fromActiveHike(
      activeHike: hikeToEnd,
      endedAt: endedAt,
    );

    ActiveHikeEndResult endResult;
    try {
      endResult = await hikerCircleRepository.endHikeSession(
        session: widget.session,
        activeHike: hikeToEnd,
        summary: report,
      );
    } catch (error) {
      _isEndingActiveHike = false;
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'The hike could not be saved safely, so tracking remains active. $error',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
      }
      return;
    }
    final completedHike = endResult.sessionId == hikeToEnd.sessionId
        ? hikeToEnd
        : hikeToEnd.copyWith(sessionId: endResult.sessionId);
    final completedReport = endResult.sessionId == report.sessionId
        ? report
        : HikeSummaryReport.fromActiveHike(
            activeHike: completedHike,
            endedAt: report.endedAt,
          );

    await fallStillnessMonitor.stop();
    try {
      await _sosDeviceAlertService.stopFallStillnessCountdownVibration();
      await _sosDeviceAlertService.stopSpokenPrompt();
      await _sosDeviceAlertService.stopManualSosPattern();
    } catch (_) {
      // Native safety outputs are best effort when ending a hike.
    }
    _syncActiveHikeServices(null);
    await _activeHikePersistenceQueue;
    isFallStillnessLocalAlarmActive = false;
    if (!mounted) {
      return;
    }

    setState(() {
      activeHike = null;
    });
    _isEndingActiveHike = false;

    if (endResult.status == 'abandoned') {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Cloud safety monitoring had already marked this hike abandoned. Local tracking was stopped, but no completed hike was published.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } else if (!endResult.cloudSynced) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Hike ended safely offline. Cloud completion is queued for the next connection.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    if (signOutAfter) {
      await _performSignOut();
      return;
    }
    if (endResult.status == 'abandoned') return;

    if (endResult.completed) {
      await _promptForTrailRating(completedHike);
      if (!mounted) return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return _HikeSummaryReportPage(
            session: widget.session,
            report: completedReport,
            activeHike: completedHike,
            initialMapStyleIndex: _lastMapStyleIndex,
            onShareReportText: (text) => _sosDeviceAlertService.shareText(
              subject: 'Hike summary: ${completedReport.trailName}',
              text: text,
            ),
            onShareToCommunity: endResult.completed
                ? (caption, images) async {
                    await hikerCircleRepository.createCompletedHikePost(
                      session: widget.session,
                      activeHike: completedHike,
                      summary: completedReport,
                      caption: caption,
                      images: images,
                    );
                  }
                : null,
          );
        },
      ),
    );
  }

  Map<String, Object?> get _adminRuntimeDebugData {
    final hike = activeHike;
    final plan = plannedHike;
    final fallSnapshot = fallStillnessMonitor.snapshot;
    return {
      'Home shell temporary state': {
        'storageType': 'Mounted HikerHomePage widget state',
        'persistence': 'Cleared when the signed-in home shell is disposed',
        'selectedTabIndex': selectedTabIndex,
        'selectedTabLabel':
            selectedTabIndex >= 0 && selectedTabIndex < tabs.length
            ? tabs[selectedTabIndex].label
            : null,
        'isLoadingLiveData': isLoadingLiveData,
        'isSendingFallStillnessSos': isSendingFallStillnessSos,
        'isRecordingActiveHikeLocation': isRecordingActiveHikeLocation,
        'isFallStillnessDialogVisible': isFallStillnessDialogVisible,
        'isFallStillnessLocalAlarmActive': isFallStillnessLocalAlarmActive,
        'fallStillnessCountdownWasBackgrounded':
            fallStillnessCountdownWasBackgrounded,
        'manualSosRequestSequence': _manualSosRequestSequence,
        'pendingManualSosRequestId': _pendingManualSosRequestId,
        'immediateSosRequestSequence': _immediateSosRequestSequence,
        'pendingImmediateSosRequestId': _pendingImmediateSosRequestId,
        'immediateSosRequestMode': immediateSosRequestMode?.name,
        'immediateSosRequestTriggerSource':
            immediateSosRequestTriggerSource.name,
        'loadedTrails': trails.map((trail) => trail.toFirestore()).toList(),
        'emergencyContacts': emergencyContacts
            .map((contact) => contact.toFirestore())
            .toList(),
      },
      'Home timers, subscriptions, and tracking flags': {
        'storageType': 'Runtime handles and temporary tracking state',
        'persistence': 'Process/widget lifetime only',
        'upcomingHikesSubscriptionActive': _myUpcomingHikesSubscription != null,
        'trailsSubscriptionActive': _trailsSubscription != null,
        'activeHikeRecordingTimerActive':
            activeHikeRecordingTimer?.isActive == true,
        'batteryLevelTimerActive': batteryLevelTimer?.isActive == true,
        'teamHikeSessionSubscriptionActive':
            teamHikeSessionSubscription != null,
        'teamHikeWatchSessionId': teamHikeWatchSessionId,
        'activeHikeRecordingSessionId': activeHikeRecordingSessionId,
        'activeHikeRecordingIntervalSeconds':
            activeHikeRecordingInterval?.inSeconds,
        'lastActiveHikeLocationRecordedAt': lastActiveHikeLocationRecordedAt
            ?.toUtc()
            .toIso8601String(),
        'lastActiveHikeLiveStatusSentAt': lastActiveHikeLiveStatusSentAt
            ?.toUtc()
            .toIso8601String(),
        'stationaryWatchReferenceLocation': stationaryWatchReferenceLocation
            ?.toFirestore(),
        'stationaryWatchStartedAt': stationaryWatchStartedAt
            ?.toUtc()
            .toIso8601String(),
        'isStationaryLocationWatchActive': isStationaryLocationWatchActive,
        'lastFallStillnessStatus': lastFallStillnessStatus.name,
        'fallStillnessCancelTaps': fallStillnessCancelTaps
            .map((date) => date.toUtc().toIso8601String())
            .toList(),
      },
      'Active hike session': {
        'storageType': 'Runtime state backed by durable local SQLite',
        'persistence':
            'The full snapshot is saved in active_hike_session and restored after app termination; telemetry is also mirrored separately to SQLite/Firestore',
        'value': hike == null
            ? null
            : {
                'sessionId': hike.sessionId,
                'startedAt': hike.startedAt.toUtc().toIso8601String(),
                'batteryLevel': hike.batteryLevel,
                'batteryStartedLevel': hike.batteryStartedLevel,
                'queuedUpdates': hike.queuedUpdates,
                'manualPins': hike.manualPins,
                'checkIns': hike.checkIns,
                'recordedDistanceKm': hike.recordedDistanceKm,
                'latestLocation': hike.latestLocation?.toFirestore(),
                'routePoints': hike.routePoints
                    .map((point) => point.toFirestore())
                    .toList(),
                'manualPinLocations': hike.manualPinLocations
                    .map((pin) => pin.toFirestore())
                    .toList(),
                'checkInRecords': hike.checkInRecords
                    .map((record) => record.toPersistence())
                    .toList(),
                'teamHikeSessionId': hike.teamHikeSessionId,
                'teamHikeSession': hike.teamHikeSession?.toFirestore(),
                'draft': {
                  'hikeType': hike.draft.hikeType.name,
                  'trail': hike.draft.trail.toFirestore(),
                  'startPointName': hike.draft.startPointName,
                  'destinationName': hike.draft.destinationName,
                  'departureTime': hike.draft.departureTime
                      .toUtc()
                      .toIso8601String(),
                  'expectedArrivalTime': hike.draft.expectedArrivalTime
                      .toUtc()
                      .toIso8601String(),
                  'expectedReturnTime': hike.draft.expectedReturnTime
                      .toUtc()
                      .toIso8601String(),
                  'safetyCheckInIntervalSeconds':
                      hike.draft.safetyCheckInInterval.inSeconds,
                  'locationRecordingIntervalSeconds':
                      hike.draft.locationRecordingInterval.inSeconds,
                  'emergencyContactNames': hike.draft.emergencyContactNames,
                  'shareLiveLocation': hike.draft.shareLiveLocation,
                  'fallDetectionEnabled': hike.draft.fallDetectionEnabled,
                  'fallDetectionSettings': {
                    'sensorSensitivity':
                        hike.draft.fallDetectionSettings.sensorSensitivity,
                    'fallResponseDurationSeconds': hike
                        .draft
                        .fallDetectionSettings
                        .fallResponseDuration
                        .inSeconds,
                    'longestRestDurationSeconds': hike
                        .draft
                        .fallDetectionSettings
                        .longestRestDuration
                        .inSeconds,
                    'stillnessDurationSeconds': hike
                        .draft
                        .fallDetectionSettings
                        .fallResponseDuration
                        .inSeconds,
                  },
                  'pathDeviationEnabled': hike.draft.pathDeviationEnabled,
                  'offlinePhysicalAlertEnabled':
                      hike.draft.offlinePhysicalAlertEnabled,
                  'duressEnabled': hike.draft.duressEnabled,
                  'completedChecklistItems': hike.draft.completedChecklistItems
                      .toList(),
                  'teamBuddies': hike.draft.teamBuddies
                      .map((buddy) => buddy.toFirestore())
                      .toList(),
                  'customCheckpoints': hike.draft.customCheckpoints
                      ?.map((checkpoint) => checkpoint.toFirestore())
                      .toList(),
                },
              },
      },
      'Planned and upcoming hike memory': {
        'storageType': 'Temporary loaded/planned hike state',
        'persistence':
            'Widget lifetime; upcoming records also exist in Firestore',
        'plannedHike': plan == null
            ? null
            : {
                'trail': plan.trail.toFirestore(),
                'plannedStartTime': plan.plannedStartTime
                    .toUtc()
                    .toIso8601String(),
                'expectedReturnTime': plan.expectedReturnTime
                    .toUtc()
                    .toIso8601String(),
                'weatherCached': plan.weatherCached,
                'offlineMapDownloaded': plan.offlineMapDownloaded,
                'emergencyContactsSelected': plan.emergencyContactsSelected,
                'checklistCompleted': plan.checklistCompleted,
                'checklistTotal': plan.checklistTotal,
                'phoneBatteryLevel': plan.phoneBatteryLevel,
                'liveLocationConfigured': plan.liveLocationConfigured,
              },
        'myUpcomingHikes': myUpcomingHikes
            .map((upcoming) => {'id': upcoming.id, ...upcoming.toFirestore()})
            .toList(),
      },
      'Fall/stillness monitor snapshot': {
        'storageType': 'Temporary sensor-monitor state',
        'persistence': 'Only while the monitor/app process is alive',
        'status': fallSnapshot.status.name,
        'message': fallSnapshot.message,
        'detectedAt': fallSnapshot.detectedAt?.toUtc().toIso8601String(),
        'countdownEndsAt': fallSnapshot.countdownEndsAt
            ?.toUtc()
            .toIso8601String(),
        'triggeredAt': fallSnapshot.triggeredAt?.toUtc().toIso8601String(),
        'lastCancelledAt': fallSnapshot.lastCancelledAt
            ?.toUtc()
            .toIso8601String(),
        'secondsRemaining': fallSnapshot.secondsRemaining,
        'accelerationMagnitude': fallSnapshot.accelerationMagnitude,
        'altitudeDropMeters': fallSnapshot.altitudeDropMeters,
        'isBackpackTrapLikely': fallSnapshot.isBackpackTrapLikely,
        'isProlongedStillnessDetection':
            fallSnapshot.isProlongedStillnessDetection,
        'settings': fallSnapshot.settings == null
            ? null
            : {
                'sensorSensitivity': fallSnapshot.settings!.sensorSensitivity,
                'fallResponseDurationSeconds':
                    fallSnapshot.settings!.fallResponseDuration.inSeconds,
                'longestRestDurationSeconds':
                    fallSnapshot.settings!.longestRestDuration.inSeconds,
              },
      },
    };
  }

  Widget pageFor(HikerBottomNavDestination tab) {
    final isActive = activeHike != null;
    switch (tab.label) {
      case 'Home':
        if (isActive) {
          return ActiveHikeHomePage(
            activeHike: activeHike!,
            currentPhoneNumber: widget.session.phoneNumber,
            onEndHike: () => unawaited(_endActiveHikeSession()),
            onOpenTeamChat: activeHike!.teamHikeSessionId.isEmpty
                ? null
                : () => unawaited(
                    _openGroupChatFromDeepLink(
                      'team_${activeHike!.teamHikeSessionId}',
                    ),
                  ),
            onReportHazard: () {
              final hike = activeHike;
              if (hike == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => HazardReportPage(
                    session: widget.session,
                    hikerCircleRepository: hikerCircleRepository,
                    trail: hike.draft.trail,
                  ),
                ),
              );
            },
            onPingTeamMember: _pingTeamMember,
            onMapStyleChanged: (index) =>
                setState(() => _lastMapStyleIndex = index),
            onCheckIn: () {
              final hike = activeHike;
              if (hike != null) {
                unawaited(_applyActiveHikeCheckIn(hike));
              }
            },
            onPinLocation: () {
              final hike = activeHike;
              if (hike != null) {
                unawaited(_applyActiveHikePin(hike));
              }
            },
            fallStillnessSnapshot: fallStillnessMonitor.snapshot,
            onCancelFallStillnessSos: () =>
                _cancelFallStillnessSos('Phone tap response received'),
          );
        }
        final now = DateTime.now();
        final activePlannedHike =
            (plannedHike != null &&
                !now.isAfter(
                  plannedHike!.plannedStartTime.add(
                    const Duration(minutes: 10),
                  ),
                ))
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
          onStartHike: _startHikeFromDashboard,
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
          onPlannedHikeChanged: _updatePlannedHike,
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
          manualSosRequestId: _pendingManualSosRequestId,
          onManualSosRequestConsumed: _consumeManualSosRequest,
          immediateSosRequestId: _pendingImmediateSosRequestId,
          immediateSosMode: immediateSosRequestMode,
          immediateSosTriggerSource: immediateSosRequestTriggerSource,
          onImmediateSosRequestConsumed: _consumeImmediateSosRequest,
          nearbySosEventRepository: nearbySosEventRepository,
          nearbySosRevision: _nearbySosRevision,
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
          onSignOut: _signOutAndClearActiveHike,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
      case 'Admin':
        return AdminPage(
          session: widget.session,
          hikerCircleRepository: hikerCircleRepository,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
          runtimeDebugData: _adminRuntimeDebugData,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    final hike = activeHike;
    if (state == AppLifecycleState.detached) {
      if (hike != null) {
        unawaited(_signalPotentialAppTermination(hike));
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (hike != null) {
        unawaited(
          _sendActiveHikeMonitoringHeartbeat(
            hike,
            lifecycleState: 'background',
          ),
        );
      }
      fallStillnessCountdownWasBackgrounded =
          fallStillnessMonitor.isAwaitingResponse;
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_drainPendingFcmOpens());
      unawaited(_drainPendingBleUiEvents());
      unawaited(_resumeBleSosMonitor());
      unawaited(_consumePendingNativeSafetyEvent());
      if (hike != null) {
        unawaited(
          _sendActiveHikeMonitoringHeartbeat(hike, lifecycleState: 'active'),
        );
        _startActiveHikeLocationRecording(hike);
        if (_isActiveHikeLocationRecordDue(hike)) {
          unawaited(_recordActiveHikeLocationTick(force: true));
        }
      }

      if (fallStillnessCountdownWasBackgrounded &&
          fallStillnessMonitor.isAwaitingResponse) {
        fallStillnessCountdownWasBackgrounded = false;
        // Opening the app is not evidence that the hiker is safe. Keep the
        // countdown active until they explicitly cancel it.
      }
    }
  }

  Future<void> _resumeBleSosMonitor() async {
    try {
      await _bleService.setActiveSosAccount(widget.session.phoneNumber);
      await _bleService.startSosButtonMonitor();
    } catch (error) {
      debugPrint('Unable to resume the BLE SOS monitor: $error');
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
    final snapshot = fallStillnessMonitor.snapshot;
    final alertName = snapshot.isProlongedStillnessDetection
        ? 'Prolonged-stillness SOS'
        : 'Fall SOS';
    unawaited(HapticFeedback.heavyImpact());
    try {
      await _sosDeviceAlertService.startFallStillnessCountdownVibration();
    } catch (_) {
      _showFallStillnessSnackBar(
        '$alertName countdown started, but vibration could not start.',
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

  Future<void> _consumePendingNativeSafetyEvent() async {
    await _waitForActiveHikeRestore();
    if (!mounted) return;
    final event = await _activeHikeLiveStatusService
        .consumePendingSafetyEvent();
    if (!mounted || event == null || event.eventId.isEmpty) return;
    final hike = activeHike;
    if (hike == null) return;
    if (event.sessionId.isNotEmpty && event.sessionId != hike.sessionId) {
      await _activeHikeLiveStatusService.acknowledgeSafetyEvent(event.eventId);
      return;
    }

    if (event.isDispatched) {
      if (_lastHandledNativeSafetyEventId == event.eventId) return;
      _lastHandledNativeSafetyEventId = event.eventId;
      _showFallStillnessSnackBar(
        '${event.dispatchMessage ?? 'The background safety alert was sent or queued for retry.'} '
        'The physical alarm remains active until you confirm you are safe.',
        includeStopAlarmAction: true,
      );
      return;
    }
    if (event.isDispatching || event.isTriggering) {
      Future<void>.delayed(
        const Duration(seconds: 2),
        _consumePendingNativeSafetyEvent,
      );
      return;
    }

    if (event.isDispatchFailed || event.isReadyForFlutterDispatch) {
      if (_lastHandledNativeSafetyEventId == event.eventId) return;
      _lastHandledNativeSafetyEventId = event.eventId;
      await _emergencyContactsLoadFuture;
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      final snapshot = FallStillnessMonitorSnapshot.triggering(
        settings: hike.draft.fallDetectionSettings,
        detectedAt: event.detectedAt ?? event.triggeredAt ?? now,
        triggeredAt: event.triggeredAt ?? now,
        accelerationMagnitude: null,
        altitudeDropMeters: null,
        isBackpackTrapLikely: false,
        isProlongedStillnessDetection: event.isProlongedStillness,
        message: event.isProlongedStillness
            ? 'Native safety countdown ended. Sending prolonged-stillness SOS.'
            : 'Native safety countdown ended. Sending Fall SOS.',
      );
      await _handleFallStillnessEmergencyReady(snapshot);
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          event.isReadyForFlutterDispatch) {
        await _activeHikeLiveStatusService.markSafetyEventDispatched(
          event.eventId,
          message:
              'Emergency alert processed. The alarm remains active until an I\'m Safe response.',
        );
      } else {
        await _activeHikeLiveStatusService.acknowledgeSafetyEvent(
          event.eventId,
        );
      }
      return;
    }

    if (isNativeSafetyDialogVisible) return;
    final deadline = event.deadlineAt;
    if (deadline == null || !deadline.isAfter(DateTime.now().toUtc())) {
      Future<void>.delayed(
        const Duration(seconds: 1),
        _consumePendingNativeSafetyEvent,
      );
      return;
    }
    // Android owns the response UI so it can appear above the lock screen and
    // other apps. Flutter only observes the persisted outcome and never stacks
    // a second countdown dialog underneath the native safety surface.
    Future<void>.delayed(
      const Duration(seconds: 2),
      _consumePendingNativeSafetyEvent,
    );
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
    final isProlongedStillness = snapshot.isProlongedStillnessDetection;
    final alertName = isProlongedStillness
        ? 'Prolonged-stillness SOS'
        : 'Fall SOS';
    var didStartLocalAlarm = isFallStillnessLocalAlarmActive;
    if (!didStartLocalAlarm) {
      try {
        await _sosDeviceAlertService.startManualSosPattern();
        didStartLocalAlarm = true;
        isFallStillnessLocalAlarmActive = true;
      } catch (_) {
        _showFallStillnessSnackBar(
          '$alertName detected, but the phone alarm or flashlight could not start.',
          isError: true,
        );
      }
    }

    try {
      final triggerLocation = await _captureTriggerLocation();
      final result = await sosAlertRepository.triggerAlert(
        session: widget.session,
        mode: isProlongedStillness
            ? SosAlertMode.prolongedStillness
            : SosAlertMode.fallStillness,
        triggeredAt: snapshot.triggeredAt ?? DateTime.now().toUtc(),
        triggerLocation: triggerLocation,
        contacts: emergencyContacts,
        triggerSource: SosAlertTriggerSource.automaticDetection,
      );
      _showFallStillnessSnackBar(
        _messageForSosResult(result),
        includeStopAlarmAction: didStartLocalAlarm,
      );
    } on SosAlertRepositoryException catch (error) {
      _showFallStillnessSnackBar(
        didStartLocalAlarm
            ? '$alertName local alarm started, but network alert failed: ${error.message}'
            : '$alertName could not be sent: ${error.message}',
        isError: true,
        includeStopAlarmAction: didStartLocalAlarm,
      );
    } catch (_) {
      _showFallStillnessSnackBar(
        didStartLocalAlarm
            ? '$alertName local alarm started, but contact notification failed.'
            : '$alertName could not be sent.',
        isError: true,
        includeStopAlarmAction: didStartLocalAlarm,
      );
    } finally {
      isSendingFallStillnessSos = false;
    }
  }

  Future<SosTriggerLocation?> _captureTriggerLocation() async {
    final snapshotService = LocationSnapshotService.instance;
    final cached = snapshotService.latestLocation;
    if (cached != null) {
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

  String _messageForSosResult(SosAlertResult result) {
    final alert = result.alert;
    final alertName = alert.mode.label;
    if (alert.status == SosAlertStatus.noContacts) {
      return '$alertName logged, but no emergency contacts are saved.';
    }
    if (alert.status == SosAlertStatus.sent) {
      return '$alertName sent to ${alert.sentCount} contacts.';
    }
    if (alert.status == SosAlertStatus.partial) {
      return '$alertName sent to ${alert.sentCount} contacts; ${alert.failedCount} failed.';
    }
    return '$alertName could not be sent to your contacts.';
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
                    _cancelFallStillnessSos('I\'m safe response received');
                  },
                )
              : null,
        ),
      );
  }

  void _syncFallStillnessMonitor(ActiveHikeSession? hike) {
    // Android's foreground service and iOS's Core Motion/location monitor own
    // the complete native sensor and alert lifecycle. Running the Dart monitor
    // too would create two independent state machines and double-trigger.
    final nativeServiceOwnsDetection =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final shouldStart =
        !nativeServiceOwnsDetection &&
        hike != null &&
        hike.draft.fallDetectionEnabled;
    final settings = hike?.draft.fallDetectionSettings;
    _fallStillnessSyncQueue = _fallStillnessSyncQueue.then((_) async {
      if (!mounted) return;
      final currentHike = activeHike;
      final stillCurrent = shouldStart
          ? currentHike != null &&
                currentHike.draft.fallDetectionEnabled &&
                currentHike.draft.fallDetectionSettings == settings
          : nativeServiceOwnsDetection ||
                currentHike == null ||
                !currentHike.draft.fallDetectionEnabled;
      if (!stillCurrent) return;
      if (!shouldStart || settings == null) {
        await fallStillnessMonitor.stop();
        await _sosDeviceAlertService.stopFallStillnessCountdownVibration();
      } else {
        await fallStillnessMonitor.start(settings);
      }
    });
  }

  Future<bool> _ensureBackgroundSafetyReady(HikeSessionDraft draft) async {
    if (!draft.fallDetectionEnabled) return true;
    var status = await _activeHikeLiveStatusService.nativeSafetyStatus();
    if (!mounted || !status.supported) return true;

    if (status.platform == 'ios') {
      if (!status.backgroundLocationGranted ||
          status.notificationAuthorizationStatus == 'not_determined' ||
          status.motionAuthorizationStatus == 'not_determined') {
        await _activeHikeLiveStatusService.requestIosSafetyPermissions();
        status = await _activeHikeLiveStatusService.nativeSafetyStatus();
        if (!mounted) return false;
      }

      final locationReady =
          status.fineLocationGranted && status.backgroundLocationGranted;
      final iosReady =
          locationReady &&
          status.notificationsAuthorized &&
          status.motionGranted;
      if (iosReady) return true;

      final missing = <String>[
        if (!locationReady) 'Location: Always',
        if (!status.notificationsAuthorized) 'Notifications: Allow',
        if (!status.motionGranted) 'Motion & Fitness: On',
      ];
      final openSettings =
          await showCupertinoDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => CupertinoAlertDialog(
              title: const Text('Finish iPhone safety setup'),
              content: Text(
                'Hike monitoring cannot start until these settings are enabled:\n\n'
                '${missing.map((item) => '• $item').join('\n')}\n\n'
                'Only the settings listed above are required. Time Sensitive '
                'Notifications and Live Activities are optional enhancements '
                'and will not remove you from a team hike.',
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel hike start'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ) ??
          false;
      if (!openSettings || !mounted) return false;
      await _activeHikeLiveStatusService.openIosSafetySettings();
      return false;
    }

    final locationReady =
        status.fineLocationGranted && status.backgroundLocationGranted;
    if (locationReady &&
        status.fullScreenIntentGranted &&
        status.overlayGranted) {
      return true;
    }
    if (locationReady && !status.overlayGranted) {
      final openSettings =
          await showCupertinoDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => CupertinoAlertDialog(
              title: const Text('Allow safety popup overlay'),
              content: const Text(
                'Allow HikerCircle to display over other apps. This lets the '
                'I\'M SAFE — STOP ALARM screen cover the current app as soon as '
                'a fall or prolonged-stillness warning begins.',
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel hike start'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Open overlay settings'),
                ),
              ],
            ),
          ) ??
          false;
      if (!openSettings || !mounted) return false;
      await _activeHikeLiveStatusService.openOverlaySettings();
      return false;
    }
    if (locationReady && !status.fullScreenIntentGranted) {
      final openSettings =
          await showCupertinoDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => CupertinoAlertDialog(
              title: const Text('Allow full-screen safety alerts'),
              content: const Text(
                'Allow HikerCircle to show full-screen alerts so a fall or '
                'stillness warning can appear above the lock screen and other '
                'apps. The alarm notification always keeps an I\'M SAFE stop '
                'button as a fallback.',
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel hike start'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Open alert settings'),
                ),
              ],
            ),
          ) ??
          false;
      if (!openSettings || !mounted) return false;
      await _activeHikeLiveStatusService.openFullScreenIntentSettings();
      return false;
    }
    final openSettings =
        await showCupertinoDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Allow reliable hike monitoring'),
            content: const Text(
              'For fall and stillness alerts to continue with the screen off, '
              'after app recovery, and after a device restart, set Location '
              'to “Allow all the time” and keep notifications enabled.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel hike start'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Open app settings'),
              ),
            ],
          ),
        ) ??
        false;
    if (!openSettings || !mounted) return false;
    await _activeHikeLiveStatusService.openBackgroundLocationSettings();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Choose Location → Allow all the time, then start the hike again.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 8),
          ),
        );
    }
    return false;
  }

  void _syncActiveHikeServices(
    ActiveHikeSession? hike, {
    bool forceLiveStatus = false,
  }) {
    _persistActiveHikeSnapshot(hike);
    _syncFallStillnessMonitor(hike);
    _syncTeamHikeSessionWatch(hike);
    unawaited(_syncLiveLocationForActiveHike(hike));
    if (hike == null) {
      _stopActiveHikeMonitoringHeartbeat();
      _stopActiveHikeLocationRecording();
      _syncBleTeamLocation(null);
      unawaited(_activeHikeLiveStatusService.stop());
      return;
    }

    _startActiveHikeMonitoringHeartbeat(hike);
    _startActiveHikeLocationRecording(hike);
    _syncBleTeamLocation(hike);
    _syncActiveHikeLiveStatus(hike, force: forceLiveStatus);
  }

  Future<void> _syncLiveLocationForActiveHike(ActiveHikeSession? hike) async {
    final service = LiveLocationSharingService.instance;
    if (hike == null || !hike.draft.shareLiveLocation) {
      if (_liveLocationActivatedForActiveHike) {
        await service.deactivate();
        _liveLocationActivatedForActiveHike = false;
      }
      return;
    }

    await service.loadExisting(
      phoneNumber: widget.session.phoneNumber,
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    if (!service.isActive) {
      await service.activate(
        phoneNumber: widget.session.phoneNumber,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      );
    }
    if (activeHike?.sessionId == hike.sessionId && service.isActive) {
      _liveLocationActivatedForActiveHike = true;
      unawaited(service.publishLatest());
    }
  }

  void _startActiveHikeMonitoringHeartbeat(ActiveHikeSession hike) {
    final isSameSession =
        activeHikeMonitoringSessionId == hike.sessionId &&
        activeHikeMonitoringHeartbeatTimer?.isActive == true;
    if (isSameSession) {
      return;
    }
    activeHikeMonitoringHeartbeatTimer?.cancel();
    activeHikeMonitoringSessionId = hike.sessionId;
    unawaited(
      _sendActiveHikeMonitoringHeartbeat(hike, lifecycleState: 'active'),
    );
    activeHikeMonitoringHeartbeatTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        final currentHike = activeHike;
        if (currentHike != null && currentHike.sessionId == hike.sessionId) {
          unawaited(
            _sendActiveHikeMonitoringHeartbeat(
              currentHike,
              lifecycleState: _appLifecycleState == AppLifecycleState.resumed
                  ? 'active'
                  : 'background',
            ),
          );
        }
      },
    );
  }

  void _stopActiveHikeMonitoringHeartbeat() {
    activeHikeMonitoringHeartbeatTimer?.cancel();
    activeHikeMonitoringHeartbeatTimer = null;
    activeHikeMonitoringSessionId = null;
  }

  Future<void> _sendActiveHikeMonitoringHeartbeat(
    ActiveHikeSession hike, {
    required String lifecycleState,
  }) async {
    try {
      await hikerCircleRepository.updateActiveHikeMonitoringHeartbeat(
        session: widget.session,
        activeHike: hike,
        lifecycleState: lifecycleState,
        fcmToken: _fcmToken,
      );
    } catch (error) {
      debugPrint('Unable to update active hike monitoring heartbeat: $error');
    }
  }

  Future<void> _signalPotentialAppTermination(ActiveHikeSession hike) async {
    try {
      await hikerCircleRepository.signalActiveHikePotentialTermination(
        session: widget.session,
        activeHike: hike,
        fcmToken: _fcmToken,
      );
    } catch (error) {
      debugPrint('Unable to send active hike termination signal: $error');
    }
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
        .listen(
          (teamSession) {
            if (!mounted || teamSession == null) {
              return;
            }
            final currentHike = activeHike;
            if (currentHike == null ||
                currentHike.teamHikeSessionId != teamSession.id) {
              return;
            }
            final updatedHike = _withTeamHikeSessionLink(
              currentHike,
              teamSession,
            );
            setState(() {
              activeHike = updatedHike;
            });
            _persistActiveHikeSnapshot(updatedHike);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Team hike updates are unavailable: $error');
          },
        );
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
    stationaryWatchReferenceAccuracyMeters = null;
    stationaryWatchStartedAt = null;
    isStationaryLocationWatchActive = false;
    LocationSnapshotService.instance.setRefreshInterval(
      _snapshotIntervalForActiveHike(interval),
    );
    activeHikeRecordingTimer = Timer.periodic(monitorInterval, (_) {
      unawaited(_recordActiveHikeLocationTick());
    });
  }

  void _stopActiveHikeLocationRecording() {
    activeHikeRecordingTimer?.cancel();
    activeHikeRecordingTimer = null;
    activeHikeRecordingSessionId = null;
    activeHikeRecordingInterval = null;
    lastActiveHikeLocationRecordedAt = null;
    lastActiveHikeLiveStatusSentAt = null;
    stationaryWatchReferenceLocation = null;
    stationaryWatchReferenceAccuracyMeters = null;
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

  bool _isAcceptableTrackingLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location,
  ) {
    if (!location.latitude.isFinite ||
        !location.longitude.isFinite ||
        location.latitude < -90 ||
        location.latitude > 90 ||
        location.longitude < -180 ||
        location.longitude > 180) {
      return false;
    }
    final accuracy = location.accuracyMeters;
    if (accuracy != null &&
        (!accuracy.isFinite || accuracy < 0 || accuracy > 150)) {
      return false;
    }
    final capturedAt = location.capturedAt?.toUtc();
    if (capturedAt == null) return false;
    final now = DateTime.now().toUtc();
    if (capturedAt.isAfter(now.add(const Duration(minutes: 2))) ||
        now.difference(capturedAt) > const Duration(minutes: 2)) {
      return false;
    }

    final previous = hike.latestLocation;
    if (previous == null) return true;
    final elapsedSeconds =
        capturedAt.difference(previous.capturedAt.toUtc()).inMilliseconds /
        1000;
    if (elapsedSeconds < -5) return false;
    if (elapsedSeconds <= 0) return true;
    final next = HikeCoordinate.fromTriggerLocation(location);
    final distance = previous.distanceTo(next);
    final uncertainty =
        (previous.accuracyMeters ?? 0) + (location.accuracyMeters ?? 0);
    final plausibleDistance = math.max(
      250.0,
      elapsedSeconds * 12 + uncertainty,
    );
    return distance.isFinite && distance <= plausibleDistance;
  }

  void _evaluatePathDeviation(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double? accuracyMeters,
  ) {
    if (!hike.draft.pathDeviationEnabled) {
      _pathDeviationStartedAt = null;
      return;
    }
    final route = <HikeCoordinate>[];
    final encoded = hike.trail.routeEncodedPolyline?.trim() ?? '';
    if (encoded.isNotEmpty) {
      try {
        route.addAll(
          PolylineCodec.decode(encoded).map(
            (point) => HikeCoordinate(
              latitude: point.latitude,
              longitude: point.longitude,
              capturedAt: coordinate.capturedAt,
            ),
          ),
        );
      } catch (_) {
        route.clear();
      }
    }
    if (route.length < 2) {
      route
        ..clear()
        ..addAll(
          hike.draft.effectiveCheckpoints
              .where((checkpoint) => checkpoint.hasValidCoordinate)
              .map(
                (checkpoint) => HikeCoordinate(
                  latitude: checkpoint.latitude,
                  longitude: checkpoint.longitude,
                  capturedAt: coordinate.capturedAt,
                ),
              ),
        );
    }
    if (route.length < 2) return;

    var nearestMeters = double.infinity;
    for (var index = 1; index < route.length; index++) {
      nearestMeters = math.min(
        nearestMeters,
        _distanceToRouteSegment(coordinate, route[index - 1], route[index]),
      );
    }
    final thresholdMeters = math.max(75.0, (accuracyMeters ?? 0) * 2);
    final now = DateTime.now().toUtc();
    if (!nearestMeters.isFinite || nearestMeters <= thresholdMeters) {
      _pathDeviationStartedAt = null;
      return;
    }
    _pathDeviationStartedAt ??= now;
    if (now.difference(_pathDeviationStartedAt!) < const Duration(minutes: 2)) {
      return;
    }
    final lastAlert = _lastPathDeviationAlertAt;
    if (lastAlert != null &&
        now.difference(lastAlert) < const Duration(minutes: 15)) {
      return;
    }
    _lastPathDeviationAlertAt = now;
    unawaited(
      _emitPathDeviationAlert(
        hike,
        coordinate,
        nearestMeters,
      ).catchError((_) {}),
    );
  }

  double _distanceToRouteSegment(
    HikeCoordinate point,
    HikeCoordinate start,
    HikeCoordinate end,
  ) {
    const metersPerDegreeLatitude = 111320.0;
    final referenceLatitude =
        (point.latitude + start.latitude + end.latitude) / 3;
    final metersPerDegreeLongitude =
        metersPerDegreeLatitude * math.cos(referenceLatitude * math.pi / 180);
    final startX =
        (start.longitude - point.longitude) * metersPerDegreeLongitude;
    final startY = (start.latitude - point.latitude) * metersPerDegreeLatitude;
    final endX = (end.longitude - point.longitude) * metersPerDegreeLongitude;
    final endY = (end.latitude - point.latitude) * metersPerDegreeLatitude;
    final dx = endX - startX;
    final dy = endY - startY;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0) return math.sqrt(startX * startX + startY * startY);
    final projection = (-(startX * dx + startY * dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    final closestX = startX + projection * dx;
    final closestY = startY + projection * dy;
    return math.sqrt(closestX * closestX + closestY * closestY);
  }

  Future<void> _emitPathDeviationAlert(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double distanceMeters,
  ) async {
    const title = 'You may be off the planned trail';
    final body =
        'Your location has remained about ${distanceMeters.round()} m from the route. Check the map and retrace safely.';
    if (mounted && _appLifecycleState == AppLifecycleState.resumed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('$title. Open the hike map and verify your route.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 8),
          ),
        );
    }
    try {
      await _localNotifications.show(
        id: hike.sessionId.hashCode & 0x7fffffff,
        title: title,
        body: body,
        payload:
            'hikercircle://hike/active?sessionId=${Uri.encodeQueryComponent(hike.sessionId)}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'hiker_circle_active_hike',
            'Active hike safety',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {
      // The in-app warning above remains available when notifications are off.
    }
    await hikerCircleRepository.recordPathDeviationAlert(
      session: widget.session,
      activeHike: hike,
      coordinate: coordinate,
      distanceMeters: distanceMeters,
    );
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
      // Safety evaluation deliberately precedes strict route-telemetry
      // validation. A cached or low-accuracy fix can still establish that the
      // phone has not moved, while the gyroscope/native monitor supplies the
      // second factor before any response countdown begins.
      _evaluateStationaryLocationWatch(
        hike,
        coordinate,
        location.accuracyMeters,
      );
      if (!_isAcceptableTrackingLocation(hike, location)) {
        return;
      }
      _evaluatePathDeviation(hike, coordinate, location.accuracyMeters);
      if (!shouldRecord) {
        return;
      }

      final batteryLevel = await _readBatteryLevel();

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
        final canonicalSessionId = _activeHikeSessionIdRemaps[sessionId];
        if (canonicalSessionId != null) {
          await hikerCircleRepository.localDatabase
              .migrateHikeTelemetrySessionId(
                ownerPhoneNumber: widget.session.phoneNumber,
                oldSessionId: sessionId,
                newSessionId: canonicalSessionId,
              );
        }
        final terminalSessionId = canonicalSessionId ?? sessionId;
        if (_terminalCloudHikeSessionIds.contains(sessionId) ||
            _terminalCloudHikeSessionIds.contains(terminalSessionId)) {
          await hikerCircleRepository.localDatabase
              .discardHikeTrackingTelemetry(sessionId: terminalSessionId);
          if (terminalSessionId != sessionId) {
            await hikerCircleRepository.localDatabase
                .discardHikeTrackingTelemetry(sessionId: sessionId);
          }
        }
        _activeHikeSessionIdRemaps.remove(sessionId);
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
      _persistActiveHikeSnapshot(updatedHike);
      _syncActiveHikeLiveStatus(updatedHike, force: true);
      _syncTeamHikeLocation(updatedHike, location);
      didRecordLocation = true;
    } catch (error) {
      debugPrint('Unable to record the active hike location tick: $error');
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
    double? accuracyMeters,
  ) {
    final stationaryTriggerDuration =
        hike.draft.fallDetectionSettings.longestRestDuration;
    final now = DateTime.now();
    final reference = stationaryWatchReferenceLocation;
    final referenceAccuracy = stationaryWatchReferenceAccuracyMeters ?? 0;
    final currentAccuracy = accuracyMeters?.isFinite == true
        ? accuracyMeters!.clamp(0, 500).toDouble()
        : 0.0;
    final movedEnough =
        reference == null ||
        StationaryLocationPolicy.isMeaningfulMovement(
          distanceMeters: reference.distanceTo(coordinate),
          referenceAccuracyMeters: referenceAccuracy,
          currentAccuracyMeters: currentAccuracy,
        );

    if (movedEnough) {
      stationaryWatchReferenceLocation = coordinate;
      stationaryWatchReferenceAccuracyMeters = currentAccuracy;
      stationaryWatchStartedAt = now;
      if (isStationaryLocationWatchActive) {
        fallStillnessMonitor.cancelStationaryLocationWatch(
          'New location recorded',
        );
        isStationaryLocationWatchActive = false;
      }
      return;
    }

    if (currentAccuracy > 0 &&
        (referenceAccuracy <= 0 || currentAccuracy < referenceAccuracy)) {
      stationaryWatchReferenceLocation = coordinate;
      stationaryWatchReferenceAccuracyMeters = currentAccuracy;
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
        final updatedHike = _withTeamHikeSessionLink(currentHike, teamSession);
        setState(() {
          activeHike = updatedHike;
        });
        _persistActiveHikeSnapshot(updatedHike);
      } catch (_) {
        // Team position sync should never stop the local tracking loop.
      }
    }());
  }

  void _syncBleTeamLocation(ActiveHikeSession? _) {
    // The legacy team-location advertisement has no per-session MAC. Do not
    // broadcast private coordinates or use nearby packets as safety evidence
    // until the native protocol authenticates and replay-protects them.
    unawaited(_bleService.stopTeamLocationExchange());
  }

  void _handleBleTeamLocation(HikerBleTeamLocationEvent _) {
    // Intentionally ignored: hashes and timestamps alone do not authenticate a
    // teammate. Cloud-authorized participant updates remain authoritative.
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
    unawaited(_activeHikeLiveStatusService.cancelNativeSafetyAlert());
    isFallStillnessLocalAlarmActive = false;
    _showFallStillnessSnackBar('$reason. Fall SOS countdown cancelled.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    fallStillnessMonitor.removeListener(_handleFallStillnessMonitorChanged);
    fallStillnessMonitor.dispose();
    _myUpcomingHikesSubscription?.cancel();
    _trailsSubscription?.cancel();
    _stopActiveHikeLocationRecording();
    teamHikeSessionSubscription?.cancel();
    teamHikeWatchSessionId = null;
    batteryLevelTimer?.cancel();
    _stopActiveHikeMonitoringHeartbeat();
    fcmTokenSubscription?.cancel();
    fcmOpenSubscription?.cancel();
    fcmForegroundSubscription?.cancel();
    _bleEventSubscription?.cancel();
    _networkReachabilitySubscription?.cancel();
    _formedTeamChatsSubscription?.cancel();
    for (final timer in _nearbySosFallbackTimers.values) {
      timer.cancel();
    }
    _nearbySosFallbackTimers.clear();
    unawaited(_bleService.stopTeamLocationExchange());
    unawaited(NetworkReachabilityService.instance.stop());

    unawaited(_sosDeviceAlertService.stopFallStillnessCountdownVibration());
    unawaited(_sosDeviceAlertService.stopSpokenPrompt());
    unawaited(_sosDeviceAlertService.stopManualSosPattern());
    tabController.removeListener(updateTabIndex);
    _deepLinkChannel.setMethodCallHandler(null);
    _activeHikeLiveStatusService.setNativeSafetyEventHandler(null);
    tabController.dispose();
    LocationSnapshotService.instance.stop();
    LiveLocationSharingService.instance.reset();
    super.dispose();
  }

  List<HikerBottomNavDestination> _visibleTabs() {
    if (activeHike != null) {
      return tabs
          .where(
            (t) =>
                t.label == 'Home' || t.label == 'SOS' || t.label == 'Profile',
          )
          .toList();
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _recordFallStillnessCancelTap(),
            child: TabBarView(
              controller: tabController,
              physics: activeHike != null
                  ? const NeverScrollableScrollPhysics()
                  : null,
              children: tabs.map(pageFor).toList(),
            ),
          ),
          if (isRestoringActiveHike)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const HikerCircleLoadingView(
                  message: 'Restoring your active hike…',
                  detail: 'Loading your route, checkpoints, and team status.',
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: isRestoringActiveHike
          ? null
          : HikerBottomNavBar(
              currentIndex: selectedTabIndex,
              onDestinationSelected: onTabTap,
              destinations: _visibleTabs(),
            ),
    );
  }
}

class _BleNearbyProximityMap extends StatefulWidget {
  const _BleNearbyProximityMap({required this.rssi});

  final int? rssi;

  @override
  State<_BleNearbyProximityMap> createState() => _BleNearbyProximityMapState();
}

class _BleNearbyProximityMapState extends State<_BleNearbyProximityMap> {
  static const _refreshInterval = Duration(seconds: 5);

  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PolygonAnnotationManager? _polygonManager;
  Timer? _locationTimer;
  SosTriggerLocation? _location;
  bool _styleLoaded = false;
  bool _refreshing = false;
  bool _hasCentered = false;

  double get _radiusMeters =>
      _HikerHomePageState._bleRangeMeters(widget.rssi ?? -70);

  mapbox.Point? get _point {
    final location = _location;
    if (location == null) return null;
    return mapbox.Point(
      coordinates: mapbox.Position(location.longitude, location.latitude),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshLocation());
    _locationTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(_refreshLocation());
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final location = await LocationSnapshotService.instance.refresh();
      if (!mounted || location == null) return;
      setState(() => _location = location);
      await _render();
      final point = _point;
      if (!_hasCentered && point != null && _mapboxMap != null) {
        _hasCentered = true;
        await _mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: point,
            zoom: (16 - math.log(_radiusMeters / 50) / math.ln2).clamp(11, 18),
          ),
          mapbox.MapAnimationOptions(duration: 300),
        );
      }
    } catch (error) {
      debugPrint('Unable to refresh the nearby SOS map: $error');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    try {
      await map.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      await map.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: false,
        ),
      );
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {}
    await _ensureManagers();
    await _render();
  }

  Future<void> _onStyleReady() async {
    _styleLoaded = true;
    _circleManager = null;
    _polygonManager = null;
    await _ensureManagers();
    await _render();
  }

  Future<bool> _ensureManagers() async {
    if (_mapboxMap == null || !_styleLoaded) return false;
    try {
      _circleManager ??= await _mapboxMap!.annotations
          .createCircleAnnotationManager();
      _polygonManager ??= await _mapboxMap!.annotations
          .createPolygonAnnotationManager();
      return true;
    } catch (_) {
      return false;
    }
  }

  List<mapbox.Position> _ring(double latitude, double longitude) {
    final radius = _radiusMeters;
    final latDelta = radius / 111320;
    final lonDelta =
        radius / (111320 * math.cos(latitude * math.pi / 180).clamp(0.2, 1.0));
    return List<mapbox.Position>.generate(49, (index) {
      final angle = 2 * math.pi * index / 48;
      return mapbox.Position(
        longitude + lonDelta * math.cos(angle),
        latitude + latDelta * math.sin(angle),
      );
    });
  }

  Future<void> _render() async {
    if (!await _ensureManagers()) return;
    final point = _point;
    if (point == null) return;
    try {
      await _circleManager?.deleteAll();
      await _polygonManager?.deleteAll();
      final latitude = point.coordinates[1]!.toDouble();
      final longitude = point.coordinates[0]!.toDouble();
      await _polygonManager?.create(
        mapbox.PolygonAnnotationOptions(
          geometry: mapbox.Polygon(coordinates: [_ring(latitude, longitude)]),
          fillColor: const Color(0xFF0A84FF).toARGB32(),
          fillOpacity: 0.14,
          fillOutlineColor: const Color(0xFF0A84FF).toARGB32(),
        ),
      );
      await _circleManager?.create(
        mapbox.CircleAnnotationOptions(
          geometry: point,
          circleColor: const Color(0xFF0A84FF).toARGB32(),
          circleRadius: 9,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2.5,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          mapbox.MapWidget(
            key: const ValueKey('ble-nearby-proximity-map'),
            styleUri: mapStyleUrls[1],
            viewport: mapbox.CameraViewportState(
              center: point ?? mapbox.Point(coordinates: mapbox.Position(0, 0)),
              zoom: point == null ? 1 : 15,
            ),
            gestureRecognizers: mapGestureRecognizers,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleReady(),
            onMapLoadedListener: (_) => _onStyleReady(),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  point == null
                      ? 'Getting detector location…'
                      : 'Detector location • possible range ${_radiusMeters.round()} m',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BleSosHelpMap extends StatefulWidget {
  const _BleSosHelpMap({
    required this.targetLatitude,
    required this.targetLongitude,
  });

  final double targetLatitude;
  final double targetLongitude;

  @override
  State<_BleSosHelpMap> createState() => _BleSosHelpMapState();
}

class _BleSosHelpMapState extends State<_BleSosHelpMap> {
  static const Duration _locationRefreshInterval = Duration(seconds: 5);

  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.PolylineAnnotationManager? _polylineManager;
  Timer? _locationTimer;
  SosTriggerLocation? _currentLocation;
  double? _distanceMeters;
  double? _previousDistanceMeters;
  bool _styleLoaded = false;
  bool _isRefreshingLocation = false;
  int _renderGeneration = 0;

  mapbox.Point get _targetPoint => mapbox.Point(
    coordinates: mapbox.Position(widget.targetLongitude, widget.targetLatitude),
  );

  mapbox.Point? get _currentPoint {
    final location = _currentLocation;
    if (location == null) {
      return null;
    }
    return mapbox.Point(
      coordinates: mapbox.Position(location.longitude, location.latitude),
    );
  }

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _renderGeneration++;
    super.dispose();
  }

  void _startLocationUpdates() {
    unawaited(_refreshLocation());
    _locationTimer = Timer.periodic(_locationRefreshInterval, (_) {
      unawaited(_refreshLocation());
    });
  }

  Future<void> _refreshLocation() async {
    if (_isRefreshingLocation) {
      return;
    }
    _isRefreshingLocation = true;
    try {
      final location = await LocationSnapshotService.instance.refresh();
      if (!mounted || location == null) {
        return;
      }
      final nextDistance = distanceMeters(
        _targetPoint,
        mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        ),
      );
      setState(() {
        _previousDistanceMeters = _distanceMeters;
        _currentLocation = location;
        _distanceMeters = nextDistance;
      });
      await _renderMarkers();
    } catch (error) {
      debugPrint('Unable to refresh the SOS help map: $error');
    } finally {
      _isRefreshingLocation = false;
    }
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await mapboxMap.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: false,
        ),
      );
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {}
    await _fitMap();
  }

  Future<void> _onStyleReady() async {
    _styleLoaded = true;
    _circleManager = null;
    _pointManager = null;
    _polylineManager = null;
    _renderGeneration++;
    await _ensureAnnotationManagers();
    await _renderMarkers();
  }

  Future<bool> _ensureAnnotationManagers() async {
    final map = _mapboxMap;
    if (map == null || !_styleLoaded) {
      return false;
    }
    try {
      _circleManager ??= await map.annotations.createCircleAnnotationManager();
      _pointManager ??= await map.annotations.createPointAnnotationManager();
      _polylineManager ??= await map.annotations
          .createPolylineAnnotationManager();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _renderMarkers() async {
    if (!await _ensureAnnotationManagers()) {
      return;
    }
    final generation = ++_renderGeneration;
    final target = _targetPoint;
    final current = _currentPoint;
    try {
      await _circleManager?.deleteAll();
      await _pointManager?.deleteAll();
      await _polylineManager?.deleteAll();
      if (!mounted || generation != _renderGeneration) {
        return;
      }

      if (current != null) {
        await _polylineManager?.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(
              coordinates: [
                mapbox.Position(
                  current.coordinates[0]!,
                  current.coordinates[1]!,
                ),
                mapbox.Position(target.coordinates[0]!, target.coordinates[1]!),
              ],
            ),
            lineColor: const Color(0xFFFF3B30).toARGB32(),
            lineOpacity: 0.78,
            lineWidth: 3,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }

      final circles = <mapbox.CircleAnnotationOptions>[
        if (current != null && _currentLocation?.accuracyMeters != null)
          mapbox.CircleAnnotationOptions(
            geometry: current,
            circleColor: const Color(0xFF0A84FF).toARGB32(),
            circleOpacity: 0.12,
            circleRadius: (_currentLocation!.accuracyMeters! / 8).clamp(12, 42),
            circleStrokeColor: const Color(0xFF0A84FF).toARGB32(),
            circleStrokeWidth: 1,
          ),
        if (current != null)
          mapbox.CircleAnnotationOptions(
            geometry: current,
            circleColor: const Color(0xFF0A84FF).toARGB32(),
            circleRadius: 8,
            circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
            circleStrokeWidth: 2.5,
          ),
        mapbox.CircleAnnotationOptions(
          geometry: target,
          circleColor: const Color(0xFFFF3B30).toARGB32(),
          circleRadius: 14,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 3,
        ),
      ];
      await _circleManager?.createMulti(circles);
      await _pointManager?.create(
        mapbox.PointAnnotationOptions(
          geometry: target,
          textField: '!',
          textColor: const Color(0xFFFFFFFF).toARGB32(),
          textHaloColor: const Color(0xFF7A1010).toARGB32(),
          textHaloWidth: 0.5,
          textSize: 18,
          textAnchor: mapbox.TextAnchor.CENTER,
        ),
      );
      await _fitMap();
    } catch (_) {}
  }

  Future<void> _fitMap() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }
    final points = [_targetPoint, if (_currentPoint != null) _currentPoint!];
    try {
      if (points.length == 1) {
        await map.flyTo(
          mapbox.CameraOptions(center: points.first, zoom: 16),
          mapbox.MapAnimationOptions(duration: 250),
        );
        return;
      }
      final bounds = boundsFor(points);
      final camera = await map.cameraForCoordinateBounds(
        mapbox.CoordinateBounds(
          southwest: mapbox.Point(
            coordinates: mapbox.Position(bounds.minLon, bounds.minLat),
          ),
          northeast: mapbox.Point(
            coordinates: mapbox.Position(bounds.maxLon, bounds.maxLat),
          ),
          infiniteBounds: false,
        ),
        mapbox.MbxEdgeInsets(top: 58, left: 42, bottom: 78, right: 42),
        null,
        null,
        null,
        null,
      );
      await map.flyTo(camera, mapbox.MapAnimationOptions(duration: 300));
    } catch (_) {
      await map.flyTo(
        mapbox.CameraOptions(center: centerFor(points), zoom: 15),
        mapbox.MapAnimationOptions(duration: 250),
      );
    }
  }

  String get _distanceLabel {
    final distance = _distanceMeters;
    if (distance == null) {
      return 'Getting your location...';
    }
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(2)} km away';
    }
    return '${distance.round()} m away';
  }

  String get _approachLabel {
    final current = _distanceMeters;
    final previous = _previousDistanceMeters;
    if (current == null) {
      return 'Move toward the warning marker';
    }
    if (current <= 25) {
      return 'You are very close to the SOS location';
    }
    if (previous == null || (previous - current).abs() < 3) {
      return 'Distance will update as you move';
    }
    return current < previous
        ? 'You are approaching the target'
        : 'You are moving farther from the target';
  }

  Color _approachColor(BuildContext context) {
    final current = _distanceMeters;
    final previous = _previousDistanceMeters;
    if (current != null && current <= 25) {
      return const Color(0xFF34C759);
    }
    if (current != null && previous != null && current > previous + 3) {
      return const Color(0xFFFF9500);
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final targetLabel =
        '${widget.targetLatitude.toStringAsFixed(5)}, ${widget.targetLongitude.toStringAsFixed(5)}';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          mapbox.MapWidget(
            key: const ValueKey('ble-sos-help-map'),
            styleUri: mapStyleUrls[1],
            viewport: mapbox.CameraViewportState(
              center: _targetPoint,
              zoom: 15,
            ),
            gestureRecognizers: mapGestureRecognizers,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleReady(),
            onMapLoadedListener: (_) => _onStyleReady(),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: const Color(0xFFFF3B30),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 34,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _approachColor(
                            context,
                          ).withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.navigation_rounded,
                          size: 18,
                          color: _approachColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _distanceLabel,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            _approachLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _approachColor(context)),
                          ),
                        ],
                      ),
                    ),
                    if (_isRefreshingLocation)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamHikeLaunchPage extends StatefulWidget {
  const _TeamHikeLaunchPage({
    required this.session,
    required this.repository,
    required this.deviceAlertService,
    required this.initialTeamSession,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final SosDeviceAlertService deviceAlertService;
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
                                subtitle: _readyButtonSubtitle(teamSession),
                                enabled: _canPressButton(teamSession),
                                busy: _isMarkingReady || _isActivating,
                                countdown:
                                    teamSession.phase == TeamHikePhase.countdown
                                    ? teamSession.countdownRemainingSeconds
                                    : null,
                                onPressed: () =>
                                    unawaited(_onButtonPressed(teamSession)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _TeamLaunchStatusCard(
                        teamSession: teamSession,
                        currentPhoneNumber: widget.session.phoneNumber,
                        onRemovePendingInvitees:
                            _sameTeamPhone(
                                  teamSession.hostPhoneNumber,
                                  widget.session.phoneNumber,
                                ) &&
                                teamSession.invitedCount > 0
                            ? () =>
                                  unawaited(_removePendingInvitees(teamSession))
                            : null,
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
    final isHost = _sameTeamPhone(
      teamSession.hostPhoneNumber,
      widget.session.phoneNumber,
    );
    if (teamSession.phase == TeamHikePhase.countdown) {
      return 'STARTING';
    }
    if (participant?.status.isReadyForStart == true) {
      return isHost ? 'START HIKE' : 'READY SENT';
    }
    return 'READY';
  }

  String _readyButtonSubtitle(TeamHikeSession teamSession) {
    final participant = _currentParticipant(teamSession);
    final isHost = _sameTeamPhone(
      teamSession.hostPhoneNumber,
      widget.session.phoneNumber,
    );
    if (teamSession.phase == TeamHikePhase.countdown) {
      return _launchSubtitle(teamSession);
    }
    if (participant?.status.isReadyForStart == true) {
      return isHost
          ? 'Start when everyone is ready'
          : 'Waiting for the host to start';
    }
    return 'press when ready';
  }

  bool _canMarkReady(TeamHikeSession teamSession) {
    if (_isMarkingReady ||
        teamSession.phase == TeamHikePhase.countdown ||
        teamSession.phase == TeamHikePhase.active) {
      return false;
    }
    final participant = _currentParticipant(teamSession);
    return participant?.status.isReadyForStart != true;
  }

  bool _canPressButton(TeamHikeSession teamSession) {
    final participant = _currentParticipant(teamSession);
    if (participant?.status.isReadyForStart == true) {
      final isHost = _sameTeamPhone(
        teamSession.hostPhoneNumber,
        widget.session.phoneNumber,
      );
      return isHost &&
          teamSession.phase == TeamHikePhase.readyCheck &&
          teamSession.everyoneReady;
    }
    return _canMarkReady(teamSession);
  }

  Future<void> _onButtonPressed(TeamHikeSession teamSession) async {
    final participant = _currentParticipant(teamSession);
    if (participant?.status.isReadyForStart == true) {
      final isHost = _sameTeamPhone(
        teamSession.hostPhoneNumber,
        widget.session.phoneNumber,
      );
      if (isHost) {
        setState(() => _isActivating = true);
        await _activateAndClose(teamSession);
      }
      return;
    }
    await _markCurrentParticipantReady(teamSession);
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
    setState(() => _isMarkingReady = true);
    try {
      final profile = await widget.repository.loadCommunityProfile(
        phoneNumber: widget.session.phoneNumber,
      );
      if (!mounted) return;
      final repo = widget.repository;
      final session = widget.session;
      final safetySettings = await Navigator.of(context)
          .push<Map<String, dynamic>>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _TeamSafetyPreparationPage(
                session: session,
                repository: repo,
                deviceAlertService: widget.deviceAlertService,
                enhancedProtectionRecommended:
                    (profile?['gender'] is String
                            ? profile!['gender'] as String
                            : '')
                        .toLowerCase() ==
                    'female',
              ),
            ),
          );
      if (safetySettings == null || !mounted) return;
      await widget.repository.markTeamParticipantReady(
        session: widget.session,
        teamHikeSessionId: teamSession.id,
        safetySettings: safetySettings,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is HikerCircleFirebaseRepositoryException
          ? error.message
          : 'Unable to send Ready. Check your connection and try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingReady = false;
        });
      }
    }
  }

  Future<void> _removePendingInvitees(TeamHikeSession teamSession) async {
    if (_isMarkingReady || _isActivating || !mounted) return;
    final shouldRemove = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Continue without pending buddies?'),
        content: Text(
          '${teamSession.invitedCount} invitation${teamSession.invitedCount == 1 ? ' has' : 's have'} not been accepted. Removing them lets the remaining team complete the ready check.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep waiting'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove pending'),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !mounted) return;
    setState(() => _isMarkingReady = true);
    try {
      await widget.repository.removePendingTeamInvitees(
        session: widget.session,
        teamHikeSessionId: teamSession.id,
      );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _isMarkingReady = false);
    }
  }

  void _closeWhenReady(TeamHikeSession teamSession) {
    if (_isActivating) {
      return;
    }
    if (teamSession.phase == TeamHikePhase.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = ModalRoute.of(context);
        if (mounted && route != null && route.isCurrent) {
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
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    try {
      final activeSession = await widget.repository.activateTeamHikeSession(
        session: widget.session,
        teamHikeSessionId: teamSession.id,
      );
      if (route != null && route.isCurrent) {
        navigator.pop(activeSession);
      }
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _isActivating = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isActivating = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to activate the team hike. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

class _TeamSafetyPreparationPage extends StatefulWidget {
  const _TeamSafetyPreparationPage({
    required this.session,
    required this.repository,
    required this.deviceAlertService,
    required this.enhancedProtectionRecommended,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final SosDeviceAlertService deviceAlertService;
  final bool enhancedProtectionRecommended;

  @override
  State<_TeamSafetyPreparationPage> createState() =>
      _TeamSafetyPreparationPageState();
}

class _TeamSafetyPreparationPageState
    extends State<_TeamSafetyPreparationPage> {
  double _sensitivity = 5;
  Duration _fallResponseDuration = const Duration(seconds: 30);
  Duration _longestRestDuration = const Duration(minutes: 3);
  bool _sensitivitySelected = true;
  bool _fallResponseSelected = true;
  bool _longestRestSelected = true;
  late bool _enhancedIsolationProtection = widget.enhancedProtectionRecommended;
  bool _isLoadingPrefs = true;
  bool _isSavingPreferences = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await widget.repository.loadTeamSafetyPreferences(
        session: widget.session,
      );
      if (!mounted) return;
      if (prefs != null) {
        final sensitivity = _finiteDoubleValue(prefs['sensorSensitivity']);
        if (sensitivity != null) {
          _sensitivity = sensitivity.clamp(
            FallDetectionSettings.minSensorSensitivity,
            FallDetectionSettings.maxSensorSensitivity,
          );
          _sensitivitySelected = true;
        }
        final fallResponseSeconds = _boundedIntValue(
          prefs['fallResponseDurationSeconds'],
          minimum: 5,
          maximum: 600,
        );
        if (fallResponseSeconds != null) {
          final seconds = fallResponseSeconds;
          _fallResponseDuration = Duration(seconds: seconds);
          _fallResponseSelected = true;
        }
        final longestRestSeconds = _boundedIntValue(
          prefs['longestRestDurationSeconds'],
          minimum: 30,
          maximum: 86400,
        );
        if (longestRestSeconds != null) {
          final seconds = longestRestSeconds;
          _longestRestDuration = Duration(seconds: seconds);
          _longestRestSelected = true;
        }
        if (prefs['enhancedIsolationProtection'] is bool) {
          _enhancedIsolationProtection =
              prefs['enhancedIsolationProtection'] as bool;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Saved team safety settings are unavailable. Review them before continuing.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPrefs = false);
      }
    }
  }

  static const _fallResponseOptions = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 5),
  ];

  static const _longestRestOptions = [
    Duration(minutes: 3),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  Future<void> _confirm() async {
    if (_isSavingPreferences) return;
    if (!await ensureIosSosOutputVolumeReady(
      context: context,
      deviceAlertService: widget.deviceAlertService,
      title: 'Turn Up iPhone Volume',
      message:
          'Fall SOS and offline audio SOS use iPhone media volume for the local alarm. Turn it up before confirming your settings.',
      proceedLabel: 'Confirm Settings',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _isSavingPreferences = true);
    final effectiveResponseDuration =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? const Duration(seconds: 15)
        : _fallResponseDuration;
    final prefs = <String, dynamic>{
      'liveLocationSharing': true,
      'pathDeviationAlerts': true,
      'teammateSeparationAlerts': true,
      'fallDetectionEnabled': true,
      'sensorSensitivity': _sensitivity,
      'responseCountdownSeconds': effectiveResponseDuration.inSeconds,
      'fallResponseDurationSeconds': effectiveResponseDuration.inSeconds,
      'longestRestDurationSeconds': _longestRestDuration.inSeconds,
      'enhancedIsolationProtection': _enhancedIsolationProtection,
      'separationDistanceMeters': _enhancedIsolationProtection ? 100 : 150,
      'isolationGraceSeconds': _enhancedIsolationProtection ? 90 : 180,
      'automaticTeamCheckPing': true,
    };
    try {
      await widget.repository.saveTeamSafetyPreferences(
        session: widget.session,
        preferences: prefs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(prefs);
    } catch (error) {
      if (!mounted) return;
      final message = error is HikerCircleFirebaseRepositoryException
          ? error.message
          : 'Unable to save team safety settings. Try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } finally {
      if (mounted) {
        setState(() => _isSavingPreferences = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _SafetyTheme.of(context);
    final theme = Theme.of(context);
    final androidNativeSafety =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final responseOptions = androidNativeSafety
        ? const [Duration(seconds: 15)]
        : _fallResponseOptions;
    final effectiveResponseDuration = androidNativeSafety
        ? const Duration(seconds: 15)
        : _fallResponseDuration;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                              color: colors.surface.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.xmark,
                              color: colors.text,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Team safety setup',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                    child: Text(
                      'Complete these settings before sending Ready. Required team settings stay enabled while the app is active; mobile OS suspension can pause updates.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _LockedTeamSafetyRow(
                    icon: Icons.location_on_rounded,
                    title: 'Live location sharing',
                    subtitle: 'Visible only to this hike team while active.',
                  ),
                  const _LockedTeamSafetyRow(
                    icon: Icons.alt_route_rounded,
                    title: 'Path deviation alerts',
                    subtitle: 'The team is warned when you leave the route.',
                  ),
                  const _LockedTeamSafetyRow(
                    icon: Icons.groups_rounded,
                    title: 'Teammate separation alerts',
                    subtitle: 'Checks distance from the nearest teammate.',
                  ),
                  const SizedBox(height: 14),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Sensor Sensitivity',
                      prefixIcon: Icon(Icons.sensors_rounded),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_sensitivityLabel(_sensitivity)} (${_sensitivity.round()}/10)',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _sensitivity,
                          min: FallDetectionSettings.minSensorSensitivity,
                          max: FallDetectionSettings.maxSensorSensitivity,
                          divisions:
                              (FallDetectionSettings.maxSensorSensitivity -
                                      FallDetectionSettings
                                          .minSensorSensitivity)
                                  .round(),
                          activeColor: colors.green,
                          inactiveColor: colors.separator,
                          label:
                              '${_sensitivityLabel(_sensitivity)} ${_sensitivity.round()}/10',
                          onChanged: (value) => setState(() {
                            _sensitivity = value;
                            _sensitivitySelected = true;
                          }),
                        ),
                        if (_sensitivity > 7)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'High sensitivity can detect softer hiking falls, '
                              'but it may also cause more false alarms from '
                              'backpack drops or sitting down hard.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.red,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Duration>(
                    initialValue: effectiveResponseDuration,
                    decoration: InputDecoration(
                      labelText: androidNativeSafety
                          ? 'Safety warning response window'
                          : 'Longest response time after a fall',
                      prefixIcon: const Icon(Icons.personal_injury_rounded),
                    ),
                    items: [
                      for (final duration in responseOptions)
                        DropdownMenuItem(
                          value: duration,
                          child: Text(
                            duration.inSeconds < 60
                                ? '${duration.inSeconds} seconds'
                                : '${duration.inMinutes} minute${duration.inMinutes == 1 ? '' : 's'}',
                          ),
                        ),
                    ],
                    onChanged: androidNativeSafety
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _fallResponseDuration = value;
                                _fallResponseSelected = true;
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    androidNativeSafety
                        ? 'Android vibrates, speaks an “Are you okay?” prompt, '
                              'and accepts a tap anywhere on the lock-screen '
                              'warning for 15 seconds. No SOS is sent yet.'
                        : 'After a fall and stillness are confirmed, this is how long '
                              'you have to cancel before Fall SOS is sent.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Duration>(
                    initialValue: _longestRestDuration,
                    decoration: const InputDecoration(
                      labelText: 'Longest time for a rest',
                      prefixIcon: Icon(Icons.self_improvement_rounded),
                    ),
                    items: [
                      for (final duration in _longestRestOptions)
                        DropdownMenuItem(
                          value: duration,
                          child: Text(
                            '${duration.inMinutes} minute${duration.inMinutes == 1 ? '' : 's'}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _longestRestDuration = value;
                          _longestRestSelected = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If your location stays within 5 m for this long, '
                    'HikerCircle checks for phone movement and asks you to '
                    'respond before sending a prolonged-stillness SOS.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Enhanced isolation protection',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    subtitle: Text(
                      widget.enhancedProtectionRecommended
                          ? 'Recommended from your private safety profile. '
                                'Teammates are never shown why.'
                          : 'Uses a tighter 100 m separation threshold '
                                'and faster team escalation.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        letterSpacing: 0,
                      ),
                    ),
                    value: _enhancedIsolationProtection,
                    onChanged: (value) =>
                        setState(() => _enhancedIsolationProtection = value),
                  ),
                  const SizedBox(height: 8),
                  if (!_sensitivitySelected ||
                      !_fallResponseSelected ||
                      !_longestRestSelected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Select sensor sensitivity, fall response time, '
                        'and longest rest time to continue.',
                        style: TextStyle(
                          color: colors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        _isLoadingPrefs ||
                            _isSavingPreferences ||
                            !_sensitivitySelected ||
                            !_fallResponseSelected ||
                            !_longestRestSelected
                        ? null
                        : () => unawaited(_confirm()),
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Save safety settings and send Ready'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sensitivityLabel(double value) {
    if (value < 3.5) return 'Low';
    if (value > 7) return 'High';
    return 'Medium';
  }
}

class _LockedTeamSafetyRow extends StatelessWidget {
  const _LockedTeamSafetyRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = _SafetyTheme.of(context);
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.lock_rounded, color: colors.green),
      title: Text(
        title,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.secondaryText,
          letterSpacing: 0,
        ),
      ),
      trailing: Icon(icon, color: colors.green),
    );
  }
}

final class _SafetyTheme {
  static const Color _lightBackground = Color(0xFFF2F2F7);
  static const Color _lightSurface = Colors.white;
  static const Color _lightGreen = Color(0xFF34A853);
  static const Color _lightSeparator = Color(0xFFD9E1DC);
  static const Color _lightText = Color(0xFF111111);
  static const Color _lightSecondaryText = Color(0xFF6E6E73);
  static const Color _lightOrange = Color(0xFFF59E0B);
  static const Color _lightRed = Color(0xFFE11D48);

  static const Color _darkBackground = Color(0xFF0C120F);
  static const Color _darkSurface = Color(0xFF141C17);
  static const Color _darkSeparator = Color(0xFF2B3A31);
  static const Color _darkText = Color(0xFFEAF4EE);
  static const Color _darkSecondaryText = Color(0xFFA8B8AE);
  static const Color _darkRed = Color(0xFFFF6B88);

  final BuildContext context;
  _SafetyTheme(this.context);

  static _SafetyTheme of(BuildContext context) => _SafetyTheme(context);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get background => _isDark ? _darkBackground : _lightBackground;
  Color get surface => _isDark ? _darkSurface : _lightSurface;
  Color get green => _lightGreen;
  Color get separator => _isDark ? _darkSeparator : _lightSeparator;
  Color get text => _isDark ? _darkText : _lightText;
  Color get secondaryText => _isDark ? _darkSecondaryText : _lightSecondaryText;
  Color get orange => _lightOrange;
  Color get red => _isDark ? _darkRed : _lightRed;
}

class _ReadyLaunchButton extends StatelessWidget {
  const _ReadyLaunchButton({
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.busy,
    required this.onPressed,
    this.countdown,
  });

  final String label;
  final String subtitle;
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
                      countdownValue == null ? subtitle : label,
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
    this.onRemovePendingInvitees,
  });

  final TeamHikeSession teamSession;
  final String currentPhoneNumber;
  final VoidCallback? onRemovePendingInvitees;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10291B),
            const Color(0xFF07140D).withValues(alpha: 0.96),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF7EE0A0).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(
            'TEAM ASSEMBLY',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF7EE0A0),
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${teamSession.readyCount} / ${teamSession.participants.length} READY',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth -
                      (teamSession.participants.length > 3 ? 24 : 16)) /
                  (teamSession.participants.length > 3 ? 3 : 2);
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 18,
                children: [
                  for (final participant in teamSession.participants)
                    SizedBox(
                      width: width.clamp(92, 132),
                      child: _TeamReadyPlayerSlot(
                        participant: participant,
                        isSelf: _sameTeamPhone(
                          participant.phoneNumber,
                          currentPhoneNumber,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  teamSession.everyoneReady
                      ? Icons.verified_rounded
                      : Icons.sync_rounded,
                  color: teamSession.everyoneReady
                      ? const Color(0xFF7EE0A0)
                      : Colors.white70,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Text(
                  teamSession.everyoneReady
                      ? 'All safety checks complete'
                      : 'Waiting for safety checks',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (onRemovePendingInvitees != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRemovePendingInvitees,
              icon: const Icon(Icons.person_remove_alt_1_rounded),
              label: const Text('Continue without pending invitees'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFBBF24),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamReadyPlayerSlot extends StatelessWidget {
  const _TeamReadyPlayerSlot({required this.participant, required this.isSelf});

  final TeamHikeParticipant participant;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final isReady = participant.status.isReadyForStart;
    final isInvited = participant.status == TeamHikeParticipantStatus.invited;
    final accent = isReady
        ? const Color(0xFF7EE0A0)
        : isInvited
        ? const Color(0xFFFBBF24)
        : Colors.white54;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isReady
                    ? accent.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.28),
                border: Border.all(color: accent, width: isReady ? 4 : 2),
                boxShadow: isReady
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.42),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : const [],
              ),
              padding: const EdgeInsets.all(7),
              child: CircleAvatar(
                backgroundColor: Color(participant.buddy.avatarColorValue),
                child: Text(
                  participant.buddy.shortName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (participant.isHost)
              const Positioned(
                top: -12,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD166),
                  size: 25,
                ),
              ),
            if (isReady)
              Positioned(
                right: -2,
                bottom: 2,
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34A853),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          isSelf ? 'You' : participant.buddy.shortName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isReady
                ? 'READY'
                : isInvited
                ? 'INVITED'
                : 'PREPARING',
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ],
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
                                color: Theme.of(context).colorScheme.onSurface,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          value.message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Keep HikerCircle open for a moment.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
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
    required this.session,
    required this.report,
    required this.activeHike,
    required this.onShareReportText,
    this.onShareToCommunity,
    this.initialMapStyleIndex = 0,
  });

  final AppSession session;
  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final Future<void> Function(
    String caption,
    List<CommunityPostImageUpload> images,
  )?
  onShareToCommunity;
  final Future<void> Function(String text) onShareReportText;
  final int initialMapStyleIndex;

  @override
  State<_HikeSummaryReportPage> createState() => _HikeSummaryReportPageState();
}

class _HikeSummaryReportPageState extends State<_HikeSummaryReportPage> {
  HikeRouteAnalysis get _routeAnalysis => analyzeHikeRoute(
    routePoints: widget.activeHike.routePoints,
    fallbackStartedAt: widget.activeHike.startedAt,
    checkpoints: widget.activeHike.trail.checkpoints
        .map(
          (checkpoint) => HikeAnalysisCheckpoint(
            name: checkpoint.name,
            order: checkpoint.order,
            latitude: checkpoint.latitude,
            longitude: checkpoint.longitude,
          ),
        )
        .toList(),
  );

  List<mapbox.Point> get _actualPinPoints => widget
      .activeHike
      .manualPinLocations
      .map(
        (pin) => mapbox.Point(
          coordinates: mapbox.Position(
            pin.coordinate.longitude,
            pin.coordinate.latitude,
          ),
        ),
      )
      .toList();

  List<mapbox.Point> get _actualCheckInPoints => widget
      .activeHike
      .checkInRecords
      .map((record) => record.coordinate)
      .whereType<HikeCoordinate>()
      .map(
        (coordinate) => mapbox.Point(
          coordinates: mapbox.Position(
            coordinate.longitude,
            coordinate.latitude,
          ),
        ),
      )
      .toList();

  Future<void> _openSharePreview() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => HikeSharePreviewPage(
          session: widget.session,
          report: widget.report,
          activeHike: widget.activeHike,
          initialMapStyleIndex: widget.initialMapStyleIndex,
          onPostToCommunity: widget.onShareToCommunity,
          onShareExternally: widget.onShareReportText,
        ),
      ),
    );
    if (!mounted || posted != true) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Hike shared to community.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  HikingRouteResult? get _summaryRouteResult {
    final recordedPoints = List<HikeCoordinate>.of(
      widget.activeHike.routePoints,
    );
    final latest = widget.activeHike.latestLocation;
    if (latest != null &&
        (recordedPoints.isEmpty ||
            recordedPoints.last.distanceTo(latest) > 2)) {
      recordedPoints.add(latest);
    }
    recordedPoints.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    if (recordedPoints.length < 2) return null;
    final encoded = PolylineCodec.encode(
      recordedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(),
    );
    if (encoded.isEmpty) return null;
    return HikingRouteResult(
      distanceMeters: (widget.report.distanceKm * 1000).round(),
      duration: widget.report.duration,
      encodedPolyline: encoded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    String formatTime(DateTime dt) {
      final local = dt.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}:'
          '${local.second.toString().padLeft(2, '0')}';
    }

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
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 220,
                      child: RoutePreviewMap(
                        trail: widget.activeHike.trail,
                        route: _summaryRouteResult,
                        pinnedPoints: _actualPinPoints,
                        checkInPoints: _actualCheckInPoints,
                        captureAllGestures: true,
                        animateRoute: false,
                        initialStyleIndex: widget.initialMapStyleIndex,
                      ),
                    ),
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
                  if (_routeAnalysis.checkpoints.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'CHECKPOINT PERFORMANCE',
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
                            index < _routeAnalysis.checkpoints.length;
                            index++
                          ) ...[
                            if (index > 0)
                              Divider(
                                height: 1,
                                color: _SummaryColors.separatorFor(context),
                              ),
                            _SummaryCheckpointPerformanceRow(
                              checkpoint: _routeAnalysis.checkpoints[index],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'CHECK-INS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _SummaryColors.secondaryTextFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SummaryCard(
                    child: widget.activeHike.checkInRecords.isEmpty
                        ? const _SummaryEmptyEvents(
                            message: 'No check-ins recorded.',
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < widget.activeHike.checkInRecords.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  Divider(
                                    height: 1,
                                    color: _SummaryColors.separatorFor(context),
                                  ),
                                _SummaryEventRow(
                                  icon: Icons.location_on_rounded,
                                  label: 'Check-in ${index + 1}',
                                  subtitle: _coordinateLabel(
                                    widget
                                        .activeHike
                                        .checkInRecords[index]
                                        .coordinate,
                                  ),
                                  time: formatTime(
                                    widget
                                        .activeHike
                                        .checkInRecords[index]
                                        .checkedInAt,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'PINS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _SummaryColors.secondaryTextFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SummaryCard(
                    child: widget.activeHike.manualPinLocations.isEmpty
                        ? const _SummaryEmptyEvents(
                            message: 'No locations pinned.',
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index <
                                    widget.activeHike.manualPinLocations.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  Divider(
                                    height: 1,
                                    color: _SummaryColors.separatorFor(context),
                                  ),
                                _SummaryEventRow(
                                  icon: Icons.push_pin_rounded,
                                  label: 'Pinned location ${index + 1}',
                                  subtitle: _coordinateLabel(
                                    widget
                                        .activeHike
                                        .manualPinLocations[index]
                                        .coordinate,
                                  ),
                                  time: formatTime(
                                    widget
                                        .activeHike
                                        .manualPinLocations[index]
                                        .pinnedAt,
                                  ),
                                  iconColor: const Color(0xFFE11D48),
                                ),
                              ],
                            ],
                          ),
                  ),
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
                    key: const Key('preview-and-share-hike'),
                    onPressed: () => unawaited(_openSharePreview()),
                    style: FilledButton.styleFrom(
                      backgroundColor: _SummaryColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share Hike'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('back-to-home-after-hike'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Back to Home'),
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
    final seconds = duration.inSeconds.remainder(60);
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  String _coordinateLabel(HikeCoordinate? coordinate) {
    if (coordinate == null) {
      return 'Location unavailable';
    }
    return '${coordinate.latitude.toStringAsFixed(5)}, '
        '${coordinate.longitude.toStringAsFixed(5)}';
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

class _SummaryEventRow extends StatelessWidget {
  const _SummaryEventRow({
    required this.icon,
    required this.label,
    required this.time,
    this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String time;
  final String? subtitle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? const Color(0xFF0A84FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SummaryColors.textFor(context),
                    letterSpacing: 0,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SummaryColors.secondaryTextFor(context),
                      fontSize: 11,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _SummaryColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCheckpointPerformanceRow extends StatelessWidget {
  const _SummaryCheckpointPerformanceRow({required this.checkpoint});

  final HikeCheckpointAnalysis checkpoint;

  @override
  Widget build(BuildContext context) {
    String clock(DateTime? value) {
      if (value == null) return 'Not reached';
      final local = value.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}:'
          '${local.second.toString().padLeft(2, '0')}';
    }

    String elapsed(Duration? value) {
      if (value == null) return 'Start';
      final hours = value.inHours;
      final minutes = value.inMinutes.remainder(60);
      return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    }

    return Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: checkpoint.reached
                  ? _SummaryColors.green
                  : _SummaryColors.secondaryTextFor(
                      context,
                    ).withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              checkpoint.reached
                  ? Icons.check_rounded
                  : Icons.horizontal_rule_rounded,
              color: checkpoint.reached
                  ? Colors.white
                  : _SummaryColors.secondaryTextFor(context),
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkpoint.name,
                  style: TextStyle(
                    color: _SummaryColors.textFor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  checkpoint.reached
                      ? '${clock(checkpoint.reachedAt)} · ${elapsed(checkpoint.timeFromPrevious)} · ${checkpoint.distanceFromPreviousKm.toStringAsFixed(2)} km'
                      : 'No GPS sample within 100 m',
                  style: TextStyle(
                    color: _SummaryColors.secondaryTextFor(context),
                    fontSize: 11,
                  ),
                ),
                if (checkpoint.reached && checkpoint.paceMinutesPerKm > 0)
                  Text(
                    '${checkpoint.paceMinutesPerKm.toStringAsFixed(1)} min/km · ${checkpoint.speedKmh.toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                      color: _SummaryColors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _SummaryEmptyEvents extends StatelessWidget {
  const _SummaryEmptyEvents({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: _SummaryColors.secondaryTextFor(context),
        ),
      ),
    );
  }
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

class _NativeSafetyCountdownDialog extends StatefulWidget {
  const _NativeSafetyCountdownDialog({
    required this.event,
    required this.onCancel,
  });

  final NativeHikeSafetyEvent event;
  final Future<void> Function() onCancel;

  @override
  State<_NativeSafetyCountdownDialog> createState() =>
      _NativeSafetyCountdownDialogState();
}

class _NativeSafetyCountdownDialogState
    extends State<_NativeSafetyCountdownDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_secondsRemaining == 0 && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  int get _secondsRemaining {
    final deadline = widget.event.deadlineAt;
    if (deadline == null) return 0;
    final milliseconds = deadline
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / 1000).ceil();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _secondsRemaining;
    final isStillness = widget.event.isProlongedStillness;
    return CupertinoAlertDialog(
      title: Text(
        isStillness ? 'Prolonged Stillness Detected' : 'Possible Fall Detected',
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(
              isStillness
                  ? 'Your phone has remained still longer than your selected rest time.'
                  : 'A possible fall followed by stillness was detected.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'SOS in $seconds seconds',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => unawaited(widget.onCancel()),
          child: const Text('I’M SAFE — CANCEL SOS'),
        ),
      ],
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
        final isProlongedStillness = snapshot.isProlongedStillnessDetection;
        final totalSeconds =
            settings?.fallResponseDuration.inSeconds ?? seconds;
        final progress = totalSeconds <= 0
            ? 0.0
            : 1 - (seconds / totalSeconds).clamp(0, 1);

        return CupertinoAlertDialog(
          title: Text(
            isProlongedStillness
                ? 'Prolonged Stillness Detected'
                : 'Possible Fall Detected',
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                Text(
                  isProlongedStillness
                      ? 'Your location and phone have been still longer than your selected rest time. Cancel below if you are resting safely.'
                      : 'Are you okay? Do you need help? Triple-tap the phone or cancel below to stop SOS.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '${isProlongedStillness ? 'Stillness' : 'Fall'} SOS in $seconds seconds',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 3,
                  color: const Color(0xFFE11D48),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
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

class ActiveHikeHomePage extends StatefulWidget {
  const ActiveHikeHomePage({
    super.key,
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.onEndHike,
    required this.onCheckIn,
    required this.onPinLocation,
    required this.onReportHazard,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
    this.onOpenTeamChat,
    this.onPingTeamMember,
    this.onMapStyleChanged,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final VoidCallback onEndHike;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final VoidCallback onReportHazard;
  final VoidCallback? onOpenTeamChat;
  final Future<TeamHikeSession?> Function(String phoneNumber)? onPingTeamMember;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;
  final ValueChanged<int>? onMapStyleChanged;

  @override
  State<ActiveHikeHomePage> createState() => _ActiveHikeHomePageState();
}

class _ActiveHikeHomePageState extends State<ActiveHikeHomePage> {
  static const _weatherRefreshInterval = Duration(minutes: 5);

  DateTime _now = DateTime.now();
  Timer? _timer;
  Timer? _weatherTimer;
  final ActiveHikeWeatherService _weatherService =
      const ActiveHikeWeatherService();
  final ValueNotifier<_ActiveHikeWeatherViewState> _weatherViewState =
      ValueNotifier(const _ActiveHikeWeatherViewState());
  ActiveHikeWeatherSnapshot? _weatherSnapshot;
  bool _isWeatherLoading = false;
  String? _weatherError;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(_refreshRouteWeather());
    _weatherTimer = Timer.periodic(
      _weatherRefreshInterval,
      (_) => unawaited(_refreshRouteWeather()),
    );
  }

  @override
  void didUpdateWidget(covariant ActiveHikeHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeHike.sessionId != widget.activeHike.sessionId) {
      _weatherSnapshot = null;
      _weatherError = null;
      unawaited(_refreshRouteWeather());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _weatherTimer?.cancel();
    _weatherViewState.dispose();
    super.dispose();
  }

  Future<void> _refreshRouteWeather() async {
    if (!mounted || _isWeatherLoading) {
      return;
    }
    setState(() {
      _isWeatherLoading = true;
      _weatherError = null;
    });
    _publishWeatherViewState();
    try {
      final snapshot = await _weatherService.fetchForHike(widget.activeHike);
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherSnapshot = snapshot;
      });
      _publishWeatherViewState();
    } on ActiveHikeWeatherException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherError = error.message;
      });
      _publishWeatherViewState();
    } finally {
      if (mounted) {
        setState(() {
          _isWeatherLoading = false;
        });
        _publishWeatherViewState();
      }
    }
  }

  void _publishWeatherViewState() {
    _weatherViewState.value = _ActiveHikeWeatherViewState(
      snapshot: _weatherSnapshot,
      isLoading: _isWeatherLoading,
      error: _weatherError,
    );
  }

  void _openRouteWeather() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ActiveHikeWeatherSheet(
        weatherState: _weatherViewState,
        onRetry: () => unawaited(_refreshRouteWeather()),
      ),
    );
  }

  void _openTeamTools() {
    final teamSession = widget.activeHike.teamHikeSession;
    if (teamSession == null || teamSession.id.isEmpty) {
      return;
    }
    final teammates = teamSession.participants
        .where(
          (participant) =>
              !_sameTeamPhone(
                participant.phoneNumber,
                widget.currentPhoneNumber,
              ) &&
              participant.canBePinged,
        )
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Team hike tools',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (widget.onOpenTeamChat != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('Open team chat'),
                  subtitle: const Text('Message everyone in this hike'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onOpenTeamChat!();
                  },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('Report a trail hazard'),
                subtitle: const Text('Include your latest phone location'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  widget.onReportHazard();
                },
              ),
              if (teammates.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'SAFETY PING',
                    style: Theme.of(sheetContext).textTheme.labelSmall
                        ?.copyWith(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                  ),
                ),
                for (final participant in teammates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.waving_hand_outlined),
                    title: Text(participant.buddy.shortName),
                    subtitle: Text(participant.responseLabel),
                    trailing: const Text('Ping'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onPingTeamMember?.call(participant.phoneNumber);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expectedReturn = widget.activeHike.draft.expectedReturnTime;
    final measuredElapsed = _now.difference(widget.activeHike.startedAt);
    final elapsed = measuredElapsed.isNegative
        ? Duration.zero
        : measuredElapsed;
    final elapsedLabel = [
      elapsed.inHours.toString().padLeft(2, '0'),
      elapsed.inMinutes.remainder(60).toString().padLeft(2, '0'),
      elapsed.inSeconds.remainder(60).toString().padLeft(2, '0'),
    ].join(':');
    final returnLabel =
        '${expectedReturn.hour.toString().padLeft(2, '0')}:${expectedReturn.minute.toString().padLeft(2, '0')}';
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        SafeArea(
          top: true,
          bottom: false,
          child: _ActiveHikeTopBar(
            trailName: widget.activeHike.draft.trail.name,
            elapsedLabel: elapsedLabel,
            returnLabel: returnLabel,
            gpsPointCount: widget.activeHike.routePointCount,
            currentWeather: _weatherSnapshot?.current,
            isWeatherLoading: _isWeatherLoading,
            onOpenWeather: _openRouteWeather,
          ),
        ),
        _ActiveHikeSafetyHealthBar(
          activeHike: widget.activeHike,
          snapshot: widget.fallStillnessSnapshot,
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: ActiveTrackingMapView(
              activeHike: widget.activeHike,
              teamHikeSession: widget.activeHike.teamHikeSession,
              weatherSamples: _weatherSnapshot?.samples ?? const [],
              showLegend: false,
              currentPhoneNumber: widget.currentPhoneNumber,
              onStyleChanged: widget.onMapStyleChanged,
            ),
          ),
        ),
        _ActiveHikeBottomBar(
          onEndHike: widget.onEndHike,
          onCheckIn: widget.onCheckIn,
          onPinLocation: widget.onPinLocation,
          onReportHazard: widget.onReportHazard,
          onOpenTeamTools: widget.activeHike.teamHikeSessionId.isEmpty
              ? null
              : _openTeamTools,
          bottomInset: bottomInset,
        ),
      ],
    );
  }
}

class _ActiveHikeSafetyHealthBar extends StatelessWidget {
  const _ActiveHikeSafetyHealthBar({
    required this.activeHike,
    required this.snapshot,
  });

  final ActiveHikeSession activeHike;
  final FallStillnessMonitorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final enabled = activeHike.draft.fallDetectionEnabled;
    final latestAt = activeHike.latestLocation?.capturedAt.toUtc();
    final locationAge = latestAt == null
        ? null
        : DateTime.now().toUtc().difference(latestAt);
    final gpsFresh =
        locationAge != null &&
        !locationAge.isNegative &&
        locationAge <= const Duration(minutes: 2);
    final nativeServiceOwnsDetection =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final sensorLabel = !enabled
        ? 'Safety detection off'
        : nativeServiceOwnsDetection
        ? 'Listening'
        : snapshot.status == FallStillnessMonitorStatus.inactive
        ? 'Safety monitor starting'
        : snapshot.status.label;
    final locationLabel = gpsFresh
        ? 'GPS live'
        : 'GPS limited · motion fallback active';
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: '$sensorLabel. $locationLabel',
      child: Container(
        width: double.infinity,
        color: enabled
            ? colorScheme.primaryContainer.withValues(alpha: 0.72)
            : colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.health_and_safety_rounded : Icons.warning_rounded,
              size: 18,
              color: enabled
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$sensorLabel  •  $locationLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveHikeTopBar extends StatelessWidget {
  const _ActiveHikeTopBar({
    required this.trailName,
    required this.elapsedLabel,
    required this.returnLabel,
    required this.gpsPointCount,
    required this.currentWeather,
    required this.isWeatherLoading,
    required this.onOpenWeather,
  });

  final String trailName;
  final String elapsedLabel;
  final String returnLabel;
  final int gpsPointCount;
  final ActiveHikeWeatherSample? currentWeather;
  final bool isWeatherLoading;
  final VoidCallback onOpenWeather;

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
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34A853),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onOpenWeather,
                  tooltip: 'View weather forecast',
                  icon: isWeatherLoading && currentWeather == null
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _activeWeatherIconForCode(
                            currentWeather?.weatherCode,
                          ),
                        ),
                  color: Theme.of(context).colorScheme.primary,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ElapsedTimeDisplay(elapsedLabel: elapsedLabel),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MetricChip(
                      icon: Icons.schedule_rounded,
                      label: 'Est. return $returnLabel',
                    ),
                    const SizedBox(height: 6),
                    _MetricChip(
                      icon: Icons.gps_fixed_rounded,
                      label: '$gpsPointCount pts',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ElapsedTimeDisplay extends StatelessWidget {
  const _ElapsedTimeDisplay({required this.elapsedLabel});

  final String elapsedLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ELAPSED TIME',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 7),
            Text(
              elapsedLabel,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActiveHikeWeatherSheet extends StatelessWidget {
  const _ActiveHikeWeatherSheet({
    required this.weatherState,
    required this.onRetry,
  });

  final ValueListenable<_ActiveHikeWeatherViewState> weatherState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ValueListenableBuilder<_ActiveHikeWeatherViewState>(
        valueListenable: weatherState,
        builder: (context, state, _) {
          final snapshot = state.snapshot;
          final samples =
              snapshot?.samples ?? const <ActiveHikeWeatherSample>[];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Weather along your hike',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot == null
                      ? 'Checking your location and the trail ahead.'
                      : 'Updated ${_activeWeatherTimeLabel(snapshot.fetchedAt)} · refreshes every 5 minutes',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (samples.isEmpty && state.isLoading)
                  const HikerCircleLoadingView(
                    message: 'Checking hike weather…',
                    detail: 'Loading conditions along the trail ahead.',
                    compact: true,
                    padding: EdgeInsets.symmetric(vertical: 16),
                  )
                else if (samples.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          'Weather is temporarily unavailable.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < samples.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(height: 10),
                            _ActiveHikeWeatherCard(sample: samples[index]),
                          ],
                          if (state.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Latest refresh failed. Showing the previous update.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActiveHikeWeatherViewState {
  const _ActiveHikeWeatherViewState({
    this.snapshot,
    this.isLoading = false,
    this.error,
  });

  final ActiveHikeWeatherSnapshot? snapshot;
  final bool isLoading;
  final String? error;
}

class _ActiveHikeWeatherCard extends StatelessWidget {
  const _ActiveHikeWeatherCard({required this.sample});

  final ActiveHikeWeatherSample sample;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _activeWeatherIconForCode(sample.weatherCode),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    sample.summary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Feels ${sample.apparentTemperatureCelsius.round()}° · '
                    '${sample.humidityPercent}% humidity · '
                    '${sample.windSpeedKph.toStringAsFixed(1)} km/h wind',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${sample.temperatureCelsius.round()}°',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _activeWeatherIconForCode(int? code) {
  if (code == null) {
    return Icons.cloud_sync_rounded;
  }
  if (code == 0 || code == 1) {
    return Icons.wb_sunny_rounded;
  }
  if (code == 2 || code == 3) {
    return Icons.cloud_rounded;
  }
  if (code == 45 || code == 48) {
    return Icons.foggy;
  }
  if (code >= 95) {
    return Icons.thunderstorm_rounded;
  }
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return Icons.water_drop_rounded;
  }
  if ((code >= 71 && code <= 77) || code >= 85) {
    return Icons.ac_unit_rounded;
  }
  return Icons.cloud_rounded;
}

String _activeWeatherTimeLabel(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

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
    required this.onReportHazard,
    this.onOpenTeamTools,
    this.bottomInset = 0,
  });

  final VoidCallback onEndHike;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final VoidCallback onReportHazard;
  final VoidCallback? onOpenTeamTools;
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
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReportHazard,
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Report Hazard'),
                  ),
                ),
                if (onOpenTeamTools != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenTeamTools,
                      icon: const Icon(Icons.groups_2_outlined, size: 18),
                      label: const Text('Team Tools'),
                    ),
                  ),
                ],
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
    final isCreator = _sameTeamPhone(hike.creatorPhone, phoneNumber);
    final canStart = isCreator && trail != null && !hike.isLocalPendingSync;
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.2),
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
                        style: Theme.of(context).textTheme.titleMedium
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
              label: 'Estimated Return',
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
              value: [
                hike.area,
                hike.state,
                hike.country,
              ].where((part) => part.trim().isNotEmpty).join(', '),
            ),
            _DetailRow(
              icon: Icons.group_rounded,
              label: 'Participants',
              value: '${hike.participantCount}',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF34A853).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isCreator
                        ? Icons.play_circle_outline_rounded
                        : Icons.schedule_rounded,
                    color: const Color(0xFF34A853),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isCreator
                          ? hike.hikeType == HikeType.team.name ||
                                    hike.participantCount > 1
                                ? 'Start team readiness when everyone is prepared. Live tracking begins after the readiness check.'
                                : 'You created this hike. Start it here when you reach the trailhead.'
                          : 'The hike host starts the session. You can review the trail and get directions while you wait.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                    onPressed: canStart
                        ? () => Navigator.of(context).pop('start')
                        : null,
                    icon: Icon(
                      canStart
                          ? Icons.play_arrow_rounded
                          : Icons.hourglass_top_rounded,
                      size: 18,
                    ),
                    label: Text(
                      hike.isLocalPendingSync
                          ? 'Waiting for sync'
                          : isCreator
                          ? hike.participantCount > 1
                                ? 'Start Team Readiness'
                                : 'Start Hike'
                          : 'Waiting for host',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop('directions'),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Directions to trailhead'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
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
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

double? _finiteDoubleValue(Object? value) {
  return value is num && value.isFinite ? value.toDouble() : null;
}

int? _boundedIntValue(
  Object? value, {
  required int minimum,
  required int maximum,
}) {
  if (value is! num || !value.isFinite) {
    return null;
  }
  final asDouble = value.toDouble();
  if (asDouble < minimum || asDouble > maximum) {
    return null;
  }
  return asDouble.toInt();
}

class _PendingFcmOpen {
  const _PendingFcmOpen({
    required this.key,
    required this.deepLink,
    required this.title,
    required this.body,
  });

  final String key;
  final String? deepLink;
  final String? title;
  final String? body;
}
