// StateBoundaryOverlay adds selectable geographic outlines to a map without mutating saved trail
// coordinates.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../trail/Model/malaysia_map_region.dart';

/// A visual overlay only. It never changes pins or saved trail metadata.
class StateBoundaryOverlay {
  static const assetPath = 'assets/maps/malaysia_states.geojson';
  static const sourceId = 'add-trail-state-boundaries';
  static const fillLayerId = 'state-selection-fill';
  static const glowDuration = Duration(seconds: 5);
  static const layerIds = [
    'state-border-halo',
    'state-border-glow',
    'state-border-edge',
  ];
  static Future<String>? _asset;

  /// Computes prewarm.
  static Future<String> prewarm() =>
      _asset ??= rootBundle.loadString(assetPath);

  mapbox.MapboxMap? _map;
  MalaysiaMapRegion _selected = MalaysiaMapRegion.peninsula;
  Future<void> _pending = Future.value();
  int _revision = 0;
  int _selectionRevision = 0;
  bool _showFill = false;
  final _glowTimers = <Timer>[];
  double _fillOpacity = 0;

  /// Computes on style loaded.
  Future<void> onStyleLoaded(mapbox.MapboxMap map) {
    _map = map;
    return _render();
  }

  /// Selects.
  Future<void> select(MalaysiaMapRegion region) {
    _cancelGlow();
    _fillOpacity = 0;
    _selectionRevision++;
    _showFill = region.boundaryIso != null;
    _selected = region;
    return _render();
  }

  /// Releases resources owned by this instance.
  void dispose() {
    _cancelGlow();
    _selectionRevision++;
    _revision++;
    _map = null;
  }

  /// Computes render.
  Future<void> _render() {
    final revision = ++_revision;
    final map = _map;
    final region = _selected;
    _pending = _pending.catchError((Object _) {}).then((_) async {
      if (map == null || revision != _revision || !identical(map, _map)) return;
      final data = await prewarm();
      if (revision != _revision || !identical(map, _map)) return;
      final style = map.style;
      if (!await style.styleSourceExists(sourceId)) {
        await style.addSource(
          mapbox.GeoJsonSource(
            id: sourceId,
            data: data,
            tolerance: 0,
            attribution:
                '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a> · <a href="https://www.geoboundaries.org/">geoBoundaries</a>',
          ),
        );
      }
      // Polygon/MultiPolygon rings render directly as lines, including islands.
      final filter = filterFor(region);
      final layers = await style.getStyleLayers();
      final fillBelow = layers
          .where(
            (layer) =>
                layer?.type == 'symbol' ||
                (layer?.id.contains('annotation') ?? false),
          )
          .firstOrNull
          ?.id;
      // Borders sit above every basemap layer, including labels and roads.
      // Only interactive annotations belong above the state outline.
      final borderBelow = layers
          .where((layer) => layer?.id.contains('annotation') ?? false)
          .firstOrNull
          ?.id;
      if (revision != _revision || !identical(map, _map)) return;
      final opacity = _fillOpacity;
      if (await style.styleLayerExists(fillLayerId)) {
        await style.setStyleLayerProperty(fillLayerId, 'filter', filter);
        await style.setStyleLayerProperty(fillLayerId, 'fill-opacity', opacity);
      } else {
        await style.addLayerAt(
          mapbox.FillLayer(
            id: fillLayerId,
            sourceId: sourceId,
            filter: filter,
            fillColor: 0xFF008CFF,
            fillOpacity: opacity,
            fillEmissiveStrength: 1,
          ),
          mapbox.LayerPosition(
            below: await style.styleLayerExists(layerIds.first)
                ? layerIds.first
                : fillBelow,
          ),
        );
      }
      await style.setStyleLayerProperty(
        fillLayerId,
        'fill-opacity-transition',
        {'duration': 400, 'delay': 0},
      );
      for (var i = 0; i < layerIds.length; i++) {
        if (revision != _revision || !identical(map, _map)) return;
        final id = layerIds[i];
        if (await style.styleLayerExists(id)) {
          await style.setStyleLayerProperty(id, 'filter', filter);
        } else {
          await style.addLayerAt(
            mapbox.LineLayer(
              id: id,
              sourceId: sourceId,
              filter: filter,
              lineColor: i == 2 ? 0xFF2196FF : 0xFF008CFF,
              // Keep detailed coastlines crisp at overview zooms. A fixed
              // 16px halo overwhelmed small states and looked furry.
              lineWidthExpression: [
                'interpolate',
                ['linear'],
                ['zoom'],
                4,
                [1.8, 1.3, 1.0][i],
                8,
                [4.0, 2.5, 1.5][i],
                12,
                [8.0, 4.0, 2.0][i],
              ],
              lineBlurExpression: [
                'interpolate',
                ['linear'],
                ['zoom'],
                4,
                [0.4, 0.2, 0.0][i],
                12,
                [2.0, 1.0, 0.0][i],
              ],
              lineOpacity: [0.16, 0.32, 1.0][i],
              lineEmissiveStrength: 1,
              lineJoin: mapbox.LineJoin.ROUND,
              lineCap: mapbox.LineCap.ROUND,
            ),
            mapbox.LayerPosition(below: borderBelow),
          );
        }
      }
      if (revision != _revision || !identical(map, _map)) return;
      if (_showFill && _glowTimers.isEmpty) _startGlow();
    });
    return _pending;
  }

  /// Cancels glow.
  void _cancelGlow() {
    for (final timer in _glowTimers) {
      timer.cancel();
    }
    _glowTimers.clear();
  }

  /// Starts glow.
  void _startGlow() {
    final selectionRevision = _selectionRevision;
    // Native 400ms paint transitions animate smoothly without sending a
    // platform-channel update every frame: glow/off/glow/off/glow, then clear.
    _setFillOpacity(0.28, selectionRevision);
    for (final step in [
      (1000, 0.0),
      (2000, 0.28),
      (3000, 0.0),
      (4000, 0.28),
      (4600, 0.0),
    ]) {
      _glowTimers.add(
        Timer(Duration(milliseconds: step.$1), () {
          _setFillOpacity(step.$2, selectionRevision);
        }),
      );
    }
    _glowTimers.add(
      Timer(glowDuration, () {
        if (selectionRevision != _selectionRevision) return;
        _showFill = false;
        _glowTimers.clear();
      }),
    );
  }

  /// Sets fill opacity.
  void _setFillOpacity(double opacity, int selectionRevision) {
    if (selectionRevision != _selectionRevision || _map == null) return;
    _fillOpacity = opacity;
    final map = _map!;
    _pending = _pending
        .catchError((Object _) {})
        .then((_) async {
          if (selectionRevision != _selectionRevision ||
              !identical(map, _map)) {
            return;
          }
          await map.style.setStyleLayerProperty(
            fillLayerId,
            'fill-opacity',
            opacity,
          );
        })
        .catchError((Object _) {
          // A style reload restores the current opacity; disposal cancels timers.
        });
  }

  /// Filters for.
  static List<Object> filterFor(MalaysiaMapRegion region) => [
    '==',
    ['get', 'shapeISO'],
    region.boundaryIso ?? '',
  ];
}
