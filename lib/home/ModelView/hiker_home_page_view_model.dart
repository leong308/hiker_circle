part of '../hiker_home_page_feature.dart';

/// Owns the state and non-visual actions of HikerHomePage.
class _HikerHomePageStateViewModel extends ChangeNotifier {
  /// Creates hiker home page state view model.
  _HikerHomePageStateViewModel({
    required this.readFirebaseBootstrapResult,
    required this.readOnSignOut,
    required this.readSession,
    required this.effectDrainPendingBleUiEvents,
    required this.effectDrainPendingFcmOpens,
    required this.effectDrainPendingTeamReadiness,
    required this.effectEmitPathDeviationAlert,
    required this.effectEnsureLiveLocationHikeConfiguration,
    required this.effectHandleBleEvent,
    required this.effectHandleDeepLink,
    required this.effectHandleFallStillnessCountdownStarted,
    required this.effectOpenStartHikeWizard,
    required this.effectPromptForFormedTeamChatName,
    required this.effectRebuildPlannedHike,
    required this.effectRecordActiveHikeLocationTick,
    required this.effectRecoverActiveHikeAfterReconnect,
    required this.effectRequestSignOut,
    required this.effectRevealActiveHike,
    required this.effectReviewDraftPreparation,
    required this.effectScheduleAnotherTimeAfterHazard,
    required this.effectShowActiveHikeActionError,
    required this.effectShowBleSosHelpPopupForLocation,
    required this.effectShowFallStillnessSnackBar,
    required this.effectShowHikeNotice,
    required this.effectShowNearbySosButtonPopup,
    required this.effectShowUpcomingHikeError,
    required this.effectStartPreparedInstantHike,
    required this.effectSyncActiveHikeLiveStatus,
    required this.effectSyncActiveHikeServices,
    required this.effectUploadActiveHikeLocations,
    required this.effectOpenEmergencyContacts,
    required this.effectRequestImmediateSos,
  });
  final FirebaseBootstrapResult Function() readFirebaseBootstrapResult;
  final VoidCallback Function() readOnSignOut;
  final AppSession Function() readSession;
  final Future<void> Function() effectDrainPendingBleUiEvents;
  final Future<void> Function() effectDrainPendingFcmOpens;
  final Future<void> Function() effectDrainPendingTeamReadiness;
  final Future<void> Function(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double distanceMeters,
  )
  effectEmitPathDeviationAlert;
  final Future<ActiveHikeSession?> Function(ActiveHikeSession hike)
  effectEnsureLiveLocationHikeConfiguration;
  final void Function(HikerBleEvent event) effectHandleBleEvent;
  final Future<void> Function(String link, {bool allowRepeat})
  effectHandleDeepLink;
  final Future<void> Function() effectHandleFallStillnessCountdownStarted;
  final Future<void> Function(
    Trail? trail, {
    bool startWithSchedule,
    UpcomingHike? rescheduleFrom,
  })
  effectOpenStartHikeWizard;
  final void Function(List<GroupChat> chats) effectPromptForFormedTeamChatName;
  final void Function() effectRebuildPlannedHike;
  final Future<void> Function({bool force}) effectRecordActiveHikeLocationTick;
  final Future<void> Function() effectRecoverActiveHikeAfterReconnect;
  final Future<void> Function() effectRequestSignOut;
  final void Function() effectRevealActiveHike;
  final Future<PlannedHike?> Function(
    HikeSessionDraft draft, {
    bool joiningTeam,
    String? upcomingHikeId,
    required Future<bool> Function(
      HikeSessionDraft draft,
      PlannedHike preparation,
    )
    onStart,
  })
  effectReviewDraftPreparation;
  final Future<void> Function(
    Trail trail, {
    UpcomingHike? hike,
    String? hazardId,
  })
  effectScheduleAnotherTimeAfterHazard;
  final void Function(String prefix, Object error)
  effectShowActiveHikeActionError;
  final Future<void> Function({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? sentAt,
    int? rssi,
  })
  effectShowBleSosHelpPopupForLocation;
  final void Function(String message, {bool isError})
  effectShowFallStillnessSnackBar;
  final Future<void> Function(String sessionId, String message, {String? title})
  effectShowHikeNotice;
  final Future<void> Function({int? rssi, SosTriggerLocation? location})
  effectShowNearbySosButtonPopup;
  final void Function(String title, String detail) effectShowUpcomingHikeError;
  final Future<bool> Function(
    HikeSessionDraft draft,
    PlannedHike reviewed, {
    TrailHazardStartGate? initialHazardGate,
  })
  effectStartPreparedInstantHike;
  final void Function(ActiveHikeSession hike, {bool force})
  effectSyncActiveHikeLiveStatus;
  final void Function(
    ActiveHikeSession? hike, {
    bool forceLiveStatus,
    bool stopNativeLiveStatus,
  })
  effectSyncActiveHikeServices;
  final Future<void> Function() effectUploadActiveHikeLocations;
  final Future<void> Function() effectOpenEmergencyContacts;
  final void Function(SosAlertMode mode, {SosAlertTriggerSource triggerSource})
  effectRequestImmediateSos;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<Trail> stateTrails = [];

  late final HikerCircleFirebaseRepository stateHikerCircleRepository;

  late final EmergencyContactsRepository stateEmergencyContactsRepository;

  late final SosAlertRepository stateSosAlertRepository;

  int stateQueuedSosCount = 0;

  int stateSosQueueCountRevision = 0;

  late final NearbySosEventRepository stateNearbySosEventRepository;

  late final FallStillnessMonitor stateFallStillnessMonitor;

  final SosDeviceAlertService stateSosDeviceAlertService =
      const SosDeviceAlertService();

  final SosPresentationController stateSosPresentation =
      SosPresentationController();

  final Map<String, int> stateNativeSosPresentationIds = {};

  final Set<String> stateStoppedNativeSosPresentationIds = {};

  final Set<Completer<void>> stateSosPresentationWaiters = {};

  final ActiveHikeLiveStatusService stateActiveHikeLiveStatusService =
      const ActiveHikeLiveStatusService();

  final HikerBleService stateBleService = const HikerBleService();

  StreamSubscription<List<UpcomingHike>>? stateMyUpcomingHikesSubscription;

  Future<bool>? stateLocalNotificationsInitialization;

  late final UpcomingHikeReminderService stateHikeReminders;

  StreamSubscription<List<Trail>>? stateTrailsSubscription;

  bool stateTrailRegionRepairStarted = false;

  StreamSubscription<HikerBleEvent>? stateBleEventSubscription;

  StreamSubscription<List<GroupChat>>? stateFormedTeamChatsSubscription;

  StreamSubscription<List<TeamHikeSession>>? stateTeamReadinessSubscription;

  final Map<String, TeamHikeSession> statePendingTeamReadinessSessions =
      <String, TeamHikeSession>{};

  final teamReadinessNavigation = TeamReadinessNavigationGuard();

  /// Shares automatic invitation receipts with the readiness stream.
  Set<String> get statePresentedTeamReadinessKeys =>
      teamReadinessNavigation.presentedKeys;

  String? stateActiveUpcomingJoinRequestReviewId;

  List<GroupChat> statePendingFormedTeamChats = const [];

  NetworkReachabilitySnapshot stateNetworkReachabilitySnapshot =
      const NetworkReachabilitySnapshot(
        state: NetworkReachabilityState.checking,
      );

  List<UpcomingHike> stateMyUpcomingHikes = const [];

  Map<String, Set<String>> statePlannedChecklistByUpcomingId = const {};

  Set<String> stateConsumedUpcomingHikeIds = const {};

  int stateUpcomingPlanningRevision = 0;

  bool stateUpcomingSnapshotIsAuthoritative = false;

  int? stateLatestPhoneBatteryLevel;

  bool stateIsLoadingLiveData = false;

  bool stateIsSendingFallStillnessSos = false;

  bool stateIsRecordingActiveHikeLocation = false;

  bool stateIsCheckInBusy = false;

  bool stateIsEndingActiveHike = false;

  bool stateLiveLocationActivatedForActiveHike = false;

  ({
    String ownerPhoneNumber,
    String sessionId,
    bool sharing,
    int intervalSeconds,
  })?
  stateLiveLocationCloudConfiguration;

  Future<void> stateLiveLocationSyncQueue = Future<void>.value();

  final Set<String> stateLiveLocationNotificationCompletedSessionIds =
      <String>{};

  final Set<String> stateLiveLocationNotificationStatusShownSessionIds =
      <String>{};

  bool stateIsFallStillnessLocalAlarmActive = false;

  Timer? stateActiveHikeRecordingTimer;

  Timer? stateActiveHikeUploadTimer;

  int stateLastManualSharingStopRevision = 0;

  int stateLastManualSharingStartRevision = 0;

  Duration? stateActiveHikeUploadInterval;

  bool stateIsReconnectSyncRunning = false;

  Timer? stateActiveHikeMonitoringHeartbeatTimer;

  StreamSubscription<String>? stateFcmTokenSubscription;

  StreamSubscription<RemoteMessage>? stateFcmOpenSubscription;

  StreamSubscription<RemoteMessage>? stateFcmForegroundSubscription;

  final FlutterLocalNotificationsPlugin stateLocalNotifications =
      FlutterLocalNotificationsPlugin();

  late final AchievementNotificationDelivery
  stateAchievementNotificationDelivery;

  StreamSubscription<List<Map<String, dynamic>>>? stateAchievementSubscription;

  final List<_PendingFcmOpen> statePendingFcmOpens = <_PendingFcmOpen>[];

  final Set<String> stateHandledFcmOpenKeys = <String>{};

  final List<HikerBleEvent> statePendingBleUiEvents = <HikerBleEvent>[];

  String? stateActiveHikeMonitoringSessionId;

  String stateFcmToken = '';

  StreamSubscription<TeamHikeSession?>? stateTeamHikeSessionSubscription;

  String? stateTeamHikeWatchSessionId;

  String? stateActiveHikeRecordingSessionId;

  Duration? stateActiveHikeRecordingInterval;

  DateTime? stateLastActiveHikeLocationRecordedAt;

  DateTime? stateLastActiveHikeLiveStatusSentAt;

  DateTime? statePathDeviationStartedAt;

  DateTime? stateLastPathDeviationAlertAt;

  HikeCoordinate? stateStationaryWatchReferenceLocation;

  double? stateStationaryWatchReferenceAccuracyMeters;

  DateTime? stateStationaryWatchStartedAt;

  bool stateIsStationaryLocationWatchActive = false;

  FallStillnessMonitorStatus stateLastFallStillnessStatus =
      FallStillnessMonitorStatus.inactive;

  ActiveHikeSession? stateActiveHike;

  Future<void>? stateActiveHikeRestoreFuture;

  Future<void> stateActiveHikePersistenceQueue = Future<void>.value();

  Future<void> stateFallStillnessSyncQueue = Future<void>.value();

  late final Future<void> stateEmergencyContactsLoadFuture;

  bool stateIsNativeSafetyDialogVisible = false;

  final Map<String, String> stateActiveHikeSessionIdRemaps = <String, String>{};

  int statePendingManualSosRequestId = 0;

  int statePendingImmediateSosRequestId = 0;

  SosAlertMode? stateImmediateSosRequestMode;

  SosAlertTriggerSource stateImmediateSosRequestTriggerSource =
      SosAlertTriggerSource.mobilePhone;

  String? stateLastHandledPairedSosKey;

  final Set<String> statePresentedNearbySosKeys = <String>{};

  final Set<String> statePresentedExactNearbySosKeys = <String>{};

  final Set<String> stateActiveApproximateNearbySosKeys = <String>{};

  final Map<String, SosTriggerLocation> stateExactNearbySosLocations = {};

  final Map<String, Timer> stateNearbySosFallbackTimers = {};

  int stateNearbySosRevision = 0;

  final List<DateTime> stateFallStillnessCancelTaps = <DateTime>[];

  List<EmergencyContact> stateEmergencyContacts = const [];

  late final List<HikerBottomNavDestination> stateTabs;

  /// Returns command has triggered sos.
  bool get commandHasTriggeredSos => stateSosPresentation.current != null;

  /// Checks whether it can speak hike warning.
  bool commandCanSpeakHikeWarning() =>
      mounted &&
      stateActiveHike != null &&
      !stateIsEndingActiveHike &&
      !stateFallStillnessMonitor.isAwaitingResponse &&
      !stateIsFallStillnessLocalAlarmActive &&
      !stateIsSendingFallStillnessSos &&
      !stateIsNativeSafetyDialogVisible &&
      !commandHasTriggeredSos;

  /// Handles live sharing changed.
  void commandHandleLiveSharingChanged() {
    final sharing = LiveLocationSharingService.instance;
    final started =
        sharing.manualStartRevision != stateLastManualSharingStartRevision;
    final stopped =
        sharing.manualStopRevision != stateLastManualSharingStopRevision;
    stateLastManualSharingStartRevision = sharing.manualStartRevision;
    stateLastManualSharingStopRevision = sharing.manualStopRevision;
    if (!mounted) return;
    final hike = stateActiveHike;
    if (hike == null) return;
    if (started) {
      // A fresh manual start can replace an expired/revoked link even when the
      // hiking preference is already on. Relink the active hike and notify its
      // contacts for the new share; a same-link expiry renewal emits no start.
      stateLiveLocationCloudConfiguration = null;
      stateLiveLocationNotificationCompletedSessionIds.remove(hike.sessionId);
      stateLiveLocationNotificationStatusShownSessionIds.remove(hike.sessionId);
    }
    final interval = sharing.hasActiveHike
        ? sharing.updateInterval
        : hike.draft.locationRecordingInterval;
    final shouldShare = stopped
        ? false
        : started
        ? true
        : hike.draft.shareLiveLocation;
    if (!started &&
        !stopped &&
        hike.draft.locationRecordingInterval == interval &&
        hike.draft.shareLiveLocation == shouldShare) {
      return;
    }
    final updated = hike.copyWith(
      draft: hike.draft.copyWith(
        shareLiveLocation: shouldShare,
        locationRecordingInterval: interval,
      ),
    );
    if (stopped) stateLiveLocationActivatedForActiveHike = false;
    _publish(() => stateActiveHike = updated);
    // Update the existing footprint timer and native uploader together. An
    // explicit start also links a hike that was initially started without sharing.
    effectSyncActiveHikeServices(updated, forceLiveStatus: true);
  }

