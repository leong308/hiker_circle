import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_utils.dart';
import '../../sos/Model/sos_models.dart';
import '../../trail/Model/trail_models.dart';

/// Distinguishes continuing setup from opening navigation or retrying GPS.
enum TrailheadProximityAction { proceed, directions, retry }

/// Describes the distance from a fresh phone location to a selected trailhead.
class TrailheadProximity {
  /// Keeps the location and destination used by both the warning and Waze.
  TrailheadProximity({required this.location, required this.trail});

  static const warningDistanceMeters = 100.0;
  final SosTriggerLocation location;
  final Trail trail;

  /// The blue location dot uses the same fix as the distance comparison.
  mapbox.Point get currentPoint => mapbox.Point(
    coordinates: mapbox.Position(location.longitude, location.latitude),
  );

  /// The red pin marks the trail's selected starting point.
  mapbox.Point get destinationPoint => mapbox.Point(
    coordinates: mapbox.Position(trail.longitude, trail.latitude),
  );

  /// Measures straight-line distance rather than a driving-route estimate.
  double get meters => distanceMeters(currentPoint, destinationPoint);

  /// Exactly 100 metres remains inside the allowed distance.
  bool get needsWarning => meters > warningDistanceMeters;

  /// Formats the distance without implying street-route accuracy.
  String get distanceLabel => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} km'
      : '${meters.round()} m';
}
