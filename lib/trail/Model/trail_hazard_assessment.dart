import 'trail_hazard_alert.dart';

/// An empty cached result must not be presented as a successful safety check.
class TrailHazardAssessment {
  const TrailHazardAssessment({required this.alerts, required this.isFresh});

  final List<TrailHazardAlert> alerts;
  final bool isFresh;
}
