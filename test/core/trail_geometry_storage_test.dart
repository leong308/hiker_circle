import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/trail_geometry_storage.dart';
import 'package:hiker_circle/core/services/hiking_route_service.dart';

void main() {
  test('stores every polyline vertex in order, including return points', () {
    final original = [
      LatLng(5.41, 100.27),
      LatLng(5.42, 100.28),
      LatLng(5.43, 100.29),
      LatLng(5.42, 100.28),
      LatLng(5.41, 100.27),
    ];
    final encoded = PolylineCodec.encode(original);
    final geometry = TrailGeometryStorage.fromPolyline(encoded);
    expect(geometry.points, [
      for (final p in original) {'lat': p.latitude, 'lon': p.longitude},
    ]);
    expect(geometry.document('now')['pointCount'], 5);
    expect(
      geometry.metadata(
        'trails/id/routeGeometry/rev',
        'now',
      )['geometryDocument'],
      'trails/id/routeGeometry/rev',
    );
    expect(geometry.encodedPolyline, encoded);
    expect(geometry.points.every((p) => !p.containsKey('ele')), isTrue);
  });
  test('identical paths have identical checksums; changed paths do not', () {
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    final a = TrailGeometryStorage.fromPolyline(encoded);
    final b = TrailGeometryStorage.fromPolyline(encoded);
    final c = TrailGeometryStorage.fromPolyline(
      PolylineCodec.encode([LatLng(5, 100), LatLng(5.1, 100.1)]),
    );
    expect(a.checksum, b.checksum);
    expect(a.checksum, isNot(c.checksum));
    expect(
      a.metadata('path', 'now').keys,
      unorderedEquals([
        'schemaVersion',
        'geometrySha256',
        'geometryDocument',
        'pointCount',
        'polylinePrecision',
        'updatedAt',
      ]),
    );
  });
  test('rejects malformed, empty, single-point and invalid coordinates', () {
    for (final encoded in [
      '',
      '_',
      PolylineCodec.encode([LatLng(5, 100)]),
      // External malformed geometry cannot be produced by the validated encoder.
      '_mljP_gjaR_ibE_ibE', // (91, 100), (92, 101)
    ]) {
      expect(
        () => TrailGeometryStorage.fromPolyline(encoded),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
