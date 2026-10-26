import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../Model/hike_session_models.dart';

/// Fit the actual GPS trace in a north-up Mercator viewport. Unwrap longitude
/// across the date line and preserve aspect ratio, including stationary tracks.
List<ui.Offset> projectRecordedHikeRoute(
  List<HikeCoordinate> coordinates,
  ui.Rect viewport,
) {
  final points = <ui.Offset>[];
  double? previousLongitude;
  for (final coordinate in coordinates.where(
    (point) => point.hasValidPosition,
  )) {
    var longitude = coordinate.longitude;
    if (previousLongitude != null) {
      while (longitude - previousLongitude > 180) {
        longitude -= 360;
      }
      while (longitude - previousLongitude < -180) {
        longitude += 360;
      }
    }
    previousLongitude = longitude;
    final latitude =
        coordinate.latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    points.add(
      ui.Offset(
        6378137 * longitude * math.pi / 180,
        -6378137 * math.log(math.tan(math.pi / 4 + latitude / 2)),
      ),
    );
  }
  if (points.isEmpty) return const [];
  var minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
  for (final point in points) {
    minX = math.min(minX, point.dx);
    maxX = math.max(maxX, point.dx);
    minY = math.min(minY, point.dy);
    maxY = math.max(maxY, point.dy);
  }
  final scale = math.min(
    viewport.width / math.max(maxX - minX, 30),
    viewport.height / math.max(maxY - minY, 30),
  );
  final center = ui.Offset((minX + maxX) / 2, (minY + maxY) / 2);
  return [
    for (final point in points) viewport.center + (point - center) * scale,
  ];
}

