part of '../residential_city_picker_page_feature.dart';

/// Keep the geocoded city selection distinct from raw search text until the user confirms it.
class ResidentialCityPickerPage extends StatefulWidget {
  /// Creates residential city picker page.
  const ResidentialCityPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.geocodingService,
    this.allowCancel = false,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final GoogleCityGeocodingService? geocodingService;
  final bool allowCancel;

  /// Creates the presentation state for this widget.
  @override
  State<ResidentialCityPickerPage> createState() =>
      _ResidentialCityPickerPageState();
}

/// Manages the residential city picker page presentation and lifecycle.
class _ResidentialCityPickerPageState extends State<ResidentialCityPickerPage> {
  late final _ResidentialCityPickerPageStateViewModel _screenModel;

  /// Returns focus region.
  MalaysiaMapRegion get _focusRegion => _screenModel.stateFocusRegion;

  /// Updates focus region.
  set _focusRegion(MalaysiaMapRegion value) =>
      _screenModel.stateFocusRegion = value;

  /// Returns focus revision.
  int get _focusRevision => _screenModel.stateFocusRevision;

  /// Updates focus revision.
  set _focusRevision(int value) => _screenModel.stateFocusRevision = value;

  /// Returns selected.
  mapbox.Point get _selected => _screenModel.stateSelected;

  /// Updates selected.
  set _selected(mapbox.Point value) => _screenModel.stateSelected = value;

  /// Returns current zoom.
  double get _currentZoom => _screenModel.stateCurrentZoom;

  /// Updates current zoom.
  set _currentZoom(double value) => _screenModel.stateCurrentZoom = value;

  /// Returns mapbox map.
  mapbox.MapboxMap? get _mapboxMap => _screenModel.stateMapboxMap;

  /// Updates mapbox map.
  set _mapboxMap(mapbox.MapboxMap? value) =>
      _screenModel.stateMapboxMap = value;

  /// Returns is resolving.
  bool get _isResolving => _screenModel.stateIsResolving;

  /// Updates is resolving.
  set _isResolving(bool value) => _screenModel.stateIsResolving = value;

  /// Returns error message.
  String? get _errorMessage => _screenModel.stateErrorMessage;

