part of '../hiker_home_page_feature.dart';

/// Displays the hiker home page.
class HikerHomePage extends StatefulWidget {
  /// Creates hiker home page.
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

  /// Creates the presentation state for this widget.
  @override
  State<HikerHomePage> createState() => _HikerHomePageState();
}

/// Manages the hiker home page presentation and lifecycle.
class _HikerHomePageState extends State<HikerHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Returns is fall stillness dialog visible.
  bool get isFallStillnessDialogVisible =>
      _screenModel.stateIsFallStillnessDialogVisible;

  /// Updates is fall stillness dialog visible.
  set isFallStillnessDialogVisible(bool value) =>
      _screenModel.stateIsFallStillnessDialogVisible = value;

  late final _HikerHomePageStateViewModel _screenModel;

  /// Returns trails.
  List<Trail> get trails => _screenModel.stateTrails;

  /// Updates trails.
  set trails(List<Trail> value) => _screenModel.stateTrails = value;

  /// Returns hiker circle repository.
  HikerCircleFirebaseRepository get hikerCircleRepository =>
      _screenModel.stateHikerCircleRepository;

  /// Updates hiker circle repository.
  set hikerCircleRepository(HikerCircleFirebaseRepository value) =>
      _screenModel.stateHikerCircleRepository = value;

  /// Returns emergency contacts repository.
  EmergencyContactsRepository get emergencyContactsRepository =>
      _screenModel.stateEmergencyContactsRepository;

  /// Updates emergency contacts repository.
  set emergencyContactsRepository(EmergencyContactsRepository value) =>
      _screenModel.stateEmergencyContactsRepository = value;

  /// Returns sos alert repository.
  SosAlertRepository get sosAlertRepository =>
      _screenModel.stateSosAlertRepository;

  /// Updates sos alert repository.
  set sosAlertRepository(SosAlertRepository value) =>
      _screenModel.stateSosAlertRepository = value;

  /// Returns queued sos count.
  int get _queuedSosCount => _screenModel.stateQueuedSosCount;

  /// Returns nearby sos event repository.
  NearbySosEventRepository get nearbySosEventRepository =>
      _screenModel.stateNearbySosEventRepository;

  /// Updates nearby sos event repository.
  set nearbySosEventRepository(NearbySosEventRepository value) =>
      _screenModel.stateNearbySosEventRepository = value;

  /// Returns fall stillness monitor.
  FallStillnessMonitor get fallStillnessMonitor =>
      _screenModel.stateFallStillnessMonitor;

  /// Updates fall stillness monitor.
  set fallStillnessMonitor(FallStillnessMonitor value) =>
      _screenModel.stateFallStillnessMonitor = value;

  /// Returns sos device alert service.
  SosDeviceAlertService get _sosDeviceAlertService =>
      _screenModel.stateSosDeviceAlertService;

  /// Returns sos presentation.
  SosPresentationController get _sosPresentation =>
      _screenModel.stateSosPresentation;

  /// Returns native sos presentation ids.
  Map<String, int> get _nativeSosPresentationIds =>
      _screenModel.stateNativeSosPresentationIds;

  /// Returns stopped native sos presentation ids.
  Set<String> get _stoppedNativeSosPresentationIds =>
      _screenModel.stateStoppedNativeSosPresentationIds;

  /// Returns sos presentation waiters.
  Set<Completer<void>> get _sosPresentationWaiters =>
      _screenModel.stateSosPresentationWaiters;

  /// Returns active hike live status service.
  ActiveHikeLiveStatusService get _activeHikeLiveStatusService =>
      _screenModel.stateActiveHikeLiveStatusService;

  /// Returns ble service.
  HikerBleService get _bleService => _screenModel.stateBleService;

  /// Returns my upcoming hikes subscription.
  StreamSubscription<List<UpcomingHike>>? get _myUpcomingHikesSubscription =>
      _screenModel.stateMyUpcomingHikesSubscription;

  /// Updates hike reminders.
  set _hikeReminders(UpcomingHikeReminderService value) =>
      _screenModel.stateHikeReminders = value;

  /// Returns trails subscription.
  StreamSubscription<List<Trail>>? get _trailsSubscription =>
      _screenModel.stateTrailsSubscription;

  /// Returns ble event subscription.
  StreamSubscription<HikerBleEvent>? get _bleEventSubscription =>
      _screenModel.stateBleEventSubscription;

  /// Returns formed team chats subscription.
  StreamSubscription<List<GroupChat>>? get _formedTeamChatsSubscription =>
      _screenModel.stateFormedTeamChatsSubscription;

  /// Returns team readiness subscription.
  StreamSubscription<List<TeamHikeSession>>? get _teamReadinessSubscription =>
      _screenModel.stateTeamReadinessSubscription;

  /// Returns pending team readiness sessions.
  Map<String, TeamHikeSession> get _pendingTeamReadinessSessions =>
      _screenModel.statePendingTeamReadinessSessions;

  /// Returns presented team readiness keys.
  Set<String> get _presentedTeamReadinessKeys =>
      _screenModel.statePresentedTeamReadinessKeys;

  /// Returns active upcoming join request review id.
  String? get _activeUpcomingJoinRequestReviewId =>
      _screenModel.stateActiveUpcomingJoinRequestReviewId;

  /// Updates active upcoming join request review id.
  set _activeUpcomingJoinRequestReviewId(String? value) =>
      _screenModel.stateActiveUpcomingJoinRequestReviewId = value;

  /// Returns pending formed team chats.
  List<GroupChat> get _pendingFormedTeamChats =>
      _screenModel.statePendingFormedTeamChats;

  /// Updates pending formed team chats.
  set _pendingFormedTeamChats(List<GroupChat> value) =>
      _screenModel.statePendingFormedTeamChats = value;

  /// Returns my upcoming hikes.
  List<UpcomingHike> get myUpcomingHikes => _screenModel.stateMyUpcomingHikes;

  /// Updates my upcoming hikes.
  set myUpcomingHikes(List<UpcomingHike> value) =>
      _screenModel.stateMyUpcomingHikes = value;

  /// Returns planned checklist by upcoming id.
  Map<String, Set<String>> get _plannedChecklistByUpcomingId =>
      _screenModel.statePlannedChecklistByUpcomingId;

  /// Returns consumed upcoming hike ids.
  Set<String> get _consumedUpcomingHikeIds =>
      _screenModel.stateConsumedUpcomingHikeIds;

  /// Updates consumed upcoming hike ids.
  set _consumedUpcomingHikeIds(Set<String> value) =>
      _screenModel.stateConsumedUpcomingHikeIds = value;

  /// Returns upcoming planning revision.
  int get _upcomingPlanningRevision =>
      _screenModel.stateUpcomingPlanningRevision;

  /// Updates upcoming planning revision.
  set _upcomingPlanningRevision(int value) =>
      _screenModel.stateUpcomingPlanningRevision = value;

  /// Returns latest phone battery level.
  int? get _latestPhoneBatteryLevel =>
      _screenModel.stateLatestPhoneBatteryLevel;

  /// Returns is loading live data.
  bool get isLoadingLiveData => _screenModel.stateIsLoadingLiveData;

  /// Updates is loading live data.
  set isLoadingLiveData(bool value) =>
      _screenModel.stateIsLoadingLiveData = value;

  /// Returns is sending fall stillness sos.
  bool get isSendingFallStillnessSos =>
      _screenModel.stateIsSendingFallStillnessSos;

  /// Updates is sending fall stillness sos.
  set isSendingFallStillnessSos(bool value) =>
      _screenModel.stateIsSendingFallStillnessSos = value;

  /// Returns is recording active hike location.
  bool get isRecordingActiveHikeLocation =>
      _screenModel.stateIsRecordingActiveHikeLocation;

  /// Updates is recording active hike location.
  set isRecordingActiveHikeLocation(bool value) =>
      _screenModel.stateIsRecordingActiveHikeLocation = value;

  /// Returns is ending active hike.
  bool get _isEndingActiveHike => _screenModel.stateIsEndingActiveHike;

  /// Updates is ending active hike.
  set _isEndingActiveHike(bool value) =>
      _screenModel.stateIsEndingActiveHike = value;

  /// Returns live location activated for active hike.
  bool get _liveLocationActivatedForActiveHike =>
      _screenModel.stateLiveLocationActivatedForActiveHike;

  /// Returns live location cloud configuration.
  ({
    String ownerPhoneNumber,
    String sessionId,
    bool sharing,
    int intervalSeconds,
  })?
  get _liveLocationCloudConfiguration =>
      _screenModel.stateLiveLocationCloudConfiguration;

  /// Updates live location cloud configuration.
  set _liveLocationCloudConfiguration(
    ({
      String ownerPhoneNumber,
      String sessionId,
      bool sharing,
      int intervalSeconds,
    })?
    value,
  ) => _screenModel.stateLiveLocationCloudConfiguration = value;

  /// Returns is fall stillness local alarm active.
  bool get isFallStillnessLocalAlarmActive =>
      _screenModel.stateIsFallStillnessLocalAlarmActive;

  /// Updates is fall stillness local alarm active.
  set isFallStillnessLocalAlarmActive(bool value) =>
      _screenModel.stateIsFallStillnessLocalAlarmActive = value;

  /// Returns active hike recording timer.
  Timer? get activeHikeRecordingTimer =>
      _screenModel.stateActiveHikeRecordingTimer;

  /// Updates active hike recording timer.
  set activeHikeRecordingTimer(Timer? value) =>
      _screenModel.stateActiveHikeRecordingTimer = value;

  /// Updates last manual sharing stop revision.
  set _lastManualSharingStopRevision(int value) =>
      _screenModel.stateLastManualSharingStopRevision = value;

  /// Updates last manual sharing start revision.
  set _lastManualSharingStartRevision(int value) =>
      _screenModel.stateLastManualSharingStartRevision = value;

  /// Returns active hike monitoring heartbeat timer.
  Timer? get activeHikeMonitoringHeartbeatTimer =>
      _screenModel.stateActiveHikeMonitoringHeartbeatTimer;

  /// Updates active hike monitoring heartbeat timer.
  set activeHikeMonitoringHeartbeatTimer(Timer? value) =>
      _screenModel.stateActiveHikeMonitoringHeartbeatTimer = value;

  /// Returns fcm token subscription.
  StreamSubscription<String>? get fcmTokenSubscription =>
      _screenModel.stateFcmTokenSubscription;

  /// Updates fcm token subscription.
  set fcmTokenSubscription(StreamSubscription<String>? value) =>
      _screenModel.stateFcmTokenSubscription = value;

  /// Returns fcm open subscription.
  StreamSubscription<RemoteMessage>? get fcmOpenSubscription =>
      _screenModel.stateFcmOpenSubscription;

  /// Updates fcm open subscription.
  set fcmOpenSubscription(StreamSubscription<RemoteMessage>? value) =>
      _screenModel.stateFcmOpenSubscription = value;

  /// Returns fcm foreground subscription.
  StreamSubscription<RemoteMessage>? get fcmForegroundSubscription =>
      _screenModel.stateFcmForegroundSubscription;

  /// Updates fcm foreground subscription.
  set fcmForegroundSubscription(StreamSubscription<RemoteMessage>? value) =>
      _screenModel.stateFcmForegroundSubscription = value;

  /// Returns local notifications.
  FlutterLocalNotificationsPlugin get _localNotifications =>
      _screenModel.stateLocalNotifications;

  /// Returns achievement notification delivery.
  AchievementNotificationDelivery get _achievementNotificationDelivery =>
      _screenModel.stateAchievementNotificationDelivery;

  /// Updates achievement notification delivery.
  set _achievementNotificationDelivery(AchievementNotificationDelivery value) =>
      _screenModel.stateAchievementNotificationDelivery = value;

  /// Returns achievement subscription.
  StreamSubscription<List<Map<String, dynamic>>>?
  get _achievementSubscription => _screenModel.stateAchievementSubscription;

  /// Returns pending fcm opens.
  List<_PendingFcmOpen> get _pendingFcmOpens =>
      _screenModel.statePendingFcmOpens;

  /// Returns handled fcm open keys.
  Set<String> get _handledFcmOpenKeys => _screenModel.stateHandledFcmOpenKeys;

  /// Returns pending ble ui events.
  List<HikerBleEvent> get _pendingBleUiEvents =>
      _screenModel.statePendingBleUiEvents;

  /// Returns active hike monitoring session id.
  String? get activeHikeMonitoringSessionId =>
      _screenModel.stateActiveHikeMonitoringSessionId;

  /// Updates active hike monitoring session id.
  set activeHikeMonitoringSessionId(String? value) =>
      _screenModel.stateActiveHikeMonitoringSessionId = value;

  /// Returns team hike session subscription.
  StreamSubscription<TeamHikeSession?>? get teamHikeSessionSubscription =>
      _screenModel.stateTeamHikeSessionSubscription;

  /// Updates team hike session subscription.
  set teamHikeSessionSubscription(
    StreamSubscription<TeamHikeSession?>? value,
  ) => _screenModel.stateTeamHikeSessionSubscription = value;

  /// Returns team hike watch session id.
  String? get teamHikeWatchSessionId =>
      _screenModel.stateTeamHikeWatchSessionId;

  /// Updates team hike watch session id.
  set teamHikeWatchSessionId(String? value) =>
      _screenModel.stateTeamHikeWatchSessionId = value;

  /// Returns active hike recording session id.
  String? get activeHikeRecordingSessionId =>
      _screenModel.stateActiveHikeRecordingSessionId;

  /// Updates active hike recording session id.
  set activeHikeRecordingSessionId(String? value) =>
      _screenModel.stateActiveHikeRecordingSessionId = value;

  /// Returns active hike recording interval.
  Duration? get activeHikeRecordingInterval =>
      _screenModel.stateActiveHikeRecordingInterval;

  /// Updates active hike recording interval.
  set activeHikeRecordingInterval(Duration? value) =>
      _screenModel.stateActiveHikeRecordingInterval = value;

  /// Returns last active hike location recorded at.
  DateTime? get lastActiveHikeLocationRecordedAt =>
      _screenModel.stateLastActiveHikeLocationRecordedAt;

  /// Updates last active hike location recorded at.
  set lastActiveHikeLocationRecordedAt(DateTime? value) =>
      _screenModel.stateLastActiveHikeLocationRecordedAt = value;

  /// Returns last active hike live status sent at.
  DateTime? get lastActiveHikeLiveStatusSentAt =>
      _screenModel.stateLastActiveHikeLiveStatusSentAt;

  /// Updates last active hike live status sent at.
  set lastActiveHikeLiveStatusSentAt(DateTime? value) =>
      _screenModel.stateLastActiveHikeLiveStatusSentAt = value;

  /// Updates path deviation started at.
  set _pathDeviationStartedAt(DateTime? value) =>
      _screenModel.statePathDeviationStartedAt = value;

  /// Updates last path deviation alert at.
  set _lastPathDeviationAlertAt(DateTime? value) =>
      _screenModel.stateLastPathDeviationAlertAt = value;

  /// Returns stationary watch reference location.
  HikeCoordinate? get stationaryWatchReferenceLocation =>
      _screenModel.stateStationaryWatchReferenceLocation;

  /// Updates stationary watch reference location.
  set stationaryWatchReferenceLocation(HikeCoordinate? value) =>
      _screenModel.stateStationaryWatchReferenceLocation = value;

  /// Returns stationary watch reference accuracy meters.
  double? get stationaryWatchReferenceAccuracyMeters =>
      _screenModel.stateStationaryWatchReferenceAccuracyMeters;

  /// Updates stationary watch reference accuracy meters.
  set stationaryWatchReferenceAccuracyMeters(double? value) =>
      _screenModel.stateStationaryWatchReferenceAccuracyMeters = value;

  /// Returns stationary watch started at.
  DateTime? get stationaryWatchStartedAt =>
      _screenModel.stateStationaryWatchStartedAt;

  /// Updates stationary watch started at.
  set stationaryWatchStartedAt(DateTime? value) =>
      _screenModel.stateStationaryWatchStartedAt = value;

  /// Returns is stationary location watch active.
  bool get isStationaryLocationWatchActive =>
      _screenModel.stateIsStationaryLocationWatchActive;

  /// Updates is stationary location watch active.
  set isStationaryLocationWatchActive(bool value) =>
      _screenModel.stateIsStationaryLocationWatchActive = value;

  /// Returns last fall stillness status.
  FallStillnessMonitorStatus get lastFallStillnessStatus =>
      _screenModel.stateLastFallStillnessStatus;

  /// Updates last fall stillness status.
  set lastFallStillnessStatus(FallStillnessMonitorStatus value) =>
      _screenModel.stateLastFallStillnessStatus = value;

  /// Returns active hike.
  ActiveHikeSession? get activeHike => _screenModel.stateActiveHike;

  /// Updates active hike.
  set activeHike(ActiveHikeSession? value) =>
      _screenModel.stateActiveHike = value;

  /// Updates active hike restore future.
  set _activeHikeRestoreFuture(Future<void>? value) =>
      _screenModel.stateActiveHikeRestoreFuture = value;

  /// Returns active hike persistence queue.
  Future<void> get _activeHikePersistenceQueue =>
      _screenModel.stateActiveHikePersistenceQueue;

  /// Returns emergency contacts load future.
  Future<void> get _emergencyContactsLoadFuture =>
      _screenModel.stateEmergencyContactsLoadFuture;

  /// Updates emergency contacts load future.
  set _emergencyContactsLoadFuture(Future<void> value) =>
      _screenModel.stateEmergencyContactsLoadFuture = value;

  /// Returns is native safety dialog visible.
  bool get isNativeSafetyDialogVisible =>
      _screenModel.stateIsNativeSafetyDialogVisible;

  /// Updates is native safety dialog visible.
  set isNativeSafetyDialogVisible(bool value) =>
      _screenModel.stateIsNativeSafetyDialogVisible = value;

  /// Returns active hike session id remaps.
  Map<String, String> get _activeHikeSessionIdRemaps =>
      _screenModel.stateActiveHikeSessionIdRemaps;

  /// Returns pending manual sos request id.
  int get _pendingManualSosRequestId =>
      _screenModel.statePendingManualSosRequestId;

  /// Updates pending manual sos request id.
  set _pendingManualSosRequestId(int value) =>
      _screenModel.statePendingManualSosRequestId = value;

  /// Returns pending immediate sos request id.
  int get _pendingImmediateSosRequestId =>
      _screenModel.statePendingImmediateSosRequestId;

  /// Updates pending immediate sos request id.
  set _pendingImmediateSosRequestId(int value) =>
      _screenModel.statePendingImmediateSosRequestId = value;

  /// Returns immediate sos request mode.
  SosAlertMode? get immediateSosRequestMode =>
      _screenModel.stateImmediateSosRequestMode;

  /// Updates immediate sos request mode.
  set immediateSosRequestMode(SosAlertMode? value) =>
      _screenModel.stateImmediateSosRequestMode = value;

  /// Returns immediate sos request trigger source.
  SosAlertTriggerSource get immediateSosRequestTriggerSource =>
      _screenModel.stateImmediateSosRequestTriggerSource;

  /// Updates immediate sos request trigger source.
  set immediateSosRequestTriggerSource(SosAlertTriggerSource value) =>
      _screenModel.stateImmediateSosRequestTriggerSource = value;

  /// Returns presented nearby sos keys.
  Set<String> get _presentedNearbySosKeys =>
      _screenModel.statePresentedNearbySosKeys;

  /// Returns presented exact nearby sos keys.
  Set<String> get _presentedExactNearbySosKeys =>
      _screenModel.statePresentedExactNearbySosKeys;

  /// Returns active approximate nearby sos keys.
  Set<String> get _activeApproximateNearbySosKeys =>
      _screenModel.stateActiveApproximateNearbySosKeys;

  /// Returns exact nearby sos locations.
  Map<String, SosTriggerLocation> get _exactNearbySosLocations =>
      _screenModel.stateExactNearbySosLocations;

  /// Returns nearby sos fallback timers.
  Map<String, Timer> get _nearbySosFallbackTimers =>
      _screenModel.stateNearbySosFallbackTimers;

  /// Returns nearby sos revision.
  int get _nearbySosRevision => _screenModel.stateNearbySosRevision;

  /// Returns fall stillness cancel taps.
  List<DateTime> get fallStillnessCancelTaps =>
      _screenModel.stateFallStillnessCancelTaps;

  /// Returns emergency contacts.
  List<EmergencyContact> get emergencyContacts =>
      _screenModel.stateEmergencyContacts;

  /// Updates emergency contacts.
  set emergencyContacts(List<EmergencyContact> value) =>
      _screenModel.stateEmergencyContacts = value;

  /// Returns tabs.
  List<HikerBottomNavDestination> get tabs => _screenModel.stateTabs;

  /// Updates tabs.
  set tabs(List<HikerBottomNavDestination> value) =>
      _screenModel.stateTabs = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const MethodChannel _deepLinkChannel = MethodChannel(
    'hiker_circle/deeplinks',
  );
  static const Duration _activeHikeLiveStatusThrottle = Duration(seconds: 20);

  late final TabController tabController;

  StreamSubscription<SosQueueChange>? _sosQueueSubscription;
  StreamSubscription<void>? _sosConnectionSubscription;

  final Set<int> _stoppingSosPresentationIds = {};

  /// Returns has triggered sos.
  bool get _hasTriggeredSos => _screenModel.commandHasTriggeredSos;

  StreamSubscription<String>? _planningChangesSubscription;

  Timer? _upcomingHikeExpiryTimer;

  StreamSubscription<bool>? _pendingTrailRequestsSubscription;
  bool _hasPendingUndiscoveredTrailRequests = false;

  StreamSubscription<NetworkReachabilitySnapshot>?
  _networkReachabilitySubscription;

  bool _isDrainingTeamReadiness = false;
  String? _activeTeamNamingChatId;

  final Set<String> _completedUpcomingJoinRequestReviewIds = <String>{};
  final Map<String, DateTime> _recentUpcomingJoinRequestAttempts =
      <String, DateTime>{};

  PlannedHike? plannedHike;

  late final _gearRouteService = RouteGearAnalysisService(
    database: hikerCircleRepository.localDatabase,
  );
  final _gearAnalysisRequests = <String>{};

  /// Computes analyze gear route.
  Future<RouteGearAssessment> _analyzeGearRoute(
    PlannedHike plan, {
    bool force = false,
  }) async {
    final result = await _gearRouteService.analyze(plan.trail, force: force);
    if (mounted) {
      setState(_rebuildPlannedHike);
    }
    return result;
  }

  Route<void>? _nativeSafetyCountdownRoute;
  String? _nativeSafetyCountdownEventId;

  bool _isOpeningHazardReport = false;

  late final _activeHikeCloudSyncOwner = widget.session.phoneNumber;
  late final _activeHikeCloudSync = ActiveHikeCloudSyncCoordinator(
    readCurrent: () =>
        mounted &&
            !_isEndingActiveHike &&
            widget.session.phoneNumber == _activeHikeCloudSyncOwner
        ? activeHike
        : null,
    ensure: (hike) => _HikerHomePageDataActions.ensureActiveHikeSessionInCloud(
      hikerCircleRepository,
    )(session: widget.session, activeHike: hike),
    apply: _applyActiveHikeCloudRestoreResult,
    onSynchronized: (hike) {
      _liveLocationCloudConfiguration = _liveLocationConfigurationFor(hike);
    },
  );

  bool fallStillnessCountdownWasBackgrounded = false;

  Completer<void>? _activeLocationWrite;
  final Set<String> _durablyDispatchedNativeSafetyEvents = {};
  Timer? _pendingHikeRetryTimer;
  bool _nativeHikeStopPending = false;

  Future<void> _hikeNoticeQueue = Future<void>.value();
  bool _isUploadingHikeLocations = false;
  StreamSubscription<EmergencyContactsChange>? _contactsChangeSubscription;
  Timer? _precautionTimer;
  bool _checkingPrecautions = false;
  String? _precautionSession;
  DateTime? _precautionCheckedAt;
  late final _hikeWarningSpeech = HikeWarningSpeechQueue(
    speak: (requestId, message) => _sosDeviceAlertService.speakHikePrecaution(
      requestId: requestId,
      message: message,
    ),
    stop: _sosDeviceAlertService.stopHikePrecaution,
  );
  late final _precautionAnnouncer = ActiveHikePrecautionAnnouncer(
    speak: (requestId, message) => _hikeWarningSpeech.enqueue(
      requestId: requestId,
      message: message,
      canSpeak: _canSpeakHikeWarning,
    ),
    stop: _hikeWarningSpeech.cancel,
  );

  /// Delegates can speak hike warning to the ViewModel.
  bool _canSpeakHikeWarning() => _screenModel.commandCanSpeakHikeWarning();

  /// Shows hike notice.
  Future<void> _showHikeNotice(
    String sessionId,
    String message, {
    String? title,
  }) {
    _hikeNoticeQueue = _hikeNoticeQueue
        .then((_) async {
          if (!mounted ||
              activeHike?.sessionId != sessionId ||
              _isEndingActiveHike ||
              fallStillnessMonitor.isAwaitingResponse ||
              isFallStillnessLocalAlarmActive ||
              isSendingFallStillnessSos ||
              isNativeSafetyDialogVisible ||
              _hasTriggeredSos) {
            return;
          }
          final toast = HikerCircleToast.show(
            context,
            message,
            title: title,
            duration: const Duration(seconds: 5),
          );
          await toast.closed;
        })
        .catchError((Object error) {
          debugPrint('Hike notice unavailable: $error');
        });
    return _hikeNoticeQueue;
  }

  /// Checks active precautions.
  Future<void> _checkActivePrecautions() async {
    final hike = activeHike;
    if (hike == null || _checkingPrecautions || !mounted || _hasTriggeredSos) {
      return;
    }
    final sessionKey = ActiveHikePrecautionAnnouncer.sessionKey(hike);
    if (_precautionSession != sessionKey) {
      _precautionSession = sessionKey;
      _precautionCheckedAt = null;
      _hikeWarningSpeech.synchronizeSession(sessionKey);
      _precautionAnnouncer.synchronizeSession(sessionKey);
    }
    if (_precautionCheckedAt != null &&
        DateTime.now().difference(_precautionCheckedAt!).inMinutes < 5) {
      return;
    }
    if (fallStillnessMonitor.isAwaitingResponse ||
        isFallStillnessLocalAlarmActive ||
        isSendingFallStillnessSos) {
      return;
    }
    _checkingPrecautions = true;
    try {
      final remaining =
          (hike.trail.estimatedDurationMinutes - hike.elapsedDuration.inMinutes)
              .clamp(1, 1440);
      final location = hike.latestLocation;
      final cautions = await PrecautionCheckService.check(
        hike.trail,
        durationMinutes: remaining,
        latitude: location?.hasValidPosition == true
            ? location!.latitude
            : null,
        longitude: location?.hasValidPosition == true
            ? location!.longitude
            : null,
      );
      if (!mounted ||
          activeHike == null ||
          ActiveHikePrecautionAnnouncer.sessionKey(activeHike!) != sessionKey) {
        return;
      }
      _precautionCheckedAt = DateTime.now();
      if (fallStillnessMonitor.isAwaitingResponse ||
          isFallStillnessLocalAlarmActive ||
          isSendingFallStillnessSos) {
        return;
      }
      await _precautionAnnouncer.announce(
        sessionKey: sessionKey,
        cautions: cautions,
        canPresent: () =>
            mounted &&
            activeHike != null &&
            ActiveHikePrecautionAnnouncer.sessionKey(activeHike!) ==
                sessionKey &&
            !_isEndingActiveHike &&
            !fallStillnessMonitor.isAwaitingResponse &&
            !isFallStillnessLocalAlarmActive &&
            !isSendingFallStillnessSos &&
            !isNativeSafetyDialogVisible &&
            !_hasTriggeredSos,
      );
    } finally {
      _checkingPrecautions = false;
    }
  }

  Timer? batteryLevelTimer;

  void Function()? _unregisterAchievementNotifications;

  final Set<String> _openingUpcomingHikeDeepLinkIds = <String>{};
  bool _notificationUiReady = false;
  bool _isDrainingFcmOpens = false;

  bool _isPresentingBleUiEvent = false;

  String? _pathDeviationSessionKey;

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  late final Future<void> _upcomingPlanningRestoreFuture;
  bool _isOpeningUpcomingWeather = false;

  String? _lastHandledNativeSafetyEventId;

  final Set<String> _terminalCloudHikeSessionIds = <String>{};
  bool isRestoringActiveHike = true;
  int selectedTabIndex = 0;
  int _buddyRequestsOpenId = 0;
  int _manualSosRequestSequence = 0;

  int _immediateSosRequestSequence = 0;

  String? _lastHandledDeepLink;
  DateTime? _lastHandledDeepLinkAt;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikerHomePageStateViewModel(
      readFirebaseBootstrapResult: () => widget.firebaseBootstrapResult,
      readOnSignOut: () => widget.onSignOut,
      readSession: () => widget.session,
      effectDrainPendingBleUiEvents: _drainPendingBleUiEvents,
      effectDrainPendingFcmOpens: _drainPendingFcmOpens,
      effectDrainPendingTeamReadiness: _drainPendingTeamReadiness,
      effectEmitPathDeviationAlert: _emitPathDeviationAlert,
      effectEnsureLiveLocationHikeConfiguration:
          _ensureLiveLocationHikeConfiguration,
      effectHandleBleEvent: _handleBleEvent,
      effectHandleDeepLink: _handleDeepLink,
      effectHandleFallStillnessCountdownStarted:
          _handleFallStillnessCountdownStarted,
      effectOpenStartHikeWizard: _openStartHikeWizard,
      effectPromptForFormedTeamChatName: _promptForFormedTeamChatName,
      effectRebuildPlannedHike: _rebuildPlannedHike,
      effectRecordActiveHikeLocationTick: _recordActiveHikeLocationTick,
      effectRecoverActiveHikeAfterReconnect: _recoverActiveHikeAfterReconnect,
      effectRequestSignOut: _requestSignOut,
      effectRevealActiveHike: _revealActiveHike,
      effectReviewDraftPreparation: _reviewDraftPreparation,
      effectScheduleAnotherTimeAfterHazard: _scheduleAnotherTimeAfterHazard,
      effectShowActiveHikeActionError: _showActiveHikeActionError,
      effectShowBleSosHelpPopupForLocation: _showBleSosHelpPopupForLocation,
      effectShowFallStillnessSnackBar: _showFallStillnessSnackBar,
      effectShowHikeNotice: _showHikeNotice,
      effectShowNearbySosButtonPopup: _showNearbySosButtonPopup,
      effectShowUpcomingHikeError: _showUpcomingHikeError,
      effectStartPreparedInstantHike: _startPreparedInstantHike,
      effectSyncActiveHikeLiveStatus: _syncActiveHikeLiveStatus,
      effectSyncActiveHikeServices: _syncActiveHikeServices,
      effectUploadActiveHikeLocations: _uploadActiveHikeLocations,
      effectOpenEmergencyContacts: openEmergencyContacts,
      effectRequestImmediateSos: requestImmediateSos,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentConfirmExternalSosTriggerEffect1 =
        _presentConfirmExternalSosTriggerEffect1;
    _screenModel.effectPresentRequestSignOutEffect1 =
        _presentRequestSignOutEffect1;
    _screenModel.effectPresentOpenEmergencyContactsEffect1 =
        _presentOpenEmergencyContactsEffect1;
    _screenModel.effectPresentOpenUndiscoveredTrailRequestsEffect1 =
        _presentOpenUndiscoveredTrailRequestsEffect1;
    _screenModel.effectPresentOpenFindHikeEffect1 = _presentOpenFindHikeEffect1;
    _screenModel.effectCancelUpcomingHike = _cancelUpcomingHike;
    _screenModel.effectPresentScheduleAnotherTimeAfterHazardEffect1 =
        _presentScheduleAnotherTimeAfterHazardEffect1;
    _screenModel.effectPresentHandleFallStillnessCountdownStartedEffect1 =
        _presentHandleFallStillnessCountdownStartedEffect1;
    _screenModel.effectPresentRescheduleExpiredHikeEffect1 =
        _presentRescheduleExpiredHikeEffect1;
    _screenModel.effectEndActiveHikeSession = _endActiveHikeSession;
    _screenModel.effectPresentConfirmHazardCancellationEffect1 =
        _presentConfirmHazardCancellationEffect1;

    _sosPresentation.addListener(_handleSosPresentationChanged);
    _lastManualSharingStopRevision =
        LiveLocationSharingService.instance.manualStopRevision;
    _lastManualSharingStartRevision =
        LiveLocationSharingService.instance.manualStartRevision;
    LiveLocationSharingService.instance.addListener(_handleLiveSharingChanged);
    unawaited(
      LocationUpdateIntervalController.instance.loadForUser(
        widget.session.phoneNumber,
      ),
    );
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
    _achievementNotificationDelivery = AchievementNotificationDelivery(
      database: hikerCircleRepository.localDatabase,
      owner: widget.session.phoneNumber,
      notifications: DeviceAchievementNotifications(_localNotifications),
    );
    _unregisterAchievementNotifications =
        AchievementNotificationEvents.register(
          widget.session.phoneNumber,
          _deliverAchievementNotifications,
        );
    if (widget.session.isAdmin) {
      _pendingTrailRequestsSubscription =
          _HikerHomePageDataActions.watchPendingTrailRequests(
            hikerCircleRepository,
          )(session: widget.session).listen(
            (hasPending) {
              if (mounted) {
                setState(
                  () => _hasPendingUndiscoveredTrailRequests = hasPending,
                );
              }
            },
            onError: (Object error) {
              debugPrint('Trail request updates are unavailable: $error');
            },
          );
    }
    _hikeReminders = UpcomingHikeReminderService(
      database: hikerCircleRepository.localDatabase,
      notifications: DeviceHikeReminderNotifications(_localNotifications),
      ownerPhoneNumber: widget.session.phoneNumber,
    );
    _planningChangesSubscription = HikerCircleFirebaseRepository.planningChanges
        .listen((owner) {
          if (mounted && owner == widget.session.phoneNumber) {
            unawaited(_restoreCachedUpcomingPlanningState());
          }
        });
    unawaited(_initializeLocalNotifications());
    _listenForFormedTeamChats();
    _listenForTeamReadiness();
    _upcomingPlanningRestoreFuture = _restoreCachedUpcomingPlanningState();
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _contactsChangeSubscription = EmergencyContactsRepository.changes.listen((
      change,
    ) {
      if (mounted && change.phoneNumber == widget.session.phoneNumber) {
        setState(() => emergencyContacts = change.contacts);
      }
    });
    _emergencyContactsLoadFuture = _loadEmergencyContacts();
    sosAlertRepository = SosAlertRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _sosQueueSubscription = SosAlertRepository.queueChanges.listen((change) {
      if (mounted && change.phoneNumber == widget.session.phoneNumber) {
        final alert = change.alert;
        if (alert != null) {
          _sosPresentation.updateDelivery(
            alert,
            queuedForRetry: change.queuedForRetry,
          );
        }
        unawaited(_refreshQueuedSosCount());
      }
    });
    unawaited(_refreshQueuedSosCount());
    _sosConnectionSubscription = NetworkReachabilityService
        .instance
        .connectionAvailable
        .listen((_) {
          unawaited(_retryQueuedSosAlerts());
        });
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
    unawaited(
      LiveLocationSharingService.instance.loadExisting(
        phoneNumber: widget.session.phoneNumber,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    unawaited(_refreshBatteryLevel());
    batteryLevelTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshBatteryLevel());
    });
    _precautionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_checkActivePrecautions());
    });
    _pendingHikeRetryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        return;
      }
      unawaited(
        _HikerHomePageDataActions.flushPendingUpcomingHikes(
          hikerCircleRepository,
        )(session: widget.session),
      );
      unawaited(_synchronizeLocalHikeReminders());
      if (_nativeHikeStopPending && activeHike == null) {
        unawaited(
          _activeHikeLiveStatusService.stop().then((stopped) {
            _nativeHikeStopPending = !stopped;
          }),
        );
      }
      unawaited(
        _runReconnectStep(
          'pending hike completions',
          () => _HikerHomePageDataActions.flushPendingHikeEnds(
            hikerCircleRepository,
          )(session: widget.session),
        ),
      );
      unawaited(
        _runReconnectStep(
          'pending sharing stop',
          LiveLocationSharingService.instance.retryPendingStop,
        ),
      );
    });
    unawaited(loadLiveData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _notificationUiReady = true;
      unawaited(_drainPendingFcmOpens());
      unawaited(_drainPendingBleUiEvents());
      unawaited(_drainPendingTeamReadiness());
    });
    unawaited(_loadInitialDeepLink());
    if (widget.initialDeepLink != null) {
      _handleDeepLinkAfterFirstFrame(widget.initialDeepLink!);
    }
    unawaited(_initializeFirebaseMessaging());
    unawaited(_initializeAchievementTracking());
    unawaited(_initializeBleBridge());
    _networkReachabilitySubscription = NetworkReachabilityService
        .instance
        .snapshots
        .listen(_handleNetworkReachabilityChanged);
    unawaited(NetworkReachabilityService.instance.start());
  }

  /// Delegates handle live sharing changed to the ViewModel.
  void _handleLiveSharingChanged() =>
      _screenModel.commandHandleLiveSharingChanged();

  /// Delegates listen for formed team chats to the ViewModel.
  void _listenForFormedTeamChats() =>
      _screenModel.commandListenForFormedTeamChats();

  /// Delegates listen for team readiness to the ViewModel.
  void _listenForTeamReadiness() =>
      _screenModel.commandListenForTeamReadiness();

  /// Delegates team readiness key to the ViewModel.
  String? _teamReadinessKey(TeamHikeSession teamSession) =>
      _screenModel.commandTeamReadinessKey(teamSession);

  /// Computes drain pending team readiness.
  Future<void> _drainPendingTeamReadiness() async {
    if (_isDrainingTeamReadiness ||
        _hasTriggeredSos ||
        !mounted ||
        !_notificationUiReady ||
        _appLifecycleState != AppLifecycleState.resumed ||
        _navigatingTeamSessionId != null) {
      return;
    }
    _isDrainingTeamReadiness = true;
    try {
      while (mounted &&
          !_hasTriggeredSos &&
          _appLifecycleState == AppLifecycleState.resumed &&
          _navigatingTeamSessionId == null &&
          _pendingTeamReadinessSessions.isNotEmpty) {
        final entries = _pendingTeamReadinessSessions.entries.toList()
          ..sort(
            (left, right) => right.value.readinessStartedAt!.compareTo(
              left.value.readinessStartedAt!,
            ),
          );
        final entry = entries.first;
        _pendingTeamReadinessSessions.remove(entry.key);
        if (_presentedTeamReadinessKeys.contains(entry.key)) {
          continue;
        }
        await _openTeamHikeInvite(entry.value.id);
      }
    } finally {
      _isDrainingTeamReadiness = false;
    }
  }

  /// Computes prompt for formed team chat name.
  void _promptForFormedTeamChatName(List<GroupChat> chats) {
    if (_hasTriggeredSos) {
      _pendingFormedTeamChats = chats;
      return;
    }
    if (!mounted || _activeTeamNamingChatId != null) {
      return;
    }
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

  /// Delegates formed chat phone key to the ViewModel.
  String _formedChatPhoneKey(String value) =>
      _screenModel.commandFormedChatPhoneKey(value);

  /// Shows formed team naming dialog.
  Future<void> _showFormedTeamNamingDialog(GroupChat chat) async {
    final trailName = chat.trailName.trim().isEmpty
        ? 'this hike'
        : chat.trailName.trim();
    final departure = chat.departureTime ?? chat.createdAt;
    final initialName = GroupChat.defaultGroupName(chat.trailName, departure);
    try {
      await _HikerHomePageDataActions.markFormedHikeGroupNamingPromptShown(
        hikerCircleRepository,
      )(chatId: chat.id, defaultName: initialName);
    } catch (_) {
      // The mandatory dialog still lets the host retry the final save. If the
      // app is killed before this acknowledgement reaches Firebase, the chat
      // remains pending and will be offered again instead of being lost.
    }
    if (!mounted) {
      return;
    }
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    final created = await _presentShowFormedTeamNamingDialogEffect1(
      chat,
      trailName,
      initialName,
    );
    if (!mounted) {
      return;
    }
    _activeTeamNamingChatId = null;
    if (created == true) {
      HikerCircleToast.show(
        context,
        'The team has been added and the conversation is ready.',
        tone: HikerCircleToastTone.success,
        title: 'Group chat ready',
      );
      final namedChat = await _HikerHomePageDataActions.loadGroupChatById(
        hikerCircleRepository,
      )(chat.id);
      if (!mounted) {
        return;
      }
      if (namedChat != null) {
        while (mounted && _hasTriggeredSos) {
          await _waitForTriggeredSosToClose();
        }
        if (!mounted) return;
        await _presentShowFormedTeamNamingDialogEffect2(namedChat);
      }
    }
  }

  /// Opens accepted hike group chat.
  Future<void> _openAcceptedHikeGroupChat(String hikeId) async {
    final normalizedHikeId = hikeId.trim();
    if (!mounted || normalizedHikeId.isEmpty) {
      return;
    }
    final chatId = 'hike_$normalizedHikeId';
    if (_activeTeamNamingChatId == chatId) {
      // The mandatory first-team naming dialog owns navigation once saved.
      return;
    }
    GroupChat? chat;
    try {
      for (var attempt = 0; attempt < 3 && chat == null; attempt++) {
        chat = await _HikerHomePageDataActions.loadGroupChatById(
          hikerCircleRepository,
        )(chatId);
        if (chat == null && attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      HikerCircleToast.show(
        context,
        'The hiker was accepted, but the group chat could not be opened yet.',
        tone: HikerCircleToastTone.warning,
        title: 'Chat is still syncing',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    if (chat == null) {
      HikerCircleToast.show(
        context,
        'The hiker was accepted. Open the hike conversation from Circle if it is still being created.',
        tone: HikerCircleToastTone.warning,
        title: 'Group chat is still syncing',
      );
      return;
    }
    final ownPhoneKey = _formedChatPhoneKey(widget.session.phoneNumber);
    final isHost = _formedChatPhoneKey(chat.creatorPhone) == ownPhoneKey;
    if (isHost &&
        chat.requiresHostNaming &&
        !chat.namingPromptShown &&
        chat.hikeEndedAt == null &&
        !chat.isDeleted) {
      _activeTeamNamingChatId = chat.id;
      await _showFormedTeamNamingDialog(chat);
      return;
    }
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GroupChatDetailPage(
          chat: chat!,
          session: widget.session,
          repository: hikerCircleRepository,
        ),
      ),
    );
  }

  /// Delegates deliver achievement notifications to the ViewModel.
  Future<void> _deliverAchievementNotifications() =>
      _screenModel.commandDeliverAchievementNotifications();

  /// Delegates initialize achievement tracking to the ViewModel.
  Future<void> _initializeAchievementTracking() =>
      _screenModel.commandInitializeAchievementTracking();

  /// Delegates initialize local notifications to the ViewModel.
  Future<bool> _initializeLocalNotifications() =>
      _screenModel.commandInitializeLocalNotifications();

  /// Delegates synchronize local hike reminders to the ViewModel.
  Future<void> _synchronizeLocalHikeReminders() =>
      _screenModel.commandSynchronizeLocalHikeReminders();

  /// Delegates initialize firebase messaging to the ViewModel.
  Future<void> _initializeFirebaseMessaging() =>
      _screenModel.commandInitializeFirebaseMessaging();

  /// Delegates initialize ble bridge to the ViewModel.
  Future<void> _initializeBleBridge() =>
      _screenModel.commandInitializeBleBridge();

  /// Handles ble event.
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

  /// Delegates enqueue ble ui event to the ViewModel.
  void _enqueueBleUiEvent(HikerBleEvent event) =>
      _screenModel.commandEnqueueBleUiEvent(event);

  /// Computes drain pending ble ui events.
  Future<void> _drainPendingBleUiEvents() async {
    if (_isPresentingBleUiEvent ||
        _hasTriggeredSos ||
        !mounted ||
        !_notificationUiReady ||
        _appLifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _isPresentingBleUiEvent = true;
    try {
      while (mounted &&
          !_hasTriggeredSos &&
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

  /// Delegates handle network reachability changed to the ViewModel.
  void _handleNetworkReachabilityChanged(
    NetworkReachabilitySnapshot snapshot,
  ) => _screenModel.commandHandleNetworkReachabilityChanged(snapshot);

  /// Delegates refresh queued sos count to the ViewModel.
  Future<void> _refreshQueuedSosCount() =>
      _screenModel.commandRefreshQueuedSosCount();

  /// Delegates retry queued sos alerts to the ViewModel.
  Future<void> _retryQueuedSosAlerts() =>
      _screenModel.commandRetryQueuedSosAlerts();

  /// Computes recover active hike after reconnect.
  Future<void> _recoverActiveHikeAfterReconnect() async {
    if (!mounted || _isEndingActiveHike) {
      return;
    }
    final currentHike = activeHike;
    if (currentHike != null) {
      await _drainNativeLocationSamples(currentHike);
      final hike =
          await _restoreScheduledTeamSourceLink(
            activeHike ?? currentHike,
          ).timeout(
            const Duration(seconds: 8),
            onTimeout: () => activeHike ?? currentHike,
          );
      if (!mounted ||
          activeHike?.sessionId != hike.sessionId ||
          _isEndingActiveHike) {
        return;
      }
      ActiveHikeSession? cloudHike;
      await _runReconnectStep('active hike', () async {
        cloudHike = await _activeHikeCloudSync.synchronize(
          hike.sessionId,
          force: true,
        );
      });
      final hikeToFlush = cloudHike;
      if (hikeToFlush != null) {
        await _runReconnectStep('hike locations', () async {
          final remaining = await _HikerHomePageDataActions.flushFootprints(
            hikerCircleRepository,
          )(session: widget.session, activeHike: hikeToFlush);
          if (mounted && activeHike?.sessionId == hikeToFlush.sessionId) {
            final updatedHike = activeHike!.copyWith(queuedUpdates: remaining);
            setState(() => activeHike = updatedHike);
            _persistActiveHikeSnapshot(updatedHike);
          }
        });
      }
    }
    final latestHike = activeHike;
    if (latestHike != null && latestHike.draft.shareLiveLocation) {
      await _runReconnectStep(
        'live location sharing',
        () => _syncLiveLocationForActiveHike(latestHike),
      );
    } else if (LiveLocationSharingService.instance.isActive) {
      await _runReconnectStep(
        'live location',
        LiveLocationSharingService.instance.publishLatest,
      );
    }
  }

  /// Delegates restore scheduled team source link to the ViewModel.
  Future<ActiveHikeSession> _restoreScheduledTeamSourceLink(
    ActiveHikeSession hike,
  ) => _screenModel.commandRestoreScheduledTeamSourceLink(hike);

  /// Delegates with team hike session link to the ViewModel.
  ActiveHikeSession _withTeamHikeSessionLink(
    ActiveHikeSession hike,
    TeamHikeSession teamSession,
  ) => _screenModel.commandWithTeamHikeSessionLink(hike, teamSession);

  /// Apply the canonical cloud session identity before later footprint uploads or team updates.
  Future<ActiveHikeSession?> _applyActiveHikeCloudRestoreResult(
    ActiveHikeSession requestedHike,
    ActiveHikeCloudRestoreResult result,
  ) async {
    if (!mounted || _isEndingActiveHike) {
      return null;
    }
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
      await _drainNativeLocationSamples(currentHike);
      await _activeHikeLiveStatusService.remapNativeLocationSession(
        oldSessionId,
        canonicalSessionId,
      );
      await _activeHikePersistenceQueue;
      cloudHike =
          await _HikerHomePageDataActions.migrateActiveHikeSessionId(
            hikerCircleRepository.localDatabase,
          )(
            ownerPhoneNumber: widget.session.phoneNumber,
            activeHike: activeHike ?? currentHike,
            newSessionId: canonicalSessionId,
          );
    }

    if (!mounted ||
        _isEndingActiveHike ||
        activeHike?.sessionId != oldSessionId) {
      return activeHike?.sessionId == canonicalSessionId ? activeHike : null;
    }
    if (result.terminal) {
      _terminalCloudHikeSessionIds
        ..add(oldSessionId)
        ..add(canonicalSessionId);
      setState(() => activeHike = null);
      _syncActiveHikeServices(null);
      await _activeHikePersistenceQueue;
      unawaited(
        _HikerHomePageDataActions.flushFootprints(hikerCircleRepository)(
          session: widget.session,
          activeHike: cloudHike,
        ).catchError((Object _) => cloudHike.queuedUpdates),
      );
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
    if (!result.ensured) {
      return null;
    }

    if (canonicalSessionId != oldSessionId) {
      cloudHike = activeHike!.copyWith(sessionId: canonicalSessionId);
      setState(() => activeHike = cloudHike);
      _syncActiveHikeServices(cloudHike, forceLiveStatus: true);
    }
    return cloudHike;
  }

  /// Delegates run reconnect step to the ViewModel.
  Future<void> _runReconnectStep(
    String label,
    Future<dynamic> Function() action,
  ) => _screenModel.commandRunReconnectStep(label, action);

  /// Computes drain pending fcm opens.
  Future<void> _drainPendingFcmOpens() async {
    if (!_notificationUiReady ||
        _hasTriggeredSos ||
        _appLifecycleState != AppLifecycleState.resumed ||
        _isDrainingFcmOpens ||
        !mounted) {
      return;
    }
    _isDrainingFcmOpens = true;
    try {
      while (mounted &&
          !_hasTriggeredSos &&
          _appLifecycleState == AppLifecycleState.resumed &&
          _pendingFcmOpens.isNotEmpty) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            _hasTriggeredSos ||
            _appLifecycleState != AppLifecycleState.resumed) {
          return;
        }
        final pending = _pendingFcmOpens.removeAt(0);
        if (!_handledFcmOpenKeys.add(pending.key)) continue;
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

  /// Shows opened notification popup.
  Future<void> _showOpenedNotificationPopup(_PendingFcmOpen pending) async {
    final title = pending.title?.trim();
    final body = pending.body?.trim();
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
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

  /// Delegates load emergency contacts to the ViewModel.
  Future<void> _loadEmergencyContacts() =>
      _screenModel.commandLoadEmergencyContacts();

  /// Delegates restore cached upcoming planning state to the ViewModel.
  Future<void> _restoreCachedUpcomingPlanningState() =>
      _screenModel.commandRestoreCachedUpcomingPlanningState();

  /// Rebuilds planned hike.
  void _rebuildPlannedHike() {
    unawaited(_synchronizeLocalHikeReminders());
    final now = DateTime.now();
    myUpcomingHikes = PlannedHikeStateResolver.mergeUpcomingHikes(
      remote: myUpcomingHikes,
      cached: const [],
      retainUnconfirmedCachedHikes: false,
      consumedHikeIds: _consumedUpcomingHikeIds,
      now: now,
    );
    _upcomingHikeExpiryTimer?.cancel();
    _upcomingHikeExpiryTimer = null;
    if (myUpcomingHikes.isNotEmpty) {
      _upcomingHikeExpiryTimer = Timer(
        myUpcomingHikes.first.visibleUntil.difference(now.toUtc()),
        () {
          if (mounted) {
            setState(_rebuildPlannedHike);
          }
        },
      );
    }
    final next = PlannedHikeStateResolver.selectNext(myUpcomingHikes, now: now);
    plannedHike = next == null
        ? null
        : PlannedHikeStateResolver.resolve(
            upcomingHike: next,
            liveTrails: trails,
            emergencyContactsSelected: emergencyContacts.isNotEmpty,
            phoneBatteryLevel: _latestPhoneBatteryLevel,
            completedChecklistItems: _plannedChecklistByUpcomingId[next.id],
          );
    final currentPlan = plannedHike;
    if (currentPlan != null) {
      plannedHike = currentPlan
          .copyWith(gearAssessment: _gearRouteService.peek(currentPlan.trail))
          .withGearProgress();
      final key = RouteGearAnalysisService.inputKey(currentPlan.trail);
      if (_gearAnalysisRequests.add(key)) {
        unawaited(_analyzeGearRoute(currentPlan));
      }
    }
    unawaited(
      HomeScreenWidgetService.shared.update(
        hikes: myUpcomingHikes,
        plan: plannedHike,
      ),
    );
  }

  /// Delegates update planned hike to the ViewModel.
  Future<void> _updatePlannedHike(PlannedHike updatedPlan) =>
      _screenModel.commandUpdatePlannedHike(updatedPlan);

  /// Restore the device's active session before processing deep links and native safety actions.
  Future<void> _restoreActiveHikeSession() async {
    try {
      final restoredHike =
          await _HikerHomePageDataActions.loadActiveHikeSession(
            hikerCircleRepository.localDatabase,
          )(phoneNumber: widget.session.phoneNumber);
      if (!mounted) {
        return;
      }
      if (restoredHike == null) {
        // Native iOS/Android monitoring persists independently so it can
        // survive process termination. Reconcile it with the local source of
        // truth before it can keep a completed hike's watchdog alive.
        await _activeHikeLiveStatusService.stop();
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

  /// Delegates wait for active hike restore to the ViewModel.
  Future<void> _waitForActiveHikeRestore() =>
      _screenModel.commandWaitForActiveHikeRestore();

  /// Serialize active-session persistence so an older asynchronous snapshot cannot win over a newer one.
  void _persistActiveHikeSnapshot(ActiveHikeSession? hike) =>
      _screenModel.commandPersistActiveHikeSnapshot(hike);

  /// Loads initial deep link.
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

  /// Handles deep link after first frame.
  void _handleDeepLinkAfterFirstFrame(String link) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_handleDeepLink(link));
    });
  }

  /// Delegates handle deep link method call to the ViewModel.
  Future<void> _handleDeepLinkMethodCall(MethodCall call) =>
      _screenModel.commandHandleDeepLinkMethodCall(call);

  /// Opens upcoming weather.
  Future<void> _openUpcomingWeather() async {
    if (_isOpeningUpcomingWeather) {
      return;
    }
    _isOpeningUpcomingWeather = true;
    try {
      await _upcomingPlanningRestoreFuture.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      if (!mounted) {
        return;
      }
      var next = PlannedHikeStateResolver.selectNext(myUpcomingHikes);
      if (next == null) {
        HikerCircleToast.show(context, 'Loading your upcoming hike…');
        final hikes = await _HikerHomePageDataActions.loadMyUpcomingHikes(
          hikerCircleRepository,
        )(widget.session.phoneNumber).timeout(const Duration(seconds: 8));
        if (!mounted) {
          return;
        }
        next = PlannedHikeStateResolver.selectNext(hikes);
        if (next != null) {
          unawaited(HomeScreenWidgetService.shared.update(hikes: hikes));
        }
      }
      if (!mounted) {
        return;
      }
      if (next == null) {
        HikerCircleToast.show(
          context,
          'No upcoming hike is available. Open your hiking plans to check the schedule.',
        );
        return;
      }
      final forecastHike = next;
      await _presentOpenUpcomingWeatherEffect1(forecastHike);
    } catch (error) {
      if (mounted) {
        HikerCircleToast.show(
          context,
          'Couldn’t open hike weather. Please try again.',
        );
      }
    } finally {
      _isOpeningUpcomingWeather = false;
    }
  }

  /// Route supported notification and app links only after the required session state is available.
  Future<void> _handleDeepLink(String link, {bool allowRepeat = false}) async {
    final now = DateTime.now();
    final lastHandledAt = _lastHandledDeepLinkAt;
    if (!allowRepeat &&
        _lastHandledDeepLink == link &&
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
    final isSafetyLink =
        uri.host == 'sos' ||
        (uri.host == 'hike' &&
            const {
              '/safety',
              '/safety-safe',
              '/safety-alarm-stopped',
            }.contains(uri.path));
    if (!isSafetyLink) {
      while (mounted && _hasTriggeredSos) {
        await _waitForTriggeredSosToClose();
      }
      if (!mounted) return;
    }
    if (uri.host == 'achievement' && uri.path == '/earned') {
      await _openEarnedAchievement(uri);
      return;
    }
    if (uri.host == 'hike' &&
        (uri.path == '/briefing' || uri.path == '/weather')) {
      if (!mounted) {
        return;
      }
      setState(() => selectedTabIndex = 0);
      tabController.animateTo(0);
      if (uri.path == '/weather') {
        await _openUpcomingWeather();
      }
      return;
    }
    if (uri.host == 'hike' && !uri.path.startsWith('/safety')) {
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
      if (!_deepLinkMatchesActiveHike(uri)) {
        return;
      }
      _openActiveHikeSessionFromDeepLink();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/report-hazard') {
      if (!_deepLinkMatchesActiveHike(uri)) return;
      await _openActiveHikeHazardReport();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/safety') {
      await _consumePendingNativeSafetyEvent();
      return;
    }
    if (uri.host == 'hike' && uri.path == '/safety-alarm-stopped') {
      final nativeId = uri.queryParameters['eventId'];
      if (nativeId == null || nativeId.isEmpty) return;
      final stopped = await _activeHikeLiveStatusService.wasSafetyAlarmStopped(
        nativeId,
      );
      if (!mounted || !stopped) return;
      _stoppedNativeSosPresentationIds.add(nativeId);
      if (_nativeSafetyCountdownEventId == nativeId) {
        _presentHandleDeepLinkEffect1();
      }
      final presentationId = _nativeSosPresentationIds[nativeId];
      if (presentationId != null &&
          _sosPresentation.current?.eventId == presentationId) {
        await _stopPresentedSos(presentationId);
      } else if (_sosPresentation.current == null) {
        await _stopTriggeredSosOutputs(nativeEventId: nativeId);
      }
      unawaited(_consumePendingNativeSafetyEvent());
      return;
    }
    if (uri.host == 'hike' && uri.path == '/safety-safe') {
      // Legacy links may reveal the emergency but cannot bypass its slider.
      await _consumePendingNativeSafetyEvent();
      if (!_hasTriggeredSos) {
        _cancelFallStillnessSos('Safety popup response received');
      }
      return;
    }
    if (uri.host == 'hike' && uri.path == '/check-in') {
      if (!_deepLinkMatchesActiveHike(uri)) {
        return;
      }
      _openActiveHikeSessionFromDeepLink();
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
        unawaited(
          _openUpcomingHikeFromDeepLink(
            hikeId,
            showChargingReminder: uri.queryParameters['chargePhone'] == '1',
            hazardId: uri.queryParameters['hazardId'],
          ),
        );
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
    if (uri.host == 'buddy' && uri.path == '/requests') {
      final owner = uri.queryParameters['ownerPhoneNumber'] ?? '';
      if (owner.isNotEmpty &&
          owner.replaceAll(RegExp(r'\D'), '') !=
              widget.session.phoneNumber.replaceAll(RegExp(r'\D'), '')) {
        return;
      }
      if (!mounted) return;
      setState(() {
        selectedTabIndex = 2;
        _buddyRequestsOpenId++;
      });
      tabController.animateTo(2);
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

  /// Delegates confirm external sos trigger to the ViewModel.
  Future<bool> _confirmExternalSosTrigger(SosAlertMode mode) =>
      _screenModel.commandConfirmExternalSosTrigger(mode);

  /// Opens earned achievement.
  Future<void> _openEarnedAchievement(Uri uri) async {
    final id = AchievementNotification.achievementIdFromLink(
      uri,
      widget.session.phoneNumber,
    );
    if (id == null) return;
    final cached =
        await _HikerHomePageDataActions.loadCachedAchievementProgress(
          hikerCircleRepository,
        )(session: widget.session);
    final matches = cached?.rows.where(
      (row) => row['achievementId'] == id && row['isUnlocked'] == true,
    );
    final row = matches != null && matches.isNotEmpty
        ? matches.first
        : await _HikerHomePageDataActions.loadAchievementNotification(
            hikerCircleRepository.localDatabase,
          )(widget.session.phoneNumber, id);
    if (!mounted || row == null || row['isUnlocked'] != true) return;
    final open = await showAchievementUnlockedPopup(context, row);
    if (!mounted || !open) return;
    await _presentOpenEarnedAchievementEffect1();
  }

  /// Computes deep link matches active hike.
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

  /// Opens upcoming hike from deep link.
  Future<void> _openUpcomingHikeFromDeepLink(
    String hikeId, {
    bool showChargingReminder = false,
    String? hazardId,
  }) async {
    // Cold-start notification callbacks and the native link channel can both
    // deliver the same tap. Keep one instance of each destination per hike.
    final chargingOnly = showChargingReminder && hazardId == null;
    final openKey =
        '$hikeId:${chargingOnly ? "charge" : hazardId ?? "details"}';
    if (!mounted || !_openingUpcomingHikeDeepLinkIds.add(openKey)) {
      return;
    }
    try {
      if (chargingOnly) {
        await showHikeChargingReminder(
          context,
          loadBatteryLevel: _readBatteryLevel,
        );
        return;
      }
      await _openUpcomingHikeNotificationDestination(
        hikeId,
        hazardId: hazardId,
      );
    } catch (error) {
      debugPrint('Unable to open the upcoming hike reminder: $error');
      if (mounted) {
        HikerCircleToast.show(
          context,
          'Unable to open this hike. Please try again.',
        );
      }
    } finally {
      _openingUpcomingHikeDeepLinkIds.remove(openKey);
    }
  }

  /// Opens upcoming hike notification destination.
  Future<void> _openUpcomingHikeNotificationDestination(
    String hikeId, {
    String? hazardId,
  }) async {
    await _upcomingPlanningRestoreFuture;
    await _waitForActiveHikeRestore();
    if (!mounted) return;
    final localStates = await _HikerHomePageDataActions.loadPlannedHikeStates(
      hikerCircleRepository.localDatabase,
    )(ownerPhoneNumber: widget.session.phoneNumber);
    for (final state in localStates) {
      // Hazard taps recheck the shared schedule; saved gear remains in the
      // local preparation resolver, but obsolete membership must not grant UI actions.
      if (hazardId != null) break;
      if (state.upcomingHike.id != hikeId &&
          'local_pending_${state.creationKey}' != hikeId) {
        continue;
      }
      if (!mounted) return;
      if (!state.isConsumed &&
          state.upcomingHike.isUpcomingAt(DateTime.now())) {
        await _showUpcomingHikeDetails(state.upcomingHike);
        return;
      }
      // A delivered reminder may outlive its cancelled or completed hike.
      if (activeHike?.sourceUpcomingHikeId == state.upcomingHike.id) {
        _revealActiveHike();
      } else {
        HikerCircleToast.show(context, 'This hike is no longer upcoming.');
      }
      return;
    }
    if (!mounted) return;
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    final progressReady = Completer<BuildContext>();
    unawaited(
      _presentOpenUpcomingHikeNotificationDestinationEffect1(progressReady),
    );
    final progressContext = await progressReady.future;
    List<Object?> results;
    try {
      results = await Future.wait<Object?>([
        hazardId == null
            ? _HikerHomePageDataActions.loadUpcomingHikeById(
                hikerCircleRepository,
              )(hikeId)
            : _HikerHomePageDataActions.loadParticipantUpcomingHikeForSafety(
                hikerCircleRepository,
              )(hikeId: hikeId, session: widget.session),
        _HikerHomePageDataActions.loadTrails(
          hikerCircleRepository,
        )().catchError((_) => <Trail>[]),
      ]);
    } catch (error) {
      if (!mounted) {
        return;
      }
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
        _presentOpenUpcomingHikeNotificationDestinationEffect2(progressContext);
      }
    }
    if (!mounted) {
      return;
    }
    final hike = results[0] as UpcomingHike?;
    final notificationTrails = results[1] as List<Trail>;
    if (hike == null || !hike.isUpcomingAt(DateTime.now())) {
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
    await _showUpcomingHikeDetails(
      hike,
      availableTrails: notificationTrails,
      hazardId: hazardId,
    );
  }

  /// Opens upcoming hike join request.
  Future<void> _openUpcomingHikeJoinRequest(String requestId) async {
    final normalizedId = requestId.trim();
    final now = DateTime.now();
    _recentUpcomingJoinRequestAttempts.removeWhere(
      (_, attemptedAt) =>
          now.difference(attemptedAt) > const Duration(minutes: 2),
    );
    final recentAttempt = _recentUpcomingJoinRequestAttempts[normalizedId];
    if (!mounted ||
        !RegExp(r'^join_[a-f0-9]{48}$').hasMatch(normalizedId) ||
        _activeUpcomingJoinRequestReviewId == normalizedId ||
        _completedUpcomingJoinRequestReviewIds.contains(normalizedId) ||
        (recentAttempt != null &&
            now.difference(recentAttempt) < const Duration(seconds: 30))) {
      return;
    }
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    _recentUpcomingJoinRequestAttempts[normalizedId] = now;
    _activeUpcomingJoinRequestReviewId = normalizedId;
    final progressReady = Completer<BuildContext>();
    unawaited(_presentOpenUpcomingHikeJoinRequestEffect1(progressReady));
    final progressContext = await progressReady.future;
    UpcomingHikeJoinRequestReview? review;
    try {
      review = await _HikerHomePageDataActions.loadUpcomingHikeJoinRequest(
        hikerCircleRepository,
      )(normalizedId).timeout(const Duration(seconds: 15));
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
    } on TimeoutException {
      if (mounted) {
        HikerCircleToast.show(
          context,
          'The request is taking too long to load. Check your connection and try the link again.',
          tone: HikerCircleToastTone.warning,
          title: 'Request timed out',
        );
      }
    } catch (_) {
      if (mounted) {
        HikerCircleToast.show(
          context,
          'Unable to check this join request right now.',
          tone: HikerCircleToastTone.error,
        );
      }
    } finally {
      if (progressContext.mounted) {
        _presentOpenUpcomingHikeJoinRequestEffect2(progressContext);
      }
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
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    final result = await showDialog<UpcomingHikeJoinRequestReview>(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpcomingHikeJoinRequestDialog(
        review: review!,
        onResolve: (accept) =>
            _HikerHomePageDataActions.resolveUpcomingHikeJoinRequest(
              hikerCircleRepository,
            )(requestId: normalizedId, accept: accept),
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
      _finishUpcomingJoinRequestReview();
      await _openAcceptedHikeGroupChat(result.hikeId);
      return;
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

  /// Computes choose future join policy.
  Future<void> _chooseFutureJoinPolicy(String hikeId) async {
    if (!mounted) {
      return;
    }
    final policy = await _presentChooseFutureJoinPolicyEffect1();
    if (!mounted || policy == null) {
      return;
    }
    try {
      await _HikerHomePageDataActions.setUpcomingHikeJoinPolicy(
        hikerCircleRepository,
      )(hikeId: hikeId, joinPolicy: policy);
      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
      _presentChooseFutureJoinPolicyEffect2(error);
    }
  }

  /// Delegates finish upcoming join request review to the ViewModel.
  void _finishUpcomingJoinRequestReview() =>
      _screenModel.commandFinishUpcomingJoinRequestReview();

  /// Opens group chat from deep link.
  Future<void> _openGroupChatFromDeepLink(String chatId) async {
    if (!mounted) {
      return;
    }
    final progressReady = Completer<BuildContext>();
    unawaited(_presentOpenGroupChatFromDeepLinkEffect1(progressReady));
    final progressContext = await progressReady.future;
    GroupChat? chat;
    try {
      chat = await _HikerHomePageDataActions.loadGroupChatById(
        hikerCircleRepository,
      )(chatId);
    } catch (error) {
      if (!mounted) {
        return;
      }
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
        _presentOpenGroupChatFromDeepLinkEffect2(progressContext);
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
    await _presentOpenGroupChatFromDeepLinkEffect3(availableChat);
  }

  /// Shows add buddy prompt.
  Future<void> _showAddBuddyPrompt({
    required String name,
    required String handle,
    required String phoneNumber,
  }) async {
    final shouldAdd = await _presentShowAddBuddyPromptEffect1(name, handle);

    if (shouldAdd != true || !mounted) {
      return;
    }

    if (phoneNumber.isNotEmpty) {
      try {
        await _HikerHomePageDataActions.sendBuddyRequest(hikerCircleRepository)(
          session: widget.session,
          buddyPhoneNumber: phoneNumber,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
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
    if (!mounted) {
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
          content: Text(
            phoneNumber.isEmpty
                ? '$name added to your buddies.'
                : 'Friend request sent to $name.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Delegates load live data to the ViewModel.
  Future<void> loadLiveData() => _screenModel.commandLoadLiveData();

  /// Delegates open undiscovered trail requests to the ViewModel.
  Future<void> _openUndiscoveredTrailRequests() =>
      _screenModel.commandOpenUndiscoveredTrailRequests();

  /// Adds trail by admin from home.
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
      await _HikerHomePageDataActions.createTrailByAdmin(hikerCircleRepository)(
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

  /// Computes edit trail by admin from home.
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
      await _HikerHomePageDataActions.updateTrailByAdmin(hikerCircleRepository)(
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

  /// Deletes trail by admin from home.
  Future<void> deleteTrailByAdminFromHome(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final shouldDelete = await _presentDeleteTrailByAdminFromHomeEffect1(trail);
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
      await _HikerHomePageDataActions.deleteTrailByAdmin(hikerCircleRepository)(
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

  /// Delegates read battery level to the ViewModel.
  Future<int?> _readBatteryLevel() => _screenModel.commandReadBatteryLevel();

  /// Delegates refresh battery level to the ViewModel.
  Future<void> _refreshBatteryLevel() =>
      _screenModel.commandRefreshBatteryLevel();

  /// Delegates hike with recorded location to the ViewModel.
  ActiveHikeSession _hikeWithRecordedLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location, {
    int? queuedUpdates,
    int? batteryLevel,
    int? checkIns,
  }) => _screenModel.commandHikeWithRecordedLocation(
    hike,
    location,
    queuedUpdates: queuedUpdates,
    batteryLevel: batteryLevel,
    checkIns: checkIns,
  );

  /// Updates tab index.
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

  /// Computes on tab tap.
  void onTabTap(int index) {
    _recordFallStillnessCancelTap();
    if (activeHike != null) {
      final visible = _visibleTabs();
      if (index < 0 || index >= visible.length) {
        return;
      }
      final label = visible[index].label;
      final actualIndex = tabs.indexWhere((t) => t.label == label);
      if (actualIndex < 0) {
        return;
      }
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

  /// Computes reveal active hike.
  void _revealActiveHike() {
    if (!mounted || activeHike == null) {
      return;
    }
    if (selectedTabIndex != 0) {
      setState(() => selectedTabIndex = 0);
    }
    tabController.animateTo(0);
    if (_hasTriggeredSos) {
      unawaited(() async {
        while (mounted && _hasTriggeredSos) {
          await _waitForTriggeredSosToClose();
        }
        if (mounted && activeHike != null) {
          HikeStartNavigation.revealHome(context);
        }
      }());
      return;
    }
    HikeStartNavigation.revealHome(context);
  }

  /// Computes new hazard start gate.
  TrailHazardStartGate _newHazardStartGate({
    bool Function()? isAttemptActive,
  }) => TrailHazardStartGate(
    load: hikerCircleRepository.loadTrailHazardAssessment,
    confirm: (alerts) async {
      while (mounted && _hasTriggeredSos) {
        await _waitForTriggeredSosToClose();
      }
      if (!mounted || isAttemptActive?.call() == false) {
        return TrailHazardAlertAction.abort;
      }
      return showTrailHazardAlertDialog(
        context,
        alerts: alerts,
        beforeStart: true,
      );
    },
    confirmUnavailable: () async {
      while (mounted && _hasTriggeredSos) {
        await _waitForTriggeredSosToClose();
      }
      if (!mounted || isAttemptActive?.call() == false) {
        return UnavailableHazardAction.abort;
      }
      return await showDialog<UnavailableHazardAction>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Latest trail reports are unavailable'),
              content: const Text(
                'We could not check for new cautions. Any cached reports may be out of date. Reconnect to retry, or continue offline after checking conditions yourself.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(UnavailableHazardAction.abort),
                  child: const Text('Go back'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(UnavailableHazardAction.retry),
                  child: const Text('Retry'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(UnavailableHazardAction.proceed),
                  child: const Text('Continue offline'),
                ),
              ],
            ),
          ) ??
          UnavailableHazardAction.abort;
    },
  );

  /// Delegates check hazards for start to the ViewModel.
  Future<bool> _checkHazardsForStart(
    TrailHazardStartGate gate,
    Trail trail, {
    UpcomingHike? upcomingHike,
  }) => _screenModel.commandCheckHazardsForStart(
    gate,
    trail,
    upcomingHike: upcomingHike,
  );

  /// Delegates confirm hazard cancellation to the ViewModel.
  Future<bool> _confirmHazardCancellation(UpcomingHike hike) =>
      _screenModel.commandConfirmHazardCancellation(hike);

  /// Delegates schedule another time after hazard to the ViewModel.
  Future<void> _scheduleAnotherTimeAfterHazard(
    Trail trail, {
    UpcomingHike? hike,
    String? hazardId,
  }) => _screenModel.commandScheduleAnotherTimeAfterHazard(
    trail,
    hike: hike,
    hazardId: hazardId,
  );

  /// Delegates open start hike wizard to the ViewModel.
  Future<void> openStartHikeWizard([Trail? trail]) =>
      _screenModel.commandOpenStartHikeWizard(trail);

  /// Delegates reschedule expired hike to the ViewModel.
  Future<void> _rescheduleExpiredHike(UpcomingHike hike) =>
      _screenModel.commandRescheduleExpiredHike(hike);

  /// Opens start hike wizard.
  Future<void> _openStartHikeWizard(
    Trail? trail, {
    bool startWithSchedule = false,
    UpcomingHike? rescheduleFrom,
  }) async {
    await AppSettingsController.instance.ready;
    await LocationUpdateIntervalController.instance.loadForUser(
      widget.session.phoneNumber,
    );
    if (!mounted) return;
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    if (trail == null) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Where are you hiking?',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const ValueKey('start-catalog-hike'),
                  enabled: trails.isNotEmpty,
                  leading: const Icon(Icons.route_rounded),
                  title: const Text('Choose a recorded trail'),
                  subtitle: const Text('Use an existing route and checkpoints'),
                  onTap: () => Navigator.pop(context, 'catalog'),
                ),
                ListTile(
                  key: const ValueKey('start-location-hike'),
                  leading: const Icon(Icons.my_location_rounded),
                  title: const Text('Hike from my current location'),
                  subtitle: const Text(
                    'Record a route that is not in HikerCircle',
                  ),
                  onTap: () => Navigator.pop(context, 'location'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || choice == null) {
        return;
      }
      if (choice == 'location') {
        try {
          final location = await LocationSnapshotService.instance.refresh();
          if (location == null ||
              !location.hasValidPosition ||
              location.capturedAt == null ||
              DateTime.now()
                      .toUtc()
                      .difference(location.capturedAt!.toUtc())
                      .abs() >
                  const Duration(minutes: 2)) {
            throw const HikerCircleFirebaseRepositoryException(
              'A fresh GPS location is needed. Enable location access and try again outdoors.',
            );
          }
          trail = Trail.fromPersistence({
            'trailId': 'unlisted_${DateTime.now().millisecondsSinceEpoch}',
            'name': 'Hike from current location',
            'latitude': location.latitude,
            'longitude': location.longitude,
            'routeProvider': 'recorded-location-hike',
            'estimatedDurationMinutes': 120,
            'checkpoints': <Map<String, dynamic>>[],
          });
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  error is HikerCircleFirebaseRepositoryException
                      ? error.message
                      : 'Unable to get your current location. Check location permission and retry.',
                ),
              ),
            );
          }
          return;
        }
      }
    }
    if (!mounted) {
      return;
    }
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    late final MaterialPageRoute<void> wizardRoute;
    final hazardGate = _newHazardStartGate(
      isAttemptActive: () => mounted && wizardRoute.isActive,
    );
    wizardRoute = MaterialPageRoute<void>(
      builder: (context) => StartHikeWizardPage(
        preselectedTrail: trail,
        availableTrails: trail?.isUnlisted == true ? [trail!] : trails,
        repository: hikerCircleRepository,
        session: widget.session,
        emergencyContactNames: emergencyContacts
            .map((contact) => contact.name)
            .toList(),
        onEditEmergencyContacts: _editSafetyContacts,
        initialShareLiveLocation:
            LiveLocationSharingService.instance.autoShareOnHikeStart,
        startWithSchedule: startWithSchedule,
        rescheduleFrom: rescheduleFrom,
        onScheduled: (_) => _restoreCachedUpcomingPlanningState(),
        onLocationSelected: (selected) => hazardGate.check(selected.trailId),
        onStartNow: (draft) =>
            _startInstantHikeFromWizard(draft, initialHazardGate: hazardGate),
      ),
    );
    await Navigator.of(context).push<void>(wizardRoute);
  }

  /// Computes review draft preparation.
  Future<PlannedHike?> _reviewDraftPreparation(
    HikeSessionDraft draft, {
    bool joiningTeam = false,
    String? upcomingHikeId,
    required Future<bool> Function(
      HikeSessionDraft draft,
      PlannedHike preparation,
    )
    onStart,
  }) async {
    final preview = PlannedHikeStateResolver.provisionalFromConfirmedDraft(
      draft: draft,
      creatorPhone: widget.session.phoneNumber,
      creatorName: '',
    );
    var plan = PlannedHikeStateResolver.resolve(
      upcomingHike: preview,
      liveTrails: trails,
      emergencyContactsSelected: emergencyContacts.isNotEmpty,
      phoneBatteryLevel: _latestPhoneBatteryLevel,
    );
    PlannedHike? reviewed;
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return null;

    /// Opens preparation.
    Future<String?> openPreparation(HikeSessionDraft safetyDraft) {
      plan = plan.copyWith(
        liveLocationConfigured: safetyDraft.shareLiveLocation,
        locationRecordingInterval: safetyDraft.locationRecordingInterval,
        emergencyContactsSelected: safetyDraft.emergencyContactNames.isNotEmpty,
      );
      return Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => FinalPreparationReviewPage(
            hike: preview,
            immediate: true,
            checkTrailheadOnStart: upcomingHikeId?.isNotEmpty == true,
            isHost: !joiningTeam,
            primaryActionLabel: joiningTeam
                ? 'Continue to team readiness'
                : null,
            canStart: true,
            plan: plan.copyWith(
              gearAssessment: _gearRouteService.peek(plan.trail),
            ),
            onPlanChanged: (value) async {
              plan = value;
            },
            onStart: (value) async {
              final started = await _tryPreparedHikeStart(
                () => onStart(safetyDraft, value),
              );
              if (started) reviewed = value;
              return started;
            },
            loadBatteryLevel: _readBatteryLevel,
            loadRouteAnalysis: draft.trail.isUnlisted
                ? null
                : (force) => _analyzeGearRoute(plan, force: force),
            loadWeather: () => HikeBriefingWeatherService.shared.fetch(
              plan.trail.latitude,
              plan.trail.longitude,
              force: true,
            ),
          ),
        ),
      );
    }

    final action = joiningTeam
        ? await _presentReviewDraftPreparationEffect1(
            draft,
            upcomingHikeId,
            openPreparation,
          )
        : await openPreparation(draft);
    if (!mounted ||
        action != 'start' ||
        reviewed == null ||
        !reviewed!.requiredGearReady) {
      return null;
    }
    return reviewed;
  }

  /// Delegates try prepared hike start to the ViewModel.
  Future<bool> _tryPreparedHikeStart(Future<bool> Function() start) =>
      _screenModel.commandTryPreparedHikeStart(start);

  /// Keep preparation on the navigator until its start attempt succeeds.
  Future<bool> _startInstantHikeFromWizard(
    HikeSessionDraft draft, {
    TrailHazardStartGate? initialHazardGate,
  }) => _screenModel.commandStartInstantHikeFromWizard(
    draft,
    initialHazardGate: initialHazardGate,
  );

  /// Starts prepared instant hike.
  Future<bool> _startPreparedInstantHike(
    HikeSessionDraft draft,
    PlannedHike reviewed, {
    TrailHazardStartGate? initialHazardGate,
  }) async {
    if (draft.trail.isUnlisted) {
      final location = await LocationSnapshotService.instance.refresh();
      if (!mounted) {
        return false;
      }
      if (location == null ||
          !location.hasValidPosition ||
          location.capturedAt == null ||
          DateTime.now()
                  .toUtc()
                  .difference(location.capturedAt!.toUtc())
                  .abs() >
              const Duration(minutes: 2)) {
        throw const HikerCircleFirebaseRepositoryException(
          'A recent GPS fix is needed before starting this location hike.',
        );
      }
      draft = draft.copyWith(
        trail: draft.trail.copyWith(
          latitude: location.latitude,
          longitude: location.longitude,
        ),
        pathDeviationEnabled: false,
      );
    }
    draft = _applyReviewedPreparation(draft, reviewed);
    final checked = await confirmSoloHikeDistance(
      context,
      draft,
      starting: true,
    );
    if (!mounted || checked == null) {
      return false;
    }
    draft = checked;
    if (!mounted) {
      return false;
    }
    final hazardGate = initialHazardGate ?? _newHazardStartGate();
    if (!await _checkHazardsForStart(hazardGate, draft.trail) || !mounted) {
      return false;
    }
    var hikeToStart = ActiveHikeSession.fromDraft(draft);
    if (hikeToStart.draft.hikeType == HikeType.team) {
      final teamSession = await _coordinateTeamHikeStart(
        hikeToStart.draft,
        confirmReportedHazards: () =>
            _checkHazardsForStart(hazardGate, draft.trail),
      );
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

    if (!await _checkHazardsForStart(hazardGate, draft.trail) || !mounted) {
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
    DialogRoute<void>? startProgressRoute;
    var progressClosed = false;
    startProgressDelayTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || progressClosed) {
        return;
      }
      startProgressRoute = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HikeStartProgressDialog(progress: startProgress),
      );
      startProgressDialogFuture = Navigator.of(
        context,
        rootNavigator: true,
      ).push(startProgressRoute!);
      unawaited(startProgressDialogFuture);
    });

    /// Closes start progress dialog.
    void closeStartProgressDialog() {
      if (progressClosed) {
        return;
      }
      progressClosed = true;
      startProgressDelayTimer?.cancel();
      _presentStartPreparedInstantHikeEffect1(startProgressRoute);
      final future = startProgressDialogFuture;
      if (future == null) {
        startProgress.dispose();
      } else {
        unawaited(future.whenComplete(startProgress.dispose));
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
      liveHike =
          await _HikerHomePageDataActions.createActiveHikeSession(
            hikerCircleRepository,
          )(
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
    } catch (_) {
      closeStartProgressDialog();
      if (mounted) {
        _showUpcomingHikeError('Unable to start hike', 'Please try again.');
      }
      return false;
    }

    try {
      if (!mounted) {
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
      await _activeHikePersistenceQueue;
      if (!mounted) {
        return false;
      }
      tabController.animateTo(0);
      unawaited(_recordInitialActiveHikeLocation(liveHike));
      return true;
    } finally {
      closeStartProgressDialog();
    }
  }

  /// Computes coordinate team hike start.
  Future<TeamHikeSession?> _coordinateTeamHikeStart(
    HikeSessionDraft draft, {
    String sourceUpcomingHikeId = '',
    required Future<bool> Function() confirmReportedHazards,
  }) async {
    TeamHikeSession teamSession;
    try {
      teamSession =
          await _HikerHomePageDataActions.createTeamHikeSession(
            hikerCircleRepository,
          )(
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

    // The team may have started before a previous local startup attempt failed.
    if (teamSession.phase == TeamHikePhase.active) return teamSession;
    try {
      teamSession = await _HikerHomePageDataActions.beginTeamHikeReadiness(
        hikerCircleRepository,
      )(session: widget.session, teamHikeSessionId: teamSession.id);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        HikerCircleToast.show(
          context,
          error.message,
          tone: HikerCircleToastTone.error,
          title: 'Could not alert the team',
        );
      }
      return null;
    }

    if (!mounted) {
      return null;
    }

    _navigatingTeamSessionId = teamSession.id;
    try {
      final launchedSession = await _presentCoordinateTeamHikeStartEffect1(
        teamSession,
        draft,
        confirmReportedHazards,
      );
      if (launchedSession == null && sourceUpcomingHikeId.trim().isEmpty) {
        try {
          await _HikerHomePageDataActions.cancelTeamHikeSession(
            hikerCircleRepository,
          )(session: widget.session, teamHikeSessionId: teamSession.id);
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

  /// Delegates record initial active hike location to the ViewModel.
  Future<void> _recordInitialActiveHikeLocation(ActiveHikeSession hike) =>
      _screenModel.commandRecordInitialActiveHikeLocation(hike);

  /// Delegates check in active hike to the ViewModel.
  Future<ActiveHikeSession> checkInActiveHike(ActiveHikeSession currentHike) =>
      _screenModel.commandCheckInActiveHike(currentHike);

  /// Computes ping team member.
  Future<TeamHikeSession?> _pingTeamMember(String phoneNumber) async {
    final currentHike = activeHike;
    if (currentHike == null || currentHike.teamHikeSessionId.isEmpty) {
      return null;
    }
    try {
      final teamSession =
          await _HikerHomePageDataActions.pingTeamParticipant(
            hikerCircleRepository,
          )(
            session: widget.session,
            teamHikeSessionId: currentHike.teamHikeSessionId,
            participantPhoneNumber: phoneNumber,
          );
      if (mounted &&
          activeHike?.sessionId == currentHike.sessionId &&
          !_isEndingActiveHike) {
        final updatedHike = _withTeamHikeSessionLink(activeHike!, teamSession);
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

  /// Reveals the live session instead of pushing a separate map snapshot.
  void _openActiveHikeSessionFromDeepLink() {
    if (!mounted) return;
    if (activeHike == null) {
      _showNoActiveHikeSnackBar();
      return;
    }
    _revealActiveHike();
  }

  /// Opens active hike hazard report.
  Future<void> _openActiveHikeHazardReport() async {
    final hike = activeHike;
    if (!mounted ||
        hike == null ||
        _isEndingActiveHike ||
        _isOpeningHazardReport) {
      return;
    }
    _isOpeningHazardReport = true;
    try {
      setState(() => selectedTabIndex = 0);
      tabController.animateTo(0);
      await _presentOpenActiveHikeHazardReportEffect1(hike);
    } finally {
      _isOpeningHazardReport = false;
    }
  }

  /// Delegates apply active hike check in to the ViewModel.
  Future<void> _applyActiveHikeCheckIn(ActiveHikeSession hike) =>
      _screenModel.commandApplyActiveHikeCheckIn(hike);

  /// Shows active hike action error.
  void _showActiveHikeActionError(String prefix, Object error) {
    if (!mounted) {
      return;
    }
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

  /// Shows no active hike snack bar.
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

  /// Shows upcoming hike details.
  Future<void> _showUpcomingHikeDetails(
    UpcomingHike hike, {
    Iterable<Trail>? availableTrails,
    String? hazardId,
  }) async {
    if (activeHike?.sourceUpcomingHikeId == hike.id) {
      _revealActiveHike();
      return;
    }
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
    if (!mounted) {
      return;
    }
    var plan = PlannedHikeStateResolver.resolve(
      upcomingHike: hike,
      liveTrails: trails,
      emergencyContactsSelected: emergencyContacts.isNotEmpty,
      phoneBatteryLevel: _latestPhoneBatteryLevel,
      completedChecklistItems: _plannedChecklistByUpcomingId[hike.id],
    );
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) {
          final details = HikeSafetySettingsPage(
            initialDraft: _draftForUpcomingHike(hike, plan.trail),
            loadDraft: () => _loadHikeSafetyDraft(
              _draftForUpcomingHike(hike, plan.trail),
              hike.id,
            ),
            onSave: (value) => _saveHikeSafetyDraft(value, hike.id),
            onEditContacts: _editSafetyContacts,
            onContinue: (safetyDraft) {
              plan = plan.copyWith(
                liveLocationConfigured: safetyDraft.shareLiveLocation,
                locationRecordingInterval:
                    safetyDraft.locationRecordingInterval,
                emergencyContactsSelected:
                    safetyDraft.emergencyContactNames.isNotEmpty,
              );
              return Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => FinalPreparationReviewPage(
                    hike: hike,
                    isHost: _sameTeamPhone(
                      hike.creatorPhone,
                      widget.session.phoneNumber,
                    ),
                    canStart:
                        _sameTeamPhone(
                          hike.creatorPhone,
                          widget.session.phoneNumber,
                        ) &&
                        trail != null &&
                        !hike.isLocalPendingSync,
                    plan: plan.copyWith(
                      gearAssessment: _gearRouteService.peek(plan.trail),
                    ),
                    onPlanChanged: (value) async {
                      plan = value;
                      await _updatePlannedHike(value);
                    },
                    onStart: (value) async {
                      final startTrail = trail;
                      if (startTrail == null || hike.isLocalPendingSync) {
                        return false;
                      }
                      return _tryPreparedHikeStart(
                        () => _startUpcomingHikeNow(
                          hike: hike,
                          preparation: value,
                          draft: safetyDraft,
                        ),
                      );
                    },
                    loadBatteryLevel: _readBatteryLevel,
                    loadRouteAnalysis: (force) =>
                        _analyzeGearRoute(plan, force: force),
                    loadWeather: () => HikeBriefingWeatherService.shared.fetch(
                      plan.trail.latitude,
                      plan.trail.longitude,
                      force: true,
                    ),
                    onCancel: () => _cancelUpcomingHike(hike),
                  ),
                ),
              );
            },
          );
          if (hazardId != null && hazardId.isNotEmpty) {
            final detailsRoute = ModalRoute.of<String>(context);
            final isParticipant =
                _sameTeamPhone(hike.creatorPhone, widget.session.phoneNumber) ||
                hike.participantPhones.any(
                  (phone) => _sameTeamPhone(phone, widget.session.phoneNumber),
                );
            return HikeHazardAlertHost(
              loadAlerts: () async {
                final assessment =
                    await _HikerHomePageDataActions.loadTrailHazardAssessment(
                      hikerCircleRepository,
                    )(hike.trailId);
                if (!assessment.isFresh) {
                  throw const HikerCircleFirebaseRepositoryException(
                    'Connect to check the current report.',
                  );
                }
                return assessment.alerts
                    .where((alert) => alert.id == hazardId)
                    .toList();
              },
              canCancelHike: isParticipant,
              onAction: (action) async {
                if (!mounted) return;
                if (action == TrailHazardAlertAction.cancelHike) {
                  if (!await _confirmHazardCancellation(hike) || !mounted) {
                    return;
                  }
                  await _cancelUpcomingHike(hike, hazardId: hazardId);
                  HikeStartNavigation.completeFlow(detailsRoute, 'cancelled');
                } else if (action == TrailHazardAlertAction.reschedule) {
                  final nextTrail = trail;
                  if (nextTrail == null) {
                    throw const HikerCircleFirebaseRepositoryException(
                      'This trail could not be loaded. Try again.',
                    );
                  }
                  await _scheduleAnotherTimeAfterHazard(
                    nextTrail,
                    hike: hike,
                    hazardId: hazardId,
                  );
                }
              },
              child: details,
            );
          }
          return details;
        },
      ),
    );
    if (!mounted) {
      return;
    }
    if (result == 'contacts') {
      openSosTab();
    } else if (result == 'viewTrail' && trail != null) {
      openTrailDetail(trail);
    } else if (result == 'directions') {
      await _openUpcomingHikeDirections(hike);
    } else if (result == 'start') {
      _revealActiveHike();
    }
  }

  /// Cancels upcoming hike.
  Future<void> _cancelUpcomingHike(
    UpcomingHike hike, {
    String? hazardId,
  }) async {
    var target = hike;
    if (hike.isLocalPendingSync) {
      final confirmed = await _HikerHomePageDataActions.loadMyUpcomingHikes(
        hikerCircleRepository,
      )(widget.session.phoneNumber);
      final matches = confirmed.where(
        (candidate) =>
            PlannedHikeStateResolver.representsSameSchedule(candidate, hike),
      );
      if (matches.isEmpty) {
        throw const HikerCircleFirebaseRepositoryException(
          'Reconnect and let this hike finish syncing before cancelling it.',
        );
      }
      target = matches.first;
    }
    await _HikerHomePageDataActions.cancelUpcomingHike(hikerCircleRepository)(
      hikeId: target.id,
      withdrawSelf: !_sameTeamPhone(
        target.creatorPhone,
        widget.session.phoneNumber,
      ),
      hazardId: hazardId,
    );
    for (final id in {hike.id, target.id}) {
      try {
        await _HikerHomePageDataActions.markPlannedHikeConsumed(
          hikerCircleRepository.localDatabase,
        )(ownerPhoneNumber: widget.session.phoneNumber, upcomingHikeId: id);
      } catch (error) {
        // The server change has committed. Do not report cancellation failure
        // because optional local cleanup failed; the live roster will reconcile.
        debugPrint('Cancelled hike local cleanup is pending: $error');
      }
    }
    if (!mounted) {
      return;
    }
    _upcomingPlanningRevision++;
    setState(() {
      _consumedUpcomingHikeIds = {
        ..._consumedUpcomingHikeIds,
        hike.id,
        target.id,
      };
      myUpcomingHikes = myUpcomingHikes
          .where(
            (item) =>
                !PlannedHikeStateResolver.representsSameSchedule(item, hike),
          )
          .toList();
      _rebuildPlannedHike();
    });
  }

  /// Opens upcoming hike directions.
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

  /// Shows upcoming hike error.
  void _showUpcomingHikeError(String title, String detail) {
    if (!mounted) {
      return;
    }
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

  /// Starts hike from dashboard.
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

  /// Delegates draft for upcoming hike to the ViewModel.
  HikeSessionDraft _draftForUpcomingHike(UpcomingHike hike, Trail trail) =>
      _screenModel.commandDraftForUpcomingHike(hike, trail);

  /// Starts upcoming hike now.
  Future<bool> _startUpcomingHikeNow({
    required UpcomingHike hike,
    required HikeSessionDraft draft,
    PlannedHike? preparation,
  }) async {
    if (preparation == null || !preparation.requiredGearReady) {
      await _showUpcomingHikeDetails(hike);
      return activeHike?.sourceUpcomingHikeId == hike.id;
    }
    try {
      final current =
          await _HikerHomePageDataActions.loadParticipantUpcomingHikeForSafety(
            hikerCircleRepository,
          )(hikeId: hike.id, session: widget.session);
      if (current == null) {
        throw const HikerCircleFirebaseRepositoryException(
          'This hike is no longer upcoming.',
        );
      }
      hike = current;
      final currentRoster = _draftForUpcomingHike(current, draft.trail);
      draft = draft.copyWith(
        hikeType: currentRoster.hikeType,
        teamBuddies: currentRoster.teamBuddies,
        clearSoloDistanceAcknowledgement:
            draft.hikeType == HikeType.team &&
            currentRoster.hikeType == HikeType.solo,
      );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!error.allowsOfflineFallback) rethrow;
      // The existing offline start remains available. The report gate below
      // requires explicit consent whenever current reports cannot be fetched.
    }
    if (!mounted) return false;
    draft = _applyReviewedPreparation(draft, preparation);
    final checked = await confirmSoloHikeDistance(
      context,
      draft,
      starting: true,
    );
    if (!mounted || checked == null) {
      return false;
    }
    draft = checked;
    final hazardGate = _newHazardStartGate();

    /// Computes confirm hazards.
    Future<bool> confirmHazards() =>
        _checkHazardsForStart(hazardGate, draft.trail, upcomingHike: hike);
    if (!await confirmHazards() || !mounted) return false;
    var hikeToStart = ActiveHikeSession.fromDraft(
      draft,
      sourceUpcomingHikeId: hike.id,
    );
    if (draft.hikeType == HikeType.team && draft.teamBuddies.isNotEmpty) {
      final teamSession = await _coordinateTeamHikeStart(
        draft,
        sourceUpcomingHikeId: hike.id,
        confirmReportedHazards: confirmHazards,
      );
      if (teamSession == null || !mounted) {
        return false;
      }
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
      if (!volumeReady || !mounted) {
        return false;
      }
    }
    if (!await _ensureBackgroundSafetyReady(hikeToStart.draft) || !mounted) {
      return false;
    }
    if (!await confirmHazards() || !mounted) return false;
    final startProgress = ValueNotifier<_HikeStartProgress>(
      const _HikeStartProgress(
        title: 'Starting scheduled hike',
        message: 'Preparing your route and safety tools.',
        progress: 0.18,
        icon: Icons.hiking_rounded,
      ),
    );
    final progressContextReady = Completer<BuildContext>();
    final progressDialogFuture = _presentStartUpcomingHikeNowEffect1(
      progressContextReady,
      startProgress,
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
        liveHike =
            await _HikerHomePageDataActions.createActiveHikeSession(
              hikerCircleRepository,
            )(
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
          return false;
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
      if (!mounted) {
        return false;
      }

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
        _HikerHomePageDataActions.markPlannedHikeConsumed(
          hikerCircleRepository.localDatabase,
        )(
          ownerPhoneNumber: widget.session.phoneNumber,
          upcomingHikeId: hike.id,
        ),
      );
      _syncActiveHikeServices(liveHike, forceLiveStatus: true);
      await _activeHikePersistenceQueue;
      if (!mounted) {
        return false;
      }
      tabController.animateTo(0);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    } finally {
      if (progressContext.mounted) {
        _presentStartUpcomingHikeNowEffect2(progressContext);
      }
      unawaited(progressDialogFuture.whenComplete(startProgress.dispose));
    }
    if (!mounted) {
      return false;
    }
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
    return true;
  }

  /// Delegates apply team safety settings to the ViewModel.
  HikeSessionDraft _applyTeamSafetySettings(
    HikeSessionDraft draft,
    TeamHikeSession teamSession,
  ) => _screenModel.commandApplyTeamSafetySettings(draft, teamSession);

  /// Delegates open find hike to the ViewModel.
  Future<void> _openFindHike() => _screenModel.commandOpenFindHike();

  String? _navigatingTeamSessionId;

  /// Opens team hike invite.
  Future<void> _openTeamHikeInvite(String teamHikeSessionId) async {
    if (_navigatingTeamSessionId == teamHikeSessionId) {
      return;
    }
    _navigatingTeamSessionId = teamHikeSessionId;
    try {
      if (!mounted) {
        _navigatingTeamSessionId = null;
        return;
      }
      final pendingSession =
          await _HikerHomePageDataActions.loadTeamHikeSession(
            hikerCircleRepository,
          )(teamHikeSessionId);
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
      final readinessKey = _teamReadinessKey(pendingSession);
      if (readinessKey != null &&
          !_presentedTeamReadinessKeys.add(readinessKey)) {
        return;
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
      final acceptedSession =
          await _HikerHomePageDataActions.acceptTeamHikeInvite(
            hikerCircleRepository,
          )(session: widget.session, teamHikeSessionId: teamHikeSessionId);
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
        _revealActiveHike();
        return;
      }
      final sharedDraft =
          acceptedSession.sharedDraft ?? pendingSession.sharedDraft;
      var draft =
          (sharedDraft ??
                  HikeSessionDraft.fromTrail(trail).copyWith(
                    locationRecordingInterval:
                        LocationUpdateIntervalController.instance.interval,
                  ))
              .copyWith(
                trail: trail,
                hikeType: HikeType.team,
                shareLiveLocation:
                    LiveLocationSharingService.instance.autoShareOnHikeStart,
                // A participant must confirm their own gear, never inherit the host's checks.
                completedChecklistItems:
                    _plannedChecklistByUpcomingId[acceptedSession
                        .sourceUpcomingHikeId] ??
                    const <String>{},
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
      final reviewed = await _reviewDraftPreparation(
        draft,
        joiningTeam: true,
        upcomingHikeId: acceptedSession.sourceUpcomingHikeId,
        onStart: (safetyDraft, preparation) =>
            _startJoinedTeamHike(acceptedSession, safetyDraft, preparation),
      );
      if (mounted && reviewed != null) _revealActiveHike();
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
      unawaited(_drainPendingTeamReadiness());
    }
  }

  /// Starts joined team hike.
  Future<bool> _startJoinedTeamHike(
    TeamHikeSession acceptedSession,
    HikeSessionDraft draft,
    PlannedHike preparation,
  ) async {
    draft = _applyReviewedPreparation(draft, preparation);
    final hazardGate = _newHazardStartGate();
    UpcomingHike? upcoming = myUpcomingHikes
        .where((hike) => hike.id == acceptedSession.sourceUpcomingHikeId)
        .firstOrNull;
    if (upcoming == null && acceptedSession.sourceUpcomingHikeId.isNotEmpty) {
      try {
        upcoming =
            await _HikerHomePageDataActions.loadParticipantUpcomingHikeForSafety(
              hikerCircleRepository,
            )(
              hikeId: acceptedSession.sourceUpcomingHikeId,
              session: widget.session,
            );
      } on HikerCircleFirebaseRepositoryException catch (error) {
        if (!error.allowsOfflineFallback) rethrow;
      }
    }

    /// Computes confirm hazards.
    Future<bool> confirmHazards() =>
        _checkHazardsForStart(hazardGate, draft.trail, upcomingHike: upcoming);
    if (!await confirmHazards() || !mounted) return false;
    final launchedSession = await _presentStartJoinedTeamHikeEffect1(
      acceptedSession,
      draft,
      confirmHazards,
    );
    if (launchedSession == null || !mounted) {
      return false;
    }
    if (!await confirmHazards() || !mounted) return false;
    final participant = launchedSession.participants
        .where(
          (item) =>
              _sameTeamPhone(item.phoneNumber, widget.session.phoneNumber),
        )
        .firstOrNull;
    final safety = participant?.safetySettings ?? const <String, dynamic>{};
    final preparedDraft = draft.copyWith(
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
    final preparedHike = ActiveHikeSession.fromDraft(
      preparedDraft,
      teamHikeSessionId: launchedSession.id,
      teamHikeSession: launchedSession,
      sourceUpcomingHikeId: launchedSession.sourceUpcomingHikeId,
    );
    ActiveHikeSession liveHike;
    try {
      liveHike =
          await _HikerHomePageDataActions.createActiveHikeSession(
            hikerCircleRepository,
          )(
            session: widget.session,
            draft: preparedHike.draft,
            teamHikeSessionId: launchedSession.id,
            teamHikeSession: launchedSession,
            sourceUpcomingHikeId: launchedSession.sourceUpcomingHikeId,
          );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!error.allowsOfflineFallback) {
        rethrow;
      }
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
      return false;
    }
    setState(() {
      activeHike = liveHike;
      selectedTabIndex = 0;
    });
    _syncActiveHikeServices(liveHike, forceLiveStatus: true);
    await _activeHikePersistenceQueue;
    unawaited(_recordInitialActiveHikeLocation(liveHike));
    return true;
  }

  /// Computes respond to team ping.
  Future<void> _respondToTeamPing(String teamHikeSessionId) async {
    try {
      if (!mounted) {
        return;
      }
      final shouldRespond = await _presentRespondToTeamPingEffect1();
      if (shouldRespond != true || !mounted) {
        return;
      }
      final teamSession = await _HikerHomePageDataActions.respondToTeamPing(
        hikerCircleRepository,
      )(session: widget.session, teamHikeSessionId: teamHikeSessionId);
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

  /// Delegates edit safety contacts to the ViewModel.
  Future<List<String>> _editSafetyContacts() =>
      _screenModel.commandEditSafetyContacts();

  /// Delegates load hike safety draft to the ViewModel.
  Future<HikeSessionDraft> _loadHikeSafetyDraft(
    HikeSessionDraft draft,
    String? hikeId,
  ) => _screenModel.commandLoadHikeSafetyDraft(draft, hikeId);

  /// Delegates save hike safety draft to the ViewModel.
  Future<void> _saveHikeSafetyDraft(HikeSessionDraft draft, String? hikeId) =>
      _screenModel.commandSaveHikeSafetyDraft(draft, hikeId);

  /// Delegates apply reviewed preparation to the ViewModel.
  HikeSessionDraft _applyReviewedPreparation(
    HikeSessionDraft draft,
    PlannedHike plan,
  ) => _screenModel.commandApplyReviewedPreparation(draft, plan);

  /// Delegates open emergency contacts to the ViewModel.
  Future<void> openEmergencyContacts() =>
      _screenModel.commandOpenEmergencyContacts();

  /// Opens trail detail.
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

  /// Opens sos tab.
  void openSosTab() {
    setState(() {
      selectedTabIndex = 1;
    });
    tabController.animateTo(1);
  }

  /// Handles sos presentation changed.
  void _handleSosPresentationChanged() {
    if (!mounted) return;
    if (_hasTriggeredSos) {
      _precautionAnnouncer.dismiss();
      _hikeWarningSpeech.synchronizeSession(null);
      return;
    }
    unawaited(_drainPendingFcmOpens());
    unawaited(_drainPendingBleUiEvents());
    unawaited(_drainPendingTeamReadiness());
    _promptForFormedTeamChatName(_pendingFormedTeamChats);
  }

  /// Delegates wait for triggered sos to close to the ViewModel.
  Future<void> _waitForTriggeredSosToClose() =>
      _screenModel.commandWaitForTriggeredSosToClose();

  /// Delegates stop triggered sos outputs to the ViewModel.
  Future<void> _stopTriggeredSosOutputs({
    String? nativeEventId,
    int? expectedEventId,
  }) => _screenModel.commandStopTriggeredSosOutputs(
    nativeEventId: nativeEventId,
    expectedEventId: expectedEventId,
  );

  /// Stops presented sos.
  Future<void> _stopPresentedSos(int eventId) async {
    if (_sosPresentation.current?.eventId != eventId ||
        !_stoppingSosPresentationIds.add(eventId)) {
      return;
    }
    try {
      final nativeIds = _nativeSosPresentationIds.entries
          .where((entry) => entry.value == eventId)
          .map((entry) => entry.key)
          .toList();
      _stoppedNativeSosPresentationIds.addAll(nativeIds);
      await _sosPresentation.stopAlarm();
      if (!mounted || _sosPresentation.current?.eventId != eventId) return;
      // Manual/medical/duress may overlap a detector event. Stop its local
      // outputs too; a native presentation already owns this cleanup callback.
      if (nativeIds.isEmpty) {
        await _stopTriggeredSosOutputs(expectedEventId: eventId);
      }
      if (!mounted || _sosPresentation.current?.eventId != eventId) return;
      _sosPresentation.dismiss(eventId);
    } finally {
      _stoppingSosPresentationIds.remove(eventId);
    }
  }

  /// Delegates present native triggered sos to the ViewModel.
  int? _presentNativeTriggeredSos(NativeHikeSafetyEvent event) =>
      _screenModel.commandPresentNativeTriggeredSos(event);

  /// Computes request manual sos.
  void requestManualSos() {
    setState(() {
      selectedTabIndex = 1;
      _manualSosRequestSequence += 1;
      _pendingManualSosRequestId = _manualSosRequestSequence;
    });
    tabController.animateTo(1);
  }

  /// Computes request immediate sos.
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

  /// Delegates consume manual sos request to the ViewModel.
  void _consumeManualSosRequest(int requestId) =>
      _screenModel.commandConsumeManualSosRequest(requestId);

  /// Delegates consume immediate sos request to the ViewModel.
  void _consumeImmediateSosRequest(int requestId) =>
      _screenModel.commandConsumeImmediateSosRequest(requestId);

  /// Shows ble sos help popup for location.
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

    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
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

  /// Delegates handle paired sos button event to the ViewModel.
  void _handlePairedSosButtonEvent(HikerBlePairedSosButtonEvent event) =>
      _screenModel.commandHandlePairedSosButtonEvent(event);

  /// Handles nearby sos button event.
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

  /// Delegates present nearby sos after location wait to the ViewModel.
  Future<void> _presentNearbySosAfterLocationWait(String key, int? rssi) =>
      _screenModel.commandPresentNearbySosAfterLocationWait(key, rssi);

  /// Handles nearby sos location event.
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
    if (location != null) {
      _exactNearbySosLocations[key] = location;
    }
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

  /// Delegates handle ble sos help event to the ViewModel.
  Future<void> _handleBleSosHelpEvent(HikerBleSosHelpEvent event) =>
      _screenModel.commandHandleBleSosHelpEvent(event);

  /// Delegates record nearby sos event to the ViewModel.
  Future<void> _recordNearbySosEvent({
    required String deviceId,
    required DateTime receivedAt,
    int? counter,
    int? rssi,
    SosTriggerLocation? location,
  }) => _screenModel.commandRecordNearbySosEvent(
    deviceId: deviceId,
    receivedAt: receivedAt,
    counter: counter,
    rssi: rssi,
    location: location,
  );

  // Retained for the legacy map widget below; nearby paired-button alerts no
  // longer display this estimate and use the relayed GPS coordinate instead.
  /// Computes ble range meters.
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

  /// Shows nearby sos button popup.
  Future<void> _showNearbySosButtonPopup({
    int? rssi,
    SosTriggerLocation? location,
  }) async {
    if (!mounted) {
      return;
    }
    while (mounted && _hasTriggeredSos) {
      await _waitForTriggeredSosToClose();
    }
    if (!mounted) return;
    await _presentShowNearbySosButtonPopupEffect1(location, rssi);
  }

  /// Delegates format ble sos help time to the ViewModel.
  String _formatBleSosHelpTime(DateTime value) =>
      _screenModel.commandFormatBleSosHelpTime(value);

  /// Checks whether usable ble coordinate.
  static bool _isUsableBleCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  /// Computes launch external uri.
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
      if (!mounted) {
        return;
      }
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

  /// Delegates sign out and clear active hike to the ViewModel.
  void _signOutAndClearActiveHike() =>
      _screenModel.commandSignOutAndClearActiveHike();

  /// Delegates request sign out to the ViewModel.
  Future<void> _requestSignOut() => _screenModel.commandRequestSignOut();

  /// Delegates perform sign out to the ViewModel.
  Future<void> _performSignOut() => _screenModel.commandPerformSignOut();

  int _lastMapStyleIndex = 0;

  /// Computes prompt for trail rating.
  Future<void> _promptForTrailRating(
    ActiveHikeSession completedHike,
    HikeSummaryReport summary,
  ) async {
    final submitted = await _presentPromptForTrailRatingEffect1(
      completedHike,
      summary,
    );
    if (!mounted || submitted != true) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks — your rating and difficulty vote are now included.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Save the final route and report before stopping tracking or opening the end-hike sharing flow.
  Future<void> _endActiveHikeSession({bool signOutAfter = false}) async {
    var hikeToEnd = activeHike;
    if (hikeToEnd == null || _isEndingActiveHike) {
      return;
    }
    if (mounted) {
      setState(() => _isEndingActiveHike = true);
    } else {
      _isEndingActiveHike = true;
    }
    _precautionAnnouncer.dismiss();

    final endedAt = DateTime.now();
    var report = HikeSummaryReport.fromActiveHike(
      activeHike: hikeToEnd,
      endedAt: endedAt,
    );

    ActiveHikeEndResult endResult;
    try {
      await _activeLocationWrite?.future;
      await _drainNativeLocationSamples(hikeToEnd);
      hikeToEnd = activeHike ?? hikeToEnd;
      report = HikeSummaryReport.fromActiveHike(
        activeHike: hikeToEnd,
        endedAt: endedAt,
      );
      endResult = await _HikerHomePageDataActions.endHikeSession(
        hikerCircleRepository,
      )(session: widget.session, activeHike: hikeToEnd, summary: report);
    } catch (error) {
      if (mounted) {
        setState(() => _isEndingActiveHike = false);
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
      await Future.wait([
        _sosDeviceAlertService.stopFallStillnessCountdownVibration(),
        _sosDeviceAlertService.stopSpokenPrompt(),
        _sosDeviceAlertService.stopManualSosPattern(),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Native safety outputs are best effort when ending a hike.
    }
    _syncActiveHikeServices(null, stopNativeLiveStatus: false);
    // Completion must not return control to the summary/rating UI while the
    // native persisted monitor can still relaunch or schedule watchdog alerts.
    _nativeHikeStopPending = !await _activeHikeLiveStatusService.stop();
    await _activeHikePersistenceQueue;
    isFallStillnessLocalAlarmActive = false;
    if (!mounted) {
      return;
    }

    setState(() {
      activeHike = null;
      _isEndingActiveHike = false;
    });

    if (_nativeHikeStopPending) {
      _presentEndActiveHikeSessionEffect1();
    }
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
              'Hike saved on this phone. Cloud confirmation is still pending and will retry automatically.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    if (signOutAfter) {
      await _performSignOut();
      return;
    }
    if (endResult.status == 'abandoned') {
      return;
    }

    if (endResult.canCollectFeedback && !completedHike.trail.isUnlisted) {
      await _promptForTrailRating(completedHike, completedReport);
      if (!mounted) {
        return;
      }
    }

    await _presentEndActiveHikeSessionEffect2(
      completedReport,
      completedHike,
      endResult,
    );
  }

  /// Returns admin runtime debug data.
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

  /// Computes page for.
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
            onReportHazard: () => unawaited(_openActiveHikeHazardReport()),
            onPingTeamMember: _pingTeamMember,
            onMapStyleChanged: (index) =>
                setState(() => _lastMapStyleIndex = index),
            onCheckIn: () {
              final hike = activeHike;
              if (hike != null) {
                unawaited(_applyActiveHikeCheckIn(hike));
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
          onReviewTrailRequestsByAdmin:
              widget.session.isAdmin && _hasPendingUndiscoveredTrailRequests
              ? () => unawaited(_openUndiscoveredTrailRequests())
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
          onPingTeamMember: _pingTeamMember,
          onEndHike: () => unawaited(_endActiveHikeSession()),
          fallStillnessSnapshot: fallStillnessMonitor.snapshot,
          onCancelFallStillnessSos: () =>
              _cancelFallStillnessSos('Phone tap response received'),
        );
      case 'SOS':
        return SosPage(
          session: widget.session,
          presentationController: _sosPresentation,
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
          buddyRequestsOpenId: _buddyRequestsOpenId,
          onBuddyRequestsOpenHandled: () {
            if (mounted) setState(() => _buddyRequestsOpenId = 0);
          },
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
      case 'Profile':
        return MePage(
          session: widget.session,
          phoneNumber: widget.session.phoneNumber,
          onSignOut: _signOutAndClearActiveHike,
          onStartHike: (trail) => openStartHikeWizard(trail),
          onRescheduleExpiredHike: _rescheduleExpiredHike,
          onOpenSos: openSosTab,
          onOpenNotificationLink: (link) =>
              _handleDeepLink(link, allowRepeat: true),
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

  /// Responds to foreground and background transitions.
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
      setState(_rebuildPlannedHike);
      unawaited(_deliverAchievementNotifications());
      unawaited(
        _HikerHomePageDataActions.flushPendingUpcomingHikes(
          hikerCircleRepository,
        )(session: widget.session),
      );
      unawaited(_retryQueuedSosAlerts());
      unawaited(_drainPendingFcmOpens());
      unawaited(_drainPendingBleUiEvents());
      unawaited(_drainPendingTeamReadiness());
      unawaited(_resumeBleSosMonitor());
      unawaited(_consumePendingNativeSafetyEvent());
      if (hike != null) {
        unawaited(
          _sendActiveHikeMonitoringHeartbeat(hike, lifecycleState: 'active'),
        );
        _startActiveHikeLocationRecording(hike);
        unawaited(
          _runReconnectStep(
            'native GPS transfer',
            () => _drainNativeLocationSamples(hike),
          ),
        );
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

  /// Delegates resume ble sos monitor to the ViewModel.
  Future<void> _resumeBleSosMonitor() =>
      _screenModel.commandResumeBleSosMonitor();

  /// Delegates handle fall stillness monitor changed to the ViewModel.
  void _handleFallStillnessMonitorChanged() =>
      _screenModel.commandHandleFallStillnessMonitorChanged();

  /// Delegates handle fall stillness countdown started to the ViewModel.
  Future<void> _handleFallStillnessCountdownStarted() =>
      _screenModel.commandHandleFallStillnessCountdownStarted();

  /// Reconcile native dispatch state with the restored hike and acknowledge events only after accepted processing.
  Future<void> _consumePendingNativeSafetyEvent() async {
    if (!mounted) {
      return;
    }
    final event = await _activeHikeLiveStatusService
        .consumePendingSafetyEvent();
    if (!mounted || event == null || event.eventId.isEmpty) {
      return;
    }
    // A verified native escalation needs a stop control even while the local
    // hike snapshot is still restoring. Legacy ownerless events wait below.
    final authenticatedUid = widget.firebaseBootstrapResult.isAvailable
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    if (event.ownerUid.isNotEmpty &&
        event.ownerUid == authenticatedUid &&
        (event.isTriggering ||
            event.isDispatching ||
            event.isDispatched ||
            event.isDispatchFailed ||
            event.isReadyForFlutterDispatch)) {
      _presentNativeTriggeredSos(event);
    }
    await _waitForActiveHikeRestore();
    if (!mounted) return;
    final hike = activeHike;
    final matchesActiveHike = hike != null && event.sessionId == hike.sessionId;
    // An ended hike may still own a durable dispatch receipt. Never replay a
    // previous account's pending emergency using the current user's contacts.
    if (event.ownerUid.isNotEmpty) {
      final currentUid = widget.firebaseBootstrapResult.isAvailable
          ? FirebaseAuth.instance.currentUser?.uid
          : null;
      if (event.ownerUid != currentUid) return;
    } else if (!matchesActiveHike) {
      return; // Legacy native receipts have no independent owner identity.
    }

    // Publish immediately, including while the native dispatcher is still
    // busy. GPS and contact/network work must never delay the stop control.
    final presentationId =
        event.isDispatched ||
            event.isDispatching ||
            event.isTriggering ||
            event.isDispatchFailed ||
            event.isReadyForFlutterDispatch
        ? _presentNativeTriggeredSos(event)
        : null;

    if (event.isDispatched) {
      if (_lastHandledNativeSafetyEventId == event.eventId) {
        return;
      }
      _lastHandledNativeSafetyEventId = event.eventId;
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
      if (_lastHandledNativeSafetyEventId == event.eventId) {
        return;
      }
      await _emergencyContactsLoadFuture;
      if (!mounted) {
        return;
      }
      final now = DateTime.now().toUtc();
      final snapshot = FallStillnessMonitorSnapshot.triggering(
        settings: matchesActiveHike
            ? hike.draft.fallDetectionSettings
            : const FallDetectionSettings(sensorSensitivity: 5),
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
      final accepted =
          _durablyDispatchedNativeSafetyEvents.contains(event.eventId) ||
          await _triggerFallStillnessSos(
            snapshot,
            presentationEventId: presentationId ?? -1,
          );
      if (!accepted) {
        Future<void>.delayed(
          const Duration(seconds: 5),
          _consumePendingNativeSafetyEvent,
        );
        return;
      }
      _durablyDispatchedNativeSafetyEvents.add(event.eventId);
      bool acknowledged;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)) {
        acknowledged = await _activeHikeLiveStatusService
            .markSafetyEventDispatched(
              event.eventId,
              message: 'Emergency alert sent or saved for retry.',
            );
      } else {
        acknowledged = await _activeHikeLiveStatusService
            .acknowledgeSafetyEvent(event.eventId);
      }
      if (acknowledged) {
        _lastHandledNativeSafetyEventId = event.eventId;
        // A stopped receipt may have been cleared, exposing an older receipt.
        unawaited(_consumePendingNativeSafetyEvent());
      } else {
        Future<void>.delayed(
          const Duration(seconds: 5),
          _consumePendingNativeSafetyEvent,
        );
      }
      return;
    }

    if (_hasTriggeredSos || isNativeSafetyDialogVisible || !matchesActiveHike) {
      return;
    }
    final deadline = event.deadlineAt;
    if (deadline == null || !deadline.isAfter(DateTime.now().toUtc())) {
      Future<void>.delayed(
        const Duration(seconds: 1),
        _consumePendingNativeSafetyEvent,
      );
      return;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS delivers the native detector event to Flutter when the app is in
      // the foreground. Unlike Android, there is no overlay activity to own
      // this screen, so the app must present the explicit cancellation UI.
      isNativeSafetyDialogVisible = true;
      var wasCancelled = false;
      try {
        await showCupertinoDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            _nativeSafetyCountdownRoute = ModalRoute.of(dialogContext);
            _nativeSafetyCountdownEventId = event.eventId;
            return _NativeSafetyCountdownDialog(
              event: event,
              onCancel: () async {
                wasCancelled = true;
                await _cancelNativeSafetyCountdown();
                if (dialogContext.mounted) {
                  HikeStartNavigation.closeOwnedRoute(
                    ModalRoute.of(dialogContext),
                  );
                }
              },
            );
          },
        );
      } finally {
        _nativeSafetyCountdownRoute = null;
        _nativeSafetyCountdownEventId = null;
        isNativeSafetyDialogVisible = false;
      }
      if (!wasCancelled && mounted) {
        // The native event changes from countdown to dispatch-ready when the
        // deadline expires. Re-read it instead of treating a displayed dialog
        // as a handled emergency.
        unawaited(_consumePendingNativeSafetyEvent());
      }
      return;
    }
    // Android owns the response UI so it can appear above the lock screen and
    // other apps. Flutter observes the persisted outcome without stacking a
    // second countdown dialog underneath the native safety surface.
    Future<void>.delayed(
      const Duration(seconds: 2),
      _consumePendingNativeSafetyEvent,
    );
  }

  /// Delegates handle fall stillness emergency ready to the ViewModel.
  Future<void> _handleFallStillnessEmergencyReady(
    FallStillnessMonitorSnapshot snapshot,
  ) => _screenModel.commandHandleFallStillnessEmergencyReady(snapshot);

  /// Delegates trigger fall stillness sos to the ViewModel.
  Future<bool> _triggerFallStillnessSos(
    FallStillnessMonitorSnapshot snapshot, {
    int? presentationEventId,
  }) => _screenModel.commandTriggerFallStillnessSos(
    snapshot,
    presentationEventId: presentationEventId,
  );

  /// Shows fall stillness snack bar.
  void _showFallStillnessSnackBar(String message, {bool isError = false}) {
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
        ),
      );
  }

  /// Delegates sync fall stillness monitor to the ViewModel.
  void _syncFallStillnessMonitor(ActiveHikeSession? hike) =>
      _screenModel.commandSyncFallStillnessMonitor(hike);

  /// Check native safety readiness during the same start attempt so tracking begins with its required permissions.
  Future<bool> _ensureBackgroundSafetyReady(HikeSessionDraft draft) async {
    if (!await confirmHikePrecautions(context, draft.trail) || !mounted) {
      return false;
    }
    if (!draft.fallDetectionEnabled && !draft.shareLiveLocation) {
      return true;
    }
    var status = await _activeHikeLiveStatusService.nativeSafetyStatus();
    if (!mounted || !status.supported) {
      return true;
    }

    if (status.platform == 'ios') {
      if (!status.backgroundLocationGranted ||
          (draft.fallDetectionEnabled &&
              (status.notificationAuthorizationStatus == 'not_determined' ||
                  status.motionAuthorizationStatus == 'not_determined'))) {
        await _activeHikeLiveStatusService.requestIosSafetyPermissions();
        status = await _activeHikeLiveStatusService.nativeSafetyStatus();
        if (!mounted) {
          return false;
        }
      }

      final locationReady =
          status.fineLocationGranted && status.backgroundLocationGranted;
      final iosReady =
          locationReady &&
          (!draft.fallDetectionEnabled ||
              (status.notificationsAuthorized && status.motionGranted));
      if (iosReady) {
        return true;
      }

      return showIosHikeSafetySetupDialog(
        context: context,
        service: _activeHikeLiveStatusService,
        initialStatus: status,
        fallDetectionEnabled: draft.fallDetectionEnabled,
      );
    }

    final locationReady =
        status.fineLocationGranted && status.backgroundLocationGranted;
    if (locationReady && !draft.fallDetectionEnabled) {
      return true;
    }
    if (locationReady &&
        status.fullScreenIntentGranted &&
        status.overlayGranted) {
      return true;
    }
    if (locationReady && !status.overlayGranted) {
      final openSettings =
          await _presentEnsureBackgroundSafetyReadyEffect1() ?? false;
      if (!openSettings || !mounted) {
        return false;
      }
      await _activeHikeLiveStatusService.openOverlaySettings();
      return false;
    }
    if (locationReady && !status.fullScreenIntentGranted) {
      final openSettings =
          await _presentEnsureBackgroundSafetyReadyEffect2() ?? false;
      if (!openSettings || !mounted) {
        return false;
      }
      await _activeHikeLiveStatusService.openFullScreenIntentSettings();
      return false;
    }
    final openSettings =
        await _presentEnsureBackgroundSafetyReadyEffect3() ?? false;
    if (!openSettings || !mounted) {
      return false;
    }
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

  /// Synchronizes active hike services.
  void _syncActiveHikeServices(
    ActiveHikeSession? hike, {
    bool forceLiveStatus = false,
    bool stopNativeLiveStatus = true,
  }) {
    final startingMonitor =
        hike != null && activeHikeRecordingSessionId != hike.sessionId;
    if (hike == null ||
        _liveLocationCloudConfiguration !=
            _liveLocationConfigurationFor(hike)) {
      _liveLocationCloudConfiguration = null;
      _activeHikeCloudSync.invalidate();
    }
    final warningSessionKey = hike == null
        ? null
        : ActiveHikePrecautionAnnouncer.sessionKey(hike);
    if (_pathDeviationSessionKey != warningSessionKey) {
      _pathDeviationSessionKey = warningSessionKey;
      _pathDeviationStartedAt = null;
      _lastPathDeviationAlertAt = null;
    }
    _hikeWarningSpeech.synchronizeSession(warningSessionKey);
    _precautionAnnouncer.synchronizeSession(warningSessionKey);
    _persistActiveHikeSnapshot(hike);
    LiveLocationSharingService.instance.setPublishInterval(
      hike?.draft.locationRecordingInterval,
    );
    if (hike == null && _liveLocationActivatedForActiveHike) {
      unawaited(LiveLocationSharingService.instance.deactivate(manual: false));
    }
    _syncFallStillnessMonitor(hike);
    _syncTeamHikeSessionWatch(hike);
    unawaited(_syncLiveLocationForActiveHike(hike));
    if (hike == null) {
      _stopActiveHikeMonitoringHeartbeat();
      _stopActiveHikeLocationRecording();
      _syncBleTeamLocation(null);
      if (stopNativeLiveStatus) {
        unawaited(_activeHikeLiveStatusService.stop());
      }
      return;
    }

    _startActiveHikeMonitoringHeartbeat(hike);
    _startActiveHikeLocationRecording(hike);
    _syncBleTeamLocation(hike);
    _syncActiveHikeLiveStatus(hike, force: forceLiveStatus);
    if (startingMonitor) unawaited(_refreshBatteryLevel());
  }

  /// Delegates sync live location for active hike to the ViewModel.
  Future<void> _syncLiveLocationForActiveHike(ActiveHikeSession? hike) =>
      _screenModel.commandSyncLiveLocationForActiveHike(hike);

  /// Delegates live location configuration for to the ViewModel.
  ({
    String ownerPhoneNumber,
    String sessionId,
    bool sharing,
    int intervalSeconds,
  })
  _liveLocationConfigurationFor(ActiveHikeSession hike) =>
      _screenModel.commandLiveLocationConfigurationFor(hike);

  /// Ensure a changed sharing choice once before linking or notifying contacts.
  /// Regular footprint uploads also ensure this configuration and prime the cache.
  Future<ActiveHikeSession?> _ensureLiveLocationHikeConfiguration(
    ActiveHikeSession hike,
  ) async {
    final requested = _liveLocationConfigurationFor(hike);
    if (_liveLocationCloudConfiguration == requested) return hike;
    return _activeHikeCloudSync
        .synchronize(hike.sessionId)
        .timeout(const Duration(seconds: 12));
  }

  /// Starts active hike monitoring heartbeat.
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

  /// Delegates stop active hike monitoring heartbeat to the ViewModel.
  void _stopActiveHikeMonitoringHeartbeat() =>
      _screenModel.commandStopActiveHikeMonitoringHeartbeat();

  /// Delegates send active hike monitoring heartbeat to the ViewModel.
  Future<void> _sendActiveHikeMonitoringHeartbeat(
    ActiveHikeSession hike, {
    required String lifecycleState,
  }) => _screenModel.commandSendActiveHikeMonitoringHeartbeat(
    hike,
    lifecycleState: lifecycleState,
  );

  /// Delegates signal potential app termination to the ViewModel.
  Future<void> _signalPotentialAppTermination(ActiveHikeSession hike) =>
      _screenModel.commandSignalPotentialAppTermination(hike);

  /// Delegates sync team hike session watch to the ViewModel.
  void _syncTeamHikeSessionWatch(ActiveHikeSession? hike) =>
      _screenModel.commandSyncTeamHikeSessionWatch(hike);

  /// Delegates start active hike location recording to the ViewModel.
  void _startActiveHikeLocationRecording(ActiveHikeSession hike) =>
      _screenModel.commandStartActiveHikeLocationRecording(hike);

  /// Delegates stop active hike location recording to the ViewModel.
  void _stopActiveHikeLocationRecording() =>
      _screenModel.commandStopActiveHikeLocationRecording();

  /// Merge durable native samples by capture time while preserving newer pins, battery and team updates.
  Future<void> _drainNativeLocationSamples(ActiveHikeSession hike) =>
      _screenModel.commandDrainNativeLocationSamples(hike);

  /// Ensure the canonical hike session, flush queued footprints, then update current team/live-share position.
  Future<void> _uploadActiveHikeLocations() async {
    final hike = activeHike;
    if (hike == null ||
        _isUploadingHikeLocations ||
        _isEndingActiveHike ||
        !mounted) {
      return;
    }
    _isUploadingHikeLocations = true;
    try {
      await _drainNativeLocationSamples(hike);
      final cloudHike = await _activeHikeCloudSync
          .synchronize(hike.sessionId, force: true)
          .timeout(const Duration(seconds: 12));
      if (cloudHike == null ||
          !mounted ||
          activeHike?.sessionId != cloudHike.sessionId ||
          _isEndingActiveHike) {
        return;
      }
      final remaining = await _HikerHomePageDataActions.flushFootprints(
        hikerCircleRepository,
      )(session: widget.session, activeHike: cloudHike);
      final last = cloudHike.latestLocation;
      if (last != null &&
          activeHike?.sessionId == cloudHike.sessionId &&
          !_isEndingActiveHike) {
        _syncTeamHikeLocation(
          cloudHike,
          SosTriggerLocation(
            latitude: last.latitude,
            longitude: last.longitude,
            accuracyMeters: last.accuracyMeters,
            capturedAt: last.capturedAt,
          ),
        );
        unawaited(_syncLiveLocationForActiveHike(cloudHike));
      }
      if (mounted &&
          activeHike?.sessionId == cloudHike.sessionId &&
          !_isEndingActiveHike) {
        final updated = activeHike!.copyWith(queuedUpdates: remaining);
        setState(() => activeHike = updated);
        _persistActiveHikeSnapshot(updated);
      }
    } catch (error) {
      debugPrint('Location batch retained for retry: $error');
    } finally {
      _isUploadingHikeLocations = false;
    }
  }

  /// Delegates is active hike location record due to the ViewModel.
  bool _isActiveHikeLocationRecordDue(ActiveHikeSession hike) =>
      _screenModel.commandIsActiveHikeLocationRecordDue(hike);

  /// Delegates is acceptable tracking location to the ViewModel.
  bool _isAcceptableTrackingLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location,
  ) => _screenModel.commandIsAcceptableTrackingLocation(hike, location);

  /// Combine the selected off-route distance with GPS uncertainty before issuing a path-deviation warning.
  void _evaluatePathDeviation(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double? accuracyMeters,
  ) => _screenModel.commandEvaluatePathDeviation(
    hike,
    coordinate,
    accuracyMeters,
  );

  /// Computes emit path deviation alert.
  Future<void> _emitPathDeviationAlert(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double distanceMeters,
  ) async {
    final sessionKey = ActiveHikePrecautionAnnouncer.sessionKey(hike);
    if (!mounted ||
        activeHike == null ||
        ActiveHikePrecautionAnnouncer.sessionKey(activeHike!) != sessionKey ||
        _isEndingActiveHike) {
      return;
    }
    const title = PathDeviationAlertMessage.title;
    final message = PathDeviationAlertMessage(distanceMeters);
    final deepLink = Uri(
      scheme: 'hikercircle',
      host: 'hike',
      path: '/active',
      queryParameters: {'sessionId': hike.sessionId},
    ).toString();
    unawaited(
      DeviceNotificationLogService.recordLocalNotification(
        ownerPhoneNumber: widget.session.phoneNumber,
        messageId:
            'path-deviation:${hike.sessionId}:${coordinate.capturedAt.toUtc().microsecondsSinceEpoch}',
        title: title,
        body: message.body,
        type: 'local_path_deviation_alert',
        deepLink: deepLink,
        receivedAt: coordinate.capturedAt,
      ),
    );
    // Speech and notification delivery are independent of each other and of
    // the cloud record. Offline or disabled notifications must not mute it.
    unawaited(
      _hikeWarningSpeech.enqueue(
        requestId:
            'path-deviation-${coordinate.capturedAt.toUtc().microsecondsSinceEpoch}',
        message: message.speech,
        canSpeak: () =>
            _canSpeakHikeWarning() &&
            ActiveHikePrecautionAnnouncer.sessionKey(activeHike!) == sessionKey,
      ),
    );
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
        body: message.body,
        payload: deepLink,
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
    await _HikerHomePageDataActions.recordPathDeviationAlert(
      hikerCircleRepository,
    )(
      session: widget.session,
      activeHike: hike,
      coordinate: coordinate,
      distanceMeters: distanceMeters,
    );
  }

  /// Records active hike location tick.
  Future<void> _recordActiveHikeLocationTick({bool force = false}) async {
    final hike = activeHike;
    if (hike == null ||
        isRecordingActiveHikeLocation ||
        _isEndingActiveHike ||
        _appLifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final shouldRecord = force || _isActiveHikeLocationRecordDue(hike);
    if (!shouldRecord && !hike.draft.fallDetectionEnabled) {
      return;
    }

    isRecordingActiveHikeLocation = true;
    final writeCompletion = Completer<void>();
    _activeLocationWrite = writeCompletion;
    final sessionId = hike.sessionId;
    var didRecordLocation = false;
    try {
      final location = await LocationSnapshotService.instance.refresh().timeout(
        const Duration(seconds: 4),
        onTimeout: () => LocationSnapshotService.instance.latestLocation,
      );
      if (location == null ||
          !mounted ||
          _isEndingActiveHike ||
          activeHike?.sessionId != sessionId) {
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
      if (!mounted ||
          _isEndingActiveHike ||
          activeHike?.sessionId != sessionId) {
        return;
      }

      final queuedUpdates =
          await _HikerHomePageDataActions.recordFootprint(
            hikerCircleRepository,
          )(
            session: widget.session,
            activeHike: hike,
            location: location,
            pointType: 'tracking',
            batteryLevel: batteryLevel,
          );
      if (!mounted || _isEndingActiveHike) {
        return;
      }

      final latestHike = activeHike;
      if (latestHike == null || latestHike.sessionId != sessionId) {
        final canonicalSessionId = _activeHikeSessionIdRemaps[sessionId];
        if (canonicalSessionId != null) {
          await _HikerHomePageDataActions.migrateHikeTelemetrySessionId(
            hikerCircleRepository.localDatabase,
          )(
            ownerPhoneNumber: widget.session.phoneNumber,
            oldSessionId: sessionId,
            newSessionId: canonicalSessionId,
          );
        }
        final terminalSessionId = canonicalSessionId ?? sessionId;
        if (_terminalCloudHikeSessionIds.contains(sessionId) ||
            _terminalCloudHikeSessionIds.contains(terminalSessionId)) {
          unawaited(
            _HikerHomePageDataActions.flushFootprints(hikerCircleRepository)(
              session: widget.session,
              activeHike: hike.copyWith(sessionId: terminalSessionId),
            ).catchError((Object _) => hike.queuedUpdates),
          );
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
      LiveLocationSharingService.instance.recordHikeLocation(location);
      _syncActiveHikeLiveStatus(updatedHike, force: true);
      didRecordLocation = true;
    } catch (error) {
      debugPrint('Unable to record the active hike location tick: $error');
    } finally {
      if (didRecordLocation) {
        lastActiveHikeLocationRecordedAt = DateTime.now();
      }
      isRecordingActiveHikeLocation = false;
      writeCompletion.complete();
      if (identical(_activeLocationWrite, writeCompletion)) {
        _activeLocationWrite = null;
      }
    }
  }

  /// Delegates evaluate stationary location watch to the ViewModel.
  void _evaluateStationaryLocationWatch(
    ActiveHikeSession hike,
    HikeCoordinate coordinate,
    double? accuracyMeters,
  ) => _screenModel.commandEvaluateStationaryLocationWatch(
    hike,
    coordinate,
    accuracyMeters,
  );

  /// Synchronizes active hike live status.
  void _syncActiveHikeLiveStatus(ActiveHikeSession hike, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        lastActiveHikeLiveStatusSentAt != null &&
        now.difference(lastActiveHikeLiveStatusSentAt!) <
            _activeHikeLiveStatusThrottle) {
      return;
    }

    lastActiveHikeLiveStatusSentAt = now;
    unawaited(
      _activeHikeLiveStatusService.startOrUpdate(
        hike,
        ownerUid: widget.firebaseBootstrapResult.isAvailable
            ? FirebaseAuth.instance.currentUser?.uid ?? ''
            : '',
      ),
    );
  }

  /// Delegates sync team hike location to the ViewModel.
  void _syncTeamHikeLocation(
    ActiveHikeSession hike,
    SosTriggerLocation location,
  ) => _screenModel.commandSyncTeamHikeLocation(hike, location);

  /// Delegates sync ble team location to the ViewModel.
  void _syncBleTeamLocation(ActiveHikeSession? forwardedArgument) =>
      _screenModel.commandSyncBleTeamLocation(forwardedArgument);

  /// Delegates handle ble team location to the ViewModel.
  void _handleBleTeamLocation(HikerBleTeamLocationEvent forwardedArgument) =>
      _screenModel.commandHandleBleTeamLocation(forwardedArgument);

  /// Delegates record fall stillness cancel tap to the ViewModel.
  void _recordFallStillnessCancelTap() =>
      _screenModel.commandRecordFallStillnessCancelTap();

  /// Delegates cancel fall stillness sos to the ViewModel.
  void _cancelFallStillnessSos(String reason) =>
      _screenModel.commandCancelFallStillnessSos(reason);

  /// Cancels native safety countdown.
  Future<void> _cancelNativeSafetyCountdown() async {
    /// Computes ignore failure.
    Future<void> ignoreFailure(Future<void> operation) async {
      try {
        await operation;
      } catch (_) {
        // One unavailable native output must not prevent the safety state from
        // being cancelled or leave the confirmation dialog stuck onscreen.
      }
    }

    await Future.wait<void>([
      ignoreFailure(
        _sosDeviceAlertService.stopFallStillnessCountdownVibration(),
      ),
      ignoreFailure(_sosDeviceAlertService.stopSpokenPrompt()),
      ignoreFailure(_sosDeviceAlertService.stopManualSosPattern()),
      ignoreFailure(_activeHikeLiveStatusService.cancelNativeSafetyAlert()),
    ]);
    isFallStillnessLocalAlarmActive = false;
    if (!mounted) {
      return;
    }
    HikerCircleToast.show(
      context,
      'The stillness alert and SOS countdown were cancelled.',
      tone: HikerCircleToastTone.success,
      title: 'You are marked safe',
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    for (final ready in _sosPresentationWaiters.toList()) {
      if (!ready.isCompleted) ready.complete();
    }
    _sosPresentation.removeListener(_handleSosPresentationChanged);
    _sosPresentation.dispose();
    _gearRouteService.dispose();
    _precautionAnnouncer.dispose();
    _hikeWarningSpeech.dispose();
    LiveLocationSharingService.instance.removeListener(
      _handleLiveSharingChanged,
    );
    _contactsChangeSubscription?.cancel();
    _pendingHikeRetryTimer?.cancel();
    _upcomingHikeExpiryTimer?.cancel();
    _precautionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    fallStillnessMonitor.removeListener(_handleFallStillnessMonitorChanged);
    fallStillnessMonitor.dispose();
    _myUpcomingHikesSubscription?.cancel();
    _planningChangesSubscription?.cancel();
    _trailsSubscription?.cancel();
    _pendingTrailRequestsSubscription?.cancel();
    _stopActiveHikeLocationRecording();
    teamHikeSessionSubscription?.cancel();
    teamHikeWatchSessionId = null;
    batteryLevelTimer?.cancel();
    _stopActiveHikeMonitoringHeartbeat();
    fcmTokenSubscription?.cancel();
    fcmOpenSubscription?.cancel();
    fcmForegroundSubscription?.cancel();
    _achievementSubscription?.cancel();
    _unregisterAchievementNotifications?.call();
    _achievementNotificationDelivery.dispose();
    _bleEventSubscription?.cancel();
    _networkReachabilitySubscription?.cancel();
    _sosQueueSubscription?.cancel();
    _sosConnectionSubscription?.cancel();
    _formedTeamChatsSubscription?.cancel();
    _teamReadinessSubscription?.cancel();
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

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates visible tabs to the ViewModel.
  List<HikerBottomNavDestination> _visibleTabs() =>
      _screenModel.commandVisibleTabs();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SosTriggeredRouteHost(
      controller: _sosPresentation,
      onStopAlarm: _stopPresentedSos,
      child: Scaffold(
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
            if (_isEndingActiveHike)
              HikerCircleLoadingToastOverlay(
                message: 'Ending your hike…',
                detail: 'Saving your route and safety summary.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
                  // Do not unlock a second completion while the first save is running.
                  debugPrint('Hike completion is still saving locally.');
                },
              ),
            if (!_isEndingActiveHike &&
                !isNativeSafetyDialogVisible &&
                !isFallStillnessDialogVisible &&
                !isSendingFallStillnessSos)
              ActiveHikePrecautionNoticeView(announcer: _precautionAnnouncer),
          ],
        ),
        bottomNavigationBar: isRestoringActiveHike
            ? null
            : HikerBottomNavBar(
                currentIndex: selectedTabIndex,
                queuedSosCount: _queuedSosCount,
                onDestinationSelected: onTabTap,
                destinations: _visibleTabs(),
              ),
      ),
    );
  }

  /// Presents the show formed team naming dialog effect1 UI.
  Future<bool?> _presentShowFormedTeamNamingDialogEffect1(
    GroupChat chat,
    String trailName,
    String initialName,
  ) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => TeamFormedNamingDialog(
      joinedHikerName: chat.latestJoinedName,
      trailName: trailName,
      initialName: initialName,
      onSubmit: (name) => _HikerHomePageDataActions.nameFormedHikeGroupChat(
        hikerCircleRepository,
      )(chatId: chat.id, name: name),
    ),
  );

  /// Presents the show formed team naming dialog effect2 UI.
  Future<void> _presentShowFormedTeamNamingDialogEffect2(GroupChat namedChat) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => GroupChatDetailPage(
            chat: namedChat,
            session: widget.session,
            repository: hikerCircleRepository,
          ),
        ),
      );

  /// Presents the open upcoming weather effect1 UI.
  Future<void> _presentOpenUpcomingWeatherEffect1(UpcomingHike forecastHike) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => HikingForecastSheet(
          hike: forecastHike,
          service: HikeBriefingWeatherService.shared,
          elevationGain: plannedHike?.upcomingHikeId == forecastHike.id
              ? plannedHike!.trail.elevationGainMeters
              : 0,
        ),
      );

  /// Presents the handle deep link effect1 UI.
  void _presentHandleDeepLinkEffect1() =>
      HikeStartNavigation.closeOwnedRoute(_nativeSafetyCountdownRoute);

  /// Presents the confirm external sos trigger effect1 UI.
  Future<bool?> _presentConfirmExternalSosTriggerEffect1(SosAlertMode mode) =>
      showCupertinoDialog<bool>(
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
      );

  /// Presents the open earned achievement effect1 UI.
  Future<void> _presentOpenEarnedAchievementEffect1() =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AchievementsPage(
            session: widget.session,
            repository: hikerCircleRepository,
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
            initiallyShowEarned: true,
          ),
        ),
      );

  /// Presents the open upcoming hike notification destination effect1 UI.
  Future<void> _presentOpenUpcomingHikeNotificationDestinationEffect1(
    Completer<BuildContext> progressReady,
  ) => showDialog<void>(
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
  );

  /// Presents the open upcoming hike notification destination effect2 UI.
  void _presentOpenUpcomingHikeNotificationDestinationEffect2(
    BuildContext progressContext,
  ) => HikeStartNavigation.closeOwnedRoute(ModalRoute.of(progressContext));

  /// Presents the open upcoming hike join request effect1 UI.
  Future<void> _presentOpenUpcomingHikeJoinRequestEffect1(
    Completer<BuildContext> progressReady,
  ) => showDialog<void>(
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
            message: 'Checking join request…',
            detail: 'Confirming the hike and request status.',
            compact: true,
          ),
        ),
      );
    },
  );

  /// Presents the open upcoming hike join request effect2 UI.
  void _presentOpenUpcomingHikeJoinRequestEffect2(
    BuildContext progressContext,
  ) => HikeStartNavigation.closeOwnedRoute(ModalRoute.of(progressContext));

  /// Presents the choose future join policy effect1 UI.
  Future<String?> _presentChooseFutureJoinPolicyEffect1() => showDialog<String>(
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

  /// Presents the choose future join policy effect2 UI.
  void _presentChooseFutureJoinPolicyEffect2(
    HikerCircleFirebaseRepositoryException error,
  ) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.message)));

  /// Presents the open group chat from deep link effect1 UI.
  Future<void> _presentOpenGroupChatFromDeepLinkEffect1(
    Completer<BuildContext> progressReady,
  ) => showDialog<void>(
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
  );

  /// Presents the open group chat from deep link effect2 UI.
  void _presentOpenGroupChatFromDeepLinkEffect2(BuildContext progressContext) =>
      HikeStartNavigation.closeOwnedRoute(ModalRoute.of(progressContext));

  /// Presents the open group chat from deep link effect3 UI.
  Future<void> _presentOpenGroupChatFromDeepLinkEffect3(
    GroupChat availableChat,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => GroupChatDetailPage(
        chat: availableChat,
        session: widget.session,
        repository: hikerCircleRepository,
      ),
    ),
  );

  /// Presents the show add buddy prompt effect1 UI.
  Future<bool?> _presentShowAddBuddyPromptEffect1(
    String name,
    String handle,
  ) => showModalBottomSheet<bool>(
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

  /// Presents the open undiscovered trail requests effect1 UI.
  Future<void> _presentOpenUndiscoveredTrailRequestsEffect1() =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecordedTrailRequestsPage(
            session: widget.session,
            repository: hikerCircleRepository,
          ),
        ),
      );

  /// Presents the delete trail by admin from home effect1 UI.
  Future<bool?> _presentDeleteTrailByAdminFromHomeEffect1(Trail trail) =>
      showCupertinoDialog<bool>(
        context: context,
        builder: (context) {
          return CupertinoAlertDialog(
            title: const Text('Delete trail?'),
            content: Text(
              '${trail.name} will be removed from Firebase trails.',
            ),
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

  /// Presents the confirm hazard cancellation effect1 UI.
  Future<bool?> _presentConfirmHazardCancellationEffect1(
    bool isHost,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isHost ? 'Cancel this hike?' : 'Leave this hike?'),
      content: Text(
        isHost
            ? 'This cancels the scheduled hike for everyone. You can choose another time afterwards.'
            : 'This removes you from the hike. The other hikers keep their plans.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep my plan'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(isHost ? 'Cancel hike' : 'Leave hike'),
        ),
      ],
    ),
  );

  /// Presents the schedule another time after hazard effect1 UI.
  void _presentScheduleAnotherTimeAfterHazardEffect1() =>
      HikeStartNavigation.revealHome(context);

  /// Presents the reschedule expired hike effect1 UI.
  void _presentRescheduleExpiredHikeEffect1() =>
      HikeStartNavigation.revealHome(context);

  /// Presents the review draft preparation effect1 UI.
  Future<String?> _presentReviewDraftPreparationEffect1(
    HikeSessionDraft draft,
    String? upcomingHikeId,
    Future<String?> Function(HikeSessionDraft) openPreparation,
  ) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => HikeSafetySettingsPage(
        initialDraft: draft,
        loadDraft: () => _loadHikeSafetyDraft(draft, upcomingHikeId),
        onSave: (value) => _saveHikeSafetyDraft(value, upcomingHikeId),
        onEditContacts: _editSafetyContacts,
        onContinue: openPreparation,
      ),
    ),
  );

  /// Presents the start prepared instant hike effect1 UI.
  void _presentStartPreparedInstantHikeEffect1(
    DialogRoute<void>? startProgressRoute,
  ) => HikeStartNavigation.closeOwnedRoute(startProgressRoute);

  /// Presents the coordinate team hike start effect1 UI.
  Future<TeamHikeSession?> _presentCoordinateTeamHikeStartEffect1(
    TeamHikeSession teamSession,
    HikeSessionDraft draft,
    Future<bool> Function() confirmReportedHazards,
  ) => Navigator.of(context).push<TeamHikeSession>(
    MaterialPageRoute<TeamHikeSession>(
      fullscreenDialog: true,
      builder: (context) {
        return _TeamHikeLaunchPage(
          session: widget.session,
          repository: hikerCircleRepository,
          deviceAlertService: _sosDeviceAlertService,
          initialTeamSession: teamSession,
          initialSafetyDraft: draft,
          confirmReportedHazards: confirmReportedHazards,
        );
      },
    ),
  );

  /// Presents the open active hike hazard report effect1 UI.
  Future<void> _presentOpenActiveHikeHazardReportEffect1(
    ActiveHikeSession hike,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: const RouteSettings(name: 'active-hike-report-hazard'),
      builder: (_) => HazardReportPage(
        session: widget.session,
        hikerCircleRepository: hikerCircleRepository,
        trail: hike.draft.trail,
      ),
    ),
  );

  /// Presents the start upcoming hike now effect1 UI.
  Future<void> _presentStartUpcomingHikeNowEffect1(
    Completer<BuildContext> progressContextReady,
    ValueNotifier<_HikeStartProgress> startProgress,
  ) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      if (!progressContextReady.isCompleted) {
        progressContextReady.complete(dialogContext);
      }
      return _HikeStartProgressDialog(progress: startProgress);
    },
  );

  /// Presents the start upcoming hike now effect2 UI.
  void _presentStartUpcomingHikeNowEffect2(BuildContext progressContext) =>
      HikeStartNavigation.closeOwnedRoute(ModalRoute.of(progressContext));

  /// Presents the open find hike effect1 UI.
  Future<void> _presentOpenFindHikeEffect1() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => FindHikePage(
        session: widget.session,
        repository: hikerCircleRepository,
      ),
    ),
  );

  /// Presents the start joined team hike effect1 UI.
  Future<TeamHikeSession?> _presentStartJoinedTeamHikeEffect1(
    TeamHikeSession acceptedSession,
    HikeSessionDraft draft,
    Future<bool> Function() confirmHazards,
  ) => Navigator.of(context).push<TeamHikeSession>(
    MaterialPageRoute<TeamHikeSession>(
      fullscreenDialog: true,
      builder: (context) {
        return _TeamHikeLaunchPage(
          session: widget.session,
          repository: hikerCircleRepository,
          deviceAlertService: _sosDeviceAlertService,
          initialTeamSession: acceptedSession,
          initialSafetyDraft: draft,
          confirmReportedHazards: confirmHazards,
        );
      },
    ),
  );

  /// Presents the respond to team ping effect1 UI.
  Future<bool?> _presentRespondToTeamPingEffect1() => showCupertinoDialog<bool>(
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

  /// Presents the open emergency contacts effect1 UI.
  Future<List<EmergencyContact>?> _presentOpenEmergencyContactsEffect1() =>
      Navigator.of(context).push<List<EmergencyContact>>(
        MaterialPageRoute<List<EmergencyContact>>(
          builder: (context) => EmergencyContactsPage(
            session: widget.session,
            initialContacts: emergencyContacts,
            repository: emergencyContactsRepository,
          ),
        ),
      );

  /// Presents the show nearby sos button popup effect1 UI.
  Future<void> _presentShowNearbySosButtonPopupEffect1(
    SosTriggerLocation? location,
    int? rssi,
  ) => showCupertinoDialog<void>(
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

  /// Presents the request sign out effect1 UI.
  Future<bool?> _presentRequestSignOutEffect1() => showCupertinoDialog<bool>(
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

  /// Presents the prompt for trail rating effect1 UI.
  Future<bool?> _presentPromptForTrailRatingEffect1(
    ActiveHikeSession completedHike,
    HikeSummaryReport summary,
  ) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => TrailRatingDialog(
      trailName: completedHike.trail.name,
      onSubmit: (feedback) =>
          _HikerHomePageDataActions.submitEndedHikeRating(
            hikerCircleRepository,
          )(
            session: widget.session,
            activeHike: completedHike,
            summary: summary,
            rating: feedback.rating,
            difficulty: feedback.difficulty,
            comment: feedback.comment,
          ),
    ),
  );

  /// Presents the end active hike session effect1 UI.
  void _presentEndActiveHikeSessionEffect1() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hike saved. Stopping background tracking will retry automatically.',
          ),
        ),
      );

  /// Presents the end active hike session effect2 UI.
  Future<void> _presentEndActiveHikeSessionEffect2(
    HikeSummaryReport completedReport,
    ActiveHikeSession completedHike,
    ActiveHikeEndResult endResult,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) {
        return _HikeSummaryReportPage(
          session: widget.session,
          repository: hikerCircleRepository,
          report: completedReport,
          activeHike: completedHike,
          initialMapStyleIndex: _lastMapStyleIndex,
          onShareReportText: (text, {routeImage}) =>
              _sosDeviceAlertService.shareHike(
                subject: 'Hike summary: ${completedReport.trailName}',
                text: text,
                routeImage: routeImage,
              ),
          onShareToCommunity: (caption, images) async {
            await _HikerHomePageDataActions.createEndedHikePost(
              hikerCircleRepository,
            )(
              session: widget.session,
              activeHike: completedHike,
              summary: completedReport,
              endResult: endResult,
              caption: caption,
              images: images,
            );
          },
        );
      },
    ),
  );

  /// Presents the handle fall stillness countdown started effect1 UI.
  Future<void> _presentHandleFallStillnessCountdownStartedEffect1() =>
      showCupertinoDialog<void>(
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

  /// Presents the ensure background safety ready effect1 UI.
  Future<bool?> _presentEnsureBackgroundSafetyReadyEffect1() =>
      showCupertinoDialog<bool>(
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
      );

  /// Presents the ensure background safety ready effect2 UI.
  Future<bool?> _presentEnsureBackgroundSafetyReadyEffect2() =>
      showCupertinoDialog<bool>(
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
      );

  /// Presents the ensure background safety ready effect3 UI.
  Future<bool?> _presentEnsureBackgroundSafetyReadyEffect3() =>
      showCupertinoDialog<bool>(
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
      );
}

/// Displays the ble nearby proximity map.
class _BleNearbyProximityMap extends StatefulWidget {
  /// Creates ble nearby proximity map.
  const _BleNearbyProximityMap({required this.rssi});

  final int? rssi;

  /// Creates the presentation state for this widget.
  @override
  State<_BleNearbyProximityMap> createState() => _BleNearbyProximityMapState();
}

/// Manages the ble nearby proximity map presentation and lifecycle.
class _BleNearbyProximityMapState extends State<_BleNearbyProximityMap> {
  late final _BleNearbyProximityMapStateViewModel _screenModel;

  /// Returns mapbox map.
  mapbox.MapboxMap? get _mapboxMap => _screenModel.stateMapboxMap;

  /// Updates mapbox map.
  set _mapboxMap(mapbox.MapboxMap? value) =>
      _screenModel.stateMapboxMap = value;

  /// Returns circle manager.
  mapbox.CircleAnnotationManager? get _circleManager =>
      _screenModel.stateCircleManager;

  /// Updates circle manager.
  set _circleManager(mapbox.CircleAnnotationManager? value) =>
      _screenModel.stateCircleManager = value;

  /// Returns polygon manager.
  mapbox.PolygonAnnotationManager? get _polygonManager =>
      _screenModel.statePolygonManager;

  /// Updates polygon manager.
  set _polygonManager(mapbox.PolygonAnnotationManager? value) =>
      _screenModel.statePolygonManager = value;

  /// Updates style loaded.
  set _styleLoaded(bool value) => _screenModel.stateStyleLoaded = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: const MapViewSettings(
      styleIndex: 1,
      dimension: MapDimension.twoD,
    ),
    onBeforeStyleReload: () async {
      final managers = <mapbox.BaseAnnotationManager?>[
        _circleManager,
        _polygonManager,
      ];
      _styleLoaded = false;
      _circleManager = null;
      _polygonManager = null;
      await removeMapAnnotationManagers(_mapboxMap, managers);
    },
  );

  static const _refreshInterval = Duration(seconds: 5);

  Timer? _locationTimer;

  /// Returns radius meters.
  double get _radiusMeters => _screenModel.commandRadiusMeters;

  /// Returns point.
  mapbox.Point? get _point => _screenModel.commandPoint;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _BleNearbyProximityMapStateViewModel(
      readRssi: () => widget.rssi,
    )..addListener(_renderScreenModel);

    unawaited(_refreshLocation());
    _locationTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(_refreshLocation());
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _mapView.dispose();
    _locationTimer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates refresh location to the ViewModel.
  Future<void> _refreshLocation() => _screenModel.commandRefreshLocation();

  /// Delegates center once to the ViewModel.
  Future<void> _centerOnce({bool force = false}) =>
      _screenModel.commandCenterOnce(force: force);

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    _mapView.attach(map);
    try {
      await map.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      await map.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {}
    await _ensureManagers();
    await _render();
    await _centerOnce();
  }

  /// Computes on style ready.
  Future<void> _onStyleReady() => _mapView.styleLoaded(_prepareMapStyle);

  /// Delegates prepare map style to the ViewModel.
  Future<void> _prepareMapStyle() => _screenModel.commandPrepareMapStyle();

  /// Delegates ensure managers to the ViewModel.
  Future<bool> _ensureManagers() => _screenModel.commandEnsureManagers();

  /// Delegates render to the ViewModel.
  Future<void> _render() => _screenModel.commandRender();

  /// Builds this widget from its current presentation state.
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
            // Initial framing only. GPS refreshes must not reset the viewer's camera.
            // ignore: deprecated_member_use
            cameraOptions: mapbox.CameraOptions(
              center: point ?? mapbox.Point(coordinates: mapbox.Position(0, 0)),
              zoom: point == null ? 1 : 15,
            ),
            gestureRecognizers: mapGestureRecognizers,
            onMapLoadErrorListener: (event) {
              if (event.type == mapbox.MapLoadErrorType.STYLE) {
                _mapView.styleLoadFailed();
              }
            },
            onMapCreated: _onMapCreated,
            onCameraChangeListener: _mapView.cameraChanged,
            onStyleLoadedListener: (_) => _onStyleReady(),
            onMapLoadedListener: (_) => _onStyleReady(),
          ),
          MapViewOverlay(
            controller: _mapView,
            onReset: () => unawaited(_centerOnce(force: true)),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 66,
            child: IgnorePointer(
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
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

/// Displays the ble sos help map.
class _BleSosHelpMap extends StatefulWidget {
  /// Creates ble sos help map.
  const _BleSosHelpMap({
    required this.targetLatitude,
    required this.targetLongitude,
  });

  final double targetLatitude;
  final double targetLongitude;

  /// Creates the presentation state for this widget.
  @override
  State<_BleSosHelpMap> createState() => _BleSosHelpMapState();
}

/// Manages the ble sos help map presentation and lifecycle.
class _BleSosHelpMapState extends State<_BleSosHelpMap> {
  late final _BleSosHelpMapStateViewModel _screenModel;

  /// Returns mapbox map.
  mapbox.MapboxMap? get _mapboxMap => _screenModel.stateMapboxMap;

  /// Updates mapbox map.
  set _mapboxMap(mapbox.MapboxMap? value) =>
      _screenModel.stateMapboxMap = value;

  /// Returns circle manager.
  mapbox.CircleAnnotationManager? get _circleManager =>
      _screenModel.stateCircleManager;

  /// Updates circle manager.
  set _circleManager(mapbox.CircleAnnotationManager? value) =>
      _screenModel.stateCircleManager = value;

  /// Returns point manager.
  mapbox.PointAnnotationManager? get _pointManager =>
      _screenModel.statePointManager;

  /// Updates point manager.
  set _pointManager(mapbox.PointAnnotationManager? value) =>
      _screenModel.statePointManager = value;

  /// Returns polyline manager.
  mapbox.PolylineAnnotationManager? get _polylineManager =>
      _screenModel.statePolylineManager;

  /// Updates polyline manager.
  set _polylineManager(mapbox.PolylineAnnotationManager? value) =>
      _screenModel.statePolylineManager = value;

  /// Returns distance meters.
  double? get _distanceMeters => _screenModel.stateDistanceMeters;

  /// Returns previous distance meters.
  double? get _previousDistanceMeters =>
      _screenModel.statePreviousDistanceMeters;

  /// Updates style loaded.
  set _styleLoaded(bool value) => _screenModel.stateStyleLoaded = value;

  /// Returns is refreshing location.
  bool get _isRefreshingLocation => _screenModel.stateIsRefreshingLocation;

  /// Returns render generation.
  int get _renderGeneration => _screenModel.stateRenderGeneration;

  /// Updates render generation.
  set _renderGeneration(int value) =>
      _screenModel.stateRenderGeneration = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: const MapViewSettings(
      styleIndex: 1,
      dimension: MapDimension.twoD,
    ),
    onBeforeStyleReload: () async {
      final managers = <mapbox.BaseAnnotationManager?>[
        _circleManager,
        _pointManager,
        _polylineManager,
      ];
      _styleLoaded = false;
      _circleManager = null;
      _pointManager = null;
      _polylineManager = null;
      _renderGeneration++;
      await removeMapAnnotationManagers(_mapboxMap, managers);
    },
  );

  static const Duration _locationRefreshInterval = Duration(seconds: 5);

  Timer? _locationTimer;

  /// Returns target point.
  mapbox.Point get _targetPoint => _screenModel.commandTargetPoint;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _BleSosHelpMapStateViewModel(
      readTargetLatitude: () => widget.targetLatitude,
      readTargetLongitude: () => widget.targetLongitude,
    )..addListener(_renderScreenModel);

    _startLocationUpdates();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _mapView.dispose();
    _locationTimer?.cancel();
    _renderGeneration++;

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Starts location updates.
  void _startLocationUpdates() {
    unawaited(_refreshLocation());
    _locationTimer = Timer.periodic(_locationRefreshInterval, (_) {
      unawaited(_refreshLocation());
    });
  }

  /// Delegates refresh location to the ViewModel.
  Future<void> _refreshLocation() => _screenModel.commandRefreshLocation();

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _mapView.attach(mapboxMap);
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
          pitchEnabled: true,
        ),
      );
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {}
    await _fitMap();
  }

  /// Computes on style ready.
  Future<void> _onStyleReady() => _mapView.styleLoaded(_prepareMapStyle);

  /// Delegates prepare map style to the ViewModel.
  Future<void> _prepareMapStyle() => _screenModel.commandPrepareMapStyle();

  /// Delegates fit map to the ViewModel.
  Future<void> _fitMap() => _screenModel.commandFitMap();

  /// Returns distance label.
  String get _distanceLabel => _screenModel.commandDistanceLabel;

  /// Returns approach label.
  String get _approachLabel => _screenModel.commandApproachLabel;

  /// Computes approach color.
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

  /// Builds this widget from its current presentation state.
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
            // Initial framing only. GPS refreshes must not reset the viewer's camera.
            // ignore: deprecated_member_use
            cameraOptions: mapbox.CameraOptions(center: _targetPoint, zoom: 15),
            gestureRecognizers: mapGestureRecognizers,
            onMapLoadErrorListener: (event) {
              if (event.type == mapbox.MapLoadErrorType.STYLE) {
                _mapView.styleLoadFailed();
              }
            },
            onMapCreated: _onMapCreated,
            onCameraChangeListener: _mapView.cameraChanged,
            onStyleLoadedListener: (_) => _onStyleReady(),
            onMapLoadedListener: (_) => _onStyleReady(),
          ),
          MapViewOverlay(
            controller: _mapView,
            onReset: () => unawaited(_fitMap()),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 66,
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
            bottom: 88,
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
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _approachColor(context).withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.navigation_rounded,
                        size: 18,
                        color: _approachColor(context),
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
                        child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
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

/// Displays the team hike launch page.
class _TeamHikeLaunchPage extends StatefulWidget {
  /// Creates team hike launch page.
  const _TeamHikeLaunchPage({
    required this.session,
    required this.repository,
    required this.deviceAlertService,
    required this.initialTeamSession,
    required this.initialSafetyDraft,
    required this.confirmReportedHazards,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final SosDeviceAlertService deviceAlertService;
  final TeamHikeSession initialTeamSession;
  final HikeSessionDraft initialSafetyDraft;
  final Future<bool> Function() confirmReportedHazards;

  /// Creates the presentation state for this widget.
  @override
  State<_TeamHikeLaunchPage> createState() => _TeamHikeLaunchPageState();
}

/// Manages the team hike launch page presentation and lifecycle.
class _TeamHikeLaunchPageState extends State<_TeamHikeLaunchPage>
    with WidgetsBindingObserver {
  late final _TeamHikeLaunchPageStateViewModel _screenModel;

  /// Returns is marking ready.
  bool get _isMarkingReady => _screenModel.stateIsMarkingReady;

  /// Updates is marking ready.
  set _isMarkingReady(bool value) => _screenModel.stateIsMarkingReady = value;

  /// Returns is activating.
  bool get _isActivating => _screenModel.stateIsActivating;

  /// Updates is activating.
  set _isActivating(bool value) => _screenModel.stateIsActivating = value;

  /// Updates latest team session.
  set _latestTeamSession(TeamHikeSession value) =>
      _screenModel.stateLatestTeamSession = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  Timer? _countdownTicker;
  Timer? _teamRefreshTimer;

  bool _didFinishNavigation = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _TeamHikeLaunchPageStateViewModel(
      readInitialTeamSession: () => widget.initialTeamSession,
      readRepository: () => widget.repository,
      readSession: () => widget.session,
      effectActivateAndClose: _activateAndClose,
      effectCloseWhenReady: _closeWhenReady,
      effectMarkCurrentParticipantReady: _markCurrentParticipantReady,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    _latestTeamSession = widget.initialTeamSession;
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    _teamRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollTeamSession()),
    );
    unawaited(_pollTeamSession());
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_pollTeamSession());
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTicker?.cancel();
    _teamRefreshTimer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates poll team session to the ViewModel.
  Future<void> _pollTeamSession() => _screenModel.commandPollTeamSession();

  /// Delegates visible team session to the ViewModel.
  TeamHikeSession _visibleTeamSession(TeamHikeSession? streamed) =>
      _screenModel.commandVisibleTeamSession(streamed);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07140D),
      body: SafeArea(
        child: StreamBuilder<TeamHikeSession?>(
          initialData: widget.initialTeamSession,
          stream: _HikerHomePageDataActions.watchTeamHikeSession(
            widget.repository,
          )(widget.initialTeamSession.id),
          builder: (context, snapshot) {
            final teamSession = _visibleTeamSession(snapshot.data);
            _closeWhenReady(teamSession);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageHeader(
                        title: 'Team Hike Launch',
                        foregroundColor: Colors.white,
                        leading: PageHeaderAction(
                          tooltip: 'Close',
                          icon: CupertinoIcons.xmark,
                          onPressed: () => Navigator.of(context).pop(),
                          color: Colors.white,
                          surface: Colors.white.withValues(alpha: .12),
                        ),
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

  /// Delegates launch subtitle to the ViewModel.
  String _launchSubtitle(TeamHikeSession teamSession) =>
      _screenModel.commandLaunchSubtitle(teamSession);

  /// Delegates ready button label to the ViewModel.
  String _readyButtonLabel(TeamHikeSession teamSession) =>
      _screenModel.commandReadyButtonLabel(teamSession);

  /// Delegates ready button subtitle to the ViewModel.
  String _readyButtonSubtitle(TeamHikeSession teamSession) =>
      _screenModel.commandReadyButtonSubtitle(teamSession);

  /// Delegates can mark ready to the ViewModel.
  bool _canMarkReady(TeamHikeSession teamSession) =>
      _screenModel.commandCanMarkReady(teamSession);

  /// Delegates can press button to the ViewModel.
  bool _canPressButton(TeamHikeSession teamSession) =>
      _screenModel.commandCanPressButton(teamSession);

  /// Delegates on button pressed to the ViewModel.
  Future<void> _onButtonPressed(TeamHikeSession teamSession) =>
      _screenModel.commandOnButtonPressed(teamSession);

  /// Marks current participant ready.
  Future<void> _markCurrentParticipantReady(TeamHikeSession teamSession) async {
    if (!_canMarkReady(teamSession)) {
      return;
    }
    setState(() => _isMarkingReady = true);
    try {
      final trail = teamSession.sharedDraft?.trail;
      if (trail != null &&
          (!await confirmHikePrecautions(context, trail) || !mounted)) {
        return;
      }
      final profile = await _HikerHomePageDataActions.loadCommunityProfile(
        widget.repository,
      )(phoneNumber: widget.session.phoneNumber);
      if (!mounted) {
        return;
      }
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
                hasPlannedRoute: trail?.isUnlisted != true,
                initialSafetyDraft: widget.initialSafetyDraft,
                enhancedProtectionRecommended:
                    (profile?['gender'] is String
                            ? profile!['gender'] as String
                            : '')
                        .toLowerCase() ==
                    'female',
              ),
            ),
          );
      if (safetySettings == null || !mounted) {
        return;
      }
      if (!await widget.confirmReportedHazards() || !mounted) {
        if (mounted) _finishTeamNavigation(null);
        return;
      }
      final readySession =
          await _HikerHomePageDataActions.markTeamParticipantReady(
            widget.repository,
          )(
            session: widget.session,
            teamHikeSessionId: teamSession.id,
            safetySettings: safetySettings,
          );
      if (mounted) {
        setState(() => _latestTeamSession = readySession);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
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

  /// Removes pending invitees.
  Future<void> _removePendingInvitees(TeamHikeSession teamSession) async {
    if (_isMarkingReady || _isActivating || !mounted) {
      return;
    }
    final shouldRemove = await _presentRemovePendingInviteesEffect1(
      teamSession,
    );
    if (shouldRemove != true || !mounted) {
      return;
    }
    setState(() => _isMarkingReady = true);
    try {
      await _HikerHomePageDataActions.removePendingTeamInvitees(
        widget.repository,
      )(session: widget.session, teamHikeSessionId: teamSession.id);
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
      if (mounted) {
        setState(() => _isMarkingReady = false);
      }
    }
  }

  /// Finishes team navigation.
  void _finishTeamNavigation(TeamHikeSession? result) {
    if (!mounted || _didFinishNavigation) {
      return;
    }
    _didFinishNavigation = true;
    final route = ModalRoute.of<TeamHikeSession>(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (result == null) {
        HikerCircleToast.show(
          context,
          'This team hike is no longer active.',
          tone: HikerCircleToastTone.info,
          title: 'Team hike ended',
        );
      }
      HikeStartNavigation.completeFlow(route, result);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Closes when ready.
  void _closeWhenReady(TeamHikeSession teamSession) {
    if (_didFinishNavigation) {
      return;
    }
    if (teamSession.phase == TeamHikePhase.completed) {
      _finishTeamNavigation(null);
      return;
    }
    if (_isActivating || _isMarkingReady) {
      return;
    }
    if (teamSession.phase == TeamHikePhase.active) {
      _finishTeamNavigation(teamSession);
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

  /// Computes activate and close.
  Future<void> _activateAndClose(TeamHikeSession teamSession) async {
    if (!mounted || _didFinishNavigation) {
      return;
    }
    try {
      if (!await widget.confirmReportedHazards() || !mounted) {
        if (mounted) _finishTeamNavigation(null);
        return;
      }
      final activeSession =
          await _HikerHomePageDataActions.activateTeamHikeSession(
            widget.repository,
          )(session: widget.session, teamHikeSessionId: teamSession.id);
      _finishTeamNavigation(activeSession);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
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

  /// Presents the remove pending invitees effect1 UI.
  Future<bool?> _presentRemovePendingInviteesEffect1(
    TeamHikeSession teamSession,
  ) => showCupertinoDialog<bool>(
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
}

/// Displays the team safety preparation page.
class _TeamSafetyPreparationPage extends StatefulWidget {
  /// Creates team safety preparation page.
  const _TeamSafetyPreparationPage({
    required this.session,
    required this.repository,
    required this.deviceAlertService,
    required this.enhancedProtectionRecommended,
    required this.hasPlannedRoute,
    required this.initialSafetyDraft,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final SosDeviceAlertService deviceAlertService;
  final bool enhancedProtectionRecommended, hasPlannedRoute;
  final HikeSessionDraft initialSafetyDraft;

  /// Creates the presentation state for this widget.
  @override
  State<_TeamSafetyPreparationPage> createState() =>
      _TeamSafetyPreparationPageState();
}

/// Manages the team safety preparation page presentation and lifecycle.
class _TeamSafetyPreparationPageState
    extends State<_TeamSafetyPreparationPage> {
  late double _sensitivity =
      widget.initialSafetyDraft.fallDetectionSettings.sensorSensitivity;
  late int _pathDeviationDistanceMeters =
      widget.initialSafetyDraft.pathDeviationDistanceMeters;
  late Duration _fallResponseDuration =
      widget.initialSafetyDraft.fallDetectionSettings.fallResponseDuration;
  late Duration _longestRestDuration =
      widget.initialSafetyDraft.fallDetectionSettings.longestRestDuration;
  bool _sensitivitySelected = true;
  bool _fallResponseSelected = true;
  bool _longestRestSelected = true;
  late bool _enhancedIsolationProtection = widget.enhancedProtectionRecommended;
  bool _isLoadingPrefs = true;
  bool _isSavingPreferences = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  /// Loads preferences.
  Future<void> _loadPreferences() async {
    try {
      final prefs = await _HikerHomePageDataActions.loadTeamSafetyPreferences(
        widget.repository,
      )(session: widget.session);
      if (!mounted) {
        return;
      }
      if (prefs != null) {
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

  /// Computes confirm.
  Future<void> _confirm() async {
    if (_isSavingPreferences) {
      return;
    }
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
    if (!mounted) {
      return;
    }
    setState(() => _isSavingPreferences = true);
    final effectiveResponseDuration =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? const Duration(seconds: 15)
        : _fallResponseDuration;
    final prefs = <String, dynamic>{
      'liveLocationSharing': true,
      'pathDeviationAlerts': widget.hasPlannedRoute,
      'pathDeviationDistanceMeters': _pathDeviationDistanceMeters,
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
      AppSettingsController.instance.setFallSensorSensitivity(_sensitivity);
      AppSettingsController.instance.setPathDeviationDistanceMeters(
        _pathDeviationDistanceMeters,
      );
      await _HikerHomePageDataActions.saveTeamSafetyPreferences(
        widget.repository,
      )(session: widget.session, preferences: prefs);
      if (!mounted) {
        return;
      }
      _presentConfirmEffect1(prefs);
    } catch (error) {
      if (!mounted) {
        return;
      }
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

  /// Builds this widget from its current presentation state.
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
                  PageHeader(
                    title: 'Team safety setup',
                    leading: PageHeaderAction(
                      tooltip: 'Close',
                      icon: CupertinoIcons.xmark,
                      onPressed: () => Navigator.of(context).pop(),
                      color: Theme.of(context).colorScheme.primary,
                      surface: Theme.of(context).colorScheme.surface,
                    ),
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
                  _LockedTeamSafetyRow(
                    icon: Icons.alt_route_rounded,
                    title: 'Path deviation alerts',
                    subtitle: widget.hasPlannedRoute
                        ? 'The team is warned when you leave the route.'
                        : 'Unavailable: this hike has no planned pathway.',
                  ),
                  if (widget.hasPlannedRoute) ...[
                    const SizedBox(height: 8),
                    PathDeviationDistanceSetting(
                      value: _pathDeviationDistanceMeters,
                      onChanged: (distance) => setState(
                        () => _pathDeviationDistanceMeters = distance,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const _LockedTeamSafetyRow(
                    icon: Icons.groups_rounded,
                    title: 'Teammate separation alerts',
                    subtitle: 'Checks distance from the nearest teammate.',
                  ),
                  const SizedBox(height: 14),
                  FallSensitivitySetting(
                    value: _sensitivity,
                    onChanged: (value) => setState(() {
                      _sensitivity = value;
                      _sensitivitySelected = true;
                    }),
                  ),
                  TextButton.icon(
                    onPressed: () => showFallDetectionTest(
                      context,
                      sensitivity: _sensitivity,
                    ),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Fall detection test'),
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
                    'Phone will vibrates asking “Are you okay?”. '
                    'Selected time is the maximum response time to cancel FALSE fall alarm',
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
                    'If location stays within 5 meters for selected longest time, '
                    'HikerCircle starts to check for stillness before triggering prolonged-stillness SOS'
                    'respond before sending a prolonged-stillness SOS.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FootprintIntervalSetting(
                    value: LocationUpdateIntervalController
                        .instance
                        .preferredInterval,
                    onChanged: (value) async {
                      await LocationUpdateIntervalController.instance
                          .setInterval(value);
                      if (mounted) setState(() {});
                    },
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

  /// Presents the confirm effect1 UI.
  void _presentConfirmEffect1(Map<String, dynamic> prefs) =>
      Navigator.of(context).pop(prefs);
}

/// Represents safety theme.
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

  /// Creates safety theme.
  _SafetyTheme(this.context);

  /// Computes of.
  static _SafetyTheme of(BuildContext context) => _SafetyTheme(context);

  /// Returns is dark.
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  /// Returns background.
  Color get background => _isDark ? _darkBackground : _lightBackground;

  /// Returns surface.
  Color get surface => _isDark ? _darkSurface : _lightSurface;

  /// Returns green.
  Color get green => _lightGreen;

  /// Returns separator.
  Color get separator => _isDark ? _darkSeparator : _lightSeparator;

  /// Returns text.
  Color get text => _isDark ? _darkText : _lightText;

  /// Returns secondary text.
  Color get secondaryText => _isDark ? _darkSecondaryText : _lightSecondaryText;

  /// Returns orange.
  Color get orange => _lightOrange;

  /// Returns red.
  Color get red => _isDark ? _darkRed : _lightRed;
}

/// Displays the team ready player slot.
class _TeamReadyPlayerSlot extends StatelessWidget {
  /// Creates team ready player slot.
  const _TeamReadyPlayerSlot({required this.participant, required this.isSelf});

  final TeamHikeParticipant participant;
  final bool isSelf;

  /// Builds this widget from its current presentation state.
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

/// Represents hike start progress.
class _HikeStartProgress {
  /// Creates hike start progress.
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

/// Displays the hike start progress dialog.
class _HikeStartProgressDialog extends StatelessWidget {
  /// Creates hike start progress dialog.
  const _HikeStartProgressDialog({required this.progress});

  final ValueListenable<_HikeStartProgress> progress;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: ValueListenableBuilder<_HikeStartProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GpsStartingProgress(
                      title: value.title,
                      message: value.message,
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
      ),
    );
  }
}

/// Displays the hike summary report page.
class _HikeSummaryReportPage extends StatefulWidget {
  /// Creates hike summary report page.
  const _HikeSummaryReportPage({
    required this.repository,
    required this.session,
    required this.report,
    required this.activeHike,
    required this.onShareReportText,
    required this.onShareToCommunity,
    this.initialMapStyleIndex = 0,
  });

  final HikerCircleFirebaseRepository repository;
  final AppSession session;
  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final Future<void> Function(
    String caption,
    List<CommunityPostImageUpload> images,
  )
  onShareToCommunity;
  final Future<void> Function(String text, {Uint8List? routeImage})
  onShareReportText;
  final int initialMapStyleIndex;

  /// Creates the presentation state for this widget.
  @override
  State<_HikeSummaryReportPage> createState() => _HikeSummaryReportPageState();
}

/// Manages the hike summary report page presentation and lifecycle.
class _HikeSummaryReportPageState extends State<_HikeSummaryReportPage> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikeSummaryReportPageStateViewModel(
      readActiveHike: () => widget.activeHike,
    )..addListener(_renderScreenModel);
  }

  late final _HikeSummaryReportPageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Returns route analysis.
  HikeRouteAnalysis get _routeAnalysis => _screenModel.commandRouteAnalysis;

  /// Returns actual check in points.
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

  /// Opens share preview.
  Future<void> _openSharePreview() async {
    final posted = await _presentOpenSharePreviewEffect1();
    if (!mounted || posted != true) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Hike shared to community.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    /// Formats time.
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
                  PageHeader(
                    title: 'Hike Summary',
                    subtitle: report.trailName,
                    leading: PageHeaderAction(
                      tooltip: 'Close',
                      icon: CupertinoIcons.xmark,
                      onPressed: () => Navigator.of(context).pop(),
                      color: Theme.of(context).colorScheme.primary,
                      surface: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 220,
                      child: RoutePreviewMap(
                        trail: widget.activeHike.trail,
                        recordedTrackPoints: recordedHikeMapPoints(
                          widget.activeHike,
                        ),
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
                                label: 'GPS points',
                                value: '${report.routePointCount}',
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
                                label: 'Average speed',
                                value:
                                    '${report.averageSpeedKmh.toStringAsFixed(2)} km/h',
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
                    const SectionLabel(label: 'CHECKPOINT PERFORMANCE'),
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
                  if (widget.activeHike.checkInRecords.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const SectionLabel(label: 'CHECK-INS'),
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
                                  index <
                                      widget.activeHike.checkInRecords.length;
                                  index++
                                ) ...[
                                  if (index > 0)
                                    Divider(
                                      height: 1,
                                      color: _SummaryColors.separatorFor(
                                        context,
                                      ),
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
                  ],
                  const SizedBox(height: 18),
                  const SectionLabel(label: 'INSIGHTS'),
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
                  if (widget.activeHike.trail.isUnlisted) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Help add this trail',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Choose checkpoints from your GPS recording and send the complete pathway to admins for review.',
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const ValueKey(
                                'submit-recorded-trail-request',
                              ),
                              onPressed: () async {
                                final sent = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RecordedTrailRequestPage(
                                      session: widget.session,
                                      repository: widget.repository,
                                      hike: widget.activeHike,
                                      report: widget.report,
                                    ),
                                  ),
                                );
                                if (context.mounted && sent == true) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Trail request submitted for admin review.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add_road_rounded),
                              label: const Text('Suggest a new trail'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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

  /// Delegates format report duration to the ViewModel.
  String _formatReportDuration(Duration duration) =>
      _screenModel.commandFormatReportDuration(duration);

  /// Delegates coordinate label to the ViewModel.
  String _coordinateLabel(HikeCoordinate? coordinate) =>
      _screenModel.commandCoordinateLabel(coordinate);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Presents the open share preview effect1 UI.
  Future<bool?> _presentOpenSharePreviewEffect1() =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => HikeSharePreviewPage(
            repository: widget.repository,
            session: widget.session,
            report: widget.report,
            activeHike: widget.activeHike,
            onPostToCommunity: widget.onShareToCommunity,
            onShareExternally: widget.onShareReportText,
          ),
        ),
      );
}

/// Displays the summary empty events.
class _SummaryEmptyEvents extends StatelessWidget {
  /// Creates summary empty events.
  const _SummaryEmptyEvents({required this.message});

  final String message;

  /// Builds this widget from its current presentation state.
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

/// Represents summary colors.
abstract final class _SummaryColors {
  static const Color green = Color(0xFF34A853);
  static const Color background = Color(0xFFF2F2F7);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color separator = Color(0xFFD9E1DC);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;
}

/// Displays the summary divider.
class _SummaryDivider extends StatelessWidget {
  /// Creates summary divider.
  const _SummaryDivider();

  /// Builds this widget from its current presentation state.
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

/// Displays the native safety countdown dialog.
class _NativeSafetyCountdownDialog extends StatefulWidget {
  /// Creates native safety countdown dialog.
  const _NativeSafetyCountdownDialog({
    required this.event,
    required this.onCancel,
  });

  final NativeHikeSafetyEvent event;
  final Future<void> Function() onCancel;

  /// Creates the presentation state for this widget.
  @override
  State<_NativeSafetyCountdownDialog> createState() =>
      _NativeSafetyCountdownDialogState();
}

/// Manages the native safety countdown dialog presentation and lifecycle.
class _NativeSafetyCountdownDialogState
    extends State<_NativeSafetyCountdownDialog> {
  Timer? _timer;
  bool _isCancelling = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
      if (_secondsRemaining == 0) {
        HikeStartNavigation.closeOwnedRoute(ModalRoute.of(context));
      }
    });
  }

  /// Returns seconds remaining.
  int get _secondsRemaining {
    final deadline = widget.event.deadlineAt;
    if (deadline == null) {
      return 0;
    }
    final milliseconds = deadline
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    if (milliseconds <= 0) {
      return 0;
    }
    return (milliseconds / 1000).ceil();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
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
          onPressed: _isCancelling
              ? null
              : () {
                  setState(() => _isCancelling = true);
                  unawaited(widget.onCancel());
                },
          child: _isCancelling
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HikerCircleMinorLoadingIndicator(size: 24),
                    SizedBox(width: 8),
                    Text('Cancelling SOS…'),
                  ],
                )
              : const Text('I’M SAFE — CANCEL SOS'),
        ),
      ],
    );
  }
}

/// Displays the fall stillness countdown dialog.
class _FallStillnessCountdownDialog extends StatelessWidget {
  /// Creates fall stillness countdown dialog.
  const _FallStillnessCountdownDialog({
    required this.monitor,
    required this.onCancel,
  });

  final FallStillnessMonitor monitor;
  final VoidCallback onCancel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        final snapshot = monitor.snapshot;
        if (snapshot.status != FallStillnessMonitorStatus.awaitingResponse) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              HikeStartNavigation.closeOwnedRoute(ModalRoute.of(context));
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

/// Computes profile handle for phone.
String _profileHandleForPhone(String phoneNumber) {
  final digits = phoneNumber.replaceAll(RegExp('[^0-9]'), '');
  if (digits.length <= 4) {
    return 'hiker$digits';
  }
  return 'hiker${digits.substring(digits.length - 4)}';
}

/// Displays the active hike home page.
class ActiveHikeHomePage extends StatefulWidget {
  /// Creates active hike home page.
  const ActiveHikeHomePage({
    super.key,
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.onEndHike,
    required this.onCheckIn,
    required this.onReportHazard,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
    this.onOpenTeamChat,
    this.onPingTeamMember,
    this.onMapStyleChanged,
    this.mapBuilder,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final VoidCallback onEndHike;
  final VoidCallback onCheckIn;
  final VoidCallback onReportHazard;
  final VoidCallback? onOpenTeamChat;
  final Future<TeamHikeSession?> Function(String phoneNumber)? onPingTeamMember;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;
  final ValueChanged<int>? onMapStyleChanged;

  @visibleForTesting
  final Widget Function(mapbox.MapWidget map)? mapBuilder;

  /// Creates the presentation state for this widget.
  @override
  State<ActiveHikeHomePage> createState() => _ActiveHikeHomePageState();
}

/// Manages the active hike home page presentation and lifecycle.
class _ActiveHikeHomePageState extends State<ActiveHikeHomePage>
    with WidgetsBindingObserver {
  late final _ActiveHikeHomePageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  DateTime _now = DateTime.now();
  Timer? _timer;
  late final _weatherViewState = ActiveHikeWeatherController(
    database: LocalSessionDatabase(),
    ownerPhoneNumber: widget.currentPhoneNumber,
  );

  /// Returns weather snapshot.
  ActiveHikeWeatherSnapshot? get _weatherSnapshot =>
      _weatherViewState.value.snapshot;

  /// Returns is weather loading.
  bool get _isWeatherLoading => _weatherViewState.value.isLoading;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ActiveHikeHomePageStateViewModel()
      ..addListener(_renderScreenModel);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _weatherViewState.addListener(_weatherChanged);
    unawaited(_weatherViewState.bind(widget.activeHike));
  }

  /// Delegates weather changed to the ViewModel.
  void _weatherChanged() => _screenModel.commandWeatherChanged();

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant ActiveHikeHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeHike.sessionId != widget.activeHike.sessionId) {
      _screenModel.commandResetMapMode();
    }
    unawaited(_weatherViewState.bind(widget.activeHike));
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_weatherViewState.refresh());
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _weatherViewState.removeListener(_weatherChanged);
    _weatherViewState.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Opens route weather.
  void _openRouteWeather() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ActiveHikeWeatherSheet(
        locationOnly: widget.activeHike.trail.isUnlisted,
        weatherState: _weatherViewState,
        onRetry: () => unawaited(_weatherViewState.refresh()),
      ),
    );
  }

  /// Opens team tools.
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

  /// Builds this widget from its current presentation state.
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
              mapMode: _screenModel.stateMapMode,
              mapBuilder: widget.mapBuilder,
              onReportHazard: widget.onReportHazard,
            ),
          ),
        ),
        _ActiveHikeBottomBar(
          onEndHike: widget.onEndHike,
          onCheckIn: widget.onCheckIn,
          mapMode: _screenModel.stateMapMode,
          onToggleMapMode: _screenModel.commandToggleMapMode,
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

/// Displays the active hike safety health bar.
class _ActiveHikeSafetyHealthBar extends StatelessWidget {
  /// Creates active hike safety health bar.
  const _ActiveHikeSafetyHealthBar({
    required this.activeHike,
    required this.snapshot,
  });

  final ActiveHikeSession activeHike;
  final FallStillnessMonitorSnapshot snapshot;

  /// Builds this widget from its current presentation state.
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

/// Displays the active hike top bar.
class _ActiveHikeTopBar extends StatelessWidget {
  /// Creates active hike top bar.
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

  /// Builds this widget from its current presentation state.
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
                          child: HikerCircleMinorLoadingIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          activeWeatherIconForCode(currentWeather?.weatherCode),
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

/// Displays the elapsed time display.
class _ElapsedTimeDisplay extends StatelessWidget {
  /// Creates elapsed time display.
  const _ElapsedTimeDisplay({required this.elapsedLabel});

  final String elapsedLabel;

  /// Builds this widget from its current presentation state.
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

/// Displays the active hike bottom bar.
class _ActiveHikeBottomBar extends StatelessWidget {
  /// Creates active hike bottom bar.
  const _ActiveHikeBottomBar({
    required this.onEndHike,
    required this.mapMode,
    required this.onToggleMapMode,
    required this.onCheckIn,
    required this.onReportHazard,
    this.onOpenTeamTools,
    this.bottomInset = 0,
  });
  final VoidCallback onEndHike;
  final ActiveHikeMapMode mapMode;
  final VoidCallback onToggleMapMode;
  final VoidCallback
  onCheckIn; // Retained constructor compatibility for saved screens.
  final VoidCallback onReportHazard;
  final VoidCallback? onOpenTeamTools;
  final double bottomInset;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(14, 10, 14, bottomInset + 10),
    child: Row(
      children: [
        Expanded(
          child: ActiveHikeMapModeButton(
            onPressed: onToggleMapMode,
            mode: mapMode,
          ),
        ),
        if (onOpenTeamTools != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Team tools',
            onPressed: onOpenTeamTools,
            icon: const Icon(Icons.groups_outlined),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: onEndHike,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End hike'),
          ),
        ),
      ],
    ),
  );
}

/// Computes same team phone.
bool _sameTeamPhone(String first, String second) {
  final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
  final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
  return firstKey.isNotEmpty && firstKey == secondKey;
}

/// Computes finite double value.
double? _finiteDoubleValue(Object? value) {
  return value is num && value.isFinite ? value.toDouble() : null;
}

/// Computes bounded int value.
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
