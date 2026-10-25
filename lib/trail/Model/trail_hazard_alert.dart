import 'package:cloud_firestore/cloud_firestore.dart';

import 'trail_hazard_categories.dart';

/// A caution read from its Firestore document, rather than an FCM payload.
/// Notifications carry an identity; a fresh document determines risk and status.
class TrailHazardAlert {
  const TrailHazardAlert({
    required this.id,
    required this.trailId,
    required this.trailName,
    required this.type,
    required this.category,
    required this.isFatal,
    required this.status,
    required this.reportedAt,
    required this.expiresAt,
    this.description = '',
    this.cycle = 0,
  });

  factory TrailHazardAlert.fromMap(String hazardId, Map<String, dynamic> data) {
    final type = _text(data['hazardType'], fallback: 'Trail caution');
    final policyVersion = data['hazardPolicyVersion'];
    final riskLevel = _text(data['riskLevel']);
    final hasServerPolicy =
        policyVersion is num &&
        policyVersion >= 1 &&
        const {'fatal', 'normal'}.contains(riskLevel);
    final reportedAt =
        _date(data['reportedAt']) ?? _date(data['reportedAtLocal']);
    return TrailHazardAlert(
      id: hazardId,
      trailId: _text(data['trailId']),
      trailName: _text(data['trailName'], fallback: 'Your hiking trail'),
      type: type,
      category: hasServerPolicy
          ? _text(
              data['hazardCategory'],
              fallback: trailHazardCategoryFor(type) ?? 'Other caution',
            )
          : trailHazardCategoryFor(type) ?? 'Other caution',
      isFatal: hasServerPolicy
          ? riskLevel == 'fatal'
          : trailHazardTypeIsFatal(type),
      status: _text(data['status'], fallback: 'unverified').toLowerCase(),
      reportedAt: reportedAt,
      expiresAt:
          _date(data['expiresAt']) ??
          _date(data['expiresAtLocal']) ??
          reportedAt?.add(const Duration(days: 7)),
      description: _text(data['description']),
      cycle: data['cycle'] is num ? (data['cycle'] as num).toInt() : 0,
    );
  }

  final String id;
  final String trailId;
  final String trailName;
  final String type;
  final String category;

  /// The backend's fatal risk category means potentially life-threatening.
  /// It does not claim that a fatality has occurred.
  final bool isFatal;
  final String status;
  final DateTime? reportedAt;
  final DateTime? expiresAt;
  final String description;
  final int cycle;

  /// Scoped by the start flow to one attempt. A reopened caution has a new
  /// cycle, while repeated team-ready/countdown checks share this identity.
  String get fingerprint => '$id|$cycle|${isFatal ? 'fatal' : 'normal'}|$type';

  bool get isVerified => status == 'verified';

  bool active(DateTime now) =>
      !const {'resolved', 'rejected', 'deleted', 'expired'}.contains(status) &&
      expiresAt != null &&
      now.toUtc().isBefore(expiresAt!.toUtc());

  String get injunctiveMessage => isFatal
      ? 'Do not start this hike while this serious hazard may be present. We recommend cancelling or choosing another time.'
      : 'Check the caution details and stay alert while hiking.';

  String get descriptiveMessage => isFatal
      ? 'Starting a hike with this hazard could expose you or your group to serious harm.'
      : 'Knowing where this caution was reported helps you prepare and adjust your route.';

  String get verificationMessage => isVerified
      ? 'Reviewed by an admin. Trail conditions can change.'
      : 'Reported by a hiker. This report has not yet been verified.';
}

String _text(dynamic value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}
