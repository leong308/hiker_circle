// naismithDurationMinutes estimates hiking duration from distance and ascent when a route needs a
// walking-time estimate.
/// Computes naismith duration minutes.
int naismithDurationMinutes(int distanceMeters, double elevationGainMeters) {
  final distanceKm = distanceMeters / 1000;
  final baseMinutes = distanceKm * 12;
  final ascentMinutes = elevationGainMeters / 10;
  final total = (baseMinutes + ascentMinutes).round();
  return total < 1 ? 1 : total;
}

/// Computes hiking duration minutes.
int hikingDurationMinutes(
  int distanceMeters, {
  double elevationGainMeters = 0,
}) {
  return naismithDurationMinutes(distanceMeters, elevationGainMeters);
}
