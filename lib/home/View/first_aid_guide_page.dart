import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FirstAidGuidePage extends StatefulWidget {
  const FirstAidGuidePage({super.key});

  @override
  State<FirstAidGuidePage> createState() => _FirstAidGuidePageState();
}

class _FirstAidGuidePageState extends State<FirstAidGuidePage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<FirstAidTopic>> _topicsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _topicsFuture = _loadTopics();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<FirstAidTopic>> _loadTopics() async {
    try {
      final rawJson = await rootBundle.loadString(
        'assets/guides/first_aid_guide.json',
      );
      final data = jsonDecode(rawJson);
      final topics = data is Map<String, dynamic> ? data['topics'] : null;
      if (topics is List) {
        return topics
            .whereType<Map<String, dynamic>>()
            .map(FirstAidTopic.fromJson)
            .toList();
      }
    } catch (_) {
      return FirstAidTopic.defaults;
    }

    return FirstAidTopic.defaults;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GuideColors.background,
      body: SafeArea(
        child: FutureBuilder<List<FirstAidTopic>>(
          future: _topicsFuture,
          builder: (context, snapshot) {
            final topics = snapshot.data ?? FirstAidTopic.defaults;
            final visibleTopics = _query.isEmpty
                ? topics
                : topics.where((topic) {
                    return topic.title.toLowerCase().contains(_query) ||
                        topic.category.toLowerCase().contains(_query);
                  }).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(onBack: () => Navigator.of(context).pop()),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search emergency condition...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _EmergencyShortcut(
                        onPressed: () => Navigator.of(context).pop('sos'),
                      ),
                      const SizedBox(height: 18),
                      for (final topic in visibleTopics) ...[
                        _TopicCard(topic: topic),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FirstAidTopic {
  const FirstAidTopic({
    required this.id,
    required this.title,
    required this.category,
    required this.steps,
  });

  factory FirstAidTopic.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    return FirstAidTopic(
      id: _stringFrom(json['id']),
      title: _stringFrom(json['title']),
      category: _stringFrom(json['category']),
      steps: rawSteps is List
          ? rawSteps.whereType<String>().toList()
          : const [],
    );
  }

  final String id;
  final String title;
  final String category;
  final List<String> steps;

  static const List<FirstAidTopic> defaults = [
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

  static String _stringFrom(Object? value) {
    return value is String ? value : '';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'First-Aid Guide',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _GuideColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Offline Ready',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _GuideColors.green,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmergencyShortcut extends StatelessWidget {
  const _EmergencyShortcut({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _Glyph(icon: Icons.sos_rounded, color: _GuideColors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Emergency Shortcut',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _GuideColors.text,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open SOS'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});

  final FirstAidTopic topic;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        leading: const _Glyph(icon: Icons.medical_services_rounded),
        title: Text(
          topic.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _GuideColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        subtitle: Text(
          topic.category,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _GuideColors.secondaryText,
            letterSpacing: 0,
          ),
        ),
        children: [
          for (var index = 0; index < topic.steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _GuideColors.green,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topic.steps[index],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _GuideColors.text,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _GuideColors.green, size: 20),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, this.color = _GuideColors.green});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

abstract final class _GuideColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color red = Color(0xFFFF3B30);
}
