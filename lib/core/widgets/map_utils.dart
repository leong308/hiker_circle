// Map utilities validate coordinates and share gesture, distance and camera helpers across map-based
// screens.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const mapGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
  Factory<OneSequenceGestureRecognizer>(ScaleGestureRecognizer.new),
};

const eagerMapGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
  Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
};

const mapStyleUrls = [
  'mapbox://styles/mapbox/outdoors-v12',
  'mapbox://styles/mapbox/streets-v12',
  'mapbox://styles/mapbox/satellite-streets-v12',
  'https://tiles.openfreemap.org/styles/liberty',
  'https://tiles.openfreemap.org/styles/positron',
  'https://tiles.openfreemap.org/styles/bright',
];

/// These labels and indices stay aligned with saved/offline style selections.
const mapStyleNames = [
  'Outdoors',
  'Streets',
  'Satellite',
  'Liberty',
  'Light',
  'Bright',
];

enum MapDimension { twoD, threeD }

@immutable
class MapViewSettings {
  const MapViewSettings({
    this.styleIndex = 0,
    this.dimension = MapDimension.threeD,
  });

  final int styleIndex;
  final MapDimension dimension;
  int get safeStyleIndex => styleIndex.clamp(0, mapStyleUrls.length - 1);
  String get styleUrl => mapStyleUrls[safeStyleIndex];
  String get styleName => mapStyleNames[safeStyleIndex];
  bool get is3D => dimension == MapDimension.threeD;
  String get dimensionLabel => is3D ? '3D' : '2D';

  MapViewSettings copyWith({int? styleIndex, MapDimension? dimension}) =>
      MapViewSettings(
        styleIndex: (styleIndex ?? this.styleIndex).clamp(
          0,
          mapStyleUrls.length - 1,
        ),
        dimension: dimension ?? this.dimension,
      );

  @override
  bool operator ==(Object other) =>
      other is MapViewSettings &&
      other.safeStyleIndex == safeStyleIndex &&
      other.dimension == dimension;

  @override
  int get hashCode => Object.hash(safeStyleIndex, dimension);
}

/// The photographic Mapbox style reserved for the immersive route preview.
const fpvMapStyleUrl = MapboxStyles.STANDARD_SATELLITE;

const mapTerrainExaggeration = 1.5;

Future<void> enableTerrain3D(MapboxMap map) async {
  try {
    await map.style.addSource(
      RasterDemSource(
        id: 'mapbox-dem',
        url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
      ),
    );
  } catch (_) {}
  try {
    await map.style.setStyleTerrain(
      '{"source": "mapbox-dem", "exaggeration": $mapTerrainExaggeration}',
    );
  } catch (_) {}
}

Future<void> disableTerrain3D(MapboxMap map) async {
  try {
    await map.style.setStyleTerrain('null');
  } catch (_) {
    // Styles with built-in terrain can still flatten the existing elevation.
    try {
      await map.style.setStyleTerrainProperty('exaggeration', 0);
    } catch (_) {
      // Flat/OpenFreeMap styles may have no terrain property at all.
    }
  }
}

/// Only change the view dimension. Style-only changes should not call this
/// helper unless restoring terrain after a native style reload.
Future<void> applyMapDimension(
  MapboxMap map,
  MapDimension dimension, {
  double pitch = 50,
}) async {
  if (dimension == MapDimension.threeD) {
    await enableTerrain3D(map);
  } else {
    await disableTerrain3D(map);
  }
  await map.setCamera(
    CameraOptions(
      pitch: dimension == MapDimension.threeD
          ? (pitch.isFinite ? pitch.clamp(0, 85).toDouble() : 50)
          : 0,
    ),
  );
  await map.gestures.updateSettings(
    GesturesSettings(pitchEnabled: dimension == MapDimension.threeD),
  );
}

void schedulePitch(MapboxMap map, {double pitch = 50}) {
  Future.delayed(const Duration(milliseconds: 300), () async {
    try {
      await map.flyTo(
        CameraOptions(pitch: pitch),
        MapAnimationOptions(duration: 800),
      );
    } catch (_) {
      // The native map may have been disposed before the delayed camera move.
    }
  });
}

const kMapMinZoom = 4.2;
const kMapMaxZoom = 21.0;

/// Platform map geometry is a value: rebuilding a page can create new lists
/// containing identical points and must not restart route rendering/playback.
bool mapPointListsEqual(List<Point>? left, List<Point>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (!listEquals(
      left[index].coordinates.toJson(),
      right[index].coordinates.toJson(),
    )) {
      return false;
    }
  }
  return true;
}

({double longitude, double latitude})? mapPointCoordinatesOrNull(Point point) {
  final coordinates = point.coordinates;
  if (coordinates.length < 2) return null;

  final longitude = coordinates[0]?.toDouble();
  final latitude = coordinates[1]?.toDouble();
  if (longitude == null ||
      latitude == null ||
      !longitude.isFinite ||
      !latitude.isFinite ||
      longitude < -180 ||
      longitude > 180 ||
      latitude < -90 ||
      latitude > 90) {
    return null;
  }
  return (longitude: longitude, latitude: latitude);
}

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
  final validCoordinates = points
      .map(mapPointCoordinatesOrNull)
      .whereType<({double longitude, double latitude})>()
      .toList(growable: false);
  if (validCoordinates.isEmpty) {
    return (minLat: -0.0005, maxLat: 0.0005, minLon: -0.0005, maxLon: 0.0005);
  }

  double minLat = validCoordinates.first.latitude;
  double maxLat = validCoordinates.first.latitude;
  double minLon = validCoordinates.first.longitude;
  double maxLon = validCoordinates.first.longitude;

  for (final coordinate in validCoordinates.skip(1)) {
    final lat = coordinate.latitude;
    final lon = coordinate.longitude;
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

  return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
}

double distanceMeters(Point a, Point b) {
  const earthRadiusMeters = 6371000.0;
  if (a.coordinates.length < 2 || b.coordinates.length < 2) {
    return double.infinity;
  }
  final aLatitude = a.coordinates[1]?.toDouble();
  final aLongitude = a.coordinates[0]?.toDouble();
  final bLatitude = b.coordinates[1]?.toDouble();
  final bLongitude = b.coordinates[0]?.toDouble();
  if (aLatitude == null ||
      aLongitude == null ||
      bLatitude == null ||
      bLongitude == null ||
      !aLatitude.isFinite ||
      !aLongitude.isFinite ||
      !bLatitude.isFinite ||
      !bLongitude.isFinite ||
      aLatitude < -90 ||
      aLatitude > 90 ||
      bLatitude < -90 ||
      bLatitude > 90 ||
      aLongitude < -180 ||
      aLongitude > 180 ||
      bLongitude < -180 ||
      bLongitude > 180) {
    return double.infinity;
  }
  final lat1 = aLatitude * math.pi / 180;
  final lat2 = bLatitude * math.pi / 180;
  final dLat = (bLatitude - aLatitude) * math.pi / 180;
  final dLon = (bLongitude - aLongitude) * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}
