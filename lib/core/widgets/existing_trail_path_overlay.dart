import 'dart:convert';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../trail/Data/local_trail_paths.dart';

/// A route-only layer: no checkpoint, hazard, weather or playback annotations.
class ExistingTrailPathOverlay {
  static const sourceId = 'existing-local-trail-paths';
  static const haloId = 'existing-local-trail-halo';
  static const lineId = 'existing-local-trail-lines';
  static const labelId = 'existing-local-trail-names';

  mapbox.MapboxMap? _map;
  List<LocalTrailPath> _paths = const [];
  Future<void> _pending = Future.value();
  int _revision = 0;

  /// Sets paths.
  Future<void> setPaths(List<LocalTrailPath> paths) {
    _paths = paths;
    return _render();
  }

  /// Computes on style loaded.
  Future<void> onStyleLoaded(mapbox.MapboxMap map) {
    _map = map;
    return _render();
  }

  /// Resets.
  void reset() {
    _revision++;
    _map = null;
  }

  /// Computes render.
  Future<void> _render() {
    final revision = ++_revision, map = _map, paths = _paths;

    /// Computes current.
    bool current() => revision == _revision && identical(map, _map);
    _pending = _pending.catchError((Object _) {}).then((_) async {
      if (map == null || !current()) return;
      final style = map.style;
      final data = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final path in paths)
            {
              'type': 'Feature',
              'id': path.trailId,
              'properties': {'name': path.name},
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  for (final p in path.coordinates) [p.longitude, p.latitude],
                ],
              },
            },
        ],
      });
      final exists = await style.styleSourceExists(sourceId);
      if (!current()) return;
      if (exists) {
        await style.setStyleSourceProperty(sourceId, 'data', data);
      } else {
        await style.addSource(
          mapbox.GeoJsonSource(id: sourceId, data: data, tolerance: 0),
        );
      }
      if (!current()) return;
      final layers = await style.getStyleLayers();
      final below = layers
          .where((l) => l?.id.contains('annotation') ?? false)
          .firstOrNull
          ?.id;
      for (final layer in <mapbox.Layer>[
        mapbox.LineLayer(
          id: haloId,
          sourceId: sourceId,
          lineColor: 0xFFFFFFFF,
          lineWidth: 6,
          lineOpacity: .8,
          lineCap: mapbox.LineCap.ROUND,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
        mapbox.LineLayer(
          id: lineId,
          sourceId: sourceId,
          lineColor: 0xFF16834B,
          lineWidth: 3.5,
          lineOpacity: .95,
          lineEmissiveStrength: 1,
          lineCap: mapbox.LineCap.ROUND,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
        mapbox.SymbolLayer(
          id: labelId,
          sourceId: sourceId,
          minZoom: 11,
          symbolPlacement: mapbox.SymbolPlacement.LINE,
          symbolSpacing: 300,
          textFieldExpression: ['get', 'name'],
          textSize: 11,
          textColor: 0xFF123E27,
          textHaloColor: 0xFFFFFFFF,
          textHaloWidth: 1.5,
        ),
      ]) {
        if (!current()) return;
        final exists = await style.styleLayerExists(layer.id);
        if (!current()) return;
        if (!exists) {
          await style.addLayerAt(layer, mapbox.LayerPosition(below: below));
        }
      }
    });
    return _pending;
  }
}
