import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'map_utils.dart';

const int routeEndpointRed = 0xFFE53935;
const double _overlappingEndpointDistanceMeters = 75;

Future<Uint8List>? _routeEndpointPinImageFuture;

/// Returns a crisp, Google-Maps-style location pin that does not depend on a
/// particular Mapbox style's sprite catalogue.
Future<Uint8List> routeEndpointPinImage() {
  return _routeEndpointPinImageFuture ??= _drawRouteEndpointPin();
}

bool shouldSeparateRouteEndpointLabels(mapbox.Point start, mapbox.Point end) {
  return distanceMeters(start, end) <= _overlappingEndpointDistanceMeters;
}

mapbox.PointAnnotationOptions routeEndpointAnnotation({
  required mapbox.Point geometry,
  required String label,
  required Uint8List pinImage,
  bool separateLabel = false,
}) {
  final isEnd = label == 'End';
  final textOffset = separateLabel
      ? (isEnd ? const [1.15, -1.7] : const [-1.15, -1.7])
      : const [0.0, -2.05];
  final textAnchor = separateLabel
      ? (isEnd ? mapbox.TextAnchor.BOTTOM_LEFT : mapbox.TextAnchor.BOTTOM_RIGHT)
      : mapbox.TextAnchor.BOTTOM;

  return mapbox.PointAnnotationOptions(
    geometry: geometry,
    image: pinImage,
    iconAnchor: mapbox.IconAnchor.BOTTOM,
    iconSize: 0.72,
    symbolSortKey: 1000,
    textField: label,
    textSize: 13,
    textColor: routeEndpointRed,
    textHaloColor: 0xFFFFFFFF,
    textHaloWidth: 2.4,
    // Most captions stay centered and attached to their own pin. Only nearby
    // loop endpoints fan out beside the pin to avoid overlapping each other.
    textOffset: textOffset,
    textAnchor: textAnchor,
  );
}

Future<Uint8List> _drawRouteEndpointPin() async {
  const width = 72;
  const height = 88;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final pinPath = ui.Path()
    ..moveTo(36, 84)
    ..cubicTo(31, 73, 10, 52, 10, 32)
    ..cubicTo(10, 17.6, 21.6, 6, 36, 6)
    ..cubicTo(50.4, 6, 62, 17.6, 62, 32)
    ..cubicTo(62, 52, 41, 73, 36, 84)
    ..close();

  canvas.save();
  canvas.translate(0, 2);
  canvas.drawPath(
    pinPath,
    ui.Paint()
      ..color = const ui.Color(0x40000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
  );
  canvas.restore();
  canvas.drawPath(
    pinPath,
    ui.Paint()
      ..color = const ui.Color(routeEndpointRed)
      ..style = ui.PaintingStyle.fill,
  );
  canvas.drawPath(
    pinPath,
    ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  canvas.drawCircle(
    const ui.Offset(36, 31),
    9,
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );

  final image = await recorder.endRecording().toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Unable to encode the route endpoint marker.');
    }
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
