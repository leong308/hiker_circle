import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'hike_session_models.dart';

/// Uses the same recorded samples as summary distance and point count. Preserve
/// their GPS precision: no polyline rounding, checkpoint routing, or snapping.
List<mapbox.Point> recordedHikeMapPoints(ActiveHikeSession hike) => [
  for (final point in HikeSummaryReport.recordedRoutePointsFor(hike))
    mapbox.Point(coordinates: mapbox.Position(point.longitude, point.latitude)),
];
