import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../Model/hike_session_models.dart';

/// Returns the current roster and draft used for a scheduled start attempt.
class ResolvedUpcomingHikeStart {
  /// Keeps the validated hike and personal draft together.
  const ResolvedUpcomingHikeStart(this.hike, this.draft);

  final UpcomingHike hike;
  final HikeSessionDraft draft;

  /// Uses team mode only after validating that another hiker is present.
  bool get isTeam => draft.hikeType == HikeType.team;
}

/// Refreshes membership before choosing readiness or individual preparation.
class UpcomingHikeStartResolver {
  /// Receives membership boundaries without owning UI or starting tracking.
  const UpcomingHikeStartResolver({
    required this.loadCurrent,
    required this.makeDraft,
  });

  final Future<UpcomingHike?> Function(String hikeId) loadCurrent;
  final HikeSessionDraft Function(UpcomingHike hike, HikeSessionDraft draft)
  makeDraft;

  /// Rejects unsynced, removed and empty-team starts with an actionable message.
  Future<ResolvedUpcomingHikeStart> resolve(
    UpcomingHike hike,
    HikeSessionDraft draft,
  ) async {
    if (hike.isLocalPendingSync) {
      throw const HikerCircleFirebaseRepositoryException(
        'This hike is still syncing. Reconnect before starting it.',
      );
    }
    try {
      final current = await loadCurrent(hike.id);
      if (current == null) {
        throw const HikerCircleFirebaseRepositoryException(
          'This hike is no longer upcoming.',
        );
      }
      hike = current;
      draft = makeDraft(current, draft);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!error.allowsOfflineFallback) rethrow;
      // Preserve the existing offline start; the hazard gate still asks consent.
    }
    if (draft.hikeType == HikeType.team && draft.teamBuddies.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'At least one other hiker must join before team readiness can start.',
      );
    }
    return ResolvedUpcomingHikeStart(hike, draft);
  }
}

/// Suppresses repeated automatic invitations while permitting deliberate taps.
class TeamReadinessNavigationGuard {
  final presentedKeys = <String>{};

  /// Claims an automatic invitation once, or reopens it on an explicit action.
  bool claim(String key, {required bool allowReopen}) {
    if (!allowReopen && presentedKeys.contains(key)) return false;
    presentedKeys.add(key);
    return true;
  }
}
