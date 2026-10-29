import '../Model/hike_session_models.dart';
import '../Model/shared_team_hike_summary.dart';
import '../Model/team_hike_identity.dart';

/// Keeps a common result monotonic while local completion and cloud snapshots reconcile.
class SharedTeamHikeSummaryViewModel {
  /// Starts with the immediately saved local result or a previously loaded history snapshot.
  SharedTeamHikeSummaryViewModel(this.summary, this.ownerPhone);
  SharedTeamHikeSummary summary;
  final String ownerPhone;

  /// Accepts only this ended member's common results and ignores older cached snapshots.
  SharedTeamHikeSummary resolve(TeamHikeSession? team) {
    final ended =
        team?.participants.any(
          (p) =>
              TeamHikeIdentity.key(p.phoneNumber) ==
                  TeamHikeIdentity.key(ownerPhone) &&
              p.status == TeamHikeParticipantStatus.ended,
        ) ==
        true;
    if (ended && team?.summarySnapshot != null) {
      summary = summary.prefer(
        SharedTeamHikeSummary.fromMap(team!.summarySnapshot!),
      );
    }
    return summary;
  }
}
