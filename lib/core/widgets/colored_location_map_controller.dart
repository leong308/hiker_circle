import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'map_utils.dart';
import 'map_view_controller.dart';

/// A recorded map point with a stable identity, readable label and assigned colour.
class ColoredLocationPoint {
  /// Keeps geographic data independent of the feature displaying the shared map.
  const ColoredLocationPoint({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.color,
    this.stale = false,
  });
  final String id, label;
  final double latitude, longitude;
  final int color;
  final bool stale;

  /// Rejects invalid positions rather than plotting an invented fallback point.
  bool get valid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  /// Uses longitude/latitude order expected by the native map.
  mapbox.Point get geometry =>
      mapbox.Point(coordinates: mapbox.Position(longitude, latitude));
}

/// Preserves coloured recorded markers and camera position through point and style updates.
class ColoredLocationMapController extends ChangeNotifier {
  /// Fits the known markers once and reuses the application's common map controls.
  ColoredLocationMapController({
    required List<ColoredLocationPoint> points,
    required this.fallback,
  }) : _points = points {
    view = MapViewController(
      settings: const MapViewSettings(dimension: MapDimension.twoD),
      onBeforeStyleReload: _clear,
    );
    _timeout = Timer(const Duration(seconds: 15), fail);
  }
  final mapbox.Point fallback;
  late final MapViewController view;
  List<ColoredLocationPoint> _points;
  mapbox.MapboxMap? _map;
  mapbox.CircleAnnotationManager? _circles;
  mapbox.PointAnnotationManager? _labels;
  Timer? _timeout;
  bool _disposed = false,
      failed = false,
      _drawing = false,
      _dirty = false,
      _fitted = false;
  int _generation = 0;
  final _fittedIdentities = <String>{};

  /// Accepts the newest snapshot without moving the hiker's manually panned camera.
  void update(List<ColoredLocationPoint> points) {
    if (_disposed) return;
    final before = _points
        .map(
          (p) =>
              '${p.id}:${p.latitude}:${p.longitude}:${p.color}:${p.label}:${p.stale}',
        )
        .join('|');
    final after = points
        .map(
          (p) =>
              '${p.id}:${p.latitude}:${p.longitude}:${p.color}:${p.label}:${p.stale}',
        )
        .join('|');
    _points = points;
    if (before != after && view.isStyleReady) unawaited(_render());
  }

  /// Attaches one native surface and disables duplicate native scale/compass controls.
  void attach(mapbox.MapboxMap map) {
    if (_disposed) return;
    _map = map;
    _generation++;
    _fitted = false;
    _fittedIdentities.clear();
    view.attach(map);
    unawaited(_prepare(map, _generation));
  }

  /// Fences delayed annotation work after style changes or disposal.
  bool _current(mapbox.MapboxMap map, int generation) =>
      !_disposed &&
      !failed &&
      identical(map, _map) &&
      generation == _generation;

  /// Applies the same native control bounds as the other reusable maps.
  Future<void> _prepare(mapbox.MapboxMap map, int generation) async {
    try {
      await map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
      if (!_current(map, generation)) return;
      await map.scaleBar.updateSettings(
        mapbox.ScaleBarSettings(enabled: false),
      );
      if (!_current(map, generation)) return;
      await map.setBounds(
        mapbox.CameraBoundsOptions(minZoom: kMapMinZoom, maxZoom: kMapMaxZoom),
      );
    } catch (_) {
      if (_current(map, generation)) fail();
    }
  }

  /// Rebuilds annotations when the style is ready, preserving the current view.
  Future<void> styleLoaded() => view.styleLoaded(_render);

  /// Serializes native marker updates so an older snapshot cannot overwrite a newer one.
  Future<void> _render() async {
    if (_drawing) {
      _dirty = true;
      return;
    }
    _drawing = true;
    try {
      do {
        _dirty = false;
        await _draw();
      } while (_dirty && !_disposed && !failed);
    } catch (_) {
      if (!_disposed && !view.isChanging) fail();
    } finally {
      _drawing = false;
    }
  }

