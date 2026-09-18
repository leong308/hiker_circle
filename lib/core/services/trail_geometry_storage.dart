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
    if (utf8.encode(jsonEncode(points)).length > 700000) {
      throw const FormatException(
        'This route is too large to save in one geometry document.',
      );
    }
    return TrailGeometryStorage._(
      polyline,
      sha256.convert(utf8.encode(polyline)).toString(),
      points,
    );
  }

  final String encodedPolyline;
  final String checksum;
  final List<Map<String, double>> points;

  Map<String, dynamic> document(String updatedAt) => {
    'coordinateSystem': 'WGS84',
    'points': points,
    'pointCount': points.length,
    'updatedAt': updatedAt,
  };

  Map<String, dynamic> metadata(String documentPath, String updatedAt) => {
    'schemaVersion': 1,
    'geometrySha256': checksum,
    'geometryDocument': documentPath,
    'pointCount': points.length,
    'polylinePrecision': 5,
    'updatedAt': updatedAt,
  };
}
