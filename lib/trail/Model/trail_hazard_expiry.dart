import 'trail_hazard_categories.dart';

/// Matches the server's report lifetime for each weather risk category.
Duration trailHazardLifetime(String type) =>
    trailHazardCategoryFor(type) == 'Weather'
    ? Duration(hours: trailHazardTypeIsFatal(type) ? 24 : 12)
    : const Duration(days: 7);

/// Applies current weather limits to cached reports while preserving earlier expiries.
DateTime? trailHazardExpiry({
  required String type,
  DateTime? reportedAt,
  DateTime? expiresAt,
}) {
  final limit = reportedAt?.add(trailHazardLifetime(type));
  if (expiresAt == null) return limit;
  if (trailHazardCategoryFor(type) == 'Weather' &&
      limit != null &&
      limit.isBefore(expiresAt)) {
    return limit;
  }
  return expiresAt;
}
