part of '../nearby_sos_map_page_feature.dart';

/// Displays the nearby sos map page.
class NearbySosMapPage extends StatefulWidget {
  /// Creates nearby sos map page.
  const NearbySosMapPage({
    super.key,
    required this.event,
    this.initialPhoneLocation,
    this.routeService,
  });

  final NearbySosEvent event;
  final SosTriggerLocation? initialPhoneLocation;
  final HikingRouteService? routeService;

  /// Creates the presentation state for this widget.
  @override
  State<NearbySosMapPage> createState() => _NearbySosMapPageState();
}

/// Manages the nearby sos map page presentation and lifecycle.
class _NearbySosMapPageState extends State<NearbySosMapPage> {
  late final _NearbySosMapPageStateViewModel _screenModel;

  /// Updates route service.
  set _routeService(HikingRouteService value) =>
      _screenModel.stateRouteService = value;

  /// Returns phone location.
  SosTriggerLocation? get _phoneLocation => _screenModel.statePhoneLocation;

  /// Updates phone location.
  set _phoneLocation(SosTriggerLocation? value) =>
      _screenModel.statePhoneLocation = value;

  /// Returns route.
  HikingRouteResult? get _route => _screenModel.stateRoute;

  /// Returns route trail.
  Trail? get _routeTrail => _screenModel.stateRouteTrail;

  /// Returns route error.
  String? get _routeError => _screenModel.stateRouteError;

  /// Returns is loading route.
  bool get _isLoadingRoute => _screenModel.stateIsLoadingRoute;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _NearbySosMapPageStateViewModel(
      readEvent: () => widget.event,
      effectShowOpenError: _showOpenError,
    )..addListener(_renderScreenModel);

