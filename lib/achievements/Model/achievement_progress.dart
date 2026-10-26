import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Computes achievement progress content hash.
String achievementProgressContentHash(List<Map<String, dynamic>> rows) {
  /// Computes string value.
  String stringValue(Object? value) => value is String ? value : '';

  /// Computes int value.
  int intValue(Object? value) =>
      value is num && value.isFinite ? value.toInt() : 0;
  final normalized =
      rows.map((row) {
        return <Object>[
          stringValue(row['achievementId']),
          stringValue(row['title']),
          stringValue(row['condition']),
          stringValue(row['category']),
          stringValue(row['iconName']),
          intValue(row['rewardPoints']),
          intValue(row['pointsAwarded']),
          stringValue(row['rewardType']),
          stringValue(row['metricKey']),
          intValue(row['targetCount']),
          intValue(row['progressCount']),
          intValue(row['sortOrder']),
          intValue(row['accentColorValue']),
          row['isActive'] != false,
          row['isUnlocked'] == true,
          stringValue(row['awardedAtLocal']),
        ];
      }).toList()..sort((left, right) {
        return (left.first as String).compareTo(right.first as String);
      });
  return crypto.sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
}

/// Represents achievement metric event.
class AchievementMetricEvent {
  /// Creates achievement metric event.
  const AchievementMetricEvent(this.metricKey, this.eventKey);
  final String metricKey;
  final String eventKey;
}

/// Computes completed hike achievement events.
List<AchievementMetricEvent> completedHikeAchievementEvents({
  required String owner,
  required String sessionId,
  required String sourceUpcomingHikeId,
  required String teamSessionId,
  required String trailId,
  required String state,
  required String country,
}) {
  /// Computes slug.
  String slug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.length > 120 ? normalized.substring(0, 120) : normalized;
  }

  var canonicalSessionId = sessionId;
  if (RegExp(r'^session_[0-9]{13}$').hasMatch(sessionId)) {
    final identity = sourceUpcomingHikeId.isNotEmpty
        ? 'upcoming:$sourceUpcomingHikeId'
        : teamSessionId.isNotEmpty
        ? 'team:$teamSessionId'
        : 'offline:$sessionId';
    canonicalSessionId =
        'hike_${crypto.sha256.convert(utf8.encode('$owner:$identity')).toString().substring(0, 48)}';
  }
  final normalizedState = switch (slug(state)) {
    'melaka' => 'malacca',
    'pulau-pinang' => 'penang',
    final value => value,
  };
  return [
    AchievementMetricEvent(
      'hike_completed',
      'hike-completed:$canonicalSessionId',
    ),
    if (trailId.trim().isNotEmpty)
      AchievementMetricEvent(
        'distinct_trail_completed',
        'distinct-trail-completed:${slug(trailId)}',
      ),
    if (slug(country) == 'malaysia' &&
        const {
          'johor',
          'kedah',
          'kelantan',
          'malacca',
          'negeri-sembilan',
          'pahang',
          'penang',
          'perak',
          'perlis',
          'sabah',
          'sarawak',
          'selangor',
          'terengganu',
        }.contains(normalizedState))
      AchievementMetricEvent(
        'malaysia_state_hiked',
        'malaysia-state-hiked:$normalizedState',
      ),
  ];
}
