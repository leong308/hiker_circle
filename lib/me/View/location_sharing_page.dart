// LocationSharingPage manages the share link and presents the latest device position.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../core/config/google_api_config.dart';
import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_endpoint_marker.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/gps_starting_progress.dart';
import '../Data/live_location_sharing_service.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../home/Model/location_update_interval.dart';

/// Drive link visibility and stop controls from LiveLocationSharingService's confirmed state.
class LocationSharingPage extends StatefulWidget {
  const LocationSharingPage({
    super.key,
    required this.phoneNumber,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.sharingService,
  });

  final String phoneNumber;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final LiveLocationSharingService? sharingService;

  @override
  State<LocationSharingPage> createState() => _LocationSharingPageState();
}

class _LocationSharingPageState extends State<LocationSharingPage> {
  final LocationSnapshotService _locationService =
      LocationSnapshotService.instance;
  late final LiveLocationSharingService _liveLocationSharingService =
      widget.sharingService ?? LiveLocationSharingService.instance;
  SosTriggerLocation? _location;
  bool _isLoading = true;
  bool _isStartingLiveLocation = false;
  String? _errorMessage;

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

  @override
  void dispose() {
    _liveLocationSharingService.removeListener(_refresh);
    super.dispose();
  }

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

  Future<void> _shareLiveLocation() async {
    if (_isStartingLiveLocation) return;
    if (!_liveLocationSharingService.isActive) {
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
    );
    _showLiveLocationMessage(fallbackMessage: 'Live location link ready.');
  }

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

