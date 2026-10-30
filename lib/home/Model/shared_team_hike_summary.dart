import 'hike_session_models.dart';
import 'team_hike_identity.dart';

/// A frozen, common team result that is replaced when the next hiker finishes.
class SharedTeamHikeSummary {
  /// Parses only shared map, identity and aggregate result fields.
  SharedTeamHikeSummary.fromMap(Map<String, dynamic> data)
    : trailName = data['trailName'] as String? ?? 'Team hike',
      finalized = data['finalized'] == true,
      finishedCount = (data['finishedCount'] as num?)?.toInt() ?? 0,
      distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? 0,
      duration = Duration(
        seconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      ),
      generatedAt = DateTime.tryParse('${data['generatedAtLocal']}'),
      members = (data['members'] is List ? data['members'] as List : const [])
          .whereType<Map>()
          .map(
            (value) =>
                SharedTeamHiker.fromMap(Map<String, dynamic>.from(value)),
          )
          .toList();

  /// Preserves the local end snapshot immediately, without waiting for the remaining hikers or cloud.
  factory SharedTeamHikeSummary.atLocalEnd(
    ActiveHikeSession hike,
    HikeSummaryReport report,
    String owner,
  ) {
    final roster =
        hike.teamHikeSession?.participants ?? const <TeamHikeParticipant>[];
    final members = roster.map((p) {
      final self =
          TeamHikeIdentity.key(p.phoneNumber) == TeamHikeIdentity.key(owner);
      final point = self
          ? hike.latestLocation ?? p.latestLocation
          : p.latestLocation;
      return {
        'id': TeamHikeIdentity.key(p.phoneNumber),
        'name': p.buddy.name,
        'color': p.buddy.avatarColorValue,
        'status': self ? 'ended' : p.status.name,
        if (point != null) 'location': point.toFirestore(),
        'distanceKm': self ? report.distanceKm : p.progressMeters / 1000,
      };
    }).toList()..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final count = members.where((p) => p['status'] == 'ended').length;
    return SharedTeamHikeSummary.fromMap({
      'trailName': report.trailName,
      'generatedAtLocal': report.endedAt.toUtc().toIso8601String(),
      'finalized': members.isNotEmpty && count == members.length,
      'finishedCount': count,
      'durationSeconds': report.duration.inSeconds,
      'distanceKm': members.fold<double>(
        0,
        (total, p) => total + (p['distanceKm'] as num).toDouble(),
      ),
      'members': members,
    });
  }

  final String trailName;
  final bool finalized;
  final int finishedCount;
  final double distanceKm;
  final Duration duration;
  final DateTime? generatedAt;
  final List<SharedTeamHiker> members;

  /// Rejects older cached snapshots and prevents a final common result becoming provisional again.
  SharedTeamHikeSummary prefer(SharedTeamHikeSummary candidate) {
    if (finalized && !candidate.finalized) return this;
    if (generatedAt != null &&
        (candidate.generatedAt == null ||
            candidate.generatedAt!.isBefore(generatedAt!))) {
      return this;
    }
    return candidate;
  }
}

/// One member's fixed identity and recorded location at the snapshot boundary.
class SharedTeamHiker {
  /// Omits missing or invalid positions instead of substituting the trailhead.
  SharedTeamHiker.fromMap(Map<String, dynamic> data)
    : id = '${data['id'] ?? ''}',
      name = data['name'] as String? ?? 'Hiker',
      color = (data['color'] as num?)?.toInt() ?? TeamHikeIdentity.colors.first,
      ended = data['status'] == 'ended',
      location = data['location'] is Map
          ? HikeCoordinate.tryFromFirestore(
              Map<String, dynamic>.from(data['location']),
            )
          : null;
  final String id, name;
  final int color;
  final bool ended;
  final HikeCoordinate? location;
}
