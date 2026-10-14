import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'hiking_route_service.dart';

/// Converts the complete saved API polyline into the native Firestore geometry.
class TrailGeometryStorage {
  TrailGeometryStorage._(this.encodedPolyline, this.checksum, this.points);

  factory TrailGeometryStorage.fromPolyline(String encoded) {
    final polyline = encoded.trim();
    final decoded = PolylineCodec.decode(polyline);
    if (decoded.length < 2 ||
        decoded.any(
          (p) =>
              !p.latitude.isFinite ||
              !p.longitude.isFinite ||
              p.latitude.abs() > 90 ||
              p.longitude.abs() > 180,
        )) {
      throw const FormatException('The route must contain valid coordinates.');
    }
    final points = [
      for (final p in decoded)
        <String, double>{'lat': p.latitude, 'lon': p.longitude},
    ];
    if (points.length > 100000 || polyline.length > 650000) {
      throw const FormatException(
        'This route exceeds the supported trail size.',
      );
    }
    return TrailGeometryStorage._(
      polyline,
      sha256.convert(utf8.encode(polyline)).toString(),
      points,
    );
  }

  factory TrailGeometryStorage.fromCoordinates(
    List<Map<String, double>> coordinates,
  ) {
    if (coordinates.length < 3 ||
        coordinates.map((p) => '${p["lat"]},${p["lon"]}').toSet().length < 2 ||
        coordinates.length > 100000 ||
        coordinates.any(
          (p) =>
              p['lat'] == null ||
              p['lon'] == null ||
              p.values.any((n) => !n.isFinite) ||
              p['lat']!.abs() > 90 ||
              p['lon']!.abs() > 180,
        )) {
      throw const FormatException(
        'The recording must contain valid GPS coordinates.',
      );
    }
    final encoded = PolylineCodec.encode([
      for (final p in coordinates) LatLng(p['lat']!, p['lon']!),
    ]);
    if (encoded.length > 650000) {
      throw const FormatException(
        'This route exceeds the trail record size limit.',
      );
    }
    return TrailGeometryStorage._(
      encoded,
      sha256.convert(utf8.encode(encoded)).toString(),
      List.unmodifiable(
        coordinates.map((p) => Map<String, double>.unmodifiable(p)),
      ),
    );
  }

  late final bool isChunked = utf8.encode(jsonEncode(points)).length > 700000;
  late final List<List<Map<String, double>>> chunks = !isChunked
      ? const []
      : [
          for (var i = 0; i < points.length; i += 500)
            points.sublist(
              i,
              i + 500 > points.length ? points.length : i + 500,
            ),
        ];

  final String encodedPolyline;
  final String checksum;
  final List<Map<String, double>> points;

  Map<String, dynamic> document(String updatedAt) => {
    'coordinateSystem': 'WGS84',
    if (!isChunked) 'points': points,
    if (isChunked) 'chunkCount': chunks.length,
    'pointCount': points.length,
    'updatedAt': updatedAt,
  };

  Map<String, dynamic> metadata(String documentPath, String updatedAt) => {
    'schemaVersion': 1,
    'geometrySha256': checksum,
    'geometryDocument': documentPath,
    'pointCount': points.length,
    'polylinePrecision': 5,
    if (isChunked) 'chunkCount': chunks.length,
    'updatedAt': updatedAt,
  };
}
