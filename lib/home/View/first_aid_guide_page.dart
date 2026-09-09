import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/emergency_number_service.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../Model/first_aid_video.dart';
import 'first_aid_tutorial_video.dart';

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
  final TextEditingController _searchController = TextEditingController();
  late Future<List<FirstAidTopic>> _topicsFuture;
  late Future<EmergencyDialTarget> _emergencyTargetFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _topicsFuture = _loadTopics();
    _emergencyTargetFuture = _resolveEmergencyTarget();
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
            final categories = _FirstAidCategory.fromTopics(topics).where((
              category,
            ) {
              if (_query.isEmpty) {
                return true;
              }
              return category.title.toLowerCase().contains(_query) ||
                  category.topics.any(
                    (topic) => topic.title.toLowerCase().contains(_query),
                  );
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
                          hintText: 'Search first-aid category...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
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
                      if (categories.isEmpty)
                        const _EmptyState(
                          message: 'No first-aid categories match this search.',
                        )
                      else
                        for (final category in categories) ...[
                          _CategoryCard(
                            category: category,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (detailContext) =>
                                    _FirstAidCategoryPage(
                                      category: category,
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
    this.guidanceSource = '',
    this.guidanceSourceUrl = '',
    this.video,
    this.videoUnavailableReason = '',
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
      guidanceSource: _stringFrom(json['guidanceSource']),
      guidanceSourceUrl: _stringFrom(json['guidanceSourceUrl']),
      videoUnavailableReason: _stringFrom(json['videoUnavailableReason']),
      video: json['video'] is Map<String, dynamic>
          ? FirstAidVideo.fromJson(json['video'] as Map<String, dynamic>)
          : null,
    );
  }

  final String id;
  final String title;
  final String category;
  final List<String> steps;
  final String guidanceSource;
  final String guidanceSourceUrl;
  final FirstAidVideo? video;
  final String videoUnavailableReason;

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

class _FirstAidCategory {
  const _FirstAidCategory({required this.title, required this.topics});

  final String title;
  final List<FirstAidTopic> topics;

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
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  IconData get icon {
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
                  color: _GuideColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Categories, steps, and tutorial media',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _GuideColors.secondaryTextFor(context),
                  fontWeight: FontWeight.w600,
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

class _FirstAidCategoryPage extends StatelessWidget {
  const _FirstAidCategoryPage({
    required this.category,
    required this.onOpenSos,
  });

  final _FirstAidCategory category;
  final VoidCallback onOpenSos;

  @override
  Widget build(BuildContext context) {
    final allSteps = category.topics.expand((topic) => topic.steps).toList();

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
                  _SectionTitle(label: 'KKM video reference'),
                  const SizedBox(height: 8),
                  _TutorialMediaStrip(category: category),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'What to do'),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                      child: Column(
                        children: [
                          for (var index = 0; index < allSteps.length; index++)
                            _StepRow(index: index, step: allSteps[index]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _GuidanceSourceCard(topic: category.topics.first),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'When to use SOS'),
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
                                  'Escalate when safety is uncertain',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: _GuideColors.textFor(context),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Use SOS if the person cannot move safely, symptoms worsen, or the group cannot return without help.',
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
  const _CategoryCard({required this.category, required this.onTap});

  final _FirstAidCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
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
          ],
        ),
      ),
    );
  }
}

class _TutorialMediaStrip extends StatelessWidget {
  const _TutorialMediaStrip({required this.category});

  final _FirstAidCategory category;

  @override
  Widget build(BuildContext context) {
    final topic = category.topics.first;
    final video = topic.video;
    if (video == null) {
      return _EmptyState(
        message: topic.videoUnavailableReason.isNotEmpty
            ? topic.videoUnavailableReason
            : 'No verified KKM video is available for this category. Use the written guidance below.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (video.scopeNote.isNotEmpty) ...[
          Text(video.scopeNote, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
        ],
        FirstAidTutorialVideoCard(
          topicId: topic.id,
          video: video,
          color: category.color,
        ),
        if (video.licenseUrl.isNotEmpty)
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(video.licenseUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text('${video.language} · KKM reuse permission'),
          ),
      ],
    );
  }
}

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
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _GuideColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _GuideColors.secondaryTextFor(context),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _GuideColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
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

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _GuideColors.surfaceFor(context),
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
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _GuideColors.surfaceFor(context),
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

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;
}
