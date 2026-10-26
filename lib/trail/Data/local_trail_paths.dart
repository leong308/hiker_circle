import '../../app/Data/local_session_database.dart';
import '../../core/services/hiking_route_service.dart';
import '../Model/trail_models.dart';

typedef TrailPathCoordinate = ({double latitude, double longitude});

/// Represents local trail path.
class LocalTrailPath {
  /// Creates local trail path.
  const LocalTrailPath({
    required this.trailId,
    required this.name,
    required this.coordinates,
  });

  final String trailId;
  final String name;
  final List<TrailPathCoordinate> coordinates;
}

/// Represents local trail path catalog.
class LocalTrailPathCatalog {
  /// Creates local trail path catalog.
  const LocalTrailPathCatalog({required this.paths, required this.unavailable});
  final List<LocalTrailPath> paths;
  final int unavailable;
}

/// Reads existing route shapes without requesting weather, hazards or routing.
class LocalTrailPaths {
  /// Creates local trail paths.
  const LocalTrailPaths(this.database);
  final LocalSessionDatabase database;

  /// Loads.
  Future<LocalTrailPathCatalog> load() async {
    final rows = await database.loadCachedEntities(
      ownerPhoneNumber: '',
      entityType: 'trail',
      includeExpired: true,
    );
    final paths = <LocalTrailPath>[];
    final seen = <String>{};
    var unavailable = 0;
    for (final row in rows) {
      if (!seen.add(row.entityId)) continue;
      try {
        final trail = Trail.fromPersistence(row.payload);
        var coordinates = HikingRouteService.savedRouteMatchesCheckpoints(trail)
            ? _decode(trail.routeEncodedPolyline)
            : null;
        if (coordinates == null) {
          final cached = await database.loadRouteCache(
            trailId: trail.trailId,
            checkpointsHash: HikingRouteService.checkpointsHash(
              trail.checkpoints,
            ),
          );
          final encoded = cached?['encoded_polyline'];
          coordinates = _decode(encoded is String ? encoded : null);
        }
        if (coordinates == null) {
          unavailable++;
          continue;
        }
        paths.add(
          LocalTrailPath(
            trailId: row.entityId,
            name: trail.name.trim().isEmpty ? 'Existing trail' : trail.name,
            coordinates: coordinates,
          ),
        );
      } catch (_) {
        // One damaged or incomplete cache entry must not hide other trails.
        unavailable++;
      }
    }
    return LocalTrailPathCatalog(
      paths: List.unmodifiable(paths),
      unavailable: unavailable,
    );
  }

  /// Computes decode.
  static List<TrailPathCoordinate>? _decode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      final points = PolylineCodec.decode(encoded);
      if (points.length < 2 ||
          points.any(
            (p) =>
                !p.latitude.isFinite ||
                !p.longitude.isFinite ||
                p.latitude.abs() > 90 ||
                p.longitude.abs() > 180,
          )) {
        return null;
      }
      final first = points.first;
      if (points.every(
        (p) => p.latitude == first.latitude && p.longitude == first.longitude,
      )) {
        return null;
      }
      return List.unmodifiable([
        for (final point in points)
          (latitude: point.latitude, longitude: point.longitude),
      ]);
    } catch (_) {
      return null;
    }
  }
}
