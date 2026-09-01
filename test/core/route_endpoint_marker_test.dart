import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_endpoint_marker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('route endpoint labels sit on opposite sides of a larger pin', () async {
    final imageBytes = await routeEndpointPinImage();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    addTearDown(() {
      frame.image.dispose();
      codec.dispose();
    });

    expect(frame.image.width, 72);
    expect(frame.image.height, 88);

    final normalAnnotation = routeEndpointAnnotation(
      geometry: mapbox.Point(coordinates: mapbox.Position(100, 5)),
      label: 'Start',
      pinImage: imageBytes,
    );
    final startAnnotation = routeEndpointAnnotation(
      geometry: mapbox.Point(coordinates: mapbox.Position(100, 5)),
      label: 'Start',
      pinImage: imageBytes,
      separateLabel: true,
    );
    final endAnnotation = routeEndpointAnnotation(
      geometry: mapbox.Point(coordinates: mapbox.Position(100, 5)),
      label: 'End',
      pinImage: imageBytes,
      separateLabel: true,
    );

    expect(normalAnnotation.image, isNotEmpty);
    expect(normalAnnotation.iconAnchor, mapbox.IconAnchor.BOTTOM);
    expect(normalAnnotation.iconSize, 0.72);
    expect(normalAnnotation.textAnchor, mapbox.TextAnchor.BOTTOM);
    expect(normalAnnotation.textOffset, const [0.0, -2.05]);

    expect(startAnnotation.textField, 'Start');
    expect(startAnnotation.textColor, routeEndpointRed);
    expect(startAnnotation.textAnchor, mapbox.TextAnchor.BOTTOM_RIGHT);
    expect(startAnnotation.textOffset, const [-1.15, -1.7]);

    expect(endAnnotation.iconSize, 0.72);
    expect(endAnnotation.textField, 'End');
    expect(endAnnotation.textAnchor, mapbox.TextAnchor.BOTTOM_LEFT);
    expect(endAnnotation.textOffset, const [1.15, -1.7]);
  });

  test('only nearby route endpoints need separated labels', () {
    final start = mapbox.Point(coordinates: mapbox.Position(100, 5));
    final nearbyEnd = mapbox.Point(
      coordinates: mapbox.Position(100.0001, 5.0001),
    );
    final distantEnd = mapbox.Point(coordinates: mapbox.Position(100.01, 5.01));

    expect(shouldSeparateRouteEndpointLabels(start, nearbyEnd), isTrue);
    expect(shouldSeparateRouteEndpointLabels(start, distantEnd), isFalse);
  });
}
