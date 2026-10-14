// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/map_controls.dart';
import 'package:hiker_circle/core/widgets/state_boundary_overlay.dart';
import 'package:hiker_circle/onboarding/Data/google_city_geocoding_service.dart';
import 'package:hiker_circle/onboarding/View/residential_city_picker_page.dart';
import 'package:hiker_circle/trail/Model/malaysia_map_region.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class _Style extends Fake implements mapbox.StyleManager {
  final layers = <String, Map<String, dynamic>>{};
  @override
  Future<bool> isStyleLoaded() async => true;
  @override
  Future<bool> styleSourceExists(String id) async => true;
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<List<mapbox.StyleObjectInfo?>> getStyleLayers() async => [];
  @override
  Future<void> addStyleLayer(
    String properties,
    mapbox.LayerPosition? position,
  ) async {
    final layer = jsonDecode(properties) as Map<String, dynamic>;
    layers[layer['id'] as String] = layer;
  }

  @override
  Future<void> setStyleLayerProperty(
    String id,
    String property,
    Object value,
  ) async {
    layers[id]![property] = value;
  }
}

class _Map extends Fake implements mapbox.MapboxMap {
  @override
  final _Style style = _Style();
  final cameras = <mapbox.CameraOptions>[];
  final bounds = <mapbox.CoordinateBounds>[];
  Completer<mapbox.CameraOptions>? delayedCamera;
  @override
  void addInteraction<
    T extends mapbox.TypedFeaturesetFeature<mapbox.FeaturesetDescriptor>
  >(mapbox.TypedInteraction<T> interaction, {String? interactionID}) {}
  @override
  Future<mapbox.CameraOptions> cameraForCoordinateBounds(
    mapbox.CoordinateBounds value,
    mapbox.MbxEdgeInsets padding,
    double? bearing,
    double? pitch,
    double? maxZoom,
    mapbox.ScreenCoordinate? offset,
  ) async {
    bounds.add(value);
    final pending = delayedCamera;
    delayedCamera = null;
    if (pending != null) return pending.future;
    return mapbox.CameraOptions(zoom: 7, center: value.southwest);
  }

  @override
  Future<void> flyTo(
    mapbox.CameraOptions options,
    mapbox.MapAnimationOptions? animation,
  ) async {
    cameras.add(options);
  }
}

