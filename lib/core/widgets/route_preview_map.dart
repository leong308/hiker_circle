import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/services/hiking_route_service.dart';
import '../../trail/Model/trail_models.dart';
import 'map_controls.dart';
import 'map_utils.dart';

class RoutePreviewMap extends StatefulWidget {
  const RoutePreviewMap({
    super.key,
    required this.trail,
    this.route,
    this.highlightedCheckpointIndex,
    this.customCheckpoints,
    this.showLayerToggle = false,
    this.animateRoute = true,
    this.animationDuration = const Duration(seconds: 5),
    this.pinnedPoints = const [],
    this.checkInPoints = const [],
    this.captureAllGestures = false,
    this.isRouteLoading = false,
    this.loadingMessage = 'Loading route…',
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
  var _styleIndex = 4;
  var _styleLoaded = false;
  var _routeRendered = false;
  late final AnimationController _routeAnimController;
  late final Animation<double> _routeAnimProgress;
  int _lastAnimatedIndex = 0;
  mapbox.PolylineAnnotation? _animatedPolyline;
  List<int> _checkpointIndices = [];
  Timer? _pauseTimer;
  Timer? _styleWatchdogTimer;
  Timer? _renderRetryTimer;
  Timer? _fitRetryTimer;
  bool _isPaused = false;
  bool _isRendering = false;
  bool _isFitting = false;
  bool _initialFitComplete = false;
  int _renderGeneration = 0;

  @override
  void initState() {
    super.initState();
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
      // Loop: reset to start and continue
      _routeAnimController.reset();
      _routeAnimController.forward();
    }
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
    final targetIndex = (progress * (_routePoints.length - 1)).round().clamp(
      1,
      _routePoints.length,
    );
    if (targetIndex == _lastAnimatedIndex) return;
    _lastAnimatedIndex = targetIndex;

    final partialCoordinates = <mapbox.Position>[
      for (final pt in _routePoints.take(targetIndex))
        mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
    ];
    _animatedPolyline!.geometry = mapbox.LineString(
      coordinates: partialCoordinates,
    );
    _polylineManager?.update(_animatedPolyline!);

    // Check if we reached a checkpoint
    if (_checkpointIndices.contains(targetIndex)) {
      _pauseAtCheckpoint(targetIndex);
    }
  }

  void _pauseAtCheckpoint(int index) {
    if (_isPaused) return;
    _isPaused = true;
    _routeAnimController.stop();

    // Trigger checkpoint glow
    _triggerCheckpointGlow(index);

    _pauseTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _isPaused = false;
      _routeAnimController.forward();
    });
  }

  void _triggerCheckpointGlow(int routeIndex) {
    // Find which actual checkpoint this route index corresponds to
    int? checkpointIdx;
    if (_checkpointPoints.isEmpty) return;

    // For each checkpoint (skipping start/end if they match), find closest route point
    for (int i = 0; i < _checkpointPoints.length; i++) {
      double minDist = double.infinity;
      int closestRouteIdx = 0;
      for (int j = 0; j < _routePoints.length; j++) {
        final dist = distanceMeters(_checkpointPoints[i], _routePoints[j]);
        if (dist < minDist) {
          minDist = dist;
          closestRouteIdx = j;
        }
      }
      if (closestRouteIdx == routeIndex) {
        checkpointIdx = i;
        break;
      }
    }
    if (checkpointIdx == null) return;

    // Update the checkpoint circle to glow
    _glowCheckpoint(checkpointIdx);
  }

  void _glowCheckpoint(int checkpointIdx) {
    if (_circleManager == null) return;
    if (checkpointIdx < 0 || checkpointIdx >= _checkpointPoints.length) return;

    final checkpoint = _checkpointPoints[checkpointIdx];
    // Small glow circle
    _circleManager
        ?.create(
          mapbox.CircleAnnotationOptions(
            geometry: checkpoint,
            circleColor: const Color(0xFF34A853).toARGB32(),
            circleRadius: 8,
            circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
            circleStrokeWidth: 1.5,
            circleOpacity: 1.0,
          ),
        )
        .then((annotation) {
          if (!mounted) return;
          Timer(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            _circleManager?.delete(annotation);
          });
        });
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _styleWatchdogTimer?.cancel();
    _renderRetryTimer?.cancel();
    _fitRetryTimer?.cancel();
    _renderGeneration++;
    _routeAnimController.removeListener(_onRouteAnimationTick);
    _routeAnimController.removeStatusListener(_onAnimationStatusChange);
    _routeAnimController.dispose();
    super.dispose();
  }

  void _buildPoints() {
    final checkpoints = [...widget.effectiveCheckpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    _startPoint = mapbox.Point(
      coordinates: mapbox.Position(
        checkpoints.first.longitude,
        checkpoints.first.latitude,
      ),
    );
    _endPoint = mapbox.Point(
      coordinates: mapbox.Position(
        checkpoints.last.longitude,
        checkpoints.last.latitude,
      ),
    );
    _checkpointPoints = checkpoints
        .map(
          (cp) => mapbox.Point(
            coordinates: mapbox.Position(cp.longitude, cp.latitude),
          ),
        )
        .toList();
    final route = widget.route;
    _routePoints = route == null
        ? const []
        : _orientRoutePoints(_decodePolyline(route.encodedPolyline));
    _computeCheckpointIndices();
    final center = centerFor(_visibleMapPoints);
    _currentZoom = 13.5;
    _scaleLatitude = center.coordinates[1]!.toDouble();
  }

  void _computeCheckpointIndices() {
    _checkpointIndices.clear();
    if (_routePoints.isEmpty || _checkpointPoints.isEmpty) return;

    // For each checkpoint (except start/end which are at route start/end),
    // find the closest route point index
    for (final checkpoint in _checkpointPoints) {
      double minDist = double.infinity;
      int closestIdx = 0;
      for (int i = 0; i < _routePoints.length; i++) {
        final dist = distanceMeters(checkpoint, _routePoints[i]);
        if (dist < minDist) {
          minDist = dist;
          closestIdx = i;
        }
      }
      if (closestIdx > 0 && closestIdx < _routePoints.length - 1) {
        _checkpointIndices.add(closestIdx);
      }
    }
    // Sort and deduplicate
    _checkpointIndices = _checkpointIndices.toSet().toList()..sort();
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectiveCheckpoints != widget.effectiveCheckpoints ||
        oldWidget.route != widget.route) {
      _buildPoints();
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

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _scheduleStyleWatchdog();
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
    unawaited(_renderRouteIfReady());
    unawaited(_syncScaleFromCamera());
  }

  Future<void> _onStyleLoaded() async {
    _styleWatchdogTimer?.cancel();
    _styleLoaded = true;
    _routeRendered = false;
    _initialFitComplete = false;
    _polylineManager = null;
    _circleManager = null;
    _pointManager = null;
    _renderGeneration++;
    await _ensureAnnotationManagers();
    await _renderRouteIfReady();
    final map = _mapboxMap;
    if (map != null) {
      unawaited(enableTerrain3D(map));
    }
  }

  Future<void> _onMapLoaded() async {
    _styleWatchdogTimer?.cancel();
    if (!_styleLoaded) {
      _styleLoaded = true;
      _routeRendered = false;
      _initialFitComplete = false;
    }
    await _ensureAnnotationManagers();
    await _renderRouteIfReady();
  }

  Future<bool> _ensureAnnotationManagers() async {
    final map = _mapboxMap;
    if (map == null || !_styleLoaded) {
      return false;
    }
    try {
      _polylineManager ??= await map.annotations
          .createPolylineAnnotationManager();
      _circleManager ??= await map.annotations.createCircleAnnotationManager();
      _pointManager ??= await map.annotations.createPointAnnotationManager();
      return _polylineManager != null &&
          _circleManager != null &&
          _pointManager != null;
    } catch (_) {
      _scheduleRenderRetry();
      return false;
    }
  }

  Future<void> _renderRouteIfReady() async {
    final map = _mapboxMap;
    if (map == null ||
        _routeRendered ||
        _isRendering ||
        !_styleLoaded ||
        _visibleMapPoints.length < 2) {
      return;
    }
    if (!await _ensureAnnotationManagers()) {
      return;
    }

    final generation = ++_renderGeneration;
    _isRendering = true;
    try {
      _routeAnimController.stop();
      _animatedPolyline = null;
      _lastAnimatedIndex = 0;
      await _polylineManager!.deleteAll();
      await _circleManager!.deleteAll();
      await _pointManager!.deleteAll();
      if (!mounted || generation != _renderGeneration) {
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
              lineOpacity: 0.3,
              lineWidth: _routeLineWidth + 3,
              lineJoin: mapbox.LineJoin.ROUND,
            ),
          );
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
            _lastAnimatedIndex = 2;
            _animateRoute(_animatedPolyline!);
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
        mapbox.CircleAnnotationOptions(
          geometry: _startPoint,
          circleColor: const Color(0xFF7BC90E).toARGB32(),
          circleRadius: 6.5,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
        mapbox.CircleAnnotationOptions(
          geometry: _endPoint,
          circleColor: const Color(0xFFE94B42).toARGB32(),
          circleRadius: 6.5,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
      ];
      await _circleManager!.createMulti(circleOptions);

      if (widget.pinnedPoints.isNotEmpty) {
        await _pointManager!.createMulti(
          widget.pinnedPoints
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

      if (widget.checkInPoints.isNotEmpty) {
        await _pointManager!.createMulti(
          widget.checkInPoints
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

      if (!mounted || generation != _renderGeneration) {
        return;
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

  void _scheduleStyleWatchdog() {
    _styleWatchdogTimer?.cancel();
    _styleWatchdogTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _styleLoaded) {
        return;
      }
      setState(() {
        _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
        _routeRendered = false;
        _initialFitComplete = false;
        _polylineManager = null;
        _circleManager = null;
        _pointManager = null;
        _renderGeneration++;
      });
      _scheduleStyleWatchdog();
    });
  }

  void _animateRoute(mapbox.PolylineAnnotation annotation) {
    if (!mounted) return;
    _routeAnimController.repeat();
  }

  Future<void> _fitRoute() async {
    final map = _mapboxMap;
    if (map == null || _visibleMapPoints.length < 2 || _isFitting) return;

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
      if (camera.zoom == null ||
          !camera.zoom!.isFinite ||
          camera.center == null ||
          camera.center!.coordinates[0] == null ||
          camera.center!.coordinates[1] == null) {
        throw StateError('Mapbox did not return a valid route camera.');
      }

      await map.flyTo(camera, mapbox.MapAnimationOptions(duration: 350));
      await Future.delayed(const Duration(milliseconds: 380));
      final state = await map.getCameraState();
      final centerLongitude = state.center.coordinates[0]!.toDouble();
      final centerLatitude = state.center.coordinates[1]!.toDouble();
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
      if (mounted) {
        setState(() {
          _initialFitComplete = true;
        });
      }
    } catch (_) {
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
        if (mounted) {
          setState(() {
            _initialFitComplete = true;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _initialFitComplete = false;
          });
          _fitRetryTimer?.cancel();
          _fitRetryTimer = Timer(const Duration(milliseconds: 800), () {
            if (mounted) {
              unawaited(_fitRoute());
            }
          });
        }
      }
    } finally {
      _isFitting = false;
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
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
      _initialFitComplete = false;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
      _renderGeneration++;
    });
    _scheduleStyleWatchdog();
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
    if (map == null) return;
    final state = await map.getCameraState();
    _updateScaleFromState(state);
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    final nextZoom = data.cameraState.zoom;
    final nextLatitude = data.cameraState.center.coordinates[1]!.toDouble();
    if (!mounted ||
        ((nextZoom - _currentZoom).abs() < 0.005 &&
            (nextLatitude - _scaleLatitude).abs() < 0.0005)) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  void _updateScaleFromState(mapbox.CameraState state) {
    final nextZoom = state.zoom;
    final nextLatitude = state.center.coordinates[1]!.toDouble();
    if (!mounted) return;
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  List<mapbox.Point> get _visibleMapPoints {
    if (_routePoints.length >= 2) {
      return [..._routePoints, _startPoint, _endPoint];
    }
    return _checkpointPoints.length >= 2
        ? _checkpointPoints
        : [_startPoint, _endPoint];
  }

  List<mapbox.Point> _decodePolyline(String encoded) {
    try {
      return PolylineCodec.decode(encoded)
          .where((point) => point.latitude.isFinite && point.longitude.isFinite)
          .map(
            (point) => mapbox.Point(
              coordinates: mapbox.Position(point.longitude, point.latitude),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<mapbox.Point> _orientRoutePoints(List<mapbox.Point> points) {
    if (points.length < 2) {
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
    final isPreparingMap =
        !_styleLoaded || !_routeRendered || !_initialFitComplete;
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
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleLoaded(),
            onMapLoadedListener: (_) => _onMapLoaded(),
            onCameraChangeListener: _onCameraChange,
            onMapIdleListener: (_) => _onMapIdle(),
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
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      !_styleLoaded
                          ? 'Preparing map…'
                          : !_routeRendered
                          ? 'Drawing route…'
                          : 'Focusing route…',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'This can take longer on a slow connection.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
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
