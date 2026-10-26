part of '../nearby_sos_map_page_feature.dart';

/// Owns the state and non-visual actions of NearbySosMapPage.
class _NearbySosMapPageStateViewModel extends ChangeNotifier {
  /// Creates nearby sos map page state view model.
  _NearbySosMapPageStateViewModel({
    required this.readEvent,
    required this.effectShowOpenError,
  });
  final NearbySosEvent Function() readEvent;
  final void Function() effectShowOpenError;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final HikingRouteService stateRouteService;

  SosTriggerLocation? statePhoneLocation;

  HikingRouteResult? stateRoute;

  Trail? stateRouteTrail;

  String? stateRouteError;

  bool stateIsLoadingRoute = false;

  /// Loads walking route.
  Future<void> commandLoadWalkingRoute() async {
    if (stateIsLoadingRoute || !readEvent().hasReportedLocation) return;
    _publish(() {
      stateIsLoadingRoute = true;
      stateRouteError = null;
    });
    try {
      final snapshots = LocationSnapshotService.instance;
      final current =
          _validLocation(await snapshots.refresh()) ??
          _validLocation(snapshots.latestLocation) ??
          _validLocation(statePhoneLocation);
      if (current == null) {
        throw const HikingRouteServiceException(
          'Current phone location is unavailable. Enable location and retry.',
        );
      }
      final trail = buildNearbySosRouteTrail(
        event: readEvent(),
        phoneLocation: current,
      );
      if (!mounted) return;
      _publish(() {
        statePhoneLocation = current;
        stateRouteTrail = trail;
      });
      final route = await stateRouteService
          .findHikingRouteForTrail(trail)
          .timeout(const Duration(seconds: 50));
      if (!mounted) return;
      _publish(() => stateRoute = route);
    } on TimeoutException {
      if (mounted) {
        _publish(() {
          stateRouteError =
              'Walking route providers are taking too long. Retry.';
        });
      }
    } on HikingRouteServiceException catch (error) {
      if (mounted) _publish(() => stateRouteError = error.message);
    } catch (_) {
      if (mounted) {
        _publish(() {
          stateRouteError = 'Unable to calculate a walking route right now.';
        });
      }
    } finally {
      if (mounted) _publish(() => stateIsLoadingRoute = false);
    }
  }

  /// Opens external directions.
  Future<void> commandOpenExternalDirections() async {
    final target = readEvent().location;
    final origin = statePhoneLocation;
    if (target == null || origin == null) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${target.latitude},${target.longitude}',
      'travelmode': 'walking',
    });
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) effectShowOpenError();
    } catch (_) {
      if (mounted) effectShowOpenError();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _NearbySosRadiusMap.
class _NearbySosRadiusMapStateViewModel extends ChangeNotifier {
  /// Creates nearby sos radius map state view model.
  _NearbySosRadiusMapStateViewModel({required this.readEvent});
  final NearbySosEvent Function() readEvent;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  mapbox.MapboxMap? stateMap;

  mapbox.CircleAnnotationManager? stateCircleManager;

  mapbox.PolygonAnnotationManager? statePolygonManager;

  SosTriggerLocation? stateCenterLocation;

  bool stateStyleLoaded = false;

  bool stateIsLoadingLocation = false;

  /// Returns command radius meters.
  double get commandRadiusMeters => _bleRadiusMeters(readEvent().rssi ?? -70);

  /// Returns command center point.
  mapbox.Point? get commandCenterPoint {
    final location = _validLocation(stateCenterLocation);
    if (location == null) return null;
    return mapbox.Point(
      coordinates: mapbox.Position(location.longitude, location.latitude),
    );
  }

  /// Loads current location.
  Future<void> commandLoadCurrentLocation() async {
    if (stateIsLoadingLocation) return;
    _publish(() => stateIsLoadingLocation = true);
    final snapshots = LocationSnapshotService.instance;
    final location =
        _validLocation(await snapshots.refresh()) ??
        _validLocation(snapshots.latestLocation);
    if (!mounted) return;
    _publish(() {
      stateIsLoadingLocation = false;
      stateCenterLocation = location;
    });
    if (location == null) return;
    await commandRender();
    await commandFit();
  }

  /// Prepares map style.
  Future<void> commandPrepareMapStyle() async {
    stateStyleLoaded = true;
    stateCircleManager = null;
    statePolygonManager = null;
    await commandEnsureManagers();
    await commandRender();
  }

  /// Ensures managers.
  Future<bool> commandEnsureManagers() async {
    final map = stateMap;
    if (map == null || !stateStyleLoaded) return false;
    try {
      stateCircleManager ??= await map.annotations
          .createCircleAnnotationManager();
      statePolygonManager ??= await map.annotations
          .createPolygonAnnotationManager();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Computes render.
  Future<void> commandRender() async {
    if (!await commandEnsureManagers()) return;
    final point = commandCenterPoint;
    if (point == null) return;
    final latitude = point.coordinates[1]!.toDouble();
    final longitude = point.coordinates[0]!.toDouble();
    try {
      await stateCircleManager?.deleteAll();
      await statePolygonManager?.deleteAll();
      await statePolygonManager?.create(
        mapbox.PolygonAnnotationOptions(
          geometry: mapbox.Polygon(
            coordinates: [
              _radiusRing(latitude, longitude, commandRadiusMeters),
            ],
          ),
          fillColor: const Color(0xFF0A84FF).toARGB32(),
          fillOpacity: 0.18,
          fillOutlineColor: const Color(0xFF0A84FF).toARGB32(),
        ),
      );
      await stateCircleManager?.create(
        mapbox.CircleAnnotationOptions(
          geometry: point,
          circleColor: const Color(0xFF0A84FF).toARGB32(),
          circleRadius: 9,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
        ),
      );
    } catch (_) {}
  }

  /// Computes fit.
  Future<void> commandFit() async {
    final map = stateMap;
    final point = commandCenterPoint;
    if (map == null || point == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          center: point,
          zoom: (16 - math.log(commandRadiusMeters / 50) / math.ln2).clamp(
            11,
            18,
          ),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {}
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
