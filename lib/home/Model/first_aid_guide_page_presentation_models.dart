part of '../first_aid_guide_page_feature.dart';

/// Represents first aid topic.
class FirstAidTopic {
  /// Creates first aid topic.
  const FirstAidTopic({
    required this.id,
    required this.title,
    required this.category,
    required this.steps,
    this.scenarios = const [],
    this.guidanceSource = '',
    this.guidanceSourceUrl = '',
  });

  /// Creates first aid topic from JSON data.
  factory FirstAidTopic.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    return FirstAidTopic(
      id: _stringFrom(json['id']),
      title: _stringFrom(json['title']),
      category: _stringFrom(json['category']),
      steps: rawSteps is List
          ? rawSteps.whereType<String>().toList()
          : const [],
      scenarios: (json['scenarios'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FirstAidScenario.fromJson)
          .toList(growable: false),
      guidanceSource: _stringFrom(json['guidanceSource']),
      guidanceSourceUrl: _stringFrom(json['guidanceSourceUrl']),
    );
  }

  final String id;
  final String title;
  final String category;
  final List<String> steps;
  final List<FirstAidScenario> scenarios;
  final String guidanceSource;
  final String guidanceSourceUrl;

  static const List<FirstAidTopic> defaults = [
    FirstAidTopic(
      id: 'cpr',
      title: 'Adult CPR and AED',
      category: 'CPR',
      guidanceSource: 'St John Ambulance — How to do CPR (reviewed April 2025)',
      guidanceSourceUrl: 'https://www.sja.org.uk/first-aid-advice/cpr/',
      steps: [
        'If an adult is unresponsive, call emergency services on speaker and check breathing.',
        'If breathing is absent or abnormal, including gasping, start compressions at 100–120 per minute, 5–6 cm deep.',
        'If trained, give 30 compressions and 2 breaths. Otherwise keep compressing. Follow the dispatcher and any AED prompts.',
        'Continue until rescuers take over, normal breathing and signs of life return, or you cannot continue. Swap with a helper when possible.',
      ],
    ),
    FirstAidTopic(
      id: 'sprain',
      title: 'Sprain or Twisted Ankle',
      category: 'Falls and Injury',
      steps: [
        'Stop walking and rest.',
        'Avoid placing weight on the injured ankle.',
        'Apply a cold compress if available.',
        'Use support or bandage if trained to do so.',
        'Request help if unable to continue safely.',
      ],
    ),
    FirstAidTopic(
      id: 'heat_exhaustion',
      title: 'Heat Exhaustion',
      category: 'Heat Exhaustion',
      steps: [
        'Move to shade and stop hiking.',
        'Sip water slowly if the person is alert.',
        'Cool skin with wet cloth or fanning.',
        'Request help if confusion, fainting, or vomiting occurs.',
      ],
    ),
  ];

  /// Computes string from.
  static String _stringFrom(Object? value) {
    return value is String ? value : '';
  }
}

/// Represents first aid scenario.
class FirstAidScenario {
  /// Creates first aid scenario.
  const FirstAidScenario({
    required this.id,
    required this.title,
    required this.summary,
    required this.urgency,
    required this.steps,
    required this.avoid,
    required this.referenceName,
    required this.referenceUrl,
  });

  /// Creates first aid scenario from JSON data.
  factory FirstAidScenario.fromJson(Map<String, dynamic> json) {
    /// Computes strings.
    List<String> strings(Object? value) => value is List
        ? value.whereType<String>().toList(growable: false)
        : const <String>[];

    return FirstAidScenario(
      id: FirstAidTopic._stringFrom(json['id']),
      title: FirstAidTopic._stringFrom(json['title']),
      summary: FirstAidTopic._stringFrom(json['summary']),
      urgency: FirstAidTopic._stringFrom(json['urgency']),
      steps: strings(json['steps']),
      avoid: strings(json['avoid']),
      referenceName: FirstAidTopic._stringFrom(json['referenceName']),
      referenceUrl: FirstAidTopic._stringFrom(json['referenceUrl']),
    );
  }

  final String id;
  final String title;
  final String summary;
  final String urgency;
  final List<String> steps;
  final List<String> avoid;
  final String referenceName;
  final String referenceUrl;
}

/// Represents first aid category.
class _FirstAidCategory {
  /// Creates first aid category.
  const _FirstAidCategory({required this.title, required this.topics});

  final String title;
  final List<FirstAidTopic> topics;

  /// Returns is cpr.
  bool get isCpr => topics.any((topic) => topic.id == 'cpr');

  /// Creates from topics.
  static List<_FirstAidCategory> fromTopics(List<FirstAidTopic> topics) {
    final grouped = <String, List<FirstAidTopic>>{};
    for (final topic in topics) {
      final key = topic.category.isEmpty ? topic.title : topic.category;
      grouped.putIfAbsent(key, () => []).add(topic);
    }
    return grouped.entries
        .map(
          (entry) => _FirstAidCategory(title: entry.key, topics: entry.value),
        )
        .toList()
      ..sort((a, b) {
        if (a.isCpr != b.isCpr) return a.isCpr ? -1 : 1;
        return a.title.compareTo(b.title);
      });
  }

  /// Returns summary.
  String get summary {
    if (isCpr) return 'Adult chest compressions, rescue breaths and AED use.';
    final lower = title.toLowerCase();
    if (lower.contains('bleeding')) {
      return 'Control bleeding, keep the person still, and escalate early.';
    }
    if (lower.contains('heat')) {
      return 'Cool the body, hydrate slowly, and watch for confusion.';
    }
    if (lower.contains('snake')) {
      return 'Keep calm, stay still, and get professional help quickly.';
    }
    if (lower.contains('lost')) {
      return 'Stop, preserve battery, mark location, and signal calmly.';
    }
    if (lower.contains('weather')) {
      return 'Move away from exposed areas and avoid flood-prone routes.';
    }
    return 'Stabilize the person and decide whether the hike can continue.';
  }
}