  /// Listens for for formed team chats.
  void commandListenForFormedTeamChats() {
    if (!readFirebaseBootstrapResult().isAvailable) {
      return;
    }
    stateFormedTeamChatsSubscription = stateHikerCircleRepository
        .formedTeamChatsForHostStream(readSession().phoneNumber)
        .listen(
          effectPromptForFormedTeamChatName,
          onError: (_) {
            // Circle provides a visible retry state if the chat stream fails.
          },
        );
  }

  /// Listens for for team readiness.
  void commandListenForTeamReadiness() {
    if (!readFirebaseBootstrapResult().isAvailable) {
      return;
    }
    stateTeamReadinessSubscription = stateHikerCircleRepository
        .watchTeamReadinessForParticipant(readSession().phoneNumber)
        .listen(
          (sessions) {
            for (final teamSession in sessions) {
              final key = commandTeamReadinessKey(teamSession);
              if (key == null ||
                  statePresentedTeamReadinessKeys.contains(key)) {
                continue;
              }
              final ownParticipant = teamSession.participants
                  .where(
                    (participant) => _sameTeamPhone(
                      participant.phoneNumber,
                      readSession().phoneNumber,
                    ),
                  )
                  .firstOrNull;
              if (ownParticipant == null ||
                  ownParticipant.status == TeamHikeParticipantStatus.ended) {
                continue;
              }
              statePendingTeamReadinessSessions[key] = teamSession;
            }
            unawaited(effectDrainPendingTeamReadiness());
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Team readiness updates are unavailable: $error');
          },
        );
  }

  /// Computes team readiness key.
  String? commandTeamReadinessKey(TeamHikeSession teamSession) {
    final startedAt = teamSession.readinessStartedAt;
    if (teamSession.id.trim().isEmpty || startedAt == null) {
      return null;
    }
    return '${teamSession.id}:${startedAt.toUtc().millisecondsSinceEpoch}';
  }

