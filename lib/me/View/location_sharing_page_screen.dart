part of '../location_sharing_page_feature.dart';

/// Drive link visibility and stop controls from LiveLocationSharingService's confirmed state.
class LocationSharingPage extends StatefulWidget {
  /// Creates location sharing page.
  const LocationSharingPage({
    super.key,
    required this.phoneNumber,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.sharingService,
  });

  final String phoneNumber;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final LiveLocationSharingService? sharingService;

  /// Creates the presentation state for this widget.
  @override
  State<LocationSharingPage> createState() => _LocationSharingPageState();
}

/// Manages the location sharing page presentation and lifecycle.
class _LocationSharingPageState extends State<LocationSharingPage> {
  final LocationSnapshotService _locationService =
      LocationSnapshotService.instance;
  late final LiveLocationSharingService _liveLocationSharingService =
      widget.sharingService ?? LiveLocationSharingService.instance;
  SosTriggerLocation? _location;
  bool _isLoading = true;
  bool _isStartingLiveLocation = false;
  String? _errorMessage;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _liveLocationSharingService.addListener(_refresh);
    _location =
        _liveLocationSharingService.latestHikeLocation ??
        _locationService.latestLocation;
    _isLoading = _location == null;
    unawaited(
      _liveLocationSharingService.loadExisting(
        phoneNumber: widget.phoneNumber,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    if (_liveLocationSharingService.hasActiveHike) {
      _location ??= _liveLocationSharingService.share?.latestLocation;
      _isLoading = false;
    } else {
      unawaited(_refreshLocation());
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _liveLocationSharingService.removeListener(_refresh);
    super.dispose();
  }

  /// Refreshes.
  void _refresh() {
    if (mounted) {
      setState(() {
        _location =
            _liveLocationSharingService.latestHikeLocation ??
            _locationService.latestLocation ??
            _liveLocationSharingService.share?.latestLocation ??
            _location;
      });
    }
  }

  /// Refreshes location.
  Future<SosTriggerLocation?> _refreshLocation() async {
    if (!mounted) {
      return _location;
    }
    if (_isLoading && _location != null) {
      return _location;
    }

    if (_liveLocationSharingService.hasActiveHike) {
      _refresh();
      return _location;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final location = await _locationService.refresh();
      if (!mounted) {
        return _location;
      }

      setState(() {
        _location = location;
        _isLoading = false;
        _errorMessage = location == null
            ? 'Location unavailable. Check GPS and location permission.'
            : null;
      });
      return location;
    } catch (_) {
      if (!mounted) {
        return _location;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Unable to refresh your live location. Try again in a moment.';
      });
      return _location;
    }
  }

  /// Delegate start/stop intent to LiveLocationSharingService instead of toggling the visible link alone.
  Future<void> _toggleLiveLocation() async {
    if (_isStartingLiveLocation) return;
    if (_liveLocationSharingService.isActive) {
      await _liveLocationSharingService.deactivate();
    } else {
      await _startLiveLocation();
    }

    _showLiveLocationMessage();
  }

  /// Computes share live location.
  Future<void> _shareLiveLocation() async {
    if (_isStartingLiveLocation) return;
    final renewExisting = _liveLocationSharingService.isActive;
    if (!renewExisting) {
      await _startLiveLocation();
      if (!mounted) return;
      if (!_liveLocationSharingService.isActive) {
        _showLiveLocationMessage();
        return;
      }
    }
    await _liveLocationSharingService.shareLiveLocation(
      phoneNumber: widget.phoneNumber,
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
      renewExisting: renewExisting,
    );
    _showLiveLocationMessage(fallbackMessage: 'Live location link ready.');
  }

  /// Starts live location.
  Future<void> _startLiveLocation() async {
    if (_isStartingLiveLocation || _liveLocationSharingService.isBusy) return;
    setState(() => _isStartingLiveLocation = true);
    try {
      await _liveLocationSharingService.activate(
        phoneNumber: widget.phoneNumber,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      );
    } finally {
      if (mounted) setState(() => _isStartingLiveLocation = false);
    }
  }

  /// Save the default preference separately from the current share's active state.
  Future<void> _setAutoShareOnHikeStart(bool enabled) async {
    await _liveLocationSharingService.setAutoShareOnHikeStart(
      phoneNumber: widget.phoneNumber,
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
      enabled: enabled,
    );
    _showLiveLocationMessage(
      fallbackMessage: enabled
          ? 'Automatic hike-start sharing is on.'
          : 'Automatic hike-start sharing is off.',
    );
  }

  /// Sets update interval.
  Future<void> _setUpdateInterval(Duration interval) async {
    final saved = await _liveLocationSharingService.setUpdateInterval(interval);
    _showLiveLocationMessage(
      fallbackMessage: saved
          ? 'Location update interval saved.'
          : 'Unable to save the location update interval. Try again.',
    );
  }

  /// Shows live location message.
  void _showLiveLocationMessage({String? fallbackMessage}) {
    if (!mounted) {
      return;
    }

    final errorMessage = _liveLocationSharingService.errorMessage;
    final message =
        errorMessage ??
        fallbackMessage ??
        (_liveLocationSharingService.isActive
            ? 'Live location active.'
            : 'Live location stopped.');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: errorMessage == null
              ? _LocationColors.green
              : _LocationColors.destructive,
        ),
      );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isStartingLiveLocation,
      child: Scaffold(
        backgroundColor: _LocationColors.backgroundFor(context),
        body: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(onBack: () => Navigator.of(context).pop()),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 250,
                          child: _MapPanel(
                            location: _location,
                            isLoading: _isLoading,
                            errorMessage: _errorMessage,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _LocationDetails(
                          location: _location,
                          isLoading: _isLoading,
                        ),
                        const SizedBox(height: 14),
                        _LiveLocationControls(
                          isActive: _liveLocationSharingService.isActive,
                          isBusy:
                              _isStartingLiveLocation ||
                              _liveLocationSharingService.isBusy,
                          isSharing: _liveLocationSharingService.isSharing,
                          shareUrl: _liveLocationSharingService.share?.shareUrl,
                          expiresAt:
                              _liveLocationSharingService.share?.expiresAt,
                          autoShareOnHikeStart:
                              _liveLocationSharingService.autoShareOnHikeStart,
                          isPreferenceBusy:
                              _liveLocationSharingService.isPreferenceBusy,
                          updateInterval:
                              _liveLocationSharingService.updateInterval,
                          hasActiveHike:
                              _liveLocationSharingService.hasActiveHike,
                          contactNotificationStatus: _liveLocationSharingService
                              .contactNotificationStatus,
                          isNotifyingContacts:
                              _liveLocationSharingService.isNotifyingContacts,
                          canRetryContactNotifications:
                              _liveLocationSharingService
                                  .canRetryContactNotifications,
                          onRetryContactNotifications: () => unawaited(
                            _liveLocationSharingService
                                .retryStandaloneContactNotifications(),
                          ),
                          onUpdateIntervalChanged: (interval) =>
                              unawaited(_setUpdateInterval(interval)),
                          onToggle: () => unawaited(_toggleLiveLocation()),
                          onShare: () => unawaited(_shareLiveLocation()),
                          onAutoShareChanged: (value) =>
                              unawaited(_setAutoShareOnHikeStart(value)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isStartingLiveLocation)
              const GpsStartingOverlay(
                title: 'Starting live location…',
                message:
                    'Getting your GPS position and activating your sharing link. This may take a few seconds.',
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays the live location map.
class _LiveLocationMap extends StatefulWidget {
  /// Creates live location map.
  const _LiveLocationMap({required this.location});
  final SosTriggerLocation location;

  /// Creates the presentation state for this widget.
  @override
  State<_LiveLocationMap> createState() => _LiveLocationMapState();
}

/// Manages the live location map presentation and lifecycle.
class _LiveLocationMapState extends State<_LiveLocationMap> {
  late final _LiveLocationMapStateViewModel _screenModel;

  /// Returns map.
  mapbox.MapboxMap? get _map => _screenModel.stateMap;

  /// Updates map.
  set _map(mapbox.MapboxMap? value) => _screenModel.stateMap = value;

  /// Returns pin manager.
  mapbox.PointAnnotationManager? get _pinManager =>
      _screenModel.statePinManager;

  /// Updates pin manager.
  set _pinManager(mapbox.PointAnnotationManager? value) =>
      _screenModel.statePinManager = value;

  /// Updates pin.
  set _pin(mapbox.PointAnnotation? value) => _screenModel.statePin = value;

  /// Returns failed.
  bool get _failed => _screenModel.stateFailed;

  /// Returns load timeout.
  Timer? get _loadTimeout => _screenModel.stateLoadTimeout;

  /// Returns generation.
  int get _generation => _screenModel.stateGeneration;

  /// Returns zoom.
  double get _zoom => _screenModel.stateZoom;

  /// Updates zoom.
  set _zoom(double value) => _screenModel.stateZoom = value;

  /// Returns follow location.
  bool get _followLocation => _screenModel.stateFollowLocation;

  /// Updates follow location.
  set _followLocation(bool value) => _screenModel.stateFollowLocation = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: const MapViewSettings(dimension: MapDimension.twoD),
    onBeforeStyleReload: () async {
      final manager = _pinManager;
      _pinManager = null;
      _pin = null;
      await removeMapAnnotationManagers(_map, [manager]);
    },
  );

  late double _scaleLatitude = widget.location.latitude;

  /// Returns center.
  mapbox.Point get _center => _screenModel.commandCenter;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _LiveLocationMapStateViewModel(
      readLocation: () => widget.location,
    )..addListener(_renderScreenModel);

    _startLoadTimeout();
  }

  /// Delegates start load timeout to the ViewModel.
  void _startLoadTimeout() => _screenModel.commandStartLoadTimeout();

  /// Delegates fallback to the ViewModel.
  void _fallback() => _screenModel.commandFallback();

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(_LiveLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.latitude != widget.location.latitude ||
        oldWidget.location.longitude != widget.location.longitude) {
      unawaited(_updatePin());
      if (_followLocation) unawaited(_followLatestLocation());
    }
  }

  /// Computes recenter.
  Future<void> _recenter() async {
    _followLocation = true;
    try {
      await _map?.flyTo(
        mapbox.CameraOptions(
          center: _center,
          zoom: 16,
          bearing: 0,
          pitch: _mapView.settings.is3D ? 50 : 0,
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // A style switch can dispose the old map during a camera operation.
    }
  }

  /// Delegates follow latest location to the ViewModel.
  Future<void> _followLatestLocation() =>
      _screenModel.commandFollowLatestLocation();

  /// Delegates is current map to the ViewModel.
  bool _isCurrentMap(mapbox.MapboxMap map, int generation) =>
      _screenModel.commandIsCurrentMap(map, generation);

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap map, int generation) async {
    if (!mounted || generation != _generation || _failed) return;
    _map = map;
    _mapView.attach(map);
    try {
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
      if (_isCurrentMap(map, generation)) {
        await map.setCamera(
          mapbox.CameraOptions(center: _center, zoom: _zoom, pitch: 0),
        );
      }
    } catch (_) {
      if (_isCurrentMap(map, generation)) _fallback();
    }
  }

  /// Computes on style loaded.
  Future<void> _onStyleLoaded(int generation) =>
      _mapView.styleLoaded(() => _prepareNativeStyle(generation));

  /// Delegates prepare native style to the ViewModel.
  Future<void> _prepareNativeStyle(int generation) =>
      _screenModel.commandPrepareNativeStyle(generation);

  /// Delegates update pin to the ViewModel.
  Future<void> _updatePin() => _screenModel.commandUpdatePin();

  /// Delegates zoom by to the ViewModel.
  Future<void> _zoomBy(double amount) => _screenModel.commandZoomBy(amount);

  /// Computes camera changed.
  void _cameraChanged(mapbox.CameraChangedEventData event, int generation) {
    _mapView.cameraChanged(event);
    final latitude = mapPointCoordinatesOrNull(
      event.cameraState.center,
    )?.latitude;
    final zoom = event.cameraState.zoom;
    if (!mounted ||
        generation != _generation ||
        latitude == null ||
        !zoom.isFinite) {
      return;
    }
    if ((_zoom - zoom).abs() < 0.005 &&
        (_scaleLatitude - latitude).abs() < 0.0005) {
      return;
    }
    setState(() {
      _zoom = zoom;
      _scaleLatitude = latitude;
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _loadTimeout?.cancel();
    _mapView.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (_failed || !GoogleApiConfig.hasMapboxAccessToken) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _OpenStreetMap(
            location: widget.location,
            zoom: _zoom.round().clamp(3, 19),
          ),
          const Center(child: _MapPin()),
          MapControlOverlay(
            zoomControls: MapZoomControls(
              onZoomIn: () => unawaited(_zoomBy(1)),
              onZoomOut: () => unawaited(_zoomBy(-1)),
              onReset: () => setState(() => _zoom = 16),
            ),
            styleControls: IgnorePointer(
              child: Opacity(
                opacity: .5,
                child: MapStyleControls(
                  settings: const MapViewSettings(dimension: MapDimension.twoD),
                  onChanged: (_) {},
                ),
              ),
            ),
            scale: MapScaleWithStyle(
              zoom: _zoom.round().clamp(3, 19).toDouble(),
              latitude: widget.location.latitude,
              settings: const MapViewSettings(dimension: MapDimension.twoD),
              styleName: 'OpenStreetMap',
            ),
            bearing: 0,
          ),
        ],
      );
    }
    final generation = _generation;
    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: const ValueKey('live-location-map'),
            styleUri: mapStyleUrls[0],
            gestureRecognizers: mapGestureRecognizers,
            onMapCreated: (map) => _onMapCreated(map, generation),
            onStyleLoadedListener: (_) => unawaited(_onStyleLoaded(generation)),
            onMapLoadedListener: (_) {
              if (_generation == generation) _loadTimeout?.cancel();
            },
            onMapLoadErrorListener: (event) {
              if (event.type != mapbox.MapLoadErrorType.STYLE) return;
              if (_mapView.isChanging) {
                _mapView.styleLoadFailed();
              } else if (_generation == generation) {
                _fallback();
              }
            },
            onCameraChangeListener: (event) =>
                _cameraChanged(event, generation),
            onScrollListener: (_) => _followLocation = false,
            onZoomListener: (_) => _followLocation = false,
          ),
        ),
        MapViewOverlay(
          controller: _mapView,
          onZoomIn: () => unawaited(_zoomBy(1)),
          onZoomOut: () => unawaited(_zoomBy(-1)),
          onReset: () => unawaited(_recenter()),
        ),
      ],
    );
  }
}