  Future<void> _setUpdateInterval(Duration interval) async {
    final saved = await _liveLocationSharingService.setUpdateInterval(interval);
    _showLiveLocationMessage(
      fallbackMessage: saved
          ? 'Location update interval saved.'
          : 'Unable to save the location update interval. Try again.',
    );
  }

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
                            onRefresh: () => unawaited(_refreshLocation()),
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
    child: PageHeader(
      title: 'Location Sharing',
      subtitle: 'Live GPS position with map pin',
      onBack: onBack,
    ),
  );
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.location,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
  });

  final SosTriggerLocation? location;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (location case final location?)
              _LiveLocationMap(location: location)
            else
              ColoredBox(color: _LocationColors.mapFallbackFor(context)),
            if (location == null) const Center(child: _MapPin()),
            if (isLoading)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: const Center(
                  child: HikerCircleMinorLoadingIndicator(size: 24),
                ),
              ),
            if (errorMessage case final errorMessage?)
              Align(
                alignment: Alignment.bottomCenter,
                child: _MapMessage(message: errorMessage),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Tooltip(
                message: 'Refresh location',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(38),
                  onPressed: isLoading ? null : onRefresh,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _LocationColors.surfaceFor(
                        context,
                      ).withValues(alpha: 0.94),
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const SizedBox.square(
                      dimension: 38,
                      child: Icon(
                        Icons.my_location_rounded,
                        color: _LocationColors.green,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLocationMap extends StatefulWidget {
  const _LiveLocationMap({required this.location});
  final SosTriggerLocation location;

  @override
  State<_LiveLocationMap> createState() => _LiveLocationMapState();
}

class _LiveLocationMapState extends State<_LiveLocationMap> {
  mapbox.MapboxMap? _map;
  mapbox.PointAnnotationManager? _pinManager;
  mapbox.PointAnnotation? _pin;
  bool _failed = false;
  Timer? _loadTimeout;
  int _styleIndex = 0;
  int _generation = 0;
  double _zoom = 16;
  late double _scaleLatitude = widget.location.latitude;
  bool _followLocation = true;

  mapbox.Point get _center => mapbox.Point(
    coordinates: mapbox.Position(
      widget.location.longitude,
      widget.location.latitude,
    ),
  );

  @override
  void initState() {
    super.initState();
    _startLoadTimeout();
  }

  void _startLoadTimeout() {
    _loadTimeout?.cancel();
    final generation = _generation;
    _loadTimeout = Timer(const Duration(seconds: 15), () {
      if (_generation == generation) _fallback();
    });
  }

  void _fallback() {
    _loadTimeout?.cancel();
    if (mounted && !_failed) {
      setState(() {
        _failed = true;
        _map = null;
        _pinManager = null;
        _pin = null;
      });
    }
  }

  @override
  void didUpdateWidget(_LiveLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.latitude != widget.location.latitude ||
        oldWidget.location.longitude != widget.location.longitude) {
      unawaited(_updatePin());
      if (_followLocation) unawaited(_followLatestLocation());
    }
  }

  Future<void> _recenter() async {
    _followLocation = true;
    try {
      await _map?.flyTo(
        mapbox.CameraOptions(center: _center, zoom: 16, bearing: 0, pitch: 0),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // A style switch can dispose the old map during a camera operation.
    }
  }

  Future<void> _followLatestLocation() async {
    try {
      await _map?.setCamera(mapbox.CameraOptions(center: _center));
    } catch (_) {
      // A replaced map is centered when its new instance is created.
    }
  }

  bool _isCurrentMap(mapbox.MapboxMap map, int generation) =>
      mounted && !_failed && generation == _generation && identical(map, _map);

  Future<void> _onMapCreated(mapbox.MapboxMap map, int generation) async {
    if (!mounted || generation != _generation || _failed) return;
    _map = map;
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

  Future<void> _onStyleLoaded(int generation) async {
    final map = _map;
    if (map == null || !_isCurrentMap(map, generation)) return;
    try {
      final manager = await map.annotations.createPointAnnotationManager();
      if (!_isCurrentMap(map, generation)) return;
      _pinManager = manager;
      await manager.setIconAllowOverlap(true);
      await _updatePin();
    } catch (_) {
      if (_isCurrentMap(map, generation)) _fallback();
    }
  }

  Future<void> _updatePin() async {
    final map = _map;
    final manager = _pinManager;
    final generation = _generation;
    if (map == null || manager == null) return;
    try {
      final pin = _pin;
      if (pin == null) {
        final image = await routeEndpointPinImage();
        if (!_isCurrentMap(map, generation) ||
            !identical(manager, _pinManager)) {
          return;
        }
        final created = await manager.create(
          mapbox.PointAnnotationOptions(
            geometry: _center,
            image: image,
            iconAnchor: mapbox.IconAnchor.BOTTOM,
            iconSize: 0.6,
          ),
        );
        if (_isCurrentMap(map, generation)) _pin = created;
      } else {
        pin.geometry = _center;
        await manager.update(pin);
      }
    } catch (_) {
      // Keep the last confirmed map pin if the map is being replaced.
    }
  }

  Future<void> _zoomBy(double amount) async {
    _followLocation = false;
    try {
      await _map?.flyTo(
        mapbox.CameraOptions(
          zoom: (_zoom + amount).clamp(kMapMinZoom, kMapMaxZoom).toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // The style may have changed while zooming.
    }
  }

  void _cycleStyle() {
    setState(() {
      _styleIndex = (_styleIndex + 1) % mapStyleUrls.length;
      _generation += 1;
      _map = null;
      _pinManager = null;
      _pin = null;
    });
    _startLoadTimeout();
  }

  void _cameraChanged(mapbox.CameraChangedEventData event, int generation) {
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

  @override
  void dispose() {
    _loadTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !GoogleApiConfig.hasMapboxAccessToken) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _OpenStreetMap(location: widget.location),
          const Center(child: _MapPin()),
        ],
      );
    }
    final generation = _generation;
    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: ValueKey('live-location-$_styleIndex-$generation'),
            styleUri: mapStyleUrls[_styleIndex],
            gestureRecognizers: mapGestureRecognizers,
            onMapCreated: (map) => _onMapCreated(map, generation),
            onStyleLoadedListener: (_) => unawaited(_onStyleLoaded(generation)),
            onMapLoadedListener: (_) {
              if (_generation == generation) _loadTimeout?.cancel();
            },
            onMapLoadErrorListener: (_) {
              if (_generation == generation) _fallback();
            },
            onCameraChangeListener: (event) =>
                _cameraChanged(event, generation),
            onScrollListener: (_) => _followLocation = false,
            onZoomListener: (_) => _followLocation = false,
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: MapZoomControls(
            onZoomIn: () => unawaited(_zoomBy(1)),
            onZoomOut: () => unawaited(_zoomBy(-1)),
            onReset: () => unawaited(_recenter()),
            onLayer: _cycleStyle,
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: MapScaleBar(zoom: _zoom, latitude: _scaleLatitude),
        ),
      ],
    );
  }
}

class _OpenStreetMap extends StatelessWidget {
  const _OpenStreetMap({required this.location});

  static const int _zoom = 16;
  static const double _tileSize = 256;

  final SosTriggerLocation location;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerTile = _tileCoordinate(
          latitude: location.latitude,
          longitude: location.longitude,
          zoom: _zoom,
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
                        zoom: _zoom,
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
                bottom: 8,
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

  static String _tileUrl({required int zoom, required int x, required int y}) {
    final tileCount = math.pow(2, zoom).toInt();
    final wrappedX = x % tileCount;
    final normalizedX = wrappedX < 0 ? wrappedX + tileCount : wrappedX;
    return 'https://tile.openstreetmap.org/$zoom/$normalizedX/$y.png';
  }
}

class _TileCoordinate {
  const _TileCoordinate({required this.x, required this.y});

  final double x;
  final double y;
}

class _MapPin extends StatelessWidget {
  const _MapPin();

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

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.message});

  final String message;

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

class _LocationDetails extends StatelessWidget {
  const _LocationDetails({required this.location, required this.isLoading});

  final SosTriggerLocation? location;
  final bool isLoading;

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

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _LiveLocationControls extends StatelessWidget {
  const _LiveLocationControls({
    required this.isActive,
    required this.isBusy,
    required this.isSharing,
    required this.shareUrl,
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
                    ? 'Shared with this hike’s footprint upload interval. Each uploaded batch updates your saved route and live location together. GPS stays recorded on this phone every 5 seconds.'
                    : 'The same interval is used for live location and footprint uploads during hikes. GPS is recorded on this phone every 5 seconds while hiking.',
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

abstract final class _LocationColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color mapFallback = Color(0xFFEAF7EE);
  static const Color pin = Color(0xFFFF3B30);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color destructive = Color(0xFFFF3B30);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color mapFallbackFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF102217) : mapFallback;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;
}
