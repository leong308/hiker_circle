import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const mapGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
  Factory<OneSequenceGestureRecognizer>(ScaleGestureRecognizer.new),
};

const mapStyleUrls = [
  'https://tiles.openfreemap.org/styles/liberty',
  'https://tiles.openfreemap.org/styles/positron',
  'https://tiles.openfreemap.org/styles/bright',
  'mapbox://styles/mapbox/streets-v12',
  'mapbox://styles/mapbox/outdoors-v12',
  'mapbox://styles/mapbox/satellite-streets-v12',
];

Future<void> enableTerrain3D(MapboxMap map) async {
  try {
    await map.style.addSource(RasterDemSource(
      id: 'mapbox-dem',
      url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
    ));
  } catch (_) {}
  try {
    await map.style
        .setStyleTerrain('{"source": "mapbox-dem", "exaggeration": 1.5}');
  } catch (_) {}
}

void schedulePitch(MapboxMap map, {double pitch = 50}) {
  Future.delayed(const Duration(milliseconds: 300), () {
    map.flyTo(
      CameraOptions(pitch: pitch),
      MapAnimationOptions(duration: 800),
    ).catchError((_) {});
  });
}

const kMapMinZoom = 4.2;
const kMapMaxZoom = 21.0;

Point centerFor(List<Point> points) {
  final bounds = boundsFor(points);
  return Point(
    coordinates: Position(
      (bounds.minLon + bounds.maxLon) / 2,
      (bounds.minLat + bounds.maxLat) / 2,
    ),
  );
}

({double minLat, double maxLat, double minLon, double maxLon}) boundsFor(
  List<Point> points,
) {
  double minLat = points.first.coordinates[1]!.toDouble();
  double maxLat = points.first.coordinates[1]!.toDouble();
  double minLon = points.first.coordinates[0]!.toDouble();
  double maxLon = points.first.coordinates[0]!.toDouble();

  for (final point in points.skip(1)) {
    final lat = point.coordinates[1]!.toDouble();
    final lon = point.coordinates[0]!.toDouble();
    minLat = math.min(minLat, lat);
    maxLat = math.max(maxLat, lat);
    minLon = math.min(minLon, lon);
    maxLon = math.max(maxLon, lon);
  }

  if (minLat == maxLat) {
    minLat -= 0.0005;
    maxLat += 0.0005;
  }
  if (minLon == maxLon) {
    minLon -= 0.0005;
    maxLon += 0.0005;
  }

  return (
    minLat: minLat,
    maxLat: maxLat,
    minLon: minLon,
    maxLon: maxLon,
  );
}

double distanceMeters(Point a, Point b) {
  const earthRadiusMeters = 6371000.0;
  final lat1 = a.coordinates[1]!.toDouble() * math.pi / 180;
  final lat2 = b.coordinates[1]!.toDouble() * math.pi / 180;
  final dLat = (b.coordinates[1]!.toDouble() - a.coordinates[1]!.toDouble()) * math.pi / 180;
  final dLon = (b.coordinates[0]!.toDouble() - a.coordinates[0]!.toDouble()) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(h));
}
