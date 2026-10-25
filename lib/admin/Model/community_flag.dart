// CommunityFlag keeps moderation provenance and safe rule evidence distinct.
import 'package:cloud_firestore/cloud_firestore.dart';

enum CommunityFlagSource {
  keywords,
  pattern,
  integrity,
  gemini,
  localRules,
  unavailable,
}

enum CommunityFlagSourceFilter {
  all,
  keywords,
  pattern,
  integrity,
  gemini,
  localRules,
  unavailable;

  String get label => switch (this) {
    all => 'All sources',
    keywords => 'Keywords',
    pattern => 'Patterns',
    integrity => 'Record checks',
    gemini => 'Gemini',
    localRules => 'Local rules',
    unavailable => 'Source unavailable',
  };
}

/// These are policy phrases, never arbitrary text copied from a community post.
const communityFlagAllowedKeywords = <String>[
  'my name is',
  'nama saya',
  'password',
  'kata laluan',
  'otp',
  'verification code',
  'authenticator',
  'diagnosed',
  'diagnosis',
  'medical record',
  'my injury',
  'my illness',
  'alamat rumah',
  'home address',
  'ic number',
  'passport',
];

const _categoryLabels = <String, String>{
  'spam_scam': 'Possible spam or scam',
  'harassment': 'Possible harassment',
  'hate': 'Possible hate speech',
  'sexual': 'Possible sexual content',
  'violence': 'Possible threats or graphic violence',
  'privacy': 'Personal information',
  'unsafe_advice': 'Potentially dangerous advice',
  'integrity': 'Content record needs review',
  'sensitive_content': 'Sensitive information',
  'provider_safety': 'Provider safety review',
  'check_unavailable': 'Check unavailable',
};

const _ruleLabels = <String, String>{
  'pattern:email_address': 'Email address pattern',
  'pattern:phone_number': 'Phone number pattern',
  'pattern:coordinates': 'Coordinate pattern',
  'record:invalid_path': 'Invalid content reference',
  'record:invalid_text': 'Invalid text format',
  'record:empty_comment': 'Empty comment',
  'record:text_too_long': 'Text exceeds the length limit',
  'record:invalid_author': 'Missing or invalid author',
};

class CommunityFlag {
  CommunityFlag({required this.id, required Map<String, dynamic> data})
    : data = Map<String, dynamic>.unmodifiable(data);

  final String id;
  final Map<String, dynamic> data;

  String get contentType => _string(data['contentType']).toLowerCase();
  bool get isComment => contentType == 'comment';
  String get contentTypeLabel => isComment ? 'Comment' : 'Post';
  String get postId => _string(data['postId']);
  String get sourcePath => _string(data['sourcePath']);
  String get fingerprint => _string(data['fingerprint']);
  String get status => _string(data['status']).toLowerCase();
  String get model => _string(data['model']);
  String get provider => _string(data['provider']);

  List<String> get categories => _strings(data['categories']);
  List<String> get categoryLabels => {
    for (final category in categories)
      _categoryLabels[category] ?? 'Other review concern',
  }.toList(growable: false);
  List<String> get reasons => _strings(data['reasons']);

  String get title {
    if (reasons.isNotEmpty) return reasons.first;
    if (categoryLabels.isNotEmpty) return categoryLabels.first;
    return 'Content needs review';
  }

  String get severity {
    final value = _string(data['severity']).toLowerCase();
    return const {'low', 'medium', 'high', 'critical'}.contains(value)
        ? value
        : 'unknown';
  }

  String get severityLabel => switch (severity) {
    'low' => 'Low',
    'medium' => 'Medium',
    'high' => 'High',
    'critical' => 'Critical',
    _ => 'Unspecified',
  };

  DateTime? get flaggedAt =>
      parseCommunityFlagTimestamp(data['flaggedAtMillis']) ??
      parseCommunityFlagTimestamp(data['flaggedAt']);

  CommunityFlagSource get source {
    final explicit = _string(data['detectionSource']).toLowerCase();
    switch (explicit) {
      case 'keywords':
        return CommunityFlagSource.keywords;
      case 'pattern':
        return CommunityFlagSource.pattern;
      case 'integrity':
        return CommunityFlagSource.integrity;
      case 'gemini':
        return CommunityFlagSource.gemini;
      case 'local_rules':
        return CommunityFlagSource.localRules;
    }
    // A model field alone is not proof that Gemini produced this verdict.
    if (_isGeminiModel(model) ||
        const {'gemini', 'google_gemini'}.contains(provider.toLowerCase())) {
      return CommunityFlagSource.gemini;
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

  String get sourceLabel => switch (source) {
    CommunityFlagSource.keywords => 'Keyword match',
    CommunityFlagSource.pattern => 'Pattern match',
    CommunityFlagSource.integrity => 'Record check',
    CommunityFlagSource.gemini => 'Gemini',
    CommunityFlagSource.localRules => 'Local rules',
    CommunityFlagSource.unavailable => 'Source unavailable',
  };

  String get sourceDescription => switch (source) {
    CommunityFlagSource.keywords =>
      'A policy phrase matched. Pattern checks may also have matched.',
    CommunityFlagSource.pattern =>
      'A sensitive information pattern matched; the value is not copied into this flag.',
    CommunityFlagSource.integrity =>
      'A content record needs checking for missing or invalid data.',
    CommunityFlagSource.gemini =>
      'This saved flag identifies Gemini as its source. Review its suggestion against the original content.',
    CommunityFlagSource.localRules =>
      'An older local check flagged this content without saving the exact matched rule.',
    CommunityFlagSource.unavailable =>
      'This flag does not identify a recognized detection source.',
  };

  List<String> get matchedKeywords => _strings(data['matchedKeywords'])
      .map((value) => value.toLowerCase())
      .where(communityFlagAllowedKeywords.contains)
      .toSet()
      .toList(growable: false);

  /// Unknown evidence is not rendered: it could contain a raw sensitive value.
  List<String> get evidenceLabels {
    final labels = <String>{};
    for (final evidence in _strings(data['detectionEvidence'])) {
      final label = _ruleLabels[evidence];
      if (label != null) {
        labels.add(label);
        continue;
      }
      for (final phrase in communityFlagAllowedKeywords) {
        if (evidence == 'keyword:${phrase.replaceAll(' ', '_')}') {
          labels.add('Matched phrase “$phrase”');
          break;
        }
      }
    }
    for (final phrase in matchedKeywords) {
      labels.add('Matched phrase “$phrase”');
    }
    return labels.toList(growable: false);
  }

  bool matchesSource(CommunityFlagSourceFilter filter) =>
      filter == CommunityFlagSourceFilter.all || filter.name == source.name;

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

  bool matchesQuery(String query) {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    return terms.every(searchableText.contains);
  }
}

String _string(Object? value) => value is String ? value.trim() : '';

List<String> _strings(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
    : const [];

bool _isGeminiModel(String value) => RegExp(
  r'^(?:(?:publishers/google/)?models/|google/)?gemini(?:-[a-z0-9][a-z0-9._-]*)?$',
  caseSensitive: false,
).hasMatch(value);

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
