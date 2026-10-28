part of '../first_aid_guide_page_feature.dart';

/// Displays the first aid guide page.
class FirstAidGuidePage extends StatefulWidget {
  /// Creates first aid guide page.
  const FirstAidGuidePage({
    super.key,
    this.emergencyLatitude,
    this.emergencyLongitude,
    this.emergencyNumberResolver,
  });

  final double? emergencyLatitude;
  final double? emergencyLongitude;
  final EmergencyNumberResolver? emergencyNumberResolver;

  /// Creates the presentation state for this widget.
  @override
  State<FirstAidGuidePage> createState() => _FirstAidGuidePageState();
}

/// Manages the first aid guide page presentation and lifecycle.
class _FirstAidGuidePageState extends State<FirstAidGuidePage> {
  late final _FirstAidGuidePageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late Future<List<FirstAidTopic>> _topicsFuture;
  late Future<EmergencyDialTarget> _emergencyTargetFuture;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _FirstAidGuidePageStateViewModel(
      effectShowDialError: _showDialError,
    )..addListener(_renderScreenModel);

    _topicsFuture = _loadTopics();
    _emergencyTargetFuture = _resolveEmergencyTarget();
  }

  /// Delegates load topics to the ViewModel.
  Future<List<FirstAidTopic>> _loadTopics() => _screenModel.commandLoadTopics();

  /// Resolves emergency target.
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

  /// Delegates call emergency services to the ViewModel.
  Future<void> _callEmergencyServices(EmergencyDialTarget target) =>
      _screenModel.commandCallEmergencyServices(target);

  /// Shows dial error.
  void _showDialError(String number) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to open the dialer. Call $number.')),
    );
  }

  /// Checks whether there is valid coordinate.
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

  /// Builds this widget from its current presentation state.
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
                      SectionLabel(label: 'First choose a category'),
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the first aid category page.
class _FirstAidCategoryPage extends StatelessWidget {
  /// Creates first aid category page.
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

  /// Builds this widget from its current presentation state.
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
                  SectionLabel(label: 'What to do'),
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
                  SectionLabel(
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

/// Displays the category hero.
class _CategoryHero extends StatelessWidget {
  /// Creates category hero.
  const _CategoryHero({required this.category});

  final _FirstAidCategory category;

  /// Builds this widget from its current presentation state.
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

/// Displays the scenario response guide.
class _ScenarioResponseGuide extends StatelessWidget {
  /// Creates scenario response guide.
  const _ScenarioResponseGuide({
    required this.scenarios,
    required this.category,
  });

  final List<FirstAidScenario> scenarios;
  final _FirstAidCategory category;

  /// Opens scenario.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the scenario action sheet.
class _ScenarioActionSheet extends StatefulWidget {
  /// Creates scenario action sheet.
  const _ScenarioActionSheet({
    required this.scenario,
    required this.categoryTitle,
    required this.scrollController,
  });

  final FirstAidScenario scenario;
  final String categoryTitle;
  final ScrollController scrollController;

  /// Creates the presentation state for this widget.
  @override
  State<_ScenarioActionSheet> createState() => _ScenarioActionSheetState();
}

/// Manages the scenario action sheet presentation and lifecycle.
class _ScenarioActionSheetState extends State<_ScenarioActionSheet> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ScenarioActionSheetStateViewModel(
      readScenario: () => widget.scenario,
    )..addListener(_renderScreenModel);
  }

  late final _ScenarioActionSheetStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  int _selectedAction = 0;

  /// Delegates open reference to the ViewModel.
  Future<void> _openReference() => _screenModel.commandOpenReference();

  /// Computes move to.
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

  /// Builds this widget from its current presentation state.
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Computes scenario icon.
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

/// Computes scenario color.
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

/// Displays the emergency shortcut.
class _EmergencyShortcut extends StatelessWidget {
  /// Creates emergency shortcut.
  const _EmergencyShortcut({
    required this.target,
    required this.isLoading,
    required this.onPressed,
  });

  final EmergencyDialTarget? target;
  final bool isLoading;
  final VoidCallback? onPressed;

  /// Builds this widget from its current presentation state.
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

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon, this.color = _GuideColors.green});

  final IconData icon;
  final Color color;

  /// Builds this widget from its current presentation state.
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

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child, this.color, this.borderColor});

  final Widget child;
  final Color? color;
  final Color? borderColor;

  /// Builds this widget from its current presentation state.
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

/// Represents guide colors.
abstract final class _GuideColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color orange = Color(0xFFF59E0B);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color red = Color(0xFFFF3B30);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes cpr surface for.
  static Color cprSurfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF342224) : const Color(0xFFFFF0EB);

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes chevron for.
  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;
}

/// Provides UI styling for _FirstAidCategory.
extension _FirstAidCategoryPresentation on _FirstAidCategory {
  /// Returns icon.
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

  /// Returns color.
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
}
