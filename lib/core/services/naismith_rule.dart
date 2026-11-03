// naismithDurationMinutes estimates hiking duration from distance and ascent when a route needs a
// walking-time estimate.
/// Computes naismith duration minutes.
int naismithDurationMinutes(int distanceMeters, double elevationGainMeters) {
  final distanceKm = distanceMeters / 1000; // me to km
  final baseMinutes =
      distanceKm * 12; // 1km to 12 minutes, so 5km to 60 minutes
  final ascentMinutes =
      elevationGainMeters / 10; // 10m to 1 minute, so 600m to 60 minutes
  final total = (baseMinutes + ascentMinutes)
      .round(); // round to nearest minute
  return total < 1 ? 1 : total;
}

/// Computes hiking duration minutes.
int hikingDurationMinutes(
  int distanceMeters, {
  double elevationGainMeters = 0,
}) {
  return naismithDurationMinutes(distanceMeters, elevationGainMeters);
}
