// CommunityFlag keeps moderation provenance and safe rule evidence distinct.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'community_moderation_policy.dart';

/// Defines the community flag source choices.
enum CommunityFlagSource {
  keywords,
  pattern,
  integrity,
  earlierReview,
  localRules,
  unavailable,
}

/// Defines the community flag source filter choices.
enum CommunityFlagSourceFilter {
  all,
  keywords,
  pattern,
  integrity,
  earlierReview,
  localRules,
  unavailable;

  /// Returns label.
  String get label => switch (this) {
    all => 'All sources',
    keywords => 'Keywords',
    pattern => 'Patterns',
    integrity => 'Record checks',
    earlierReview => 'Earlier checks',
    localRules => 'Local rules',
    unavailable => 'Source unavailable',
  };
}

/// Represents community flag.
class CommunityFlag {
  /// Creates community flag.
  CommunityFlag({required this.id, required Map<String, dynamic> data})
    : data = Map<String, dynamic>.unmodifiable(data);

  final String id;
  final Map<String, dynamic> data;

  /// Returns content type.
  String get contentType => _string(data['contentType']).toLowerCase();

  /// Returns is comment.
  bool get isComment => contentType == 'comment';

  /// Returns content type label.
  String get contentTypeLabel => isComment ? 'Comment' : 'Post';

  /// Returns post id.
  String get postId => _string(data['postId']);

  /// Returns source path.
  String get sourcePath => _string(data['sourcePath']);

  /// Returns fingerprint.
  String get fingerprint => _string(data['fingerprint']);

  /// Returns status.
  String get status => _string(data['status']).toLowerCase();

  /// Returns model.
  String get model => _string(data['model']);

  /// Returns provider.
  String get provider => _string(data['provider']);

  /// Returns categories.
  List<String> get categories => _strings(data['categories']);

  /// Returns category labels.
  List<String> get categoryLabels => {
    for (final category in categories)
      CommunityModerationPolicy.categoryLabel(category),
  }.toList(growable: false);

  /// Returns reasons.
  List<String> get reasons => _strings(data['reasons']);

  /// Returns title.
  String get title {
    if (reasons.isNotEmpty) return reasons.first;
    if (categoryLabels.isNotEmpty) return categoryLabels.first;
    return 'Content needs review';
  }

  /// Returns severity.
  String get severity {
    final value = _string(data['severity']).toLowerCase();
    return const {'low', 'medium', 'high', 'critical'}.contains(value)
        ? value
        : 'unknown';
  }

  /// Returns severity label.
  String get severityLabel => switch (severity) {
    'low' => 'Low',
    'medium' => 'Medium',
    'high' => 'High',
    'critical' => 'Critical',
    _ => 'Unspecified',
  };

  /// Returns flagged at.
  DateTime? get flaggedAt =>
      parseCommunityFlagTimestamp(data['flaggedAtMillis']) ??
      parseCommunityFlagTimestamp(data['flaggedAt']);

  /// Returns source.
  CommunityFlagSource get source {
    final explicit = _string(data['detectionSource']).toLowerCase();
    switch (explicit) {
      case 'keywords':
        return CommunityFlagSource.keywords;
      case 'pattern':
        return CommunityFlagSource.pattern;
      case 'integrity':
        return CommunityFlagSource.integrity;
      case 'local_rules':
        return CommunityFlagSource.localRules;
    }
    // Retain flags produced by earlier checkers without exposing a retired provider.
    if (model.isNotEmpty || provider.isNotEmpty || explicit.isNotEmpty) {
      return CommunityFlagSource.earlierReview;
    }
    if (explicit.isEmpty &&
        model.isEmpty &&
        provider.isEmpty &&
        categories.any(
          (value) => value == 'sensitive_content' || value == 'integrity',
        )) {
      // Older local checks saved categories without their exact matched rule.
      return CommunityFlagSource.localRules;
    }
    return CommunityFlagSource.unavailable;
  }

  /// Returns source label.
  String get sourceLabel => switch (source) {
    CommunityFlagSource.keywords => 'Keyword match',
    CommunityFlagSource.pattern => 'Pattern match',
    CommunityFlagSource.integrity => 'Record check',
    CommunityFlagSource.earlierReview => 'Earlier check',
    CommunityFlagSource.localRules => 'Local rules',
    CommunityFlagSource.unavailable => 'Source unavailable',
  };

  /// Returns source description.
  String get sourceDescription => switch (source) {
    CommunityFlagSource.keywords =>
      'A policy phrase matched. Pattern checks may also have matched.',
    CommunityFlagSource.pattern =>
      'An authored policy pattern matched. Personal values are not copied into the evidence.',
    CommunityFlagSource.integrity =>
      'A content record needs checking for missing or invalid data.',
    CommunityFlagSource.earlierReview =>
      'A saved flag from an earlier checker. Review it against the original content; the current checker uses local rules.',
    CommunityFlagSource.localRules =>
      'An older local check flagged this content without saving the exact matched rule.',
    CommunityFlagSource.unavailable =>
      'This flag does not identify a recognized detection source.',
  };

  /// Returns matched keywords.
  List<String> get matchedKeywords => _strings(data['matchedKeywords'])
      .map((value) => value.toLowerCase())
      .where(CommunityModerationPolicy.keywords.contains)
      .toSet()
      .toList(growable: false);

  /// Unknown evidence is not rendered: it could contain a raw sensitive value.
  List<String> get evidenceLabels {
    final labels = <String>{};
    for (final evidence in _strings(data['detectionEvidence'])) {
      final label = CommunityModerationPolicy.evidenceLabel(evidence);
      if (label != null) {
        labels.add(label);
        continue;
      }
    }
    for (final phrase in matchedKeywords) {
      labels.add('Matched phrase “$phrase”');
    }
    return labels.toList(growable: false);
  }

  /// Computes matches source.
  bool matchesSource(CommunityFlagSourceFilter filter) =>
      filter == CommunityFlagSourceFilter.all || filter.name == source.name;

  /// Returns searchable text.
  String get searchableText => [
    contentTypeLabel,
    sourceLabel,
    title,
    severityLabel,
    ...categoryLabels,
    ...reasons,
    ...matchedKeywords,
    ...evidenceLabels,
  ].join(' ').toLowerCase();

  /// Computes matches query.
  bool matchesQuery(String query) {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    return terms.every(searchableText.contains);
  }
}

/// Computes string.
String _string(Object? value) => value is String ? value.trim() : '';

/// Computes strings.
List<String> _strings(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
    : const [];

/// Supports current millisecond fields and older Firestore/ISO timestamps.
DateTime? parseCommunityFlagTimestamp(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is num) {
    if (!value.isFinite || value.abs() > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
  }
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
