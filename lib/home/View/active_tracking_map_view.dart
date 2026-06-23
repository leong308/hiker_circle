import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../Data/active_hike_weather_service.dart';
import '../Model/hike_session_models.dart';

final _teamColors = <Color>[
  const Color(0xFF7C3AED),
  const Color(0xFF0EA5E9),
  const Color(0xFFEC4899),
  const Color(0xFF14B8A6),
  const Color(0xFFF97316),
  const Color(0xFF8B5CF6),
  const Color(0xFF06B6D4),
  const Color(0xFFD946EF),
  const Color(0xFF84CC16),
  const Color(0xFFF43F5E),
];

const _selfTeamColor = Color(0xFF34A853);

Color _fallbackTeamColor(int index) => _teamColors[index % _teamColors.length];

bool _samePhoneNumber(String first, String second) {
  final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
  final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
  return firstKey.isNotEmpty && firstKey == secondKey;
}

Color _displayColorForParticipant(
  TeamHikeParticipant participant,
  int index,
  String currentPhoneNumber,
) {
  if (_samePhoneNumber(participant.phoneNumber, currentPhoneNumber)) {
    return _selfTeamColor;
  }
  final storedColor = Color(participant.buddy.avatarColorValue);
  if (storedColor == _selfTeamColor) {
    return _fallbackTeamColor(index);
  }
  return storedColor;
}

class ActiveTrackingMapView extends StatefulWidget {
  const ActiveTrackingMapView({
    super.key,
    required this.activeHike,
    this.teamHikeSession,
    this.weatherSamples = const [],
    this.interactive = true,
    this.showLegend = false,
    this.currentPhoneNumber = '',
    this.onStyleChanged,
  });

  final ActiveHikeSession activeHike;
  final TeamHikeSession? teamHikeSession;
  final List<ActiveHikeWeatherSample> weatherSamples;
  final bool interactive;
  final bool showLegend;
  final String currentPhoneNumber;
  final ValueChanged<int>? onStyleChanged;

  @override
  State<ActiveTrackingMapView> createState() => _ActiveTrackingMapViewState();
}

