// RoutePreviewMap renders planned or recorded geometry with route playback, checkpoint markers,
// hazard/weather layers and camera controls.
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/local_session_database.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/services/static_hazard_dataset_service.dart';
import '../../trail/Model/trail_models.dart';
import 'community_hazard_marker.dart';
import 'loading_toast.dart';
import '../services/weather_map_service.dart';
import 'map_controls.dart';
import 'map_utils.dart';
import 'route_preview_camera.dart';
import 'route_checkpoint_progress.dart';
import 'route_endpoint_marker.dart';
import 'route_animation_geometry.dart';
import 'static_hazard_marker.dart';

bool _isValidMapPoint(mapbox.Point point) {
  return mapPointCoordinatesOrNull(point) != null;
}

enum RoutePreviewMode { normal, firstPerson }

class _FpvTelemetry {
  const _FpvTelemetry({
    required this.distanceMeters,
    required this.elapsed,
    required this.progress,
    this.elevationMeters,
    this.gradePercent,
  });

  final double distanceMeters;
  final Duration elapsed;
  final double progress;
  final double? elevationMeters;
  final double? gradePercent;
}

class RoutePreviewMap extends StatefulWidget {
  const RoutePreviewMap({
    super.key,
    required this.trail,
    this.route,
    this.recordedTrackPoints,
    this.highlightedCheckpointIndex,
    this.customCheckpoints,
    this.showLayerToggle = false,
    this.animateRoute = true,
    this.animationDuration = const Duration(seconds: 15),
    this.pinnedPoints = const [],
    this.checkInPoints = const [],
    this.captureAllGestures = false,
    this.isRouteLoading = false,
    this.loadingMessage = 'Loading route…',
    this.initialStyleIndex = 0,
    this.previewMode = RoutePreviewMode.normal,
    this.localDatabase,
    this.departureTime,
    this.onAnimationProgress,
  });

  final ValueChanged<RouteCheckpointProgress>? onAnimationProgress;
  final DateTime? departureTime;
  final Trail trail;
  final HikingRouteResult? route;

  /// Non-null selects recorded-track mode, including an empty recording.
  /// Coordinates are chronological GPS samples, never snapped to the trail.
  final List<mapbox.Point>? recordedTrackPoints;
  final int? highlightedCheckpointIndex;
  final List<TrailCheckpoint>? customCheckpoints;
  final bool showLayerToggle;
  final bool animateRoute;
  final Duration animationDuration;
  final List<mapbox.Point> pinnedPoints;
  final List<mapbox.Point> checkInPoints;
  final bool captureAllGestures;
  final bool isRouteLoading;
  final String loadingMessage;
  final int initialStyleIndex;
  final RoutePreviewMode previewMode;
  final LocalSessionDatabase? localDatabase;

