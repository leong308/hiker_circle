import 'dart:convert';

import 'package:flutter/services.dart';

/// An admin-readable category from the same JSON file executed by Firebase.
class CommunityModerationCategory {
  /// Keeps descriptions and phrase lists together without a second Dart policy.
  const CommunityModerationCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.keywords,
  });

  final String id, label, description;
  final List<String> keywords;
}

/// Loads the single bundled policy and allows only its static evidence to display.
abstract final class CommunityModerationPolicy {
  static Future<void>? _loading;
  static List<CommunityModerationCategory> _categories = const [];
  static List<Map<String, String>> _patterns = const [];
  static Map<String, String> _labels = const {}, _evidence = const {};
  static Set<String> _keywords = const {};

  /// Loads once before app UI starts; failed reads can be retried.
  static Future<void> load() => _loading ??= _read();

  /// Decodes only the shared catalog, with no hardcoded phrase fallback.
  static Future<void> _read() async {
    try {
      final data =
          jsonDecode(
                await rootBundle.loadString(
                  'functions/community_moderation_policy.json',
                ),
              )
              as Map<String, dynamic>;
      final definitions = data['categories'] as Map<String, dynamic>;
      final categories = <CommunityModerationCategory>[];
      final patterns = <Map<String, String>>[];
      final keywords = <String>{};
      final labels = Map<String, String>.from(data['legacyLabels'] as Map);
      final evidence = <String, String>{};
      for (final entry in definitions.entries) {
        final row = entry.value as Map<String, dynamic>;
        final phrases = List<String>.from(row['keywords'] as List);
        categories.add(
          CommunityModerationCategory(
            id: entry.key,
            label: row['label'] as String,
            description: row['description'] as String,
            keywords: List.unmodifiable(phrases),
          ),
        );
        labels[entry.key] = row['label'] as String;
        keywords.addAll(phrases);
        for (final phrase in phrases) {
          evidence['keyword:${phrase.replaceAll(' ', '_')}'] =
              'Matched phrase “$phrase”';
        }
        for (final pattern in row['patterns'] as List) {
          evidence[pattern['id'] as String] = pattern['label'] as String;
          patterns.add({
            'label': pattern['label'] as String,
            'category': row['label'] as String,
          });
        }
      }
      for (final rule in data['recordRules'] as List) {
        evidence[rule['id'] as String] = rule['label'] as String;
      }
      _categories = List.unmodifiable(categories);
      _patterns = List.unmodifiable(patterns);
      _labels = Map.unmodifiable(labels);
      _evidence = Map.unmodifiable(evidence);
      _keywords = Set.unmodifiable(keywords);
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  /// Lists all implemented categories in catalog order.
  static List<CommunityModerationCategory> get categories => _categories;

  /// Lists wording and personal-information patterns without exposing matched values.
  static List<Map<String, String>> get patterns => _patterns;

  /// Allows matched phrases only when they were authored in the bundled policy.
  static Set<String> get keywords => _keywords;

  /// Names current and legacy concerns while keeping unknown values neutral.
  static String categoryLabel(String id) =>
      _labels[id] ?? 'Other review concern';

  /// Suppresses unknown evidence, which may contain arbitrary private text.
  static String? evidenceLabel(String id) => _evidence[id];
}
