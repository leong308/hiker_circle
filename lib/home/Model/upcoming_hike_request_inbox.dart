import 'hike_join_request_stats.dart';

/// A host-visible request summary without contact, profile or route data.
class UpcomingHikeRequestEntry {
  /// Creates an inbox row from server-projected fields.
  const UpcomingHikeRequestEntry({
    required this.id,
    required this.hikeId,
    required this.name,
    required this.status,
    this.createdAt,
    this.decidedAt,
  });
  final String id, hikeId, name, status;
  final DateTime? createdAt, decidedAt;

  /// Uses the same decision labels in the inbox and history.
  String get statusLabel => switch (status) {
    'accepted' => 'Accepted',
    'rejected' => 'Rejected',
    'pending' => 'Pending',
    _ => 'Expired',
  };

  /// Reads only the approved public alias and lifecycle metadata.
  factory UpcomingHikeRequestEntry.fromMap(Map<String, dynamic> data) =>
      UpcomingHikeRequestEntry(
        id: data['requestId']?.toString() ?? '',
        hikeId: data['hikeId']?.toString() ?? '',
        name: safeJoinRequestAlias(data['requesterName']),
        status: data['status']?.toString() ?? 'expired',
        createdAt: DateTime.tryParse(data['createdAtLocal']?.toString() ?? ''),
        decidedAt: DateTime.tryParse(data['decidedAtLocal']?.toString() ?? ''),
      );
}

/// One independently paged pending or history list.
class UpcomingHikeRequestPage {
  /// Keeps the authoritative count alongside an opaque page cursor.
  const UpcomingHikeRequestPage({
    required this.rows,
    required this.pendingCount,
    this.hasMore = false,
    this.nextCursor,
  });
  final List<UpcomingHikeRequestEntry> rows;
  final int pendingCount;
  final bool hasMore;
  final String? nextCursor;

  /// Converts the callable response into immutable presentation data.
  factory UpcomingHikeRequestPage.fromMap(
    Map<String, dynamic> data,
  ) => UpcomingHikeRequestPage(
    rows: List.unmodifiable(
      (data['rows'] as List? ?? const []).whereType<Map>().map(
        (row) =>
            UpcomingHikeRequestEntry.fromMap(Map<String, dynamic>.from(row)),
      ),
    ),
    pendingCount: (data['pendingCount'] as num? ?? 0).toInt().clamp(0, 100000),
    hasMore: data['hasMore'] == true,
    nextCursor: data['nextCursor'] as String?,
  );
}
