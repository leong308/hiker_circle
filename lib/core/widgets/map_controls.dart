// Map controls provide zoom/reset actions, a geographic scale bar and deferred native-map creation
// for scrolling pages.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'map_utils.dart';
import 'map_compass.dart';

/// One corner layout for all ordinary maps. FPV retains its own playback layout.
class MapControlOverlay extends StatelessWidget {
  /// Creates map control overlay.
  const MapControlOverlay({
    super.key,
    required this.zoomControls,
    required this.styleControls,
    required this.scale,
    required this.bearing,
  });
  final Widget zoomControls;
  final Widget styleControls;
  final Widget scale;
  final double bearing;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned(
        key: const ValueKey('map-controls-zoom'),
        left: 10,
        top: 10,
        child: zoomControls,
      ),
      Positioned(
        key: const ValueKey('map-controls-style'),
        right: 10,
        top: 10,
        child: styleControls,
      ),
      Positioned(
        key: const ValueKey('map-controls-scale'),
        left: 10,
        right: 82,
        bottom: 10,
        child: scale,
      ),
      Positioned(
        key: const ValueKey('map-controls-compass'),
        right: 10,
        bottom: 10,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: MapCompass(bearing: bearing),
        ),
      ),
    ],
  );
}

/// Consistent upper-right picker for every map, including recorded tracks.
class MapStyleControls extends StatelessWidget {
  /// Creates map style controls.
  const MapStyleControls({
    super.key,
    required this.settings,
    required this.onChanged,
    this.showDimensionChoices = true,
  });

  final MapViewSettings settings;
  final ValueChanged<MapViewSettings> onChanged;
  final bool showDimensionChoices;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer.withValues(alpha: 0.96),
      elevation: 3,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<MapViewSettings>(
        tooltip: 'Map style and view',
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.layers_rounded, color: colors.onSurface, size: 21),
        onSelected: onChanged,
        itemBuilder: (context) => [
          const PopupMenuItem<MapViewSettings>(
            enabled: false,
            child: Text('Map style'),
          ),
          for (var index = 0; index < mapStyleNames.length; index++)
            PopupMenuItem<MapViewSettings>(
              key: ValueKey('map-style-option-$index'),
              value: settings.copyWith(styleIndex: index),
              child: _MapSettingChoice(
                label: mapStyleNames[index],
                icon: switch (index) {
                  0 => Icons.terrain_rounded,
                  1 => Icons.signpost_rounded,
                  2 => Icons.satellite_alt_rounded,
                  _ => Icons.map_outlined,
                },
                selected: settings.safeStyleIndex == index,
              ),
            ),
          if (showDimensionChoices) const PopupMenuDivider(),
          for (final dimension
              in showDimensionChoices
                  ? MapDimension.values
                  : const <MapDimension>[])
            PopupMenuItem<MapViewSettings>(
              key: ValueKey('map-dimension-${dimension.name}'),
              value: settings.copyWith(dimension: dimension),
              child: _MapSettingChoice(
                label: dimension == MapDimension.twoD
                    ? '2D · Flat map'
                    : '3D · Terrain',
                icon: dimension == MapDimension.twoD
                    ? Icons.crop_square_rounded
                    : Icons.view_in_ar_rounded,
                selected: settings.dimension == dimension,
              ),
            ),
        ],
      ),
    );
  }
}

/// Displays the map setting choice.
class _MapSettingChoice extends StatelessWidget {
  /// Creates map setting choice.
  const _MapSettingChoice({
    required this.label,
    required this.icon,
    required this.selected,
  });
  final String label;
  final IconData icon;
  final bool selected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
      const SizedBox(width: 8),
      if (selected) const Icon(Icons.check_rounded, size: 20),
    ],
  );
}

/// Displays the map scale with style.
class MapScaleWithStyle extends StatelessWidget {
  /// Creates map scale with style.
  const MapScaleWithStyle({
    super.key,
    required this.zoom,
    required this.latitude,
    required this.settings,
    this.styleName,
  });

  final double zoom;
  final double latitude;
  final MapViewSettings settings;
  final String? styleName;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 6,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          MapScaleBar(zoom: zoom, latitude: latitude),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth.isFinite
                  ? math.min(210, constraints.maxWidth)
                  : 210,
            ),
            child: Semantics(
              label:
                  'Map style: ${styleName ?? settings.styleName}, ${settings.dimensionLabel}',
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text(
                      '${styleName ?? settings.styleName} · ${settings.dimensionLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the map zoom controls.
class MapZoomControls extends StatelessWidget {
  /// Creates map zoom controls.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the map zoom button.
class MapZoomButton extends StatelessWidget {
  /// Creates map zoom button.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the mini divider.
class _MiniDivider extends StatelessWidget {
  /// Creates mini divider.
  const _MiniDivider();

  /// Builds this widget from its current presentation state.
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

/// Displays the map scale bar.
class MapScaleBar extends StatelessWidget {
  /// Creates map scale bar.
  const MapScaleBar({super.key, required this.zoom, required this.latitude});

  final double zoom;
  final double latitude;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    const targetWidth = 72.0;
    final safeLatitude = latitude.isFinite
        ? latitude.clamp(-85.0, 85.0).toDouble()
        : 0.0;
    final safeZoom = zoom.isFinite ? zoom.clamp(0.0, 30.0).toDouble() : 13.5;
    final calculatedMetersPerPixel =
        156543.03392 *
        math.cos(safeLatitude * math.pi / 180).abs() /
        math.pow(2, safeZoom);
    final metersPerPixel =
        calculatedMetersPerPixel.isFinite && calculatedMetersPerPixel > 0
        ? calculatedMetersPerPixel
        : 1.0;
    final distanceMeters = _niceDistance(targetWidth * metersPerPixel);
    final calculatedWidth = distanceMeters / metersPerPixel;
    final width = calculatedWidth.isFinite
        ? calculatedWidth.clamp(34.0, 92.0).toDouble()
        : targetWidth;

    final surface = Theme.of(context).colorScheme.surfaceContainer;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: onSurface.withValues(alpha: 0.8),
                      width: 1.4,
                    ),
                    bottom: BorderSide(
                      color: onSurface.withValues(alpha: 0.8),
                      width: 1.4,
                    ),
                    right: BorderSide(
                      color: onSurface.withValues(alpha: 0.8),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Computes nice distance.
  double _niceDistance(double rawMeters) {
    const distances = [
      1000000.0,
      500000.0,
      200000.0,
      100000.0,
      50000.0,
      20000.0,
      10000.0,
      5000.0,
      2000.0,
      1000.0,
      500.0,
      200.0,
      100.0,
      50.0,
      20.0,
      10.0,
      5.0,
    ];

    for (final distance in distances) {
      if (rawMeters >= distance) {
        return distance;
      }
    }
    return 5;
  }

  /// Computes distance label.
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

/// Displays the deferred map.
class DeferredMap extends StatefulWidget {
  /// Creates deferred map.
  const DeferredMap({super.key, required this.child});

  final Widget child;

  /// Creates the presentation state for this widget.
  @override
  State<DeferredMap> createState() => _DeferredMapState();
}

/// Manages the deferred map presentation and lifecycle.
class _DeferredMapState extends State<DeferredMap> {
  var _ready = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return widget.child;
  }
}
