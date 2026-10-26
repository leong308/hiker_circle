part of '../gears_required_page_feature.dart';

/// An offline reference. Packing choices remain in hike preparation.
class GearsRequiredPage extends StatelessWidget {
  /// Creates gears required page.
  const GearsRequiredPage({super.key});

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sections = GearGuideCatalog.sections;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  child: Row(
                    children: [
                      PageHeaderAction(
                        tooltip: 'Back',
                        icon: CupertinoIcons.chevron_back,
                        onPressed: () => Navigator.of(context).pop(),
                        color: scheme.primary,
                        surface: scheme.surface,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Gears required',
                          style: PageHeaderStyle.title(
                            context,
                            scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    children: [
                      _GearGuideHero(
                        itemCount: TrailGearPlan.allItems.length,
                        categoryCount: sections.length,
                      ),
                      for (final section in sections.entries)
                        if (section.value.isNotEmpty)
                          _GearGuideSection(
                            category: section.key,
                            items: section.value,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the gear guide hero.
class _GearGuideHero extends StatelessWidget {
  /// Creates gear guide hero.
  const _GearGuideHero({required this.itemCount, required this.categoryCount});

  final int itemCount, categoryCount;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.4;
    final medallion = Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE9AD), Color(0xFFFFCC69)],
        ),
        border: Border.all(color: const Color(0xFFFFF2C9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .15),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.backpack_outlined,
        size: 32,
        color: Color(0xFF214D34),
      ),
    );
    final title = Text(
      'Pack with purpose',
      style: theme.textTheme.headlineSmall?.copyWith(
        color: Colors.white,
        fontSize: 25,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -.6,
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF249A51).withValues(alpha: .22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B3323), Color(0xFF1A6A40), Color(0xFF37A95C)],
              stops: [0, .55, 1],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -42,
                top: -54,
                child: _GearHeroOrb(color: Colors.white.withValues(alpha: .13)),
              ),
              Positioned(
                left: -72,
                bottom: -95,
                child: _GearHeroOrb(
                  color: const Color(0xFFFFD166).withValues(alpha: .16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR TRAIL PACK',
                      style: TextStyle(
                        color: Color(0xFFC8F3D6),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (largeText) ...[
                      medallion,
                      const SizedBox(height: 14),
                      title,
                    ] else
                      Row(
                        children: [
                          medallion,
                          const SizedBox(width: 16),
                          Expanded(child: title),
                        ],
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Know what to bring and why. Hike preparation selects '
                      'the items that suit your route, weather and schedule.',
                      style: TextStyle(
                        color: Color(0xFFD9F4E2),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _GearHeroLabel(
                          icon: Icons.backpack_outlined,
                          text: '$itemCount gear items',
                        ),
                        _GearHeroLabel(
                          icon: Icons.grid_view_rounded,
                          text: '$categoryCount categories',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the gear hero orb.
class _GearHeroOrb extends StatelessWidget {
  /// Creates gear hero orb.
  const _GearHeroOrb({required this.color});
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}
