import 'dart:async';
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
import '../../me/Data/live_location_sharing_service.dart';
import '../../me/View/me_page.dart';
import '../../navigation/View/hiker_bottom_nav_bar.dart';
import '../../core/services/device_notification_log_service.dart';
import '../../core/services/hiker_ble_service.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/services/network_reachability_service.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_preview_map.dart';
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
import '../Data/active_hike_weather_service.dart';
import '../Data/active_hike_live_status_service.dart';
import '../Model/hike_session_models.dart';
import 'active_tracking_map_view.dart';
import '../ModelView/fall_stillness_monitor.dart';
import 'active_hike_map_page.dart';
import 'home_dashboard_page.dart';
import 'first_aid_guide_page.dart';
import 'start_hike_wizard_page.dart';

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
  late final FallStillnessMonitor fallStillnessMonitor;
  final SosDeviceAlertService _sosDeviceAlertService =
      const SosDeviceAlertService();
  final ActiveHikeLiveStatusService _activeHikeLiveStatusService =
      const ActiveHikeLiveStatusService();
  final HikerBleService _bleService = const HikerBleService();
  StreamSubscription<List<UpcomingHike>>? _myUpcomingHikesSubscription;
  StreamSubscription<List<Trail>>? _trailsSubscription;
  StreamSubscription<HikerBleEvent>? _bleEventSubscription;
  StreamSubscription<NetworkReachabilitySnapshot>?
  _networkReachabilitySubscription;
  NetworkReachabilitySnapshot _networkReachabilitySnapshot =
      const NetworkReachabilitySnapshot(
        state: NetworkReachabilityState.checking,
      );
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
  Timer? activeHikeMonitoringHeartbeatTimer;
  StreamSubscription<String>? fcmTokenSubscription;
  StreamSubscription<RemoteMessage>? fcmOpenSubscription;
  StreamSubscription<RemoteMessage>? fcmForegroundSubscription;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? activeHikeMonitoringSessionId;
  String _fcmToken = '';
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
  Future<void>? _activeHikeRestoreFuture;
  Future<void> _activeHikePersistenceQueue = Future<void>.value();
  bool isRestoringActiveHike = true;
  int selectedTabIndex = 0;
  int manualSosRequestId = 0;
  int immediateSosRequestId = 0;
  SosAlertMode? immediateSosRequestMode;
  String? _lastHandledDeepLink;
  DateTime? _lastHandledDeepLinkAt;
  String? _lastHandledPairedSosKey;
  String? _lastHandledNearbySosKey;
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
    _activeHikeRestoreFuture = _restoreActiveHikeSession();
    _deepLinkChannel.setMethodCallHandler(_handleDeepLinkMethodCall);
    unawaited(LocationSnapshotService.instance.start());
    unawaited(_refreshBatteryLevel());
    batteryLevelTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshBatteryLevel());
    });
    unawaited(loadLiveData());
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

  Future<void> _initializeFirebaseMessaging() async {
    if (!widget.firebaseBootstrapResult.isAvailable) {
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );
      fcmTokenSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_registerFcmToken(token));
      });
      fcmOpenSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleFcmOpen,
      );
      fcmForegroundSubscription = FirebaseMessaging.onMessage.listen(
        _showForegroundNotification,
      );

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _handleFcmOpenFromLocal,
      );

      try {
        final token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _registerFcmToken(token);
        }
      } catch (error) {
        debugPrint('FCM token is not available yet: $error');
      }
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        await _handleFcmOpen(initialMessage);
      }
    } catch (error) {
      debugPrint('Unable to initialize Firebase Messaging: $error');
    }
  }

  Future<void> _initializeBleBridge() async {
    _bleEventSubscription?.cancel();
    _bleEventSubscription = _bleService.events.listen(
      _handleBleEvent,
      onError: (_) {},
    );
    await _bleService.startSosButtonMonitor();
  }

  void _handleBleEvent(HikerBleEvent event) {
    switch (event) {
      case HikerBlePairedButtonSetupEvent():
        break;
      case HikerBleSosButtonEvent():
        requestImmediateSos(SosAlertMode.manual);
      case HikerBlePairedSosButtonEvent():
        _handlePairedSosButtonEvent(event);
      case HikerBleNearbySosButtonEvent():
        _handleNearbySosButtonEvent(
          deviceId: event.deviceId,
          counter: event.counter,
          receivedAt: event.receivedAt,
          rssi: event.rssi,
        );
      case HikerBleNearbySosLocationEvent():
        _handleNearbySosLocationEvent(event);
      case HikerBleSosHelpEvent():
        _showBleSosHelpPopupForLocation(
          latitude: event.location.latitude,
          longitude: event.location.longitude,
          accuracyMeters: event.location.accuracyMeters,
          sentAt: event.location.capturedAt,
          rssi: event.rssi,
        );
      case HikerBleTeamLocationEvent():
        _handleBleTeamLocation(event);
      case HikerBleStatusEvent():
        break;
    }
  }

  void _handleNetworkReachabilityChanged(NetworkReachabilitySnapshot snapshot) {
    final wasOnline = _networkReachabilitySnapshot.isOnline;
    _networkReachabilitySnapshot = snapshot;
    if (!wasOnline && snapshot.isOnline) {
      unawaited(
        sosAlertRepository.flushQueuedAlerts(
          session: widget.session,
          contacts: const [],
        ),
      );
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

  Future<void> _handleFcmOpen(RemoteMessage message) async {
    await DeviceNotificationLogService.recordFcmMessage(
      message,
      ownerPhoneNumber: widget.session.phoneNumber,
      opened: true,
    );
    final deepLink = message.data['deepLink'];
    if (deepLink is String && deepLink.isNotEmpty) {
      await _handleDeepLink(deepLink);
    }
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
    final deepLink = message.data['deepLink'] as String?;

    if (type == 'active_hike_monitoring_stopped') return;

    if (type != null &&
        type.startsWith('team_hike_') &&
        deepLink != null &&
        deepLink.isNotEmpty) {
      unawaited(_handleDeepLink(deepLink));
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'hiker_circle_foreground',
      'HikerCircle notifications',
      channelDescription: 'In-app notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);
    _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: deepLink,
      notificationDetails: details,
    );
  }

  void _handleFcmOpenFromLocal(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      unawaited(_handleDeepLink(payload));
    }
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
    if (uri.host == 'sos' && uri.path == '/help') {
      _showBleSosHelpPopup(uri);
      return;
    }
    if (uri.host == 'sos' && uri.path == '/instant') {
      _debugPrintPhysicalSosPackage(uri);
      requestImmediateSos(SosAlertMode.manual);
      return;
    }
    if (uri.host == 'sos' && uri.path == '/paired') {
      _handlePairedSosButtonEvent(
        HikerBlePairedSosButtonEvent(
          deviceId: uri.queryParameters['deviceId'] ?? '',
          counter: int.tryParse(uri.queryParameters['counter'] ?? ''),
          mode: 1,
          rssi: int.tryParse(uri.queryParameters['rssi'] ?? ''),
          receivedAt: _dateFromDeepLink(uri.queryParameters['receivedAt']),
        ),
      );
      return;
    }
    if (uri.host == 'sos' && uri.path == '/nearby-button') {
      _handleNearbySosButtonEvent(
        deviceId: uri.queryParameters['deviceId'] ?? '',
        counter: int.tryParse(uri.queryParameters['counter'] ?? ''),
        receivedAt: _dateFromDeepLink(uri.queryParameters['receivedAt']),
        rssi: int.tryParse(uri.queryParameters['rssi'] ?? ''),
      );
      return;
    }
    if (uri.host == 'sos' && uri.path == '/nearby-button-location') {
      final latitude = double.tryParse(uri.queryParameters['latitude'] ?? '');
      final longitude = double.tryParse(uri.queryParameters['longitude'] ?? '');
      if (latitude == null || longitude == null) return;
      _handleNearbySosLocationEvent(
        HikerBleNearbySosLocationEvent(
          deviceId: uri.queryParameters['deviceId'] ?? '',
          counter: int.tryParse(uri.queryParameters['counter'] ?? ''),
          rssi: int.tryParse(uri.queryParameters['rssi'] ?? ''),
          receivedAt: _dateFromDeepLink(uri.queryParameters['receivedAt']),
          location: SosTriggerLocation(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: double.tryParse(
              uri.queryParameters['accuracy'] ?? '',
            ),
            capturedAt: _dateFromDeepLink(uri.queryParameters['receivedAt']),
          ),
        ),
      );
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
    if (uri.host == 'upcoming-hike' && uri.path == '/view') {
      final hikeId = uri.queryParameters['upcomingHikeId'] ?? '';
      if (hikeId.isNotEmpty) {
        unawaited(_openUpcomingHikeFromDeepLink(hikeId));
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

  void _debugPrintPhysicalSosPackage(Uri uri) {
    if (uri.queryParameters['source'] != 'ble_button') {
      return;
    }
    debugPrint(
      [
        'HikerCircle physical SOS BLE package accepted',
        'broadcastId: ${uri.queryParameters['broadcastId'] ?? 'none'}',
        'rssi: ${uri.queryParameters['rssi'] ?? 'unknown'}',
        'deviceAddress: ${uri.queryParameters['deviceAddress'] ?? 'unknown'}',
        'manufacturerData: ${uri.queryParameters['manufacturerData'] ?? 'none'}',
        'serviceUuids: ${uri.queryParameters['serviceUuids'] ?? 'none'}',
        'receivedAt: ${uri.queryParameters['receivedAt'] ?? 'unknown'}',
      ].join('\n'),
    );
  }

  Future<void> _openUpcomingHikeFromDeepLink(String hikeId) async {
    if (!mounted) {
      return;
    }
    var loadingVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading upcoming hike...'),
                ],
              ),
            ),
          ),
        ),
      ).whenComplete(() => loadingVisible = false),
    );
    await Future<void>.delayed(Duration.zero);

    final results = await Future.wait<Object?>([
      hikerCircleRepository.loadUpcomingHikeById(hikeId),
      LocationSnapshotService.instance.refresh(),
    ]);
    if (!mounted) {
      return;
    }
    if (loadingVisible && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    final hike = results[0] as UpcomingHike?;
    final location = results[1] as SosTriggerLocation?;
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
    await showUpcomingHikePopup(
      context,
      hike: hike,
      session: widget.session,
      repository: hikerCircleRepository,
      userLat: location?.latitude,
      userLng: location?.longitude,
      onJoin: () => unawaited(loadLiveData()),
    );
  }

  Future<void> _openGroupChatFromDeepLink(String chatId) async {
    if (!mounted) {
      return;
    }
    var loadingVisible = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Opening group chat...'),
                ],
              ),
            ),
          ),
        ),
      ).whenComplete(() => loadingVisible = false),
    );
    await Future<void>.delayed(Duration.zero);
    final chat = await hikerCircleRepository.loadGroupChatById(chatId);
    if (!mounted) {
      return;
    }
    if (loadingVisible && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GroupChatDetailPage(
          chat: chat,
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
      if (widget.session.isAdmin) {
        try {
          await hikerCircleRepository.deleteLegacyFirebaseDummyData(
            session: widget.session,
          );
        } catch (_) {
          // Cleanup should not block normal trail loading.
        }
      }
      _trailsSubscription?.cancel();
      _trailsSubscription = hikerCircleRepository.watchTrails().listen(
        (liveTrails) {
          if (!mounted) return;
          setState(() {
            trails = liveTrails;
            isLoadingLiveData = false;
          });
        },
        onError: (_) {
          if (mounted) setState(() => isLoadingLiveData = false);
        },
      );
      _myUpcomingHikesSubscription?.cancel();
      _myUpcomingHikesSubscription = hikerCircleRepository
          .watchMyUpcomingHikes(widget.session.phoneNumber)
          .listen((hikes) {
            if (!mounted) return;
            setState(() => myUpcomingHikes = hikes);
          });
      unawaited(hikerCircleRepository.ensureAchievementSeeds());
    } catch (_) {
      if (mounted) {
        setState(() => isLoadingLiveData = false);
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

    if (!mounted || startedHike == null) return;
    var hikeToStart = startedHike;
    if (hikeToStart.draft.hikeType == HikeType.team) {
      final teamSession = await _coordinateTeamHikeStart(hikeToStart.draft);
      if (teamSession == null || !mounted) {
        return;
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
        teamHikeSession: hikeToStart.teamHikeSession,
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
    await _activeHikePersistenceQueue;
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

    _navigatingTeamSessionId = teamSession.id;
    try {
      return await Navigator.of(context).push<TeamHikeSession>(
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
    final location = await LocationSnapshotService.instance.refresh();
    final checkedInAt = DateTime.now();
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
      queuedUpdates: currentHike.queuedUpdates + 1,
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
        final updatedHike = currentHike.copyWith(teamHikeSession: teamSession);
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

  Future<void> _applyActiveHikeCheckIn(ActiveHikeSession hike) async {
    final updatedHike = await checkInActiveHike(hike);
    if (!mounted || activeHike?.sessionId != hike.sessionId) {
      return;
    }
    setState(() {
      activeHike = updatedHike;
    });
    _syncActiveHikeServices(updatedHike, forceLiveStatus: true);
  }

  Future<void> _applyActiveHikePin(ActiveHikeSession hike) async {
    final result = await pinCurrentLocation(hike);
    if (!mounted || activeHike?.sessionId != hike.sessionId) {
      return;
    }
    setState(() {
      activeHike = result.hike;
    });
    _syncActiveHikeServices(result.hike, forceLiveStatus: true);
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
      final hikeType = hike.participantCount > 1
          ? HikeType.team
          : HikeType.solo;
      final draft = HikeSessionDraft.fromTrail(trail).copyWith(
        hikeType: hikeType,
        departureTime: hike.departureTime,
        expectedReturnTime: hike.expectedReturnTime,
        teamBuddies: hike.participantPhones
            .where(
              (phone) => !_sameTeamPhone(phone, widget.session.phoneNumber),
            )
            .map(
              (phone) =>
                  TeamHikeBuddy(name: phone, handle: '', phoneNumber: phone),
            )
            .toList(),
      );
      await _startUpcomingHikeNow(hike: hike, draft: draft);
    }
  }

  Future<void> _startUpcomingHikeNow({
    required UpcomingHike hike,
    required HikeSessionDraft draft,
  }) async {
    var hikeToStart = ActiveHikeSession.fromDraft(draft);
    if (draft.hikeType == HikeType.team && draft.teamBuddies.isNotEmpty) {
      final teamSession = await _coordinateTeamHikeStart(draft);
      if (teamSession == null || !mounted) return;
      hikeToStart = hikeToStart.copyWith(
        draft: _applyTeamSafetySettings(draft, teamSession),
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
        draft: hikeToStart.draft,
        teamHikeSessionId: hikeToStart.teamHikeSessionId,
        teamHikeSession: hikeToStart.teamHikeSession,
        sourceUpcomingHikeId: hike.id,
      );
      final batteryLevel = await _readBatteryLevel(fallback: 100);
      liveHike = liveHike.copyWith(
        batteryLevel: batteryLevel,
        batteryStartedLevel: batteryLevel,
      );
    } on HikerCircleFirebaseRepositoryException catch (_) {
      // Proceed in offline mode
    }
    if (!mounted) return;
    setState(() {
      activeHike = liveHike;
      selectedTabIndex = 0;
    });
    _syncActiveHikeServices(liveHike, forceLiveStatus: true);
    await _activeHikePersistenceQueue;
    tabController.animateTo(0);
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
            (safety['sensorSensitivity'] as num?)?.toDouble() ??
            draft.fallDetectionSettings.sensorSensitivity,
        fallResponseDuration: Duration(
          seconds:
              (safety['fallResponseDurationSeconds'] as num?)?.toInt() ??
              (safety['responseCountdownSeconds'] as num?)?.toInt() ??
              draft.fallDetectionSettings.fallResponseDuration.inSeconds,
        ),
        longestRestDuration: Duration(
          seconds:
              (safety['longestRestDurationSeconds'] as num?)?.toInt() ??
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
              content: Text('This trail is not available right now.'),
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
              (safety['sensorSensitivity'] as num?)?.toDouble() ??
              draft.fallDetectionSettings.sensorSensitivity,
          fallResponseDuration: Duration(
            seconds:
                (safety['fallResponseDurationSeconds'] as num?)?.toInt() ??
                (safety['responseCountdownSeconds'] as num?)?.toInt() ??
                draft.fallDetectionSettings.fallResponseDuration.inSeconds,
          ),
          longestRestDuration: Duration(
            seconds:
                (safety['longestRestDurationSeconds'] as num?)?.toInt() ??
                draft.fallDetectionSettings.longestRestDuration.inSeconds,
          ),
        ),
      );
      final preparedHike = ActiveHikeSession.fromDraft(
        preparedDraft,
        teamHikeSessionId: launchedSession.id,
        teamHikeSession: launchedSession,
      );
      var liveHike = await hikerCircleRepository.createActiveHikeSession(
        session: widget.session,
        draft: preparedHike.draft,
        teamHikeSessionId: launchedSession.id,
        teamHikeSession: launchedSession,
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
        final updatedHike = currentHike.copyWith(teamHikeSession: teamSession);
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

  void _showBleSosHelpPopup(Uri uri) {
    final latitude = double.tryParse(uri.queryParameters['lat'] ?? '');
    final longitude = double.tryParse(uri.queryParameters['lng'] ?? '');
    if (!mounted || latitude == null || longitude == null) {
      return;
    }
    final accuracy = double.tryParse(uri.queryParameters['accuracy'] ?? '');
    final rssi = int.tryParse(uri.queryParameters['rssi'] ?? '');
    final sentAtMillis = int.tryParse(uri.queryParameters['sentAt'] ?? '');
    final sentAt = sentAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sentAtMillis, isUtc: true);
    _showBleSosHelpPopupForLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      sentAt: sentAt,
      rssi: rssi,
    );
  }

  void _showBleSosHelpPopupForLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? sentAt,
    int? rssi,
  }) {
    if (!mounted) {
      return;
    }
    final mapUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    showDialog<void>(
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
                  if (accuracyMeters != null)
                    Text('GPS accuracy: ${accuracyMeters.round()} m'),
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
                unawaited(launchUrl(mapUri));
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
    requestImmediateSos(SosAlertMode.manual);
    final eventId = event.counter;
    if (eventId != null) {
      unawaited(_sendPairedSosLocation(event.deviceId, eventId));
    }
  }

  Future<void> _sendPairedSosLocation(String deviceId, int eventId) async {
    try {
      final location =
          LocationSnapshotService.instance.latestLocation ??
          await LocationSnapshotService.instance.refresh();
      if (location == null) return;
      await _bleService.sendPairedSosLocation(
        deviceId: deviceId,
        eventId: eventId,
        location: location,
      );
    } catch (error) {
      debugPrint('Unable to return SOS location to button: $error');
    }
  }

  void _handleNearbySosButtonEvent({
    required String deviceId,
    int? counter,
    required DateTime receivedAt,
    int? rssi,
  }) {
    final key =
        '$deviceId:${counter ?? receivedAt.millisecondsSinceEpoch ~/ 1000}';
    if (_lastHandledNearbySosKey == key) return;
    _lastHandledNearbySosKey = key;
    _showNearbySosButtonPopup(
      deviceId: deviceId,
      receivedAt: receivedAt,
      rssi: rssi,
    );
  }

  void _handleNearbySosLocationEvent(HikerBleNearbySosLocationEvent event) {
    final key =
        '${event.deviceId}:${event.counter ?? event.receivedAt.millisecondsSinceEpoch ~/ 1000}:location';
    if (_lastHandledNearbySosKey == key) return;
    _lastHandledNearbySosKey = key;
    _showNearbySosButtonPopup(
      deviceId: event.deviceId,
      receivedAt: event.receivedAt,
      rssi: event.rssi,
      location: event.location,
    );
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

  void _showNearbySosButtonPopup({
    required String deviceId,
    required DateTime receivedAt,
    int? rssi,
    SosTriggerLocation? location,
  }) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: Color(0xFFFF9500)),
        title: const Text('Nearby SOS button pressed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A nearby paired HikerCircle button sent an unverified proximity signal. It is not your SOS and no alert has been sent from this phone.',
              ),
              const SizedBox(height: 12),
              if (location == null)
                const Text(
                  'Precise location has not been relayed yet. Keep Bluetooth enabled to receive it if the owner phone is nearby.',
                )
              else ...[
                SizedBox(
                  height: 280,
                  child: _BleSosHelpMap(
                    targetLatitude: location.latitude,
                    targetLongitude: location.longitude,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Location: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                ),
                if (location.accuracyMeters != null)
                  Text(
                    'Reported GPS accuracy: ${location.accuracyMeters!.round()} m',
                  ),
              ],
              if (rssi != null)
                Text(
                  'BLE signal: $rssi dBm',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text('Received: ${_formatBleSosHelpTime(receivedAt)}'),
              if (deviceId.isNotEmpty)
                Text(
                  'Button ID: ${deviceId.length > 4 ? deviceId.substring(deviceId.length - 4) : deviceId}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FirstAidGuidePage(),
                ),
              );
            },
            child: const Text('First-aid guide'),
          ),
          FilledButton(
            onPressed: () => unawaited(launchUrl(Uri.parse('tel:112'))),
            child: const Text('Call emergency services'),
          ),
        ],
      ),
    );
  }

  DateTime _dateFromDeepLink(String? value) {
    final millis = int.tryParse(value ?? '');
    return millis == null
        ? DateTime.now().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  String _formatBleSosHelpTime(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  void _signOutAndClearActiveHike() {
    _persistActiveHikeSnapshot(null);
    unawaited(
      _activeHikePersistenceQueue.then((_) async {
        if (mounted) {
          try {
            await hikerCircleRepository.removeFcmToken(session: widget.session);
          } catch (_) {}
          widget.onSignOut();
        }
      }),
    );
  }

  int _lastMapStyleIndex = 0;

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
    await _activeHikePersistenceQueue;
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
            activeHike: hikeToEnd,
            initialMapStyleIndex: _lastMapStyleIndex,
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
        'manualSosRequestId': manualSosRequestId,
        'immediateSosRequestId': immediateSosRequestId,
        'immediateSosRequestMode': immediateSosRequestMode?.name,
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
      _pauseActiveHikeLocationRecording();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_bleService.startSosButtonMonitor());
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
    try {
      return LocationSnapshotService.instance.latestLocation ??
          await LocationSnapshotService.instance.refresh();
    } catch (_) {
      return null;
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
    _persistActiveHikeSnapshot(hike);
    _syncFallStillnessMonitor(hike);
    _syncTeamHikeSessionWatch(hike);
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
              lifecycleState: 'active',
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
        .listen((teamSession) {
          if (!mounted || teamSession == null) {
            return;
          }
          final currentHike = activeHike;
          if (currentHike == null ||
              currentHike.teamHikeSessionId != teamSession.id) {
            return;
          }
          final updatedHike = currentHike.copyWith(
            teamHikeSession: teamSession,
          );
          setState(() {
            activeHike = updatedHike;
          });
          _persistActiveHikeSnapshot(updatedHike);
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
      _persistActiveHikeSnapshot(updatedHike);
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
    final stationaryTriggerDuration =
        hike.draft.fallDetectionSettings.longestRestDuration;
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
    _syncBleTeamLocation(hike, location);
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
        final updatedHike = currentHike.copyWith(teamHikeSession: teamSession);
        setState(() {
          activeHike = updatedHike;
        });
        _persistActiveHikeSnapshot(updatedHike);
      } catch (_) {
        // Team position sync should never stop the local tracking loop.
      }
    }());
  }

  void _syncBleTeamLocation(
    ActiveHikeSession? hike, [
    SosTriggerLocation? location,
  ]) {
    if (hike == null || hike.teamHikeSessionId.isEmpty) {
      unawaited(_bleService.stopTeamLocationExchange());
      return;
    }

    final locationForBle =
        location ?? _triggerLocationFromCoordinate(hike.latestLocation);
    if (locationForBle == null) {
      return;
    }

    unawaited(
      _bleService.updateTeamLocation(
        teamHikeSessionId: hike.teamHikeSessionId,
        phoneNumber: widget.session.phoneNumber,
        location: locationForBle,
      ),
    );
  }

  SosTriggerLocation? _triggerLocationFromCoordinate(
    HikeCoordinate? coordinate,
  ) {
    if (coordinate == null) {
      return null;
    }
    return SosTriggerLocation(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      accuracyMeters: coordinate.accuracyMeters,
      capturedAt: coordinate.capturedAt,
    );
  }

  void _handleBleTeamLocation(HikerBleTeamLocationEvent event) {
    final hike = activeHike;
    final teamSession = hike?.teamHikeSession;
    if (hike == null ||
        teamSession == null ||
        hike.teamHikeSessionId.isEmpty ||
        event.teamSessionHash != hikerBleHash(hike.teamHikeSessionId) ||
        event.phoneNumberHash ==
            hikerBlePhoneHash(widget.session.phoneNumber)) {
      return;
    }

    final now = DateTime.now().toUtc();
    final coordinate = HikeCoordinate.fromTriggerLocation(event.location);
    var matchedParticipant = false;
    var participants = teamSession.participants.map((participant) {
      if (hikerBlePhoneHash(participant.phoneNumber) != event.phoneNumberHash) {
        return participant;
      }
      matchedParticipant = true;
      return participant.copyWith(
        status: TeamHikeParticipantStatus.active,
        latestLocation: coordinate,
        updatedAt: now,
      );
    }).toList();

    if (!matchedParticipant) {
      return;
    }

    final newlyIsolated = <TeamHikeParticipant>[];
    participants = _participantsWithLocalSeparationState(
      participants: participants,
      now: now,
      newlyIsolated: newlyIsolated,
    );
    final updatedTeamSession = teamSession.copyWith(
      phase: TeamHikePhase.active,
      participants: participants,
      updatedAt: now,
    );
    final updatedHike = hike.copyWith(teamHikeSession: updatedTeamSession);

    setState(() {
      activeHike = updatedHike;
    });
    _persistActiveHikeSnapshot(updatedHike);

    if (newlyIsolated.isNotEmpty) {
      final name = newlyIsolated.first.buddy.shortName;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '$name may be separated from the team. BLE location is still updating locally.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  List<TeamHikeParticipant> _participantsWithLocalSeparationState({
    required List<TeamHikeParticipant> participants,
    required DateTime now,
    required List<TeamHikeParticipant> newlyIsolated,
  }) {
    return participants.map((participant) {
      final location = participant.latestLocation;
      if (location == null || participants.length < 2) {
        return participant;
      }
      final nearestDistance = participants
          .where(
            (other) =>
                !_sameTeamPhone(other.phoneNumber, participant.phoneNumber) &&
                other.latestLocation != null,
          )
          .map((other) => location.distanceTo(other.latestLocation!))
          .fold<double>(
            double.infinity,
            (nearest, distance) => distance < nearest ? distance : nearest,
          );
      final threshold =
          (participant.safetySettings['separationDistanceMeters'] as num?)
              ?.toDouble() ??
          150;
      final graceSeconds =
          (participant.safetySettings['isolationGraceSeconds'] as num?)
              ?.toInt() ??
          180;
      if (!nearestDistance.isFinite || nearestDistance <= threshold) {
        return participant.copyWith(
          clearIsolatedSince: true,
          separationAlertActive: false,
        );
      }
      final isolatedSince = participant.isolatedSince ?? now;
      final shouldAlert =
          !participant.separationAlertActive &&
          now.difference(isolatedSince).inSeconds >= graceSeconds;
      final next = participant.copyWith(
        isolatedSince: isolatedSince,
        separationAlertActive: participant.separationAlertActive || shouldAlert,
      );
      if (shouldAlert) {
        newlyIsolated.add(next);
      }
      return next;
    }).toList();
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
    unawaited(_bleService.stopTeamLocationExchange());
    unawaited(NetworkReachabilityService.instance.stop());

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
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Restoring your active hike...'),
                    ],
                  ),
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
  const _BleNearbyProximityMap({this.rssi});

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
                  (profile?['gender'] as String? ?? '').toLowerCase() ==
                  'female',
            ),
          ),
        );
    if (safetySettings == null || !mounted) {
      return;
    }
    setState(() {
      _isMarkingReady = true;
    });
    try {
      await widget.repository.markTeamParticipantReady(
        session: widget.session,
        teamHikeSessionId: teamSession.id,
        safetySettings: safetySettings,
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
    final isHost = _sameTeamPhone(
      teamSession.hostPhoneNumber,
      widget.session.phoneNumber,
    );
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
    if (!isHost) {
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
    final activeSession = await widget.repository.activateTeamHikeSession(
      session: widget.session,
      teamHikeSessionId: teamSession.id,
    );
    if (route != null && route.isCurrent) {
      navigator.pop(activeSession);
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

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await widget.repository.loadTeamSafetyPreferences(
      session: widget.session,
    );
    if (!mounted) return;
    if (prefs != null) {
      setState(() {
        if (prefs['sensorSensitivity'] is num) {
          _sensitivity = (prefs['sensorSensitivity'] as num).toDouble();
          _sensitivitySelected = true;
        }
        if (prefs['fallResponseDurationSeconds'] is num) {
          final seconds = (prefs['fallResponseDurationSeconds'] as num).toInt();
          _fallResponseDuration = Duration(seconds: seconds);
          _fallResponseSelected = true;
        }
        if (prefs['longestRestDurationSeconds'] is num) {
          final seconds = (prefs['longestRestDurationSeconds'] as num).toInt();
          _longestRestDuration = Duration(seconds: seconds);
          _longestRestSelected = true;
        }
        if (prefs['enhancedIsolationProtection'] is bool) {
          _enhancedIsolationProtection =
              prefs['enhancedIsolationProtection'] as bool;
        }
        _isLoadingPrefs = false;
      });
    } else {
      setState(() {
        _isLoadingPrefs = false;
      });
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
    final prefs = <String, dynamic>{
      'liveLocationSharing': true,
      'pathDeviationAlerts': true,
      'teammateSeparationAlerts': true,
      'fallDetectionEnabled': true,
      'sensorSensitivity': _sensitivity,
      'responseCountdownSeconds': _fallResponseDuration.inSeconds,
      'fallResponseDurationSeconds': _fallResponseDuration.inSeconds,
      'longestRestDurationSeconds': _longestRestDuration.inSeconds,
      'enhancedIsolationProtection': _enhancedIsolationProtection,
      'separationDistanceMeters': _enhancedIsolationProtection ? 100 : 150,
      'isolationGraceSeconds': _enhancedIsolationProtection ? 90 : 180,
      'automaticTeamCheckPing': true,
    };
    await widget.repository.saveTeamSafetyPreferences(
      session: widget.session,
      preferences: prefs,
    );
    if (!mounted) return;
    Navigator.of(context).pop(prefs);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _SafetyTheme.of(context);
    final theme = Theme.of(context);
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
                      'Complete these settings before sending Ready. Required team monitoring cannot be disabled during this hike.',
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
                    initialValue: _fallResponseDuration,
                    decoration: const InputDecoration(
                      labelText: 'Longest response time after a fall',
                      prefixIcon: Icon(Icons.personal_injury_rounded),
                    ),
                    items: [
                      for (final duration in _fallResponseOptions)
                        DropdownMenuItem(
                          value: duration,
                          child: Text(
                            duration.inSeconds < 60
                                ? '${duration.inSeconds} seconds'
                                : '${duration.inMinutes} minute${duration.inMinutes == 1 ? '' : 's'}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
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
                    'After a fall and stillness are confirmed, this is how long '
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
  });

  final TeamHikeSession teamSession;
  final String currentPhoneNumber;

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
    required this.activeHike,
    required this.onShareToCommunity,
    required this.onShareReportText,
    this.initialMapStyleIndex = 0,
  });

  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final Future<void> Function() onShareToCommunity;
  final Future<void> Function() onShareReportText;
  final int initialMapStyleIndex;

  @override
  State<_HikeSummaryReportPage> createState() => _HikeSummaryReportPageState();
}

class _HikeSummaryReportPageState extends State<_HikeSummaryReportPage> {
  bool _isSharingCommunity = false;

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
            content: Text('Sharing is unavailable on this device.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
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

class ActiveHikeHomePage extends StatefulWidget {
  const ActiveHikeHomePage({
    super.key,
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.onEndHike,
    required this.onCheckIn,
    required this.onPinLocation,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
    this.onMapStyleChanged,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final VoidCallback onEndHike;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
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
    if (_isWeatherLoading) {
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
                      label: 'Expected $returnLabel',
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
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
                    onPressed: isCreator
                        ? () => Navigator.of(context).pop('start')
                        : null,
                    icon: Icon(
                      isCreator
                          ? Icons.play_arrow_rounded
                          : Icons.hourglass_top_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isCreator
                          ? hike.participantCount > 1
                                ? 'Start Team Readiness'
                                : 'Start Now (Solo)'
                          : 'Waiting for host',
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