class _ActiveTrackingMapViewState extends State<ActiveTrackingMapView>
    with WidgetsBindingObserver {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  List<Offset?> _weatherScreenPositions = const [];
  List<Offset?> _teamScreenPositions = const [];
  var _weatherProjectionScheduled = false;
  var _teamProjectionScheduled = false;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;
  var _isRendering = false;
  var _renderPending = false;
  late double _currentZoom;
  late double _scaleLatitude;
  mapbox.CameraOptions? _initialCamera;

  List<mapbox.Point> _routePoints = const [];
  late mapbox.Point _startPoint;
  late mapbox.Point _endPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _buildPoints();
    _initialCamera = _computeInitialCamera();
    _currentZoom = _initialCamera?.zoom ?? 13.5;
    _scaleLatitude = _initialCamera?.center?.coordinates[1]?.toDouble() ?? 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refocusOnSelf());
    }
  }

  Future<void> _refocusOnSelf() async {
    final map = _mapboxMap;
    final location = widget.activeHike.latestLocation;
    if (map == null || location == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(location.longitude, location.latitude),
          ),
          zoom: 15,
        ),
        mapbox.MapAnimationOptions(duration: 500),
      );
      await _syncScaleFromCamera();
    } catch (_) {}
  }

  mapbox.CameraOptions? _computeInitialCamera() {
    final latest = widget.activeHike.latestLocation;
    if (latest != null) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(latest.longitude, latest.latitude),
        ),
        zoom: 15,
      );
    }
    return mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(
          _startPoint.coordinates[0]!,
          _startPoint.coordinates[1]!,
        ),
      ),
      zoom: 13.5,
    );
  }

  void _buildPoints() {
    final checkpoints = [...widget.activeHike.trail.checkpoints]
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
    final encoded = widget.activeHike.trail.routeEncodedPolyline;
    _routePoints = encoded == null || encoded.isEmpty
        ? const []
        : _orientRoutePoints(_decodePolyline(encoded));
  }

  List<mapbox.Point> get _recordedRoutePoints {
    return widget.activeHike.routePoints
        .map(
          (point) => mapbox.Point(
            coordinates: mapbox.Position(point.longitude, point.latitude),
          ),
        )
        .toList();
  }

  List<mapbox.Point> get _checkpointPoints {
    final checkpoints = [...widget.activeHike.trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    return checkpoints
        .map(
          (checkpoint) => mapbox.Point(
            coordinates: mapbox.Position(
              checkpoint.longitude,
              checkpoint.latitude,
            ),
          ),
        )
        .toList();
  }

  List<mapbox.Point> get _manualPinPoints {
    return widget.activeHike.manualPinLocations
        .map(
          (pin) => mapbox.Point(
            coordinates: mapbox.Position(
              pin.coordinate.longitude,
              pin.coordinate.latitude,
            ),
          ),
        )
        .toList();
  }

  List<TeamHikeParticipant> get _effectiveParticipants {
    if (widget.activeHike.draft.hikeType != HikeType.team) {
      return const [];
    }

    final realParticipants =
        (widget.teamHikeSession ?? widget.activeHike.teamHikeSession)
            ?.participants ??
        const <TeamHikeParticipant>[];
    return realParticipants;
  }

  List<TeamHikeParticipant> get _locatedTeamParticipants {
    return _effectiveParticipants
        .where((participant) => participant.latestLocation != null)
        .toList();
  }

  Color _colorForParticipant(TeamHikeParticipant participant, int index) {
    return _displayColorForParticipant(
      participant,
      index,
      widget.currentPhoneNumber,
    );
  }

  List<mapbox.Point> get _teamMatePoints {
    return _effectiveParticipants
        .where((p) => p.latestLocation != null)
        .map(
          (p) => mapbox.Point(
            coordinates: mapbox.Position(
              p.latestLocation!.longitude,
              p.latestLocation!.latitude,
            ),
          ),
        )
        .toList();
  }

  mapbox.Point? get _latestPoint {
    final latest = widget.activeHike.latestLocation;
    if (latest == null) {
      return null;
    }
    return mapbox.Point(
      coordinates: mapbox.Position(latest.longitude, latest.latitude),
    );
  }

  List<mapbox.Point> get _visiblePoints {
    final points = <mapbox.Point>[
      ..._recordedRoutePoints,
      ..._manualPinPoints,
      ..._teamMatePoints,
      if (_latestPoint != null) _latestPoint!,
      ..._checkpointPoints,
    ];
    if (_routePoints.length >= 2) {
      points.addAll(_routePoints);
    }
    return points;
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
  void didUpdateWidget(covariant ActiveTrackingMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeHike != widget.activeHike) {
      _buildPoints();
      _routeRendered = false;
      unawaited(_renderRouteIfReady());
      _scheduleTeamProjection();
    }
    if (!identical(oldWidget.weatherSamples, widget.weatherSamples)) {
      _scheduleWeatherProjection();
    }
    if (oldWidget.teamHikeSession != widget.teamHikeSession ||
        oldWidget.currentPhoneNumber != widget.currentPhoneNumber) {
      _scheduleTeamProjection();
    }
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: widget.interactive,
        pinchToZoomEnabled: widget.interactive,
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
    await _renderRouteIfReady();
    await _syncScaleFromCamera();
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  Future<void> _onStyleLoaded() async {
    await enableTerrain3D(_mapboxMap!);
    schedulePitch(_mapboxMap!);
    _styleLoaded = true;
    _routeRendered = false;
    await _renderRouteIfReady();
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  Future<void> _renderRouteIfReady() async {
    if (_isRendering) {
      _renderPending = true;
      return;
    }
    final map = _mapboxMap;
    if (map == null ||
        !_styleLoaded ||
        _routeRendered ||
        _visiblePoints.isEmpty) {
      return;
    }

    _isRendering = true;
    try {
      await _renderRouteNow();
    } finally {
      _isRendering = false;
      if (_renderPending && mounted) {
        _renderPending = false;
        _routeRendered = false;
        unawaited(_renderRouteIfReady());
      }
    }
  }

  Future<void> _renderRouteNow() async {
    final map = _mapboxMap;
    if (map == null ||
        !_styleLoaded ||
        _routeRendered ||
        _visiblePoints.isEmpty) {
      return;
    }

    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    var created = false;

    final recordedRoute = _recordedRoutePoints;
    final hasTrailRoute = _routePoints.length >= 2;
    final hasCheckpoints = _checkpointPoints.length >= 2;

    // Draw the planned trail route (decoded polyline) as background reference,
    // matching the style used by RoutePreviewMap on the trail page.
    if (hasTrailRoute) {
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
          lineWidth: 3,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      created = true;
    }

    // Draw the recorded GPS route (thicker, brighter) on top when available.
    if (recordedRoute.length >= 2) {
      await _polylineManager?.create(
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
      await _polylineManager?.create(
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
      for (final point in _manualPinPoints)
        mapbox.CircleAnnotationOptions(
          geometry: point,
          circleColor: const Color(0xFFE11D48).toARGB32(),
          circleRadius: 6,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
      if (_latestPoint != null)
        mapbox.CircleAnnotationOptions(
          geometry: _latestPoint!,
          circleColor: const Color(0xFF0A84FF).toARGB32(),
          circleRadius: 7,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
      if (recordedRoute.isNotEmpty)
        mapbox.CircleAnnotationOptions(
          geometry: recordedRoute.first,
          circleColor: const Color(0xFF7BC90E).toARGB32(),
          circleRadius: 6,
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
      if (hasCheckpoints)
        mapbox.CircleAnnotationOptions(
          geometry: _checkpointPoints.first,
          circleColor: const Color(0xFF7BC90E).toARGB32(),
          circleRadius: 6.5,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
      if (hasCheckpoints)
        mapbox.CircleAnnotationOptions(
          geometry: _checkpointPoints.last,
          circleColor: const Color(0xFFE94B42).toARGB32(),
          circleRadius: 6.5,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2,
        ),
    ];

    if (circleAnnotations.isNotEmpty) {
      await _circleManager?.createMulti(circleAnnotations);
      created = true;
    }

    if (created) {
      _routeRendered = true;
    }

    await _fitRoute();
  }

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

  Future<void> _projectWeatherMarkers() async {
    final map = _mapboxMap;
    if (map == null || !_styleLoaded || widget.weatherSamples.isEmpty) {
      if (mounted && _weatherScreenPositions.isNotEmpty) {
        setState(() {
          _weatherScreenPositions = const [];
        });
      }
      return;
    }

    try {
      final pixels = await map.pixelsForCoordinates([
        for (final sample in widget.weatherSamples)
          mapbox.Point(
            coordinates: mapbox.Position(
              sample.coordinate.longitude,
              sample.coordinate.latitude,
            ),
          ),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherScreenPositions = pixels
            .map((pixel) => pixel == null ? null : Offset(pixel.x, pixel.y))
            .toList();
      });
    } catch (error) {
      debugPrint('Unable to project hike weather markers: $error');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _scheduleWeatherProjection();
        }
      });
    }
  }

  Future<void> _projectTeamMarkers() async {
    final map = _mapboxMap;
    final participants = _locatedTeamParticipants;
    if (map == null || !_styleLoaded || participants.isEmpty) {
      if (mounted && _teamScreenPositions.isNotEmpty) {
        setState(() {
          _teamScreenPositions = const [];
        });
      }
      return;
    }

    try {
      final pixels = await map.pixelsForCoordinates([
        for (final participant in participants)
          mapbox.Point(
            coordinates: mapbox.Position(
              participant.latestLocation!.longitude,
              participant.latestLocation!.latitude,
            ),
          ),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _teamScreenPositions = pixels
            .map((pixel) => pixel == null ? null : Offset(pixel.x, pixel.y))
            .toList();
      });
    } catch (error) {
      debugPrint('Unable to project team markers: $error');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _scheduleTeamProjection();
        }
      });
    }
  }

  Future<void> _fitRoute() async {
    final map = _mapboxMap;
    final points = _visiblePoints;
    if (map == null || points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      try {
        await map.flyTo(
          mapbox.CameraOptions(center: points.first, zoom: 15),
          mapbox.MapAnimationOptions(duration: 300),
        );
      } catch (_) {
        return;
      }
      await _syncScaleFromCamera();
      return;
    }

    try {
      try {
        final b = boundsFor(points);
        if (b.minLon > b.maxLon || b.minLat > b.maxLat) {
          final center = centerFor(points);
          await map.flyTo(
            mapbox.CameraOptions(center: center, zoom: _currentZoom),
            mapbox.MapAnimationOptions(duration: 300),
          );
          await _syncScaleFromCamera();
          return;
        }

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
        if (camera.zoom != null &&
            camera.zoom!.isFinite &&
            camera.center != null &&
            camera.center!.coordinates[0] != null) {
          await map.flyTo(camera, mapbox.MapAnimationOptions(duration: 300));
        } else {
          throw Exception('Invalid camera from cameraForCoordinateBounds');
        }
      } catch (_) {
        final center = centerFor(points);
        await map.flyTo(
          mapbox.CameraOptions(center: center, zoom: _currentZoom),
          mapbox.MapAnimationOptions(duration: 300),
        );
      }
    } catch (_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) unawaited(_fitRoute());
      });
    }
    await _syncScaleFromCamera();
  }

  void _cycleStyle() {
    setState(() {
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
    });
    widget.onStyleChanged?.call(_styleIndex);
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

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _updateScale(data);
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    if (map == null) return;
    final state = await map.getCameraState();
    final nextZoom = state.zoom;
    final nextLatitude = state.center.coordinates[1]!.toDouble();
    if (!mounted) return;
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
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

  @override
  Widget build(BuildContext context) {
    final visiblePoints = _visiblePoints;
    if (visiblePoints.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFEAF7EE),
        child: Center(child: Text('Waiting for trail coordinates')),
      );
    }
    final locatedParticipants = _locatedTeamParticipants;

    return Stack(
      fit: StackFit.expand,
      children: [
        mapbox.MapWidget(
          key: ValueKey(mapStyleUrls[_styleIndex]),
          styleUri: mapStyleUrls[_styleIndex],
          cameraOptions: _initialCamera,
          gestureRecognizers: mapGestureRecognizers,
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: (_) => _onStyleLoaded(),
          onCameraChangeListener: _onCameraChange,
          onMapIdleListener: (_) {
            unawaited(_syncScaleFromCamera());
            _scheduleWeatherProjection();
            _scheduleTeamProjection();
          },
        ),
        for (
          var index = 0;
          index < locatedParticipants.length &&
              index < _teamScreenPositions.length;
          index++
        )
          if (_teamScreenPositions[index] != null)
            Positioned(
              left: _teamScreenPositions[index]!.dx - 24,
              top: _teamScreenPositions[index]!.dy - 50,
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
        if (widget.interactive)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MapZoomControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
                onReset: _fitRoute,
                onLayer: _cycleStyle,
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
        if (widget.showLegend)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _ActiveTrackingLegend(activeHike: widget.activeHike),
          ),
        if (widget.interactive && _effectiveParticipants.isNotEmpty)
          Positioned(
            right: 10,
            top: 56,
            child: _TeamParticipantPanel(
              participants: _effectiveParticipants,
              currentPhoneNumber: widget.currentPhoneNumber,
            ),
          ),
      ],
    );
  }

  Offset _weatherMarkerVisualOffset(int index) {
    final sample = widget.weatherSamples[index];
    final coincidentCount = widget.weatherSamples
        .take(index)
        .where(
          (previous) => previous.coordinate.distanceTo(sample.coordinate) < 12,
        )
        .length;
    final direction = index.isEven ? -1.0 : 1.0;
    final separation = coincidentCount * 14.0;
    return Offset(direction * (18 + separation), -54);
  }
}