  List<TrailCheckpoint> get effectiveCheckpoints => recordedTrackPoints != null
      ? const []
      : customCheckpoints ?? trail.checkpoints;

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap>
    with SingleTickerProviderStateMixin {
  DateTime _previewStartedAt = DateTime.now();
  final _fpvHeadingFilter = RoutePreviewHeadingFilter();
  final _fpvCameraClock = Stopwatch()..start();

  static const _routeLineWidth = 2.65;
  static const _routeTrailColor = Color(0xFF7DD3FC);
  static const _routeHighlightColor = Color(0xFF007AFF);

  late List<mapbox.Point> _routePoints;
  late List<mapbox.Point> _checkpointPoints;
  List<int> _checkpointOriginalIndices = [];
  Map<int, double> _checkpointFractions = const {};
  Map<int, double> _checkpointDistancesMeters = const {};
  RouteCheckpointProgress? _pendingCheckpointProgress;
  bool _checkpointNotificationScheduled = false;

  void _publishCheckpointProgress(double progress) {
    if (widget.onAnimationProgress == null) return;
    final position =
        progress.clamp(0.0, 1.0) * math.max(0, _routeDistances.length - 1);
    final lower = position.floor();
    final upper = math.min(lower + 1, _routeDistances.length - 1);
    final distance = _routeDistances.isEmpty
        ? 0.0
        : _routeDistances[lower] +
              (_routeDistances[upper] - _routeDistances[lower]) *
                  (position - lower);
    _pendingCheckpointProgress = RouteCheckpointProgress(
      progress: progress.clamp(0.0, 1.0),
      checkpointFractions: _checkpointFractions,
      checkpointDistancesMeters: _checkpointDistancesMeters,
      distanceMeters: distance,
      estimatedDuration: _estimatedHikeDuration,
    );
    if (_checkpointNotificationScheduled) return;
    _checkpointNotificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkpointNotificationScheduled = false;
      if (!mounted) return;
      final value = _pendingCheckpointProgress;
      if (value != null) widget.onAnimationProgress?.call(value);
    });
  }

  late mapbox.Point _startPoint;
  late mapbox.Point _endPoint;
  late double _currentZoom;
  late double _scaleLatitude;
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.Cancelable? _pointTapEvents;
  Future<bool>? _annotationManagersFuture;
  late final LocalSessionDatabase _fallbackLocalDatabase;
  List<LocalTrailHazardMatch> _staticHazards = const [];
  final Map<String, LocalTrailHazardMatch> _hazardsByAnnotationId = {};
  int _hazardLoadGeneration = 0;
  StreamSubscription<User?>? _hazardAuthSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _communityHazardSubscription;
  int _communityHazardGeneration = 0;
  final _cautionMarkerSizer = CautionMarkerSizer();
  late final _communityCautionLayer = CommunityCautionMapLayer(
    onTap: (cluster) {
      if (mounted) unawaited(showCommunityHazardDetails(context, cluster));
    },
  );
  Timer? _cautionExpiryTimer;
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
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;
  late final AnimationController _routeAnimController;
  late final Animation<double> _routeAnimProgress;
  int _lastAnimatedIndex = 0;
  mapbox.PolylineAnnotation? _animatedPolyline;
  final List<mapbox.PolylineAnnotation> _cometLayers = [];
  List<double> _routeDistances = [];
  double get _cometLength => _routeDistances.isEmpty
      ? 125
      : (_routeDistances.last * .15).clamp(2.5, 625.0);
  List<int> _checkpointIndices = [];
  Map<int, List<int>> _checkpointIndicesByRouteIndex = {};
  List<mapbox.CircleAnnotation?> _checkpointCircleAnnotations = [];
  final Map<int, Timer> _checkpointGlowTimers = {};
  Timer? _pauseTimer;
  Timer? _loopPauseTimer;
  Timer? _styleWatchdogTimer;
  Timer? _renderRetryTimer;
  Timer? _fitRetryTimer;
  bool _isPaused = false;
  bool _isRendering = false;
  bool _renderPending = false;
  bool _isFitting = false;
  bool _fitPending = false;
  bool _initialFitComplete = false;
  int _renderGeneration = 0;
  int _mapGeneration = 0;
  bool _hasUsableGeometry = false;
  bool _fpvCameraUpdateInFlight = false;
  double? _pendingFpvProgress;
  int _lastFpvCameraUpdateMs = 0;
  double _fpvZoom = 17.2;
  double _fpvPitch = 68;
  double _fpvZoomOffset = 0;
  double _fpvLookAheadMeters = 25;
  double _fpvPlaybackSpeed = 1;
  late final ValueNotifier<_FpvTelemetry> _fpvTelemetry;
  final ValueNotifier<double> _fpvBearing = ValueNotifier(0);
  bool _terrainQueryInFlight = false;
  int _lastTerrainQueryMs = 0;
  int _terrainQueryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _styleIndex = widget.initialStyleIndex.clamp(0, mapStyleUrls.length - 1);
    _fallbackLocalDatabase = LocalSessionDatabase();
    _routeAnimController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _routeAnimProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _routeAnimController, curve: Curves.linear),
    );
    _routeAnimController.addListener(_onRouteAnimationTick);
    _routeAnimController.addStatusListener(_onAnimationStatusChange);
    _buildPoints();
    _fpvTelemetry = ValueNotifier(_telemetryAt(distanceMeters: 0));
    _syncRouteAnimationDuration();
    unawaited(_loadStaticHazards());
    if (Firebase.apps.isNotEmpty) {
      _hazardAuthSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (_) => _watchCommunityHazards(),
        onError: (Object error) {
          if (!mounted) return;
          _communityHazardGeneration++;
          _communityHazardSubscription?.cancel();
          _communityHazardSubscription = null;
          _applyCommunityHazards(const []);
          debugPrint('Community caution authentication unavailable: $error');
        },
      );
      _watchCommunityHazards();
      _cautionExpiryTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _expireCommunityCautions(),
      );
    }
  }

  Duration get _estimatedHikeDuration {
    final routeDuration = widget.route?.duration;
    if (routeDuration != null && routeDuration > Duration.zero) {
      return routeDuration;
    }
    return Duration(minutes: widget.trail.estimatedDurationMinutes);
  }

  double get _totalRouteDistanceMeters =>
      _routeDistances.isEmpty ? 0 : _routeDistances.last;

  String get _activeStyleUrl =>
      widget.previewMode == RoutePreviewMode.firstPerson
      ? fpvMapStyleUrl
      : mapStyleUrls[_styleIndex];

  _FpvTelemetry _telemetryAt({
    required double distanceMeters,
    double? elevationMeters,
    double? gradePercent,
  }) {
    final totalDistance = _totalRouteDistanceMeters;
    final safeDistance = distanceMeters.clamp(0.0, totalDistance).toDouble();
    final progress = totalDistance <= 0
        ? 0.0
        : (safeDistance / totalDistance).clamp(0.0, 1.0).toDouble();
    return _FpvTelemetry(
      distanceMeters: safeDistance,
      elapsed: Duration(
        milliseconds: (_estimatedHikeDuration.inMilliseconds * progress)
            .round(),
      ),
      progress: progress,
      elevationMeters: elevationMeters,
      gradePercent: gradePercent,
    );
  }

  void _syncRouteAnimationDuration() {
    _routeAnimController.duration =
        widget.previewMode == RoutePreviewMode.firstPerson
        ? routePreviewPlaybackDuration(
            totalDistanceMeters: _totalRouteDistanceMeters,
            speed: _fpvPlaybackSpeed,
          )
        : widget.animationDuration;
  }

  void _setFpvPlaybackSpeed(double speed) {
    if (_fpvPlaybackSpeed == speed) return;
    final shouldResume = _routeAnimController.isAnimating;
    _routeAnimController.stop();
    setState(() {
      _fpvPlaybackSpeed = speed;
      _syncRouteAnimationDuration();
    });
    if (shouldResume && !_isPaused) {
      _routeAnimController.forward();
    }
  }

  LocalSessionDatabase get _localDatabase =>
      widget.localDatabase ?? _fallbackLocalDatabase;

  void _watchCommunityHazards() {
    if (!mounted) return;
    final generation = ++_communityHazardGeneration;
    _communityHazardSubscription?.cancel();
    _communityHazardSubscription = null;
    _applyCommunityHazards(const []);
    if (Firebase.apps.isEmpty || widget.recordedTrackPoints != null) return;
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    final trailId = widget.trail.trailId;
    if (ownerUid == null || trailId.isEmpty) return;
    _communityHazardSubscription = FirebaseFirestore.instance
        .collection('hazardReports')
        .where('trailId', isEqualTo: trailId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted ||
                generation != _communityHazardGeneration ||
                widget.trail.trailId != trailId ||
                FirebaseAuth.instance.currentUser?.uid != ownerUid) {
              return;
            }
            final reports = snapshot.docs
                .map((doc) => CommunityHazard.fromMap(doc.id, doc.data()))
                .whereType<CommunityHazard>();
            _applyCommunityHazards(clusterCommunityHazards(reports));
          },
          onError: (Object error) {
            if (!mounted || generation != _communityHazardGeneration) return;
            _applyCommunityHazards(const []);
            debugPrint('Community cautions unavailable: $error');
          },
        );
  }

  void _applyCommunityHazards(List<CommunityHazardCluster> hazards) {
    if (!mounted) return;
    _communityHazards = hazards;
    _communityCautionLayer.setReports(hazards);
  }

  Future<void> _loadStaticHazards() async {
    final generation = ++_hazardLoadGeneration;
    if (widget.recordedTrackPoints != null) {
      _staticHazards = const [];
      return;
    }
    try {
      final currentScan = await _localDatabase.loadStaticHazardScanTime(
        widget.trail.trailId,
      );
      if (!mounted || generation != _hazardLoadGeneration) return;
      if (currentScan != null) {
        final cached = await _localDatabase.loadStaticHazardsForTrail(
          widget.trail.trailId,
        );
        if (!mounted || generation != _hazardLoadGeneration) return;
        _applyStaticHazards(cached);
      } else {
        // Do not flash markers produced by an older detection algorithm while
        // the versioned route-specific scan is being refreshed.
        _applyStaticHazards(const []);
      }

      final hazards = await StaticHazardDatasetService(
        database: _localDatabase,
      ).ensureForTrail(widget.trail, route: widget.route);
      if (!mounted || generation != _hazardLoadGeneration) return;
      _applyStaticHazards(hazards);
    } catch (_) {
      // The route remains usable when the optional local hazard dataset is
      // absent, migrating, unavailable, or the phone is offline.
    }
  }

  void _applyStaticHazards(List<LocalTrailHazardMatch> hazards) {
    if (!mounted) return;
    setState(() {
      _staticHazards = prepareStaticHazardsForMapDisplay(hazards);
      _routeRendered = false;
    });
    unawaited(_renderRouteIfReady());
  }

  void _onAnimationStatusChange(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _pauseBeforeRouteLoop();
    }
  }

  void _pauseBeforeRouteLoop() {
    if (_isPaused || !mounted) return;
    _isPaused = true;
    _routeAnimController.stop();
    _loopPauseTimer?.cancel();
    _loopPauseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      unawaited(_restartRouteLoop());
    });
  }

  Future<void> _restartRouteLoop() async {
    final annotation = _animatedPolyline;
    final manager = _polylineManager;
    if (!mounted || annotation == null || manager == null) return;

    _pauseTimer?.cancel();
    _loopPauseTimer?.cancel();
    _routeAnimController.reset();
    _publishCheckpointProgress(0);
    _fpvTelemetry.value = _telemetryAt(distanceMeters: 0);
    _lastAnimatedIndex = math.min(1, _routePoints.length);
    annotation.geometry = mapbox.LineString(
      coordinates: [
        for (final point in _routePoints.take(math.min(2, _routePoints.length)))
          mapbox.Position(point.coordinates[0]!, point.coordinates[1]!),
      ],
    );
    try {
      await manager.update(annotation);
      for (final layer in _cometLayers) {
        layer.geometry = annotation.geometry;
        await manager.update(layer);
      }
    } catch (_) {
      // A style replacement will rebuild the route with a new manager.
    }
    if (!mounted ||
        !identical(manager, _polylineManager) ||
        !identical(annotation, _animatedPolyline)) {
      return;
    }
    _isPaused = false;
    _queueFpvCameraUpdate(0, force: true);
    _routeAnimController.forward(from: 0);
  }

  void _onRouteAnimationTick() {
    if (!mounted ||
        _polylineManager == null ||
        _routePoints.length < 2 ||
        _animatedPolyline == null ||
        _isPaused) {
      return;
    }
    final progress = _routeAnimProgress.value.clamp(0.0, 1.0);
    var targetIndex = (1 + (progress * (_routePoints.length - 1)).round())
        .clamp(2, _routePoints.length);

    int? reachedCheckpointRouteIndex;
    if (targetIndex > _lastAnimatedIndex) {
      for (final checkpointRouteIndex in _checkpointIndices) {
        if (checkpointRouteIndex >= _lastAnimatedIndex &&
            checkpointRouteIndex < targetIndex) {
          reachedCheckpointRouteIndex = checkpointRouteIndex;
          targetIndex = checkpointRouteIndex + 1;
          break;
        }
      }
    }
    _publishCheckpointProgress(
      reachedCheckpointRouteIndex == null
          ? progress
          : reachedCheckpointRouteIndex / (_routePoints.length - 1),
    );
    if (targetIndex == _lastAnimatedIndex) {
      // The line is revealed point-by-point, but the FPV camera must continue
      // interpolating between those points for smooth slow-speed playback.
      _queueFpvCameraUpdate(progress);
      return;
    }
    _lastAnimatedIndex = targetIndex;

    final partialCoordinates = <mapbox.Position>[
      for (final pt in _routePoints.sublist(
        cometTailStart(_routeDistances, targetIndex - 1, _cometLength / 3),
        targetIndex,
      ))
        mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
    ];
    _animatedPolyline!.geometry = mapbox.LineString(
      coordinates: partialCoordinates,
    );
    final manager = _polylineManager;
    final annotation = _animatedPolyline;
    if (manager != null && annotation != null) {
      unawaited(manager.update(annotation).catchError((_) {}));
      for (var layer = 0; layer < _cometLayers.length; layer++) {
        final start = cometTailStart(
          _routeDistances,
          targetIndex - 1,
          _cometLength * (1 - layer / 3),
        );
        _cometLayers[layer].geometry = mapbox.LineString(
          coordinates: [
            for (final pt in _routePoints.sublist(start, targetIndex))
              mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
          ],
        );
        unawaited(manager.update(_cometLayers[layer]).catchError((_) {}));
      }
    }

    _queueFpvCameraUpdate(
      reachedCheckpointRouteIndex == null
          ? progress
          : reachedCheckpointRouteIndex / (_routePoints.length - 1),
      force: reachedCheckpointRouteIndex != null,
    );

    if (reachedCheckpointRouteIndex != null) {
      _pauseAtCheckpoint(reachedCheckpointRouteIndex);
    }
  }

  void _pauseAtCheckpoint(int index) {
    if (_isPaused) return;
    _isPaused = true;
    _routeAnimController.stop();

    final checkpointProgress = index / (_routePoints.length - 1);
    if ((_routeAnimController.value - checkpointProgress).abs() > 0.000001) {
      _routeAnimController.value = checkpointProgress;
    }

    for (final checkpointIndex
        in _checkpointIndicesByRouteIndex[index] ?? const <int>[]) {
      _glowCheckpoint(checkpointIndex);
    }

    _pauseTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _isPaused = false;
      _routeAnimController.forward();
    });
  }

  void _glowCheckpoint(int checkpointIdx) {
    final manager = _circleManager;
    if (manager == null) return;
    final annotationIndex = checkpointIdx - 1;
    if (annotationIndex < 0 ||
        annotationIndex >= _checkpointCircleAnnotations.length) {
      return;
    }
    final annotation = _checkpointCircleAnnotations[annotationIndex];
    if (annotation == null) return;

    _checkpointGlowTimers.remove(checkpointIdx)?.cancel();
    unawaited(() async {
      try {
        annotation.circleColor = _routeHighlightColor.toARGB32();
        annotation.circleRadius = 9;
        annotation.circleStrokeColor = const Color(0xFFFFFFFF).toARGB32();
        annotation.circleStrokeWidth = 2.4;
        annotation.circleOpacity = 1;
        await manager.update(annotation);
        if (!mounted || !identical(manager, _circleManager)) return;
        _checkpointGlowTimers[checkpointIdx] = Timer(
          const Duration(milliseconds: 500),
          () {
            if (!mounted || !identical(manager, _circleManager)) return;
            annotation.circleColor = _routeHighlightColor.toARGB32();
            annotation.circleRadius = 4.2;
            annotation.circleStrokeColor = const Color(0xFFFFFFFF).toARGB32();
            annotation.circleStrokeWidth = 1.2;
            annotation.circleOpacity = 0.65;
            unawaited(manager.update(annotation).catchError((_) {}));
            _checkpointGlowTimers.remove(checkpointIdx);
          },
        );
      } catch (_) {
        // Style replacement invalidates the old annotation manager.
      }
    }());
  }

  void _cancelCheckpointGlows() {
    for (final timer in _checkpointGlowTimers.values) {
      timer.cancel();
    }
    _checkpointGlowTimers.clear();
  }

  @override
  void dispose() {
    _hazardLoadGeneration++;
    _communityHazardGeneration++;
    _hazardAuthSubscription?.cancel();
    _communityHazardSubscription?.cancel();
    _pointTapEvents?.cancel();
    _cautionExpiryTimer?.cancel();
    _communityCautionLayer.dispose();
    _pauseTimer?.cancel();
    _loopPauseTimer?.cancel();
    _cancelCheckpointGlows();
    _styleWatchdogTimer?.cancel();
    _renderRetryTimer?.cancel();
    _fitRetryTimer?.cancel();
    _renderGeneration++;
    _mapGeneration++;
    _terrainQueryGeneration++;
    _pendingFpvProgress = null;
    _mapboxMap = null;
    _annotationManagersFuture = null;
    _routeAnimController.removeListener(_onRouteAnimationTick);
    _routeAnimController.removeStatusListener(_onAnimationStatusChange);
    _routeAnimController.dispose();
    _fpvTelemetry.dispose();
    _fpvBearing.dispose();
    super.dispose();
  }

  void _buildPoints() {
    _fpvHeadingFilter.reset();
    _checkpointOriginalIndices =
        [
          for (var i = 0; i < widget.effectiveCheckpoints.length; i++)
            if (widget.effectiveCheckpoints[i].hasValidCoordinate) i,
        ]..sort(
          (a, b) => widget.effectiveCheckpoints[a].order.compareTo(
            widget.effectiveCheckpoints[b].order,
          ),
        );
    final checkpoints = [
      for (final i in _checkpointOriginalIndices)
        widget.effectiveCheckpoints[i],
    ];
    _checkpointPoints = checkpoints
        .map(
          (cp) => mapbox.Point(
            coordinates: mapbox.Position(cp.longitude, cp.latitude),
          ),
        )
        .toList();
    final route = widget.route;
    final decodedRoute = widget.recordedTrackPoints != null
        ? widget.recordedTrackPoints!.where(_isValidMapPoint).toList()
        : route == null
        ? const <mapbox.Point>[]
        : _decodePolyline(route.encodedPolyline);
    if (_checkpointPoints.isNotEmpty) {
      _startPoint = _checkpointPoints.first;
      _endPoint = _checkpointPoints.last;
      _hasUsableGeometry = true;
      _routePoints = _orientRoutePoints(decodedRoute);
    } else if (decodedRoute.isNotEmpty) {
      _startPoint = decodedRoute.first;
      _endPoint = decodedRoute.last;
      _hasUsableGeometry = true;
      _routePoints = decodedRoute;
    } else {
      _startPoint = _zeroPoint;
      _endPoint = _zeroPoint;
      _hasUsableGeometry = false;
      _routePoints = const [];
    }
    _computeCheckpointIndices();
    _publishCheckpointProgress(0);
    _currentZoom = 13.5;
    final centerCoordinates = _hasUsableGeometry
        ? mapPointCoordinatesOrNull(centerFor(_visibleMapPoints))
        : null;
    _scaleLatitude = centerCoordinates?.latitude ?? 0;
  }

  static final _zeroPoint = mapbox.Point(coordinates: mapbox.Position(0, 0));

  void _computeCheckpointIndices() {
    _routeDistances = [0];
    for (var i = 1; i < _routePoints.length; i++) {
      _routeDistances.add(
        _routeDistances.last +
            distanceMeters(_routePoints[i - 1], _routePoints[i]),
      );
    }
    _checkpointFractions = const {};
    _checkpointDistancesMeters = const {};
    _checkpointIndices.clear();
    _checkpointIndicesByRouteIndex = {};
    if (_routePoints.isEmpty || _checkpointPoints.isEmpty) return;

    final matches = orderedCheckpointMatches([
      for (final checkpoint in _checkpointPoints)
        [for (final point in _routePoints) distanceMeters(checkpoint, point)],
    ]);
    _checkpointFractions = Map.unmodifiable({
      for (var c = 0; c < matches.length; c++)
        _checkpointOriginalIndices[c]:
            matches[c] / math.max(1, _routePoints.length - 1),
    });
    _checkpointDistancesMeters = Map.unmodifiable({
      for (var c = 0; c < matches.length; c++)
        _checkpointOriginalIndices[c]: _routeDistances[matches[c]],
    });
    for (var c = 1; c < matches.length - 1; c++) {
      final index = matches[c];
      if (index > 0 && index < _routePoints.length - 1) {
        _checkpointIndicesByRouteIndex.putIfAbsent(index, () => []).add(c);
      }
    }
    _checkpointIndices = _checkpointIndicesByRouteIndex.keys.toList()..sort();
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trail.trailId != widget.trail.trailId ||
        (oldWidget.recordedTrackPoints == null) !=
            (widget.recordedTrackPoints == null)) {
      _watchCommunityHazards();
    }
    if (oldWidget.trail.trailId != widget.trail.trailId ||
        oldWidget.localDatabase != widget.localDatabase ||
        (oldWidget.recordedTrackPoints == null) !=
            (widget.recordedTrackPoints == null) ||
        oldWidget.route?.encodedPolyline != widget.route?.encodedPolyline) {
      unawaited(_loadStaticHazards());
    }
    final geometryChanged =
        oldWidget.effectiveCheckpoints != widget.effectiveCheckpoints ||
        oldWidget.route != widget.route ||
        oldWidget.recordedTrackPoints != widget.recordedTrackPoints;
    final overlayPointsChanged =
        oldWidget.pinnedPoints != widget.pinnedPoints ||
        oldWidget.checkInPoints != widget.checkInPoints;
    if (geometryChanged) {
      final previouslyHadGeometry = _hasUsableGeometry;
      _buildPoints();
      _syncRouteAnimationDuration();
      _fpvTelemetry.value = _telemetryAt(distanceMeters: 0);
      if (previouslyHadGeometry != _hasUsableGeometry) {
        _mapGeneration++;
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
      }
    }
    if (geometryChanged || overlayPointsChanged) {
      _routeRendered = false;
      _initialFitComplete = false;
      _animatedPolyline = null;
      _lastAnimatedIndex = 0;
      _routeAnimController.stop();
      _renderRetryTimer?.cancel();
      _fitRetryTimer?.cancel();
      _renderGeneration++;
      unawaited(_renderRouteIfReady());
    }
    if (oldWidget.previewMode != widget.previewMode) {
      _previewStartedAt = DateTime.now();
      _routeAnimController.stop();
      _pauseTimer?.cancel();
      _loopPauseTimer?.cancel();
      _pendingFpvProgress = null;
      _isPaused = false;
      _initialFitComplete = false;
      _lastFpvCameraUpdateMs = 0;
      _lastTerrainQueryMs = 0;
      _terrainQueryGeneration++;
      _fpvPitch = 68;
      _fpvZoomOffset = 0;
      _fpvLookAheadMeters = 25;
      _syncRouteAnimationDuration();
      _mapGeneration++;
      _styleLoaded = false;
      _routeRendered = false;
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
      _animatedPolyline = null;
      _cometLayers.clear();
      _lastAnimatedIndex = 0;
      _renderGeneration++;
      _fpvTelemetry.value = _telemetryAt(distanceMeters: 0);
      _fpvBearing.value = 0;
    } else if (oldWidget.animationDuration != widget.animationDuration) {
      _syncRouteAnimationDuration();
    }
    if (oldWidget.highlightedCheckpointIndex !=
        widget.highlightedCheckpointIndex) {
      final index = widget.highlightedCheckpointIndex;
      final sortedIndex = index == null
          ? -1
          : _checkpointOriginalIndices.indexOf(index);
      if (sortedIndex >= 0) {
        _focusOnCheckpoint(_checkpointPoints[sortedIndex]);
      }
    }
  }

  Future<void> _focusOnCheckpoint(mapbox.Point point) async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(center: point, zoom: 16),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {}
  }

  void _onPointAnnotationTapped(mapbox.PointAnnotation annotation) {
    if (!mounted) return;
    final match = _hazardsByAnnotationId[annotation.id];
    if (match == null) return;
    unawaited(showStaticHazardDetails(context, match));
  }

  bool _isCurrentMap(mapbox.MapboxMap map, int generation) {
    return mounted &&
        generation == _mapGeneration &&
        identical(map, _mapboxMap);
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap, int generation) async {
    if (!mounted || generation != _mapGeneration) return;
    final replacingNativeMap =
        _mapboxMap != null && !identical(_mapboxMap, mapboxMap);
    _mapboxMap = mapboxMap;
    if (replacingNativeMap) {
      _styleLoaded = false;
      _routeRendered = false;
      _initialFitComplete = false;
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
    _scheduleStyleWatchdog(generation);
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await mapboxMap.gestures.updateSettings(_gestureSettingsForPreviewMode);
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {
      // The map channel can still be settling. Style/map callbacks retry setup.
    }
    if (!_isCurrentMap(mapboxMap, generation)) return;
    unawaited(_renderRouteIfReady());
    unawaited(_syncScaleFromCamera());
  }

  Future<void> _onStyleLoaded(int generation) async {
    final map = _mapboxMap;
    if (map == null || !_isCurrentMap(map, generation)) return;
    _styleWatchdogTimer?.cancel();
    if (!_styleLoaded) {
      _styleLoaded = true;
      _routeRendered = false;
      _initialFitComplete = false;
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
    if (!await _ensureAnnotationManagers(generation)) return;
    await _renderRouteIfReady();
    if (_isCurrentMap(map, generation)) {
      unawaited(enableTerrain3D(map));
    }
  }

  Future<void> _onMapLoaded(int generation) async {
    final map = _mapboxMap;
    if (map == null || !_isCurrentMap(map, generation)) return;
    _styleWatchdogTimer?.cancel();
    if (!_styleLoaded) {
      _styleLoaded = true;
      _routeRendered = false;
      _initialFitComplete = false;
    }
    await _ensureAnnotationManagers(generation);
    await _renderRouteIfReady();
  }

  Future<bool> _ensureAnnotationManagers(int generation) {
    final map = _mapboxMap;
    if (map == null || !_styleLoaded || !_isCurrentMap(map, generation)) {
      return Future.value(false);
    }
    final existingFuture = _annotationManagersFuture;
    if (existingFuture != null) return existingFuture;
    final future = _createAnnotationManagers(map, generation);
    _annotationManagersFuture = future;
    return future.whenComplete(() {
      if (identical(_annotationManagersFuture, future)) {
        _annotationManagersFuture = null;
      }
    });
  }

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
      return _polylineManager != null &&
          _circleManager != null &&
          _pointManager != null;
    } catch (_) {
      if (_isCurrentMap(map, generation)) {
        _scheduleRenderRetry();
      }
      return false;
    }
  }

  Future<void> _renderRouteIfReady() async {
    if (_isRendering) {
      _renderPending = true;
      return;
    }
    final map = _mapboxMap;
    final mapGeneration = _mapGeneration;
    if (map == null ||
        _routeRendered ||
        !_styleLoaded ||
        _visibleMapPoints.length < 2) {
      return;
    }
    if (!await _ensureAnnotationManagers(mapGeneration)) {
      return;
    }

    final generation = ++_renderGeneration;
    _isRendering = true;
    try {
      _routeAnimController.stop();
      _pauseTimer?.cancel();
      _loopPauseTimer?.cancel();
      _cancelCheckpointGlows();
      _isPaused = false;
      _animatedPolyline = null;
      _checkpointCircleAnnotations = [];
      _hazardsByAnnotationId.clear();
      _cautionMarkerSizer.clear();
      _lastAnimatedIndex = 0;
      await _polylineManager!.deleteAll();
      await _circleManager!.deleteAll();
      await _pointManager!.deleteAll();
      if (!_isCurrentMap(map, mapGeneration) ||
          generation != _renderGeneration) {
        return;
      }

      final displayPoints = _routePoints.length >= 2
          ? _routePoints
          : _checkpointPoints;
      final hasDetailedRoute = _routePoints.length >= 2;

      if (displayPoints.length >= 2) {
        final coordinates = [
          for (final point in displayPoints)
            mapbox.Position(point.coordinates[0]!, point.coordinates[1]!),
        ];
        if (hasDetailedRoute &&
            widget.animateRoute &&
            displayPoints.length > 2) {
          await _polylineManager!.create(
            mapbox.PolylineAnnotationOptions(
              geometry: mapbox.LineString(coordinates: coordinates),
              lineColor: _routeTrailColor.toARGB32(),
              lineOpacity: 0.45,
              lineWidth: _routeLineWidth + 3,
              lineJoin: mapbox.LineJoin.ROUND,
            ),
          );
          _cometLayers.clear();
          for (var layer = 0; layer < 2; layer++) {
            final tail = await _polylineManager!.create(
              mapbox.PolylineAnnotationOptions(
                geometry: mapbox.LineString(
                  coordinates: coordinates.take(2).toList(),
                ),
                lineColor: _routeHighlightColor.toARGB32(),
                lineOpacity: .18 + layer * .22,
                lineWidth: _routeLineWidth,
                lineJoin: mapbox.LineJoin.ROUND,
              ),
            );
            _cometLayers.add(tail);
          }
          _animatedPolyline = await _polylineManager!.create(
            mapbox.PolylineAnnotationOptions(
              geometry: mapbox.LineString(
                coordinates: coordinates.take(2).toList(),
              ),
              lineColor: _routeHighlightColor.toARGB32(),
              lineOpacity: 0.9,
              lineWidth: _routeLineWidth,
              lineJoin: mapbox.LineJoin.ROUND,
            ),
          );
          if (_animatedPolyline != null) {
            _lastAnimatedIndex = 1;
          }
        } else {
          await _polylineManager!.create(
            mapbox.PolylineAnnotationOptions(
              geometry: mapbox.LineString(coordinates: coordinates),
              lineColor:
                  (hasDetailedRoute
                          ? _routeHighlightColor
                          : const Color(0xFFF59E0B))
                      .toARGB32(),
              lineOpacity: hasDetailedRoute ? 0.9 : 0.72,
              lineWidth: hasDetailedRoute
                  ? _routeLineWidth + 0.5
                  : _routeLineWidth,
              lineJoin: mapbox.LineJoin.ROUND,
            ),
          );
        }
      }

      final circleOptions = <mapbox.CircleAnnotationOptions>[
        for (final checkpoint
            in _checkpointPoints
                .skip(1)
                .take(math.max(0, _checkpointPoints.length - 2)))
          mapbox.CircleAnnotationOptions(
            geometry: checkpoint,
            circleColor: _routeHighlightColor.toARGB32(),
            circleOpacity: 0.65,
            circleRadius: 4.2,
            circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
            circleStrokeWidth: 1.2,
          ),
      ];
      if (circleOptions.isNotEmpty) {
        _checkpointCircleAnnotations = await _circleManager!.createMulti(
          circleOptions,
        );
      }

      final endpointPin = await routeEndpointPinImage();
      if (!_isCurrentMap(map, mapGeneration) ||
          generation != _renderGeneration) {
        return;
      }
      final separateEndpointLabels = shouldSeparateRouteEndpointLabels(
        _startPoint,
        _endPoint,
      );
      await _pointManager!.createMulti([
        routeEndpointAnnotation(
          geometry: _startPoint,
          label: widget.recordedTrackPoints != null && _routePoints.length == 1
              ? 'Recorded location'
              : 'Start',
          pinImage: endpointPin,
          separateLabel: separateEndpointLabels,
        ),
        if (widget.recordedTrackPoints == null || _routePoints.length > 1)
          routeEndpointAnnotation(
            geometry: _endPoint,
            label: 'End',
            pinImage: endpointPin,
            separateLabel: separateEndpointLabels,
          ),
      ]);

      final hazardMarkers = await Future.wait([
        for (final match in _staticHazards) staticHazardMarkerImageFor(match),
      ]);
      if (!_isCurrentMap(map, mapGeneration) ||
          generation != _renderGeneration) {
        return;
      }
      final hazardAnnotations = await _pointManager!.createMulti([
        for (var index = 0; index < _staticHazards.length; index++)
          staticHazardAnnotation(
            _staticHazards[index],
            hazardMarkers[index],
            scaleFactor: cautionMarkerScale(_currentZoom, _scaleLatitude) / .65,
          ),
      ]);
      for (var index = 0; index < hazardAnnotations.length; index++) {
        final annotation = hazardAnnotations[index];
        if (annotation != null && index < _staticHazards.length) {
          _hazardsByAnnotationId[annotation.id] = _staticHazards[index];
          _cautionMarkerSizer.add(
            annotation,
            _staticHazards[index].hazard.severity == 'warning' ? .72 : .64,
          );
        }
      }

      final validPinnedPoints = widget.pinnedPoints
          .where(_isValidMapPoint)
          .toList();
      if (validPinnedPoints.isNotEmpty) {
        await _pointManager!.createMulti(
          validPinnedPoints
              .map(
                (pin) => mapbox.PointAnnotationOptions(
                  geometry: pin,
                  iconSize: 0.7,
                  iconImage: 'marker',
                  iconAnchor: mapbox.IconAnchor.BOTTOM,
                ),
              )
              .toList(),
        );
      }

      final validCheckInPoints = widget.checkInPoints
          .where(_isValidMapPoint)
          .toList();
      if (validCheckInPoints.isNotEmpty) {
        await _pointManager!.createMulti(
          validCheckInPoints
              .map(
                (ci) => mapbox.PointAnnotationOptions(
                  geometry: ci,
                  iconSize: 0.5,
                  iconImage: 'circle',
                  iconColor: 0xFF0A84FF,
                ),
              )
              .toList(),
        );
      }

      if (!_isCurrentMap(map, mapGeneration) ||
          generation != _renderGeneration) {
        return;
      }
      final animatedPolyline = _animatedPolyline;
      if (animatedPolyline != null) {
        _animateRoute(animatedPolyline);
      }
      setState(() {
        _routeRendered = true;
      });
      await Future.delayed(const Duration(milliseconds: 180));
      await _positionCameraForPreviewMode();
    } catch (_) {
      if (mounted && generation == _renderGeneration) {
        setState(() {
          _routeRendered = false;
          _initialFitComplete = false;
        });
        _scheduleRenderRetry();
      }
    } finally {
      _isRendering = false;
      if (_renderPending && mounted) {
        _renderPending = false;
        _routeRendered = false;
        unawaited(_renderRouteIfReady());
      }
    }
  }

  void _scheduleRenderRetry() {
    _renderRetryTimer?.cancel();
    _renderRetryTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        unawaited(_renderRouteIfReady());
      }
    });
  }

  void _scheduleStyleWatchdog(int generation) {
    _styleWatchdogTimer?.cancel();
    _styleWatchdogTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || generation != _mapGeneration || _styleLoaded) {
        return;
      }
      setState(() {
        _mapGeneration++;
        _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
        _routeRendered = false;
        _initialFitComplete = false;
        _polylineManager = null;
        _circleManager = null;
        _pointManager = null;
        _communityCautionLayer.reset();
        _annotationManagersFuture = null;
        _mapboxMap = null;
        _renderGeneration++;
      });
    });
  }

  void _animateRoute(mapbox.PolylineAnnotation annotation) {
    if (!mounted) return;
    _routeAnimController.forward(from: 0);
  }

  mapbox.GesturesSettings get _gestureSettingsForPreviewMode {
    final cameraIsFollowing =
        widget.previewMode == RoutePreviewMode.firstPerson;
    return mapbox.GesturesSettings(
      scrollEnabled: !cameraIsFollowing,
      pinchToZoomEnabled: !cameraIsFollowing,
      rotateEnabled: !cameraIsFollowing,
      pitchEnabled: !cameraIsFollowing,
    );
  }

  Future<void> _positionCameraForPreviewMode() {
    if (widget.previewMode == RoutePreviewMode.firstPerson) {
      return _setFpvCamera(_routeAnimProgress.value, force: true);
    }
    return _fitRoute();
  }

  void _queueFpvCameraUpdate(double progress, {bool force = false}) {
    if (widget.previewMode != RoutePreviewMode.firstPerson) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastFpvCameraUpdateMs < 120) return;
    _lastFpvCameraUpdateMs = now;
    _pendingFpvProgress = progress;
    if (!_fpvCameraUpdateInFlight) {
      unawaited(_drainFpvCameraUpdates());
    }
  }

  Future<void> _drainFpvCameraUpdates() async {
    _fpvCameraUpdateInFlight = true;
    try {
      while (mounted && _pendingFpvProgress != null) {
        final progress = _pendingFpvProgress!;
        _pendingFpvProgress = null;
        await _setFpvCamera(progress);
      }
    } finally {
      _fpvCameraUpdateInFlight = false;
    }
  }

  Future<void> _setFpvCamera(double progress, {bool force = false}) async {
    if (widget.previewMode != RoutePreviewMode.firstPerson) return;
    final map = _mapboxMap;
    final generation = _mapGeneration;
    final cameraPoints = _routePoints.length >= 2
        ? _routePoints
        : _checkpointPoints;
    if (map == null || cameraPoints.length < 2) return;

    var distances = _routeDistances;
    if (cameraPoints.length != distances.length) {
      distances = [0];
      for (var i = 1; i < cameraPoints.length; i++) {
        distances.add(
          distances.last + distanceMeters(cameraPoints[i - 1], cameraPoints[i]),
        );
      }
    }
    final frame = routePreviewCameraFrame(
      points: cameraPoints,
      cumulativeDistances: distances,
      progress: progress,
      lookAheadMeters: 60,
      headingSampleMeters: 20,
    );
    if (frame == null) return;

    final previousTelemetry = _fpvTelemetry.value;
    final targetTuning = routePreviewCameraTuning(
      previousTelemetry.gradePercent,
    );
    const tuningResponse = 0.18;
    _fpvPitch += (targetTuning.pitch - _fpvPitch) * tuningResponse;
    _fpvZoomOffset +=
        (targetTuning.zoomOffset - _fpvZoomOffset) * tuningResponse;
    _fpvLookAheadMeters +=
        (targetTuning.lookAheadMeters - _fpvLookAheadMeters) * tuningResponse;
    final cameraTarget = routePreviewPointAtDistance(
      points: cameraPoints,
      cumulativeDistances: distances,
      distanceMeters: math.min(
        distances.last,
        frame.distanceMeters + _fpvLookAheadMeters,
      ),
    );
    _fpvTelemetry.value = _telemetryAt(
      distanceMeters: frame.distanceMeters,
      elevationMeters: previousTelemetry.elevationMeters,
      gradePercent: previousTelemetry.gradePercent,
    );
    if (!_initialFitComplete) _fpvHeadingFilter.reset();
    final heading = _fpvHeadingFilter.update(
      bearing: frame.bearing,
      distanceMeters: frame.distanceMeters,
      elapsed: _fpvCameraClock.elapsed,
    );
    _fpvBearing.value = heading;

    try {
      final options = mapbox.CameraOptions(
        center: cameraTarget ?? frame.center,
        zoom: (_fpvZoom + _fpvZoomOffset).clamp(14.5, kMapMaxZoom).toDouble(),
        bearing: heading,
        pitch: _fpvPitch,
        padding: mapbox.MbxEdgeInsets(top: 84, left: 20, bottom: 24, right: 20),
      );
      if (!_initialFitComplete || force) {
        await map.setCamera(options);
      } else {
        // Interpolate between camera samples rather than jumping every tick.
        await map.easeTo(options, mapbox.MapAnimationOptions(duration: 180));
      }
      _queueTerrainTelemetryUpdate(
        map: map,
        generation: generation,
        frame: frame,
        cameraPoints: cameraPoints,
        cumulativeDistances: distances,
      );
      if (_isCurrentMap(map, generation) && !_initialFitComplete) {
        setState(() {
          _initialFitComplete = true;
        });
      }
    } catch (_) {
      if (force && _isCurrentMap(map, generation)) {
        _fitRetryTimer?.cancel();
        _fitRetryTimer = Timer(const Duration(milliseconds: 350), () {
          if (mounted && generation == _mapGeneration) {
            _queueFpvCameraUpdate(progress, force: true);
          }
        });
      }
    }
  }

  void _queueTerrainTelemetryUpdate({
    required mapbox.MapboxMap map,
    required int generation,
    required RoutePreviewCameraFrame frame,
    required List<mapbox.Point> cameraPoints,
    required List<double> cumulativeDistances,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_terrainQueryInFlight || now - _lastTerrainQueryMs < 350) return;
    _terrainQueryInFlight = true;
    _lastTerrainQueryMs = now;
    final queryGeneration = ++_terrainQueryGeneration;
    unawaited(() async {
      try {
        const halfSlopeSampleMeters = 15.0;
        final sampleStartDistance = math.max(
          0.0,
          frame.distanceMeters - halfSlopeSampleMeters,
        );
        final sampleEndDistance = math.min(
          cumulativeDistances.last,
          frame.distanceMeters + halfSlopeSampleMeters,
        );
        final sampleStartPoint = routePreviewPointAtDistance(
          points: cameraPoints,
          cumulativeDistances: cumulativeDistances,
          distanceMeters: sampleStartDistance,
        );
        final sampleEndPoint = routePreviewPointAtDistance(
          points: cameraPoints,
          cumulativeDistances: cumulativeDistances,
          distanceMeters: sampleEndDistance,
        );
        final elevations = await Future.wait<double?>([
          map.getElevation(frame.center),
          sampleStartPoint == null
              ? Future<double?>.value()
              : map.getElevation(sampleStartPoint),
          sampleEndPoint == null
              ? Future<double?>.value()
              : map.getElevation(sampleEndPoint),
        ]);
        final currentRaw = elevations[0];
        final sampleStartRaw = elevations[1];
        final sampleEndRaw = elevations[2];
        if (!_isCurrentMap(map, generation) ||
            queryGeneration != _terrainQueryGeneration ||
            currentRaw == null ||
            !currentRaw.isFinite) {
          return;
        }

        // Mapbox returns terrain elevation after visual exaggeration.
        final elevation = currentRaw / mapTerrainExaggeration;
        double? grade;
        final sampleDistance = sampleEndDistance - sampleStartDistance;
        if (sampleStartRaw != null &&
            sampleStartRaw.isFinite &&
            sampleEndRaw != null &&
            sampleEndRaw.isFinite &&
            sampleDistance >= 8) {
          final startElevation = sampleStartRaw / mapTerrainExaggeration;
          final endElevation = sampleEndRaw / mapTerrainExaggeration;
          grade = ((endElevation - startElevation) / sampleDistance * 100)
              .clamp(-99.0, 99.0)
              .toDouble();
        }
        final current = _fpvTelemetry.value;
        _fpvTelemetry.value = _FpvTelemetry(
          distanceMeters: current.distanceMeters,
          elapsed: current.elapsed,
          progress: current.progress,
          elevationMeters: elevation,
          gradePercent: grade,
        );
      } catch (_) {
        // Terrain tiles can still be loading. A later camera frame retries.
      } finally {
        _terrainQueryInFlight = false;
      }
    }());
  }

  Future<void> _fitRoute() async {
    if (_isFitting) {
      _fitPending = true;
      return;
    }
    final map = _mapboxMap;
    final mapGeneration = _mapGeneration;
    if (map == null || _visibleMapPoints.length < 2) return;

    final bounds = boundsFor(_visibleMapPoints);
    if (bounds.minLon > bounds.maxLon || bounds.minLat > bounds.maxLat) {
      return;
    }

    _isFitting = true;
    try {
      final camera =
          bounds.minLon == bounds.maxLon && bounds.minLat == bounds.maxLat
          ? mapbox.CameraOptions(center: _startPoint, zoom: 16)
          : await map.cameraForCoordinateBounds(
              mapbox.CoordinateBounds(
                southwest: mapbox.Point(
                  coordinates: mapbox.Position(bounds.minLon, bounds.minLat),
                ),
                northeast: mapbox.Point(
                  coordinates: mapbox.Position(bounds.maxLon, bounds.maxLat),
                ),
                infiniteBounds: false,
              ),
              mapbox.MbxEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
              null,
              null,
              null,
              null,
            );
      final cameraCenter = camera.center == null
          ? null
          : mapPointCoordinatesOrNull(camera.center!);
      if (camera.zoom == null ||
          !camera.zoom!.isFinite ||
          cameraCenter == null) {
        throw StateError('Mapbox did not return a valid route camera.');
      }

      await map.flyTo(camera, mapbox.MapAnimationOptions(duration: 350));
      await Future.delayed(const Duration(milliseconds: 380));
      if (!_isCurrentMap(map, mapGeneration)) return;
      final state = await map.getCameraState();
      final settledCenter = mapPointCoordinatesOrNull(state.center);
      if (settledCenter == null) {
        throw StateError('Mapbox returned an invalid settled route camera.');
      }
      final centerLongitude = settledCenter.longitude;
      final centerLatitude = settledCenter.latitude;
      final latitudeMargin = math.max(
        0.002,
        (bounds.maxLat - bounds.minLat) * 0.75,
      );
      final longitudeMargin = math.max(
        0.002,
        (bounds.maxLon - bounds.minLon) * 0.75,
      );
      final centerLooksValid =
          centerLatitude >= bounds.minLat - latitudeMargin &&
          centerLatitude <= bounds.maxLat + latitudeMargin &&
          centerLongitude >= bounds.minLon - longitudeMargin &&
          centerLongitude <= bounds.maxLon + longitudeMargin &&
          state.zoom.isFinite;
      if (!centerLooksValid) {
        throw StateError('The route camera did not settle on the route.');
      }

      _fitRetryTimer?.cancel();
      if (_isCurrentMap(map, mapGeneration)) {
        setState(() {
          _initialFitComplete = true;
        });
      }
    } catch (_) {
      if (!_isCurrentMap(map, mapGeneration)) return;
      try {
        final latitudeSpan = bounds.maxLat - bounds.minLat;
        final longitudeSpan = bounds.maxLon - bounds.minLon;
        final largestSpan = math.max(
          0.0005,
          math.max(latitudeSpan, longitudeSpan),
        );
        final fallbackZoom = (math.log(360 / largestSpan) / math.ln2 - 1.8)
            .clamp(kMapMinZoom, 17.5)
            .toDouble();
        await map.flyTo(
          mapbox.CameraOptions(
            center: centerFor(_visibleMapPoints),
            zoom: fallbackZoom,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(duration: 350),
        );
        _fitRetryTimer?.cancel();
        if (_isCurrentMap(map, mapGeneration)) {
          setState(() {
            _initialFitComplete = true;
          });
        }
      } catch (_) {
        if (_isCurrentMap(map, mapGeneration)) {
          setState(() {
            _initialFitComplete = false;
          });
          _fitRetryTimer?.cancel();
          _fitRetryTimer = Timer(const Duration(milliseconds: 800), () {
            if (mounted && mapGeneration == _mapGeneration) {
              unawaited(_fitRoute());
            }
          });
        }
      }
    } finally {
      _isFitting = false;
      if (_fitPending && mounted) {
        _fitPending = false;
        unawaited(_fitRoute());
      }
    }
    unawaited(_syncScaleFromCamera());
  }

  Future<void> _zoomBy(double amount) async {
    if (_mapboxMap == null) return;
    if (widget.previewMode == RoutePreviewMode.firstPerson) {
      _fpvZoom = (_fpvZoom + amount).clamp(14.5, kMapMaxZoom).toDouble();
      _queueFpvCameraUpdate(_routeAnimProgress.value, force: true);
      return;
    }
    try {
      await _mapboxMap!.flyTo(
        mapbox.CameraOptions(zoom: _currentZoom + amount),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {}
    await _syncScaleFromCamera();
  }

  void _cycleStyle() {
    if (widget.previewMode == RoutePreviewMode.firstPerson) return;
    setState(() {
      _mapGeneration++;
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
      _initialFitComplete = false;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
      _communityCautionLayer.reset();
      _annotationManagersFuture = null;
      _mapboxMap = null;
      _renderGeneration++;
    });
  }

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _updateScale(data);
  }

  void _onMapIdle() {
    unawaited(_syncScaleFromCamera());
    if (_routeRendered && !_initialFitComplete) {
      unawaited(_positionCameraForPreviewMode());
    }
  }

  Future<void> _resetCameraForPreviewMode() async {
    if (widget.previewMode == RoutePreviewMode.firstPerson) {
      _fpvZoom = 17.2;
      await _setFpvCamera(_routeAnimProgress.value, force: true);
      return;
    }
    await _fitRoute();
  }

  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    final generation = _mapGeneration;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      if (_isCurrentMap(map, generation)) {
        _updateScaleFromState(state);
      }
    } catch (_) {
      // The native map may have been replaced while reading its camera.
    }
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    _updateScaleValues(data.cameraState.zoom, data.cameraState.center);
  }

  void _updateScaleFromState(mapbox.CameraState state) {
    _updateScaleValues(state.zoom, state.center);
  }

  void _updateScaleValues(double nextZoom, mapbox.Point center) {
    final coordinates = mapPointCoordinatesOrNull(center);
    if (!mounted || !nextZoom.isFinite || coordinates == null) return;
    final nextLatitude = coordinates.latitude;
    if (((nextZoom - _currentZoom).abs() < 0.005 &&
        (nextLatitude - _scaleLatitude).abs() < 0.0005)) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
    _communityCautionLayer.setScale(_currentZoom, _scaleLatitude);
    unawaited(
      _cautionMarkerSizer.resize(
        _pointManager,
        cautionMarkerScale(_currentZoom, _scaleLatitude) / .65,
      ),
    );
  }

  List<mapbox.Point> get _visibleMapPoints {
    if (!_hasUsableGeometry) return const [];
    if (_routePoints.length >= 2) {
      return [..._routePoints, _startPoint, _endPoint];
    }
    return _checkpointPoints.length >= 2
        ? _checkpointPoints
        : [_startPoint, _endPoint];
  }

  List<mapbox.Point> _decodePolyline(String encoded) {
    try {
      final points = <mapbox.Point>[];
      var index = 0;
      var latitude = 0;
      var longitude = 0;

      int? readDelta() {
        var shift = 0;
        var result = 0;
        while (true) {
          if (index >= encoded.length || shift > 30) return null;
          final byte = encoded.codeUnitAt(index++) - 63;
          if (byte < 0 || byte > 0x3f) return null;
          result |= (byte & 0x1f) << shift;
          if (byte < 0x20) {
            return (result & 1) == 1 ? ~(result >> 1) : result >> 1;
          }
          shift += 5;
        }
      }

      while (index < encoded.length) {
        final latitudeDelta = readDelta();
        final longitudeDelta = readDelta();
        if (latitudeDelta == null || longitudeDelta == null) return const [];
        latitude += latitudeDelta;
        longitude += longitudeDelta;
        final point = mapbox.Point(
          coordinates: mapbox.Position(longitude / 100000, latitude / 100000),
        );
        if (!_isValidMapPoint(point)) return const [];
        points.add(point);
      }
      return points;
    } catch (_) {
      return const [];
    }
  }

  List<mapbox.Point> _orientRoutePoints(List<mapbox.Point> points) {
    if (points.length < 2 || !_hasUsableGeometry) {
      return points;
    }

    final forwardScore =
        distanceMeters(points.first, _startPoint) +
        distanceMeters(points.last, _endPoint);
    final reverseScore =
        distanceMeters(points.first, _endPoint) +
        distanceMeters(points.last, _startPoint);

    if (reverseScore < forwardScore) {
      return points.reversed.toList();
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUsableGeometry) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            widget.recordedTrackPoints != null
                ? 'No GPS movement was recorded for this hike'
                : 'Trail coordinates are unavailable',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final isPreparingMap =
        !_styleLoaded || !_routeRendered || !_initialFitComplete;
    final mapGeneration = _mapGeneration;
    final activeStyleUrl = _activeStyleUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: ValueKey('$activeStyleUrl#$mapGeneration'),
            styleUri: activeStyleUrl,
            gestureRecognizers: widget.captureAllGestures
                ? eagerMapGestureRecognizers
                : mapGestureRecognizers,
            onMapCreated: (map) => _onMapCreated(map, mapGeneration),
            onStyleLoadedListener: (_) => _onStyleLoaded(mapGeneration),
            onMapLoadedListener: (_) => _onMapLoaded(mapGeneration),
            onCameraChangeListener: (data) {
              if (mapGeneration == _mapGeneration) {
                _onCameraChange(data);
              }
            },
            onMapIdleListener: (_) {
              if (mapGeneration == _mapGeneration) {
                _onMapIdle();
              }
            },
          ),
        ),
        if (widget.previewMode == RoutePreviewMode.normal)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MapZoomControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
                onReset: _resetCameraForPreviewMode,
                onLayer: widget.showLayerToggle ? _cycleStyle : null,
              ),
            ),
          ),
        if (widget.previewMode == RoutePreviewMode.firstPerson &&
            !isPreparingMap)
          Positioned(
            right: 10,
            top: 10,
            width: 132,
            child: ValueListenableBuilder<_FpvTelemetry>(
              valueListenable: _fpvTelemetry,
              builder: (context, telemetry, _) {
                final arrival = (widget.departureTime ?? _previewStartedAt).add(
                  telemetry.elapsed,
                );
                final rain = trailRainEstimateAt(
                  widget.trail.weather,
                  forecastTime: arrival,
                  now: DateTime.now(),
                );
                return _FpvTelemetryPanel(
                  telemetry: telemetry,
                  rainTimeLabel: trailForecastArrivalLabel(
                    widget.trail.weather,
                    rain.time,
                  ),
                  rainProbability: rain.probability,
                );
              },
            ),
          ),
        if (widget.previewMode == RoutePreviewMode.firstPerson &&
            !isPreparingMap)
          Positioned(
            left: 10,
            bottom: 10,
            child: _FpvSpeedControl(
              speed: _fpvPlaybackSpeed,
              onChanged: _setFpvPlaybackSpeed,
            ),
          ),
        if (widget.previewMode == RoutePreviewMode.firstPerson &&
            !isPreparingMap)
          Positioned(
            right: 10,
            bottom: 10,
            child: ValueListenableBuilder<double>(
              valueListenable: _fpvBearing,
              builder: (context, bearing, _) => _FpvCompass(bearing: bearing),
            ),
          ),
        if (widget.previewMode == RoutePreviewMode.normal)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MapScaleBar(zoom: _currentZoom, latitude: _scaleLatitude),
            ),
          ),
        if (isPreparingMap)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.82),
              child: HikerCircleLoadingView(
                message: !_styleLoaded
                    ? 'Preparing map…'
                    : !_routeRendered
                    ? 'Drawing route…'
                    : 'Focusing route…',
                detail: 'This can take longer on a slow connection.',
                compact: true,
                padding: const EdgeInsets.all(8),
              ),
            ),
          )
        else if (widget.isRouteLoading)
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.loadingMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FpvTelemetryPanel extends StatelessWidget {
  const _FpvTelemetryPanel({
    required this.telemetry,
    required this.rainTimeLabel,
    this.rainProbability,
  });

  final String rainTimeLabel;

  final int? rainProbability;

  final _FpvTelemetry telemetry;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFFB9C8BE);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEA101A14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x5534A853)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'LIVE ROUTE',
                  style: TextStyle(
                    color: Color(0xFF7EE2A0),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(telemetry.progress * 100).round()}%',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: telemetry.progress,
                color: const Color(0xFF4ADE80),
                backgroundColor: const Color(0xFF29372E),
              ),
            ),
            const SizedBox(height: 8),
            _FpvTelemetryRow(
              icon: Icons.terrain_rounded,
              label: 'Elevation',
              value: telemetry.elevationMeters == null
                  ? 'Loading…'
                  : '${telemetry.elevationMeters!.round()} m',
            ),
            _FpvTelemetryRow(
              icon: _gradeIcon(telemetry.gradePercent),
              label: 'Steepness',
              value: _gradeLabel(telemetry.gradePercent),
            ),
            _FpvTelemetryRow(
              icon: Icons.schedule_rounded,
              label: 'Est. elapsed',
              value: _durationLabel(telemetry.elapsed),
            ),
            _FpvTelemetryRow(
              icon: Icons.route_rounded,
              label: 'Distance',
              value: _distanceLabel(telemetry.distanceMeters),
            ),
            Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              message:
                  'Estimated hourly rain-probability trend at your arrival time, '
                  'sampled every 10 hiking minutes between hourly forecasts. '
                  'Not a separate 10-minute forecast.',
              child: _FpvTelemetryRow(
                icon: Icons.water_drop_outlined,
                label: 'Rain est. · $rainTimeLabel',
                labelMaxLines: 2,
                value: rainProbability == null
                    ? 'Unavailable'
                    : '$rainProbability% · 10m',
                bottomPadding: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _gradeIcon(double? grade) {
    if (grade == null || grade.abs() < 2) return Icons.trending_flat_rounded;
    return grade > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
  }

  String _gradeLabel(double? grade) {
    if (grade == null) return 'Loading…';
    final degrees = routePreviewSlopeDegrees(grade);
    if (degrees.abs() < 1) return 'Level';
    return '${degrees.abs().round()}° ${degrees > 0 ? 'up' : 'down'}';
  }

  String _durationLabel(Duration value) {
    final minutes = value.inMinutes;
    if (minutes == 0 && value > Duration.zero) return '<1 min';
    if (minutes < 60) return '${math.max(0, minutes)} min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
  }

  String _distanceLabel(double meters) {
    if (meters < 1000) return '${math.max(0, meters).round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class _FpvTelemetryRow extends StatelessWidget {
  const _FpvTelemetryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.bottomPadding = 6,
    this.labelMaxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final double bottomPadding;
  final int labelMaxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF7EE2A0)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: labelMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9EADA3),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
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

