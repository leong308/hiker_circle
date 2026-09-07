import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/services/hiking_route_service.dart';
import '../../trail/Model/trail_models.dart';
import 'loading_toast.dart';
import 'map_controls.dart';
import 'map_utils.dart';
import 'route_endpoint_marker.dart';
import 'route_animation_geometry.dart';

bool _isValidMapPoint(mapbox.Point point) {
  return mapPointCoordinatesOrNull(point) != null;
}

class RoutePreviewMap extends StatefulWidget {
  const RoutePreviewMap({
    super.key,
    required this.trail,
    this.route,
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
  });

  final Trail trail;
  final HikingRouteResult? route;
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

  List<TrailCheckpoint> get effectiveCheckpoints =>
      customCheckpoints ?? trail.checkpoints;

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap>
    with SingleTickerProviderStateMixin {
  static const _routeLineWidth = 2.65;

  late List<mapbox.Point> _routePoints;
  late List<mapbox.Point> _checkpointPoints;
  late mapbox.Point _startPoint;
  late mapbox.Point _endPoint;
  late double _currentZoom;
  late double _scaleLatitude;
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  Future<bool>? _annotationManagersFuture;
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

  @override
  void initState() {
    super.initState();
    _styleIndex = widget.initialStyleIndex.clamp(0, mapStyleUrls.length - 1);
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

    _routeAnimController.reset();
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
    if (targetIndex == _lastAnimatedIndex) return;
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
        annotation.circleColor = const Color(0xFF34A853).toARGB32();
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
            annotation.circleColor = const Color(0xFF2F8E50).toARGB32();
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
    _pauseTimer?.cancel();
    _loopPauseTimer?.cancel();
    _cancelCheckpointGlows();
    _styleWatchdogTimer?.cancel();
    _renderRetryTimer?.cancel();
    _fitRetryTimer?.cancel();
    _renderGeneration++;
    _mapGeneration++;
    _mapboxMap = null;
    _annotationManagersFuture = null;
    _routeAnimController.removeListener(_onRouteAnimationTick);
    _routeAnimController.removeStatusListener(_onAnimationStatusChange);
    _routeAnimController.dispose();
    super.dispose();
  }

  void _buildPoints() {
    final checkpoints =
        widget.effectiveCheckpoints
            .where((checkpoint) => checkpoint.hasValidCoordinate)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    _checkpointPoints = checkpoints
        .map(
          (cp) => mapbox.Point(
            coordinates: mapbox.Position(cp.longitude, cp.latitude),
          ),
        )
        .toList();
    final route = widget.route;
    final decodedRoute = route == null
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
    _checkpointIndices.clear();
    _checkpointIndicesByRouteIndex = {};
    if (_routePoints.isEmpty || _checkpointPoints.isEmpty) return;

    final matches = orderedCheckpointMatches([
      for (final checkpoint in _checkpointPoints)
        [for (final point in _routePoints) distanceMeters(checkpoint, point)],
    ]);
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
    final geometryChanged =
        oldWidget.effectiveCheckpoints != widget.effectiveCheckpoints ||
        oldWidget.route != widget.route;
    final overlayPointsChanged =
        oldWidget.pinnedPoints != widget.pinnedPoints ||
        oldWidget.checkInPoints != widget.checkInPoints;
    if (geometryChanged) {
      final previouslyHadGeometry = _hasUsableGeometry;
      _buildPoints();
      if (previouslyHadGeometry != _hasUsableGeometry) {
        _mapGeneration++;
        _styleLoaded = false;
        _mapboxMap = null;
        _polylineManager = null;
        _circleManager = null;
        _pointManager = null;
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
    if (oldWidget.highlightedCheckpointIndex !=
        widget.highlightedCheckpointIndex) {
      final index = widget.highlightedCheckpointIndex;
      if (index != null && index >= 0 && index < _checkpointPoints.length) {
        _focusOnCheckpoint(_checkpointPoints[index]);
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
      _annotationManagersFuture = null;
      _renderGeneration++;
    }
    _scheduleStyleWatchdog(generation);
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
      _polylineManager = polylineManager;
      _circleManager = circleManager;
      _pointManager = pointManager;
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
              lineColor: const Color(0xFF4ADE80).toARGB32(),
              lineOpacity: 0.12,
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
                lineColor: const Color(0xFF2F8E50).toARGB32(),
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
              lineColor: const Color(0xFF2F8E50).toARGB32(),
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
                          ? const Color(0xFF2F8E50)
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
            circleColor: const Color(0xFF2F8E50).toARGB32(),
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
      await _fitRoute();
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
    try {
      await _mapboxMap!.flyTo(
        mapbox.CameraOptions(zoom: _currentZoom + amount),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {}
    await _syncScaleFromCamera();
  }

  void _cycleStyle() {
    setState(() {
      _mapGeneration++;
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
      _initialFitComplete = false;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
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
      unawaited(_fitRoute());
    }
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
            'Trail coordinates are unavailable',
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
    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: ValueKey(mapStyleUrls[_styleIndex]),
            styleUri: mapStyleUrls[_styleIndex],
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
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: MapZoomControls(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
              onReset: _fitRoute,
              onLayer: widget.showLayerToggle ? _cycleStyle : null,
            ),
          ),
        ),
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
