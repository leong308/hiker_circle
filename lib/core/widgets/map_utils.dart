import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

const mapStyleUrls = [
  'https://tiles.openfreemap.org/styles/liberty',
  'https://tiles.openfreemap.org/styles/positron',
  'https://tiles.openfreemap.org/styles/bright',
];

const kMapMinZoom = 4.2;
const kMapMaxZoom = 21.0;

maplibre.LatLng centerFor(List<maplibre.LatLng> points) {
  final bounds = boundsFor(points);
  return maplibre.LatLng(
    (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
    (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
  );
}

maplibre.LatLngBounds boundsFor(List<maplibre.LatLng> points) {
  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLon = points.first.longitude;
  var maxLon = points.first.longitude;

  for (final point in points.skip(1)) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLon = math.min(minLon, point.longitude);
    maxLon = math.max(maxLon, point.longitude);
  }

  if (minLat == maxLat) {
    minLat -= 0.0005;
    maxLat += 0.0005;
  }
  if (minLon == maxLon) {
    minLon -= 0.0005;
    maxLon += 0.0005;
  }

  return maplibre.LatLngBounds(
    southwest: maplibre.LatLng(minLat, minLon),
    northeast: maplibre.LatLng(maxLat, maxLon),
  );
}

double distanceMeters(maplibre.LatLng a, maplibre.LatLng b) {
  const earthRadiusMeters = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(h));
}