class _FpvSpeedControl extends StatelessWidget {
  const _FpvSpeedControl({required this.speed, required this.onChanged});

  static const _speeds = <double>[0.5, 1, 2, 4];

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEA101A14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x5534A853)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _speeds)
              Tooltip(
                message: '${option == 0.5 ? 'Half' : option.toInt()} speed',
                child: Semantics(
                  button: true,
                  selected: speed == option,
                  label: '${option == 0.5 ? 'Half' : option.toInt()} speed',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => onChanged(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 34,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: speed == option
                            ? const Color(0xFF34A853)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        option == 0.5 ? '0.5×' : '${option.toInt()}×',
                        style: TextStyle(
                          color: speed == option
                              ? Colors.white
                              : const Color(0xFFC7D2CA),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FpvCompass extends StatelessWidget {
  const _FpvCompass({required this.bearing});

  final double bearing;

  @override
  Widget build(BuildContext context) {
    final normalized = bearing.isFinite ? (bearing % 360 + 360) % 360 : 0.0;
    final cardinal = routePreviewCardinalDirection(normalized);
    return Semantics(
      label: 'Compass. Heading ${normalized.round()} degrees $cardinal',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xEA101A14),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x7734A853), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 9,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 7,
                child: Transform.rotate(
                  angle: -normalized * math.pi / 180,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'N',
                        style: TextStyle(
                          color: Color(0xFFFF6B61),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      Icon(
                        Icons.navigation_rounded,
                        size: 24,
                        color: Color(0xFFFF6B61),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                child: Text(
                  '${normalized.round()}° $cardinal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