class _ActiveTrackingLegend extends StatelessWidget {
  const _ActiveTrackingLegend({required this.activeHike});

  final ActiveHikeSession activeHike;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          children: const [
            _LegendDot(color: Color(0xFF34A853), label: 'Recorded trail'),
            _LegendDot(color: Color(0xFFE11D48), label: 'Pinned location'),
            _LegendDot(color: Color(0xFF0A84FF), label: 'Latest GPS'),
            _LegendDot(color: Color(0xFF34A853), label: 'You'),
            _LegendDot(color: Color(0xFF7C3AED), label: 'Teammate border'),
          ],
        ),
      ),
    );
  }
}

class _ProjectedTeamMarker extends StatelessWidget {
  const _ProjectedTeamMarker({
    required this.participant,
    required this.color,
    required this.isSelf,
  });

  final TeamHikeParticipant participant;
  final Color color;
  final bool isSelf;

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
                    style: const TextStyle(
                      color: Colors.white,
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
                      style: const TextStyle(
                        color: Colors.white,
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

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

class _ProjectedWeatherMarker extends StatelessWidget {
  const _ProjectedWeatherMarker({
    required this.sample,
    required this.markerOffset,
  });

  final ActiveHikeWeatherSample sample;
  final Offset markerOffset;

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

class _WeatherMarkerConnectorPainter extends CustomPainter {
  const _WeatherMarkerConnectorPainter({required this.markerOffset});

  final Offset markerOffset;

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

  @override
  bool shouldRepaint(covariant _WeatherMarkerConnectorPainter oldDelegate) {
    return oldDelegate.markerOffset != markerOffset;
  }
}

class _TeamParticipantPanel extends StatelessWidget {
  const _TeamParticipantPanel({
    required this.participants,
    required this.currentPhoneNumber,
  });

  final List<TeamHikeParticipant> participants;
  final String currentPhoneNumber;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: 152,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text(
                  'Team',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6E6E73),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              for (var i = 0; i < participants.length; i++)
                _ParticipantRow(
                  color: _displayColorForParticipant(
                    participants[i],
                    i,
                    currentPhoneNumber,
                  ),
                  name: participants[i].buddy.shortName,
                  photoURL: participants[i].buddy.photoURL,
                  isLeader: participants[i].isLeader,
                  hasLocation: participants[i].latestLocation != null,
                  status: participants[i].status,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.color,
    required this.name,
    required this.photoURL,
    required this.isLeader,
    required this.hasLocation,
    required this.status,
  });

  final Color color;
  final String name;
  final String photoURL;
  final bool isLeader;
  final bool hasLocation;
  final TeamHikeParticipantStatus status;

  @override
  Widget build(BuildContext context) {
    final isEnded = status == TeamHikeParticipantStatus.ended;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isEnded ? const Color(0xFF6E6E73) : color,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: photoURL.trim().isEmpty
                ? Text(
                    name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Image.network(
                    photoURL.trim(),
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Text(
                      name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: isEnded ? const Color(0xFF6E6E73) : null,
              decoration: isEnded ? TextDecoration.lineThrough : null,
            ),
          ),
          if (isLeader && !isEnded) ...[
            const SizedBox(width: 4),
            Icon(Icons.star_rounded, size: 14, color: color),
          ],
          if (!hasLocation && !isEnded) ...[
            const SizedBox(width: 4),
            Text(
              'away',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF6E6E73),
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
