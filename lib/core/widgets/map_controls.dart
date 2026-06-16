import 'dart:math' as math;

import 'package:flutter/material.dart';

class MapZoomControls extends StatelessWidget {
  const MapZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    this.onLayer,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback? onLayer;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainer;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MapZoomButton(
            tooltip: 'Zoom in',
            icon: Icons.add_rounded,
            onPressed: onZoomIn,
            color: onSurface,
          ),
          const _MiniDivider(),
          MapZoomButton(
            tooltip: 'Zoom out',
            icon: Icons.remove_rounded,
            onPressed: onZoomOut,
            color: onSurface,
          ),
          const _MiniDivider(),
          MapZoomButton(
            tooltip: 'Fit map',
            icon: Icons.center_focus_strong_rounded,
            onPressed: onReset,
            color: onSurface,
          ),
          if (onLayer != null) ...[
            const _MiniDivider(),
            MapZoomButton(
              tooltip: 'Change map style',
              icon: Icons.layers_rounded,
              onPressed: onLayer!,
              color: onSurface,
            ),
          ],
        ],
      ),
    );
  }
}

class MapZoomButton extends StatelessWidget {
  const MapZoomButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MiniDivider extends StatelessWidget {
  const _MiniDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class MapScaleBar extends StatelessWidget {
  const MapScaleBar({super.key, required this.zoom, required this.latitude});

  final double zoom;
  final double latitude;

  @override
  Widget build(BuildContext context) {
    const targetWidth = 72.0;
    final metersPerPixel = 156543.03392 *
        math.cos(latitude * math.pi / 180).abs() /
        math.pow(2, zoom);
    final distanceMeters = _niceDistance(targetWidth * metersPerPixel);
    final width = (distanceMeters / metersPerPixel).clamp(34.0, 92.0);

    final surface = Theme.of(context).colorScheme.surfaceContainer;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x77000000), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _distanceLabel(distanceMeters),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: width,
              height: 8,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xBB111111), width: 1.4),
                    bottom: BorderSide(color: Color(0xBB111111), width: 1.4),
                    right: BorderSide(color: Color(0xBB111111), width: 1.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _niceDistance(double rawMeters) {
    const distances = [
      1000000.0, 500000.0, 200000.0, 100000.0,
      50000.0, 20000.0, 10000.0, 5000.0,
      2000.0, 1000.0, 500.0, 200.0,
      100.0, 50.0, 20.0, 10.0, 5.0,
    ];

    for (final distance in distances) {
      if (rawMeters >= distance) {
        return distance;
      }
    }
    return 5;
  }

  String _distanceLabel(double meters) {
    if (meters >= 1000) {
      final kilometers = meters / 1000;
      return kilometers >= 100
          ? '${kilometers.round()} km'
          : '${kilometers.toStringAsFixed(kilometers >= 10 ? 0 : 1)} km';
    }
    return '${meters.round()} m';
  }
}
