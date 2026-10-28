import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../config/google_api_config.dart';
import 'location_destination_map_controller.dart';
import 'map_utils.dart';
import 'map_view_controller.dart';

/// Reusable map showing the hiker's blue dot and a red destination pin.
class LocationDestinationMap extends StatefulWidget {
  /// The supplied points are the exact locations used in the distance check.
  const LocationDestinationMap({
    super.key,
    required this.current,
    required this.destination,
    this.mapBuilder,
  });

  final mapbox.Point current;
  final mapbox.Point destination;
  @visibleForTesting
  final Widget Function(mapbox.MapWidget configuration)? mapBuilder;

  /// Creates the map lifecycle bindings.
  @override
  State<LocationDestinationMap> createState() => _LocationDestinationMapState();
}

/// Binds native map events to the reusable controller.
class _LocationDestinationMapState extends State<LocationDestinationMap> {
  late final _controller = LocationDestinationMapController(
    current: widget.current,
    destination: widget.destination,
  );

  /// Releases map resources when the popup leaves the screen.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Uses the same zoom, style, scale and compass arrangement as other maps.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      if (_controller.failed ||
          (!GoogleApiConfig.hasMapboxAccessToken &&
              widget.mapBuilder == null)) {
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Map unavailable. You can still get directions in Waze.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
      final map = mapbox.MapWidget(
        key: const ValueKey('location-destination-map'),
        styleUri: mapStyleUrls[0],
        viewport: mapbox.CameraViewportState(
          center: widget.destination,
          zoom: 13,
        ),
        gestureRecognizers: eagerMapGestureRecognizers,
        onMapCreated: _controller.attach,
        onStyleLoadedListener: (_) => unawaited(_controller.styleLoaded()),
        onMapLoadedListener: (_) => unawaited(_controller.styleLoaded()),
        onCameraChangeListener: _controller.view.cameraChanged,
        onMapLoadErrorListener: (event) {
          if (event.type != mapbox.MapLoadErrorType.STYLE) return;
          if (_controller.view.isChanging) {
            _controller.view.styleLoadFailed();
          } else {
            _controller.fail();
          }
        },
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.mapBuilder?.call(map) ?? map,
          MapViewOverlay(
            controller: _controller.view,
            onReset: () => unawaited(_controller.fit()),
          ),
        ],
      );
    },
  );
}
