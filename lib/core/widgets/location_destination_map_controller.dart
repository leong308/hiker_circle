import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'map_utils.dart';
import 'map_view_controller.dart';
import 'route_endpoint_marker.dart';

/// Draws a location dot and destination pin with the shared map controls.
class LocationDestinationMapController extends ChangeNotifier {
  /// Keeps both points fixed to the comparison shown by the calling dialog.
  LocationDestinationMapController({
    required this.current,
    required this.destination,
  }) {
    view = MapViewController(
      settings: const MapViewSettings(dimension: MapDimension.twoD),
      onBeforeStyleReload: _clearAnnotations,
    );
    _timeout = Timer(const Duration(seconds: 15), fail);
  }

  final mapbox.Point current;
  final mapbox.Point destination;
  late final MapViewController view;
  mapbox.MapboxMap? _map;
  mapbox.CircleAnnotationManager? _dots;
  mapbox.PointAnnotationManager? _pins;
  Timer? _timeout;
  bool _disposed = false;
  bool failed = false;
  int _generation = 0;

  /// Stops delayed work from writing to a replaced or disposed native map.
  bool _isCurrent(mapbox.MapboxMap map, int generation) =>
      !_disposed &&
      !failed &&
      identical(map, _map) &&
      generation == _generation;

  /// Attaches the native map before early style callbacks are replayed.
  void attach(mapbox.MapboxMap map) {
    if (_disposed || failed) return;
    _map = map;
    _generation++;
    view.attach(map);
    unawaited(_prepareMap(map, _generation));
  }

  /// Hides native controls that are already supplied by the shared overlay.
  Future<void> _prepareMap(mapbox.MapboxMap map, int generation) async {
    try {
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      if (!_isCurrent(map, generation)) return;
      await map.scaleBar.updateSettings(
        mapbox.ScaleBarSettings(enabled: false),
      );
      if (!_isCurrent(map, generation)) return;
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {
      if (_isCurrent(map, generation)) fail();
    }
  }

  /// Recreates both markers when the selected map style finishes loading.
  Future<void> styleLoaded() => view.styleLoaded(_render);

  /// Uses a blue circle for the hiker and the existing red endpoint artwork.
  Future<void> _render() async {
    final map = _map;
    final generation = _generation;
    if (map == null || !_isCurrent(map, generation)) return;
    final image = await routeEndpointPinImage();
    if (!_isCurrent(map, generation)) return;
    final dots = await map.annotations.createCircleAnnotationManager();
    if (!_isCurrent(map, generation)) return;
    _dots = dots;
    await dots.create(
      mapbox.CircleAnnotationOptions(
        geometry: current,
        circleRadius: 8,
        circleColor: 0xFF007AFF,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 3,
      ),
    );
    if (!_isCurrent(map, generation)) return;
    final pins = await map.annotations.createPointAnnotationManager();
    if (!_isCurrent(map, generation)) return;
    _pins = pins;
    await pins.setIconAllowOverlap(true);
    if (!_isCurrent(map, generation)) return;
    await pins.create(
      routeEndpointAnnotation(
        geometry: destination,
        label: 'Trail start',
        pinImage: image,
      ),
    );
    if (!_isCurrent(map, generation)) return;
    await fit();
    if (!_isCurrent(map, generation)) return;
    _timeout?.cancel();
  }

  /// Fits both points with room for the corner controls and the red pin label.
  Future<void> fit() async {
    final map = _map;
    final generation = _generation;
    if (map == null || !_isCurrent(map, generation)) return;
    try {
      final bounds = boundsFor([current, destination]);
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
        mapbox.MbxEdgeInsets(top: 92, left: 46, bottom: 82, right: 46),
        0,
        view.settings.is3D ? 50 : 0,
        17,
        null,
      );
      if (!_isCurrent(map, generation)) return;
      await map.setCamera(camera);
    } catch (_) {
      if (_isCurrent(map, generation)) fail();
    }
  }

  /// Removes old managers before a style change so markers are not duplicated.
  Future<void> _clearAnnotations() async {
    final dots = _dots;
    final pins = _pins;
    _dots = null;
    _pins = null;
    _generation++;
    await removeMapAnnotationManagers(_map, [dots, pins]);
  }

  /// Reports map failure without preventing directions or the user's decision.
  void fail() {
    if (_disposed || failed) return;
    _timeout?.cancel();
    failed = true;
    _generation++;
    notifyListeners();
  }

  /// Releases listeners and timers when the popup closes.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timeout?.cancel();
    view.dispose();
    _map = null;
    super.dispose();
  }
}
