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
  });

  final Trail trail;
  final HikingRouteResult? route;
  final int? highlightedCheckpointIndex;
  final List<TrailCheckpoint>? customCheckpoints;
  final bool showLayerToggle;

  List<TrailCheckpoint> get effectiveCheckpoints =>
      customCheckpoints ?? trail.checkpoints;

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap> {
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
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;

  @override
  void initState() {
    super.initState();
    _buildPoints();
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
    final center = centerFor(_visibleMapPoints);
    _currentZoom = 13.5;
    _scaleLatitude = center.coordinates[1]!.toDouble();
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectiveCheckpoints != widget.effectiveCheckpoints ||
        oldWidget.route != widget.route) {
      _buildPoints();
      _routeRendered = false;
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
      mapbox.CameraOptions(
        center: point,
        zoom: 16,
      ),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    await mapboxMap.logo.updateSettings(
      mapbox.LogoSettings(enabled: false),
    );
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        rotateEnabled: false,
        pitchEnabled: false,
      ),
    );
    await mapboxMap.setBounds(
      mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
    );
    _polylineManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager = await mapboxMap.annotations.createCircleAnnotationManager();
    await _renderRouteIfReady();
    await _syncScaleFromCamera();
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    unawaited(_fitRoute());
  }

  Future<void> _onMapLoaded() async {
    if (!_styleLoaded) {
      _styleLoaded = true;
      unawaited(_fitRoute());
    }
  }

  Future<void> _renderRouteIfReady() async {
    final map = _mapboxMap;
    if (map == null || _routeRendered || _visibleMapPoints.length < 2) {
      return;
    }

    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    var created = false;

    if (_routePoints.length >= 2) {
      await _polylineManager?.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: [
            for (final pt in _routePoints)
              mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
          ]),
          lineColor: const Color(0xFF2F8E50).toARGB32(),
          lineOpacity: 0.86,
          lineWidth: _routeLineWidth,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      created = true;
    }

    final circleOptions = <mapbox.CircleAnnotationOptions>[
      for (final checkpoint in _checkpointPoints
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

  Future<void> _fitRoute() async {
    final map = _mapboxMap;
    if (map == null || _visibleMapPoints.length < 2) return;

    final b = boundsFor(_visibleMapPoints);
    if (b.minLon > b.maxLon || b.minLat > b.maxLat) return;

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

      points.add(mapbox.Point(
        coordinates: mapbox.Position(longitude / 100000, latitude / 100000),
      ));
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
            child: MapScaleBar(
              zoom: _currentZoom,
              latitude: _scaleLatitude,
            ),
          ),
        ),
      ],
    );
  }
}
