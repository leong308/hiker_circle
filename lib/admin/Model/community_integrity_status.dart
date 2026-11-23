import 'community_flag.dart';

/// Represents a server-confirmed scan status.
class CommunityIntegrityStatus {
  /// Stores the latest scan result.
  const CommunityIntegrityStatus({
    required this.status,
    this.lastRunAt,
    this.updatedAt,
  });

  final String status;
  final DateTime? lastRunAt, updatedAt;

  /// Reads the latest server status.
  factory CommunityIntegrityStatus.fromMap(Map<String, dynamic> data) {
    final last = parseCommunityFlagTimestamp(data['lastRunAtMillis']);
    return CommunityIntegrityStatus(
      status: data['status']?.toString() ?? '',
      lastRunAt: last,
      updatedAt:
          parseCommunityFlagTimestamp(data['updatedAtMillis']) ??
          parseCommunityFlagTimestamp(data['startedAtMillis']) ??
          last,
    );
  }

  /// Prefers a newer live result over a just-completed manual response.
  static CommunityIntegrityStatus? latest(
    CommunityIntegrityStatus? live,
    CommunityIntegrityStatus? manual,
  ) {
    if (live == null) return manual;
    if (manual == null) return live;
    return (manual.updatedAt?.millisecondsSinceEpoch ?? 0) >
            (live.updatedAt?.millisecondsSinceEpoch ?? 0)
        ? manual
        : live;
  }

  /// Exposes progress without starting a second client-side scan.
  bool get isRunning => status == 'running';

  /// Keeps incomplete-check messaging separate from a successful check time.
  bool get isFailed => const {'failed', 'deferred'}.contains(status);
}
