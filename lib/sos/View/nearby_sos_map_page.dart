import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/hiking_route_service.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../home/View/first_aid_guide_page.dart';
import '../../trail/Model/trail_models.dart';
import '../Data/location_snapshot_service.dart';
import '../Model/nearby_sos_event.dart';
import '../Model/sos_models.dart';

class NearbySosMapPage extends StatefulWidget {
  const NearbySosMapPage({
    super.key,
    required this.event,
    this.initialPhoneLocation,
    this.routeService,
  });

  final NearbySosEvent event;
  final SosTriggerLocation? initialPhoneLocation;
  final HikingRouteService? routeService;

  @override
  State<NearbySosMapPage> createState() => _NearbySosMapPageState();
}

class _NearbySosMapPageState extends State<NearbySosMapPage> {
  late final HikingRouteService _routeService;
  SosTriggerLocation? _phoneLocation;
  HikingRouteResult? _route;
  Trail? _routeTrail;
  String? _routeError;
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    _routeService = widget.routeService ?? HikingRouteService();
    _phoneLocation = _validLocation(widget.initialPhoneLocation);
    if (widget.event.hasReportedLocation) {
      unawaited(_loadWalkingRoute());
    }
  }

  Future<void> _loadWalkingRoute() async {
    if (_isLoadingRoute || !widget.event.hasReportedLocation) return;
    setState(() {
      _isLoadingRoute = true;
      _routeError = null;
    });
    try {
      final snapshots = LocationSnapshotService.instance;
      final current =
          _validLocation(await snapshots.refresh()) ??
          _validLocation(snapshots.latestLocation) ??
          _validLocation(_phoneLocation);
      if (current == null) {
        throw const HikingRouteServiceException(
          'Current phone location is unavailable. Enable location and retry.',
        );
      }
      final trail = buildNearbySosRouteTrail(
        event: widget.event,
        phoneLocation: current,
      );
      if (!mounted) return;
      setState(() {
        _phoneLocation = current;
        _routeTrail = trail;
      });
      final route = await _routeService
          .findHikingRouteForTrail(trail)
          .timeout(const Duration(seconds: 50));
      if (!mounted) return;
      setState(() => _route = route);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _routeError = 'Walking route providers are taking too long. Retry.';
        });
      }
    } on HikingRouteServiceException catch (error) {
      if (mounted) setState(() => _routeError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _routeError = 'Unable to calculate a walking route right now.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _openExternalDirections() async {
    final target = widget.event.location;
    final origin = _phoneLocation;
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
      if (!launched && mounted) _showOpenError();
    } catch (_) {
      if (mounted) _showOpenError();
    }
  }

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
}

class _RouteMapPlaceholder extends StatelessWidget {
  const _RouteMapPlaceholder({
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _NearbyMapColors.surfaceFor(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const CircularProgressIndicator()
              else
                Icon(
                  Icons.location_off_outlined,
                  size: 42,
                  color: _NearbyMapColors.secondaryFor(context),
                ),
              const SizedBox(height: 14),
              Text(
                isLoading
                    ? 'Getting your location for the emergency map…'
                    : errorMessage ?? 'The emergency map is unavailable.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _NearbyMapColors.textFor(context),
                ),
              ),
              if (!isLoading) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry location'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
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

class _NearbyMapHeader extends StatelessWidget {
  const _NearbyMapHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Nearby SOS route',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _NearbyMapColors.textFor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Icon(Icons.sos_rounded, color: Color(0xFFFF3B30)),
        ],
      ),
    );
  }
}

