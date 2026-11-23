// Community caution map widgets decode, cluster and render community hazard markers with access to
// their detail sheets.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../trail/Model/trail_hazard_categories.dart';
import '../../trail/Model/community_hazard.dart';
export '../../trail/Model/community_hazard.dart';
import '../../trail/View/trail_caution_details.dart';

/// Represents community hazard cluster.
class CommunityHazardCluster {
  /// Creates community hazard cluster.
  const CommunityHazardCluster(this.reports);
  final List<CommunityHazard> reports;

  /// Returns latitude.
  double get latitude => reports.first.latitude;

  /// Returns longitude.
  double get longitude => reports.first.longitude;

  /// Returns count.
  int get count => reports.length;

  /// Returns confirmations.
  int get confirmations =>
      reports.fold(0, (total, report) => total + report.reportCount);

  /// Returns is resolved.
  bool get isResolved => reports.every((r) => r.isResolved);

  /// Returns has serious risk.
  bool get hasSeriousRisk => reports.any((r) => r.isFatal && !r.isResolved);

  /// Returns lead report.
  CommunityHazard get leadReport => reports.firstWhere(
    (r) => r.isFatal && !r.isResolved,
    orElse: () => reports.firstWhere(
      (r) => trailHazardCategoryFor(r.type) == 'Weather',
      orElse: () => reports.first,
    ),
  );
}

/// Computes cluster community hazards.
List<CommunityHazardCluster> clusterCommunityHazards(
  Iterable<CommunityHazard> reports,
) {
  final clusters = <List<CommunityHazard>>[];
  final seen = <String>{};
  for (final report in reports) {
    if (!seen.add(report.id)) continue;
    List<CommunityHazard>? nearest;
    var distance = 40.0;
    for (final group in clusters) {
      final dLat = (report.latitude - group.first.latitude) * math.pi / 180;
      final dLon = (report.longitude - group.first.longitude) * math.pi / 180;
      final a =
          math.pow(math.sin(dLat / 2), 2) +
          math.cos(report.latitude * math.pi / 180) *
              math.cos(group.first.latitude * math.pi / 180) *
              math.pow(math.sin(dLon / 2), 2);
      final meters = 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
      if (meters <= distance) {
        nearest = group;
        distance = meters;
      }
    }
    if (nearest == null) {
      clusters.add([report]);
    } else {
      nearest.add(report);
    }
  }
  return clusters
      .map((reports) => CommunityHazardCluster(List.unmodifiable(reports)))
      .toList();
}

/// Computes community hazard marker image.
Future<Uint8List> communityHazardMarkerImage(
  int count, {
  String? type,
  bool seriousRisk = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _paintCommunityHazardMarker(
    canvas,
    count,
    type: type,
    seriousRisk: seriousRisk,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 76);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

/// Matches the single-report marker shown on trail maps.
class CommunityHazardMarkerIcon extends StatelessWidget {
  /// Creates community hazard marker icon.
  const CommunityHazardMarkerIcon({super.key});

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(44, 42),
    painter: _CommunityHazardIconPainter(),
  );
}

/// Represents community hazard icon painter.
class _CommunityHazardIconPainter extends CustomPainter {
  /// Creates community hazard icon painter.
  const _CommunityHazardIconPainter();

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80, size.height / 76);
    _paintCommunityHazardMarker(canvas, 1);
    canvas.restore();
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(_CommunityHazardIconPainter oldDelegate) => false;
}

