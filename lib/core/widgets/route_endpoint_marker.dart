import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

const int routeEndpointRed = 0xFFE53935;

Future<Uint8List>? _routeEndpointPinImageFuture;

/// Returns a crisp, Google-Maps-style location pin that does not depend on a
/// particular Mapbox style's sprite catalogue.
Future<Uint8List> routeEndpointPinImage() {
  return _routeEndpointPinImageFuture ??= _drawRouteEndpointPin();
}

mapbox.PointAnnotationOptions routeEndpointAnnotation({
  required mapbox.Point geometry,
  required String label,
  required Uint8List pinImage,
}) {
  return mapbox.PointAnnotationOptions(
    geometry: geometry,
    image: pinImage,
    iconAnchor: mapbox.IconAnchor.BOTTOM,
    iconSize: 0.5,
    symbolSortKey: 1000,
    textField: label,
    textSize: 13,
    textColor: routeEndpointRed,
    textHaloColor: 0xFFFFFFFF,
    textHaloWidth: 2.4,
    // Keep the caption visually attached to the top of the half-scale pin.
    // Mapbox offsets are expressed in ems, so reducing the negative offset
    // moves Start/End down without shifting the geographic pin itself.
    textOffset: const [0.0, -2.5],
    textAnchor: mapbox.TextAnchor.BOTTOM,
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
