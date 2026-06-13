import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../Model/hike_session_models.dart';

class ActiveHikeMapPage extends StatelessWidget {
  const ActiveHikeMapPage({super.key, required this.activeHike});

  final ActiveHikeSession activeHike;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MapColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.white),
                        child: CustomPaint(
                          painter: _OfflineMapPainter(
                            color: Color(activeHike.trail.coverColorValue),
                            routePoints: activeHike.routePoints,
                            manualPins: activeHike.manualPinLocations,
                            latestLocation: activeHike.latestLocation,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: _MapLegend(activeHike: activeHike),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _StatusCard(activeHike: activeHike),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Active Offline Map',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _MapColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.activeHike});

  final ActiveHikeSession activeHike;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activeHike.trail.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _MapColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            const _LegendRow(color: _MapColors.green, label: 'Recorded trail'),
            const _LegendRow(color: _MapColors.red, label: 'Pinned location'),
            const _LegendRow(color: _MapColors.blue, label: 'Latest GPS'),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _MapColors.secondaryText,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.activeHike});

  final ActiveHikeSession activeHike;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _Glyph(icon: Icons.cloud_off_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No connection available. Your trail and emergency data are being stored on this phone. ${activeHike.queuedUpdates} location updates are waiting to sync.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _MapColors.text,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineMapPainter extends CustomPainter {
  const _OfflineMapPainter({
    required this.color,
    required this.routePoints,
    required this.manualPins,
    required this.latestLocation,
  });

  final Color color;
  final List<HikeCoordinate> routePoints;
  final List<HikeManualPin> manualPins;
  final HikeCoordinate? latestLocation;

  @override
  void paint(Canvas canvas, Size size) {
    final terrainPaint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final contourPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final routePaint = Paint()
      ..color = _MapColors.green
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final plannedPaint = Paint()
      ..color = _MapColors.green.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;

    canvas.drawRect(Offset.zero & size, terrainPaint);

    for (var index = 0; index < 7; index++) {
      final path = Path()
        ..moveTo(-20, size.height * (0.16 + index * 0.11))
        ..cubicTo(
          size.width * 0.24,
          size.height * (0.03 + index * 0.10),
          size.width * 0.55,
          size.height * (0.26 + index * 0.08),
          size.width + 20,
          size.height * (0.14 + index * 0.10),
        );
      canvas.drawPath(path, contourPaint);
    }

    final visiblePoints = <HikeCoordinate>[
      ...routePoints,
      for (final pin in manualPins) pin.coordinate,
      if (latestLocation != null) latestLocation!,
    ];
    if (visiblePoints.length < 2) {
      _drawMarker(
        canvas,
        Offset(size.width * 0.5, size.height * 0.5),
        _MapColors.blue,
      );
      return;
    }

    final bounds = _CoordinateBounds.from(visiblePoints);
    final projectedRoute = routePoints
        .map((point) => bounds.project(point, size))
        .toList();
    final route = Path();
    if (projectedRoute.isNotEmpty) {
      route.moveTo(projectedRoute.first.dx, projectedRoute.first.dy);
      for (final point in projectedRoute.skip(1)) {
        route.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(route, plannedPaint);
    canvas.drawPath(route, routePaint);

    if (projectedRoute.isNotEmpty) {
      _drawMarker(canvas, projectedRoute.first, _MapColors.green);
    }

    for (final pin in manualPins) {
      _drawMarker(canvas, bounds.project(pin.coordinate, size), _MapColors.red);
    }
    if (latestLocation != null) {
      _drawMarker(
        canvas,
        bounds.project(latestLocation!, size),
        _MapColors.blue,
      );
    }
  }

  void _drawMarker(Canvas canvas, Offset center, Color color) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, 9, fill);
    canvas.drawCircle(center, 9, stroke);
  }

  @override
  bool shouldRepaint(covariant _OfflineMapPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.routePoints != routePoints ||
        oldDelegate.manualPins != manualPins ||
        oldDelegate.latestLocation != latestLocation;
  }
}

class _CoordinateBounds {
  const _CoordinateBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  factory _CoordinateBounds.from(List<HikeCoordinate> points) {
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }
    if ((maxLatitude - minLatitude).abs() < 0.0001) {
      minLatitude -= 0.00005;
      maxLatitude += 0.00005;
    }
    if ((maxLongitude - minLongitude).abs() < 0.0001) {
      minLongitude -= 0.00005;
      maxLongitude += 0.00005;
    }
    return _CoordinateBounds(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );
  }

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  Offset project(HikeCoordinate coordinate, Size size) {
    const padding = 24.0;
    final xRatio =
        (coordinate.longitude - minLongitude) / (maxLongitude - minLongitude);
    final yRatio =
        1 - (coordinate.latitude - minLatitude) / (maxLatitude - minLatitude);
    return Offset(
      padding + xRatio * (size.width - padding * 2),
      padding + yRatio * (size.height - padding * 2),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _MapColors.green, size: 20),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _MapColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

abstract final class _MapColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFE11D48);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
}
