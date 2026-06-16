import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

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
  static const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';
  static const _defaultLatitude = 3.1390;
  static const _defaultLongitude = 101.6869;

  late maplibre.LatLng _selected = maplibre.LatLng(
    widget.initialLatitude ?? _defaultLatitude,
    widget.initialLongitude ?? _defaultLongitude,
  );
  late final GoogleCityGeocodingService _geocodingService =
      widget.geocodingService ?? GoogleCityGeocodingService();
  maplibre.MapLibreMapController? _mapController;
  bool _isResolving = false;
  String? _errorMessage;

  void _movePin(maplibre.LatLng coordinate) {
    setState(() {
      _selected = coordinate;
      _errorMessage = null;
    });
    unawaited(
      _mapController?.animateCamera(
        maplibre.CameraUpdate.newLatLng(coordinate),
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
        latitude: _selected.latitude,
        longitude: _selected.longitude,
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
                  maplibre.MapLibreMap(
                    styleString: _styleUrl,
                    initialCameraPosition: maplibre.CameraPosition(
                      target: _selected,
                      zoom: 10.5,
                    ),
                    minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
                      3,
                      18,
                    ),
                    compassEnabled: true,
                    logoEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    trackCameraPosition: true,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        EagerGestureRecognizer.new,
                      ),
                    },
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    onMapClick: (_, coordinate) => _movePin(coordinate),
                    onCameraMove: (position) {
                      _selected = position.target;
                    },
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
