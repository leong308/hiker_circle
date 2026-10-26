// WeatherMapOverlay loads the selected weather layer and manages its native-map image, legend and
// refresh lifecycle.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:url_launcher/url_launcher.dart';

import '../services/weather_map_service.dart';
import '../services/weather_area_service.dart';

/// Controls a geographic raster layer. Flutter only draws the controls/legend;
/// Mapbox projects a preloaded 50 km weather image as the camera moves.
class WeatherMapOverlay extends StatefulWidget {
  /// Creates weather map overlay.
  const WeatherMapOverlay({
    super.key,
    required this.map,
    required this.latitude,
    required this.longitude,
  });
  final double latitude;
  final double longitude;
  final mapbox.MapboxMap? map;

  /// Creates the presentation state for this widget.
  @override
  State<WeatherMapOverlay> createState() => WeatherMapOverlayState();
}

/// Manages the weather map overlay presentation and lifecycle.
class WeatherMapOverlayState extends State<WeatherMapOverlay> {
  static const sourceId = 'trail-weather-source';
  static const layerId = 'trail-weather-layer';
  WeatherMapLayer _layer = WeatherMapLayer.off;
  double _opacity = .85;
  bool _loading = false;
  DateTime? _loadedAt;
  String? _error;
  Future<void> _pending = Future.value();
  int _revision = 0;

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant WeatherMapOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.map, widget.map) ||
        oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _apply();
    }
  }

  /// Computes report map error.
  void reportMapError(String? source) {
    if (source != sourceId || _layer == WeatherMapLayer.off || !mounted) return;
    setState(() {
      _error = 'Weather unavailable. Try again later.';
      _layer = WeatherMapLayer.off;
    });
    _apply();
  }

  /// Selects.
  void _select(WeatherMapLayer value) {
    if (value != WeatherMapLayer.off && WeatherMapService.apiKey.isEmpty) {
      setState(() => _error = 'Weather maps are not available yet.');
      return;
    }
    setState(() {
      _layer = value;
      _error = null;
    });
    _apply();
  }

  /// Applies.
  void _apply({bool refresh = false}) {
    final revision = ++_revision;
    final map = widget.map;
    final selected = _layer;
    final latitude = widget.latitude;
    final longitude = widget.longitude;
    // Serialize remove/add operations; fast selection/style changes cannot
    // leave the previous raster on top or create duplicate sources.
    _pending = _pending.then((_) async {
      if (!mounted || revision != _revision || map == null) return;
      try {
        if (await map.style.styleLayerExists(layerId)) {
          await map.style.removeStyleLayer(layerId);
        }
        if (await map.style.styleSourceExists(sourceId)) {
          await map.style.removeStyleSource(sourceId);
        }
        if (selected == WeatherMapLayer.off || revision != _revision) return;
        setState(() => _loading = true);
        final area = await WeatherAreaService.shared.load(
          latitude: latitude,
          longitude: longitude,
          layer: selected,
          apiKey: WeatherMapService.apiKey,
          refresh: refresh,
        );
        if (!mounted || revision != _revision) return;
        await map.style.addSource(
          mapbox.ImageSource(id: sourceId, coordinates: area.grid.corners),
        );
        // The installed iOS/Android image-source bridges decode encoded image
        // bytes (UIImage/BitmapFactory); pass PNG, as in the SDK example.
        await map.style.updateStyleImageSourceImage(
          sourceId,
          mapbox.MbxImage(
            width: area.grid.width,
            height: area.grid.height,
            data: area.png,
          ),
        );
        if (!mounted || revision != _revision) return;
        setState(() => _loadedAt = area.loadedAt);
        final layers = await map.style.getStyleLayers();
        String? below;
        for (final layer in layers) {
          if (layer != null &&
              (layer.type == 'symbol' || layer.id.contains('annotation'))) {
            below = layer.id;
            break;
          }
        }
        await map.style.addLayerAt(
          mapbox.RasterLayer(
            id: layerId,
            sourceId: sourceId,
            rasterOpacity: _opacity,
            rasterEmissiveStrength: 1,
            rasterFadeDuration: 300,
          ),
          mapbox.LayerPosition(below: below),
        );
      } catch (_) {
        if (mounted && revision == _revision) {
          setState(() {
            _error = 'Weather unavailable. Try again later.';
            _layer = WeatherMapLayer.off;
          });
          if (selected != WeatherMapLayer.off) _apply();
        }
      } finally {
        if (mounted && revision == _revision) setState(() => _loading = false);
      }
    });
  }

  /// Sets opacity.
  void _setOpacity(double value) {
    setState(() => _opacity = value);
    final map = widget.map;
    // Queue behind installation so sliders cannot race a style change.
    _pending = _pending.then((_) async {
      if (!mounted || map == null || !identical(map, widget.map)) return;
      try {
        if (await map.style.styleLayerExists(layerId)) {
          await map.style.setStyleLayerProperty(
            layerId,
            'raster-opacity',
            _opacity,
          );
        }
      } catch (_) {
        /* A replaced map has no active weather layer. */
      }
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final active = _layer != WeatherMapLayer.off;
    return Stack(
      children: [
        Positioned(
          left: 10,
          top: 10,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(8),
            child: PopupMenuButton<WeatherMapLayer>(
              tooltip: 'Weather layers',
              initialValue: _layer,
              icon: Icon(
                Icons.cloud_outlined,
                color: active ? Colors.blue : null,
              ),
              onSelected: _select,
              itemBuilder: (_) => WeatherMapLayer.values
                  .map(
                    (layer) => CheckedPopupMenuItem(
                      value: layer,
                      checked: layer == _layer,
                      child: Text(layer.label),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (active || _error != null)
          Positioned(
            left: 10,
            bottom: 45,
            width: 210,
            child: Material(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _error = null),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    if (active) ...[
                      Text(
                        '${_layer.label} · current conditions',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _WeatherLegend(layer: _layer),
                      SizedBox(
                        height: 28,
                        child: Row(
                          children: [
                            const Icon(Icons.opacity, size: 14),
                            Expanded(
                              child: Slider(
                                value: _opacity,
                                min: .15,
                                max: 1,
                                label: '${(_opacity * 100).round()}%',
                                onChanged: _setOpacity,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        '50 km radius · enhanced visibility',
                        style: TextStyle(fontSize: 9),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _loading
                                  ? 'Loading weather…'
                                  : _loadedAt == null
                                  ? 'Select a layer to load'
                                  : 'Loaded ${TimeOfDay.fromDateTime(_loadedAt!).format(context)}',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: 'Refresh weather area',
                              onPressed: _loading
                                  ? null
                                  : () => _apply(refresh: true),
                              icon: const Icon(Icons.refresh, size: 16),
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () =>
                            launchUrl(Uri.parse('https://openweathermap.org/')),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Weather data © OpenWeather',
                            style: TextStyle(
                              fontSize: 10,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Displays the weather legend.
class _WeatherLegend extends StatelessWidget {
  /// Creates weather legend.
  const _WeatherLegend({required this.layer});
  final WeatherMapLayer layer;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    // Provider's published default palette; see docs/WEATHER_MAPS.md.
    final (colors, labels) = switch (layer) {
      WeatherMapLayer.temperature => (
        [
          const Color(0xFF208CEC),
          const Color(0xFF23DDDD),
          const Color(0xFFC2FF28),
          const Color(0xFFFFF028),
          const Color(0xFFFC8014),
        ],
        ['−20', '0', '10', '20', '30+ °C'],
      ),
      WeatherMapLayer.wind => (
        [
          const Color(0xFFEECECE),
          const Color(0xFFB364BC),
          const Color(0xFF3F213B),
          const Color(0xFF744CAC),
        ],
        ['5', '15', '25', '50+ m/s'],
      ),
      _ => (
        [
          const Color(0xFF6E6ECD),
          const Color(0xFF5050E1),
          const Color(0xFF1414FF),
        ],
        ['1', '10', '140+ mm'],
      ),
    };
    return Row(
      children: List.generate(
        colors.length,
        (i) => Expanded(
          child: Column(
            children: [
              Container(height: 6, color: colors[i]),
              Text(labels[i], style: const TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }
}