    _routeService = widget.routeService ?? HikingRouteService();
    _phoneLocation = _validLocation(widget.initialPhoneLocation);
    if (widget.event.hasReportedLocation) {
      unawaited(_loadWalkingRoute());
    }
  }

  /// Delegates load walking route to the ViewModel.
  Future<void> _loadWalkingRoute() => _screenModel.commandLoadWalkingRoute();

  /// Delegates open external directions to the ViewModel.
  Future<void> _openExternalDirections() =>
      _screenModel.commandOpenExternalDirections();

  /// Shows open error.
  void _showOpenError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Unable to open walking directions.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Opens first aid.
  void _openFirstAid() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FirstAidGuidePage(
          emergencyLatitude: widget.event.location?.latitude,
          emergencyLongitude: widget.event.location?.longitude,
        ),
      ),
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final hasExactLocation = widget.event.hasReportedLocation;
    final trail = _routeTrail;
    return Scaffold(
      backgroundColor: _NearbyMapColors.backgroundFor(context),
      body: SafeArea(
        child: Column(
          children: [
            _NearbyMapHeader(onBack: () => Navigator.of(context).pop()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: hasExactLocation
                  ? _WalkingRouteStatusCard(
                      route: _route,
                      isLoading: _isLoadingRoute,
                      errorMessage: _routeError,
                      onRetry: _loadWalkingRoute,
                    )
                  : const _RadiusExplanationCard(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: hasExactLocation
                      ? trail == null
                            ? _RouteMapPlaceholder(
                                isLoading: _isLoadingRoute,
                                errorMessage: _routeError,
                                onRetry: _loadWalkingRoute,
                              )
                            : RoutePreviewMap(
                                key: ValueKey(
                                  'nearby-sos-route-${widget.event.eventKey}',
                                ),
                                trail: trail,
                                route: _route,
                                animateRoute: false,
                                captureAllGestures: true,
                                showLayerToggle: true,
                                isRouteLoading: _isLoadingRoute,
                                loadingMessage: 'Calculating walking route…',
                              )
                      : _NearbySosRadiusMap(
                          event: widget.event,
                          initialPhoneLocation: _phoneLocation,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openFirstAid,
                      icon: const Icon(Icons.medical_services_outlined),
                      label: const Text('First aid guide'),
                    ),
                  ),
                  if (hasExactLocation) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _phoneLocation == null
                            ? null
                            : _openExternalDirections,
                        icon: const Icon(Icons.directions_walk_rounded),
                        label: const Text('Open directions'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the route map placeholder.
class _RouteMapPlaceholder extends StatelessWidget {
  /// Creates route map placeholder.
  const _RouteMapPlaceholder({
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ColoredBox(
        color: _NearbyMapColors.surfaceFor(context),
        child: const HikerCircleLoadingView(
          message: 'Getting your emergency location…',
          detail: 'Preparing the nearby SOS map.',
          compact: true,
        ),
      );
    }
    return ColoredBox(
      color: _NearbyMapColors.surfaceFor(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 42,
                color: _NearbyMapColors.secondaryFor(context),
              ),
              const SizedBox(height: 14),
              Text(
                errorMessage ?? 'The emergency map is unavailable.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _NearbyMapColors.textFor(context),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
/// Build a display route to the selected nearby event without replacing the hiker's active session.
Trail buildNearbySosRouteTrail({
  required NearbySosEvent event,
  required SosTriggerLocation phoneLocation,
}) {
  final target = event.location;
  if (!event.hasReportedLocation || target == null) {
    throw ArgumentError('A reported SOS location is required.');
  }
  final straightLineMeters = event.distanceMetersFrom(phoneLocation) ?? 1;
  return Trail(
    trailId: 'nearby_sos_${event.eventKey}',
    name: 'Nearby SOS walking route',
    area: 'Emergency route',
    state: '',
    latitude: target.latitude,
    longitude: target.longitude,
    distanceKm: math.max(straightLineMeters / 1000, 0.001),
    difficulty: 'Emergency',
    estimatedDurationMinutes: math.max((straightLineMeters / 80).ceil(), 1),
    elevationGainMeters: 0,
    ratingAverage: 0,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: false,
    routeFilePath: '',
    coverColorValue: 0xFFFF3B30,
    checkpoints: [
      TrailCheckpoint(
        name: 'Your phone',
        latitude: phoneLocation.latitude,
        longitude: phoneLocation.longitude,
        order: 1,
      ),
      TrailCheckpoint(
        name: 'Reported SOS',
        latitude: target.latitude,
        longitude: target.longitude,
        order: 2,
      ),
    ],
    weather: TrailWeather(
      summary: '',
      temperatureRange: '',
      rainProbability: 0,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    hazards: const [],
  );
}

/// Displays the nearby sos radius map.
class _NearbySosRadiusMap extends StatefulWidget {
  /// Creates nearby sos radius map.
  const _NearbySosRadiusMap({
    required this.event,
    required this.initialPhoneLocation,
  });

  final NearbySosEvent event;
  final SosTriggerLocation? initialPhoneLocation;

  /// Creates the presentation state for this widget.
  @override
  State<_NearbySosRadiusMap> createState() => _NearbySosRadiusMapState();
}

/// Manages the nearby sos radius map presentation and lifecycle.
class _NearbySosRadiusMapState extends State<_NearbySosRadiusMap> {
  late final _NearbySosRadiusMapStateViewModel _screenModel;

  /// Returns map.
  mapbox.MapboxMap? get _map => _screenModel.stateMap;

  /// Updates map.
  set _map(mapbox.MapboxMap? value) => _screenModel.stateMap = value;

  /// Returns circle manager.
  mapbox.CircleAnnotationManager? get _circleManager =>
      _screenModel.stateCircleManager;

  /// Updates circle manager.
  set _circleManager(mapbox.CircleAnnotationManager? value) =>
      _screenModel.stateCircleManager = value;

  /// Returns polygon manager.
  mapbox.PolygonAnnotationManager? get _polygonManager =>
      _screenModel.statePolygonManager;

  /// Updates polygon manager.
  set _polygonManager(mapbox.PolygonAnnotationManager? value) =>
      _screenModel.statePolygonManager = value;

  /// Returns center location.
  SosTriggerLocation? get _centerLocation => _screenModel.stateCenterLocation;

  /// Updates center location.
  set _centerLocation(SosTriggerLocation? value) =>
      _screenModel.stateCenterLocation = value;

  /// Updates style loaded.
  set _styleLoaded(bool value) => _screenModel.stateStyleLoaded = value;

  /// Returns is loading location.
  bool get _isLoadingLocation => _screenModel.stateIsLoadingLocation;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: const MapViewSettings(dimension: MapDimension.twoD),
    onBeforeStyleReload: () async {
      final managers = <mapbox.BaseAnnotationManager?>[
        _circleManager,
        _polygonManager,
      ];
      _styleLoaded = false;
      _circleManager = null;
      _polygonManager = null;
      await removeMapAnnotationManagers(_map, managers);
    },
  );

  /// Returns radius meters.
  double get _radiusMeters => _screenModel.commandRadiusMeters;

  /// Returns center point.
  mapbox.Point? get _centerPoint => _screenModel.commandCenterPoint;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _NearbySosRadiusMapStateViewModel(
      readEvent: () => widget.event,
    )..addListener(_renderScreenModel);

    _centerLocation =
        _validLocation(widget.event.detectorLocation) ??
        _validLocation(widget.initialPhoneLocation);
    if (_centerLocation == null) {
      unawaited(_loadCurrentLocation());
    }
  }

  /// Delegates load current location to the ViewModel.
  Future<void> _loadCurrentLocation() =>
      _screenModel.commandLoadCurrentLocation();

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    _map = map;
    _mapView.attach(map);
    try {
      await map.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      await map.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {}
    await _fit();
  }

  /// Computes on style ready.
  Future<void> _onStyleReady() => _mapView.styleLoaded(_prepareMapStyle);

  /// Delegates prepare map style to the ViewModel.
  Future<void> _prepareMapStyle() => _screenModel.commandPrepareMapStyle();

  /// Delegates fit to the ViewModel.
  Future<void> _fit() => _screenModel.commandFit();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _mapView.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final point = _centerPoint;
    if (point == null) {
      if (_isLoadingLocation) {
        return ColoredBox(
          color: _NearbyMapColors.surfaceFor(context),
          child: const HikerCircleLoadingView(
            message: 'Locating this phone…',
            detail: 'Preparing the SOS search radius.',
            compact: true,
          ),
        );
      }
      return ColoredBox(
        color: _NearbyMapColors.surfaceFor(context),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_off_outlined,
                  size: 42,
                  color: _NearbyMapColors.secondaryFor(context),
                ),
                const SizedBox(height: 14),
                Text(
                  'The phone location is unavailable, so the search '
                  'radius cannot be placed on the map.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _NearbyMapColors.textFor(context),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadCurrentLocation,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry location'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        mapbox.MapWidget(
          key: ValueKey('nearby-sos-radius-${widget.event.eventKey}'),
          styleUri: mapStyleUrls.first,
          // ignore: deprecated_member_use
          cameraOptions: mapbox.CameraOptions(center: point, zoom: 15),
          gestureRecognizers: mapGestureRecognizers,
          onMapLoadErrorListener: (event) {
            if (event.type == mapbox.MapLoadErrorType.STYLE) {
              _mapView.styleLoadFailed();
            }
          },
          onMapCreated: _onMapCreated,
          onCameraChangeListener: _mapView.cameraChanged,
          onStyleLoadedListener: (_) => _onStyleReady(),
          onMapLoadedListener: (_) => _onStyleReady(),
        ),
        MapViewOverlay(controller: _mapView, onReset: () => unawaited(_fit())),
        Positioned(
          left: 10,
          right: 10,
          top: 66,
          child: IgnorePointer(
            child: _NearbySurface(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  'Blue area • estimated ${_radiusMeters.round()} m radius',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _NearbyMapColors.textFor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays the nearby surface.
class _NearbySurface extends StatelessWidget {
  /// Creates nearby surface.
  const _NearbySurface({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _NearbyMapColors.surfaceFor(context).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Computes valid location.
SosTriggerLocation? _validLocation(SosTriggerLocation? value) {
  return value?.hasValidPosition == true ? value : null;
}

/// Computes ble radius meters.
double _bleRadiusMeters(int rssi) {
  const referenceRssi = -59.0;
  const pathLossExponent = 2.3;
  final meters =
      30 * math.pow(10, (referenceRssi - rssi) / (10 * pathLossExponent));
  return meters.toDouble().clamp(20, 500);
}

/// Computes radius ring.
List<mapbox.Position> _radiusRing(
  double latitude,
  double longitude,
  double radiusMeters,
) {
  final latDelta = radiusMeters / 111320;
  final lonDelta =
      radiusMeters /
      (111320 * math.cos(latitude * math.pi / 180).clamp(0.2, 1.0));
  return List<mapbox.Position>.generate(49, (index) {
    final angle = 2 * math.pi * index / 48;
    return mapbox.Position(
      longitude + lonDelta * math.cos(angle),
      latitude + latDelta * math.sin(angle),
    );
  });
}

/// Represents nearby map colors.
abstract final class _NearbyMapColors {
  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF0C120F)
      : const Color(0xFFF2F2F7);

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF141C17)
      : Colors.white;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFEAF4EE)
      : const Color(0xFF111111);

  /// Computes secondary for.
  static Color secondaryFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFA8B8AE)
      : const Color(0xFF6E6E73);
}
