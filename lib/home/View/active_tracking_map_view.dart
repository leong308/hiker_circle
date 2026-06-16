import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

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
  maplibre.MapLibreMapController? _mapController;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;
  late double _currentZoom;
  late double _scaleLatitude;

  @override
  void initState() {
    super.initState();
    final pts = _visiblePoints;
    final center = pts.isEmpty ? maplibre.LatLng(0, 0) : centerFor(pts);
    _currentZoom = pts.length == 1 ? 15 : 13.5;
    _scaleLatitude = center.latitude;
  }

  List<maplibre.LatLng> get _recordedRoutePoints {
    return widget.activeHike.routePoints
        .map((point) => maplibre.LatLng(point.latitude, point.longitude))
        .toList();
  }

  List<maplibre.LatLng> get _checkpointPoints {
    final checkpoints = [...widget.activeHike.trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    return checkpoints
        .map(
          (checkpoint) =>
              maplibre.LatLng(checkpoint.latitude, checkpoint.longitude),
        )
        .toList();
  }

  List<maplibre.LatLng> get _manualPinPoints {
    return widget.activeHike.manualPinLocations
        .map(
          (pin) => maplibre.LatLng(
            pin.coordinate.latitude,
            pin.coordinate.longitude,
          ),
        )
        .toList();
  }

  List<maplibre.LatLng> get _teamMatePoints {
    final teamSession =
        widget.teamHikeSession ?? widget.activeHike.teamHikeSession;
    if (teamSession == null) {
      return const [];
    }
    return teamSession.participants
        .where((participant) => participant.latestLocation != null)
        .map(
          (participant) => maplibre.LatLng(
            participant.latestLocation!.latitude,
            participant.latestLocation!.longitude,
          ),
        )
        .toList();
  }

  maplibre.LatLng? get _latestPoint {
    final latest = widget.activeHike.latestLocation;
    if (latest == null) {
      return null;
    }
    return maplibre.LatLng(latest.latitude, latest.longitude);
  }

  List<maplibre.LatLng> get _visiblePoints {
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

  Future<void> _onMapCreated(maplibre.MapLibreMapController controller) async {
    _mapController = controller;
    await _renderRouteIfReady();
    await _syncScaleFromCamera();
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    _routeRendered = false;
    await _renderRouteIfReady();
  }

  Future<void> _renderRouteIfReady() async {
    final controller = _mapController;
    if (controller == null ||
        !_styleLoaded ||
        _routeRendered ||
        _visiblePoints.isEmpty) {
      return;
    }

    _routeRendered = true;
    await controller.clearLines();
    await controller.clearCircles();

    final recordedRoute = _recordedRoutePoints;
    if (recordedRoute.length >= 2) {
      await controller.addLine(
        maplibre.LineOptions(
          geometry: recordedRoute,
          lineColor: '#34A853',
          lineOpacity: 0.92,
          lineWidth: 4.2,
          lineJoin: 'round',
        ),
      );
    } else if (_checkpointPoints.length >= 2) {
      await controller.addLine(
        maplibre.LineOptions(
          geometry: _checkpointPoints,
          lineColor: '#6E6E73',
          lineOpacity: 0.5,
          lineWidth: 2.4,
        ),
      );
    }

    await controller.addCircles([
      for (final participant
          in (widget.teamHikeSession ?? widget.activeHike.teamHikeSession)
                  ?.participants ??
              const <TeamHikeParticipant>[])
        if (participant.latestLocation != null)
          maplibre.CircleOptions(
            geometry: maplibre.LatLng(
              participant.latestLocation!.latitude,
              participant.latestLocation!.longitude,
            ),
            circleColor: participant.isLeader ? '#F59E0B' : '#7C3AED',
            circleRadius: participant.isLeader ? 8 : 6,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ),
      for (final point in _manualPinPoints)
        maplibre.CircleOptions(
          geometry: point,
          circleColor: '#E11D48',
          circleRadius: 6,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      if (_latestPoint != null)
        maplibre.CircleOptions(
          geometry: _latestPoint!,
          circleColor: '#0A84FF',
          circleRadius: 7,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      if (recordedRoute.isNotEmpty)
        maplibre.CircleOptions(
          geometry: recordedRoute.first,
          circleColor: '#7BC90E',
          circleRadius: 6,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
    ]);

    await _fitRoute();
  }

  Future<void> _fitRoute() async {
    final controller = _mapController;
    final points = _visiblePoints;
    if (controller == null || points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(points.first, 15),
      );
      await _syncScaleFromCamera();
      return;
    }
    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        boundsFor(points),
        left: 34,
        top: 34,
        right: 34,
        bottom: 34,
      ),
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
    await _mapController?.animateCamera(maplibre.CameraUpdate.zoomBy(amount));
    await _syncScaleFromCamera();
  }

  void _onCameraMove(maplibre.CameraPosition position) {
    _updateScale(position);
  }

  Future<void> _syncScaleFromCamera() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final position =
        controller.cameraPosition ?? await controller.queryCameraPosition();
    if (position != null) {
      _updateScale(position);
    }
  }

  void _updateScale(maplibre.CameraPosition position) {
    final nextZoom = position.zoom;
    final nextLatitude = position.target.latitude;
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
        maplibre.MapLibreMap(
          key: ValueKey(mapStyleUrls[_styleIndex]),
          styleString: mapStyleUrls[_styleIndex],
          initialCameraPosition: maplibre.CameraPosition(
            target: centerFor(visiblePoints),
            zoom: _currentZoom,
          ),
          minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
            kMapMinZoom,
            kMapMaxZoom,
          ),
          compassEnabled: false,
          logoEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          zoomGesturesEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          trackCameraPosition: true,
          gestureRecognizers: widget.interactive
              ? {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                }
              : const <Factory<OneSequenceGestureRecognizer>>{},
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraMove: _onCameraMove,
          onCameraIdle: () => unawaited(_syncScaleFromCamera()),
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
                ? 'Live MapLibre trail'
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
