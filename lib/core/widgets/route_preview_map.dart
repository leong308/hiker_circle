import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  });

  final Trail trail;
  final HikingRouteResult? route;
  final int? highlightedCheckpointIndex;
  final List<TrailCheckpoint>? customCheckpoints;
  final bool showLayerToggle;
  final bool animateRoute;
  final Duration animationDuration;

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
  late List<TrailCheckpoint> _checkpointData;
  late mapbox.Point _startPoint;
  late mapbox.Point _endPoint;
  late double _currentZoom;
  late double _scaleLatitude;
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;
  late final AnimationController _routeAnimController;
  late final Animation<double> _routeAnimProgress;
  int _lastAnimatedIndex = 0;
  mapbox.PolylineAnnotation? _animatedPolyline;
  List<int> _checkpointIndices = [];
  Timer? _pauseTimer;
  bool _isPaused = false;

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
        _isPaused)
      return;
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
    _checkpointData = checkpoints;
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
      _animatedPolyline = null;
      _lastAnimatedIndex = 0;
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
    await map.flyTo(
      mapbox.CameraOptions(center: point, zoom: 16),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
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
    _polylineManager = await mapboxMap.annotations
        .createPolylineAnnotationManager();
    _circleManager = await mapboxMap.annotations
        .createCircleAnnotationManager();
    _pointManager = await mapboxMap.annotations.createPointAnnotationManager();
    await _renderRouteIfReady();
    await _syncScaleFromCamera();
  }

  Future<void> _onStyleLoaded() async {
    await enableTerrain3D(_mapboxMap!);
    schedulePitch(_mapboxMap!);
    _styleLoaded = true;
    _routeRendered = false;
    await _renderRouteIfReady();
  }

  Future<void> _onMapLoaded() async {
    if (!_styleLoaded) {
      _styleLoaded = true;
      _routeRendered = false;
      await _renderRouteIfReady();
    }
  }

  Future<void> _renderRouteIfReady() async {
    final map = _mapboxMap;
    if (map == null || _routeRendered || !_styleLoaded || _visibleMapPoints.length < 2) {
      return;
    }

    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    var created = false;

    if (_routePoints.length >= 2) {
      if (widget.animateRoute && _routePoints.length > 2) {
        // Ghost line: full route always visible while animation plays on top
        await _polylineManager?.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(
              coordinates: [
                for (final pt in _routePoints)
                  mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
              ],
            ),
            lineColor: const Color(0xFF4ADE80).toARGB32(),
            lineOpacity: 0.25,
            lineWidth: _routeLineWidth + 3,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
        // Foreground animated line
        _animatedPolyline = await _polylineManager?.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: []),
            lineColor: const Color(0xFF2F8E50).toARGB32(),
            lineOpacity: 0.86,
            lineWidth: _routeLineWidth,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
        if (_animatedPolyline != null) {
          _lastAnimatedIndex = 0;
          _animateRoute(_animatedPolyline!);
        }
      } else {
        // Static route
        await _polylineManager?.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(
              coordinates: [
                for (final pt in _routePoints)
                  mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
              ],
            ),
            lineColor: const Color(0xFF2F8E50).toARGB32(),
            lineOpacity: 0.86,
            lineWidth: _routeLineWidth,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }
      created = true;
    }

    final circleOptions = <mapbox.CircleAnnotationOptions>[
      for (final checkpoint
          in _checkpointPoints
              .skip(1)
              .take(math.max(0, _checkpointPoints.length - 2)))
        mapbox.CircleAnnotationOptions(
          geometry: checkpoint,
          circleColor: const Color(0xFF2F8E50).toARGB32(),
          circleOpacity: 0.55,
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

    if (circleOptions.isNotEmpty) {
      await _circleManager?.createMulti(circleOptions);
      created = true;
    }

    if (created) {
      _routeRendered = true;
      await Future.delayed(const Duration(milliseconds: 50));
      await _fitRoute();
    }
  }

  void _animateRoute(mapbox.PolylineAnnotation annotation) {
    if (!mounted) return;
    _routeAnimController.repeat();
  }

  Future<void> _fitRoute() async {
    final map = _mapboxMap;
    if (map == null || _visibleMapPoints.length < 2) return;

    final b = boundsFor(_visibleMapPoints);
    if (b.minLon > b.maxLon || b.minLat > b.maxLat) return;

    try {
      try {
        final camera = await map.cameraForCoordinateBounds(
          mapbox.CoordinateBounds(
            southwest: mapbox.Point(
              coordinates: mapbox.Position(b.minLon, b.minLat),
            ),
            northeast: mapbox.Point(
              coordinates: mapbox.Position(b.maxLon, b.maxLat),
            ),
            infiniteBounds: false,
          ),
          mapbox.MbxEdgeInsets(top: 60, left: 60, bottom: 60, right: 60),
          null,
          null,
          null,
          null,
        );
        if (camera != null &&
            camera.zoom != null &&
            camera.zoom!.isFinite &&
            camera.center != null &&
            camera.center!.coordinates[0] != null) {
          await map.flyTo(camera, mapbox.MapAnimationOptions(duration: 300));
        } else {
          throw Exception('Invalid camera from cameraForCoordinateBounds');
        }
      } catch (_) {
        final center = centerFor(_visibleMapPoints);
        await map.flyTo(
          mapbox.CameraOptions(center: center, zoom: 13.5),
          mapbox.MapAnimationOptions(duration: 300),
        );
      }
    } catch (_) {
      // Map channel may not be ready yet (e.g. 64x64 invalid-size fallback).
      // Retry once the viewport stabilises.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) unawaited(_fitRoute());
      });
    }
    await _syncScaleFromCamera();
  }

  Future<void> _zoomBy(double amount) async {
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(zoom: _currentZoom + amount),
      mapbox.MapAnimationOptions(duration: 300),
    );
    await _syncScaleFromCamera();
  }

  void _cycleStyle() {
    setState(() {
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
    });
  }

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _updateScale(data);
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
    final points = <mapbox.Point>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      latitude += (result & 1) == 1 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      longitude += (result & 1) == 1 ? ~(result >> 1) : result >> 1;

      points.add(
        mapbox.Point(
          coordinates: mapbox.Position(longitude / 100000, latitude / 100000),
        ),
      );
    }
    return points;
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
    final center = centerFor(_visibleMapPoints);
    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: ValueKey(mapStyleUrls[_styleIndex]),
            styleUri: mapStyleUrls[_styleIndex],
            gestureRecognizers: mapGestureRecognizers,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleLoaded(),
            onMapLoadedListener: (_) => _onMapLoaded(),
            onCameraChangeListener: _onCameraChange,
            onMapIdleListener: (_) => unawaited(_syncScaleFromCamera()),
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
      ],
    );
  }
}
