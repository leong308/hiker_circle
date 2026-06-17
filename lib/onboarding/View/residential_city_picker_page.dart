import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../Data/google_city_geocoding_service.dart';

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
  static const _defaultLatitude = 3.1390;
  static const _defaultLongitude = 101.6869;

  late mapbox.Point _selected = mapbox.Point(
    coordinates: mapbox.Position(
      widget.initialLongitude ?? _defaultLongitude,
      widget.initialLatitude ?? _defaultLatitude,
    ),
  );
  late double _currentZoom = 10.5;
  late double _scaleLatitude =
      widget.initialLatitude ?? _defaultLatitude;
  late final GoogleCityGeocodingService _geocodingService =
      widget.geocodingService ?? GoogleCityGeocodingService();
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleManager;
  bool _isResolving = false;
  String? _errorMessage;

  double get _selectedLat => _selected.coordinates[1]!.toDouble();
  double get _selectedLng => _selected.coordinates[0]!.toDouble();

  void _movePin(mapbox.Point coordinate) {
    setState(() {
      _selected = coordinate;
      _errorMessage = null;
    });
    unawaited(_syncPin());
    unawaited(
      _mapboxMap?.flyTo(
        mapbox.CameraOptions(center: coordinate),
        mapbox.MapAnimationOptions(duration: 300),
      ),
    );
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
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(center: _selected, zoom: 14),
      mapbox.MapAnimationOptions(duration: 300),
    );
    await _syncScaleFromCamera();
  }

  Future<void> _zoomBy(double amount) async {
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(zoom: _currentZoom + amount),
      mapbox.MapAnimationOptions(duration: 300),
    );
    await _syncScaleFromCamera();
  }

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _selected = data.cameraState.center;
    _updateScale(data);
  }

  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    if (map == null) return;
    final state = await map.getCameraState();
    if (!mounted) return;
    final nextZoom = state.zoom;
    final nextLatitude = state.center.coordinates[1]!.toDouble();
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    final nextZoom = data.cameraState.zoom;
    final nextLatitude = data.cameraState.center.coordinates[1]!.toDouble();
    if (!mounted ||
        ((nextZoom - _currentZoom).abs() < 0.005 &&
            (nextLatitude - _scaleLatitude).abs() < 0.0005)) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(
      mapbox.CompassSettings(enabled: true),
    );
    await mapboxMap.logo.updateSettings(
      mapbox.LogoSettings(enabled: false),
    );
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        rotateEnabled: false,
        pitchEnabled: false,
      ),
    );
    await mapboxMap.setBounds(
      mapbox.CameraBoundsOptions(minZoom: 3, maxZoom: 18),
    );
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    await _syncPin();
    await _syncScaleFromCamera();
  }

  Future<void> _syncPin() async {
    await _circleManager?.deleteAll();
    await _circleManager?.create(
      mapbox.CircleAnnotationOptions(
        geometry: _selected,
        circleColor: const Color(0xFFE11D48).toARGB32(),
        circleRadius: 8,
        circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
        circleStrokeWidth: 3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.allowCancel,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: widget.allowCancel,
          title: const Text('Choose residential city'),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DeferredMap(
                    child: mapbox.MapWidget(
                      key: const ValueKey('city-picker'),
                      styleUri: mapStyleUrls[0],
                      onMapCreated: _onMapCreated,
                      onCameraChangeListener: _onCameraChange,
                      onMapIdleListener: (_) => unawaited(_syncScaleFromCamera()),
                      onTapListener: (context) => _movePin(context.point),
                    ),
                  ),
                  const Center(
                    child: IgnorePointer(
                      child: Icon(
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
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 14,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Move the map until the pin is over your city. Exact home address is not required.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: MapZoomControls(
                        onZoomIn: () => _zoomBy(1),
                        onZoomOut: () => _zoomBy(-1),
                        onReset: _fitToPin,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: MapScaleBar(
                        zoom: _currentZoom,
                        latitude: _scaleLatitude,
                      ),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
