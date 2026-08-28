import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_endpoint_marker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('route endpoints keep the red label close above the pin', () async {
    final imageBytes = await routeEndpointPinImage();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    addTearDown(() {
      frame.image.dispose();
      codec.dispose();
    });

    expect(frame.image.width, 72);
    expect(frame.image.height, 88);

    final annotation = routeEndpointAnnotation(
      geometry: mapbox.Point(coordinates: mapbox.Position(100, 5)),
      label: 'Start',
      pinImage: imageBytes,
    );
    expect(annotation.image, isNotEmpty);
    expect(annotation.iconAnchor, mapbox.IconAnchor.BOTTOM);
    expect(annotation.textField, 'Start');
    expect(annotation.textColor, routeEndpointRed);
    expect(annotation.textAnchor, mapbox.TextAnchor.BOTTOM);
    expect(annotation.textOffset, const [0.0, -2.5]);
  });
}
