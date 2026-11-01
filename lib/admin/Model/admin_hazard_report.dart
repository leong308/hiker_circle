import 'package:cloud_firestore/cloud_firestore.dart';

import '../../trail/Model/community_hazard.dart';
import '../../trail/Model/trail_hazard_categories.dart';
import '../../trail/Model/trail_hazard_expiry.dart';

/// The community lifecycle shown in the administrator's Safety tabs.
enum AdminHazardStage {
  reported('Reported'),
  resolving('Resolving'),
  resolved('Resolved');

  /// Provides the readable tab name without tying the model to a widget.
  const AdminHazardStage(this.label);
  final String label;
}

/// Reads reports without dropping older records that have no map coordinates.
class AdminHazardReport {
  /// Keeps the document identity separate from potentially stale stored IDs.
  AdminHazardReport(this.id, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);

  static const resolutionTarget = 3;
  final String id;
  final Map<String, dynamic> data;

  /// Uses the stored caution type, including retired report options.
  String get type => _text(data['hazardType'], fallback: 'Trail caution');

  /// Keeps a missing trail name readable in historical reports.
  String get trailName => _text(data['trailName'], fallback: 'Unnamed trail');

  /// Reads the original hiker's description.
  String get description => _text(data['description']);

  /// Normalizes legacy status values for lifecycle grouping.
  String get status => _text(data['status']).toLowerCase();

  /// Uses the shared category catalog for searching and presentation.
  String get category => trailHazardCategoryFor(type) ?? 'Other caution';

  /// Includes the original reporter in the caution confirmation count.
  int get reportCount =>
      _count(data['reportCount'], fallback: 1).clamp(1, 1000000);

  /// Counts distinct resolution voters in the current report cycle.
  int get resolutionCount => _count(data['resolutionCount']);

  /// Separates current confirmations from evidence before a reopening.
  int get cycle => _count(data['cycle']);

  /// Keeps previously removed reports out of the community lifecycle tabs.
  bool get isVisible => !const {'rejected', 'deleted'}.contains(status);

  /// Prefers the server's classification and falls back for older records.
  bool get isSerious {
    if (data['hazardPolicyVersion'] is num &&
        (data['hazardPolicyVersion'] as num) >= 1 &&
        const {'fatal', 'normal'}.contains(data['riskLevel'])) {
      return data['riskLevel'] == 'fatal';
    }
    return data['severity'] == 'fatal' || trailHazardTypeIsFatal(type);
  }

  /// Accepts both current server timestamps and older ISO date strings.
  DateTime? get reportedAt =>
      _date(data['reportedAt']) ?? _date(data['reportedAtLocal']);

  /// Leaves an unavailable closure time unset instead of inventing one.
  DateTime? get resolvedAt =>
      _date(data['resolvedAt']) ?? _date(data['resolvedAtLocal']);

  /// Uses the latest recorded activity when ordering reports.
  DateTime? get updatedAt =>
      _date(data['updatedAt']) ?? _date(data['updatedAtLocal']) ?? reportedAt;

  /// Applies the same weather and trail report lifetimes as the hiker view.
  DateTime? get expiresAt => trailHazardExpiry(
    type: type,
    reportedAt: reportedAt,
    expiresAt: _date(data['expiresAt']) ?? _date(data['expiresAtLocal']),
  );

  /// Preserves explicit legacy closure and the current community quorum.
  bool get confirmedResolved =>
      status == 'resolved' || resolutionCount >= resolutionTarget;

  /// Returns supported HTTPS photo and video evidence only.
  List<Map<String, dynamic>> get media => cautionMediaFrom(data['media']);

  /// Reads the evidence that most recently reopened a report.
  Map<String, dynamic> get latestEvidence => data['latestEvidence'] is Map
      ? Map<String, dynamic>.from(data['latestEvidence'] as Map)
      : const {};

  /// Omits a marker when the stored latitude is invalid.
  double? get latitude => _coordinate(data['latitude'], 90);

  /// Omits a marker when the stored longitude is invalid.
  double? get longitude => _coordinate(data['longitude'], 180);

  /// Requires both coordinates before presenting the reusable map.
  bool get hasLocation => latitude != null && longitude != null;

  /// Expiry closes a report even when no new Firestore write is made.
  AdminHazardStage stageAt(DateTime now) {
    if (confirmedResolved ||
        status == 'expired' ||
        (expiresAt != null && !now.isBefore(expiresAt!))) {
      return AdminHazardStage.resolved;
    }
    if (resolutionCount > 0 || _text(data['resolutionId']).isNotEmpty) {
      return AdminHazardStage.resolving;
    }
    return AdminHazardStage.reported;
  }

  /// Preserves the reason a report closed instead of implying expiry is proof.
  String statusLabel(DateTime now) => switch (stageAt(now)) {
    AdminHazardStage.reported => 'Reported',
    AdminHazardStage.resolving => 'Awaiting confirmation',
    AdminHazardStage.resolved =>
      confirmedResolved
          ? resolutionCount >= resolutionTarget
                ? 'Confirmed resolved'
                : 'Marked resolved'
          : 'Expired',
  };

  /// Sorts closed reports by their actual closure and open reports by activity.
  DateTime? activityAt(DateTime now) =>
      stageAt(now) == AdminHazardStage.resolved
      ? confirmedResolved
            ? resolvedAt ?? updatedAt
            : expiresAt ?? updatedAt
      : updatedAt;

  /// Searches useful report text without exposing account identifiers.
  bool matches(String query) => '$type $trailName $description $category'
      .toLowerCase()
      .contains(query.trim().toLowerCase());

  /// Accepts Firestore and legacy date values without fabricating timestamps.
  static DateTime? _date(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : DateTime.tryParse('$value');

  /// Normalizes optional text for report presentation.
  static String _text(Object? value, {String fallback = ''}) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;

  /// Rejects malformed counters rather than displaying negative confirmations.
  static int _count(Object? value, {int fallback = 0}) =>
      value is num && value.isFinite && value >= 0 ? value.toInt() : fallback;

  /// Accepts only finite coordinates within the geographic bounds.
  static double? _coordinate(Object? value, int bound) =>
      value is num && value.isFinite && value.abs() <= bound
      ? value.toDouble()
      : null;
}