class _Geocoder extends GoogleCityGeocodingService {
  double? latitude;
  double? longitude;
  @override
  Future<ResidentialCitySelection> resolveCity({
    required double latitude,
    required double longitude,
  }) async {
    this.latitude = latitude;
    this.longitude = longitude;
    return ResidentialCitySelection(
      city: 'Actual town',
      state: 'Actual state',
      country: 'Malaysia',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

mapbox.MapWidget _widget(WidgetTester tester) =>
    tester.widget<DeferredMap>(find.byType(DeferredMap)).child
        as mapbox.MapWidget;

Future<void> _open(
  WidgetTester tester, {
  _Geocoder? geocoder,
  double? latitude,
  double? longitude,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ResidentialCityPickerPage(
        geocodingService: geocoder,
        initialLatitude: latitude,
        initialLongitude: longitude,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void _select(WidgetTester tester, MalaysiaMapRegion region) {
  tester
      .widget<DropdownButtonFormField<MalaysiaMapRegion>>(
        find.byKey(const Key('residential-state-focus')),
      )
      .onChanged!(region);
}

void main() {
  setUpAll(StateBoundaryOverlay.prewarm);
  testWidgets('opens on the peninsula and offers all states and territories', (
    tester,
  ) async {
    await _open(tester);
    final map = _widget(tester);
    expect(
      map.cameraOptions!.center!.coordinates.lat,
      MalaysiaMapRegion.peninsula.latitude,
    );
    expect(map.cameraOptions!.zoom, lessThan(7));
    final dropdown = tester.widget<DropdownButton<MalaysiaMapRegion>>(
      find.byType(DropdownButton<MalaysiaMapRegion>),
    );
    expect(dropdown.items!.map((item) => item.value), MalaysiaMapRegion.values);
    final native = _Map();
    map.onMapCreated!(native);
    await tester.pump();
    expect(
      native.bounds.single.southwest.coordinates.lng,
      MalaysiaMapRegion.peninsula.west,
    );
    expect(
      native.cameras.last.center!.coordinates.lat,
      MalaysiaMapRegion.peninsula.latitude,
    );
    await _close(tester);
  });

  testWidgets(
    'state focuses its center and reuses blue boundary layers; final city follows the pin',
    (tester) async {
      final geocoder = _Geocoder();
      await _open(tester, geocoder: geocoder);
      final map = _widget(tester);
      final native = _Map();
      map.onMapCreated!(native);
      await tester.pump();
      map.onStyleLoadedListener!(
        mapbox.StyleLoadedEventData.fromJson({
          'timeInterval': {'begin': 0, 'end': 1},
        }),
      );
      _select(tester, MalaysiaMapRegion.sabah);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(
        native.cameras.last.center!.coordinates.lng,
        MalaysiaMapRegion.sabah.longitude,
      );
      expect(
        native.cameras.last.center!.coordinates.lat,
        MalaysiaMapRegion.sabah.latitude,
      );
      expect(native.style.layers.length, 4);
      for (final layer in native.style.layers.values) {
        expect(
          layer['filter'],
          StateBoundaryOverlay.filterFor(MalaysiaMapRegion.sabah),
        );
      }
      expect(
        native.style.layers[StateBoundaryOverlay.fillLayerId]!['fill-opacity'],
        0.28,
      );
      map.onCameraChangeListener!(
        mapbox.CameraChangedEventData.fromJson({
          'timestamp': 1,
          'cameraState': {
            'center': {
              'type': 'Point',
              'coordinates': [100.4, 5.4],
            },
            'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
            'zoom': 12.0,
            'bearing': 0.0,
            'pitch': 0.0,
          },
        }),
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use this city'),
          )
          .onPressed!();
      await tester.pump();
      expect(geocoder.latitude, 5.4);
      expect(geocoder.longitude, 100.4);
      await _close(tester);
    },
  );

  testWidgets('rapid state changes cannot apply an older camera result', (
    tester,
  ) async {
    await _open(tester);
    final native = _Map();
    _widget(tester).onMapCreated!(native);
    await tester.pump();
    final delayed = Completer<mapbox.CameraOptions>();
    native.delayedCamera = delayed;
    _select(tester, MalaysiaMapRegion.johor);
    _select(tester, MalaysiaMapRegion.penang);
    await tester.pump();
    expect(
      native.cameras.last.center!.coordinates.lng,
      MalaysiaMapRegion.penang.longitude,
    );
    final cameraCount = native.cameras.length;
    delayed.complete(mapbox.CameraOptions(zoom: 9));
    await tester.pump();
    expect(native.cameras.length, cameraCount);
    for (final layer in native.style.layers.values) {
      expect(
        layer['filter'],
        StateBoundaryOverlay.filterFor(MalaysiaMapRegion.penang),
      );
    }
    await _close(tester);
  });

  testWidgets(
    'editing an existing city retains its saved coordinate initially',
    (tester) async {
      await _open(tester, latitude: 5.4, longitude: 100.3);
      final native = _Map();
      _widget(tester).onMapCreated!(native);
      await tester.pump();
      expect(native.cameras.last.center!.coordinates.lat, 5.4);
      expect(native.cameras.last.zoom, 14);
      _select(tester, MalaysiaMapRegion.sarawak);
      await tester.pump();
      expect(
        native.cameras.last.center!.coordinates.lat,
        MalaysiaMapRegion.sarawak.latitude,
      );
      await _close(tester);
    },
  );
}
