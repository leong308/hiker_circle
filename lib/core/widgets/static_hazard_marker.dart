import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/local_session_database.dart';

Future<Uint8List>? _staticHazardMarkerImageFuture;

/// A style-independent caution marker. Using a rendered PNG avoids relying on
/// emoji/font coverage inside the native Mapbox renderer.
Future<Uint8List> staticHazardMarkerImage() {
  return _staticHazardMarkerImageFuture ??= _drawStaticHazardMarker();
}

mapbox.PointAnnotationOptions staticHazardAnnotation(
  LocalTrailHazardMatch match,
  Uint8List markerImage,
) {
  return mapbox.PointAnnotationOptions(
    geometry: mapbox.Point(
      coordinates: mapbox.Position(
        match.hazard.longitude,
        match.hazard.latitude,
      ),
    ),
    image: markerImage,
    iconAnchor: mapbox.IconAnchor.CENTER,
    iconSize: match.hazard.severity == 'warning' ? 0.72 : 0.64,
    symbolSortKey: 900,
    customData: {'hazard_id': match.hazard.hazardId},
  );
}

Future<void> showStaticHazardDetails(
  BuildContext context,
  LocalTrailHazardMatch match,
) {
  final hazard = match.hazard;
  final downloaded = MaterialLocalizations.of(
    context,
  ).formatMediumDate(hazard.downloadedAt.toLocal());
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 30,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hazard.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(hazard.description),
              const SizedBox(height: 12),
              Text(
                hazard.safetyGuidance,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Text(
                '${hazard.sourceName} · downloaded $downloaded · ${hazard.confidence.replaceAll('_', ' ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Mapped caution only—not a guarantee that the route is safe or that conditions are current.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<Uint8List> _drawStaticHazardMarker() async {
  const width = 80;
  const height = 72;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final triangle = ui.Path()
    ..moveTo(40, 5)
    ..lineTo(75, 65)
    ..quadraticBezierTo(76, 68, 71, 68)
    ..lineTo(9, 68)
    ..quadraticBezierTo(4, 68, 5, 65)
    ..close();

  canvas.save();
  canvas.translate(0, 2);
  canvas.drawPath(
    triangle,
    ui.Paint()
      ..color = const ui.Color(0x44000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
  );
  canvas.restore();
  canvas.drawPath(
    triangle,
    ui.Paint()
      ..color = const ui.Color(0xFFF59E0B)
      ..style = ui.PaintingStyle.fill,
  );
  canvas.drawPath(
    triangle,
    ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(36.5, 24, 7, 23),
      const ui.Radius.circular(3.5),
    ),
    ui.Paint()..color = const ui.Color(0xFF3B2F16),
  );
  canvas.drawCircle(
    const ui.Offset(40, 56),
    4,
    ui.Paint()..color = const ui.Color(0xFF3B2F16),
  );

  final image = await recorder.endRecording().toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Unable to encode the static hazard marker.');
    }
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
