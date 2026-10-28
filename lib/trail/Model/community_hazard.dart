import 'package:cloud_firestore/cloud_firestore.dart';

import 'trail_hazard_categories.dart';
import 'trail_hazard_expiry.dart';

/// Represents community hazard.
class CommunityHazard {
  /// Creates community hazard.
  const CommunityHazard({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description = '',
    this.reportedAt,
    this.expiresAt,
    this.status = 'unverified',
    this.reportCount = 1,
    this.resolutionCount = 0,
    this.media = const [],
    this.latestEvidence = const {},
    this.resolutionId,
    this.reportedBy = '',
    this.cycle = 0,
    bool? isFatal,
  }) : _isFatal = isFatal;
  final bool? _isFatal;

  /// Returns is fatal.
  bool get isFatal => _isFatal ?? trailHazardTypeIsFatal(type);
  final String id;
  final String type;
  final String description;
  final double latitude;
  final double longitude;
  final DateTime? reportedAt, expiresAt;
  final String status;
  final int reportCount, resolutionCount;
  final List<Map<String, dynamic>> media;
  final Map<String, dynamic> latestEvidence;
  final String? resolutionId;
  final String reportedBy;
  final int cycle;

  /// Returns is resolved.
  bool get isResolved => status == 'resolved';

  /// Checks whether active at.
  bool isActiveAt(DateTime now) =>
      !['rejected', 'deleted'].contains(status) &&
      now.isBefore(
        trailHazardExpiry(
              type: type,
              reportedAt: reportedAt,
              expiresAt: expiresAt,
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Creates from map.
  static CommunityHazard? fromMap(
    String id,
    Map<String, dynamic> data, {
    bool includeExpired = false,
    DateTime? now,
  }) {
    if (const {'rejected', 'deleted'}.contains(data['status'])) {
      return null;
    }
    final lat = data['latitude'];
    final lon = data['longitude'];
    if (lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      return null;
    }
    final time = data['reportedAt'];
    final reportedAt = time is Timestamp
        ? time.toDate()
        : DateTime.tryParse('${data['reportedAtLocal'] ?? ''}');
    final type = data['hazardType'] is String
        ? data['hazardType'] as String
        : 'Caution';
    final result = CommunityHazard(
      id: id,
      reportedBy: data['reportedBy'] is String
          ? (data['reportedBy'] as String).trim()
          : '',
      cycle: data['cycle'] is num
          ? (data['cycle'] as num).toInt().clamp(0, 1000000)
          : 0,
      type: type,
      isFatal:
          data['hazardPolicyVersion'] is num &&
              (data['hazardPolicyVersion'] as num) >= 1 &&
              const {'fatal', 'normal'}.contains(data['riskLevel'])
          ? data['riskLevel'] == 'fatal'
          : null,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      description: data['description'] is String
          ? data['description'] as String
          : '',
      expiresAt: trailHazardExpiry(
        type: type,
        reportedAt: reportedAt,
        expiresAt: data['expiresAt'] is Timestamp
            ? (data['expiresAt'] as Timestamp).toDate()
            : DateTime.tryParse('${data['expiresAtLocal'] ?? ''}'),
      ),
      status: data['status'] is String
          ? data['status'] as String
          : 'unverified',
      reportCount: data['reportCount'] is num
          ? (data['reportCount'] as num).toInt().clamp(1, 1000000)
          : 1,
      resolutionCount: data['resolutionCount'] is num
          ? (data['resolutionCount'] as num).toInt().clamp(0, 1000000)
          : 0,
      resolutionId: data['resolutionId'] is String
          ? data['resolutionId'] as String
          : null,
      media: cautionMediaFrom(data['media']),
      latestEvidence: data['latestEvidence'] is Map
          ? Map<String, dynamic>.from(data['latestEvidence'] as Map)
          : const {},
      reportedAt: reportedAt,
    );
    return includeExpired || result.isActiveAt(now ?? DateTime.now())
        ? result
        : null;
  }
}

/// Computes caution media from.
List<Map<String, dynamic>> cautionMediaFrom(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where(
            (m) =>
                m['url'] is String &&
                Uri.tryParse(m['url'] as String)?.scheme == 'https' &&
                m['contentType'] is String,
          )
          .toList()
    : const [];
