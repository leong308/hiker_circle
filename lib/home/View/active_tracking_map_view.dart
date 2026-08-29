import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_endpoint_marker.dart';
import '../../trail/Model/trail_models.dart';
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

bool _isValidCoordinate(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

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
  static const double _navigationZoom = 17;
  static const Duration _navigationRefocusDelay = Duration(seconds: 30);

  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  Future<bool>? _annotationManagersFuture;
  List<Offset?> _weatherScreenPositions = const [];
  Map<String, Offset?> _teamScreenPositions = const {};
  var _weatherProjectionScheduled = false;
  var _teamProjectionScheduled = false;
  var _weatherProjectionGeneration = 0;
  var _teamProjectionGeneration = 0;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;
  var _isRendering = false;
  var _renderPending = false;
  var _mapGeneration = 0;
  var _renderGeneration = 0;
  var _hasReferenceEndpoints = false;
  var _showsMap = false;
  Timer? _navigationRefocusTimer;
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
    _showsMap = _visiblePoints.isNotEmpty;
    _initialCamera = _computeInitialCamera();
    _currentZoom = _initialCamera?.zoom ?? 13.5;
    final initialCenter = _initialCamera?.center;
    _scaleLatitude = initialCenter == null
        ? 0
        : mapPointCoordinatesOrNull(initialCenter)?.latitude ?? 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigationRefocusTimer?.cancel();
    _mapGeneration++;
    _renderGeneration++;
    _mapboxMap = null;
    _polylineManager = null;
    _circleManager = null;
    _pointManager = null;
    _annotationManagersFuture = null;
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
    final focusPoint =
        _latestPoint ??
        (_hasReferenceEndpoints ? _startPoint : _validTrailCenterPoint());
    if (map == null || focusPoint == null) return;
    _navigationRefocusTimer?.cancel();
    _navigationRefocusTimer = null;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          center: focusPoint,
          padding: mapbox.MbxEdgeInsets(
            top: 150,
            left: 0,
            bottom: 30,
            right: 0,
          ),
          zoom: _navigationZoom,
          bearing: _navigationBearing(),
        ),
        mapbox.MapAnimationOptions(duration: 500),
      );
      await _syncScaleFromCamera();
    } catch (_) {}
  }

  mapbox.CameraOptions? _computeInitialCamera() {
    final focusPoint =
        _latestPoint ??
        (_hasReferenceEndpoints ? _startPoint : _validTrailCenterPoint());
    if (focusPoint == null) return null;
    return mapbox.CameraOptions(
      center: focusPoint,
      padding: mapbox.MbxEdgeInsets(top: 150, left: 0, bottom: 30, right: 0),
      zoom: _navigationZoom,
      bearing: _navigationBearing(),
    );
  }

  double? _navigationBearing() {
    final latest = _latestPoint;
    final recorded = _recordedRoutePoints;
    if (latest != null && recorded.length >= 2) {
      for (var index = recorded.length - 2; index >= 0; index--) {
        if (distanceMeters(recorded[index], latest) >= 5) {
          return _bearingBetween(recorded[index], latest);
        }
      }
    }

    final planned = _routePoints.length >= 2 ? _routePoints : _checkpointPoints;
    if (planned.length < 2) return null;
    if (latest == null) {
      return _bearingBetween(planned.first, planned[1]);
    }

    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < planned.length; index++) {
      final distance = distanceMeters(latest, planned[index]);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    for (var index = nearestIndex + 1; index < planned.length; index++) {
      if (distanceMeters(latest, planned[index]) >= 15) {
        return _bearingBetween(latest, planned[index]);
      }
    }
    if (nearestIndex > 0) {
      return _bearingBetween(planned[nearestIndex - 1], planned[nearestIndex]);
    }
    return _bearingBetween(planned.first, planned[1]);
  }

  double? _bearingBetween(mapbox.Point from, mapbox.Point to) {
    final start = mapPointCoordinatesOrNull(from);
    final end = mapPointCoordinatesOrNull(to);
    if (start == null || end == null || distanceMeters(from, to) < 2) {
      return null;
    }
    final startLatitude = start.latitude * math.pi / 180;
    final endLatitude = end.latitude * math.pi / 180;
    final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
    final y = math.sin(longitudeDelta) * math.cos(endLatitude);
    final x =
        math.cos(startLatitude) * math.sin(endLatitude) -
        math.sin(startLatitude) *
            math.cos(endLatitude) *
            math.cos(longitudeDelta);
    if (x.abs() < 1e-12 && y.abs() < 1e-12) return null;
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

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
    _hasReferenceEndpoints = fallbackPoint != null;
    _routePoints = const [];
  }

  mapbox.Point _pointForCheckpoint(TrailCheckpoint checkpoint) => mapbox.Point(
    coordinates: mapbox.Position(checkpoint.longitude, checkpoint.latitude),
  );

  mapbox.Point? _validTrailCenterPoint() {
    final latitude = widget.activeHike.trail.latitude;
    final longitude = widget.activeHike.trail.longitude;
    if (!_isValidCoordinate(latitude, longitude)) {
      return null;
    }
    return mapbox.Point(coordinates: mapbox.Position(longitude, latitude));
  }

  static final _zeroPoint = mapbox.Point(coordinates: mapbox.Position(0, 0));

  List<mapbox.Point> get _recordedRoutePoints {
    return widget.activeHike.routePoints
        .where((point) => point.hasValidPosition)
        .map(
          (point) => mapbox.Point(
            coordinates: mapbox.Position(point.longitude, point.latitude),
          ),
        )
        .toList();
  }

  List<mapbox.Point> get _checkpointPoints {
    final checkpoints =
        widget.activeHike.draft.effectiveCheckpoints
            .where((checkpoint) => checkpoint.hasValidCoordinate)
            .toList()
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
        .where((pin) => pin.coordinate.hasValidPosition)
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
    final now = DateTime.now().toUtc();
    return _effectiveParticipants
        .where((participant) => participant.hasFreshLocationAt(now))
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
    return _locatedTeamParticipants
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
    if (latest == null || !latest.hasValidPosition) {
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
        final decodedLatitude = latitude / 100000;
        final decodedLongitude = longitude / 100000;
        if (!_isValidCoordinate(decodedLatitude, decodedLongitude)) {
          return const [];
        }
        points.add(
          mapbox.Point(
            coordinates: mapbox.Position(decodedLongitude, decodedLatitude),
          ),
        );
      }
      return points;
    } catch (_) {
      return const [];
    }
  }

  List<mapbox.Point> _orientRoutePoints(List<mapbox.Point> points) {
    if (points.length < 2 || !_hasReferenceEndpoints) {
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
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
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
      await mapboxMap.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: widget.interactive,
          pinchToZoomEnabled: widget.interactive,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      if (!_isCurrentMap(mapboxMap, generation)) return;
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (error) {
      debugPrint('Unable to configure active hike map: $error');
    }
    if (!_isCurrentMap(mapboxMap, generation)) return;
    if (_styleLoaded) {
      await _ensureAnnotationManagers(mapboxMap, generation);
      await _renderRouteIfReady();
    }
    unawaited(_syncScaleFromCamera());
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  Future<void> _onStyleLoaded(int generation) async {
    final map = _mapboxMap;
    if (map == null || !_isCurrentMap(map, generation)) return;
    if (!_styleLoaded) {
      _styleLoaded = true;
      _routeRendered = false;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
      _annotationManagersFuture = null;
      _renderGeneration++;
    }
    await enableTerrain3D(map);
    if (!_isCurrentMap(map, generation)) return;
    schedulePitch(map);
    if (!await _ensureAnnotationManagers(map, generation)) return;
    await _renderRouteIfReady();
    _scheduleWeatherProjection();
    _scheduleTeamProjection();
  }

  Future<void> _onMapLoaded(int generation) async {
    final map = _mapboxMap;
    if (map == null || !_isCurrentMap(map, generation) || _styleLoaded) return;
    await _onStyleLoaded(generation);
  }

  Future<bool> _ensureAnnotationManagers(mapbox.MapboxMap map, int generation) {
    if (!_styleLoaded || !_isCurrentMap(map, generation)) {
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

  Future<void> _renderRouteIfReady() async {
    if (_isRendering) {
      _renderPending = true;
      return;
    }
    final map = _mapboxMap;
    final mapGeneration = _mapGeneration;
    if (map == null ||
        !_styleLoaded ||
        _routeRendered ||
        _visiblePoints.isEmpty) {
      return;
    }
    if (!await _ensureAnnotationManagers(map, mapGeneration)) return;

    _isRendering = true;
    final renderGeneration = _renderGeneration;
    try {
      await _renderRouteNow(map, mapGeneration, renderGeneration);
    } catch (error) {
      if (_isCurrentMap(map, mapGeneration) &&
          renderGeneration == _renderGeneration) {
        _routeRendered = false;
        debugPrint('Unable to draw active hike route: $error');
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
      await pointManager.createMulti([
        routeEndpointAnnotation(
          geometry: _startPoint,
          label: 'Start',
          pinImage: endpointPin,
        ),
        routeEndpointAnnotation(
          geometry: _endPoint,
          label: 'End',
          pinImage: endpointPin,
        ),
      ]);
      created = true;
    }

    if (!_isCurrentMap(map, mapGeneration) ||
        renderGeneration != _renderGeneration) {
      return;
    }
    if (created) {
      _routeRendered = true;
    }

    if (_navigationRefocusTimer == null) {
      await _refocusOnSelf();
    }
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
    final generation = _mapGeneration;
    final projectionGeneration = _weatherProjectionGeneration;
    final samples = widget.weatherSamples;
    final validIndices = <int>[
      for (var index = 0; index < samples.length; index++)
        if (samples[index].coordinate.hasValidPosition) index,
    ];
    if (map == null || !_styleLoaded || validIndices.isEmpty) {
      if (mounted && _weatherScreenPositions.isNotEmpty) {
        setState(() {
          _weatherScreenPositions = const [];
        });
      }
      return;
    }

    try {
      final pixels = await map.pixelsForCoordinates([
        for (final index in validIndices)
          mapbox.Point(
            coordinates: mapbox.Position(
              samples[index].coordinate.longitude,
              samples[index].coordinate.latitude,
            ),
          ),
      ]);
      if (!_isCurrentMap(map, generation) ||
          projectionGeneration != _weatherProjectionGeneration) {
        return;
      }
      setState(() {
        final positions = List<Offset?>.filled(samples.length, null);
        final projectedCount = math.min(validIndices.length, pixels.length);
        for (var index = 0; index < projectedCount; index++) {
          final pixel = pixels[index];
          positions[validIndices[index]] =
              pixel == null || !pixel.x.isFinite || !pixel.y.isFinite
              ? null
              : Offset(pixel.x, pixel.y);
        }
        _weatherScreenPositions = positions;
      });
    } catch (error) {
      debugPrint('Unable to project hike weather markers: $error');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && generation == _mapGeneration) {
          _scheduleWeatherProjection();
        }
      });
    }
  }

  Future<void> _projectTeamMarkers() async {
    final map = _mapboxMap;
    final generation = _mapGeneration;
    final projectionGeneration = _teamProjectionGeneration;
    final participants = _locatedTeamParticipants;
    if (map == null || !_styleLoaded || participants.isEmpty) {
      if (mounted && _teamScreenPositions.isNotEmpty) {
        setState(() {
          _teamScreenPositions = const {};
        });
      }
      return;
    }

    try {
      final participantKeys = participants
          .map(_participantProjectionKey)
          .toList();
      final pixels = await map.pixelsForCoordinates([
        for (final participant in participants)
          mapbox.Point(
            coordinates: mapbox.Position(
              participant.latestLocation!.longitude,
              participant.latestLocation!.latitude,
            ),
          ),
      ]);
      if (!_isCurrentMap(map, generation) ||
          projectionGeneration != _teamProjectionGeneration) {
        return;
      }
      setState(() {
        final projectedCount = math.min(participantKeys.length, pixels.length);
        _teamScreenPositions = {
          for (var index = 0; index < projectedCount; index++)
            participantKeys[index]: pixels[index] == null
                ? null
                : pixels[index]!.x.isFinite && pixels[index]!.y.isFinite
                ? Offset(pixels[index]!.x, pixels[index]!.y)
                : null,
        };
      });
    } catch (error) {
      debugPrint('Unable to project team markers: $error');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && generation == _mapGeneration) {
          _scheduleTeamProjection();
        }
      });
    }
  }

  String _participantProjectionKey(TeamHikeParticipant participant) {
    final phone = participant.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isNotEmpty) return 'phone:$phone';
    final handle = participant.buddy.handle.trim().toLowerCase();
    if (handle.isNotEmpty) return 'handle:$handle';
    return 'name:${participant.buddy.name.trim().toLowerCase()}';
  }

  Future<void> _fitRoute() async {
    _pauseNavigationFollow();
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
        final cameraCenter = camera.center == null
            ? null
            : mapPointCoordinatesOrNull(camera.center!);
        if (camera.zoom != null &&
            camera.zoom!.isFinite &&
            cameraCenter != null) {
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
      _mapGeneration++;
      _renderGeneration++;
      _weatherProjectionGeneration++;
      _teamProjectionGeneration++;
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
      _mapboxMap = null;
      _polylineManager = null;
      _circleManager = null;
      _pointManager = null;
      _annotationManagersFuture = null;
      _weatherScreenPositions = const [];
      _teamScreenPositions = const {};
    });
    widget.onStyleChanged?.call(_styleIndex);
  }

  Future<void> _zoomBy(double amount) async {
    if (_mapboxMap == null) return;
    _pauseNavigationFollow();
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
      });
      _scheduleWeatherProjection();
      _scheduleTeamProjection();
    } catch (_) {
      // Map replacement can invalidate an in-flight camera request.
    }
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    final nextZoom = data.cameraState.zoom;
    final coordinates = mapPointCoordinatesOrNull(data.cameraState.center);
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
        mapbox.MapWidget(
          key: ValueKey(mapStyleUrls[_styleIndex]),
          styleUri: mapStyleUrls[_styleIndex],
          // ignore: deprecated_member_use
          cameraOptions: _initialCamera,
          gestureRecognizers: mapGestureRecognizers,
          onMapCreated: (map) => _onMapCreated(map, mapGeneration),
          onStyleLoadedListener: (_) => _onStyleLoaded(mapGeneration),
          onMapLoadedListener: (_) => _onMapLoaded(mapGeneration),
          onScrollListener: (_) => _pauseNavigationFollow(),
          onZoomListener: (_) => _pauseNavigationFollow(),
          onCameraChangeListener: (data) {
            if (mapGeneration == _mapGeneration) {
              _onCameraChange(data);
            }
          },
          onMapIdleListener: (_) {
            if (mapGeneration == _mapGeneration) {
              unawaited(_syncScaleFromCamera());
              _scheduleWeatherProjection();
              _scheduleTeamProjection();
            }
          },
        ),
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
    final now = DateTime.now().toUtc();
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
                  hasLocation: participants[i].hasFreshLocationAt(now),
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
          if (isEnded) ...[
            const SizedBox(width: 4),
            Text(
              'Ended',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF6E6E73),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ] else if (!hasLocation) ...[
            const SizedBox(width: 4),
            Text(
              'Away',
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
