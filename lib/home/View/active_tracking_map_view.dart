import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../Model/hike_session_models.dart';

class ActiveTrackingMapView extends StatefulWidget {
  const ActiveTrackingMapView({
    super.key,
    required this.activeHike,
    this.interactive = true,
    this.showLegend = false,
  });

  final ActiveHikeSession activeHike;
  final bool interactive;
  final bool showLegend;

  @override
  State<ActiveTrackingMapView> createState() => _ActiveTrackingMapViewState();
}

class _ActiveTrackingMapViewState extends State<ActiveTrackingMapView> {
  static const _styleUrls = [
    'https://tiles.openfreemap.org/styles/liberty',
    'https://tiles.openfreemap.org/styles/positron',
    'https://tiles.openfreemap.org/styles/bright',
  ];
  static const _minZoom = 4.2;
  static const _maxZoom = 21.0;

  maplibre.MapLibreMapController? _mapController;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;

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
      return;
    }
    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        _boundsFor(points),
        left: 34,
        top: 34,
        right: 34,
        bottom: 34,
      ),
    );
  }

  void _cycleStyle() {
    setState(() {
      _styleIndex = (_styleIndex + 1) % _styleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
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
          key: ValueKey(_styleUrls[_styleIndex]),
          styleString: _styleUrls[_styleIndex],
          initialCameraPosition: maplibre.CameraPosition(
            target: _centerFor(visiblePoints),
            zoom: visiblePoints.length == 1 ? 15 : 13.5,
          ),
          minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
            _minZoom,
            _maxZoom,
          ),
          compassEnabled: false,
          logoEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          zoomGesturesEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          trackCameraPosition: false,
          gestureRecognizers: widget.interactive
              ? {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                }
              : const <Factory<OneSequenceGestureRecognizer>>{},
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
        ),
        Positioned(
          left: 10,
          top: 10,
          child: _MapPill(
            label: widget.activeHike.routePoints.length >= 2
                ? 'Live MapLibre trail'
                : 'Checkpoint route',
            color: widget.activeHike.routePoints.length >= 2
                ? const Color(0xFF34A853)
                : const Color(0xFF6E6E73),
          ),
        ),
        if (widget.interactive)
          Positioned(
            right: 10,
            top: 10,
            child: _MapIconButton(
              tooltip: 'Change map style',
              icon: Icons.layers_rounded,
              onPressed: _cycleStyle,
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

  maplibre.LatLng _centerFor(List<maplibre.LatLng> points) {
    var latitude = 0.0;
    var longitude = 0.0;
    for (final point in points) {
      latitude += point.latitude;
      longitude += point.longitude;
    }
    return maplibre.LatLng(latitude / points.length, longitude / points.length);
  }

  maplibre.LatLngBounds _boundsFor(List<maplibre.LatLng> points) {
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }
    if ((maxLatitude - minLatitude).abs() < 0.0001) {
      minLatitude -= 0.00005;
      maxLatitude += 0.00005;
    }
    if ((maxLongitude - minLongitude).abs() < 0.0001) {
      minLongitude -= 0.00005;
      maxLongitude += 0.00005;
    }
    return maplibre.LatLngBounds(
      southwest: maplibre.LatLng(minLatitude, minLongitude),
      northeast: maplibre.LatLng(maxLatitude, maxLongitude),
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

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: const Color(0xFF34A853), size: 20),
        ),
      ),
    );
  }
}