  /// Draws coloured circles and matching names from actual recorded coordinates only.
  Future<void> _draw() async {
    final map = _map, generation = _generation;
    if (map == null || !_current(map, generation)) return;
    try {
      final circles =
          _circles ?? await map.annotations.createCircleAnnotationManager();
      if (!_current(map, generation)) return;
      _circles = circles;
      final labels =
          _labels ?? await map.annotations.createPointAnnotationManager();
      if (!_current(map, generation)) return;
      _labels = labels;
      await circles.deleteAll();
      if (!_current(map, generation)) return;
      await labels.deleteAll();
      if (!_current(map, generation)) return;
      final points = _points.where((p) => p.valid).toList();
      if (points.isNotEmpty) {
        await circles.createMulti(
          points
              .map(
                (p) => mapbox.CircleAnnotationOptions(
                  geometry: p.geometry,
                  circleColor: p.color,
                  circleRadius: 9,
                  circleStrokeColor: 0xff102a1d,
                  circleStrokeWidth: 2,
                  circleOpacity: p.stale ? .5 : 1,
                ),
              )
              .toList(),
        );
        if (!_current(map, generation)) return;
        await labels.setTextAllowOverlap(false);
        if (!_current(map, generation)) return;
        await labels.createMulti(
          points
              .map(
                (p) => mapbox.PointAnnotationOptions(
                  geometry: p.geometry,
                  textField: p.label,
                  textSize: 12,
                  textColor: 0xff102a1d,
                  textHaloColor: 0xffffffff,
                  textHaloWidth: 2,
                  textOffset: [0, 1.6],
                ),
              )
              .toList(),
        );
      }
      if (!_current(map, generation)) return;
      if (points.isNotEmpty &&
          (!_fitted ||
              points.any((point) => !_fittedIdentities.contains(point.id)))) {
        await fit();
        _fitted = true;
        _fittedIdentities.addAll(points.map((point) => point.id));
      }
      _timeout?.cancel();
    } catch (_) {
      if (_current(map, generation)) rethrow;
    }
  }

  /// Fits every recorded hiker, with room for the standard corner controls.
  Future<void> fit() async {
    final map = _map, generation = _generation;
    if (map == null || !_current(map, generation)) return;
    final points = _points
        .where((p) => p.valid)
        .map((p) => p.geometry)
        .toList();
    if (points.isEmpty) points.add(fallback);
    try {
      if (points.length == 1) {
        await map.setCamera(
          mapbox.CameraOptions(center: points.first, zoom: 15),
        );
        return;
      }
      final bounds = boundsFor(points);
      final camera = await map.cameraForCoordinateBounds(
        mapbox.CoordinateBounds(
          southwest: mapbox.Point(
            coordinates: mapbox.Position(bounds.minLon, bounds.minLat),
          ),
          northeast: mapbox.Point(
            coordinates: mapbox.Position(bounds.maxLon, bounds.maxLat),
          ),
          infiniteBounds: false,
        ),
        mapbox.MbxEdgeInsets(top: 90, left: 45, bottom: 90, right: 45),
        0,
        view.settings.is3D ? 50 : 0,
        17,
        null,
      );
      if (_current(map, generation)) await map.setCamera(camera);
    } catch (_) {
      /* Keep existing markers and camera when a fit request is interrupted. */
    }
  }

  /// Drops style-owned managers before the style is replaced.
  Future<void> _clear() async {
    _generation++;
    final map = _map, circles = _circles, labels = _labels;
    _circles = null;
    _labels = null;
    if (map == null) return;
    if (circles != null) {
      try {
        await map.annotations.removeAnnotationManager(circles);
      } catch (_) {}
    }
    if (labels != null) {
      try {
        await map.annotations.removeAnnotationManager(labels);
      } catch (_) {}
    }
  }

  /// Exposes a readable fallback when the native map cannot be loaded.
  void fail() {
    if (_disposed) return;
    failed = true;
    _generation++;
    _timeout?.cancel();
    notifyListeners();
  }

  /// Releases only this map's resources, leaving the recorded team positions intact.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timeout?.cancel();
    view.dispose();
    _map = null;
    super.dispose();
  }
}
