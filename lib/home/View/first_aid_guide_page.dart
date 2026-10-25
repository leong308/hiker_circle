// FirstAidGuidePage organizes offline first-aid topics, scenarios and step-by-step instructions.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/emergency_number_service.dart';
import '../../sos/Data/location_snapshot_service.dart';

class FirstAidGuidePage extends StatefulWidget {
  const FirstAidGuidePage({
    super.key,
    this.emergencyLatitude,
    this.emergencyLongitude,
    this.emergencyNumberResolver,
  });

  final double? emergencyLatitude;
  final double? emergencyLongitude;
  final EmergencyNumberResolver? emergencyNumberResolver;

  @override
  State<FirstAidGuidePage> createState() => _FirstAidGuidePageState();
}

class _FirstAidGuidePageState extends State<FirstAidGuidePage> {
  late Future<List<FirstAidTopic>> _topicsFuture;
  late Future<EmergencyDialTarget> _emergencyTargetFuture;

  @override
  void initState() {
    super.initState();
    _topicsFuture = _loadTopics();
    _emergencyTargetFuture = _resolveEmergencyTarget();
  }

  Future<List<FirstAidTopic>> _loadTopics() async {
    try {
      final rawJson = await rootBundle.loadString(
        'assets/guides/first_aid_guide.json',
      );
      final data = jsonDecode(rawJson);
      final topics = data is Map<String, dynamic> ? data['topics'] : null;
      if (topics is List) {
        unawaited(_removeRetiredTutorialCache());
        return topics
            .whereType<Map<String, dynamic>>()
            .map(FirstAidTopic.fromJson)
            .toList();
      }
    } catch (_) {
      unawaited(_removeRetiredTutorialCache());
      return FirstAidTopic.defaults;
    }

    unawaited(_removeRetiredTutorialCache());
    return FirstAidTopic.defaults;
  }

