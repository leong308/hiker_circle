import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:hiker_circle/core/widgets/state_boundary_overlay.dart';
import 'package:hiker_circle/trail/Model/malaysia_map_region.dart';

class _Style extends Fake implements mapbox.StyleManager {
  final layers = <String, Map<String, dynamic>>{};
  int additions = 0;
  final opacityWrites = <double>[];
  @override
  Future<bool> styleSourceExists(String id) async => true;
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<List<mapbox.StyleObjectInfo?>> getStyleLayers() async => [
    mapbox.StyleObjectInfo(id: 'place-labels', type: 'symbol'),
    mapbox.StyleObjectInfo(id: 'road-overlay', type: 'line'),
    mapbox.StyleObjectInfo(id: 'building-overlay', type: 'fill-extrusion'),
    mapbox.StyleObjectInfo(id: 'circle-annotation', type: 'circle'),
  ];
  @override
  Future<void> addStyleLayer(
    String properties,
    mapbox.LayerPosition? position,
  ) async {
    final layer = jsonDecode(properties) as Map<String, dynamic>;
    expect(
      position?.below,
      layer['id'] == StateBoundaryOverlay.fillLayerId
          ? 'place-labels'
          : 'circle-annotation',
    );
    expect(layers.containsKey(layer['id']), isFalse);
    layers[layer['id'] as String] = layer;
    additions++;
  }

  @override
  Future<void> setStyleLayerProperty(
    String id,
    String property,
    Object value,
  ) async {
    if (property == 'fill-opacity') {
      opacityWrites.add((value as num).toDouble());
      (layers[id]!['paint'] as Map)[property] = value;
    } else {
      layers[id]![property] = value;
    }
  }
}

class _Map extends Fake implements mapbox.MapboxMap {
  @override
  final _Style style = _Style();
}

