import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/map_utils.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  test('Mapbox Outdoors is the default mobile map style', () {
    expect(mapStyleUrls.first, 'mapbox://styles/mapbox/outdoors-v12');
  });

  group('map point validation', () {
    test('rejects out-of-range and non-finite coordinates', () {
      expect(
        mapPointCoordinatesOrNull(Point(coordinates: Position(double.nan, 3))),
        isNull,
      );
      expect(
        mapPointCoordinatesOrNull(Point(coordinates: Position(101, 91))),
        isNull,
      );
    });

    test('bounds ignore malformed points and remain finite when empty', () {
      final valid = Point(coordinates: Position(101.6869, 3.1390));
      final bounds = boundsFor([
        Point(coordinates: Position(double.infinity, 3)),
        valid,
      ]);

      expect(bounds.minLat, closeTo(3.1385, 0.000001));
      expect(bounds.maxLat, closeTo(3.1395, 0.000001));
      expect(bounds.minLon, closeTo(101.6864, 0.000001));
      expect(bounds.maxLon, closeTo(101.6874, 0.000001));

      final emptyBounds = boundsFor(const []);
      expect(emptyBounds.minLat.isFinite, isTrue);
      expect(emptyBounds.maxLat.isFinite, isTrue);
      expect(centerFor(const []).coordinates[0], 0);
      expect(centerFor(const []).coordinates[1], 0);
    });
  });

  group('distanceMeters', () {
    test('stays finite for antipodal points', () {
      final distance = distanceMeters(
        Point(coordinates: Position(0, 0)),
        Point(coordinates: Position(180, 0)),
      );

      expect(distance.isFinite, isTrue);
      expect(distance, closeTo(20015086.8, 1));
    });

    test('rejects non-finite coordinates', () {
      final distance = distanceMeters(
        Point(coordinates: Position(double.nan, 0)),
        Point(coordinates: Position(101, 3)),
      );

      expect(distance, double.infinity);
    });
  });
}