  Future<void> _removeRetiredTutorialCache() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final separator = Platform.pathSeparator;
      final tutorialDirectory = Directory(
        '${supportDirectory.path}${separator}first_aid${separator}videos',
      );
      if (await tutorialDirectory.exists()) {
        await tutorialDirectory.delete(recursive: true);
      }
    } catch (_) {
      // Retired media cleanup must never prevent the offline guide from opening.
    }
  }

  Future<EmergencyDialTarget> _resolveEmergencyTarget() async {
    var latitude = widget.emergencyLatitude;
    var longitude = widget.emergencyLongitude;
    if (!_hasValidCoordinate(latitude, longitude)) {
      try {
        final location =
            LocationSnapshotService.instance.latestLocation ??
            await LocationSnapshotService.instance.refresh();
        latitude = location?.latitude;
        longitude = location?.longitude;
      } catch (_) {
        latitude = null;
        longitude = null;
      }
    }

    final localeCountryCode =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final resolver = widget.emergencyNumberResolver ?? EmergencyNumberService();
    return resolver.resolve(
      latitude: latitude,
      longitude: longitude,
      fallbackCountryCode: localeCountryCode,
    );
  }

  Future<void> _callEmergencyServices(EmergencyDialTarget target) async {
    try {
      final launched = await launchUrl(
        Uri(scheme: 'tel', path: target.number),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showDialError(target.number);
      }
    } catch (_) {
      if (mounted) _showDialError(target.number);
    }
  }

  void _showDialError(String number) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to open the dialer. Call $number.')),
    );
  }

  static bool _hasValidCoordinate(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GuideColors.backgroundFor(context),
      body: SafeArea(
        child: FutureBuilder<List<FirstAidTopic>>(
          future: _topicsFuture,
          builder: (context, snapshot) {
            final topics = snapshot.data ?? FirstAidTopic.defaults;
            final categories = _FirstAidCategory.fromTopics(topics);

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
                      FutureBuilder<EmergencyDialTarget>(
                        future: _emergencyTargetFuture,
                        builder: (context, emergencySnapshot) {
                          final target = emergencySnapshot.data;
                          return _EmergencyShortcut(
                            target: target,
                            isLoading:
                                emergencySnapshot.connectionState !=
                                    ConnectionState.done &&
                                target == null,
                            onPressed: target == null
                                ? null
                                : () => _callEmergencyServices(target),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      _SectionTitle(label: 'First choose a category'),
                      const SizedBox(height: 8),
                      for (final category in categories) ...[
                        _CategoryCard(
                          key: ValueKey('first-aid-category-${category.title}'),
                          category: category,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (detailContext) => _FirstAidCategoryPage(
                                category: category,
                                emergencyTargetFuture: _emergencyTargetFuture,
                                onCallEmergencyServices: _callEmergencyServices,
                                onOpenSos: () {
                                  Navigator.of(detailContext).pop();
                                  Navigator.of(context).pop('sos');
                                },
                              ),
                            ),
                          ),
                        ),
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
    this.scenarios = const [],
    this.guidanceSource = '',
    this.guidanceSourceUrl = '',
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

  static String _stringFrom(Object? value) {
    return value is String ? value : '';
  }
}

class FirstAidScenario {
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

  factory FirstAidScenario.fromJson(Map<String, dynamic> json) {
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

class _FirstAidCategory {
  const _FirstAidCategory({required this.title, required this.topics});

  final String title;
  final List<FirstAidTopic> topics;

  bool get isCpr => topics.any((topic) => topic.id == 'cpr');

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

  IconData get icon {
    if (isCpr) return Icons.monitor_heart_rounded;
    final lower = title.toLowerCase();
    if (lower.contains('bleeding')) {
      return Icons.bloodtype_rounded;
    }
    if (lower.contains('heat')) {
      return Icons.wb_sunny_rounded;
    }
    if (lower.contains('snake')) {
      return Icons.crisis_alert_rounded;
    }
    if (lower.contains('weather')) {
      return Icons.thunderstorm_rounded;
    }
    if (lower.contains('lost')) {
      return Icons.explore_rounded;
    }
    return Icons.health_and_safety_rounded;
  }

  Color get color {
    if (isCpr) return _GuideColors.red;
    final lower = title.toLowerCase();
    if (lower.contains('bleeding') || lower.contains('snake')) {
      return _GuideColors.red;
    }
    if (lower.contains('heat') || lower.contains('weather')) {
      return _GuideColors.orange;
    }
    return _GuideColors.green;
  }

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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => PageHeader(
    title: 'First-Aid Guide',
    subtitle: 'Scenario-based emergency guidance',
    onBack: onBack,
  );
}

class _FirstAidCategoryPage extends StatelessWidget {
  const _FirstAidCategoryPage({
    required this.category,
    required this.onOpenSos,
    required this.emergencyTargetFuture,
    required this.onCallEmergencyServices,
  });

  final _FirstAidCategory category;
  final VoidCallback onOpenSos;
  final Future<EmergencyDialTarget> emergencyTargetFuture;
  final Future<void> Function(EmergencyDialTarget) onCallEmergencyServices;

  @override
  Widget build(BuildContext context) {
    final allSteps = category.topics.expand((topic) => topic.steps).toList();
    final scenarios = category.topics
        .expand((topic) => topic.scenarios)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: _GuideColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: category.title,
                    subtitle: 'Detailed response guide',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _CategoryHero(category: category),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'What to do'),
                  const SizedBox(height: 8),
                  if (scenarios.isNotEmpty)
                    _ScenarioResponseGuide(
                      scenarios: scenarios,
                      category: category,
                    )
                  else ...[
                    _InsetGroup(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < allSteps.length;
                              index++
                            )
                              _StepRow(index: index, step: allSteps[index]),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (scenarios.isEmpty || category.isCpr)
                    _GuidanceSourceCard(topic: category.topics.first),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    label: category.isCpr
                        ? 'Get emergency help now'
                        : 'When to use SOS',
                  ),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Glyph(
                            icon: Icons.sos_rounded,
                            color: _GuideColors.red,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.isCpr
                                      ? 'Call emergency services'
                                      : 'Escalate when safety is uncertain',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: _GuideColors.textFor(context),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  category.isCpr
                                      ? 'Use speakerphone and follow the dispatcher. Ask a helper to use HikerCircle SOS; do not pause CPR to use the app.'
                                      : 'Use SOS if the person cannot move safely, symptoms worsen, or the group cannot return without help.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: _GuideColors.secondaryTextFor(
                                          context,
                                        ),
                                        letterSpacing: 0,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (category.isCpr)
                            FutureBuilder<EmergencyDialTarget>(
                              future: emergencyTargetFuture,
                              builder: (context, snapshot) => FilledButton(
                                onPressed: snapshot.data == null
                                    ? null
                                    : () => unawaited(
                                        onCallEmergencyServices(snapshot.data!),
                                      ),
                                child: Text(
                                  snapshot.data == null
                                      ? 'Call'
                                      : 'Call ${snapshot.data!.number}',
                                ),
                              ),
                            )
                          else
                            FilledButton(
                              onPressed: onOpenSos,
                              child: const Text('Open SOS'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({super.key, required this.category, required this.onTap});

  final _FirstAidCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      color: category.isCpr ? _GuideColors.cprSurfaceFor(context) : null,
      borderColor: category.isCpr
          ? _GuideColors.red.withValues(alpha: 0.22)
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _Glyph(icon: category.icon, color: category.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _GuideColors.textFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        category.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _GuideColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_forward,
                  color: _GuideColors.chevronFor(context),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryHero extends StatelessWidget {
  const _CategoryHero({required this.category});

  final _FirstAidCategory category;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Glyph(icon: category.icon, color: category.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.summary,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _GuideColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final topic in category.topics)
                  _InfoPill(label: topic.title, color: category.color),
              ],
            ),
            if (category.isCpr) ...[
              const SizedBox(height: 12),
              Text(
                'Adult guidance. For a child, infant or drowning, tell the emergency dispatcher and follow their instructions. Practical CPR training is recommended.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _GuideColors.secondaryTextFor(context),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScenarioResponseGuide extends StatelessWidget {
  const _ScenarioResponseGuide({
    required this.scenarios,
    required this.category,
  });

  final List<FirstAidScenario> scenarios;
  final _FirstAidCategory category;

  Future<void> _openScenario(
    BuildContext context,
    FirstAidScenario scenario,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.62,
        maxChildSize: 0.96,
        snap: true,
        snapSizes: const [0.62, 0.88, 0.96],
        builder: (context, scrollController) => _ScenarioActionSheet(
          scenario: scenario,
          categoryTitle: category.title,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (scenarios.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('first-aid-scenario-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < scenarios.length; index++) ...[
                _ScenarioLaunchTile(
                  scenario: scenarios[index],
                  onTap: () => _openScenario(context, scenarios[index]),
                ),
                if (index != scenarios.length - 1)
                  Divider(
                    height: 1,
                    indent: 64,
                    color: _GuideColors.chevronFor(
                      context,
                    ).withValues(alpha: 0.3),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ScenarioLaunchTile extends StatelessWidget {
  const _ScenarioLaunchTile({required this.scenario, required this.onTap});

  final FirstAidScenario scenario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _scenarioColor(scenario.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('first-aid-scenario-${scenario.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _scenarioIcon(scenario.id),
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scenario.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _GuideColors.textFor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scenario.urgency,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Tap to view steps',
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.touch_app_rounded, color: accent, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioActionSheet extends StatefulWidget {
  const _ScenarioActionSheet({
    required this.scenario,
    required this.categoryTitle,
    required this.scrollController,
  });

  final FirstAidScenario scenario;
  final String categoryTitle;
  final ScrollController scrollController;

  @override
  State<_ScenarioActionSheet> createState() => _ScenarioActionSheetState();
}

class _ScenarioActionSheetState extends State<_ScenarioActionSheet> {
  int _selectedAction = 0;

  Future<void> _openReference() async {
    final uri = Uri.tryParse(widget.scenario.referenceUrl);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _moveTo(int index) {
    if (index < 0 || index >= widget.scenario.steps.length) return;
    setState(() => _selectedAction = index);
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenario = widget.scenario;
    final accent = _scenarioColor(scenario.id);
    final isLast = _selectedAction == scenario.steps.length - 1;
    return Container(
      key: ValueKey('first-aid-scenario-sheet-${scenario.id}'),
      decoration: BoxDecoration(
        color: _GuideColors.backgroundFor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _GuideColors.chevronFor(
                      context,
                    ).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _scenarioIcon(scenario.id),
                        color: accent,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.categoryTitle.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          Text(
                            scenario.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _GuideColors.textFor(context),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('first-aid-scenario-close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: _GuideColors.chevronFor(context).withValues(alpha: 0.3),
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                Text(
                  scenario.summary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _GuideColors.secondaryTextFor(context),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, color: accent, size: 20),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          scenario.urgency,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'ACTION ${_selectedAction + 1} OF ${scenario.steps.length}',
                      key: const ValueKey('first-aid-action-count'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _GuideColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (_selectedAction + 1) / scenario.steps.length,
                          minHeight: 6,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Container(
                    key: ValueKey('${scenario.id}-action-$_selectedAction'),
                    constraints: const BoxConstraints(minHeight: 150),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _GuideColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.26)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_selectedAction + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Text(
                          scenario.steps[_selectedAction],
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: _GuideColors.textFor(context),
                                height: 1.48,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('first-aid-action-previous'),
                        onPressed: _selectedAction == 0
                            ? null
                            : () => _moveTo(_selectedAction - 1),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('first-aid-action-next'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: isLast
                            ? () => Navigator.of(context).pop()
                            : () => _moveTo(_selectedAction + 1),
                        icon: Icon(
                          isLast
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                        label: Text(isLast ? 'Done' : 'Next action'),
                      ),
                    ),
                  ],
                ),
                if (scenario.avoid.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'AVOID',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _GuideColors.red,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _GuideColors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _GuideColors.red.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < scenario.avoid.length;
                          index++
                        )
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: index == scenario.avoid.length - 1
                                  ? 0
                                  : 9,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.block_rounded,
                                  color: _GuideColors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    scenario.avoid[index],
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: _GuideColors.textFor(context),
                                          height: 1.4,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('first-aid-reference-${scenario.id}'),
                    onTap: _openReference,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _GuideColors.chevronFor(
                            context,
                          ).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: _GuideColors.green,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Medical reference',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: _GuideColors.textFor(context),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                Text(
                                  scenario.referenceName,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: _GuideColors.secondaryTextFor(
                                          context,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.open_in_new_rounded,
                            color: _GuideColors.chevronFor(context),
                            size: 18,
                          ),
                        ],
                      ),
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

IconData _scenarioIcon(String id) => switch (id) {
  'cpr_adult_collapse' || 'cpr_rescue_breaths' => Icons.monitor_heart_rounded,
  'cpr_aed' => Icons.bolt_rounded,
  'cpr_breathing_normally' => Icons.air_rounded,
  'life_threatening_external' ||
  'major_fall_multiple_injuries' ||
  'heat_stroke' ||
  'snake_bite_unconscious' => Icons.emergency_rounded,
  'embedded_object' => Icons.push_pin_rounded,
  'nosebleed' => Icons.face_rounded,
  'minor_cut_graze' ||
  'minor_fall_bruise' ||
  'mild_ankle_sprain' => Icons.healing_rounded,
  'suspected_internal' || 'heat_syncope' => Icons.monitor_heart_rounded,
  'suspected_fracture' ||
  'severe_ankle_injury' ||
  'ankle_deformity_open_wound' => Icons.personal_injury_rounded,
  'head_injury' || 'snake_bite_neuro_signs' => Icons.psychology_alt_rounded,
  'suspected_spinal_injury' => Icons.accessibility_new_rounded,
  'joint_dislocation' => Icons.sync_problem_rounded,
  'ankle_circulation_problem' => Icons.device_thermostat_rounded,
  'heat_cramps' => Icons.fitness_center_rounded,
  'heat_exhaustion_symptoms' => Icons.thermostat_rounded,
  'heat_rhabdomyolysis' => Icons.water_drop_rounded,
  'snake_bite_no_symptoms' ||
  'snake_bite_swelling' => Icons.crisis_alert_rounded,
  'lost_recently_off_route' => Icons.route_rounded,
  'lost_no_signal_low_battery' => Icons.signal_cellular_off_rounded,
  'lost_after_dark' => Icons.dark_mode_rounded,
  'lost_injured_immobile' => Icons.sos_rounded,
  'group_member_missing' => Icons.person_search_rounded,
  'weather_lightning' => Icons.thunderstorm_rounded,
  'weather_flash_flood' => Icons.flood_rounded,
  'weather_strong_wind' => Icons.air_rounded,
  'weather_cold_wet' => Icons.ac_unit_rounded,
  'weather_poor_visibility' => Icons.visibility_off_rounded,
  'weather_landslide' => Icons.landslide_rounded,
  _ => Icons.bloodtype_rounded,
};

Color _scenarioColor(String id) => switch (id) {
  'cpr_adult_collapse' || 'cpr_rescue_breaths' || 'cpr_aed' => _GuideColors.red,
  'cpr_breathing_normally' => const Color(0xFF5478C8),
  'life_threatening_external' ||
  'suspected_internal' ||
  'suspected_spinal_injury' ||
  'major_fall_multiple_injuries' ||
  'ankle_deformity_open_wound' ||
  'ankle_circulation_problem' ||
  'heat_stroke' ||
  'heat_rhabdomyolysis' ||
  'snake_bite_neuro_signs' ||
  'snake_bite_unconscious' ||
  'lost_injured_immobile' ||
  'group_member_missing' ||
  'weather_flash_flood' ||
  'weather_landslide' => _GuideColors.red,
  'embedded_object' ||
  'suspected_fracture' ||
  'joint_dislocation' ||
  'severe_ankle_injury' ||
  'heat_cramps' ||
  'heat_exhaustion_symptoms' ||
  'heat_syncope' ||
  'snake_bite_no_symptoms' ||
  'snake_bite_swelling' ||
  'weather_lightning' ||
  'weather_strong_wind' => _GuideColors.orange,
  'nosebleed' ||
  'head_injury' ||
  'lost_no_signal_low_battery' ||
  'lost_after_dark' ||
  'weather_cold_wet' ||
  'weather_poor_visibility' => const Color(0xFF5478C8),
  _ => _GuideColors.green,
};

class _GuidanceSourceCard extends StatelessWidget {
  const _GuidanceSourceCard({required this.topic});

  final FirstAidTopic topic;

  Future<void> _openSource() async {
    final uri = Uri.tryParse(topic.guidanceSourceUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (topic.guidanceSource.isEmpty || topic.guidanceSourceUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSource,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: _GuideColors.green,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Medical guidance source',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _GuideColors.textFor(context),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        topic.guidanceSource,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _GuideColors.secondaryTextFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  color: _GuideColors.secondaryTextFor(context),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step});

  final int index;
  final String step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _GuideColors.greenSoftFor(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _GuideColors.green,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _GuideColors.textFor(context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

class _EmergencyShortcut extends StatelessWidget {
  const _EmergencyShortcut({
    required this.target,
    required this.isLoading,
    required this.onPressed,
  });

  final EmergencyDialTarget? target;
  final bool isLoading;
  final VoidCallback? onPressed;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Call emergency services',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _GuideColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  Text(
                    isLoading
                        ? 'Finding the emergency number for this region...'
                        : '${target?.description ?? 'Local emergency service'} • ${target?.number ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _GuideColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(target == null ? 'Call' : target!.number),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _GuideColors.secondaryTextFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
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
  const _InsetGroup({required this.child, this.color, this.borderColor});

  final Widget child;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? _GuideColors.surfaceFor(context),
          border: borderColor == null ? null : Border.all(color: borderColor!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

abstract final class _GuideColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color orange = Color(0xFFF59E0B);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color red = Color(0xFFFF3B30);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color cprSurfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF342224) : const Color(0xFFFFF0EB);

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;
}
