int naismithDurationMinutes(int distanceMeters, double elevationGainMeters) {
  final distanceKm = distanceMeters / 1000;
  final baseMinutes = distanceKm * 12;
  final ascentMinutes = elevationGainMeters / 10;
  final total = (baseMinutes + ascentMinutes).round();
  return total < 1 ? 1 : total;
}

int hikingDurationMinutes(int distanceMeters, {double elevationGainMeters = 0}) {
  return naismithDurationMinutes(distanceMeters, elevationGainMeters);
}
