part of '../location_sharing_page_feature.dart';

/// Owns the state and non-visual actions of _LiveLocationMap.
class _LiveLocationMapStateViewModel extends ChangeNotifier {
  /// Creates live location map state view model.
  _LiveLocationMapStateViewModel({required this.readLocation});
  final SosTriggerLocation Function() readLocation;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  mapbox.MapboxMap? stateMap;

  mapbox.PointAnnotationManager? statePinManager;

  mapbox.PointAnnotation? statePin;

  bool stateFailed = false;

  Timer? stateLoadTimeout;

  final int stateGeneration = 0;

  double stateZoom = 16;

  bool stateFollowLocation = true;

  /// Returns command center.
  mapbox.Point get commandCenter => mapbox.Point(
    coordinates: mapbox.Position(
      readLocation().longitude,
      readLocation().latitude,
    ),
  );

  /// Starts load timeout.
  void commandStartLoadTimeout() {
    stateLoadTimeout?.cancel();
    final generation = stateGeneration;
    stateLoadTimeout = Timer(const Duration(seconds: 15), () {
      if (stateGeneration == generation) commandFallback();
    });
  }

  /// Computes fallback.
  void commandFallback() {
    stateLoadTimeout?.cancel();
    if (mounted && !stateFailed) {
      _publish(() {
        stateFailed = true;
        stateMap = null;
        statePinManager = null;
        statePin = null;
      });
    }
  }

  /// Computes follow latest location.
  Future<void> commandFollowLatestLocation() async {
    try {
      await stateMap?.setCamera(mapbox.CameraOptions(center: commandCenter));
    } catch (_) {
      // A replaced map is centered when its new instance is created.
    }
  }

  /// Checks whether current map.
  bool commandIsCurrentMap(mapbox.MapboxMap map, int generation) =>
      mounted &&
      !stateFailed &&
      generation == stateGeneration &&
      identical(map, stateMap);

  /// Prepares native style.
  Future<void> commandPrepareNativeStyle(int generation) async {
    final map = stateMap;
    if (map == null || !commandIsCurrentMap(map, generation)) return;
    try {
      final manager = await map.annotations.createPointAnnotationManager();
      if (!commandIsCurrentMap(map, generation)) return;
      statePinManager = manager;
      await manager.setIconAllowOverlap(true);
      await commandUpdatePin();
    } catch (_) {
      if (commandIsCurrentMap(map, generation)) commandFallback();
    }
  }

  /// Updates pin.
  Future<void> commandUpdatePin() async {
    final map = stateMap;
    final manager = statePinManager;
    final generation = stateGeneration;
    if (map == null || manager == null) return;
    try {
      final pin = statePin;
      if (pin == null) {
        final image = await routeEndpointPinImage();
        if (!commandIsCurrentMap(map, generation) ||
            !identical(manager, statePinManager)) {
          return;
        }
        final created = await manager.create(
          mapbox.PointAnnotationOptions(
            geometry: commandCenter,
            image: image,
            iconAnchor: mapbox.IconAnchor.BOTTOM,
            iconSize: 0.6,
          ),
        );
        if (commandIsCurrentMap(map, generation)) statePin = created;
      } else {
        pin.geometry = commandCenter;
        await manager.update(pin);
      }
    } catch (_) {
      // Keep the last confirmed map pin if the map is being replaced.
    }
  }

  /// Computes zoom by.
  Future<void> commandZoomBy(double amount) async {
    if (stateFailed || !GoogleApiConfig.hasMapboxAccessToken) {
      _publish(() => stateZoom = (stateZoom + amount).clamp(3.0, 19.0));
      return;
    }
    stateFollowLocation = false;
    try {
      await stateMap?.flyTo(
        mapbox.CameraOptions(
          zoom: (stateZoom + amount).clamp(kMapMinZoom, kMapMaxZoom).toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // The style may have changed while zooming.
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
