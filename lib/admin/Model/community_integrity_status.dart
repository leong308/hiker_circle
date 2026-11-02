import 'community_flag.dart';

/// Represents a server-confirmed scan status and its shared next-check deadline.
class CommunityIntegrityStatus {
  /// Keeps countdown presentation independent of Firestore and the device clock.
  const CommunityIntegrityStatus({
    required this.status,
    this.lastRunAt,
    this.nextRunAt,
    this.updatedAt,
  });

  final String status;
  final DateTime? lastRunAt, nextRunAt, updatedAt;

  /// Restores old status documents while preferring the explicit server deadline.
  factory CommunityIntegrityStatus.fromMap(Map<String, dynamic> data) {
    final last = parseCommunityFlagTimestamp(data['lastRunAtMillis']);
    final running = data['status'] == 'running';
    return CommunityIntegrityStatus(
      status: data['status']?.toString() ?? '',
      lastRunAt: last,
      nextRunAt: running
          ? null
          : parseCommunityFlagTimestamp(data['nextRunAtMillis']) ??
                last?.add(const Duration(minutes: 30)),
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

  /// Derives the display from the deadline rather than decrementing a drifting counter.
  String nextCheckLabel(DateTime now) {
    if (isRunning) return 'Checking now…';
    final due = nextRunAt;
    if (due == null) return 'Waiting for the first check';
    final remaining = due.difference(now).inMilliseconds;
    if (remaining <= 0) return 'Next check due';
    final seconds = (remaining / 1000).ceil();
    final minutes = seconds ~/ 60;
    return 'Next check in ${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
