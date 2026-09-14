import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_preview_camera.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

void main() {
  mapbox.Point point(double longitude, double latitude) =>
      mapbox.Point(coordinates: mapbox.Position(longitude, latitude));

  group('routePreviewBearing', () {
    test('uses compass headings', () {
      final origin = point(101, 3);

      expect(routePreviewBearing(origin, point(101, 4)), closeTo(0, 0.01));
      expect(routePreviewBearing(origin, point(102, 3)), closeTo(90, 0.1));
      expect(routePreviewBearing(origin, point(101, 2)), closeTo(180, 0.01));
      expect(routePreviewBearing(origin, point(100, 3)), closeTo(270, 0.1));
    });
  });

  group('routePreviewCameraFrame', () {
    test('interpolates smoothly along the animated route', () {
      final points = [point(100, 3), point(101, 3), point(102, 3)];
      final frame = routePreviewCameraFrame(
        points: points,
        cumulativeDistances: const [0, 100, 200],
        progress: 0.25,
        lookAheadMeters: 30,
      );

      expect(frame, isNotNull);
      expect(frame!.center.coordinates[0], closeTo(100.5, 0.000001));
      expect(frame.center.coordinates[1], closeTo(3, 0.000001));
      expect(frame.bearing, closeTo(90, 0.1));
      expect(frame.distanceMeters, closeTo(50, 0.001));
    });

    test('keeps the final camera facing the route direction', () {
      final points = [point(100, 3), point(101, 3), point(102, 3)];
      final frame = routePreviewCameraFrame(
        points: points,
        cumulativeDistances: const [0, 100, 200],
        progress: 1,
      );

      expect(frame, isNotNull);
      expect(frame!.center.coordinates[0], closeTo(102, 0.000001));
      expect(frame.bearing, closeTo(90, 0.1));
    });

    test('rejects mismatched route distance data', () {
      final frame = routePreviewCameraFrame(
        points: [point(100, 3), point(101, 3)],
        cumulativeDistances: const [0],
        progress: 0.5,
      );

      expect(frame, isNull);
    });
  });

  group('route preview playback', () {
    test('formats camera headings as eight-point compass directions', () {
      expect(routePreviewCardinalDirection(0), 'N');
      expect(routePreviewCardinalDirection(44), 'NE');
      expect(routePreviewCardinalDirection(90), 'E');
      expect(routePreviewCardinalDirection(225), 'SW');
      expect(routePreviewCardinalDirection(359), 'N');
    });

    test('converts grade percentage to a true slope angle', () {
      expect(routePreviewSlopeDegrees(100), closeTo(45, 0.0001));
      expect(routePreviewSlopeDegrees(-100), closeTo(-45, 0.0001));
      expect(routePreviewSlopeDegrees(0), 0);
    });

    test('widens and raises the camera view on steep descents', () {
      final level = routePreviewCameraTuning(0);
      final moderateDescent = routePreviewCameraTuning(-25);
      final severeDescent = routePreviewCameraTuning(-45);

      expect(level.pitch, 68);
      expect(level.zoomOffset, 0);
      expect(level.lookAheadMeters, 25);
      expect(moderateDescent.pitch, lessThan(level.pitch));
      expect(moderateDescent.zoomOffset, lessThan(level.zoomOffset));
      expect(
        moderateDescent.lookAheadMeters,
        greaterThan(level.lookAheadMeters),
      );
      expect(severeDescent.pitch, 30);
      expect(severeDescent.zoomOffset, -1.1);
      expect(severeDescent.lookAheadMeters, 120);
    });

    test('keeps the immersive framing while ascending', () {
      final ascending = routePreviewCameraTuning(35);

      expect(ascending.pitch, 68);
      expect(ascending.zoomOffset, 0);
      expect(ascending.lookAheadMeters, 25);
    });

    test(
      'uses a slower distance-aware baseline with bounded speed choices',
      () {
        expect(
          routePreviewPlaybackDuration(totalDistanceMeters: 2500, speed: 1),
          const Duration(milliseconds: 83333),
        );
        expect(
          routePreviewPlaybackDuration(totalDistanceMeters: 2500, speed: 0.5),
          const Duration(milliseconds: 166667),
        );
        expect(
          routePreviewPlaybackDuration(totalDistanceMeters: 2500, speed: 4),
          const Duration(milliseconds: 20833),
        );
      },
    );

    test('keeps even short FPV routes watchable', () {
      expect(
        routePreviewPlaybackDuration(totalDistanceMeters: 200, speed: 1),
        const Duration(seconds: 60),
      );
    });

    test('finds the point used for a local terrain slope sample', () {
      final result = routePreviewPointAtDistance(
        points: [point(100, 3), point(101, 3), point(102, 3)],
        cumulativeDistances: const [0, 100, 200],
        distanceMeters: 125,
      );

      expect(result, isNotNull);
      expect(result!.coordinates[0], closeTo(101.25, 0.000001));
      expect(result.coordinates[1], closeTo(3, 0.000001));
    });
  });
}