/// Render a shareable PNG from recorded movement, without network tiles or
/// inventing a planned trail. The card is deliberately labelled as a GPS trace.
abstract final class HikeShareCardRenderer {
  /// Computes render.
  static Future<Uint8List?> render({
    required ActiveHikeSession hike,
    required HikeSummaryReport report,
  }) async {
    final coordinates = HikeSummaryReport.recordedRoutePointsFor(hike);
    if (coordinates.isEmpty) return null;
    const width = 1080, height = 1350;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const forest = ui.Color(0xFF12271E),
        green = ui.Color(0xFF80D6A3),
        white = ui.Color(0xFFF5FAF7);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1080, 1350),
      ui.Paint()..color = forest,
    );
    _text(
      canvas,
      'HIKERCIRCLE',
      const ui.Offset(64, 53),
      width: 650,
      size: 25,
      color: green,
      weight: FontWeight.w800,
    );
    _text(
      canvas,
      'HIKE COMPLETED',
      const ui.Offset(64, 106),
      width: 950,
      size: 18,
      color: green,
    );
    _text(
      canvas,
      report.trailName,
      const ui.Offset(64, 145),
      width: 952,
      size: 45,
      color: white,
      weight: FontWeight.w800,
      maxLines: 2,
    );
    _text(
      canvas,
      _date(report.endedAt),
      const ui.Offset(64, 268),
      width: 900,
      size: 23,
      color: const ui.Color(0xFFB6C9BE),
    );

    const mapRect = ui.Rect.fromLTWH(64, 326, 952, 665);
    canvas.save();
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(mapRect, const ui.Radius.circular(28)),
    );
    canvas.drawRect(mapRect, ui.Paint()..color = const ui.Color(0xFFEDF3ED));
    final gridPaint = ui.Paint()
      ..color = const ui.Color(0xFFD8E3D9)
      ..strokeWidth = 1;
    for (var x = mapRect.left; x < mapRect.right; x += 64) {
      canvas.drawLine(
        ui.Offset(x, mapRect.top),
        ui.Offset(x, mapRect.bottom),
        gridPaint,
      );
    }
    for (var y = mapRect.top; y < mapRect.bottom; y += 64) {
      canvas.drawLine(
        ui.Offset(mapRect.left, y),
        ui.Offset(mapRect.right, y),
        gridPaint,
      );
    }
    final points = projectRecordedHikeRoute(coordinates, mapRect.deflate(105));
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    var previous = points.first;
    for (final point in points.skip(1)) {
      if ((point - previous).distance >= 0.6 || identical(point, points.last)) {
        path.lineTo(point.dx, point.dy);
        previous = point;
      }
    }
    for (final (color, stroke) in [
      (const ui.Color(0xFFFFFFFF), 15.0),
      (const ui.Color(0xFF258553), 8.0),
    ]) {
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = color
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round,
      );
    }
    _marker(canvas, points.first, const ui.Color(0xFF258553), 17);
    final closeFinish = (points.last - points.first).distance < 40;
    _marker(
      canvas,
      points.last,
      const ui.Color(0xFFE7934C),
      closeFinish ? 9 : 17,
    );
    _text(
      canvas,
      points.length == 1
          ? 'Recorded location'
          : closeFinish
          ? 'Start / Finish'
          : 'Start',
      ui.Offset(
        (points.first.dx - 55).clamp(mapRect.left + 16, mapRect.right - 186),
        points.first.dy - 48,
      ),
      width: 170,
      size: 20,
      color: forest,
      weight: FontWeight.w700,
    );
    if (!closeFinish) {
      _text(
        canvas,
        'Finish',
        points.last + const ui.Offset(-30, 28),
        width: 100,
        size: 20,
        color: forest,
        weight: FontWeight.w700,
      );
    }
    _text(
      canvas,
      'N ↑',
      ui.Offset(mapRect.right - 77, mapRect.top + 22),
      width: 65,
      size: 22,
      color: forest,
    );
    _text(
      canvas,
      points.length > 1 ? 'RECORDED GPS PATH · NORTH UP' : 'RECORDED LOCATION',
      ui.Offset(mapRect.left + 24, mapRect.bottom - 45),
      width: 850,
      size: 18,
      color: const ui.Color(0xFF4B6554),
    );
    canvas.restore();
    _metric(
      canvas,
      64,
      'DISTANCE',
      '${report.distanceKm.toStringAsFixed(2)} km',
    );
    _metric(canvas, 420, 'DURATION', _duration(report.duration));
    _metric(
      canvas,
      760,
      'AVG. SPEED',
      '${report.averageSpeedKmh.toStringAsFixed(2)} km/h',
    );
    _text(
      canvas,
      'Recorded with HikerCircle',
      const ui.Offset(64, 1239),
      width: 950,
      size: 24,
      color: green,
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Computes marker.
  static void _marker(
    ui.Canvas canvas,
    ui.Offset point,
    ui.Color color,
    double radius,
  ) {
    canvas.drawCircle(
      point,
      radius + 4,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawCircle(point, radius, ui.Paint()..color = color);
  }

  /// Computes metric.
  static void _metric(
    ui.Canvas canvas,
    double left,
    String label,
    String value,
  ) {
    _text(
      canvas,
      label,
      ui.Offset(left, 1053),
      width: 300,
      size: 17,
      color: const ui.Color(0xFFB6C9BE),
    );
    _text(
      canvas,
      value,
      ui.Offset(left, 1092),
      width: 300,
      size: 32,
      color: const ui.Color(0xFFF5FAF7),
      weight: FontWeight.w800,
    );
  }

  /// Computes text.
  static void _text(
    ui.Canvas canvas,
    String value,
    ui.Offset offset, {
    required double width,
    required double size,
    required ui.Color color,
    FontWeight weight = FontWeight.w500,
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.2,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
    painter.dispose();
  }

  /// Computes duration.
  static String _duration(Duration value) => value.inHours > 0
      ? '${value.inHours}h ${value.inMinutes.remainder(60)}m'
      : value.inMinutes > 0
      ? '${value.inMinutes}m ${value.inSeconds.remainder(60)}s'
      : '${value.inSeconds}s';

  /// Computes date.
  static String _date(DateTime value) {
    final date = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