  /// Updates error message.
  set _errorMessage(String? value) => _screenModel.stateErrorMessage = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: const MapViewSettings(dimension: MapDimension.twoD),
    onBeforeStyleReload: () async {
      final managers = <mapbox.BaseAnnotationManager?>[];

      await removeMapAnnotationManagers(_mapboxMap, managers);
    },
  );

  static final _defaultLatitude = MalaysiaMapRegion.peninsula.latitude;
  static final _defaultLongitude = MalaysiaMapRegion.peninsula.longitude;
  final _stateBoundary = StateBoundaryOverlay();

  bool _hasSelectedRegion = false;

  /// Returns has initial location.
  bool get _hasInitialLocation => _screenModel.commandHasInitialLocation;

  late final mapbox.CameraOptions _initialCameraOptions;

  double _scaleLatitude = _defaultLatitude;
  late final GoogleCityGeocodingService _geocodingService =
      widget.geocodingService ?? GoogleCityGeocodingService();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ResidentialCityPickerPageStateViewModel(
      readInitialLatitude: () => widget.initialLatitude,
      readInitialLongitude: () => widget.initialLongitude,
      effectUpdateScaleValues: _updateScaleValues,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentUpdateStateBoundaryEffect1 =
        _presentUpdateStateBoundaryEffect1;

    final candidate = mapbox.Point(
      coordinates: mapbox.Position(
        _hasInitialLocation ? widget.initialLongitude! : _defaultLongitude,
        _hasInitialLocation ? widget.initialLatitude! : _defaultLatitude,
      ),
    );
    final coordinates = mapPointCoordinatesOrNull(candidate);
    _selected = coordinates == null
        ? mapbox.Point(
            coordinates: mapbox.Position(_defaultLongitude, _defaultLatitude),
          )
        : mapbox.Point(
            coordinates: mapbox.Position(
              coordinates.longitude,
              coordinates.latitude,
            ),
          );
    _scaleLatitude = coordinates?.latitude ?? _defaultLatitude;
    _currentZoom = _hasInitialLocation ? 14 : 5.4;
    _initialCameraOptions = mapbox.CameraOptions(
      center: _selected,
      zoom: _currentZoom,
    );
    unawaited(
      StateBoundaryOverlay.prewarm()
          .then<void>((_) {})
          .catchError((Object _) {}),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _mapView.dispose();
    _focusRevision++;
    _stateBoundary.dispose();
    _mapboxMap = null;

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Returns selected lat.
  double get _selectedLat =>
      mapPointCoordinatesOrNull(_selected)?.latitude ?? _defaultLatitude;

  /// Returns selected lng.
  double get _selectedLng =>
      mapPointCoordinatesOrNull(_selected)?.longitude ?? _defaultLongitude;

  /// Delegates move pin to the ViewModel.
  void _movePin(mapbox.Point coordinate) =>
      _screenModel.commandMovePin(coordinate);

  /// Computes confirm city.
  Future<void> _confirmCity() async {
    if (_isResolving) {
      return;
    }
    setState(() {
      _isResolving = true;
      _errorMessage = null;
    });
    try {
      final selection = await _geocodingService.resolveCity(
        latitude: _selectedLat,
        longitude: _selectedLng,
      );
      if (mounted) {
        _presentConfirmCityEffect1(selection);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  /// Delegates fit to pin to the ViewModel.
  Future<void> _fitToPin() => _screenModel.commandFitToPin();

  /// Delegates zoom by to the ViewModel.
  Future<void> _zoomBy(double amount) => _screenModel.commandZoomBy(amount);

  /// Computes on camera change.
  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _mapView.cameraChanged(data);
    if (!mounted ||
        _isResolving ||
        mapPointCoordinatesOrNull(data.cameraState.center) == null) {
      return;
    }
    _selected = data.cameraState.center;
    _updateScale(data);
  }

  /// Delegates sync scale from camera to the ViewModel.
  Future<void> _syncScaleFromCamera() =>
      _screenModel.commandSyncScaleFromCamera();

  /// Delegates update scale to the ViewModel.
  void _updateScale(mapbox.CameraChangedEventData data) =>
      _screenModel.commandUpdateScale(data);

  /// Updates scale values.
  void _updateScaleValues(double nextZoom, mapbox.Point center) {
    final coordinates = mapPointCoordinatesOrNull(center);
    if (!mounted || !nextZoom.isFinite || coordinates == null) return;
    final nextLatitude = coordinates.latitude;
    if (((nextZoom - _currentZoom).abs() < 0.005 &&
        (nextLatitude - _scaleLatitude).abs() < 0.0005)) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  /// Selects focus region.
  void _selectFocusRegion(MalaysiaMapRegion? region) {
    if (region == null || _isResolving) return;
    setState(() {
      _focusRegion = region;
      _hasSelectedRegion = true;
      _selected = mapbox.Point(
        coordinates: mapbox.Position(region.longitude, region.latitude),
      );
      _errorMessage = null;
    });
    unawaited(_updateStateBoundary(_stateBoundary.select(region)));
    unawaited(_focusOnRegion());
  }

  /// Delegates focus on region to the ViewModel.
  Future<void> _focusOnRegion({int duration = 450}) =>
      _screenModel.commandFocusOnRegion(duration: duration);

  /// Delegates update state boundary to the ViewModel.
  Future<void> _updateStateBoundary(Future<void> update) =>
      _screenModel.commandUpdateStateBoundary(update);

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    if (!mounted) return;
    _mapboxMap = mapboxMap;
    _mapView.attach(mapboxMap);
    mapboxMap.addInteraction(
      mapbox.TapInteraction.onMap((context) => _movePin(context.point)),
    );
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await mapboxMap.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: 3, maxZoom: 18),
      );
    } catch (_) {
      // Camera framing remains available if an optional control fails to initialize.
    }
    if (!mounted || !identical(mapboxMap, _mapboxMap)) return;
    if (_hasInitialLocation && !_hasSelectedRegion) {
      await _fitToPin();
    } else {
      await _focusOnRegion(duration: 0);
    }
    if (!mounted || !identical(mapboxMap, _mapboxMap)) return;
    try {
      if (await mapboxMap.style.isStyleLoaded()) {
        await _updateStateBoundary(_stateBoundary.onStyleLoaded(mapboxMap));
      }
    } catch (_) {
      // The style-loaded event can initialize the boundary once the style is ready.
    }
    await _syncScaleFromCamera();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.allowCancel,
      child: Scaffold(
        appBar: PageHeaderAppBar(
          automaticallyImplyLeading: widget.allowCancel,
          title: const Text('Choose residential city'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<MalaysiaMapRegion>(
                    key: const Key('residential-state-focus'),
                    initialValue: _focusRegion,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Focus on a state',
                      prefixIcon: Icon(Icons.map_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final region in MalaysiaMapRegion.values)
                        DropdownMenuItem(
                          value: region,
                          child: Text(
                            region.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _isResolving ? null : _selectFocusRegion,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Move the map until the pin is over your city. Exact home address is not required.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DeferredMap(
                    child: mapbox.MapWidget(
                      key: const ValueKey('city-picker'),
                      styleUri: mapStyleUrls[0],
                      // ignore: deprecated_member_use
                      cameraOptions: _initialCameraOptions,
                      gestureRecognizers: mapGestureRecognizers,
                      onMapLoadErrorListener: (event) {
                        if (event.type == mapbox.MapLoadErrorType.STYLE) {
                          _mapView.styleLoadFailed();
                        }
                      },
                      onMapCreated: _onMapCreated,
                      onCameraChangeListener: _onCameraChange,
                      onStyleLoadedListener: (_) =>
                          _mapView.styleLoaded(() async {
                            final map = _mapboxMap;
                            if (map != null) {
                              await _updateStateBoundary(
                                _stateBoundary.onStyleLoaded(map),
                              );
                            }
                          }),
                      onMapIdleListener: (_) =>
                          unawaited(_syncScaleFromCamera()),
                    ),
                  ),
                  Center(
                    child: IgnorePointer(
                      child: Transform.translate(
                        offset: const Offset(0, -24),
                        child: const Icon(
                          Icons.location_pin,
                          size: 50,
                          color: Color(0xFFE11D48),
                          shadows: [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  MapViewOverlay(
                    controller: _mapView,
                    onZoomIn: () => unawaited(_zoomBy(1)),
                    onZoomOut: () => unawaited(_zoomBy(-1)),
                    onReset: () => unawaited(_fitToPin()),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton.icon(
                      onPressed: _isResolving ? null : _confirmCity,
                      icon: _isResolving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: HikerCircleMinorLoadingIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.location_city_rounded),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _isResolving ? 'Finding city...' : 'Use this city',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Presents the confirm city effect1 UI.
  void _presentConfirmCityEffect1(ResidentialCitySelection selection) =>
      Navigator.of(context).pop(selection);

  /// Presents the update state boundary effect1 UI.
  void _presentUpdateStateBoundaryEffect1() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'State outline could not load. You can still choose your city.',
          ),
        ),
      );
}
