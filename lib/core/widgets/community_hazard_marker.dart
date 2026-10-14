import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../trail/View/trail_caution_details.dart';

class CommunityHazard {
  const CommunityHazard({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description = '',
    this.reportedAt,
    this.expiresAt,
    this.status = 'unverified',
    this.reportCount = 1,
    this.resolutionCount = 0,
    this.media = const [],
    this.latestEvidence = const {},
    this.resolutionId,
  });
  final String id;
  final String type;
  final String description;
  final double latitude;
  final double longitude;
  final DateTime? reportedAt, expiresAt;
  final String status;
  final int reportCount, resolutionCount;
  final List<Map<String, dynamic>> media;
  final Map<String, dynamic> latestEvidence;
  final String? resolutionId;
  bool get isResolved => status == 'resolved';
  bool isActiveAt(DateTime now) =>
      !['rejected', 'deleted'].contains(status) &&
      now.isBefore(
        expiresAt ??
            reportedAt?.add(const Duration(days: 7)) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static CommunityHazard? fromMap(
    String id,
    Map<String, dynamic> data, {
    bool includeExpired = false,
    DateTime? now,
  }) {
    if (const {'rejected', 'deleted'}.contains(data['status'])) {
      return null;
    }
    final lat = data['latitude'];
    final lon = data['longitude'];
    if (lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      return null;
    }
    final time = data['reportedAt'];
    final result = CommunityHazard(
      id: id,
      type: data['hazardType'] is String
          ? data['hazardType'] as String
          : 'Caution',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      description: data['description'] is String
          ? data['description'] as String
          : '',
      expiresAt: data['expiresAt'] is Timestamp
          ? (data['expiresAt'] as Timestamp).toDate()
          : DateTime.tryParse('${data['expiresAtLocal'] ?? ''}'),
      status: data['status'] is String
          ? data['status'] as String
          : 'unverified',
      reportCount: data['reportCount'] is num
          ? (data['reportCount'] as num).toInt().clamp(1, 1000000)
          : 1,
      resolutionCount: data['resolutionCount'] is num
          ? (data['resolutionCount'] as num).toInt().clamp(0, 1000000)
          : 0,
      resolutionId: data['resolutionId'] is String
          ? data['resolutionId'] as String
          : null,
      media: cautionMediaFrom(data['media']),
      latestEvidence: data['latestEvidence'] is Map
          ? Map<String, dynamic>.from(data['latestEvidence'] as Map)
          : const {},
      reportedAt: time is Timestamp
          ? time.toDate()
          : DateTime.tryParse(
              data['reportedAtLocal'] is String
                  ? data['reportedAtLocal'] as String
                  : '',
            ),
    );
    return includeExpired || result.isActiveAt(now ?? DateTime.now())
        ? result
        : null;
  }
}

class CommunityHazardCluster {
  const CommunityHazardCluster(this.reports);
  final List<CommunityHazard> reports;
  double get latitude => reports.first.latitude;
  double get longitude => reports.first.longitude;
  int get count => reports.length;
  int get confirmations =>
      reports.fold(0, (total, report) => total + report.reportCount);
  bool get isResolved => reports.every((r) => r.isResolved);
}

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

Future<Uint8List> communityHazardMarkerImage(int count) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _paintCommunityHazardMarker(canvas, count);
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 76);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

/// Matches the single-report marker shown on trail maps.
class CommunityHazardMarkerIcon extends StatelessWidget {
  const CommunityHazardMarkerIcon({super.key});
  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(44, 42),
    painter: _CommunityHazardIconPainter(),
  );
}

class _CommunityHazardIconPainter extends CustomPainter {
  const _CommunityHazardIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80, size.height / 76);
    _paintCommunityHazardMarker(canvas, 1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CommunityHazardIconPainter oldDelegate) => false;
}

