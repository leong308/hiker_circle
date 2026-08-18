import '../Model/trail_models.dart';

/// Legacy local trail source retained for API compatibility.
///
/// Production trails come from Firebase. Returning an empty collection keeps
/// demo weather, hazards, and fake offline-download flags from leaking into a
/// real mobile session when this old repository is accidentally instantiated.
class TrailRepository {
  const TrailRepository();

  List<Trail> loadTrails() => const [];
}
