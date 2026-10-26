part of '../../first_aid_guide_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({required this.onBack});

  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PageHeader(
    title: 'First-Aid Guide',
    subtitle: 'Scenario-based emergency guidance',
    onBack: onBack,
  );
}

/// Displays the category card.
class _CategoryCard extends StatelessWidget {
  /// Creates category card.
  const _CategoryCard({super.key, required this.category, required this.onTap});

  final _FirstAidCategory category;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
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

/// Displays the scenario launch tile.
class _ScenarioLaunchTile extends StatelessWidget {
  /// Creates scenario launch tile.
  const _ScenarioLaunchTile({required this.scenario, required this.onTap});

  final FirstAidScenario scenario;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
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

/// Displays the guidance source card.
class _GuidanceSourceCard extends StatelessWidget {
  /// Creates guidance source card.
  const _GuidanceSourceCard({required this.topic});

  final FirstAidTopic topic;

  /// Opens source.
  Future<void> _openSource() async {
    final uri = Uri.tryParse(topic.guidanceSourceUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Builds this widget from its current presentation state.
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

/// Displays the step row.
class _StepRow extends StatelessWidget {
  /// Creates step row.
  const _StepRow({required this.index, required this.step});

  final int index;
  final String step;

  /// Builds this widget from its current presentation state.
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

/// Displays the detail header.
class _DetailHeader extends StatelessWidget {
  /// Creates detail header.
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

/// Displays the info pill.
class _InfoPill extends StatelessWidget {
  /// Creates info pill.
  const _InfoPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// Builds this widget from its current presentation state.
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
