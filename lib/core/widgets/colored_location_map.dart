import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../config/google_api_config.dart';
import 'colored_location_map_controller.dart';
import 'map_utils.dart';
import 'map_view_controller.dart';
export 'colored_location_map_controller.dart' show ColoredLocationPoint;

/// Reusable map for named, colour-assigned locations with the shared map controls.
class ColoredLocationMap extends StatefulWidget {
  /// Uses the fallback only as the camera centre, never as a fabricated hiker marker.
  const ColoredLocationMap({
    super.key,
    required this.points,
    required this.fallback,
    this.mapBuilder,
  });
  final List<ColoredLocationPoint> points;
  final mapbox.Point fallback;
  final Widget Function(mapbox.MapWidget configuration)? mapBuilder;

  /// Binds native map events to the marker controller.
  @override
  State<ColoredLocationMap> createState() => _ColoredLocationMapState();
}

/// Owns the map surface lifecycle while the controller owns annotation changes.
class _ColoredLocationMapState extends State<ColoredLocationMap> {
  late final _controller = ColoredLocationMapController(
    points: widget.points,
    fallback: widget.fallback,
  );

  /// Accepts updated recorded positions without replacing the native map surface.
  @override
  void didUpdateWidget(covariant ColoredLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.update(widget.points);
  }

  /// Releases native listeners when the map page closes.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps zoom/reset, style selection, scale/style label and compass in their standard corners.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      if (_controller.failed ||
          !GoogleApiConfig.hasMapboxAccessToken && widget.mapBuilder == null) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Map unavailable. Last recorded locations remain listed below.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      final configuration = mapbox.MapWidget(
        key: const ValueKey('colored-location-map'),
        styleUri: mapStyleUrls.first,
        viewport: mapbox.CameraViewportState(center: widget.fallback, zoom: 13),
        gestureRecognizers: eagerMapGestureRecognizers,
        onMapCreated: _controller.attach,
        onStyleLoadedListener: (_) => unawaited(_controller.styleLoaded()),
        onMapLoadedListener: (_) => unawaited(_controller.styleLoaded()),
        onCameraChangeListener: _controller.view.cameraChanged,
        onMapLoadErrorListener: (event) {
          if (event.type == mapbox.MapLoadErrorType.STYLE) {
            if (_controller.view.isChanging) {
              _controller.view.styleLoadFailed();
            } else {
              _controller.fail();
            }
          }
        },
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.mapBuilder?.call(configuration) ?? configuration,
          MapViewOverlay(
            controller: _controller.view,
            onReset: () => unawaited(_controller.fit()),
          ),
        ],
      );
    },
  );
}
