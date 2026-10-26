import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'route_preview_camera.dart' show routePreviewCardinalDirection;

/// Displays the map compass.
class MapCompass extends StatelessWidget {
  /// Creates map compass.
  const MapCompass({super.key, required this.bearing});

  final double bearing;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final normalized = bearing.isFinite ? (bearing % 360 + 360) % 360 : 0.0;
    final cardinal = routePreviewCardinalDirection(normalized);
    return Semantics(
      label: 'Compass. Heading ${normalized.round()} degrees $cardinal',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xEA101A14),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x7734A853), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 9,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 7,
                child: Transform.rotate(
                  angle: -normalized * math.pi / 180,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'N',
                        style: TextStyle(
                          color: Color(0xFFFF6B61),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      Icon(
                        Icons.navigation_rounded,
                        size: 24,
                        color: Color(0xFFFF6B61),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                child: Text(
                  '${normalized.round()}° $cardinal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
