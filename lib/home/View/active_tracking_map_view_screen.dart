part of '../active_tracking_map_view_feature.dart';

/// Checks whether valid coordinate.
bool _isValidCoordinate(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

/// Computes same phone number.
bool _samePhoneNumber(String first, String second) {
  final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
  final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
  return firstKey.isNotEmpty && firstKey == secondKey;
}

/// Computes display color for participant.
Color _displayColorForParticipant(
  TeamHikeParticipant participant,
  int index,
  String currentPhoneNumber,
) {
  return Color(participant.buddy.avatarColorValue);
}

/// Keep GPS movement and team markers tied to the active session rather than the planned trail geometry.
class ActiveTrackingMapView extends StatefulWidget {
  /// Creates active tracking map view.
  const ActiveTrackingMapView({
    super.key,
    required this.activeHike,
    this.teamHikeSession,
    this.weatherSamples = const [],
    this.interactive = true,
    this.showLegend = false,
    this.currentPhoneNumber = '',
    this.onStyleChanged,
    this.onReportHazard,
    this.mapBuilder,
    this.mapMode = ActiveHikeMapMode.normal,
  });

  final ActiveHikeSession activeHike;
  final TeamHikeSession? teamHikeSession;
  final List<ActiveHikeWeatherSample> weatherSamples;
  final bool interactive;
  final bool showLegend;
  final String currentPhoneNumber;
  final ValueChanged<int>? onStyleChanged;
  final VoidCallback? onReportHazard;
  final ActiveHikeMapMode mapMode;

  @visibleForTesting
  final Widget Function(mapbox.MapWidget map)? mapBuilder;

  /// Creates the presentation state for this widget.
  @override
  State<ActiveTrackingMapView> createState() => _ActiveTrackingMapViewState();
}

/// Manages the active tracking map view presentation and lifecycle.
class _ActiveTrackingMapViewState extends State<ActiveTrackingMapView>
    with WidgetsBindingObserver {
  late final ActiveTrackingMapViewModel _screenModel;

  /// Returns mapbox map.
  mapbox.MapboxMap? get _mapboxMap => _screenModel.stateMapboxMap;

  /// Updates mapbox map.
  set _mapboxMap(mapbox.MapboxMap? value) =>
      _screenModel.stateMapboxMap = value;

  /// Updates annotation managers future.
  set _annotationManagersFuture(Future<bool>? value) =>
      _screenModel.stateAnnotationManagersFuture = value;

  /// Updates local database.
  set _localDatabase(LocalSessionDatabase value) =>
      _screenModel.stateLocalDatabase = value;

  /// Returns static hazards.
  List<LocalTrailHazardMatch> get _staticHazards =>
      _screenModel.stateStaticHazards;

  /// Returns hazard load generation.
  int get _hazardLoadGeneration => _screenModel.stateHazardLoadGeneration;

  /// Updates hazard load generation.
  set _hazardLoadGeneration(int value) =>
      _screenModel.stateHazardLoadGeneration = value;

  /// Returns weather screen positions.
  List<Offset?> get _weatherScreenPositions =>
      _screenModel.stateWeatherScreenPositions;

  /// Updates weather screen positions.
  set _weatherScreenPositions(List<Offset?> value) =>
      _screenModel.stateWeatherScreenPositions = value;

  /// Returns team screen positions.
  Map<String, Offset?> get _teamScreenPositions =>
      _screenModel.stateTeamScreenPositions;

  /// Updates team screen positions.
  set _teamScreenPositions(Map<String, Offset?> value) =>
      _screenModel.stateTeamScreenPositions = value;

  /// Returns weather projection generation.
  int get _weatherProjectionGeneration =>
      _screenModel.stateWeatherProjectionGeneration;

  /// Updates weather projection generation.
  set _weatherProjectionGeneration(int value) =>
      _screenModel.stateWeatherProjectionGeneration = value;

  /// Returns team projection generation.
  int get _teamProjectionGeneration =>
      _screenModel.stateTeamProjectionGeneration;

  /// Updates team projection generation.
  set _teamProjectionGeneration(int value) =>
      _screenModel.stateTeamProjectionGeneration = value;

  /// Returns map settings.
  MapViewSettings get _mapSettings => _screenModel.stateMapSettings;

  /// Returns style loaded.
  bool get _styleLoaded => _screenModel.stateStyleLoaded;

  /// Updates style loaded.
  set _styleLoaded(bool value) => _screenModel.stateStyleLoaded = value;

  /// Returns route rendered.
  bool get _routeRendered => _screenModel.stateRouteRendered;

  /// Updates route rendered.
  set _routeRendered(bool value) => _screenModel.stateRouteRendered = value;

  /// Returns map generation.
  int get _mapGeneration => _screenModel.stateMapGeneration;

  /// Updates map generation.
  set _mapGeneration(int value) => _screenModel.stateMapGeneration = value;

  /// Returns render generation.
  int get _renderGeneration => _screenModel.stateRenderGeneration;

  /// Updates render generation.
  set _renderGeneration(int value) =>
      _screenModel.stateRenderGeneration = value;

  /// Returns has reference endpoints.
  bool get _hasReferenceEndpoints => _screenModel.stateHasReferenceEndpoints;

  /// Updates has reference endpoints.
  set _hasReferenceEndpoints(bool value) =>
      _screenModel.stateHasReferenceEndpoints = value;

  /// Returns current zoom.
  double get _currentZoom => _screenModel.stateCurrentZoom;

  /// Updates current zoom.
  set _currentZoom(double value) => _screenModel.stateCurrentZoom = value;

  /// Returns route points.
  List<mapbox.Point> get _routePoints => _screenModel.stateRoutePoints;

  /// Updates route points.
  set _routePoints(List<mapbox.Point> value) =>
      _screenModel.stateRoutePoints = value;

  /// Returns start point.
  mapbox.Point get _startPoint => _screenModel.stateStartPoint;

  /// Updates start point.
  set _startPoint(mapbox.Point value) => _screenModel.stateStartPoint = value;

  /// Returns end point.
  mapbox.Point get _endPoint => _screenModel.stateEndPoint;

  /// Updates end point.
  set _endPoint(mapbox.Point value) => _screenModel.stateEndPoint = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const double _navigationZoom = 17;
  static const Duration _navigationRefocusDelay = Duration(seconds: 30);

  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.Cancelable? _pointTapEvents;

  final Map<String, LocalTrailHazardMatch> _hazardsByAnnotationId = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _communityHazardSubscription;
  StreamSubscription<User?>? _communityHazardAuthSubscription;
  final _cautionMarkerSizer = CautionMarkerSizer();
  late final _communityCautionLayer = CommunityCautionMapLayer(
    placeBelowLocation: true,
    onTap: (cluster) {
      if (mounted) {
        unawaited(
          showCommunityHazardDetails(
            context,
            cluster,
            allowFeedback: widget.interactive,
          ),
        );
      }
    },
  );
  Timer? _cautionExpiryTimer;

  /// Computes expire community cautions.
  void _expireCommunityCautions() {
    if (!mounted) return;
    final remaining = _communityHazards
        .expand((c) => c.reports)
        .where((r) => r.isActiveAt(DateTime.now()))
        .toList();
    if (remaining.length ==
        _communityHazards.fold<int>(0, (total, c) => total + c.count)) {
      return;
    }
    _communityHazards = clusterCommunityHazards(remaining);
    _communityCautionLayer.setReports(_communityHazards);
  }

  List<CommunityHazardCluster> _communityHazards = const [];

  var _weatherProjectionScheduled = false;
  var _teamProjectionScheduled = false;

  var _nativeStyleUrl = mapStyleUrls.first;
  Future<void> _mapSettingsWork = Future.value();
  int _mapSettingsRevision = 0;
  var _needsModeCamera = false;

  var _showsMap = false;
  Timer? _navigationRefocusTimer;

  late double _scaleLatitude;
  double _cameraBearing = 0;
  mapbox.CameraOptions? _initialCamera;

  /// Stops gesture inertia and built-in zoom animations in terrain view.
  Future<void> _configureNavigationGestures(mapbox.MapboxMap map) {
    final animate = widget.mapMode == ActiveHikeMapMode.normal;
    return map.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: widget.interactive,
        pinchToZoomEnabled: widget.interactive,
        rotateEnabled: true,
        pitchEnabled: _mapSettings.is3D,
        pinchToZoomDecelerationEnabled: animate,
        rotateDecelerationEnabled: animate,
        scrollDecelerationEnabled: animate,
        doubleTapToZoomInEnabled: animate,
        doubleTouchToZoomOutEnabled: animate,
        quickZoomEnabled: animate,
      ),
    );
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = ActiveTrackingMapViewModel(
      readActiveHike: () => widget.activeHike,
      readCurrentPhoneNumber: () => widget.currentPhoneNumber,
      readTeamHikeSession: () => widget.teamHikeSession,
      readWeatherSamples: () => widget.weatherSamples,
      effectCreateAnnotationManagers: _createAnnotationManagers,
      effectOnStyleLoaded: _onStyleLoaded,
      effectPauseNavigationFollow: _pauseNavigationFollow,
      effectQueueMapSettingsUpdate: _queueMapSettingsUpdate,
      effectRenderRouteNow: _renderRouteNow,
      effectScheduleTeamProjection: _scheduleTeamProjection,
      effectScheduleWeatherProjection: _scheduleWeatherProjection,
      effectSyncScaleFromCamera: _syncScaleFromCamera,
      effectUpdateScale: _updateScale,
    )..addListener(_renderScreenModel);

    _needsModeCamera = widget.mapMode == ActiveHikeMapMode.firstPerson;
    _screenModel.commandSetMapMode(widget.mapMode);

    WidgetsBinding.instance.addObserver(this);
    _localDatabase = LocalSessionDatabase();
    _buildPoints();
    _showsMap = _visiblePoints.isNotEmpty;
    _initialCamera = _computeInitialCamera();
    _currentZoom = _initialCamera?.zoom ?? 13.5;
    final initialCenter = _initialCamera?.center;
    _scaleLatitude = initialCenter == null
        ? 0
        : mapPointCoordinatesOrNull(initialCenter)?.latitude ?? 0;
    unawaited(_loadStaticHazards());
    _watchCommunityHazards();
    _cautionExpiryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _expireCommunityCautions(),
    );
    if (Firebase.apps.isNotEmpty) {
      _communityHazardAuthSubscription = FirebaseAuth.instance
          .authStateChanges()
          .listen((_) => _watchCommunityHazards());
    }
  }

  /// Watches community hazards.
  void _watchCommunityHazards() {
    _communityHazardSubscription?.cancel();
    _communityHazards = const [];
    _communityCautionLayer.setReports(const []);
    _routeRendered = false;
    unawaited(_renderRouteIfReady());
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      return;
    }
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final trailId = widget.activeHike.trail.trailId;
    // Query hazards on tracked trail
    _communityHazardSubscription = FirebaseFirestore.instance
        .collection('hazardReports')
        .where('trailId', isEqualTo: trailId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted ||
                widget.activeHike.trail.trailId != trailId ||
                FirebaseAuth.instance.currentUser?.uid != ownerUid) {
              return;
            }
            final reports = snapshot.docs
                .map((doc) => CommunityHazard.fromMap(doc.id, doc.data()))
                .whereType<CommunityHazard>();
            _communityHazards = clusterCommunityHazards(reports);
            _communityCautionLayer.setReports(_communityHazards);
          },
          onError: (Object error) {
            debugPrint('Community cautions unavailable: $error');
          },
        );
  }

  /// Delegates load static hazards to the ViewModel.
  Future<void> _loadStaticHazards() => _screenModel.commandLoadStaticHazards();

  /// Refreshes presentation dependencies.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _communityCautionLayer.setAnimationsEnabled(
      !MediaQuery.disableAnimationsOf(context) &&
          TickerMode.valuesOf(context).enabled,
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _communityHazardSubscription?.cancel();
    _communityHazardAuthSubscription?.cancel();
    _cautionExpiryTimer?.cancel();
    _communityCautionLayer.dispose();
    _hazardLoadGeneration++;
    _pointTapEvents?.cancel();
    _navigationRefocusTimer?.cancel();
    _mapGeneration++;
    _renderGeneration++;
    _mapboxMap = null;
    _polylineManager = null;
    _circleManager = null;
    _pointManager = null;
    _communityCautionLayer.reset();
    _hazardsByAnnotationId.clear();
    _cautionMarkerSizer.clear();
    _annotationManagersFuture = null;

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refocusOnSelf());
    }
  }

  /// Computes refocus on self.
  Future<void> _refocusOnSelf({bool immediately = false}) async {
    final map = _mapboxMap;
    final focusPoint =
        _latestPoint ??
        (_hasReferenceEndpoints ? _startPoint : _validTrailCenterPoint());
    if (map == null || focusPoint == null) return;
    _navigationRefocusTimer?.cancel();
    _navigationRefocusTimer = null;
    try {
      await _screenModel.commandMoveCamera(
        mapbox.CameraOptions(
          center: focusPoint,
          padding: mapbox.MbxEdgeInsets(
            top: 150,
            left: 0,
            bottom: 30,
            right: 0,
          ),
          zoom: widget.mapMode == ActiveHikeMapMode.firstPerson
              ? 17.2
              : _navigationZoom,
          bearing: _navigationBearing(),
          pitch: _screenModel.cameraPitch,
        ),
        durationMillis: 500,
        immediately: immediately,
      );
      await _syncScaleFromCamera();
    } catch (_) {}
  }

  /// Computes initial camera.
  mapbox.CameraOptions? _computeInitialCamera() {
    final focusPoint =
        _latestPoint ??
        (_hasReferenceEndpoints ? _startPoint : _validTrailCenterPoint());
    if (focusPoint == null) return null;
    return mapbox.CameraOptions(
      center: focusPoint,
      padding: mapbox.MbxEdgeInsets(top: 150, left: 0, bottom: 30, right: 0),
      zoom: widget.mapMode == ActiveHikeMapMode.firstPerson
          ? 17.2
          : _navigationZoom,
      bearing: _navigationBearing(),
      pitch: _screenModel.cameraPitch,
    );
  }

  /// Delegates navigation bearing to the ViewModel.
  double? _navigationBearing() => _screenModel.commandNavigationBearing();

  /// Computes pause navigation follow.
  void _pauseNavigationFollow() {
    if (!widget.interactive) return;
    _navigationRefocusTimer?.cancel();
    _navigationRefocusTimer = Timer(_navigationRefocusDelay, () {
      _navigationRefocusTimer = null;
      if (mounted) {
        unawaited(_refocusOnSelf());
      }
    });
  }

  /// Builds points.
  void _buildPoints() {
    final checkpoints =
        widget.activeHike.draft.effectiveCheckpoints
            .where((checkpoint) => checkpoint.hasValidCoordinate)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final encoded = widget.activeHike.trail.routeEncodedPolyline;
    final decodedRoute = encoded == null || encoded.isEmpty
        ? const <mapbox.Point>[]
        : _decodePolyline(encoded);
    final recordedRoute = _recordedRoutePoints;
    final latestPoint = _latestPoint;
    if (checkpoints.isNotEmpty) {
      _startPoint = _pointForCheckpoint(checkpoints.first);
      _endPoint = _pointForCheckpoint(checkpoints.last);
      _hasReferenceEndpoints = true;
      _routePoints = _orientRoutePoints(decodedRoute);
      return;
    }
    if (decodedRoute.isNotEmpty) {
      _startPoint = decodedRoute.first;
      _endPoint = decodedRoute.last;
      _hasReferenceEndpoints = true;
      _routePoints = decodedRoute;
      return;
    }
    final fallbackPoint = recordedRoute.isNotEmpty
        ? recordedRoute.last
        : latestPoint ?? _validTrailCenterPoint();
    _startPoint = fallbackPoint ?? _zeroPoint;
    _endPoint = fallbackPoint ?? _zeroPoint;
    _hasReferenceEndpoints =
        !widget.activeHike.trail.isUnlisted && fallbackPoint != null;
    _routePoints = const [];
  }

  /// Delegates point for checkpoint to the ViewModel.
  mapbox.Point _pointForCheckpoint(TrailCheckpoint checkpoint) =>
      _screenModel.commandPointForCheckpoint(checkpoint);

  /// Delegates valid trail center point to the ViewModel.
  mapbox.Point? _validTrailCenterPoint() =>
      _screenModel.commandValidTrailCenterPoint();

  static final _zeroPoint = mapbox.Point(coordinates: mapbox.Position(0, 0));

  /// Returns recorded route points.
  List<mapbox.Point> get _recordedRoutePoints =>
      _screenModel.commandRecordedRoutePoints;

  /// Returns checkpoint points.
  List<mapbox.Point> get _checkpointPoints =>
      _screenModel.commandCheckpointPoints;

  /// Returns effective participants.
  List<TeamHikeParticipant> get _effectiveParticipants =>
      _screenModel.commandEffectiveParticipants;

  /// Returns located team participants.
  List<TeamHikeParticipant> get _locatedTeamParticipants =>
      _screenModel.commandLocatedTeamParticipants;

  /// Delegates color for participant to the ViewModel.
  Color _colorForParticipant(TeamHikeParticipant participant, int index) =>
      _screenModel.commandColorForParticipant(participant, index);

  /// Returns latest point.
  mapbox.Point? get _latestPoint => _screenModel.commandLatestPoint;

  /// Returns visible points.
  List<mapbox.Point> get _visiblePoints => _screenModel.commandVisiblePoints;

  /// Delegates decode polyline to the ViewModel.
  List<mapbox.Point> _decodePolyline(String encoded) =>
      _screenModel.commandDecodePolyline(encoded);

  /// Delegates orient route points to the ViewModel.
  List<mapbox.Point> _orientRoutePoints(List<mapbox.Point> points) =>
      _screenModel.commandOrientRoutePoints(points);

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant ActiveTrackingMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapMode != widget.mapMode) {
      _needsModeCamera = true;
      _navigationRefocusTimer?.cancel();
      _navigationRefocusTimer = null;
      _screenModel.commandSetMapMode(widget.mapMode);
      _initialCamera = _computeInitialCamera();
    }
    if (oldWidget.activeHike != widget.activeHike) {
      if (oldWidget.activeHike.trail.trailId !=
          widget.activeHike.trail.trailId) {
        unawaited(_loadStaticHazards());
        _watchCommunityHazards();
      }
      _teamProjectionGeneration++;
      final previouslyShowedMap = _showsMap;
      _buildPoints();
      _showsMap = _visiblePoints.isNotEmpty;
      if (previouslyShowedMap != _showsMap) {
        _mapGeneration++;
        _renderGeneration++;
        _styleLoaded = false;
        _mapboxMap = null;
        _polylineManager = null;
        _circleManager = null;
        _pointManager = null;
        _communityCautionLayer.reset();
        _pointTapEvents?.cancel();
        _pointTapEvents = null;
        _hazardsByAnnotationId.clear();
        _cautionMarkerSizer.clear();
        _annotationManagersFuture = null;
        _weatherScreenPositions = const [];
        _teamScreenPositions = const {};
      }
      _initialCamera = _computeInitialCamera();
      _routeRendered = false;
      _renderGeneration++;
      _teamScreenPositions = const {};
      unawaited(_renderRouteIfReady());
      _scheduleTeamProjection();
      if (_navigationRefocusTimer == null) {
        unawaited(_refocusOnSelf());
      }
    }
    if (!identical(oldWidget.weatherSamples, widget.weatherSamples)) {
      _weatherProjectionGeneration++;
      _scheduleWeatherProjection();
    }
    if (oldWidget.teamHikeSession != widget.teamHikeSession ||
        oldWidget.currentPhoneNumber != widget.currentPhoneNumber) {
      _teamProjectionGeneration++;
      _teamScreenPositions = const {};
      _scheduleTeamProjection();
    }
  }

  /// Computes on point annotation tapped.
  void _onPointAnnotationTapped(mapbox.PointAnnotation annotation) {
    final match = _hazardsByAnnotationId[annotation.id];
    if (match == null || !mounted) return;
    unawaited(showStaticHazardDetails(context, match));
  }

  /// Delegates is current map to the ViewModel.
  bool _isCurrentMap(mapbox.MapboxMap map, int generation) =>
      _screenModel.commandIsCurrentMap(map, generation);

  /// Recreate annotation state for a replacement native map and ignore callbacks from older map generations.
  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap, int generation) async {
    if (!mounted || generation != _mapGeneration) return;
    final replacingNativeMap =
        _mapboxMap != null && !identical(_mapboxMap, mapboxMap);
    _mapboxMap = mapboxMap;
    _nativeStyleUrl = mapStyleUrls.first;
    if (replacingNativeMap) {
      _styleLoaded = false;
      _routeRendered = false;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
      _communityCautionLayer.reset();
      _pointTapEvents?.cancel();
      _pointTapEvents = null;
      _hazardsByAnnotationId.clear();
      _cautionMarkerSizer.clear();
      _annotationManagersFuture = null;
      _renderGeneration++;
    }
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      if (!_isCurrentMap(mapboxMap, generation)) return;
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      if (!_isCurrentMap(mapboxMap, generation)) return;
      await _configureNavigationGestures(mapboxMap);
      if (!_isCurrentMap(mapboxMap, generation)) return;
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (error) {
      debugPrint('Unable to configure active hike map: $error');
    }
    if (!_isCurrentMap(mapboxMap, generation)) return;
    _queueMapSettingsUpdate();
    if (_styleLoaded) {
      await _ensureAnnotationManagers(mapboxMap, generation);
      await _renderRouteIfReady();
    }
    unawaited(_syncScaleFromCamera());
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  /// Computes on style loaded.
  Future<void> _onStyleLoaded(int generation) async {
    final map = _mapboxMap;
    final revision = _mapSettingsRevision;
    if (map == null || !_isCurrentMap(map, generation)) return;
    if (!_styleLoaded) {
      _styleLoaded = true;
      _routeRendered = false;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
      _communityCautionLayer.reset();
      _pointTapEvents?.cancel();
      _pointTapEvents = null;
      _hazardsByAnnotationId.clear();
      _cautionMarkerSizer.clear();
      _annotationManagersFuture = null;
      _renderGeneration++;
    }
    // A style reload preserves the current viewpoint. In particular, a user
    // inspecting a teammate or panning the route must not jump back to self.
    var pitch = _screenModel.cameraPitch;
    try {
      if (widget.mapMode == ActiveHikeMapMode.normal) {
        pitch = (await map.getCameraState()).pitch;
      }
    } catch (_) {}
    if (!_isCurrentMap(map, generation)) return;
    await applyMapDimension(map, _mapSettings.dimension, pitch: pitch);
    if (!_isCurrentMap(map, generation)) return;
    if (revision != _mapSettingsRevision) {
      _queueMapSettingsUpdate();
      return;
    }
    if (_needsModeCamera) {
      await _refocusOnSelf(immediately: true);
      if (!_isCurrentMap(map, generation)) return;
      if (revision != _mapSettingsRevision) return;
      _needsModeCamera = false;
    }
    if (!await _ensureAnnotationManagers(map, generation)) return;
    await _renderRouteIfReady();
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  /// Delegates on map loaded to the ViewModel.
  Future<void> _onMapLoaded(int generation) =>
      _screenModel.commandOnMapLoaded(generation);

  /// Delegates ensure annotation managers to the ViewModel.
  Future<bool> _ensureAnnotationManagers(
    mapbox.MapboxMap map,
    int generation,
  ) => _screenModel.commandEnsureAnnotationManagers(map, generation);

  /// Creates annotation managers.
  Future<bool> _createAnnotationManagers(
    mapbox.MapboxMap map,
    int generation,
  ) async {
    try {
      var polylineManager = _polylineManager;
      var circleManager = _circleManager;
      var pointManager = _pointManager;
      polylineManager ??= await map.annotations
          .createPolylineAnnotationManager();
      if (!_isCurrentMap(map, generation)) return false;
      circleManager ??= await map.annotations.createCircleAnnotationManager();
      if (!_isCurrentMap(map, generation)) return false;
      pointManager ??= await map.annotations.createPointAnnotationManager();
      if (!_isCurrentMap(map, generation)) return false;
      await pointManager.setIconAllowOverlap(true);
      await pointManager.setTextAllowOverlap(true);
      if (!_isCurrentMap(map, generation)) return false;
      if (!identical(pointManager, _pointManager)) {
        _pointTapEvents?.cancel();
        _pointTapEvents = pointManager.tapEvents(
          onTap: _onPointAnnotationTapped,
        );
      }
      _polylineManager = polylineManager;
      _circleManager = circleManager;
      _pointManager = pointManager;
      unawaited(_communityCautionLayer.attach(map, generation));
      return true;
    } catch (error) {
      if (_isCurrentMap(map, generation)) {
        debugPrint('Unable to prepare active hike map annotations: $error');
        Future.delayed(const Duration(milliseconds: 600), () {
          if (_isCurrentMap(map, generation)) {
            unawaited(_renderRouteIfReady());
          }
        });
      }
      return false;
    }
  }

  /// Delegates render route if ready to the ViewModel.
  Future<void> _renderRouteIfReady() =>
      _screenModel.commandRenderRouteIfReady();

  /// Computes render route now.
  Future<void> _renderRouteNow(
    mapbox.MapboxMap map,
    int mapGeneration,
    int renderGeneration,
  ) async {
    if (!_isCurrentMap(map, mapGeneration) ||
        renderGeneration != _renderGeneration ||
        !_styleLoaded ||
        _routeRendered ||
        _visiblePoints.isEmpty) {
      return;
    }

    final polylineManager = _polylineManager;
    final circleManager = _circleManager;
    final pointManager = _pointManager;
    if (polylineManager == null ||
        circleManager == null ||
        pointManager == null) {
      return;
    }
    await polylineManager.deleteAll();
    await circleManager.deleteAll();
    await pointManager.deleteAll();
    _hazardsByAnnotationId.clear();
    _cautionMarkerSizer.clear();
    if (!_isCurrentMap(map, mapGeneration) ||
        renderGeneration != _renderGeneration) {
      return;
    }

    var created = false;

    final recordedRoute = _recordedRoutePoints;
    final hasTrailRoute = _routePoints.length >= 2;
    final hasCheckpoints = _checkpointPoints.length >= 2;

    // Draw the planned trail route (decoded polyline) as background reference,
    // matching the style used by RoutePreviewMap on the trail page.
    if (hasTrailRoute) {
      await polylineManager.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(
            coordinates: [
              for (final pt in _routePoints)
                mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
            ],
          ),
          lineColor: const Color(0xFF2F8E50).toARGB32(),
          lineOpacity: 0.86,
          lineWidth: 3,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      created = true;
    }

    // Draw the recorded GPS route (thicker, brighter) on top when available.
    if (recordedRoute.length >= 2) {
      await polylineManager.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(
            coordinates: [
              for (final pt in recordedRoute)
                mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
            ],
          ),
          lineColor: const Color(0xFF34A853).toARGB32(),
          lineOpacity: 0.92,
          lineWidth: 4.2,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      created = true;
    }

    // Fallback: connect checkpoints with a subtle gray line when no route data.
    if (!hasTrailRoute && recordedRoute.length < 2 && hasCheckpoints) {
      await polylineManager.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(
            coordinates: [
              for (final pt in _checkpointPoints)
                mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
            ],
          ),
          lineColor: const Color(0xFF6E6E73).toARGB32(),
          lineOpacity: 0.5,
          lineWidth: 2.4,
        ),
      );
      created = true;
    }

    final circleAnnotations = <mapbox.CircleAnnotationOptions>[
      if (_latestPoint != null)
        mapbox.CircleAnnotationOptions(
          geometry: _latestPoint!,
          circleColor: const Color(0xFF0A84FF).toARGB32(),
          circleRadius: 7,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
      if (hasCheckpoints)
        for (final cp
            in _checkpointPoints
                .skip(1)
                .take(math.max(0, _checkpointPoints.length - 2)))
          mapbox.CircleAnnotationOptions(
            geometry: cp,
            circleColor: const Color(0xFF2F8E50).toARGB32(),
            circleOpacity: 0.55,
            circleRadius: 4.2,
            circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
            circleStrokeWidth: 1.2,
          ),
    ];

    if (circleAnnotations.isNotEmpty) {
      await circleManager.createMulti(circleAnnotations);
      created = true;
    }

    if (_hasReferenceEndpoints) {
      final endpointPin = await routeEndpointPinImage();
      if (!_isCurrentMap(map, mapGeneration) ||
          renderGeneration != _renderGeneration) {
        return;
      }
      final separateEndpointLabels = shouldSeparateRouteEndpointLabels(
        _startPoint,
        _endPoint,
      );
      await pointManager.createMulti([
        routeEndpointAnnotation(
          geometry: _startPoint,
          label: 'Start',
          pinImage: endpointPin,
          separateLabel: separateEndpointLabels,
        ),
        routeEndpointAnnotation(
          geometry: _endPoint,
          label: 'End',
          pinImage: endpointPin,
          separateLabel: separateEndpointLabels,
        ),
      ]);
      created = true;
    }

    if (_staticHazards.isNotEmpty) {
      final hazardMarkers = await Future.wait([
        for (final match in _staticHazards) staticHazardMarkerImageFor(match),
      ]);
      if (!_isCurrentMap(map, mapGeneration) ||
          renderGeneration != _renderGeneration) {
        return;
      }
      final annotations = await pointManager.createMulti([
        for (var index = 0; index < _staticHazards.length; index++)
          staticHazardAnnotation(
            _staticHazards[index],
            hazardMarkers[index],
            scaleFactor: cautionMarkerScale(_currentZoom, _scaleLatitude) / .65,
          ),
      ]);
      for (var index = 0; index < annotations.length; index++) {
        final annotation = annotations[index];
        if (annotation != null && index < _staticHazards.length) {
          _hazardsByAnnotationId[annotation.id] = _staticHazards[index];
          _cautionMarkerSizer.add(
            annotation,
            _staticHazards[index].hazard.severity == 'warning' ? .72 : .64,
          );
        }
      }
      created = true;
    }

    if (!_isCurrentMap(map, mapGeneration) ||
        renderGeneration != _renderGeneration) {
      return;
    }
    if (created) {
      _routeRendered = true;
    }

    // GPS updates and explicit recenter actions own camera following. Drawing
    // annotations after a style load must not move the inspected viewpoint.
  }

  /// Computes schedule weather projection.
  void _scheduleWeatherProjection() {
    if (_weatherProjectionScheduled) {
      return;
    }
    _weatherProjectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _weatherProjectionScheduled = false;
      if (mounted) {
        unawaited(_projectWeatherMarkers());
      }
    });
  }

  /// Computes schedule team projection.
  void _scheduleTeamProjection() {
    if (_teamProjectionScheduled) {
      return;
    }
    _teamProjectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _teamProjectionScheduled = false;
      if (mounted) {
        unawaited(_projectTeamMarkers());
      }
    });
  }

  /// Delegates project weather markers to the ViewModel.
  Future<void> _projectWeatherMarkers() =>
      _screenModel.commandProjectWeatherMarkers();

  /// Delegates project team markers to the ViewModel.
  Future<void> _projectTeamMarkers() =>
      _screenModel.commandProjectTeamMarkers();

  /// Delegates participant projection key to the ViewModel.
  String _participantProjectionKey(TeamHikeParticipant participant) =>
      _screenModel.commandParticipantProjectionKey(participant);

  /// Delegates fit route to the ViewModel.
  Future<void> _fitRoute() => _screenModel.commandFitRoute();

  /// Delegates change map settings to the ViewModel.
  void _changeMapSettings(MapViewSettings next) =>
      _screenModel.commandChangeMapSettings(next);

  /// Computes queue map settings update.
  void _queueMapSettingsUpdate() {
    final next = _mapSettings;
    final revision = ++_mapSettingsRevision;
    _mapSettingsWork = _mapSettingsWork
        .catchError((Object _) {})
        .then((_) async {
          if (!mounted || revision != _mapSettingsRevision) return;
          final map = _mapboxMap;
          if (map == null) return;
          await map.cancelCameraAnimation();
          if (!mounted || revision != _mapSettingsRevision) return;
          await _configureNavigationGestures(map);
          if (!mounted || revision != _mapSettingsRevision) return;
          if (_nativeStyleUrl != next.styleUrl) {
            final oldManagers = <mapbox.BaseAnnotationManager>[
              if (_polylineManager != null) _polylineManager!,
              if (_circleManager != null) _circleManager!,
              if (_pointManager != null) _pointManager!,
            ];
            _mapGeneration++;
            _renderGeneration++;
            _weatherProjectionGeneration++;
            _teamProjectionGeneration++;
            final generation = _mapGeneration;
            _styleLoaded = false;
            _routeRendered = false;
            _polylineManager = null;
            _circleManager = null;
            _pointManager = null;
            await _communityCautionLayer.resetAndWait();
            _pointTapEvents?.cancel();
            _pointTapEvents = null;
            _hazardsByAnnotationId.clear();
            _cautionMarkerSizer.clear();
            _annotationManagersFuture = null;
            if (mounted) {
              setState(() {
                _weatherScreenPositions = const [];
                _teamScreenPositions = const {};
              });
            }
            for (final manager in oldManagers) {
              try {
                await map.annotations.removeAnnotationManager(manager);
              } catch (_) {}
              if (!_isCurrentMap(map, generation)) return;
            }
            if (revision != _mapSettingsRevision) return;
            await map.loadStyleURI(next.styleUrl);
            if (!_isCurrentMap(map, generation)) return;
            _nativeStyleUrl = next.styleUrl;
            widget.onStyleChanged?.call(next.styleIndex);
          } else if (_styleLoaded) {
            final generation = _mapGeneration;
            await applyMapDimension(
              map,
              next.dimension,
              pitch: _screenModel.cameraPitch,
            );
            if (!_isCurrentMap(map, generation)) return;
            if (revision != _mapSettingsRevision) return;
            if (_needsModeCamera) {
              await _refocusOnSelf(immediately: true);
              if (!mounted || revision != _mapSettingsRevision) return;
              _needsModeCamera = false;
            }
            await _syncScaleFromCamera();
            _scheduleWeatherProjection();
            _scheduleTeamProjection();
          }
        })
        .catchError((Object error) {
          debugPrint('Unable to update active hike map appearance: $error');
        });
  }

  /// Delegates zoom by to the ViewModel.
  Future<void> _zoomBy(double amount) => _screenModel.commandZoomBy(amount);

  /// Delegates on camera change to the ViewModel.
  void _onCameraChange(mapbox.CameraChangedEventData data) =>
      _screenModel.commandOnCameraChange(data);

  /// Synchronizes scale from camera.
  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    final generation = _mapGeneration;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      if (!_isCurrentMap(map, generation)) return;
      final nextZoom = state.zoom;
      final coordinates = mapPointCoordinatesOrNull(state.center);
      if (!nextZoom.isFinite || coordinates == null) return;
      setState(() {
        _currentZoom = nextZoom;
        _scaleLatitude = coordinates.latitude;
        _cameraBearing = state.bearing.isFinite ? state.bearing : 0;
      });
      _communityCautionLayer.setScale(_currentZoom, _scaleLatitude);
      unawaited(
        _cautionMarkerSizer.resize(
          _pointManager,
          cautionMarkerScale(_currentZoom, _scaleLatitude) / .65,
        ),
      );
      _scheduleWeatherProjection();
      _scheduleTeamProjection();
    } catch (_) {
      // Map replacement can invalidate an in-flight camera request.
    }
  }

  /// Updates scale.
  void _updateScale(mapbox.CameraChangedEventData data) {
    final nextZoom = data.cameraState.zoom;
    final coordinates = mapPointCoordinatesOrNull(data.cameraState.center);
    if (!mounted || !nextZoom.isFinite || coordinates == null) return;
    final nextLatitude = coordinates.latitude;
    final scaleChanged =
        (nextZoom - _currentZoom).abs() >= .005 ||
        (nextLatitude - _scaleLatitude).abs() >= .0005;
    final nextBearing = data.cameraState.bearing.isFinite
        ? data.cameraState.bearing
        : 0.0;
    if (!scaleChanged && (nextBearing - _cameraBearing).abs() < .1) return;
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
      _cameraBearing = nextBearing;
    });
    if (!scaleChanged) return;
    _communityCautionLayer.setScale(_currentZoom, _scaleLatitude);
    unawaited(
      _cautionMarkerSizer.resize(
        _pointManager,
        cautionMarkerScale(_currentZoom, _scaleLatitude) / .65,
      ),
    );
  }

  /// Builds map widget.
  Widget _buildMapWidget(int mapGeneration) {
    final mapWidget = mapbox.MapWidget(
      key: const ValueKey('active-hike-tracking-map'),
      styleUri: mapStyleUrls.first,
      // ignore: deprecated_member_use
      cameraOptions: _initialCamera,
      gestureRecognizers: mapGestureRecognizers,
      onMapCreated: (map) => _onMapCreated(map, mapGeneration),
      onStyleLoadedListener: (_) => _onStyleLoaded(_mapGeneration),
      onMapLoadedListener: (_) => _onMapLoaded(_mapGeneration),
      onScrollListener: (_) => _pauseNavigationFollow(),
      onZoomListener: (_) => _pauseNavigationFollow(),
      onCameraChangeListener: (data) {
        if (mapGeneration == _mapGeneration) _onCameraChange(data);
      },
      onMapIdleListener: (_) {
        if (mapGeneration == _mapGeneration) {
          unawaited(_syncScaleFromCamera());
          _scheduleWeatherProjection();
          _scheduleTeamProjection();
        }
      },
    );
    return widget.mapBuilder?.call(mapWidget) ?? mapWidget;
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final visiblePoints = _visiblePoints;
    if (visiblePoints.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            'Waiting for trail coordinates',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final locatedParticipants = _locatedTeamParticipants;
    final mapGeneration = _mapGeneration;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMapWidget(mapGeneration),
        for (var index = 0; index < locatedParticipants.length; index++)
          if (_teamScreenPositions[_participantProjectionKey(
                locatedParticipants[index],
              )] !=
              null)
            Positioned(
              left:
                  _teamScreenPositions[_participantProjectionKey(
                        locatedParticipants[index],
                      )]!
                      .dx -
                  24,
              top:
                  _teamScreenPositions[_participantProjectionKey(
                        locatedParticipants[index],
                      )]!
                      .dy -
                  50,
              child: IgnorePointer(
                child: _ProjectedTeamMarker(
                  participant: locatedParticipants[index],
                  color: _colorForParticipant(
                    locatedParticipants[index],
                    index,
                  ),
                  isSelf: _samePhoneNumber(
                    locatedParticipants[index].phoneNumber,
                    widget.currentPhoneNumber,
                  ),
                ),
              ),
            ),
        for (
          var index = 0;
          index < widget.weatherSamples.length &&
              index < _weatherScreenPositions.length;
          index++
        )
          if (_weatherScreenPositions[index] != null)
            Positioned(
              left: _weatherScreenPositions[index]!.dx - 38,
              top: _weatherScreenPositions[index]!.dy - 70,
              child: IgnorePointer(
                child: _ProjectedWeatherMarker(
                  sample: widget.weatherSamples[index],
                  markerOffset: _weatherMarkerVisualOffset(index),
                ),
              ),
            ),
        MapControlOverlay(
          zoomControls: MapZoomControls(
            onZoomIn: () => unawaited(_zoomBy(1)),
            onZoomOut: () => unawaited(_zoomBy(-1)),
            onReset: () => unawaited(_fitRoute()),
          ),
          styleControls: MapStyleControls(
            settings: _mapSettings,
            onChanged: _changeMapSettings,
            showDimensionChoices: widget.mapMode == ActiveHikeMapMode.normal,
          ),
          scale: MapScaleWithStyle(
            zoom: _currentZoom,
            latitude: _scaleLatitude,
            settings: _mapSettings,
          ),
          bearing: _cameraBearing,
        ),
        if (widget.showLegend)
          Positioned(
            left: 10,
            right: 82,
            bottom: 88,
            child: _ActiveTrackingLegend(
              isTeam: _effectiveParticipants.isNotEmpty,
              selfColor: _effectiveParticipants
                  .where(
                    (p) => _samePhoneNumber(
                      p.phoneNumber,
                      widget.currentPhoneNumber,
                    ),
                  )
                  .map((p) => Color(p.buddy.avatarColorValue))
                  .firstOrNull,
            ),
          ),
        if (widget.onReportHazard != null && widget.interactive)
          Positioned(
            right: 14,
            bottom: 86,
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Report a caution',
              backgroundColor: const Color(0xFFFFC857),
              foregroundColor: const Color(0xFF342500),
              onPressed: widget.onReportHazard,
              child: const Icon(Icons.warning_amber_rounded),
            ),
          ),
        if (widget.interactive && _effectiveParticipants.isNotEmpty)
          Positioned(
            right: 10,
            top: 66,
            bottom: widget.onReportHazard != null ? 140 : 88,
            width: 152,
            child: Align(
              alignment: Alignment.topRight,
              child: SingleChildScrollView(
                child: _TeamParticipantPanel(
                  participants: _effectiveParticipants,
                  currentPhoneNumber: widget.currentPhoneNumber,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Delegates weather marker visual offset to the ViewModel.
  Offset _weatherMarkerVisualOffset(int index) =>
      _screenModel.commandWeatherMarkerVisualOffset(index);
}

/// Displays the projected team marker.
class _ProjectedTeamMarker extends StatelessWidget {
  /// Creates projected team marker.
  const _ProjectedTeamMarker({
    required this.participant,
    required this.color,
    required this.isSelf,
  });

  final TeamHikeParticipant participant;
  final Color color;
  final bool isSelf;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final name = participant.buddy.shortName;
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final photoURL = participant.buddy.photoURL.trim();
    return SizedBox(
      width: 48,
      height: 54,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: isSelf ? 4 : 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 7,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: photoURL.isEmpty
                ? Text(
                    initial,
                    style: TextStyle(
                      color: Color(
                        TeamHikeIdentity.foreground(color.toARGB32()),
                      ),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Image.network(
                    photoURL,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Text(
                      initial,
                      style: TextStyle(
                        color: Color(
                          TeamHikeIdentity.foreground(color.toARGB32()),
                        ),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: 39,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the legend dot.
class _LegendDot extends StatelessWidget {
  /// Creates legend dot.
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// Computes weather icon for code.
IconData _weatherIconForCode(int code) {
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

/// Computes weather color for code.
Color _weatherColorForCode(int code) {
  if (code == 0 || code == 1) {
    return const Color(0xFFF59E0B);
  }
  if (code >= 95) {
    return const Color(0xFF7C3AED);
  }
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return const Color(0xFF0A84FF);
  }
  if ((code >= 71 && code <= 77) || code >= 85) {
    return const Color(0xFF38BDF8);
  }
  return const Color(0xFF64748B);
}

/// Displays the projected weather marker.
class _ProjectedWeatherMarker extends StatelessWidget {
  /// Creates projected weather marker.
  const _ProjectedWeatherMarker({
    required this.sample,
    required this.markerOffset,
  });

  final ActiveHikeWeatherSample sample;
  final Offset markerOffset;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 70,
      child: CustomPaint(
        painter: _WeatherMarkerConnectorPainter(markerOffset: markerOffset),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 38 + markerOffset.dx - 22,
              top: 70 + markerOffset.dy - 14,
              child: SizedBox(
                width: 44,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.97),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF34A853),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _weatherIconForCode(sample.weatherCode),
                        size: 15,
                        color: _weatherColorForCode(sample.weatherCode),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEFFFFFFF),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(color: Color(0x22000000), blurRadius: 3),
                        ],
                      ),
                      child: Text(
                        '${sample.shortLabel} ${sample.temperatureCelsius.round()}°',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFF1C1C1E),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 35.5,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF34A853),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Represents weather marker connector painter.
class _WeatherMarkerConnectorPainter extends CustomPainter {
  /// Creates weather marker connector painter.
  const _WeatherMarkerConnectorPainter({required this.markerOffset});

  final Offset markerOffset;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    final anchor = Offset(size.width / 2, size.height - 2.5);
    final markerBottom = Offset(
      size.width / 2 + markerOffset.dx,
      size.height + markerOffset.dy + 25,
    );
    canvas.drawLine(
      anchor,
      markerBottom,
      Paint()
        ..color = const Color(0xAA34A853)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _WeatherMarkerConnectorPainter oldDelegate) {
    return oldDelegate.markerOffset != markerOffset;
  }
}
