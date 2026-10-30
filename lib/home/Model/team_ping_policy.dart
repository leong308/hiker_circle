import 'hike_session_models.dart';
import 'team_hike_identity.dart';

/// Identifies an unanswered, recent ping belonging to an active hiker.
abstract final class TeamPingPolicy {
  /// Uses the server-recorded ping time to deduplicate stream updates and push delivery.
  static String? pendingKey(TeamHikeSession team, String phone, DateTime now) {
    if (team.phase != TeamHikePhase.active) return null;
    final member = team.participants
        .where(
          (p) =>
              TeamHikeIdentity.key(p.phoneNumber) ==
              TeamHikeIdentity.key(phone),
        )
        .firstOrNull;
    if (member == null || member.status == TeamHikeParticipantStatus.ended) {
      return null;
    }
    final ping = member.lastPingAt;
    if (ping == null ||
        now.difference(ping) > const Duration(hours: 1) ||
        ping.isAfter(now.add(const Duration(seconds: 10))) ||
        member.lastOkAt != null && !member.lastOkAt!.isBefore(ping)) {
      return null;
    }
    return '${team.id}:${ping.toUtc().millisecondsSinceEpoch}';
  }
}
