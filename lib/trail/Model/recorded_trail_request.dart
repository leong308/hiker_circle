// recordedTrailCandidate derives a proposed trail from one recorded hike and named checkpoints.
import '../../home/Model/hike_session_models.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/services/trail_geometry_storage.dart';
import 'trail_models.dart';

Trail recordedTrailCandidate(
  Map<String, dynamic> request,
  List<HikeCoordinate> points,
) {
  if (points.length < 3) {
    throw const FormatException(
      'At least three recorded GPS samples are needed.',
    );
  }
  final proposed = Map<String, dynamic>.from(request['proposed'] as Map);
  final checkpoints = (request['checkpoints'] as List)
      .whereType<Map>()
      .map((r) => TrailCheckpoint.fromPersistence(Map<String, dynamic>.from(r)))
      .toList();
  final geometry = TrailGeometryStorage.fromCoordinates([
    for (final p in points)
      {
        'lat': p.latitude,
        'lon': p.longitude,
        if (p.altitudeMeters?.isFinite == true) 'ele': p.altitudeMeters!,
      },
  ]);
  var distance = 0.0, elevation = 0.0;
  for (var i = 1; i < points.length; i++) {
    distance += points[i - 1].distanceTo(points[i]);
    final a = points[i - 1].altitudeMeters, b = points[i].altitudeMeters;
    if (a != null && b != null && a.isFinite && b.isFinite && b > a) {
      elevation += b - a;
    }
  }
  return Trail.fromPersistence({
    'trailId': 'trail_request_${request['requestId']}',
    ...proposed,
    'latitude': points.first.latitude,
    'longitude': points.first.longitude,
    'distanceKm': distance / 1000,
    'estimatedDurationMinutes': ((request['durationMinutes'] as num?) ?? 120)
        .round()
        .clamp(15, 10080),
    'elevationGainMeters': elevation.round(),
    'routeEncodedPolyline': geometry.encodedPolyline,
    'routeCheckpointsHash': HikingRouteService.checkpointsHash(checkpoints),
    'routeProvider': 'stored-polyline',
    'routeFilePath':
        'offline/maps/trail_request_${request['requestId']}.mbtiles',
    'coverColorValue': 0xFF638B74,
    'checkpoints': checkpoints.map((c) => c.toFirestore()).toList(),
    'weather': <String, dynamic>{},
    'hazards': <Map<String, dynamic>>[],
  });
}
