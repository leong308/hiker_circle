import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class CommunityHazard {
  const CommunityHazard({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description = '',
    this.reportedAt,
  });
  final String id;
  final String type;
  final String description;
  final double latitude;
  final double longitude;
  final DateTime? reportedAt;

  static CommunityHazard? fromMap(String id, Map<String, dynamic> data) {
    if (const {'resolved', 'rejected', 'deleted'}.contains(data['status'])) {
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
    return CommunityHazard(
      id: id,
      type: data['hazardType'] is String
          ? data['hazardType'] as String
          : 'Caution',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      description: data['description'] is String
          ? data['description'] as String
          : '',
      reportedAt: time is Timestamp
          ? time.toDate()
          : DateTime.tryParse(
              data['reportedAtLocal'] is String
                  ? data['reportedAtLocal'] as String
                  : '',
            ),
    );
  }
}

class CommunityHazardCluster {
  const CommunityHazardCluster(this.reports);
  final List<CommunityHazard> reports;
  double get latitude => reports.first.latitude;
  double get longitude => reports.first.longitude;
  int get count => reports.length;
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
  Uint8List image,
) => mapbox.PointAnnotationOptions(
  geometry: mapbox.Point(
    coordinates: mapbox.Position(cluster.longitude, cluster.latitude),
  ),
  image: image,
  iconSize: 0.65,
  iconAnchor: mapbox.IconAnchor.CENTER,
);

Future<void> showCommunityHazardDetails(
  BuildContext context,
  CommunityHazardCluster cluster,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: math.min(440, MediaQuery.sizeOf(context).height * .65),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            cluster.count == 1
                ? 'Trail caution'
                : '${cluster.count} nearby reports',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text('Reported by hikers • Not officially verified'),
          for (final report in cluster.reports)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              title: Text(report.type),
              subtitle: Text(
                [
                  if (report.description.isNotEmpty) report.description,
                  if (report.reportedAt != null)
                    report.reportedAt!.toLocal().toString().split('.').first,
                ].join('\n'),
              ),
            ),
        ],
      ),
    ),
  ),
);
