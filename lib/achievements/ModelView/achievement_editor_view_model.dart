import 'package:flutter/foundation.dart';
import '../Model/achievement_catalog.dart';

/// Owns metric selection, authoring defaults, unit conversion and validation for reward moderation.
class AchievementEditorViewModel extends ChangeNotifier {
  /// Opens a supported rule without replacing administrator-authored descriptions.
  AchievementEditorViewModel({Map<String, dynamic>? initial})
    : original = initial ?? const {} {
    metricKey =
        AchievementCatalog.metric(
              original['metricKey']?.toString() ?? '',
            )?['key']
            as String? ??
        AchievementCatalog.metrics.first['key'] as String;
    final metric = activity;
    categoryId = metric['categoryId'] as String;
    rewardType =
        original['rewardType'] == 'cumulative' ||
            metric['allowsOneTime'] != true
        ? 'cumulative'
        : 'one_time';
    isActive = original['isActive'] != false;
    final target =
        (original['targetCount'] as num?)?.toInt() ??
        (metric['defaultTarget'] as num).toInt();
    values.addAll({
      'title': original['title']?.toString() ?? '',
      'condition':
          original['condition']?.toString() ??
          AchievementCatalog.goal(metricKey, target),
      ...AchievementCatalog.content({...original, 'metricKey': metricKey}),
      'targetCount': AchievementCatalog.quantity(
        metricKey,
        target,
        unit: false,
      ),
      'rewardPoints': original['rewardPoints']?.toString() ?? '100',
      'sortOrder': original['sortOrder']?.toString() ?? '100',
    });
  }

  final Map<String, dynamic> original;
  final values = <String, String>{};
  late String metricKey, categoryId, rewardType;
  late bool isActive;
  int contentRevision = 0;

  /// Returns the selected executable metric.
  Map<String, dynamic> get activity => AchievementCatalog.metric(metricKey)!;

  /// Returns the category's visual defaults.
  Map<String, dynamic> get category => AchievementCatalog.categories.firstWhere(
    (row) => row['id'] == categoryId,
  );

  /// Limits each category to measurements the application implements.
  List<Map<String, dynamic>> get activities => AchievementCatalog.metrics
      .where((row) => row['categoryId'] == categoryId)
      .toList();

  /// Converts the displayed target into exact stored integer units.
  int? get target {
    if (rewardType == 'one_time') return 1;
    final value = double.tryParse(values['targetCount'] ?? '');
    if (value == null || !value.isFinite) return null;
    final scaled = value * (activity['scale'] as num);
    if ((scaled - scaled.round()).abs() > 0.000001) return null;
    return scaled.round();
  }

  /// Switches category and replaces only text still equal to its previous suggested content.
  void selectCategory(String id) {
    if (id == categoryId) return;
    final next = AchievementCatalog.metrics.firstWhere(
      (row) => row['categoryId'] == id,
    );
    selectMetric(next['key'] as String);
  }

  /// Applies relevant defaults while preserving custom explanations and the title.
  void selectMetric(String key) {
    if (key == metricKey) return;
    final previousContent = AchievementCatalog.content({
      'metricKey': metricKey,
    });
    final previousGoal = AchievementCatalog.goal(metricKey, target ?? 1);
    metricKey = key;
    categoryId = activity['categoryId'] as String;
    if (activity['allowsOneTime'] != true) rewardType = 'cumulative';
    final nextTarget = (activity['defaultTarget'] as num).toInt();
    values['targetCount'] = AchievementCatalog.quantity(
      key,
      nextTarget,
      unit: false,
    );
    final nextContent = AchievementCatalog.content({'metricKey': key});
    for (final field in previousContent.keys) {
      if (values[field]?.trim().isEmpty != false ||
          values[field] == previousContent[field]) {
        values[field] = nextContent[field]!;
      }
    }
    if (values['condition'] == previousGoal) {
      values['condition'] = AchievementCatalog.goal(key, nextTarget);
    }
    contentRevision++;
    notifyListeners();
  }

  /// Changes the target mode without permitting one metre/minute to masquerade as a whole milestone.
  void selectRewardType(String type) {
    final previousGoal = AchievementCatalog.goal(metricKey, target ?? 1);
    rewardType = activity['allowsOneTime'] == true ? type : 'cumulative';
    if (values['condition'] == previousGoal) {
      values['condition'] = AchievementCatalog.goal(metricKey, target ?? 1);
    }
    contentRevision++;
    notifyListeners();
  }

  /// Updates text and keeps an unchanged suggested goal in sync with the target.
  void update(String field, String value) {
    final oldGoal = AchievementCatalog.goal(metricKey, target ?? 1);
    values[field] = value;
    if (field == 'targetCount' &&
        values['condition'] == oldGoal &&
        target != null) {
      values['condition'] = AchievementCatalog.goal(metricKey, target!);
      contentRevision++;
      notifyListeners();
    }
  }

  /// Validates actual measurement limits rather than accepting an unreachable target.
  String? validateTarget(String? _) {
    final number = target;
    return number == null ||
            number < 1 ||
            number > (activity['maxTarget'] as num)
        ? 'Enter a target above zero, up to ${AchievementCatalog.quantity(metricKey, (activity['maxTarget'] as num).toInt())}.'
        : null;
  }

  /// Requires complete, bounded public descriptions.
  String? validateText(String field, String? value) {
    final max = field == 'title' ? 160 : 1000;
    return value == null || value.trim().isEmpty
        ? 'Enter this achievement detail.'
        : value.trim().length > max
        ? 'Use $max characters or fewer.'
        : null;
  }

  /// Validates points independently of the editable recognition message.
  String? validatePoints(String? value) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 1 || number > 1000000
        ? 'Enter 1–1,000,000 points.'
        : null;
  }

  /// Produces the same authored fields displayed to hikers; Firebase revalidates every rule.
  Map<String, dynamic> save() => {
    for (final field in [
      'title',
      'condition',
      'whyItMatters',
      'whatCounts',
      'rewardRecognition',
    ])
      field: values[field]!.trim(),
    'metricKey': metricKey,
    'category': category['label'],
    'rewardType': rewardType,
    'targetCount': target,
    'rewardPoints': int.parse(values['rewardPoints']!),
    'sortOrder': int.tryParse(values['sortOrder'] ?? '') ?? 100,
    'iconName': original['iconName'] ?? category['iconName'],
    'accentColorValue':
        original['accentColorValue'] ?? category['accentColorValue'],
    'isActive': isActive,
  };
}
