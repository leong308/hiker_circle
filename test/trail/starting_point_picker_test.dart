import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/core/widgets/map_controls.dart';
import 'package:hiker_circle/trail/View/trail_page.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class _Repository extends Fake implements HikerCircleFirebaseRepository {}

class _Circle extends Fake implements mapbox.CircleAnnotation {}

class _Point extends Fake implements mapbox.PointAnnotation {}

class _Circles extends Fake implements mapbox.CircleAnnotationManager {
  final pins = <mapbox.CircleAnnotationOptions>[];
  @override
  Future<void> deleteAll() async => pins.clear();
  @override
  Future<mapbox.CircleAnnotation> create(
    mapbox.CircleAnnotationOptions options,
  ) async {
    pins.add(options);
    return _Circle();
  }
}

class _Points extends Fake implements mapbox.PointAnnotationManager {
  @override
  Future<void> deleteAll() async {}
  @override
  Future<void> setTextAllowOverlap(bool value) async {}
  @override
  Future<mapbox.PointAnnotation> create(
    mapbox.PointAnnotationOptions options,
  ) async => _Point();
}

class _Lines extends Fake implements mapbox.PolylineAnnotationManager {
  @override
  Future<void> deleteAll() async {}
}

class _Annotations extends Fake implements mapbox.AnnotationManager {
  final circles = _Circles();
  int creations = 0;
  @override
  Future<mapbox.CircleAnnotationManager> createCircleAnnotationManager({
    String? id,
    String? below,
  }) async {
    creations++;
    return circles;
  }

  @override
  Future<mapbox.PointAnnotationManager> createPointAnnotationManager({
    String? id,
    String? below,
  }) async => _Points();
  @override
  Future<mapbox.PolylineAnnotationManager> createPolylineAnnotationManager({
    String? id,
    String? below,
  }) async => _Lines();
}

class _Style extends Fake implements mapbox.StyleManager {
  int terrainUpdates = 0;
  @override
  Future<void> setStyleTerrain(String properties) async {
    terrainUpdates++;
  }
}

class _Map extends Fake implements mapbox.MapboxMap {
  @override
  final _Style style = _Style();
  @override
  final _Annotations annotations = _Annotations();
  // Nonessential camera and terrain methods deliberately throw, as can happen
  // when the native surface is still initializing. Marker setup must recover.
}

Future<mapbox.MapWidget> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAddTrailSheet(
              context,
              session: AppSession(
                phoneNumber: 'test',
                signedInAt: DateTime(2026),
              ),
              repository: _Repository(),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  // Inspect the map callbacks without constructing an unsupported native view.
  return tester.widget<DeferredMap>(find.byType(DeferredMap)).child
      as mapbox.MapWidget;
}

void _tap(mapbox.MapWidget map, double longitude, double latitude) {
  // ignore: deprecated_member_use
  map.onTapListener!(
    mapbox.MapContentGestureContext(
      touchPosition: mapbox.ScreenCoordinate(x: 100, y: 100),
      point: mapbox.Point(coordinates: mapbox.Position(longitude, latitude)),
      gestureState: mapbox.GestureState.ended,
    ),
  );
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
    'add form locks region and checkpoint map starts at selected trailhead',
    (tester) async {
      final startingMap = await _open(tester);
      _tap(startingMap, 100.27, 5.42);
      await tester.pump();
      await tester.tap(find.text('Use this location'));
      await tester.pump();
      expect(find.byType(AppBar), findsNothing);
      expect(tester.widget<Text>(find.text('Add Trail')).style?.fontSize, 26);
      for (final label in ['State', 'Country']) {
        final field = tester.widget<TextField>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == label,
          ),
        );
        expect(field.readOnly, isTrue);
        expect(field.onTap, isNull);
      }
      expect(find.text('Finish & Add'), findsOneWidget);
      await tester.ensureVisible(find.text('Add checkpoints on map'));
      await tester.tap(find.text('Add checkpoints on map'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final map =
          tester.widget<DeferredMap>(find.byType(DeferredMap)).child
              as mapbox.MapWidget;
      // ignore: deprecated_member_use
      expect(map.cameraOptions!.center!.coordinates.lng, 100.27);
      // ignore: deprecated_member_use
      expect(map.cameraOptions!.center!.coordinates.lat, 5.42);
      _tap(map, 100.28, 5.43);
      _tap(map, 100.29, 5.44);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // A selected pin can also be removed without a fixed-length-list error.
      _tap(map, 100.29, 5.44);
      await tester.pump();
      expect(tester.takeException(), isNull);
      _tap(map, 100.29, 5.44);
      await tester.pump();
      await tester.tap(find.text('Confirm 3 pins'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ROUTE PREVIEW'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('FPV'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets(
    'header matches app and repeated nearby taps keep the selected location',
    (tester) async {
      final map = await _open(tester);
      final title = tester.widget<Text>(find.text('Select a Starting Point'));
      expect(title.style?.fontSize, 26);
      expect(title.style?.fontWeight, FontWeight.w800);
      expect(find.byType(AppBar), findsNothing);
      final recognizer = map.gestureRecognizers!.single.constructor();
      expect(recognizer, isA<EagerGestureRecognizer>());
      recognizer.dispose();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this location'),
            )
            .onPressed,
        isNull,
      );
      for (final longitude in [100.27, 100.27, 100.2701]) {
        _tap(map, longitude, 5.42);
        await tester.pump();
        expect(
          find.text(
            'Starting point selected\n5.420000, ${longitude.toStringAsFixed(6)}',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use this location'),
              )
              .onPressed,
          isNotNull,
        );
      }
      await tester.tap(find.byTooltip('Close starting point selection'));
      await tester.pump();
      await _close(tester);
    },
  );
  testWidgets(
    'a tap before style readiness is rendered and rapid taps leave only the latest pin',
    (tester) async {
      final config = await _open(tester);
      final nativeMap = _Map();
      config.onMapCreated!(nativeMap);
      _tap(config, 100.27, 5.42);
      await tester.pump();
      expect(nativeMap.annotations.circles.pins, isEmpty);
      config.onStyleLoadedListener!(
        mapbox.StyleLoadedEventData.fromJson({
          'timeInterval': {'begin': 0, 'end': 1},
        }),
      );
      await tester.pump();
      expect(
        nativeMap.annotations.circles.pins.single.geometry.coordinates.lng,
        100.27,
      );
      _tap(config, 100.28, 5.43);
      _tap(config, 100.29, 5.44);
      _tap(config, 100.30, 5.45);
      await tester.pump();
      final pin = nativeMap.annotations.circles.pins.single;
      expect(pin.geometry.coordinates.lng, 100.30);
      expect(pin.geometry.coordinates.lat, 5.45);
      expect(nativeMap.annotations.creations, 1);
      expect(nativeMap.style.terrainUpdates, 0);
      await _close(tester);
    },
  );
}

