part of '../residential_city_picker_page_feature.dart';

/// Owns the state and non-visual actions of ResidentialCityPickerPage.
class _ResidentialCityPickerPageStateViewModel extends ChangeNotifier {
  /// Creates residential city picker page state view model.
  _ResidentialCityPickerPageStateViewModel({
    required this.readInitialLatitude,
    required this.readInitialLongitude,
    required this.effectUpdateScaleValues,
  });
  final double? Function() readInitialLatitude;
  final double? Function() readInitialLongitude;
  final void Function(double nextZoom, mapbox.Point center)
  effectUpdateScaleValues;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  MalaysiaMapRegion stateFocusRegion = MalaysiaMapRegion.peninsula;

  int stateFocusRevision = 0;

  late mapbox.Point stateSelected;

  double stateCurrentZoom = 5.4;

  mapbox.MapboxMap? stateMapboxMap;

  bool stateIsResolving = false;

  String? stateErrorMessage;

  /// Returns command has initial location.
  bool get commandHasInitialLocation =>
      readInitialLatitude() != null &&
      readInitialLongitude() != null &&
      mapPointCoordinatesOrNull(
            mapbox.Point(
              coordinates: mapbox.Position(
                readInitialLongitude()!,
                readInitialLatitude()!,
              ),
            ),
          ) !=
          null;

  /// Computes move pin.
  void commandMovePin(mapbox.Point coordinate) {
    final values = mapPointCoordinatesOrNull(coordinate);
    if (!mounted || stateIsResolving || values == null) return;
    final safeCoordinate = mapbox.Point(
      coordinates: mapbox.Position(values.longitude, values.latitude),
    );
    _publish(() {
      stateSelected = safeCoordinate;
      stateErrorMessage = null;
    });
    unawaited(commandCenterMapOn(safeCoordinate));
  }

  /// Computes center map on.
  Future<void> commandCenterMapOn(mapbox.Point coordinate) async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(center: coordinate),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // The native map may have been disposed while handling a tap.
    }
  }

  /// Computes fit to pin.
  Future<void> commandFitToPin() async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(center: stateSelected, zoom: 14),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      return;
    }
    await commandSyncScaleFromCamera();
  }

  /// Computes zoom by.
  Future<void> commandZoomBy(double amount) async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          zoom: (stateCurrentZoom + amount)
              .clamp(kMapMinZoom, kMapMaxZoom)
              .toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      return;
    }
    await commandSyncScaleFromCamera();
  }

  /// Synchronizes scale from camera.
  Future<void> commandSyncScaleFromCamera() async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      if (!mounted || !identical(map, stateMapboxMap)) return;
      effectUpdateScaleValues(state.zoom, state.center);
    } catch (_) {
      // Map replacement can invalidate an in-flight camera request.
    }
  }

  /// Updates scale.
  void commandUpdateScale(mapbox.CameraChangedEventData data) {
    effectUpdateScaleValues(data.cameraState.zoom, data.cameraState.center);
  }

  /// Computes focus on region.
  Future<void> commandFocusOnRegion({int duration = 450}) async {
    final map = stateMapboxMap;
    if (map == null) return;
    final region = stateFocusRegion;
    final revision = ++stateFocusRevision;
    try {
      final camera = await map.cameraForCoordinateBounds(
        mapbox.CoordinateBounds(
          southwest: mapbox.Point(
            coordinates: mapbox.Position(region.west, region.south),
          ),
          northeast: mapbox.Point(
            coordinates: mapbox.Position(region.east, region.north),
          ),
          infiniteBounds: false,
        ),
        mapbox.MbxEdgeInsets(top: 32, left: 32, bottom: 32, right: 32),
        0,
        0,
        null,
        null,
      );
      if (!mounted ||
          !identical(map, stateMapboxMap) ||
          revision != stateFocusRevision) {
        return;
      }
      // The fixed pointer selects the camera center, so retain the precise
      // region center instead of a padding-adjusted bounds-fitting center.
      camera.center = mapbox.Point(
        coordinates: mapbox.Position(region.longitude, region.latitude),
      );
      await map.flyTo(camera, mapbox.MapAnimationOptions(duration: duration));
    } catch (_) {
      // A replaced or disposed native map can invalidate the camera request.
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final void Function() effectPresentUpdateStateBoundaryEffect1;

  /// Updates state boundary.
  Future<void> commandUpdateStateBoundary(Future<void> update) async {
    try {
      await update;
    } catch (error) {
      debugPrint('Residential city boundary failed: $error');
      if (!mounted) return;
      effectPresentUpdateStateBoundaryEffect1();
    }
  }
}