/// Computes paint community hazard marker.
void _paintCommunityHazardMarker(
  Canvas canvas,
  int count, {
  String? type,
  bool seriousRisk = false,
}) {
  canvas.drawCircle(const Offset(36, 40), 27, Paint()..color = Colors.white);
  canvas.drawCircle(
    const Offset(36, 40),
    23,
    Paint()..color = const Color(0xFFFFC857),
  );
  final icon = type == null ? null : trailHazardIconFor(type);
  final warning = TextPainter(
    text: TextSpan(
      text: icon == null ? '!' : String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon?.fontFamily ?? 'Inter',
        package: icon?.fontPackage,
        fontSize: icon == null ? 36 : 32,
        fontWeight: FontWeight.w900,
        color: Color(0xFF342500),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  warning.paint(
    canvas,
    Offset(36 - warning.width / 2, 39 - warning.height / 2),
  );
  if (seriousRisk) {
    canvas.drawCircle(const Offset(58, 17), 15, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(58, 17),
      13,
      Paint()..color = const Color(0xFFD32F2F),
    );
    // Draw the small exclamation directly so its shape stays crisp at map scale.
    canvas.drawLine(
      const Offset(58, 11),
      const Offset(58, 17),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(58, 23), 1.8, Paint()..color = Colors.white);
  }
  if (count > 1) {
    final center = seriousRisk ? const Offset(60, 60) : const Offset(58, 17);
    canvas.drawCircle(center, 16, Paint()..color = Colors.white);
    canvas.drawCircle(center, 14, Paint()..color = const Color(0xFFE24B3C));
    final badge = TextPainter(
      text: TextSpan(
        text: count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badge.paint(
      canvas,
      Offset(center.dx - badge.width / 2, center.dy - badge.height / 2),
    );
  }
}

/// Computes community hazard annotation.
mapbox.PointAnnotationOptions communityHazardAnnotation(
  CommunityHazardCluster cluster,
  Uint8List image, {
  double iconSize = .65,
  bool placeBelowLocation = false,
}) => mapbox.PointAnnotationOptions(
  geometry: mapbox.Point(
    coordinates: mapbox.Position(cluster.longitude, cluster.latitude),
  ),
  image: image,
  iconSize: iconSize,
  iconOpacity: cluster.isResolved ? .35 : 1,
  iconAnchor: placeBelowLocation
      ? mapbox.IconAnchor.TOP
      : mapbox.IconAnchor.CENTER,
  iconOffset: placeBelowLocation ? const [0, 16] : null,
);

/// Shows community hazard details.
Future<void> showCommunityHazardDetails(
  BuildContext context,
  CommunityHazardCluster cluster, {
  bool allowFeedback = false,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  clipBehavior: Clip.antiAlias,
  builder: (_) => TrailCautionDetailsSheet(
    reports: cluster.reports,
    allowFeedback: allowFeedback,
  ),
);

/// 38 logical pixels represent roughly a centimetre on typical phone screens.
/// Grow continuously from the 100 m scale to 3.5 times the size at 10 m.
double cautionMarkerScale(double zoom, double latitude) {
  final metersPerCm =
      156543.03392 *
      math.cos(latitude * math.pi / 180) /
      math.pow(2, zoom) *
      38;
  final progress = (math.log(100 / metersPerCm) / math.ln10).clamp(0.0, 1.0);
  return .65 * (1 + progress * 2.5);
}

/// Represents caution marker sizer.
class CautionMarkerSizer {
  final _markers = <String, (mapbox.PointAnnotation, double)>{};
  mapbox.PointAnnotationManager? _manager;
  double _factor = 1;
  bool _updating = false, _dirty = false;

  /// Clears.
  void clear() => _markers.clear();

  /// Adds.
  void add(mapbox.PointAnnotation marker, double baseSize) {
    _markers[marker.id] = (marker, baseSize);
    _dirty = true;
  }

  /// Computes resize.
  Future<void> resize(
    mapbox.PointAnnotationManager? manager,
    double factor,
  ) async {
    if (manager == null ||
        (factor - _factor).abs() < .02 &&
            identical(manager, _manager) &&
            !_dirty) {
      return;
    }
    _manager = manager;
    _factor = factor;
    _dirty = true;
    if (_updating) return;
    _updating = true;
    try {
      while (_dirty) {
        _dirty = false;
        final current = _manager!, scale = _factor;
        await Future.wait([
          for (final item in _markers.values.toList())
            (() async {
              item.$1.iconSize = item.$2 * scale;
              try {
                await current.update(item.$1);
              } catch (_) {
                /* A replaced map may have removed this marker. */
              }
            })(),
        ]);
      }
    } finally {
      _updating = false;
    }
  }
}

/// Community changes update their own annotation layer. Route geometry and the
/// playback controller are never cleared or restarted by a vote or expiry.
class CommunityCautionMapLayer with WidgetsBindingObserver {
  /// Creates community caution map layer.
  CommunityCautionMapLayer({
    required this.onTap,
    this.placeBelowLocation = false,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }
  final void Function(CommunityHazardCluster) onTap;
  final bool placeBelowLocation;
  final _sizer = CautionMarkerSizer();
  final _byId = <String, CommunityHazardCluster>{};
  List<CommunityHazardCluster> _reports = const [];
  mapbox.MapboxMap? _map;
  mapbox.PointAnnotationManager? _manager;
  mapbox.Cancelable? _tap;
  Future<void>? _attaching, _rendering;
  int _generation = 0, _styleGeneration = -1, _revision = 0;
  double _factor = 1;
  bool _dirty = false, _disposed = false;
  final _badgeMarkers = <mapbox.PointAnnotation>[];
  Timer? _badgeTimer;
  Future<void>? _badgeUpdate;
  bool _animationsEnabled = true, _foreground = true, _badgeBright = true;
  bool _badgeDirty = false;

  /// Sets animations enabled.
  void setAnimationsEnabled(bool enabled) {
    if (_animationsEnabled == enabled) return;
    _animationsEnabled = enabled;
    _syncBadgeTimer();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncBadgeTimer();
  }

  /// Synchronizes badge timer.
  void _syncBadgeTimer() {
    if (_disposed ||
        _badgeMarkers.isEmpty ||
        !_animationsEnabled ||
        !_foreground) {
      _badgeTimer?.cancel();
      _badgeTimer = null;
      if (!_badgeBright) {
        _badgeBright = true;
        unawaited(_updateBadgeFrames());
      }
      return;
    }
    _badgeTimer ??= Timer.periodic(const Duration(milliseconds: 900), (_) {
      _badgeBright = !_badgeBright;
      unawaited(_updateBadgeFrames());
    });
  }

  /// Updates badge frames.
  Future<void> _updateBadgeFrames() {
    if (_disposed || _manager == null || _badgeMarkers.isEmpty) {
      return Future.value();
    }
    _badgeDirty = true;
    if (_badgeUpdate != null) return _badgeUpdate!;
    final manager = _manager!, generation = _generation;
    late Future<void> updating;
    updating =
        (() async {
          while (_badgeDirty && !_disposed && generation == _generation) {
            _badgeDirty = false;
            final opacity = _badgeBright ? 1.0 : .72;
            for (final annotation in _badgeMarkers.toList()) {
              if (_disposed || generation != _generation) return;
              // Pulse the registered icon without replacing its image.
              annotation.iconOpacity = opacity;
              try {
                await manager.update(annotation);
              } catch (_) {
                // A style change may have removed this annotation.
              }
            }
          }
        })().whenComplete(() {
          if (identical(_badgeUpdate, updating)) _badgeUpdate = null;
        });
    _badgeUpdate = updating;
    return updating;
  }

  /// Sets reports.
  void setReports(List<CommunityHazardCluster> reports) {
    if (_disposed) return;
    _reports = reports;
    _revision++;
    _dirty = true;
    unawaited(_render());
  }

  /// Sets scale.
  void setScale(double zoom, double latitude) {
    _factor = cautionMarkerScale(zoom, latitude) / .65;
    unawaited(_sizer.resize(_manager, _factor));
  }

  /// Computes attach.
  Future<void> attach(mapbox.MapboxMap map, int styleGeneration) {
    if (_disposed) return Future.value();
    if (identical(map, _map) &&
        _styleGeneration == styleGeneration &&
        (_manager != null || _attaching != null)) {
      return _attaching ?? _render();
    }
    reset();
    _map = map;
    _styleGeneration = styleGeneration;
    final generation = _generation;
    late Future<void> attaching;
    attaching =
        (() async {
              final manager = await map.annotations
                  .createPointAnnotationManager();
              if (_disposed || generation != _generation) {
                try {
                  await map.annotations.removeAnnotationManager(manager);
                } catch (_) {
                  // A detached style may already have removed this manager.
                }
                return;
              }
              _manager = manager;
              await manager.setIconAllowOverlap(true);
              if (_disposed || generation != _generation) return;
              _tap = manager.tapEvents(
                onTap: (annotation) {
                  final report = _byId[annotation.id];
                  if (!_disposed &&
                      generation == _generation &&
                      report != null) {
                    onTap(report);
                  }
                },
              );
              _dirty = true;
              await _render();
            })()
            .catchError((Object _) {
              /* Optional annotations never block the route. */
            })
            .whenComplete(() {
              if (identical(_attaching, attaching)) _attaching = null;
            });
    _attaching = attaching;
    return attaching;
  }

  /// Computes render.
  Future<void> _render() {
    if (_disposed || _manager == null || !_dirty) return Future.value();
    if (_rendering != null) return _rendering!;
    final manager = _manager!, generation = _generation;
    late Future<void> rendering;
    rendering =
        (() async {
              while (!_disposed && generation == _generation && _dirty) {
                _dirty = false;
                final revision = _revision,
                    reports = List<CommunityHazardCluster>.of(_reports);
                _badgeTimer?.cancel();
                _badgeTimer = null;
                _badgeMarkers.clear();
                // Finish a frame already being sent before replacing markers.
                await _badgeUpdate;
                await manager.deleteAll();
                if (_disposed || generation != _generation) return;
                _byId.clear();
                _sizer.clear();
                final images = await Future.wait(
                  reports.map(
                    (r) => communityHazardMarkerImage(
                      r.confirmations,
                      type: r.leadReport.type,
                      seriousRisk: r.hasSeriousRisk,
                    ),
                  ),
                );
                if (_disposed || generation != _generation) return;
                final annotations = await manager.createMulti([
                  for (var i = 0; i < reports.length; i++)
                    communityHazardAnnotation(
                      reports[i],
                      images[i],
                      iconSize: .65 * _factor,
                      placeBelowLocation: placeBelowLocation,
                    ),
                ]);
                if (_disposed || generation != _generation) return;
                for (var i = 0; i < annotations.length; i++) {
                  final annotation = annotations[i];
                  if (annotation != null) {
                    _byId[annotation.id] = reports[i];
                    _sizer.add(annotation, .65);
                    if (reports[i].hasSeriousRisk) {
                      _badgeMarkers.add(annotation);
                    }
                  }
                }
                await _sizer.resize(manager, _factor);
                _badgeBright = true;
                _syncBadgeTimer();
                if (revision != _revision) _dirty = true;
              }
            })()
            .catchError((Object _) {
              /* The map may have changed its style. */
            })
            .whenComplete(() {
              if (identical(_rendering, rendering)) {
                _rendering = null;
                if (_dirty) unawaited(_render());
              }
            });
    _rendering = rendering;
    return rendering;
  }

  /// Resets.
  void reset() {
    unawaited(resetAndWait());
  }

  /// Resets and wait.
  Future<void> resetAndWait() async {
    _generation++;
    _badgeTimer?.cancel();
    _badgeTimer = null;
    _badgeMarkers.clear();
    _badgeUpdate = null;
    _badgeDirty = false;
    _badgeBright = true;
    _tap?.cancel();
    _tap = null;
    final old = _manager;
    final oldMap = _map;
    _manager = null;
    _map = null;
    _attaching = null;
    _rendering = null;
    _byId.clear();
    _sizer.clear();
    if (old != null && oldMap != null) {
      try {
        await oldMap.annotations.removeAnnotationManager(old);
      } catch (_) {
        // The native map/style may already have disposed the old manager.
      }
    }
  }

  /// Releases resources owned by this instance.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    reset();
    _disposed = true;
  }
}
