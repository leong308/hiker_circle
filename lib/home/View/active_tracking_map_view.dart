import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../Model/hike_session_models.dart';

class ActiveTrackingMapView extends StatefulWidget {
  const ActiveTrackingMapView({
    super.key,
    required this.activeHike,
    this.teamHikeSession,
    this.interactive = true,
    this.showLegend = false,
  });

  final ActiveHikeSession activeHike;
  final TeamHikeSession? teamHikeSession;
  final bool interactive;
  final bool showLegend;

  @override
  State<ActiveTrackingMapView> createState() => _ActiveTrackingMapViewState();
}

class _ActiveTrackingMapViewState extends State<ActiveTrackingMapView> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;
  late double _currentZoom;
  late double _scaleLatitude;

  @override
  void initState() {
    super.initState();
    final pts = _visiblePoints;
    final center = pts.isEmpty
        ? mapbox.Point(coordinates: mapbox.Position(0, 0))
        : centerFor(pts);
    _currentZoom = pts.length == 1 ? 15 : 13.5;
    _scaleLatitude = center.coordinates[1]!.toDouble();
  }

  List<mapbox.Point> get _recordedRoutePoints {
    return widget.activeHike.routePoints
        .map((point) => mapbox.Point(
              coordinates: mapbox.Position(point.longitude, point.latitude),
            ))
        .toList();
  }

  List<mapbox.Point> get _checkpointPoints {
    final checkpoints = [...widget.activeHike.trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    return checkpoints
        .map(
          (checkpoint) => mapbox.Point(
            coordinates: mapbox.Position(checkpoint.longitude, checkpoint.latitude),
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

  List<mapbox.Point> get _teamMatePoints {
    final teamSession =
        widget.teamHikeSession ?? widget.activeHike.teamHikeSession;
    if (teamSession == null) {
      return const [];
    }
    return teamSession.participants
        .where((participant) => participant.latestLocation != null)
        .map(
          (participant) => mapbox.Point(
            coordinates: mapbox.Position(
              participant.latestLocation!.longitude,
              participant.latestLocation!.latitude,
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
    return mapbox.Point(coordinates: mapbox.Position(latest.longitude, latest.latitude));
  }

  List<mapbox.Point> get _visiblePoints {
    return [
      ..._recordedRoutePoints,
      ..._manualPinPoints,
      ..._teamMatePoints,
      if (_latestPoint != null) _latestPoint!,
      if (_recordedRoutePoints.isEmpty) ..._checkpointPoints,
    ];
  }

  @override
  void didUpdateWidget(covariant ActiveTrackingMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeHike != widget.activeHike) {
      _routeRendered = false;
      unawaited(_renderRouteIfReady());
    }
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
        scrollEnabled: widget.interactive,
        pinchToZoomEnabled: widget.interactive,
        rotateEnabled: false,
        pitchEnabled: false,
      ),
    );
    await mapboxMap.setBounds(
      mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
    );
    _polylineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    await _renderRouteIfReady();
    await _syncScaleFromCamera();
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    _routeRendered = false;
    await _renderRouteIfReady();
  }

  Future<void> _renderRouteIfReady() async {
    final map = _mapboxMap;
    if (map == null || !_styleLoaded || _routeRendered || _visiblePoints.isEmpty) {
      return;
    }

    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    var created = false;

    final recordedRoute = _recordedRoutePoints;
    if (recordedRoute.length >= 2) {
      await _polylineManager?.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: [
            for (final pt in recordedRoute)
              mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
          ]),
          lineColor: const Color(0xFF34A853).toARGB32(),
          lineOpacity: 0.92,
          lineWidth: 4.2,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      created = true;
    } else if (_checkpointPoints.length >= 2) {
      await _polylineManager?.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: [
            for (final pt in _checkpointPoints)
              mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
          ]),
          lineColor: const Color(0xFF6E6E73).toARGB32(),
          lineOpacity: 0.5,
          lineWidth: 2.4,
        ),
      );
      created = true;
    }

    final circleAnnotations = <mapbox.CircleAnnotationOptions>[
      for (final participant
          in (widget.teamHikeSession ?? widget.activeHike.teamHikeSession)
                  ?.participants ??
              const <TeamHikeParticipant>[])
        if (participant.latestLocation != null)
          mapbox.CircleAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(
                participant.latestLocation!.longitude,
                participant.latestLocation!.latitude,
              ),
            ),
            circleColor: participant.isLeader
                ? const Color(0xFFF59E0B).toARGB32()
                : const Color(0xFF7C3AED).toARGB32(),
            circleRadius: participant.isLeader ? 8.0 : 6.0,
            circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
            circleStrokeWidth: 2,
          ),
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

  Future<void> _fitRoute() async {
    final map = _mapboxMap;
    final points = _visiblePoints;
    if (map == null || points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      await map.flyTo(
        mapbox.CameraOptions(center: points.first, zoom: 15),
        mapbox.MapAnimationOptions(duration: 300),
      );
      await _syncScaleFromCamera();
      return;
    }
    final center = centerFor(points);
    await map.flyTo(
      mapbox.CameraOptions(center: center, zoom: _currentZoom),
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

  Future<void> _zoomBy(double amount) async {
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(zoom: _currentZoom + amount),
      mapbox.MapAnimationOptions(duration: 300),
    );
    await _syncScaleFromCamera();
  }

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _updateScale(data);
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

    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: ValueKey(mapStyleUrls[_styleIndex]),
            styleUri: mapStyleUrls[_styleIndex],
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleLoaded(),
            onCameraChangeListener: _onCameraChange,
            onMapIdleListener: (_) => unawaited(_syncScaleFromCamera()),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: _MapPill(
            label:
                (widget.teamHikeSession ?? widget.activeHike.teamHikeSession) !=
                    null
                    ? 'Live team map'
                    : widget.activeHike.routePoints.length >= 2
                        ? 'Live trail'
                        : 'Checkpoint route',
            color: widget.activeHike.routePoints.length >= 2
                ? const Color(0xFF34A853)
                : const Color(0xFF6E6E73),
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
      ],
    );
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
            _LegendDot(color: Color(0xFF7C3AED), label: 'Teammate'),
            _LegendDot(color: Color(0xFFF59E0B), label: 'Leader'),
          ],
        ),
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

class _MapPill extends StatelessWidget {
  const _MapPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