/// Displays the open street map.
class _OpenStreetMap extends StatelessWidget {
  /// Creates open street map.
  const _OpenStreetMap({required this.location, required this.zoom});

  final int zoom;
  static const double _tileSize = 256;

  final SosTriggerLocation location;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerTile = _tileCoordinate(
          latitude: location.latitude,
          longitude: location.longitude,
          zoom: zoom,
        );
        final baseTileX = centerTile.x.floor();
        final baseTileY = centerTile.y.floor();
        final centerOffsetX = (centerTile.x - baseTileX) * _tileSize;
        final centerOffsetY = (centerTile.y - baseTileY) * _tileSize;
        final gridRadius =
            (math.max(constraints.maxWidth, constraints.maxHeight) /
                    _tileSize /
                    2)
                .ceil() +
            1;
        final left =
            constraints.maxWidth / 2 - centerOffsetX - gridRadius * _tileSize;
        final top =
            constraints.maxHeight / 2 - centerOffsetY - gridRadius * _tileSize;

        return ClipRect(
          child: Stack(
            children: [
              for (var yOffset = -gridRadius; yOffset <= gridRadius; yOffset++)
                for (
                  var xOffset = -gridRadius;
                  xOffset <= gridRadius;
                  xOffset++
                )
                  Positioned(
                    left: left + (xOffset + gridRadius) * _tileSize,
                    top: top + (yOffset + gridRadius) * _tileSize,
                    width: _tileSize,
                    height: _tileSize,
                    child: Image.network(
                      _tileUrl(
                        zoom: zoom,
                        x: baseTileX + xOffset,
                        y: baseTileY + yOffset,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return ColoredBox(
                          color: _LocationColors.mapFallbackFor(context),
                        );
                      },
                    ),
                  ),
              Positioned(
                left: 10,
                bottom: 82,
                child: Text(
                  'OpenStreetMap contributors',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _LocationColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Computes tile coordinate.
  static _TileCoordinate _tileCoordinate({
    required double latitude,
    required double longitude,
    required int zoom,
  }) {
    const maximumMercatorLatitude = 85.05112878;
    final scale = math.pow(2, zoom).toDouble();
    final projectedLatitude = latitude.clamp(
      -maximumMercatorLatitude,
      maximumMercatorLatitude,
    );
    final latitudeRadians = projectedLatitude * math.pi / 180;
    final x = (longitude + 180) / 360 * scale;
    final y =
        (1 -
            math.log(
                  math.tan(latitudeRadians) + 1 / math.cos(latitudeRadians),
                ) /
                math.pi) /
        2 *
        scale;

    return _TileCoordinate(x: x, y: y);
  }

  /// Computes tile url.
  static String _tileUrl({required int zoom, required int x, required int y}) {
    final tileCount = math.pow(2, zoom).toInt();
    final wrappedX = x % tileCount;
    final normalizedX = wrappedX < 0 ? wrappedX + tileCount : wrappedX;
    return 'https://tile.openstreetmap.org/$zoom/$normalizedX/$y.png';
  }
}

/// Displays the map pin.
class _MapPin extends StatelessWidget {
  /// Creates map pin.
  const _MapPin();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: const Icon(
        Icons.location_pin,
        color: _LocationColors.pin,
        size: 48,
        shadows: [
          Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
    );
  }
}

/// Displays the map message.
class _MapMessage extends StatelessWidget {
  /// Creates map message.
  const _MapMessage({required this.message});

  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _LocationColors.surfaceFor(context).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _LocationColors.textFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the location details.
class _LocationDetails extends StatelessWidget {
  /// Creates location details.
  const _LocationDetails({required this.location, required this.isLoading});

  final SosTriggerLocation? location;
  final bool isLoading;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final capturedAt = location?.capturedAt?.toLocal();
    final timestamp = capturedAt == null
        ? 'Waiting for GPS'
        : '${_twoDigits(capturedAt.hour)}:${_twoDigits(capturedAt.minute)}:${_twoDigits(capturedAt.second)}';
    final accuracy = location?.accuracyMeters == null
        ? 'Accuracy unknown'
        : 'Accuracy +/- ${location!.accuracyMeters!.toStringAsFixed(0)} m';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _LocationColors.green,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  isLoading
                      ? Icons.satellite_alt_rounded
                      : Icons.my_location_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location == null
                          ? 'Live location'
                          : '${location!.latitude.toStringAsFixed(6)}, ${location!.longitude.toStringAsFixed(6)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _LocationColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$accuracy - Updated $timestamp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _LocationColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Computes two digits.
  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

/// Displays the live location controls.
class _LiveLocationControls extends StatelessWidget {
  /// Creates live location controls.
  const _LiveLocationControls({
    required this.isActive,
    required this.isBusy,
    required this.isSharing,
    required this.shareUrl,
    required this.expiresAt,
    required this.autoShareOnHikeStart,
    required this.isPreferenceBusy,
    required this.onToggle,
    required this.onShare,
    required this.onAutoShareChanged,
    required this.updateInterval,
    required this.hasActiveHike,
    required this.onUpdateIntervalChanged,
    required this.contactNotificationStatus,
    required this.isNotifyingContacts,
    required this.canRetryContactNotifications,
    required this.onRetryContactNotifications,
  });

  final bool isActive;
  final bool isBusy;
  final bool isSharing;
  final String? shareUrl;
  final DateTime? expiresAt;
  final bool autoShareOnHikeStart;
  final bool isPreferenceBusy;
  final VoidCallback onToggle;
  final VoidCallback onShare;
  final ValueChanged<bool> onAutoShareChanged;
  final Duration updateInterval;
  final bool hasActiveHike;
  final ValueChanged<Duration> onUpdateIntervalChanged;
  final String? contactNotificationStatus;
  final bool isNotifyingContacts;
  final bool canRetryContactNotifications;
  final VoidCallback onRetryContactNotifications;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final statusText = isActive ? 'Live location active' : 'Live location off';
    final linkText = shareUrl ?? 'Firebase live link not created yet';
    final isDisabled = isBusy || isSharing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isActive
                          ? _LocationColors.green
                          : _LocationColors.secondaryTextFor(context),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isActive
                          ? Icons.location_searching_rounded
                          : Icons.location_disabled_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _LocationColors.textFor(context),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          linkText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _LocationColors.secondaryTextFor(
                                  context,
                                ),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0,
                              ),
                        ),
                        if (isActive && expiresAt != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Expires: ${PreferredTimeZone.formatInstant(expiresAt!, AppSettingsController.instance.preferredTimeZone)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _LocationColors.secondaryTextFor(
                                    context,
                                  ),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!hasActiveHike) ...[
                Text(
                  'Activating live location outside a hike sends a WhatsApp update with your live link, phone number and original sharing start time to every saved SOS contact.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _LocationColors.secondaryTextFor(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (contactNotificationStatus case final status?) ...[
                Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isNotifyingContacts)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: HikerCircleMinorLoadingIndicator(size: 18),
                        )
                      else
                        Icon(
                          Icons.info_outline_rounded,
                          size: 19,
                          color: _LocationColors.secondaryTextFor(context),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canRetryContactNotifications)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onRetryContactNotifications,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Retry SOS contact notification'),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              DropdownButtonFormField<Duration>(
                key: ValueKey(updateInterval),
                initialValue: updateInterval,
                decoration: const InputDecoration(
                  labelText: 'Location update interval',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                items: [
                  for (final interval in LocationUpdateInterval.options)
                    DropdownMenuItem(
                      value: interval,
                      child: Text(LocationUpdateInterval.label(interval)),
                    ),
                ],
                onChanged: isDisabled
                    ? null
                    : (interval) {
                        if (interval != null) onUpdateIntervalChanged(interval);
                      },
              ),
              const SizedBox(height: 7),
              Text(
                hasActiveHike
                    ? 'Shared with this hike’s footprint upload interval. Each uploaded batch updates your saved route and live location together. GPS footprints follow the selected interval.'
                    : 'The same interval is used for live location and footprint uploads during hikes. GPS footprints follow the selected interval.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _LocationColors.secondaryTextFor(context),
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: _LocationColors.secondaryTextFor(
                  context,
                ).withValues(alpha: 0.22),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share automatically when a hike starts',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: _LocationColors.textFor(context),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Creates a live link after tracking starts and sends it to every saved SOS contact. This is a safety update, not an SOS alert.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _LocationColors.secondaryTextFor(
                                  context,
                                ),
                                height: 1.35,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CupertinoSwitch(
                    value: autoShareOnHikeStart,
                    activeTrackColor: _LocationColors.green,
                    onChanged: isPreferenceBusy ? null : onAutoShareChanged,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isActive) ...[
                Text(
                  'Share Live renews an active link for 24 hours before opening sharing options.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _LocationColors.secondaryTextFor(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isDisabled ? null : onToggle,
                      icon: Icon(
                        isActive
                            ? Icons.stop_circle_rounded
                            : Icons.power_settings_new_rounded,
                        size: 18,
                      ),
                      label: Text(isActive ? 'Stop Live' : 'Activate Live'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isActive
                            ? _LocationColors.destructive
                            : _LocationColors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isDisabled ? null : onShare,
                      icon: isSharing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: HikerCircleMinorLoadingIndicator(size: 18),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share Live'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _LocationColors.green,
                        minimumSize: const Size(0, 44),
                        side: const BorderSide(color: _LocationColors.green),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Represents location colors.
abstract final class _LocationColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color mapFallback = Color(0xFFEAF7EE);
  static const Color pin = Color(0xFFFF3B30);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color destructive = Color(0xFFFF3B30);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes map fallback for.
  static Color mapFallbackFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF102217) : mapFallback;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;
}
