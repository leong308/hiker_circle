// ResidentialCityPickerPage searches and confirms a geocoded residential city selection.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_view_controller.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/state_boundary_overlay.dart';
import '../../trail/Model/malaysia_map_region.dart';
import '../Data/google_city_geocoding_service.dart';

/// Keep the geocoded city selection distinct from raw search text until the user confirms it.
class ResidentialCityPickerPage extends StatefulWidget {
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

  @override
  State<ResidentialCityPickerPage> createState() =>
      _ResidentialCityPickerPageState();
}

class _ResidentialCityPickerPageState extends State<ResidentialCityPickerPage> {
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
  MalaysiaMapRegion _focusRegion = MalaysiaMapRegion.peninsula;
  int _focusRevision = 0;
  bool _hasSelectedRegion = false;
  bool get _hasInitialLocation =>
      widget.initialLatitude != null &&
      widget.initialLongitude != null &&
      mapPointCoordinatesOrNull(
            mapbox.Point(
              coordinates: mapbox.Position(
                widget.initialLongitude!,
                widget.initialLatitude!,
              ),
            ),
          ) !=
          null;

  late mapbox.Point _selected;
  late final mapbox.CameraOptions _initialCameraOptions;
  double _currentZoom = 5.4;
  double _scaleLatitude = _defaultLatitude;
  late final GoogleCityGeocodingService _geocodingService =
      widget.geocodingService ?? GoogleCityGeocodingService();
  mapbox.MapboxMap? _mapboxMap;
  bool _isResolving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _mapView.dispose();
    _focusRevision++;
    _stateBoundary.dispose();
    _mapboxMap = null;
    super.dispose();
  }

  double get _selectedLat =>
      mapPointCoordinatesOrNull(_selected)?.latitude ?? _defaultLatitude;
  double get _selectedLng =>
      mapPointCoordinatesOrNull(_selected)?.longitude ?? _defaultLongitude;

  void _movePin(mapbox.Point coordinate) {
    final values = mapPointCoordinatesOrNull(coordinate);
    if (!mounted || _isResolving || values == null) return;
    final safeCoordinate = mapbox.Point(
      coordinates: mapbox.Position(values.longitude, values.latitude),
    );
    setState(() {
      _selected = safeCoordinate;
      _errorMessage = null;
    });
    unawaited(_centerMapOn(safeCoordinate));
  }

  Future<void> _centerMapOn(mapbox.Point coordinate) async {
    final map = _mapboxMap;
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
        Navigator.of(context).pop(selection);
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

  Future<void> _fitToPin() async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(center: _selected, zoom: 14),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      return;
    }
    await _syncScaleFromCamera();
  }

  Future<void> _zoomBy(double amount) async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          zoom: (_currentZoom + amount)
              .clamp(kMapMinZoom, kMapMaxZoom)
              .toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      return;
    }
    await _syncScaleFromCamera();
  }

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

  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      if (!mounted || !identical(map, _mapboxMap)) return;
      _updateScaleValues(state.zoom, state.center);
    } catch (_) {
      // Map replacement can invalidate an in-flight camera request.
    }
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    _updateScaleValues(data.cameraState.zoom, data.cameraState.center);
  }

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

  Future<void> _focusOnRegion({int duration = 450}) async {
    final map = _mapboxMap;
    if (map == null) return;
    final region = _focusRegion;
    final revision = ++_focusRevision;
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
          !identical(map, _mapboxMap) ||
          revision != _focusRevision) {
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

  Future<void> _updateStateBoundary(Future<void> update) async {
    try {
      await update;
    } catch (error) {
      debugPrint('Residential city boundary failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'State outline could not load. You can still choose your city.',
          ),
        ),
      );
    }
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    if (!mounted) return;
    _mapboxMap = mapboxMap;
    _mapView.attach(mapboxMap);
    mapboxMap.addInteraction(
      mapbox.TapInteraction.onMap((context) => _movePin(context.point)),
    );
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: true),
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
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: MapViewControls(
                        controller: _mapView,
                        zoomControls: MapZoomControls(
                          onZoomIn: () => _zoomBy(1),
                          onZoomOut: () => _zoomBy(-1),
                          onReset: _fitToPin,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: MapViewScale(controller: _mapView),
                    ),
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
}