void _paintCommunityHazardMarker(Canvas canvas, int count) {
  canvas.drawCircle(const Offset(36, 40), 27, Paint()..color = Colors.white);
  canvas.drawCircle(
    const Offset(36, 40),
    23,
    Paint()..color = const Color(0xFFFFC857),
  );
  final warning = TextPainter(
    text: const TextSpan(
      text: '!',
      style: TextStyle(
        fontSize: 36,
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
  if (count > 1) {
    canvas.drawCircle(const Offset(58, 17), 16, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(58, 17),
      14,
      Paint()..color = const Color(0xFFE24B3C),
    );
    final badge = TextPainter(
      text: TextSpan(
        text: count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badge.paint(canvas, Offset(58 - badge.width / 2, 17 - badge.height / 2));
  }
}

mapbox.PointAnnotationOptions communityHazardAnnotation(
  CommunityHazardCluster cluster,
  Uint8List image, {
  double iconSize = .65,
}) => mapbox.PointAnnotationOptions(
  geometry: mapbox.Point(
    coordinates: mapbox.Position(cluster.longitude, cluster.latitude),
  ),
  image: image,
  iconSize: iconSize,
  iconOpacity: cluster.isResolved ? .35 : 1,
  iconAnchor: mapbox.IconAnchor.CENTER,
);

Future<void> showCommunityHazardDetails(
  BuildContext context,
  CommunityHazardCluster cluster, {
  bool allowFeedback = false,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => TrailCautionDetailsSheet(
    reports: cluster.reports,
    allowFeedback: allowFeedback,
  ),
);

List<Map<String, dynamic>> cautionMediaFrom(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where(
            (m) =>
                m['url'] is String &&
                Uri.tryParse(m['url'] as String)?.scheme == 'https' &&
                m['contentType'] is String,
          )
          .toList()
    : const [];

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

class CautionMarkerSizer {
  final _markers = <String, (mapbox.PointAnnotation, double)>{};
  mapbox.PointAnnotationManager? _manager;
  double _factor = 1;
  bool _updating = false, _dirty = false;
  void clear() => _markers.clear();
  void add(mapbox.PointAnnotation marker, double baseSize) {
    _markers[marker.id] = (marker, baseSize);
    _dirty = true;
  }

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
class CommunityCautionMapLayer {
  CommunityCautionMapLayer({required this.onTap});
  final void Function(CommunityHazardCluster) onTap;
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

  void setReports(List<CommunityHazardCluster> reports) {
    if (_disposed) return;
    _reports = reports;
    _revision++;
    _dirty = true;
    unawaited(_render());
  }

  void setScale(double zoom, double latitude) {
    _factor = cautionMarkerScale(zoom, latitude) / .65;
    unawaited(_sizer.resize(_manager, _factor));
  }

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
              if (_disposed || generation != _generation) return;
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
                await manager.deleteAll();
                if (_disposed || generation != _generation) return;
                _byId.clear();
                _sizer.clear();
                final images = await Future.wait(
                  reports.map(
                    (r) => communityHazardMarkerImage(r.confirmations),
                  ),
                );
                if (_disposed || generation != _generation) return;
                final annotations = await manager.createMulti([
                  for (var i = 0; i < reports.length; i++)
                    communityHazardAnnotation(
                      reports[i],
                      images[i],
                      iconSize: .65 * _factor,
                    ),
                ]);
                if (_disposed || generation != _generation) return;
                for (var i = 0; i < annotations.length; i++) {
                  final annotation = annotations[i];
                  if (annotation != null) {
                    _byId[annotation.id] = reports[i];
                    _sizer.add(annotation, .65);
                  }
                }
                await _sizer.resize(manager, _factor);
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

  void reset() {
    _generation++;
    _tap?.cancel();
    _tap = null;
    final old = _manager;
    if (old != null) unawaited(old.deleteAll().catchError((Object _) {}));
    _manager = null;
    _map = null;
    _attaching = null;
    _rendering = null;
    _byId.clear();
    _sizer.clear();
  }

  void dispose() {
    reset();
    _disposed = true;
  }
}