Iterable<List<num>> _positions(dynamic coordinates) sync* {
  final list = coordinates as List;
  if (list.first is num) {
    yield list.cast<num>();
  } else {
    for (final item in list) {
      yield* _positions(item);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(StateBoundaryOverlay.prewarm);
  test(
    'bundled asset maps every state and territory to real polygon geometry',
    () async {
      final data = jsonDecode(await StateBoundaryOverlay.prewarm()) as Map;
      final features = data['features'] as List;
      expect(features.length, 16);
      for (final region in MalaysiaMapRegion.values.where(
        (r) => r.boundaryIso != null,
      )) {
        final feature =
            features.singleWhere(
                  (f) => f['properties']['shapeISO'] == region.boundaryIso,
                )
                as Map;
        final name = region == MalaysiaMapRegion.melaka
            ? 'Malacca'
            : region.label.split(' (').first;
        expect(feature['properties']['shapeName'], name);
        expect(feature['geometry']['type'], isIn(['Polygon', 'MultiPolygon']));
        final coordinates = _positions(
          feature['geometry']['coordinates'],
        ).toList();
        expect(coordinates.length, greaterThan(100));
        for (final coordinate in coordinates) {
          expect(
            coordinate[0],
            inInclusiveRange(region.west - .000001, region.east + .000001),
          );
          expect(
            coordinate[1],
            inInclusiveRange(region.south - .000001, region.north + .000001),
          );
        }
      }
    },
  );
  test(
    'switching states replaces every outline filter without stacking layers',
    () async {
      final map = _Map();
      final overlay = StateBoundaryOverlay();
      addTearDown(overlay.dispose);
      await overlay.select(MalaysiaMapRegion.penang);
      await overlay.onStyleLoaded(map);
      expect(map.style.layers.length, 4);
      await Future.wait([
        overlay.select(MalaysiaMapRegion.johor),
        overlay.select(MalaysiaMapRegion.sabah),
      ]);
      expect(map.style.additions, 4);
      for (final layer in map.style.layers.values) {
        expect(
          layer['filter'],
          StateBoundaryOverlay.filterFor(MalaysiaMapRegion.sabah),
        );
      }
      await overlay.select(MalaysiaMapRegion.peninsula);
      for (final layer in map.style.layers.values) {
        expect((layer['filter'] as List).last, '');
      }
    },
  );
  test('style reload recreates outlines with the selected state', () async {
    final map = _Map();
    final overlay = StateBoundaryOverlay();
    addTearDown(overlay.dispose);
    await overlay.onStyleLoaded(map);
    await overlay.select(MalaysiaMapRegion.melaka);
    map.style.layers.clear();
    await overlay.onStyleLoaded(map);
    expect(map.style.layers.length, 4);
    for (final layer in map.style.layers.values) {
      expect(
        layer['filter'],
        StateBoundaryOverlay.filterFor(MalaysiaMapRegion.melaka),
      );
    }
  });
  test('disposing ignores queued selection work', () async {
    final map = _Map();
    final overlay = StateBoundaryOverlay();
    addTearDown(overlay.dispose);
    final pending = overlay.onStyleLoaded(map);
    overlay.dispose();
    await pending;
    expect(map.style.layers, isEmpty);
  });
  test(
    'three smoothly animated pulses finish at five seconds and retain a crisp border',
    () async {
      final map = _Map();
      final overlay = StateBoundaryOverlay();
      addTearDown(overlay.dispose);
      await overlay.onStyleLoaded(map);
      await overlay.select(MalaysiaMapRegion.penang);
      await Future<void>.delayed(Duration.zero);
      expect(map.style.opacityWrites.last, 0.28);
      final pulseStart = map.style.opacityWrites.length - 1;
      expect(
        map.style.layers[StateBoundaryOverlay
            .fillLayerId]!['fill-opacity-transition'],
        {'duration': 400, 'delay': 0},
      );
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(map.style.opacityWrites.sublist(pulseStart), [
        0.28,
        0,
        0.28,
        0,
        0.28,
        0,
      ]);
      for (final id in StateBoundaryOverlay.layerIds) {
        final layer = map.style.layers[id]!;
        expect(
          layer['filter'],
          StateBoundaryOverlay.filterFor(MalaysiaMapRegion.penang),
        );
        final paint = layer['paint'] as Map;
        expect(paint['line-opacity'], greaterThan(0));
        final width = paint['line-width'] as List;
        expect(width[2], ['zoom']);
        expect(width[4] as num, lessThanOrEqualTo(1.8));
        expect(width.last as num, greaterThan(width[4] as num));
        final blur = paint['line-blur'] as List;
        expect(blur[4] as num, lessThanOrEqualTo(0.4));
      }
    },
  );
  test(
    'switching states restarts pulses; style reload and disposal do not restart them',
    () async {
      final map = _Map();
      final overlay = StateBoundaryOverlay();
      addTearDown(overlay.dispose);
      await overlay.onStyleLoaded(map);
      await overlay.select(MalaysiaMapRegion.penang);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await overlay.select(MalaysiaMapRegion.johor);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      map.style.layers.clear();
      await overlay.onStyleLoaded(map);
      final fill = map.style.layers[StateBoundaryOverlay.fillLayerId]!;
      expect(
        fill['filter'],
        StateBoundaryOverlay.filterFor(MalaysiaMapRegion.johor),
      );
      expect((fill['paint'] as Map)['fill-opacity'], 0.28);
      await Future<void>.delayed(const Duration(milliseconds: 4600));
      expect((fill['paint'] as Map)['fill-opacity'], 0);
      await overlay.onStyleLoaded(map);
      await Future<void>.delayed(Duration.zero);
      expect((fill['paint'] as Map)['fill-opacity'], 0);
      await overlay.select(MalaysiaMapRegion.sabah);
      await overlay.select(MalaysiaMapRegion.peninsula);
      await Future<void>.delayed(Duration.zero);
      expect((fill['paint'] as Map)['fill-opacity'], 0);
      expect((fill['filter'] as List).last, '');
      await overlay.select(MalaysiaMapRegion.penang);
      await Future<void>.delayed(Duration.zero);
      overlay.dispose();
      final count = map.style.opacityWrites.length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(map.style.opacityWrites.length, count);
    },
  );
}
