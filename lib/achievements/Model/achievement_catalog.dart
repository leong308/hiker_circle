import 'dart:convert';
import 'package:flutter/services.dart';

/// Loads the single catalog shared with Firebase, including categories, metrics and seed rules.
abstract final class AchievementCatalog {
  static Map<String, dynamic> _rules = const {};
  static Future<void>? _loading;

  /// Loads once per isolate; the JSON file is bundled for offline use.
  static Future<void> load() => _loading ??= _read();

  /// Decodes the authored catalog without maintaining another Dart copy of its rules.
  static Future<void> _read() async {
    try {
      _rules = Map<String, dynamic>.from(
        jsonDecode(
              await rootBundle.loadString('functions/achievement_rules.json'),
            )
            as Map,
      );
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  /// Lists supported categories in their display order.
  static List<Map<String, dynamic>> get categories =>
      _maps(_rules['categories']);

  /// Lists metrics backed by actual app events.
  static List<Map<String, dynamic>> get metrics => _maps(_rules['metrics']);

  /// Returns Malaysian states supported by the exploration metric.
  static Set<String> get malaysiaStates =>
      Set<String>.from(_rules['malaysiaStates'] as List? ?? const []);

  /// Returns definitions for the offline catalog, without archived check-in rewards.
  static List<Map<String, dynamic>> get seeds =>
      (Map<String, dynamic>.from(_rules['achievements'] as Map? ?? const {}))
          .entries
          .map(
            (entry) => {
              'achievementId': entry.key,
              ...Map<String, dynamic>.from(entry.value as Map),
            },
          )
          .toList();

  /// Returns the catalog's maximum contribution from one trusted event.
  static int eventLimit(String key) =>
      (metric(key)?['maxIncrement'] as num?)?.toInt() ?? 0;

  /// Resolves a metric without accepting arbitrary text as a tracking rule.
  static Map<String, dynamic>? metric(String key) {
    for (final row in metrics) {
      if (row['key'] == key) return row;
    }
    return null;
  }

  /// Suppresses unsupported and explicitly retired definitions without removing earned points.
  static bool visible(Map<String, dynamic> row) =>
      metric(row['metricKey']?.toString() ?? '') != null &&
      !(_rules['retiredAchievementIds'] as List? ?? const []).contains(
        row['achievementId'],
      );

  /// Resolves admin-authored detail text, with accurate catalog defaults for older definitions.
  static Map<String, String> content(Map<String, dynamic> row) {
    final activity = metric(row['metricKey']?.toString() ?? '');
    final category = categories
        .where((c) => c['id'] == activity?['categoryId'])
        .firstOrNull;
    return {
      'whyItMatters': _text(row['whyItMatters'], category?['description']),
      'whatCounts': _text(
        row['whatCounts'],
        activity?['whatCounts'] ?? row['condition'],
      ),
      'rewardRecognition': _text(
        row['rewardRecognition'],
        (_rules['defaults'] as Map?)?['rewardRecognition'],
      ),
    };
  }

  /// Formats stored integer quantities in the units chosen in the admin editor.
  static String quantity(String key, int value, {bool unit = true}) {
    final activity = metric(key);
    final scale = (activity?['scale'] as num?)?.toDouble() ?? 1;
    final number = value / scale;
    final text = number.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    final label = scale == 1 ? value.toString() : text;
    return unit ? '$label ${activity?['unit'] ?? 'activities'}' : label;
  }

  /// Builds the goal shown in the editor from the selected measurement and target.
  static String goal(String key, int target) =>
      (metric(key)?['goal'] as String? ?? '').replaceAll(
        '{target}',
        quantity(key, target, unit: false),
      );

  /// Normalizes dynamic JSON lists for callers.
  static List<Map<String, dynamic>> _maps(Object? raw) =>
      (raw as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  /// Uses a fallback only when authored content is absent.
  static String _text(Object? value, Object? fallback) =>
      value is String && value.trim().isNotEmpty
      ? value.trim()
      : fallback?.toString().trim() ?? '';
}
