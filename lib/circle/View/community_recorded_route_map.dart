import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../home/Model/hike_session_models.dart';
import '../../trail/Model/trail_models.dart';

/// An independently controlled map of a post's recorded GPS samples. Public
/// posts contain route geometry, never a viewer's style or camera position.
class CommunityRecordedRouteMap extends StatelessWidget {
  const CommunityRecordedRouteMap({
    super.key,
    required this.recordingId,
    required this.trailName,
    required this.points,
  });

  final String recordingId;
  final String trailName;
  final List<HikeCoordinate> points;

  @override
  Widget build(BuildContext context) {
    final recordedPoints = [
      for (final point in points)
        mapbox.Point(
          coordinates: mapbox.Position(point.longitude, point.latitude),
        ),
    ].where((point) => mapPointCoordinatesOrNull(point) != null).toList();
    final origin = recordedPoints.isEmpty
        ? null
        : mapPointCoordinatesOrNull(recordedPoints.first);
    return RoutePreviewMap(
      key: ValueKey('community-recorded-route:$recordingId'),
      trail: Trail.fromPersistence({
        'trailId': 'community-recording:$recordingId',
        'name': trailName,
        'latitude': origin?.latitude ?? 0,
        'longitude': origin?.longitude ?? 0,
      }),
      // Always non-null, even when empty: never load a planned trail route.
      recordedTrackPoints: recordedPoints,
      showLayerToggle: true,
      animateRoute: false,
      captureAllGestures: true,
    );
  }
}
