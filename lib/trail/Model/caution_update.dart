import 'package:cloud_firestore/cloud_firestore.dart';

import 'community_hazard.dart';

/// One hiker's evidence or confirmation in a caution's history.
class CautionUpdate {
  /// Creates a caution update without exposing account details in the UI.
  const CautionUpdate({
    required this.id,
    required this.uid,
    required this.action,
    this.cycle = 0,
    this.description = '',
    this.media = const [],
    this.createdAt,
  });

  /// Decodes the server's update record.
  factory CautionUpdate.fromMap(String id, Map<String, dynamic> data) {
    final time = data['createdAt'] ?? data['createdAtLocal'];
    return CautionUpdate(
      id: id,
      uid: data['uid'] is String ? (data['uid'] as String).trim() : '',
      action: data['action'] is String ? data['action'] as String : '',
      cycle: data['cycle'] is num ? (data['cycle'] as num).toInt() : 0,
      description: data['description'] is String
          ? (data['description'] as String).trim()
          : '',
      media: cautionMediaFrom(data['media']),
      createdAt: time is Timestamp
          ? time.toDate()
          : time is DateTime
          ? time
          : DateTime.tryParse('$time'),
    );
  }

  final String id, uid, action, description;
  final int cycle;
  final List<Map<String, dynamic>> media;
  final DateTime? createdAt;
}

/// The viewer's confirmations for the current caution cycle.
class CautionViewerVotes {
  /// Creates an account-scoped snapshot of the viewer's existing votes.
  const CautionViewerVotes({
    this.confirmed = false,
    this.resolutionConfirmed = false,
    this.authoritative = false,
  });

  final bool confirmed, resolutionConfirmed, authoritative;
}