  /// Computes formed chat phone key.
  String commandFormedChatPhoneKey(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Computes deliver achievement notifications.
  Future<void> commandDeliverAchievementNotifications() async {
    if (!mounted) return;
    final ready = await commandInitializeLocalNotifications();
    if (!mounted) return;
    await stateAchievementNotificationDelivery.flush(showBanners: ready);
  }

  /// Computes initialize achievement tracking.
  Future<void> commandInitializeAchievementTracking() async {
    try {
      await stateHikerCircleRepository.recordLocalAchievementEvents(
        session: readSession(),
        events: const [],
      );
      if (!mounted) return;
      stateAchievementSubscription = stateHikerCircleRepository
          .watchUserAchievementProgress(session: readSession())
          .listen(
            (_) {},
            onError: (Object error) =>
                debugPrint('Achievement updates will retry: $error'),
          );
      await stateHikerCircleRepository.loadUserAchievementProgress(
        session: readSession(),
      );
    } catch (error) {
      debugPrint('Achievement sync will retry: $error');
    }
  }

  /// Computes initialize local notifications.
  Future<bool> commandInitializeLocalNotifications() =>
      stateLocalNotificationsInitialization ??=
          commandSetUpLocalNotifications();

  /// Sets up local notifications.
  Future<bool> commandSetUpLocalNotifications() async {
    try {
      final initialized = await stateLocalNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: commandHandleFcmOpenFromLocal,
      );
      if (initialized == false) return false;
      await stateLocalNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'hiker_circle_foreground',
              'HikerCircle notifications',
              description: 'Hiking updates and active trail cautions',
              importance: Importance.high,
            ),
          );
      await stateLocalNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'hiker_circle_upcoming_hikes',
              'Upcoming hike cautions',
              description:
                  'Reported trail conditions affecting your planned hikes',
              importance: Importance.high,
            ),
          );
      final launch = await stateLocalNotifications
          .getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse != null) {
        commandHandleFcmOpenFromLocal(launch!.notificationResponse!);
      }
      await stateLocalNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return true;
    } catch (error) {
      debugPrint('Unable to initialize local notifications: $error');
      stateLocalNotificationsInitialization = null;
      return false;
    }
  }

  /// Synchronizes local hike reminders.
  Future<void> commandSynchronizeLocalHikeReminders() async {
    try {
      if (await commandInitializeLocalNotifications() && mounted) {
        await stateHikeReminders.synchronize();
      }
    } catch (error) {
      debugPrint('Local hike reminders will retry: $error');
    }
  }

  /// Computes initialize firebase messaging.
  Future<void> commandInitializeFirebaseMessaging() async {
    if (!readFirebaseBootstrapResult().isAvailable) {
      return;
    }
    try {
      await commandInitializeLocalNotifications();
      final messaging = FirebaseMessaging.instance;
      // Install open listeners before any permission/token network work. A tap
      // that resumes the app must not be lost while initialization is waiting.
      stateFcmTokenSubscription = messaging.onTokenRefresh.listen(
        (token) => unawaited(commandRegisterFcmTokenBestEffort(token)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('FCM token refresh stream stopped: $error');
        },
      );
      stateFcmOpenSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(commandHandleFcmOpenBestEffort(message)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('FCM open stream stopped: $error');
        },
      );
      stateFcmForegroundSubscription = FirebaseMessaging.onMessage.listen(
        commandShowForegroundNotification,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('FCM foreground stream stopped: $error');
        },
      );

      // Read the terminated-state message before token registration. This is
      // a one-shot value and is the critical path for notification cold starts.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        await commandHandleFcmOpen(initialMessage);
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
          await commandRegisterFcmToken(token);
        }
      } catch (error) {
        debugPrint('FCM token is not available yet: $error');
      }
    } catch (error) {
      debugPrint('Unable to initialize Firebase Messaging: $error');
    }
  }

  /// Computes initialize ble bridge.
  Future<void> commandInitializeBleBridge() async {
    try {
      await stateBleService.setActiveSosAccount(readSession().phoneNumber);
      if (!mounted) {
        return;
      }
      await stateBleEventSubscription?.cancel();
      if (!mounted) {
        return;
      }
      stateBleEventSubscription = stateBleService.events.listen(
        (event) {
          if (event is HikerBleStatusEvent &&
              {
                'paired_button_presence_changed',
                'paired_button_notice',
              }.contains(event.status)) {
            unawaited(
              SosButtonNotificationHistory.synchronize(
                owner: readSession().phoneNumber,
                ble: stateBleService,
                database: stateHikerCircleRepository.localDatabase,
              ),
            );
          }
          effectHandleBleEvent(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('BLE event stream stopped: $error');
        },
      );
      await stateBleService.startSosButtonMonitor();
      await SosButtonNotificationHistory.synchronize(
        owner: readSession().phoneNumber,
        ble: stateBleService,
        database: stateHikerCircleRepository.localDatabase,
      );
    } catch (error) {
      // BLE is an optional transport. A disabled adapter, denied permission,
      // or unavailable native bridge must not become an uncaught launch error.
      debugPrint('Unable to initialize the BLE SOS bridge: $error');
    }
  }

  /// Computes enqueue ble ui event.
  void commandEnqueueBleUiEvent(HikerBleEvent event) {
    if (event is HikerBleSosHelpEvent &&
        !event.canPresentTestPreview(
          DateTime.now().toUtc(),
          debugCaptureEnabled: HikerBleService.isButtonDebugCaptureEnabled,
        )) {
      return;
    }
    final key = switch (event) {
      HikerBleNearbySosButtonEvent() =>
        '${event.deviceId}:${event.counter ?? event.receivedAt.millisecondsSinceEpoch ~/ 1000}',
      HikerBleNearbySosLocationEvent() =>
        '${event.deviceId}:${event.counter ?? event.receivedAt.millisecondsSinceEpoch ~/ 1000}',
      HikerBleSosHelpEvent() =>
        'help:${event.location.latitude.toStringAsFixed(5)}:${event.location.longitude.toStringAsFixed(5)}:${event.location.capturedAt?.millisecondsSinceEpoch ?? 0}',
      _ => '',
    };
    if (key.isEmpty) {
      return;
    }

    final matchingIndex = statePendingBleUiEvents.indexWhere((pending) {
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
      final existing = statePendingBleUiEvents[matchingIndex];
      if (existing is HikerBleNearbySosLocationEvent &&
          event is HikerBleNearbySosButtonEvent) {
        return;
      }
      statePendingBleUiEvents[matchingIndex] = event;
    } else {
      statePendingBleUiEvents.add(event);
      if (statePendingBleUiEvents.length > 16) {
        statePendingBleUiEvents.removeAt(0);
      }
    }
    unawaited(effectDrainPendingBleUiEvents());
  }

  /// Handles network reachability changed.
  void commandHandleNetworkReachabilityChanged(
    NetworkReachabilitySnapshot snapshot,
  ) {
    final wasOnline = stateNetworkReachabilitySnapshot.isOnline;
    stateNetworkReachabilitySnapshot = snapshot;
    if (snapshot.isOnline && (!wasOnline || stateQueuedSosCount > 0)) {
      unawaited(commandRetryQueuedSosAlerts());
    }
    if (!wasOnline && snapshot.isOnline) {
      unawaited(commandSynchronizeAfterReconnect());
    }
  }

  /// Refreshes queued sos count.
  Future<void> commandRefreshQueuedSosCount() async {
    final revision = ++stateSosQueueCountRevision;
    try {
      final count = await stateSosAlertRepository.countQueuedAlerts(
        session: readSession(),
      );
      if (!mounted || revision != stateSosQueueCountRevision) return;
      _publish(() => stateQueuedSosCount = count);
    } catch (_) {
      // Keep the last known count if local storage is temporarily unavailable.
    }
  }

  /// Retries queued sos alerts.
  Future<void> commandRetryQueuedSosAlerts() =>
      commandRunReconnectStep('SOS alerts', () async {
        await stateSosAlertRepository.flushQueuedAlerts(
          session: readSession(),
          contacts: stateEmergencyContacts,
        );
        await commandRefreshQueuedSosCount();
      });

  /// Run reconnect recovery once at a time and let independent retry steps retain their own failures.
  Future<void> commandSynchronizeAfterReconnect() async {
    if (stateIsReconnectSyncRunning || !mounted) {
      return;
    }
    stateIsReconnectSyncRunning = true;
    final requestedSession = readSession();
    try {
      await stateHikerCircleRepository.reconcileCachedReadsAfter(
        session: requestedSession,
        synchronizePending: () async {
          await Future.wait<void>([
            commandRunReconnectStep(
              'privacy consent',
              () => stateHikerCircleRepository.flushPrivacyConsent(
                session: requestedSession,
              ),
            ),
            commandRunReconnectStep(
              'caution reports',
              () => stateHikerCircleRepository.flushPendingCautionReports(
                session: requestedSession,
                forceRetry: true,
              ),
            ),
            commandRunReconnectStep(
              'submitted feedback',
              () => FeedbackRepository().flushPendingSubmission(),
            ),
            commandRunReconnectStep(
              'read receipts',
              () => stateHikerCircleRepository.syncPendingReadReceipts(
                phoneNumber: requestedSession.phoneNumber,
              ),
            ),
            commandRunReconnectStep(
              'upcoming hike plans',
              () => stateHikerCircleRepository.flushPendingUpcomingHikes(
                session: requestedSession,
              ),
            ),
            commandRunReconnectStep(
              'achievement event reconciliation',
              () => stateHikerCircleRepository
                  .synchronizeHistoricalAchievementProgress(
                    session: requestedSession,
                  ),
            ),
            commandRunReconnectStep(
              'emergency contacts',
              () => stateEmergencyContactsRepository
                  .flushPendingEmergencyContacts(session: requestedSession),
            ),
            commandRunReconnectStep(
              'pending sharing stop',
              LiveLocationSharingService.instance.retryPendingStop,
            ),
            commandRunReconnectStep(
              'SOS message notes',
              () => stateSosAlertRepository.flushPendingCustomWhatsAppNotes(
                session: requestedSession,
              ),
            ),
            commandRunReconnectStep('nearby SOS forwarding', () async {
              final events = await stateNearbySosEventRepository.load(
                ownerPhoneNumber: requestedSession.phoneNumber,
                limit: 50,
              );
              final now = DateTime.now().toUtc();
              for (final event in events.where(
                (event) => event.ageAt(now) <= const Duration(hours: 1),
              )) {
                if (!mounted ||
                    readSession().phoneNumber != requestedSession.phoneNumber) {
                  return;
                }
                await stateHikerCircleRepository.forwardNearbySosIncident(
                  event: event,
                );
              }
            }),
            commandRunReconnectStep(
              'chat messages',
              () => stateHikerCircleRepository.flushPendingMessages(
                ownerPhoneNumber: requestedSession.phoneNumber,
              ),
            ),
            commandRunReconnectStep(
              'offline changes',
              () => stateHikerCircleRepository.flushSyncOutbox(
                session: requestedSession,
              ),
            ),
            commandRunReconnectStep(
              'ended hikes',
              () => stateHikerCircleRepository.flushPendingHikeEnds(
                session: requestedSession,
              ),
            ),
          ]);
        },
        recoverLive: () async {
          if (!mounted ||
              readSession().phoneNumber != requestedSession.phoneNumber) {
            return;
          }
          await commandRunReconnectStep(
            'active hike recovery',
            effectRecoverActiveHikeAfterReconnect,
          );
        },
      );
      if (!mounted ||
          readSession().phoneNumber != requestedSession.phoneNumber) {
        return;
      }
      await commandRunReconnectStep("cached emergency preferences", () async {
        await stateEmergencyContactsRepository.applyCachedCloudPreferences(
          session: requestedSession,
        );
        await stateSosAlertRepository.loadCustomWhatsAppNotes(
          session: requestedSession,
          cacheOnly: true,
        );
        final contacts = await stateEmergencyContactsRepository
            .loadCachedEmergencyContacts(session: requestedSession);
        if (mounted &&
            readSession().phoneNumber == requestedSession.phoneNumber) {
          _publish(() => stateEmergencyContacts = contacts);
        }
      });
    } catch (error) {
      debugPrint(
        'Reconnect cache validation remains pending: ${error.runtimeType}',
      );
    } finally {
      stateIsReconnectSyncRunning = false;
    }
  }

  /// Restores scheduled team source link.
  Future<ActiveHikeSession> commandRestoreScheduledTeamSourceLink(
    ActiveHikeSession hike,
  ) async {
    if (hike.sourceUpcomingHikeId.trim().isNotEmpty ||
        hike.teamHikeSessionId.trim().isEmpty) {
      return hike;
    }
    final teamSession = await stateHikerCircleRepository.loadTeamHikeSession(
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
    if (mounted && stateActiveHike?.sessionId == hike.sessionId) {
      final merged = stateActiveHike!.copyWith(
        sourceUpcomingHikeId: sourceUpcomingHikeId,
        teamHikeSession: teamSession,
      );
      _publish(() => stateActiveHike = merged);
      commandPersistActiveHikeSnapshot(merged);
      return merged;
    }
    return updatedHike;
  }

  /// Applies team hike session link.
  ActiveHikeSession commandWithTeamHikeSessionLink(
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

  /// Computes run reconnect step.
  Future<void> commandRunReconnectStep(
    String label,
    Future<dynamic> Function() action,
  ) async {
    try {
      // Repositories bound individual network attempts. Do not let an outer
      // queue timeout release read validation while its writes are still running.
      await action();
    } catch (error) {
      debugPrint('Reconnect $label synchronization will retry: $error');
    }
  }

  /// Computes register fcm token.
  Future<void> commandRegisterFcmToken(String token) async {
    stateFcmToken = token;
    await stateHikerCircleRepository.registerFcmToken(
      session: readSession(),
      token: token,
    );
    final hike = stateActiveHike;
    if (hike != null) {
      await commandSendActiveHikeMonitoringHeartbeat(
        hike,
        lifecycleState: 'active',
      );
    }
  }

  /// Computes register fcm token best effort.
  Future<void> commandRegisterFcmTokenBestEffort(String token) async {
    try {
      await commandRegisterFcmToken(token);
    } catch (error) {
      debugPrint('Unable to refresh the FCM registration: $error');
    }
  }

  /// Handles fcm open best effort.
  Future<void> commandHandleFcmOpenBestEffort(RemoteMessage message) async {
    try {
      await commandHandleFcmOpen(message);
    } catch (error) {
      debugPrint('Unable to open the notification destination: $error');
    }
  }

  /// Handles fcm open.
  Future<void> commandHandleFcmOpen(RemoteMessage message) async {
    await DeviceNotificationLogService.recordFcmMessage(
      message,
      ownerPhoneNumber: readSession().phoneNumber,
      opened: true,
    );
    final data = <String, dynamic>{...message.data};
    commandEnqueueFcmOpen(
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

  /// Computes enqueue fcm open.
  void commandEnqueueFcmOpen(_PendingFcmOpen pending) {
    if (stateHandledFcmOpenKeys.contains(pending.key) ||
        statePendingFcmOpens.any((item) => item.key == pending.key)) {
      return;
    }
    statePendingFcmOpens.add(pending);
    unawaited(effectDrainPendingFcmOpens());
  }

  /// Shows foreground notification.
  Future<void> commandShowForegroundNotification(RemoteMessage message) async {
    if (await ChatMuteStore.suppress(
      message.data,
      owner: readSession().phoneNumber,
    )) {
      return;
    }
    unawaited(
      DeviceNotificationLogService.recordFcmMessage(
        message,
        ownerPhoneNumber: readSession().phoneNumber,
      ),
    );
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'HikerCircle update';
    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'Tap to view details.';
    final type = message.data['type'];
    if (type == 'upcoming_hike_join_request') {
      stateHikerCircleRepository.notifyUpcomingHikeJoinRequestsChanged();
    }
    final deepLink = FcmNotificationRouter.deepLinkFor(<String, dynamic>{
      ...message.data,
    });

    if (type == 'active_hike_monitoring_stopped') {
      return;
    }

    // Active hikers see the canonical-report popup immediately while the app is
    // foregrounded. Background notifications use the same link when tapped.
    if (ActiveTrailHazardNotice.fromFcm(message.data) != null &&
        deepLink != null) {
      commandEnqueueFcmOpen(
        _PendingFcmOpen(
          key: message.messageId?.trim().isNotEmpty == true
              ? message.messageId!.trim()
              : 'foreground-hazard:${message.sentTime?.millisecondsSinceEpoch ?? 0}:${message.data.hashCode}',
          deepLink: deepLink,
          title: title,
          body: body,
        ),
      );
    }

    // A team readiness request is actionable state, not just an informational
    // banner. Foreground users should see the ready interface immediately;
    // background and terminated users follow the same deep link after tapping
    // the FCM notification.
    if (const {
          'team_hike_invite',
          'team_hike_ready',
          'team_hike_countdown',
          'team_hike_started',
          'team_hike_start',
          'team_hike_ping',
        }.contains(type) &&
        deepLink != null) {
      commandEnqueueFcmOpen(
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

    final upcomingCaution =
        type == 'trail_hazard_alert' &&
        !ActiveTrailHazardNotice.isActiveFcm(message.data);
    final androidDetails = AndroidNotificationDetails(
      upcomingCaution
          ? 'hiker_circle_upcoming_hikes'
          : 'hiker_circle_foreground',
      upcomingCaution ? 'Upcoming hike cautions' : 'HikerCircle notifications',
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
      stateLocalNotifications
          .show(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: title,
            body: body,
            payload: jsonEncode({
              ...message.data,
              'type': type,
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

  /// Handles fcm open from local.
  void commandHandleFcmOpenFromLocal(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
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
        final owner = data['ownerPhoneNumber'];
        if (const {
              'local_upcoming_hike_reminder',
              'local_achievement_unlocked',
            }.contains(data['type']) &&
            owner != readSession().phoneNumber) {
          return;
        }
        deepLink = FcmNotificationRouter.deepLinkFor(data);
        title = data['title']?.toString();
        body = data['body']?.toString();
        final messageId = data['messageId']?.toString() ?? '';
        if (messageId.isNotEmpty) {
          unawaited(
            stateHikerCircleRepository.localDatabase
                .markDeviceNotificationMessageOpened(
                  ownerPhoneNumber: readSession().phoneNumber,
                  messageId: messageId,
                ),
          );
        }
      }
    } catch (_) {
      final uri = Uri.tryParse(payload.trim());
      if (uri?.scheme == 'hikercircle') {
        deepLink = uri.toString();
      }
    }
    commandEnqueueFcmOpen(
      _PendingFcmOpen(
        key: 'local:${response.id ?? 0}:${payload.hashCode}',
        deepLink: deepLink,
        title: title,
        body: body,
      ),
    );
  }

  /// Loads emergency contacts.
  Future<void> commandLoadEmergencyContacts() async {
    try {
      final contacts = await stateEmergencyContactsRepository
          .loadEmergencyContacts(session: readSession());
      if (!mounted) {
        return;
      }
      _publish(() {
        stateEmergencyContacts = contacts;
        effectRebuildPlannedHike();
      });
    } catch (_) {
      return;
    }
  }

  /// Restores cached upcoming planning state.
  Future<void> commandRestoreCachedUpcomingPlanningState() async {
    final revision = ++stateUpcomingPlanningRevision;
    try {
      final states = await stateHikerCircleRepository.localDatabase
          .loadPlannedHikeStates(ownerPhoneNumber: readSession().phoneNumber);
      if (!mounted || revision != stateUpcomingPlanningRevision) {
        return;
      }
      final consumed = await stateHikerCircleRepository
          .loadLocallyHiddenUpcomingHikeIds(readSession().phoneNumber);
      if (!mounted || revision != stateUpcomingPlanningRevision) return;
      final checklist = {
        for (final state in states)
          state.upcomingHike.id: state.completedChecklistItems,
      };
      final cached = states
          .where((state) => !state.isConsumed)
          .map((state) => state.upcomingHike);
      _publish(() {
        stateConsumedUpcomingHikeIds = Set<String>.unmodifiable(consumed);
        statePlannedChecklistByUpcomingId =
            Map<String, Set<String>>.unmodifiable(checklist);
        stateMyUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
          remote: stateMyUpcomingHikes,
          cached: cached,
          retainUnconfirmedCachedHikes: true,
          consumedHikeIds: stateConsumedUpcomingHikeIds,
        );
        effectRebuildPlannedHike();
      });
    } catch (error) {
      debugPrint('Unable to restore planned hike state: $error');
    }
  }

  /// Applies upcoming hike snapshot.
  Future<void> commandApplyUpcomingHikeSnapshot(
    List<UpcomingHike> remote,
  ) async {
    final revision = ++stateUpcomingPlanningRevision;
    try {
      final isAuthoritative =
          stateUpcomingSnapshotIsAuthoritative &&
          readFirebaseBootstrapResult().isAvailable &&
          NetworkReachabilityService.instance.latest.isOnline;
      await stateHikerCircleRepository.localDatabase
          .saveUpcomingHikesForPlanning(
            ownerPhoneNumber: readSession().phoneNumber,
            upcomingHikes: remote,
            pruneMissing: isAuthoritative,
          );
      final states = await stateHikerCircleRepository.localDatabase
          .loadPlannedHikeStates(ownerPhoneNumber: readSession().phoneNumber);
      if (!mounted || revision != stateUpcomingPlanningRevision) {
        return;
      }
      final consumed = await stateHikerCircleRepository
          .loadLocallyHiddenUpcomingHikeIds(readSession().phoneNumber);
      if (!mounted || revision != stateUpcomingPlanningRevision) return;
      final checklist = {
        for (final state in states)
          state.upcomingHike.id: state.completedChecklistItems,
      };
      _publish(() {
        stateConsumedUpcomingHikeIds = Set<String>.unmodifiable(consumed);
        statePlannedChecklistByUpcomingId =
            Map<String, Set<String>>.unmodifiable(checklist);
        stateMyUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
          remote: remote,
          cached: states.map((state) => state.upcomingHike),
          // SQLite has pruned confirmed removals; keep local creations that
          // have received an acknowledgement ahead of their live query.
          retainUnconfirmedCachedHikes: true,
          consumedHikeIds: stateConsumedUpcomingHikeIds,
        );
        effectRebuildPlannedHike();
      });
    } catch (error) {
      debugPrint('Unable to reconcile planned hike state: $error');
      if (!mounted || revision != stateUpcomingPlanningRevision) {
        return;
      }
      _publish(() {
        stateMyUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
          remote: remote,
          cached: stateMyUpcomingHikes,
          retainUnconfirmedCachedHikes: true,
          consumedHikeIds: stateConsumedUpcomingHikeIds,
        );
        effectRebuildPlannedHike();
      });
    }
  }

  /// Updates planned hike.
  Future<void> commandUpdatePlannedHike(PlannedHike updatedPlan) async {
    final completed = GearChecklistCatalog.sanitize(
      updatedPlan.completedChecklistItems,
    );
    final normalized = updatedPlan
        .copyWith(
          completedChecklistItems: completed,
          checklistCompleted: completed.length,
          checklistTotal: GearChecklistCatalog.itemCount,
        )
        .withGearProgress();
    final hikeId = await stateHikerCircleRepository.localDatabase
        .resolvePlannedHikeId(
          ownerPhoneNumber: readSession().phoneNumber,
          hikeId: normalized.upcomingHikeId.trim(),
        );
    if (hikeId.isNotEmpty) {
      await stateHikerCircleRepository.localDatabase.savePlannedHikeChecklist(
        ownerPhoneNumber: readSession().phoneNumber,
        upcomingHikeId: hikeId,
        completedItems: completed,
      );
    }
    if (!mounted) {
      return;
    }
    _publish(() {
      if (hikeId.isNotEmpty) {
        statePlannedChecklistByUpcomingId =
            Map<String, Set<String>>.unmodifiable({
              ...statePlannedChecklistByUpcomingId,
              hikeId: completed,
            });
      }
      effectRebuildPlannedHike();
    });
  }

  /// Computes wait for active hike restore.
  Future<void> commandWaitForActiveHikeRestore() async {
    final restoreFuture = stateActiveHikeRestoreFuture;
    if (restoreFuture != null) {
      await restoreFuture;
    }
  }

  /// Serialize active-session persistence so an older asynchronous snapshot cannot win over a newer one.
  void commandPersistActiveHikeSnapshot(ActiveHikeSession? hike) {
    stateActiveHikePersistenceQueue = stateActiveHikePersistenceQueue.then((
      _,
    ) async {
      try {
        if (hike == null) {
          await stateHikerCircleRepository.localDatabase.clearActiveHikeSession(
            phoneNumber: readSession().phoneNumber,
          );
        } else {
          await stateHikerCircleRepository.localDatabase.saveActiveHikeSession(
            phoneNumber: readSession().phoneNumber,
            activeHike:
                stateActiveHikeSessionIdRemaps.containsKey(hike.sessionId)
                ? hike.copyWith(
                    sessionId: stateActiveHikeSessionIdRemaps[hike.sessionId]!,
                  )
                : hike,
          );
        }
      } catch (error) {
        debugPrint('Unable to persist active hike snapshot: $error');
      }
    });
  }

  /// Handles deep link method call.
  Future<void> commandHandleDeepLinkMethodCall(MethodCall call) async {
    if (call.method != 'onDeepLink') {
      return;
    }
    final link = call.arguments;
    if (link is String) {
      await effectHandleDeepLink(link);
    }
  }

  /// Finishes upcoming join request review.
  void commandFinishUpcomingJoinRequestReview() {
    stateActiveUpcomingJoinRequestReviewId = null;
    final pendingChats = statePendingFormedTeamChats;
    statePendingFormedTeamChats = const [];
    if (pendingChats.isNotEmpty) {
      effectPromptForFormedTeamChatName(pendingChats);
    }
  }

  /// Loads live data.
  Future<void> commandLoadLiveData() async {
    _publish(() {
      stateIsLoadingLiveData = true;
    });
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        _publish(() => stateIsLoadingLiveData = false);
      }
    });
    try {
      stateTrailsSubscription?.cancel();
      stateTrailsSubscription = stateHikerCircleRepository.watchTrails().listen(
        (liveTrails) {
          if (!mounted) {
            return;
          }
          _publish(() {
            stateTrails = liveTrails;
            stateIsLoadingLiveData = false;
            effectRebuildPlannedHike();
          });
          if (readSession().isAdmin && !stateTrailRegionRepairStarted) {
            stateTrailRegionRepairStarted = true;
            unawaited(commandRepairTrailRegions(liveTrails));
          }
        },
        onError: (_) {
          if (mounted) {
            _publish(() => stateIsLoadingLiveData = false);
          }
        },
      );
      stateMyUpcomingHikesSubscription?.cancel();
      stateMyUpcomingHikesSubscription = stateHikerCircleRepository
          .watchMyUpcomingHikes(
            readSession().phoneNumber,
            onSourceChanged: (value) =>
                stateUpcomingSnapshotIsAuthoritative = value,
          )
          .listen(
            (hikes) {
              if (!mounted) {
                return;
              }
              unawaited(commandApplyUpcomingHikeSnapshot(hikes));
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Upcoming hike updates are unavailable: $error');
            },
          );
      unawaited(
        stateHikerCircleRepository.ensureAchievementSeeds().catchError((
          Object error,
        ) {
          debugPrint('Achievement seed sync was skipped: $error');
        }),
      );
    } catch (_) {
      if (mounted) {
        _publish(() => stateIsLoadingLiveData = false);
      }
    }
  }

  /// Repairs trail regions.
  Future<void> commandRepairTrailRegions(List<Trail> liveTrails) async {
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
        await stateHikerCircleRepository.updateTrailByAdmin(
          session: readSession(),
          trail: trail.copyWith(country: region.country, state: region.state),
        );
      } catch (error) {
        debugPrint('Unable to normalize ${trail.name} region: $error');
      }
    }
  }

  /// Computes battery level.
  Future<int?> commandReadBatteryLevel() => stateSosDeviceAlertService
      .getBatteryLevel()
      .timeout(const Duration(milliseconds: 700), onTimeout: () => null)
      .catchError((Object _) => null);

  /// Refreshes battery level.
  Future<void> commandRefreshBatteryLevel() async {
    final requestedSession = stateActiveHike?.sessionId;
    final power = requestedSession == null
        ? null
        : await stateActiveHikeLiveStatusService
              .activePowerSettings()
              .timeout(const Duration(seconds: 1), onTimeout: () => null)
              .catchError((Object _) => null);
    final batteryLevel = await commandReadBatteryLevel();
    if (!mounted) return;
    var hike = stateActiveHike;
    if (hike != null && hike.sessionId == requestedSession) {
      hike = reconcileNativeBatterySafety(hike, power);
      if (batteryLevel != null) {
        hike = applyLowBatterySafety(hike, batteryLevel);
      }
    }
    final changedSettings =
        hike != null && hike.draft != stateActiveHike?.draft;
    _publish(() {
      if (batteryLevel != null) stateLatestPhoneBatteryLevel = batteryLevel;
      effectRebuildPlannedHike();
      if (hike?.sessionId == stateActiveHike?.sessionId) stateActiveHike = hike;
    });
    if (hike != null) {
      if (changedSettings) {
        effectSyncActiveHikeServices(hike, forceLiveStatus: true);
      } else {
        commandPersistActiveHikeSnapshot(hike);
        effectSyncActiveHikeLiveStatus(hike, force: true);
      }
    }
  }

  /// Computes hike with recorded location.
  ActiveHikeSession commandHikeWithRecordedLocation(
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

  /// Checks hazards for start.
  Future<bool> commandCheckHazardsForStart(
    TrailHazardStartGate gate,
    Trail trail, {
    UpcomingHike? upcomingHike,
  }) async {
    if (trail.isUnlisted) return mounted;
    final action = await gate.check(trail.trailId);
    if (!mounted) return false;
    if (action == TrailHazardAlertAction.reschedule) {
      await effectScheduleAnotherTimeAfterHazard(
        trail,
        hike: upcomingHike,
        hazardId: gate.fatalHazardId,
      );
    }
    return mounted && action == TrailHazardAlertAction.proceed;
  }

  /// Opens start hike wizard.
  Future<void> commandOpenStartHikeWizard([Trail? trail]) =>
      effectOpenStartHikeWizard(trail);

  /// Computes try prepared hike start.
  Future<bool> commandTryPreparedHikeStart(
    Future<bool> Function() start,
  ) async {
    try {
      return await start();
    } on HikerCircleFirebaseRepositoryException catch (error) {
      effectShowUpcomingHikeError('Unable to start hike', error.message);
      return false;
    }
  }

  /// Keep preparation on the navigator until its start attempt succeeds.
  Future<bool> commandStartInstantHikeFromWizard(
    HikeSessionDraft draft, {
    TrailHazardStartGate? initialHazardGate,
  }) async {
    final reviewed = await effectReviewDraftPreparation(
      draft,
      onStart: (safetyDraft, preparation) => effectStartPreparedInstantHike(
        safetyDraft,
        preparation,
        initialHazardGate: initialHazardGate,
      ),
    );
    if (!mounted || reviewed == null) return false;
    effectRevealActiveHike();
    return true;
  }

  /// Records initial active hike location.
  Future<void> commandRecordInitialActiveHikeLocation(
    ActiveHikeSession hike,
  ) async {
    if (stateActiveHike?.sessionId != hike.sessionId) {
      return;
    }
    await effectRecordActiveHikeLocationTick(force: true);
  }

  /// Checks in active hike.
  Future<ActiveHikeSession> commandCheckInActiveHike(
    ActiveHikeSession currentHike,
  ) async => stateActiveHike ?? currentHike;

  /// Applies active hike check in.
  Future<void> commandApplyActiveHikeCheckIn(ActiveHikeSession hike) async {
    if (stateIsCheckInBusy || stateActiveHike?.sessionId != hike.sessionId) {
      return;
    }
    stateIsCheckInBusy = true;
    try {
      final updatedHike = await commandCheckInActiveHike(hike);
      if (!mounted || stateActiveHike?.sessionId != hike.sessionId) {
        return;
      }
      _publish(() => stateActiveHike = updatedHike);
      effectSyncActiveHikeServices(updatedHike, forceLiveStatus: true);
    } catch (error) {
      effectShowActiveHikeActionError('Unable to save check-in', error);
    } finally {
      stateIsCheckInBusy = false;
    }
  }

  /// Resolves current membership before opening preparation or team readiness.
  Future<ResolvedUpcomingHikeStart> commandResolveUpcomingStart(
    UpcomingHike hike,
    HikeSessionDraft draft,
  ) => UpcomingHikeStartResolver(
    loadCurrent: (id) =>
        stateHikerCircleRepository.loadParticipantUpcomingHikeForSafety(
          hikeId: id,
          session: readSession(),
        ),
    makeDraft: (current, draft) {
      final roster = commandDraftForUpcomingHike(current, draft.trail);
      return draft.copyWith(
        hikeType: roster.hikeType,
        teamBuddies: roster.teamBuddies,
        clearSoloDistanceAcknowledgement:
            draft.hikeType == HikeType.team && roster.hikeType == HikeType.solo,
      );
    },
  ).resolve(hike, draft);

  /// Computes draft for upcoming hike.
  HikeSessionDraft commandDraftForUpcomingHike(UpcomingHike hike, Trail trail) {
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
        .where((phone) => !_sameTeamPhone(phone, readSession().phoneNumber))
        .map((phone) {
          final key = phone.replaceAll(RegExp(r'[^0-9]'), '');
          return savedBuddies[key] ??
              TeamHikeBuddy(name: phone, handle: '', phoneNumber: phone);
        })
        .toList();
    final base =
        savedDraft ??
        HikeSessionDraft.fromTrail(trail).copyWith(
          locationRecordingInterval:
              LocationUpdateIntervalController.instance.interval,
        );
    final completed = GearChecklistCatalog.sanitize(
      statePlannedChecklistByUpcomingId[hike.id] ??
          savedDraft?.completedChecklistItems ??
          const <String>{},
    );
    return base.copyWith(
      locationRecordingInterval:
          LocationUpdateIntervalController.instance.preferredInterval,
      pathDeviationDistanceMeters:
          AppSettingsController.instance.pathDeviationDistanceMeters,
      fallDetectionSettings: FallDetectionSettings(
        sensorSensitivity: AppSettingsController.instance.fallSensorSensitivity,
        fallResponseDuration: base.fallDetectionSettings.fallResponseDuration,
        longestRestDuration: base.fallDetectionSettings.longestRestDuration,
      ),
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
      emergencyContactNames: stateEmergencyContacts
          .map((contact) => contact.name.trim())
          .where((name) => name.isNotEmpty)
          .toList(),
      completedChecklistItems: completed,
      teamBuddies: buddies,
    );
  }

  /// Applies team safety settings.
  HikeSessionDraft commandApplyTeamSafetySettings(
    HikeSessionDraft draft,
    TeamHikeSession teamSession,
  ) {
    TeamHikeParticipant? participant;
    for (final item in teamSession.participants) {
      if (_sameTeamPhone(item.phoneNumber, readSession().phoneNumber)) {
        participant = item;
        break;
      }
    }
    final safety = participant?.safetySettings ?? const <String, dynamic>{};
    return draft.copyWith(
      shareLiveLocation: draft.shareLiveLocation,
      pathDeviationEnabled: !draft.trail.isUnlisted,
      pathDeviationDistanceMeters: safety['pathDeviationDistanceMeters'] == null
          ? draft.pathDeviationDistanceMeters
          : PathDeviationPolicy.normalizeDistance(
              safety['pathDeviationDistanceMeters'],
            ),
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

  /// Computes edit safety contacts.
  Future<List<String>> commandEditSafetyContacts() async {
    await effectOpenEmergencyContacts();
    final contacts = await commandPreparationContacts();
    return contacts.map((contact) => contact.name).toList();
  }

  /// Loads hike safety draft.
  Future<HikeSessionDraft> commandLoadHikeSafetyDraft(
    HikeSessionDraft draft,
    String? hikeId,
  ) async {
    final settings = AppSettingsController.instance;
    await settings.ready;
    final interval = LocationUpdateIntervalController.instance;
    await interval.loadForUser(readSession().phoneNumber);
    draft = draft.copyWith(
      locationRecordingInterval: interval.preferredInterval,
      pathDeviationDistanceMeters: settings.pathDeviationDistanceMeters,
      fallDetectionSettings: FallDetectionSettings(
        sensorSensitivity: settings.fallSensorSensitivity,
        fallResponseDuration: draft.fallDetectionSettings.fallResponseDuration,
        longestRestDuration: draft.fallDetectionSettings.longestRestDuration,
      ),
    );
    if (hikeId != null && hikeId.isNotEmpty) {
      final saved = await stateHikerCircleRepository.localDatabase
          .loadPreparationSafetyPreference(
            ownerPhoneNumber: readSession().phoneNumber,
            hikeId: hikeId,
          );
      if (saved is Map) {
        draft = HikeSafetyPreferences.applyToDraft(draft, saved);
      } else {
        // Preserve choices made in the previous preparation screen.
        final sharing = await commandLoadPreparationSharing(hikeId);
        if (sharing != null) {
          draft = draft.copyWith(
            shareLiveLocation: sharing.enabled,
            locationRecordingInterval: sharing.interval,
          );
        }
      }
    }
    final contacts = await commandPreparationContacts();
    final fall = draft.fallDetectionSettings;
    return draft.copyWith(
      emergencyContactNames: contacts.map((contact) => contact.name).toList(),
      pathDeviationEnabled:
          !draft.trail.isUnlisted && draft.pathDeviationEnabled,
      fallDetectionSettings: FallDetectionSettings(
        sensorSensitivity: fall.sensorSensitivity,
        fallResponseDuration:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? const Duration(seconds: 15)
            : fall.fallResponseDuration,
        longestRestDuration: fall.longestRestDuration,
      ),
    );
  }

  /// Saves hike safety draft.
  Future<void> commandSaveHikeSafetyDraft(
    HikeSessionDraft draft,
    String? hikeId,
  ) async {
    if (hikeId != null && hikeId.isNotEmpty) {
      await stateHikerCircleRepository.localDatabase
          .savePreparationSafetyPreference(
            ownerPhoneNumber: readSession().phoneNumber,
            hikeId: hikeId,
            value: HikeSafetyPreferences.fromDraft(draft),
          );
      await commandSavePreparationSharing(
        hikeId,
        HikePreparationSharing(
          enabled: draft.shareLiveLocation,
          interval: draft.locationRecordingInterval,
        ),
      );
    } else {
      await LocationUpdateIntervalController.instance.loadForUser(
        readSession().phoneNumber,
      );
      await LocationUpdateIntervalController.instance.setInterval(
        draft.locationRecordingInterval,
      );
    }
    final settings = AppSettingsController.instance;
    settings.setFallSensorSensitivity(
      draft.fallDetectionSettings.sensorSensitivity,
    );
    settings.setPathDeviationDistanceMeters(draft.pathDeviationDistanceMeters);
    await settings.saved;
  }

  /// Computes preparation contacts.
  Future<List<EmergencyContact>> commandPreparationContacts() async {
    await stateEmergencyContactsLoadFuture;
    return List.of(stateEmergencyContacts);
  }

  /// Loads preparation sharing.
  Future<HikePreparationSharing?> commandLoadPreparationSharing(
    String hikeId,
  ) async => HikePreparationSharing.fromJson(
    await stateHikerCircleRepository.localDatabase
        .loadPreparationSharingPreference(
          ownerPhoneNumber: readSession().phoneNumber,
          hikeId: hikeId,
        ),
  );

  /// Saves preparation sharing.
  Future<void> commandSavePreparationSharing(
    String hikeId,
    HikePreparationSharing choice,
  ) async {
    await stateHikerCircleRepository.localDatabase
        .savePreparationSharingPreference(
          ownerPhoneNumber: readSession().phoneNumber,
          hikeId: hikeId,
          value: choice.toJson(),
        );
    await LocationUpdateIntervalController.instance.loadForUser(
      readSession().phoneNumber,
    );
    await LocationUpdateIntervalController.instance.setInterval(
      choice.interval,
    );
  }

  /// Applies reviewed preparation.
  HikeSessionDraft commandApplyReviewedPreparation(
    HikeSessionDraft draft,
    PlannedHike plan,
  ) => plan
      .applyToDraft(draft)
      .copyWith(
        emergencyContactNames: stateEmergencyContacts
            .map((contact) => contact.name)
            .toList(),
      );

  /// Computes wait for triggered sos to close.
  Future<void> commandWaitForTriggeredSosToClose() async {
    if (!mounted || !commandHasTriggeredSos) return;
    final ready = Completer<void>();
    stateSosPresentationWaiters.add(ready);

    /// Checks.
    void check() {
      if (!commandHasTriggeredSos && !ready.isCompleted) ready.complete();
    }

    stateSosPresentation.addListener(check);
    try {
      check();
      await ready.future;
    } finally {
      stateSosPresentationWaiters.remove(ready);
      stateSosPresentation.removeListener(check);
    }
  }

  /// Stops triggered sos outputs.
  Future<void> commandStopTriggeredSosOutputs({
    String? nativeEventId,
    int? expectedEventId,
  }) async {
    stateFallStillnessMonitor.cancelPendingEmergency(
      'Slide-to-stop response received',
    );
    stateFallStillnessCancelTaps.clear();
    await Future.wait<void>([
      stateSosDeviceAlertService.stopFallStillnessCountdownVibration(
        strict: true,
      ),
      stateSosDeviceAlertService.stopSpokenPrompt(strict: true),
      stateSosDeviceAlertService.stopManualSosPattern(strict: true),
      () async {
        final pending = await stateActiveHikeLiveStatusService
            .consumePendingSafetyEvent(strict: true);
        final id = nativeEventId ?? pending?.eventId;
        if (id == null || id.isEmpty) return;
        if (expectedEventId != null &&
            stateSosPresentation.current != null &&
            stateSosPresentation.current?.eventId != expectedEventId) {
          return;
        }
        if (pending?.eventId == id && pending?.phase == 'awaiting_response') {
          await stateActiveHikeLiveStatusService.cancelNativeSafetyAlert();
          return;
        }
        final stopped = await stateActiveHikeLiveStatusService
            .stopTriggeredSafetyAlarm(id);
        if (!stopped) {
          final latest = await stateActiveHikeLiveStatusService
              .consumePendingSafetyEvent(strict: true);
          if (latest != null && !latest.localAlarmStopped) {
            if (latest.eventId != id &&
                (latest.isTriggering ||
                    latest.isDispatching ||
                    latest.isDispatched ||
                    latest.isDispatchFailed ||
                    latest.isReadyForFlutterDispatch)) {
              commandPresentNativeTriggeredSos(latest);
            }
            throw StateError('The local safety alarm could not be stopped.');
          }
        }
      }(),
    ]).timeout(const Duration(seconds: 4));
    stateIsFallStillnessLocalAlarmActive = false;
  }

  /// Computes present native triggered sos.
  int? commandPresentNativeTriggeredSos(NativeHikeSafetyEvent event) {
    if (event.localAlarmStopped) {
      stateStoppedNativeSosPresentationIds.add(event.eventId);
      return null;
    }
    if (stateStoppedNativeSosPresentationIds.contains(event.eventId)) {
      return null;
    }
    var presentationId = stateNativeSosPresentationIds[event.eventId];
    presentationId ??= stateSosPresentation.begin(
      mode: event.isProlongedStillness
          ? SosAlertMode.prolongedStillness
          : SosAlertMode.fallStillness,
      triggeredAt: event.triggeredAt,
      onStopAlarm: () => commandStopTriggeredSosOutputs(
        nativeEventId: event.eventId,
        expectedEventId: stateNativeSosPresentationIds[event.eventId],
      ),
    );
    stateNativeSosPresentationIds[event.eventId] = presentationId;
    if (!stateSosPresentation.hasDeliveryStatus(presentationId)) {
      stateSosPresentation.updateStatus(
        presentationId,
        phase: event.isDispatchFailed
            ? SosPresentationPhase.failed
            : event.isDispatched
            ? SosPresentationPhase.sent
            : SosPresentationPhase.sending,
        message:
            event.dispatchMessage ??
            (event.isDispatched
                ? 'The background alert was sent or saved for retry.'
                : event.isDispatchFailed
                ? 'Contact delivery needs retry. Your local alarm is still active.'
                : 'Preparing your alert for emergency contacts…'),
      );
    }
    return presentationId;
  }

  /// Computes consume manual sos request.
  void commandConsumeManualSosRequest(int requestId) {
    if (!mounted || requestId != statePendingManualSosRequestId) {
      return;
    }
    _publish(() {
      statePendingManualSosRequestId = 0;
    });
  }

  /// Computes consume immediate sos request.
  void commandConsumeImmediateSosRequest(int requestId) {
    if (!mounted || requestId != statePendingImmediateSosRequestId) {
      return;
    }
    _publish(() {
      statePendingImmediateSosRequestId = 0;
      stateImmediateSosRequestMode = null;
      stateImmediateSosRequestTriggerSource = SosAlertTriggerSource.mobilePhone;
    });
  }

  /// Handles paired sos button event.
  void commandHandlePairedSosButtonEvent(HikerBlePairedSosButtonEvent event) {
    if (event.mode != 1) {
      return;
    }
    final key = '${event.deviceId}:${event.counter ?? 'unknown'}';
    if (event.deviceId.isEmpty || stateLastHandledPairedSosKey == key) {
      return;
    }
    stateLastHandledPairedSosKey = key;
    effectRequestImmediateSos(
      SosAlertMode.manual,
      triggerSource: SosAlertTriggerSource.emergencyButton,
    );
    final eventId = event.counter;
    if (eventId != null) {
      unawaited(commandSendPairedSosLocation(event.deviceId, eventId));
    }
  }

  /// Sends paired sos location.
  Future<void> commandSendPairedSosLocation(
    String deviceId,
    int eventId,
  ) async {
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
      await stateBleService.sendPairedSosLocation(
        deviceId: deviceId,
        eventId: eventId,
        location: location,
      );
    } catch (error) {
      debugPrint('Unable to return SOS location to button: $error');
    }
  }

  /// Computes present nearby sos after location wait.
  Future<void> commandPresentNearbySosAfterLocationWait(
    String key,
    int? rssi,
  ) async {
    stateNearbySosFallbackTimers.remove(key)?.cancel();
    final exact = stateExactNearbySosLocations[key];
    if (exact != null) {
      if (statePresentedExactNearbySosKeys.add(key)) {
        statePresentedNearbySosKeys.add(key);
        await effectShowNearbySosButtonPopup(rssi: rssi, location: exact);
      }
      return;
    }
    if (!statePresentedNearbySosKeys.add(key)) {
      return;
    }
    stateActiveApproximateNearbySosKeys.add(key);
    await effectShowNearbySosButtonPopup(rssi: rssi);
    stateActiveApproximateNearbySosKeys.remove(key);
    final lateExact = stateExactNearbySosLocations[key];
    if (lateExact != null && statePresentedExactNearbySosKeys.add(key)) {
      await effectShowNearbySosButtonPopup(rssi: rssi, location: lateExact);
    }
  }

  /// Handles ble sos help event.
  Future<void> commandHandleBleSosHelpEvent(HikerBleSosHelpEvent event) async {
    if (!event.canPresentTestPreview(
      DateTime.now().toUtc(),
      debugCaptureEnabled: HikerBleService.isButtonDebugCaptureEnabled,
    )) {
      return;
    }
    // The type-three transport is an explicit test; never save or forward it as an incident.
    await effectShowBleSosHelpPopupForLocation(
      latitude: event.location.latitude,
      longitude: event.location.longitude,
      accuracyMeters: event.location.accuracyMeters,
      sentAt: event.location.capturedAt,
      rssi: event.rssi,
    );
  }

  /// Records nearby sos event.
  Future<void> commandRecordNearbySosEvent({
    required String deviceId,
    required DateTime receivedAt,
    int? counter,
    int? rssi,
    SosTriggerLocation? location,
  }) async {
    final event = NearbySosEvent(
      ownerPhoneNumber: readSession().phoneNumber,
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
    if (event.isDiagnosticTest) return;
    try {
      await stateNearbySosEventRepository.save(event);
      if (mounted) {
        _publish(() => stateNearbySosRevision += 1);
      }
    } catch (error) {
      debugPrint('Unable to save nearby SOS event: $error');
    }
    unawaited(commandForwardNearbySosEvent(event));
  }

  /// Computes forward nearby sos event.
  Future<void> commandForwardNearbySosEvent(NearbySosEvent event) async {
    if (event.isDiagnosticTest) return;
    try {
      await stateHikerCircleRepository.forwardNearbySosIncident(event: event);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      // The local SQLite record is the durable retry source. Reconnect sync
      // replays it through the server's deterministic incident deduplicator.
      debugPrint('Nearby SOS forwarding deferred: ${error.message}');
    } catch (error) {
      debugPrint('Unable to forward nearby SOS observation: $error');
    }
  }

  /// Formats ble sos help time.
  String commandFormatBleSosHelpTime(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  /// Computes sign out and clear active hike.
  void commandSignOutAndClearActiveHike() {
    unawaited(effectRequestSignOut());
  }

  /// Computes perform sign out.
  Future<void> commandPerformSignOut() async {
    /// Computes bounded.
    Future<void> bounded(Future<void> action) async {
      try {
        await action.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    await Future.wait([
      bounded(LiveLocationSharingService.instance.deactivate(manual: false)),
      bounded(stateBleService.setActiveSosAccount(null)),
      bounded(
        stateHikerCircleRepository.removeFcmToken(session: readSession()),
      ),
    ]);
    if (mounted) {
      await bounded(stateHikeReminders.stopForSignOut());
      if (mounted) readOnSignOut()();
    }
  }

  /// Computes resume ble sos monitor.
  Future<void> commandResumeBleSosMonitor() async {
    try {
      await stateBleService.setActiveSosAccount(readSession().phoneNumber);
      await stateBleService.startSosButtonMonitor();
    } catch (error) {
      debugPrint('Unable to resume the BLE SOS monitor: $error');
    }
  }

  /// Handles fall stillness monitor changed.
  void commandHandleFallStillnessMonitorChanged() {
    if (!mounted) {
      return;
    }

    final status = stateFallStillnessMonitor.snapshot.status;
    final didStartCountdown =
        status == FallStillnessMonitorStatus.awaitingResponse &&
        stateLastFallStillnessStatus !=
            FallStillnessMonitorStatus.awaitingResponse;
    stateLastFallStillnessStatus = status;

    _publish(() {});

    if (didStartCountdown) {
      unawaited(effectHandleFallStillnessCountdownStarted());
    }
  }

  /// Handles fall stillness emergency ready.
  Future<void> commandHandleFallStillnessEmergencyReady(
    FallStillnessMonitorSnapshot snapshot,
  ) async {
    stateFallStillnessCancelTaps.clear();
    unawaited(stateSosDeviceAlertService.stopFallStillnessCountdownVibration());
    unawaited(stateSosDeviceAlertService.stopSpokenPrompt());
    await commandTriggerFallStillnessSos(snapshot);
  }

  /// Computes trigger fall stillness sos.
  Future<bool> commandTriggerFallStillnessSos(
    FallStillnessMonitorSnapshot snapshot, {
    int? presentationEventId,
  }) async {
    if (stateIsSendingFallStillnessSos) {
      return false;
    }

    stateIsSendingFallStillnessSos = true;
    final isProlongedStillness = snapshot.isProlongedStillnessDetection;
    final alertName = isProlongedStillness
        ? 'Prolonged-stillness SOS'
        : 'Fall SOS';
    final presentationId =
        presentationEventId ??
        stateSosPresentation.begin(
          mode: isProlongedStillness
              ? SosAlertMode.prolongedStillness
              : SosAlertMode.fallStillness,
          triggeredAt: snapshot.triggeredAt,
          onStopAlarm: commandStopTriggeredSosOutputs,
        );
    if (!stateIsFallStillnessLocalAlarmActive) {
      startSosAlarmOutput(
        controller: stateSosPresentation,
        eventId: presentationId,
        start: stateSosDeviceAlertService.startManualSosPattern,
        stop: stateSosDeviceAlertService.stopManualSosPattern,
        onStarted: () => stateIsFallStillnessLocalAlarmActive = true,
        onUnavailable: () => stateIsFallStillnessLocalAlarmActive = false,
      );
    }

    try {
      final triggerLocation = await commandCaptureTriggerLocation();
      final result = await stateSosAlertRepository.triggerAlert(
        session: readSession(),
        mode: isProlongedStillness
            ? SosAlertMode.prolongedStillness
            : SosAlertMode.fallStillness,
        triggeredAt: snapshot.triggeredAt ?? DateTime.now().toUtc(),
        triggerLocation: triggerLocation,
        contacts: stateEmergencyContacts,
        triggerSource: SosAlertTriggerSource.automaticDetection,
      );
      stateSosPresentation.updateResult(presentationId, result);
      return true; // Repository has sent or durably queued the alert.
    } on SosAlertRepositoryException catch (error) {
      stateSosPresentation.updateResult(
        presentationId,
        null,
        errorMessage: '$alertName needs retry: ${error.message}',
      );
    } catch (_) {
      stateSosPresentation.updateResult(
        presentationId,
        null,
        errorMessage:
            '$alertName could not be confirmed. Check the SOS events for delivery status.',
      );
    } finally {
      stateIsSendingFallStillnessSos = false;
    }
    return false;
  }

  /// Captures trigger location.
  Future<SosTriggerLocation?> commandCaptureTriggerLocation() async {
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

  /// Synchronizes fall stillness monitor.
  void commandSyncFallStillnessMonitor(ActiveHikeSession? hike) {
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
    stateFallStillnessSyncQueue = stateFallStillnessSyncQueue.then((_) async {
      if (!mounted) {
        return;
      }
      final currentHike = stateActiveHike;
      final stillCurrent = shouldStart
          ? currentHike != null &&
                currentHike.draft.fallDetectionEnabled &&
                currentHike.draft.fallDetectionSettings == settings
          : nativeServiceOwnsDetection ||
                currentHike == null ||
                !currentHike.draft.fallDetectionEnabled;
      if (!stillCurrent) {
        return;
      }
      if (!shouldStart || settings == null) {
        await stateFallStillnessMonitor.stop();
        await stateSosDeviceAlertService.stopFallStillnessCountdownVibration();
      } else {
        await stateFallStillnessMonitor.start(settings);
      }
    });
  }

  /// Synchronizes live location for active hike.
  Future<void> commandSyncLiveLocationForActiveHike(
    ActiveHikeSession? hike,
  ) async {
    stateLiveLocationSyncQueue = stateLiveLocationSyncQueue
        .then((_) => commandPerformLiveLocationSyncForActiveHike(hike))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Unable to synchronize live hike location: $error');
        });
    return stateLiveLocationSyncQueue;
  }

  /// Computes perform live location sync for active hike.
  Future<void> commandPerformLiveLocationSyncForActiveHike(
    ActiveHikeSession? hike,
  ) async {
    if (!mounted) {
      return;
    }
    if (hike != null &&
        (stateActiveHike?.sessionId != hike.sessionId ||
            stateIsEndingActiveHike)) {
      return;
    }
    // Queued work must use the current choices, not an older captured draft.
    if (hike != null) hike = stateActiveHike;
    final service = LiveLocationSharingService.instance;
    if (hike == null &&
        stateActiveHike?.draft.shareLiveLocation == true &&
        !stateIsEndingActiveHike) {
      return;
    }
    if (hike == null || !hike.draft.shareLiveLocation) {
      if (stateLiveLocationActivatedForActiveHike ||
          (hike != null && service.isActive)) {
        await service.deactivate(manual: false);
        stateLiveLocationActivatedForActiveHike = false;
      }
      return;
    }

    hike = await effectEnsureLiveLocationHikeConfiguration(hike);
    if (hike == null) return;

    await service.loadExisting(
      phoneNumber: readSession().phoneNumber,
      firebaseBootstrapResult: readFirebaseBootstrapResult(),
    );
    if (!mounted ||
        stateActiveHike?.sessionId != hike.sessionId ||
        stateActiveHike?.draft.shareLiveLocation != true ||
        stateIsEndingActiveHike) {
      return;
    }
    if (!service.isActive) {
      await service.activate(
        phoneNumber: readSession().phoneNumber,
        firebaseBootstrapResult: readFirebaseBootstrapResult(),
        manual: false,
      );
    }
    if (!mounted ||
        stateActiveHike?.sessionId != hike.sessionId ||
        stateActiveHike?.draft.shareLiveLocation != true ||
        stateIsEndingActiveHike) {
      if (service.isActive) {
        await service.deactivate(manual: false);
      }
      return;
    }
    if (service.isActive) {
      final currentHike = stateActiveHike!;
      if (stateLiveLocationCloudConfiguration !=
          commandLiveLocationConfigurationFor(currentHike)) {
        return;
      }
      hike = currentHike;
      final firstActivation = !stateLiveLocationActivatedForActiveHike;
      stateLiveLocationActivatedForActiveHike = true;
      if (firstActivation && !service.hasActiveHike) {
        await service.publishLatest();
      }
      effectSyncActiveHikeLiveStatus(hike, force: true);
      final share = service.share;
      if (share == null ||
          stateLiveLocationNotificationCompletedSessionIds.contains(
            hike.sessionId,
          )) {
        return;
      }
      try {
        final result = await stateHikerCircleRepository
            .notifyEmergencyContactsOfLiveLocation(
              activeHikeSessionId: hike.sessionId,
              shareId: share.id,
            )
            .timeout(const Duration(seconds: 8));
        if (!result.shouldRetry) {
          stateLiveLocationNotificationCompletedSessionIds.add(hike.sessionId);
        }
        if (!mounted ||
            stateActiveHike?.sessionId != hike.sessionId ||
            !stateLiveLocationNotificationStatusShownSessionIds.add(
              hike.sessionId,
            )) {
          return;
        }
        final message = result.contactCount == 0
            ? 'Live location is active, but no SOS contacts are saved.'
            : result.sentCount == result.contactCount
            ? 'Live location was sent to all ${result.contactCount} SOS contacts.'
            : result.uncertainCount > 0
            ? 'Live location is active, but delivery to ${result.uncertainCount} SOS contact(s) could not be confirmed.'
            : 'Live location is active. ${result.sentCount} of ${result.contactCount} SOS contacts were notified; remaining deliveries will retry when connected.';
        unawaited(
          effectShowHikeNotice(hike.sessionId, message, title: 'Live sharing'),
        );
      } on HikerCircleFirebaseRepositoryException catch (error) {
        if (!mounted ||
            stateActiveHike?.sessionId != hike.sessionId ||
            !stateLiveLocationNotificationStatusShownSessionIds.add(
              hike.sessionId,
            )) {
          return;
        }
        unawaited(
          effectShowHikeNotice(
            hike.sessionId,
            'Hike tracking and the live link are active, but SOS contacts were not notified yet. ${error.message}',
            title: 'Live sharing',
          ),
        );
      }
    }
  }

  /// Computes live location configuration for.
  ({
    String ownerPhoneNumber,
    String sessionId,
    bool sharing,
    int intervalSeconds,
  })
  commandLiveLocationConfigurationFor(ActiveHikeSession hike) => (
    ownerPhoneNumber: readSession().phoneNumber,
    sessionId: hike.sessionId,
    sharing: hike.draft.shareLiveLocation,
    intervalSeconds: hike.draft.locationRecordingInterval.inSeconds,
  );

  /// Stops active hike monitoring heartbeat.
  void commandStopActiveHikeMonitoringHeartbeat() {
    stateActiveHikeMonitoringHeartbeatTimer?.cancel();
    stateActiveHikeMonitoringHeartbeatTimer = null;
    stateActiveHikeMonitoringSessionId = null;
  }

  /// Sends active hike monitoring heartbeat.
  Future<void> commandSendActiveHikeMonitoringHeartbeat(
    ActiveHikeSession hike, {
    required String lifecycleState,
  }) async {
    try {
      await stateHikerCircleRepository.updateActiveHikeMonitoringHeartbeat(
        session: readSession(),
        activeHike: hike,
        lifecycleState: lifecycleState,
        fcmToken: stateFcmToken,
      );
    } catch (error) {
      debugPrint('Unable to update active hike monitoring heartbeat: $error');
    }
  }

  /// Computes signal potential app termination.
  Future<void> commandSignalPotentialAppTermination(
    ActiveHikeSession hike,
  ) async {
    try {
      await stateHikerCircleRepository.signalActiveHikePotentialTermination(
        session: readSession(),
        activeHike: hike,
        fcmToken: stateFcmToken,
      );
    } catch (error) {
      debugPrint('Unable to send active hike termination signal: $error');
    }
  }

  /// Synchronizes team hike session watch.
  void commandSyncTeamHikeSessionWatch(ActiveHikeSession? hike) {
    final teamHikeSessionId = hike?.teamHikeSessionId ?? '';
    if (teamHikeSessionId.isEmpty) {
      stateTeamHikeSessionSubscription?.cancel();
      stateTeamHikeSessionSubscription = null;
      stateTeamHikeWatchSessionId = null;
      return;
    }
    if (stateTeamHikeWatchSessionId == teamHikeSessionId &&
        stateTeamHikeSessionSubscription != null) {
      return;
    }

    stateTeamHikeSessionSubscription?.cancel();
    stateTeamHikeWatchSessionId = teamHikeSessionId;
    stateTeamHikeSessionSubscription = stateHikerCircleRepository
        .watchTeamHikeSession(teamHikeSessionId)
        .listen(
          (teamSession) {
            if (!mounted || teamSession == null) {
              return;
            }
            final currentHike = stateActiveHike;
            if (currentHike == null ||
                currentHike.teamHikeSessionId != teamSession.id) {
              return;
            }
            final updatedHike = commandWithTeamHikeSessionLink(
              currentHike,
              teamSession,
            );
            _publish(() {
              stateActiveHike = updatedHike;
            });
            commandPersistActiveHikeSnapshot(updatedHike);
            final pingKey = TeamPingPolicy.pendingKey(
              teamSession,
              readSession().phoneNumber,
              DateTime.now(),
            );
            if (pingKey != null) {
              commandEnqueueFcmOpen(
                _PendingFcmOpen(
                  key: 'team-ping:$pingKey',
                  title: 'Your team is checking on you',
                  body: 'Please confirm that you are OK.',
                  deepLink: Uri(
                    scheme: 'hikercircle',
                    host: 'team-hike',
                    path: '/ping',
                    queryParameters: {'teamSessionId': teamSession.id},
                  ).toString(),
                ),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Team hike updates are unavailable: $error');
          },
        );
  }

  /// Starts active hike location recording.
  void commandStartActiveHikeLocationRecording(ActiveHikeSession hike) {
    final interval = commandEffectiveActiveHikeRecordingInterval(hike);
    final uploadInterval =
        hike.draft.locationRecordingInterval < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : hike.draft.locationRecordingInterval;
    const monitorInterval = Duration(seconds: 5);
    final isSameRecordingLoop =
        stateActiveHikeRecordingTimer?.isActive == true &&
        stateActiveHikeRecordingSessionId == hike.sessionId &&
        stateActiveHikeRecordingInterval == interval &&
        stateActiveHikeUploadInterval == uploadInterval;
    if (isSameRecordingLoop) {
      return;
    }

    stateActiveHikeRecordingTimer?.cancel();
    stateActiveHikeUploadTimer?.cancel();
    stateActiveHikeUploadInterval = uploadInterval;
    stateActiveHikeUploadTimer = Timer.periodic(
      uploadInterval,
      (_) => unawaited(effectUploadActiveHikeLocations()),
    );
    unawaited(
      commandRunReconnectStep(
        'native GPS transfer',
        () => commandDrainNativeLocationSamples(hike),
      ),
    );
    stateActiveHikeRecordingSessionId = hike.sessionId;
    stateActiveHikeRecordingInterval = interval;
    stateStationaryWatchReferenceLocation = null;
    stateStationaryWatchReferenceAccuracyMeters = null;
    stateStationaryWatchStartedAt = null;
    stateIsStationaryLocationWatchActive = false;
    LocationSnapshotService.instance.setRefreshInterval(
      commandSnapshotIntervalForActiveHike(interval),
    );
    stateActiveHikeRecordingTimer = Timer.periodic(monitorInterval, (_) {
      unawaited(effectRecordActiveHikeLocationTick());
    });
  }

  /// Stops active hike location recording.
  void commandStopActiveHikeLocationRecording() {
    stateActiveHikeRecordingTimer?.cancel();
    stateActiveHikeRecordingTimer = null;
    stateActiveHikeUploadTimer?.cancel();
    stateActiveHikeUploadTimer = null;
    stateActiveHikeUploadInterval = null;
    stateActiveHikeRecordingSessionId = null;
    stateActiveHikeRecordingInterval = null;
    stateLastActiveHikeLocationRecordedAt = null;
    stateLastActiveHikeLiveStatusSentAt = null;
    stateStationaryWatchReferenceLocation = null;
    stateStationaryWatchReferenceAccuracyMeters = null;
    stateStationaryWatchStartedAt = null;
    stateIsStationaryLocationWatchActive = false;
    LocationSnapshotService.instance.setRefreshInterval(
      LiveLocationSharingService.instance.isActive
          ? LiveLocationSharingService.instance.updateInterval
          : LocationSnapshotService.passiveSnapshotInterval,
    );
    stateIsRecordingActiveHikeLocation = false;
  }

  /// Computes snapshot interval for active hike.
  Duration commandSnapshotIntervalForActiveHike(Duration recordingInterval) =>
      recordingInterval;

  /// Computes effective active hike recording interval.
  Duration commandEffectiveActiveHikeRecordingInterval(
    ActiveHikeSession hike,
  ) => LocationUpdateInterval.normalize(hike.draft.locationRecordingInterval);

  /// Merge durable native samples by capture time while preserving newer pins, battery and team updates.
  Future<void> commandDrainNativeLocationSamples(ActiveHikeSession hike) async {
    await stateHikerCircleRepository.drainNativeLocationSamples(
      session: readSession(),
      sessionId: hike.sessionId,
    );
    final latest = stateActiveHike;
    if (latest == null || latest.sessionId != hike.sessionId) {
      return;
    }
    final merged = await stateHikerCircleRepository.mergeStoredRoute(
      session: readSession(),
      activeHike: latest,
    );
    if (!mounted || stateActiveHike?.sessionId != hike.sessionId) {
      return;
    }
    // Only replace route fields; pins, battery and team updates may have changed.
    final current = stateActiveHike!;
    final route = <int, HikeCoordinate>{
      for (final p in merged.routePoints)
        p.capturedAt.millisecondsSinceEpoch: p,
      for (final p in current.routePoints)
        p.capturedAt.millisecondsSinceEpoch: p,
    }.values.toList()..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final updated = current.copyWith(
      routePoints: route,
      latestLocation: route.isEmpty ? current.latestLocation : route.last,
    );
    _publish(() => stateActiveHike = updated);
    commandPersistActiveHikeSnapshot(updated);
    final location = updated.latestLocation;
    if (location != null) {
      LiveLocationSharingService.instance.recordHikeLocation(
        SosTriggerLocation(
          latitude: location.latitude,
          longitude: location.longitude,
          accuracyMeters: location.accuracyMeters,
          capturedAt: location.capturedAt,
        ),
      );
    }
  }

  /// Checks whether active hike location record due.
  bool commandIsActiveHikeLocationRecordDue(ActiveHikeSession hike) {
    final lastRecordedAt = stateLastActiveHikeLocationRecordedAt;
    if (lastRecordedAt == null) {
      return true;
    }

    return DateTime.now().difference(lastRecordedAt) >=
        commandEffectiveActiveHikeRecordingInterval(hike);
  }

  /// Checks whether acceptable tracking location.
  bool commandIsAcceptableTrackingLocation(
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
    if (capturedAt == null) {
      return false;
    }
    final now = DateTime.now().toUtc();
    if (capturedAt.isAfter(now.add(const Duration(minutes: 2))) ||
        now.difference(capturedAt) > const Duration(seconds: 30)) {
      return false;
    }

    final previous = hike.latestLocation;
    if (previous == null) {
      return true;
    }
    final elapsedSeconds =
        capturedAt.difference(previous.capturedAt.toUtc()).inMilliseconds /
        1000;
    if (elapsedSeconds < -5) {
      return false;
    }
    if (elapsedSeconds <= 0) {
      return true;
    }
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

  /// Combine the selected off-route distance with GPS uncertainty before issuing a path-deviation warning.
  void commandEvaluatePathDeviation(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double? accuracyMeters,
  ) {
    if (!hike.draft.pathDeviationEnabled) {
      statePathDeviationStartedAt = null;
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
    if (route.length < 2) {
      return;
    }

    var nearestMeters = double.infinity;
    for (var index = 1; index < route.length; index++) {
      nearestMeters = math.min(
        nearestMeters,
        commandDistanceToRouteSegment(
          coordinate,
          route[index - 1],
          route[index],
        ),
      );
    }
    final thresholdMeters = PathDeviationPolicy.effectiveThreshold(
      selectedDistanceMeters: hike.draft.pathDeviationDistanceMeters,
      accuracyMeters: accuracyMeters,
    );
    final now = DateTime.now().toUtc();
    if (!nearestMeters.isFinite || nearestMeters <= thresholdMeters) {
      statePathDeviationStartedAt = null;
      return;
    }
    statePathDeviationStartedAt ??= now;
    if (now.difference(statePathDeviationStartedAt!) <
        const Duration(minutes: 2)) {
      return;
    }
    final lastAlert = stateLastPathDeviationAlertAt;
    if (lastAlert != null &&
        now.difference(lastAlert) < const Duration(minutes: 15)) {
      return;
    }
    stateLastPathDeviationAlertAt = now;
    unawaited(
      effectEmitPathDeviationAlert(
        hike,
        coordinate,
        nearestMeters,
      ).catchError((_) {}),
    );
  }

  /// Computes distance to route segment.
  double commandDistanceToRouteSegment(
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
    if (lengthSquared <= 0) {
      return math.sqrt(startX * startX + startY * startY);
    }
    final projection = (-(startX * dx + startY * dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    final closestX = startX + projection * dx;
    final closestY = startY + projection * dy;
    return math.sqrt(closestX * closestX + closestY * closestY);
  }

  /// Computes evaluate stationary location watch.
  void commandEvaluateStationaryLocationWatch(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double? accuracyMeters,
  ) {
    final stationaryTriggerDuration =
        hike.draft.fallDetectionSettings.longestRestDuration;
    final now = DateTime.now();
    final reference = stateStationaryWatchReferenceLocation;
    final referenceAccuracy = stateStationaryWatchReferenceAccuracyMeters ?? 0;
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
      stateStationaryWatchReferenceLocation = coordinate;
      stateStationaryWatchReferenceAccuracyMeters = currentAccuracy;
      stateStationaryWatchStartedAt = now;
      if (stateIsStationaryLocationWatchActive) {
        stateFallStillnessMonitor.cancelStationaryLocationWatch(
          'New location recorded',
        );
        stateIsStationaryLocationWatchActive = false;
      }
      return;
    }

    if (currentAccuracy > 0 &&
        (referenceAccuracy <= 0 || currentAccuracy < referenceAccuracy)) {
      stateStationaryWatchReferenceLocation = coordinate;
      stateStationaryWatchReferenceAccuracyMeters = currentAccuracy;
    }

    stateStationaryWatchStartedAt ??= now;
    if (stateIsStationaryLocationWatchActive ||
        now.difference(stateStationaryWatchStartedAt!) <
            stationaryTriggerDuration) {
      return;
    }

    stateFallStillnessMonitor.beginStationaryLocationWatch(
      hike.draft.fallDetectionSettings,
    );
    stateIsStationaryLocationWatchActive = true;
  }

  /// Synchronizes team hike location.
  void commandSyncTeamHikeLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location,
  ) {
    if (hike.teamHikeSessionId.isEmpty) {
      return;
    }
    unawaited(() async {
      try {
        final teamSession = await stateHikerCircleRepository
            .syncTeamHikeParticipantLocation(
              session: readSession(),
              activeHike: hike,
              location: location,
            );
        if (!mounted || teamSession == null) {
          return;
        }
        final currentHike = stateActiveHike;
        if (currentHike == null ||
            currentHike.teamHikeSessionId != teamSession.id) {
          return;
        }
        final updatedHike = commandWithTeamHikeSessionLink(
          currentHike,
          teamSession,
        );
        _publish(() {
          stateActiveHike = updatedHike;
        });
        commandPersistActiveHikeSnapshot(updatedHike);
      } catch (_) {
        // Team position sync should never stop the local tracking loop.
      }
    }());
  }

  /// Synchronizes ble team location.
  void commandSyncBleTeamLocation(ActiveHikeSession? _) {
    // The legacy team-location advertisement has no per-session MAC. Do not
    // broadcast private coordinates or use nearby packets as safety evidence
    // until the native protocol authenticates and replay-protects them.
    unawaited(stateBleService.stopTeamLocationExchange());
  }

  /// Handles ble team location.
  void commandHandleBleTeamLocation(HikerBleTeamLocationEvent _) {
    // Intentionally ignored: hashes and timestamps alone do not authenticate a
    // teammate. Cloud-authorized participant updates remain authoritative.
  }

  /// Records fall stillness cancel tap.
  void commandRecordFallStillnessCancelTap() {
    if (!stateFallStillnessMonitor.isAwaitingResponse) {
      stateFallStillnessCancelTaps.clear();
      return;
    }

    final now = DateTime.now();
    stateFallStillnessCancelTaps.removeWhere(
      (tapTime) => now.difference(tapTime) > const Duration(seconds: 2),
    );
    stateFallStillnessCancelTaps.add(now);
    if (stateFallStillnessCancelTaps.length >= 3) {
      stateFallStillnessCancelTaps.clear();
      commandCancelFallStillnessSos('Triple tap received');
    }
  }

  /// Cancels fall stillness sos.
  void commandCancelFallStillnessSos(String reason) {
    final triggered = stateSosPresentation.current;
    if (triggered != null) return; // Triggered alarms require the slider.
    unawaited(() async {
      try {
        await commandStopTriggeredSosOutputs();
        if (mounted) effectShowFallStillnessSnackBar('Safety alarm stopped.');
      } catch (_) {
        if (mounted) {
          effectShowFallStillnessSnackBar(
            'The alarm could not be stopped. Try again.',
            isError: true,
          );
        }
      }
    }());
  }

  /// Computes visible tabs.
  List<HikerBottomNavDestination> commandVisibleTabs() {
    if (stateActiveHike != null) {
      return stateTabs
          .where(
            (t) =>
                t.label == 'Home' || t.label == 'SOS' || t.label == 'Profile',
          )
          .toList();
    }
    return stateTabs;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<bool?> Function(SosAlertMode mode)
  effectPresentConfirmExternalSosTriggerEffect1;

  late final Future<bool?> Function() effectPresentRequestSignOutEffect1;

  late final Future<List<EmergencyContact>?> Function()
  effectPresentOpenEmergencyContactsEffect1;

  late final Future<void> Function()
  effectPresentOpenUndiscoveredTrailRequestsEffect1;

  late final Future<void> Function() effectPresentOpenFindHikeEffect1;

  late final Future<void> Function(UpcomingHike hike, {String? hazardId})
  effectCancelUpcomingHike;

  late final void Function() effectPresentScheduleAnotherTimeAfterHazardEffect1;

  late final Future<void> Function()
  effectPresentHandleFallStillnessCountdownStartedEffect1;

  late final void Function() effectPresentRescheduleExpiredHikeEffect1;

  late final Future<void> Function({bool signOutAfter})
  effectEndActiveHikeSession;

  late final Future<bool?> Function(bool isHost)
  effectPresentConfirmHazardCancellationEffect1;

  bool stateIsOpeningTrailRequests = false;

  bool stateIsFallStillnessDialogVisible = false;

  /// Computes confirm external sos trigger.
  Future<bool> commandConfirmExternalSosTrigger(SosAlertMode mode) async {
    if (!mounted) {
      return false;
    }
    return await effectPresentConfirmExternalSosTriggerEffect1(mode) ?? false;
  }

  /// Opens undiscovered trail requests.
  Future<void> commandOpenUndiscoveredTrailRequests() async {
    if (!readSession().isAdmin || stateIsOpeningTrailRequests) {
      return;
    }
    stateIsOpeningTrailRequests = true;
    try {
      await effectPresentOpenUndiscoveredTrailRequestsEffect1();
    } finally {
      stateIsOpeningTrailRequests = false;
    }
  }

  /// Computes confirm hazard cancellation.
  Future<bool> commandConfirmHazardCancellation(UpcomingHike hike) async {
    final isHost = _sameTeamPhone(hike.creatorPhone, readSession().phoneNumber);
    return await effectPresentConfirmHazardCancellationEffect1(isHost) ?? false;
  }

  /// Computes schedule another time after hazard.
  Future<void> commandScheduleAnotherTimeAfterHazard(
    Trail trail, {
    UpcomingHike? hike,
    String? hazardId,
  }) async {
    if (hike != null) {
      if (!await commandConfirmHazardCancellation(hike) || !mounted) return;
      await effectCancelUpcomingHike(hike, hazardId: hazardId);
    }
    if (!mounted) return;
    effectPresentScheduleAnotherTimeAfterHazardEffect1();
    await effectOpenStartHikeWizard(trail, startWithSchedule: true);
  }

  /// Computes reschedule expired hike.
  Future<void> commandRescheduleExpiredHike(UpcomingHike hike) async {
    Trail? trail = stateTrails
        .where((trail) => trail.trailId == hike.trailId)
        .firstOrNull;
    final savedTrail = hike.draft?.trail;
    if (trail == null && savedTrail?.trailId == hike.trailId) {
      trail = savedTrail;
    }
    if (trail == null) {
      final available = await stateHikerCircleRepository.loadTrails();
      trail = available
          .where((trail) => trail.trailId == hike.trailId)
          .firstOrNull;
    }
    if (!mounted) return;
    if (trail == null || trail.trailId != hike.trailId) {
      throw const HikerCircleFirebaseRepositoryException(
        'This trail is unavailable. Refresh your trails and try again.',
      );
    }
    effectPresentRescheduleExpiredHikeEffect1();
    await effectOpenStartHikeWizard(
      trail,
      startWithSchedule: true,
      rescheduleFrom: hike,
    );
  }

  /// Opens find hike.
  Future<void> commandOpenFindHike() async {
    await effectPresentOpenFindHikeEffect1();
  }

  /// Opens emergency contacts.
  Future<void> commandOpenEmergencyContacts() async {
    final contacts = await effectPresentOpenEmergencyContactsEffect1();

    if (contacts == null || !mounted) {
      return;
    }

    _publish(() {
      stateEmergencyContacts = contacts;
      effectRebuildPlannedHike();
    });
  }

  /// Computes request sign out.
  Future<void> commandRequestSignOut() async {
    if (stateIsEndingActiveHike) {
      return;
    }
    if (stateActiveHike != null) {
      final shouldEnd = await effectPresentRequestSignOutEffect1();
      if (shouldEnd == true) {
        await effectEndActiveHikeSession(signOutAfter: true);
      }
      return;
    }
    await commandPerformSignOut();
  }

  /// Handles fall stillness countdown started.
  Future<void> commandHandleFallStillnessCountdownStarted() async {
    final snapshot = stateFallStillnessMonitor.snapshot;
    final alertName = snapshot.isProlongedStillnessDetection
        ? 'Prolonged-stillness SOS'
        : 'Fall SOS';
    unawaited(HapticFeedback.heavyImpact());
    try {
      await stateSosDeviceAlertService.startFallStillnessCountdownVibration();
    } catch (_) {
      effectShowFallStillnessSnackBar(
        '$alertName countdown started, but vibration could not start.',
        isError: true,
      );
    }

    if (!mounted ||
        commandHasTriggeredSos ||
        stateIsFallStillnessDialogVisible) {
      return;
    }

    stateIsFallStillnessDialogVisible = true;
    await effectPresentHandleFallStillnessCountdownStartedEffect1();
    stateIsFallStillnessDialogVisible = false;
  }
}

/// Owns the state and non-visual actions of _BleNearbyProximityMap.
class _BleNearbyProximityMapStateViewModel extends ChangeNotifier {
  /// Creates ble nearby proximity map state view model.
  _BleNearbyProximityMapStateViewModel({required this.readRssi});
  final int? Function() readRssi;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  mapbox.MapboxMap? stateMapboxMap;

  mapbox.CircleAnnotationManager? stateCircleManager;

  mapbox.PolygonAnnotationManager? statePolygonManager;

  SosTriggerLocation? stateLocation;

  bool stateStyleLoaded = false;

  bool stateRefreshing = false;

  bool stateHasCentered = false;

  /// Returns command radius meters.
  double get commandRadiusMeters =>
      _HikerHomePageState._bleRangeMeters(readRssi() ?? -70);

  /// Returns command point.
  mapbox.Point? get commandPoint {
    final location = stateLocation;
    if (location == null) {
      return null;
    }
    return mapbox.Point(
      coordinates: mapbox.Position(location.longitude, location.latitude),
    );
  }

  /// Refreshes location.
  Future<void> commandRefreshLocation() async {
    if (stateRefreshing) {
      return;
    }
    stateRefreshing = true;
    try {
      final location = await LocationSnapshotService.instance.refresh();
      if (!mounted || location == null) {
        return;
      }
      _publish(() => stateLocation = location);
      await commandRender();
      await commandCenterOnce();
    } catch (error) {
      debugPrint('Unable to refresh the nearby SOS map: $error');
    } finally {
      stateRefreshing = false;
    }
  }

  /// Computes center once.
  Future<void> commandCenterOnce({bool force = false}) async {
    final point = commandPoint;
    final map = stateMapboxMap;
    if ((stateHasCentered && !force) || point == null || map == null) return;
    stateHasCentered = true;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          center: point,
          zoom: (16 - math.log(commandRadiusMeters / 50) / math.ln2).clamp(
            11,
            18,
          ),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      stateHasCentered = false;
    }
  }

  /// Prepares map style.
  Future<void> commandPrepareMapStyle() async {
    stateStyleLoaded = true;
    stateCircleManager = null;
    statePolygonManager = null;
    await commandEnsureManagers();
    await commandRender();
  }

  /// Ensures managers.
  Future<bool> commandEnsureManagers() async {
    if (stateMapboxMap == null || !stateStyleLoaded) {
      return false;
    }
    try {
      stateCircleManager ??= await stateMapboxMap!.annotations
          .createCircleAnnotationManager();
      statePolygonManager ??= await stateMapboxMap!.annotations
          .createPolygonAnnotationManager();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Computes ring.
  List<mapbox.Position> commandRing(double latitude, double longitude) {
    final radius = commandRadiusMeters;
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

  /// Computes render.
  Future<void> commandRender() async {
    if (!await commandEnsureManagers()) {
      return;
    }
    final point = commandPoint;
    if (point == null) {
      return;
    }
    try {
      await stateCircleManager?.deleteAll();
      await statePolygonManager?.deleteAll();
      final latitude = point.coordinates[1]!.toDouble();
      final longitude = point.coordinates[0]!.toDouble();
      await statePolygonManager?.create(
        mapbox.PolygonAnnotationOptions(
          geometry: mapbox.Polygon(
            coordinates: [commandRing(latitude, longitude)],
          ),
          fillColor: const Color(0xFF0A84FF).toARGB32(),
          fillOpacity: 0.14,
          fillOutlineColor: const Color(0xFF0A84FF).toARGB32(),
        ),
      );
      await stateCircleManager?.create(
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _BleSosHelpMap.
class _BleSosHelpMapStateViewModel extends ChangeNotifier {
  /// Creates ble sos help map state view model.
  _BleSosHelpMapStateViewModel({
    required this.readTargetLatitude,
    required this.readTargetLongitude,
  });
  final double Function() readTargetLatitude;
  final double Function() readTargetLongitude;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  mapbox.MapboxMap? stateMapboxMap;

  mapbox.CircleAnnotationManager? stateCircleManager;

  mapbox.PointAnnotationManager? statePointManager;

  mapbox.PolylineAnnotationManager? statePolylineManager;

  SosTriggerLocation? stateCurrentLocation;

  double? stateDistanceMeters;

  double? statePreviousDistanceMeters;

  bool stateStyleLoaded = false;

  bool stateIsRefreshingLocation = false;

  int stateRenderGeneration = 0;

  bool stateHasFitted = false;

  /// Returns command target point.
  mapbox.Point get commandTargetPoint => mapbox.Point(
    coordinates: mapbox.Position(readTargetLongitude(), readTargetLatitude()),
  );

  /// Returns command current point.
  mapbox.Point? get commandCurrentPoint {
    final location = stateCurrentLocation;
    if (location == null) {
      return null;
    }
    return mapbox.Point(
      coordinates: mapbox.Position(location.longitude, location.latitude),
    );
  }

  /// Refreshes location.
  Future<void> commandRefreshLocation() async {
    if (stateIsRefreshingLocation) {
      return;
    }
    stateIsRefreshingLocation = true;
    try {
      final location = await LocationSnapshotService.instance.refresh();
      if (!mounted || location == null) {
        return;
      }
      final nextDistance = distanceMeters(
        commandTargetPoint,
        mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        ),
      );
      _publish(() {
        statePreviousDistanceMeters = stateDistanceMeters;
        stateCurrentLocation = location;
        stateDistanceMeters = nextDistance;
      });
      await commandRenderMarkers();
      if (!stateHasFitted) await commandFitMap();
    } catch (error) {
      debugPrint('Unable to refresh the SOS help map: $error');
    } finally {
      stateIsRefreshingLocation = false;
    }
  }

  /// Prepares map style.
  Future<void> commandPrepareMapStyle() async {
    stateStyleLoaded = true;
    stateCircleManager = null;
    statePointManager = null;
    statePolylineManager = null;
    stateRenderGeneration++;
    await commandEnsureAnnotationManagers();
    await commandRenderMarkers();
  }

  /// Ensures annotation managers.
  Future<bool> commandEnsureAnnotationManagers() async {
    final map = stateMapboxMap;
    if (map == null || !stateStyleLoaded) {
      return false;
    }
    try {
      stateCircleManager ??= await map.annotations
          .createCircleAnnotationManager();
      statePointManager ??= await map.annotations
          .createPointAnnotationManager();
      statePolylineManager ??= await map.annotations
          .createPolylineAnnotationManager();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Computes render markers.
  Future<void> commandRenderMarkers() async {
    if (!await commandEnsureAnnotationManagers()) {
      return;
    }
    final generation = ++stateRenderGeneration;
    final target = commandTargetPoint;
    final current = commandCurrentPoint;
    try {
      await stateCircleManager?.deleteAll();
      await statePointManager?.deleteAll();
      await statePolylineManager?.deleteAll();
      if (!mounted || generation != stateRenderGeneration) {
        return;
      }

      if (current != null) {
        await statePolylineManager?.create(
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
        if (current != null && stateCurrentLocation?.accuracyMeters != null)
          mapbox.CircleAnnotationOptions(
            geometry: current,
            circleColor: const Color(0xFF0A84FF).toARGB32(),
            circleOpacity: 0.12,
            circleRadius: (stateCurrentLocation!.accuracyMeters! / 8).clamp(
              12,
              42,
            ),
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
      await stateCircleManager?.createMulti(circles);
      await statePointManager?.create(
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
    } catch (_) {}
  }

  /// Computes fit map.
  Future<void> commandFitMap() async {
    final map = stateMapboxMap;
    if (map == null) {
      return;
    }
    final points = [
      commandTargetPoint,
      if (commandCurrentPoint != null) commandCurrentPoint!,
    ];
    stateHasFitted = commandCurrentPoint != null;
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

  /// Returns command distance label.
  String get commandDistanceLabel {
    final distance = stateDistanceMeters;
    if (distance == null) {
      return 'Getting your location...';
    }
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(2)} km away';
    }
    return '${distance.round()} m away';
  }

  /// Returns command approach label.
  String get commandApproachLabel {
    final current = stateDistanceMeters;
    final previous = statePreviousDistanceMeters;
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _TeamHikeLaunchPage.
class _TeamHikeLaunchPageStateViewModel extends ChangeNotifier {
  /// Creates team hike launch page state view model.
  _TeamHikeLaunchPageStateViewModel({
    required this.readInitialTeamSession,
    required this.readRepository,
    required this.readSession,
    required this.effectActivateAndClose,
    required this.effectCloseWhenReady,
    required this.effectMarkCurrentParticipantReady,
  });
  final TeamHikeSession Function() readInitialTeamSession;
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  final Future<void> Function(TeamHikeSession teamSession)
  effectActivateAndClose;
  final void Function(TeamHikeSession teamSession) effectCloseWhenReady;
  final Future<void> Function(TeamHikeSession teamSession)
  effectMarkCurrentParticipantReady;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  bool stateIsMarkingReady = false;

  bool stateIsActivating = false;

  bool stateIsPollingTeam = false;

  late TeamHikeSession stateLatestTeamSession;

  /// Saves this account's personal launch draft locally before publishing Ready.
  Future<void> commandSavePreparedDraft(HikeSessionDraft draft) =>
      readRepository().localDatabase.saveLocalPreference(
        ownerPhoneNumber: readSession().phoneNumber,
        key: 'team_prepared:${readInitialTeamSession().id}',
        value: draft.toPersistence(),
      );

  /// Restores a matching confirmed draft after app termination; another member's checks are never reused.
  Future<HikeSessionDraft?> commandRestorePreparedDraft() async {
    try {
      final raw = await readRepository().localDatabase.loadLocalPreference(
        ownerPhoneNumber: readSession().phoneNumber,
        key: 'team_prepared:${readInitialTeamSession().id}',
      );
      if (raw is! Map) return null;
      final draft = HikeSessionDraft.fromPersistence(
        Map<String, dynamic>.from(raw),
      );
      return draft.trail.trailId == readInitialTeamSession().trailId
          ? draft
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Computes poll team session.
  Future<void> commandPollTeamSession() async {
    if (stateIsPollingTeam || !mounted) {
      return;
    }
    stateIsPollingTeam = true;
    try {
      final refreshed = await readRepository().loadTeamHikeSession(
        readInitialTeamSession().id,
      );
      if (!mounted || refreshed == null) {
        return;
      }
      if (commandIsNewerTeamState(refreshed, stateLatestTeamSession)) {
        _publish(() => stateLatestTeamSession = refreshed);
      }
      effectCloseWhenReady(refreshed);
    } catch (_) {
      // Firestore remains the primary real-time channel. Polling is a recovery
      // path for delayed listeners and temporary cache-only snapshots.
    } finally {
      stateIsPollingTeam = false;
    }
  }

  /// Checks whether newer team state.
  bool commandIsNewerTeamState(
    TeamHikeSession candidate,
    TeamHikeSession current,
  ) {
    final candidateUpdated = candidate.updatedAt;
    final currentUpdated = current.updatedAt;
    if (candidateUpdated != null &&
        currentUpdated != null &&
        candidateUpdated != currentUpdated) {
      // A participant withdrawing can legitimately reset countdown to READY.
      return candidateUpdated.isAfter(currentUpdated);
    }
    const phaseOrder = <TeamHikePhase, int>{
      TeamHikePhase.inviting: 0,
      TeamHikePhase.readyCheck: 1,
      TeamHikePhase.countdown: 2,
      TeamHikePhase.active: 3,
      TeamHikePhase.completed: 4,
    };
    final candidatePhase = phaseOrder[candidate.phase] ?? 0;
    final currentPhase = phaseOrder[current.phase] ?? 0;
    if (candidatePhase != currentPhase) {
      return candidatePhase > currentPhase;
    }
    return candidate.readyCount != current.readyCount ||
        candidate.participants.length != current.participants.length;
  }

  /// Computes visible team session.
  TeamHikeSession commandVisibleTeamSession(TeamHikeSession? streamed) {
    if (streamed == null) {
      return stateLatestTeamSession;
    }
    return commandIsNewerTeamState(streamed, stateLatestTeamSession)
        ? streamed
        : stateLatestTeamSession;
  }

  /// Computes launch subtitle.
  String commandLaunchSubtitle(TeamHikeSession teamSession) {
    if (teamSession.phase == TeamHikePhase.countdown) {
      return 'Everyone is ready. Starting together in ${teamSession.countdownRemainingSeconds} seconds.';
    }
    if (teamSession.invitedCount > 0) {
      return '${teamSession.invitedCount} buddy invite${teamSession.invitedCount == 1 ? '' : 's'} still need to be opened before READY appears.';
    }
    return 'The team hike session is going to start. Press READY when your gear and GPS are set.';
  }

  /// Computes ready button label.
  String commandReadyButtonLabel(TeamHikeSession teamSession) {
    final participant = commandCurrentParticipant(teamSession);
    final isHost = _sameTeamPhone(
      teamSession.hostPhoneNumber,
      readSession().phoneNumber,
    );
    if (teamSession.phase == TeamHikePhase.countdown) {
      return 'STARTING';
    }
    if (participant?.status.isReadyForStart == true) {
      return isHost ? 'START HIKE' : 'READY SENT';
    }
    return 'READY';
  }

  /// Computes ready button subtitle.
  String commandReadyButtonSubtitle(TeamHikeSession teamSession) {
    final participant = commandCurrentParticipant(teamSession);
    final isHost = _sameTeamPhone(
      teamSession.hostPhoneNumber,
      readSession().phoneNumber,
    );
    if (teamSession.phase == TeamHikePhase.countdown) {
      return commandLaunchSubtitle(teamSession);
    }
    if (participant?.status.isReadyForStart == true) {
      return isHost
          ? 'Start when everyone is ready'
          : 'Waiting for the host to start';
    }
    return 'press when ready';
  }

  /// Checks whether it can mark ready.
  bool commandCanMarkReady(TeamHikeSession teamSession) {
    if (stateIsMarkingReady ||
        teamSession.phase == TeamHikePhase.countdown ||
        teamSession.phase == TeamHikePhase.active) {
      return false;
    }
    final participant = commandCurrentParticipant(teamSession);
    return participant?.status.isReadyForStart != true;
  }

  /// Checks whether it can press button.
  bool commandCanPressButton(TeamHikeSession teamSession) {
    final participant = commandCurrentParticipant(teamSession);
    if (participant?.status.isReadyForStart == true) {
      final isHost = _sameTeamPhone(
        teamSession.hostPhoneNumber,
        readSession().phoneNumber,
      );
      return isHost &&
          teamSession.phase == TeamHikePhase.readyCheck &&
          teamSession.everyoneReady;
    }
    return commandCanMarkReady(teamSession);
  }

  /// Computes on button pressed.
  Future<void> commandOnButtonPressed(TeamHikeSession teamSession) async {
    final participant = commandCurrentParticipant(teamSession);
    if (participant?.status.isReadyForStart == true) {
      final isHost = _sameTeamPhone(
        teamSession.hostPhoneNumber,
        readSession().phoneNumber,
      );
      if (isHost) {
        _publish(() => stateIsActivating = true);
        await effectActivateAndClose(teamSession);
      }
      return;
    }
    await effectMarkCurrentParticipantReady(teamSession);
  }

  /// Computes current participant.
  TeamHikeParticipant? commandCurrentParticipant(TeamHikeSession teamSession) {
    for (final participant in teamSession.participants) {
      if (_sameTeamPhone(participant.phoneNumber, readSession().phoneNumber)) {
        return participant;
      }
    }
    return null;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _HikeSummaryReportPage.
class _HikeSummaryReportPageStateViewModel extends ChangeNotifier {
  /// Creates hike summary report page state view model.
  _HikeSummaryReportPageStateViewModel({required this.readActiveHike});
  final ActiveHikeSession Function() readActiveHike;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Returns command route analysis.
  HikeRouteAnalysis get commandRouteAnalysis => analyzeHikeRoute(
    routePoints: readActiveHike().routePoints,
    fallbackStartedAt: readActiveHike().startedAt,
    checkpoints: readActiveHike().trail.checkpoints
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

  /// Formats report duration.
  String commandFormatReportDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  /// Computes coordinate label.
  String commandCoordinateLabel(HikeCoordinate? coordinate) {
    if (coordinate == null) {
      return 'Location unavailable';
    }
    return '${coordinate.latitude.toStringAsFixed(5)}, '
        '${coordinate.longitude.toStringAsFixed(5)}';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of ActiveHikeHomePage.
class _ActiveHikeHomePageStateViewModel extends ChangeNotifier {
  /// Creates active hike home page state view model.
  _ActiveHikeHomePageStateViewModel();

  var stateMapMode = ActiveHikeMapMode.normal;

  /// Changes only the live map viewpoint; recording and safety stay active.
  void commandToggleMapMode() {
    if (!mounted) return;
    _publish(() {
      stateMapMode = stateMapMode == ActiveHikeMapMode.normal
          ? ActiveHikeMapMode.firstPerson
          : ActiveHikeMapMode.normal;
    });
  }

  /// Starts each new hiking session in its ordinary map view.
  void commandResetMapMode() {
    if (mounted) _publish(() => stateMapMode = ActiveHikeMapMode.normal);
  }

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  /// Computes weather changed.
  void commandWeatherChanged() {
    if (mounted) _publish(() {});
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