class _WalkingRouteStatusCard extends StatelessWidget {
  const _WalkingRouteStatusCard({
    required this.route,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final HikingRouteResult? route;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    return _NearbySurface(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            const Icon(
              Icons.directions_walk_rounded,
              color: Color(0xFF34A853),
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route != null ? 'Walking route ready' : 'Walking route',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _NearbyMapColors.textFor(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    route != null
                        ? '${route.distanceLabel} • about ${route.durationLabel}'
                        : isLoading
                        ? 'Calculating distance and estimated time…'
                        : errorMessage ?? 'Waiting for current phone location…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _NearbyMapColors.secondaryFor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (errorMessage != null)
              IconButton(
                tooltip: 'Retry walking route',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadiusExplanationCard extends StatelessWidget {
  const _RadiusExplanationCard();

  @override
  Widget build(BuildContext context) {
    return _NearbySurface(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFF0A84FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'The button did not provide a GPS location, so an exact '
                'direction or walking route cannot be calculated. The blue '
                'area shows the estimated reception radius.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _NearbyMapColors.textFor(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbySosRadiusMap extends StatefulWidget {
  const _NearbySosRadiusMap({
    required this.event,
    required this.initialPhoneLocation,
  });

  final NearbySosEvent event;
  final SosTriggerLocation? initialPhoneLocation;

  @override
  State<_NearbySosRadiusMap> createState() => _NearbySosRadiusMapState();
}

class _NearbySosRadiusMapState extends State<_NearbySosRadiusMap> {
  mapbox.MapboxMap? _map;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PolygonAnnotationManager? _polygonManager;
  SosTriggerLocation? _centerLocation;
  bool _styleLoaded = false;
  bool _isLoadingLocation = false;

  double get _radiusMeters => _bleRadiusMeters(widget.event.rssi ?? -70);

  mapbox.Point? get _centerPoint {
    final location = _validLocation(_centerLocation);
    if (location == null) return null;
    return mapbox.Point(
      coordinates: mapbox.Position(location.longitude, location.latitude),
    );
  }

  @override
  void initState() {
    super.initState();
    _centerLocation =
        _validLocation(widget.event.detectorLocation) ??
        _validLocation(widget.initialPhoneLocation);
    if (_centerLocation == null) {
      unawaited(_loadCurrentLocation());
    }
  }

  Future<void> _loadCurrentLocation() async {
    if (_isLoadingLocation) return;
    setState(() => _isLoadingLocation = true);
    final snapshots = LocationSnapshotService.instance;
    final location =
        _validLocation(await snapshots.refresh()) ??
        _validLocation(snapshots.latestLocation);
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = false;
      _centerLocation = location;
    });
    if (location == null) return;
    await _render();
    await _fit();
  }

  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    _map = map;
    try {
      await map.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      await map.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: false,
        ),
      );
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {}
    await _fit();
  }

  Future<void> _onStyleReady() async {
    _styleLoaded = true;
    _circleManager = null;
    _polygonManager = null;
    await _ensureManagers();
    await _render();
  }

  Future<bool> _ensureManagers() async {
    final map = _map;
    if (map == null || !_styleLoaded) return false;
    try {
      _circleManager ??= await map.annotations.createCircleAnnotationManager();
      _polygonManager ??= await map.annotations
          .createPolygonAnnotationManager();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _render() async {
    if (!await _ensureManagers()) return;
    final point = _centerPoint;
    if (point == null) return;
    final latitude = point.coordinates[1]!.toDouble();
    final longitude = point.coordinates[0]!.toDouble();
    try {
      await _circleManager?.deleteAll();
      await _polygonManager?.deleteAll();
      await _polygonManager?.create(
        mapbox.PolygonAnnotationOptions(
          geometry: mapbox.Polygon(
            coordinates: [_radiusRing(latitude, longitude, _radiusMeters)],
          ),
          fillColor: const Color(0xFF0A84FF).toARGB32(),
          fillOpacity: 0.18,
          fillOutlineColor: const Color(0xFF0A84FF).toARGB32(),
        ),
      );
      await _circleManager?.create(
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

  Future<void> _fit() async {
    final map = _map;
    final point = _centerPoint;
    if (map == null || point == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          center: point,
          zoom: (16 - math.log(_radiusMeters / 50) / math.ln2).clamp(11, 18),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final point = _centerPoint;
    if (point == null) {
      return ColoredBox(
        color: _NearbyMapColors.surfaceFor(context),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingLocation)
                  const CircularProgressIndicator()
                else
                  Icon(
                    Icons.location_off_outlined,
                    size: 42,
                    color: _NearbyMapColors.secondaryFor(context),
                  ),
                const SizedBox(height: 14),
                Text(
                  _isLoadingLocation
                      ? 'Locating the phone to place the blue search radius…'
                      : 'The phone location is unavailable, so the search '
                            'radius cannot be placed on the map.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _NearbyMapColors.textFor(context),
                  ),
                ),
                if (!_isLoadingLocation) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _loadCurrentLocation,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry location'),
                  ),
                ],
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
          viewport: mapbox.CameraViewportState(center: point, zoom: 15),
          gestureRecognizers: mapGestureRecognizers,
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: (_) => _onStyleReady(),
          onMapLoadedListener: (_) => _onStyleReady(),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _NearbySurface(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ],
    );
  }
}

class _NearbySurface extends StatelessWidget {
  const _NearbySurface({required this.child});

  final Widget child;

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

SosTriggerLocation? _validLocation(SosTriggerLocation? value) {
  return value?.hasValidPosition == true ? value : null;
}

double _bleRadiusMeters(int rssi) {
  const referenceRssi = -59.0;
  const pathLossExponent = 2.3;
  final meters =
      30 * math.pow(10, (referenceRssi - rssi) / (10 * pathLossExponent));
  return meters.toDouble().clamp(20, 500);
}

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

abstract final class _NearbyMapColors {
  static Color backgroundFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF0C120F)
      : const Color(0xFFF2F2F7);

  static Color surfaceFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF141C17)
      : Colors.white;

  static Color textFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFEAF4EE)
      : const Color(0xFF111111);

  static Color secondaryFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFA8B8AE)
      : const Color(0xFF6E6E73);
}
