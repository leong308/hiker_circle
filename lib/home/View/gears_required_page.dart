import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/page_header_style.dart';
import '../Model/gear_guide_catalog.dart';
import '../Model/trail_gear_plan.dart';

/// An offline reference. Packing choices remain in hike preparation.
class GearsRequiredPage extends StatelessWidget {
  const GearsRequiredPage({super.key});

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

class _GearGuideHero extends StatelessWidget {
  const _GearGuideHero({required this.itemCount, required this.categoryCount});

  final int itemCount, categoryCount;

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

class _GearHeroOrb extends StatelessWidget {
  const _GearHeroOrb({required this.color});
  final Color color;

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

class _GearHeroLabel extends StatelessWidget {
  const _GearHeroLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF06170E).withValues(alpha: .22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFFFFE297)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _GearGuideSection extends StatelessWidget {
  const _GearGuideSection({required this.category, required this.items});
  final GearGuideCategory category;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final (title, subtitle) = switch (category) {
      GearGuideCategory.waterAndFood => (
        'Water & food',
        'Hydration, energy and a little extra for delays.',
      ),
      GearGuideCategory.safety => (
        'Safety essentials',
        'Light, first aid and ways to signal for help.',
      ),
      GearGuideCategory.weather => (
        'Weather & clothing',
        'Stay comfortable when conditions change.',
      ),
      GearGuideCategory.footing => (
        'Footwear & support',
        'Grip and balance for more demanding ground.',
      ),
      GearGuideCategory.navigation => (
        'Navigation & power',
        'Keep your bearings and essential devices ready.',
      ),
      GearGuideCategory.camping => (
        'Overnight & camp',
        'Shelter and supplies for a longer stay.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 330 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.4
                  ? 2
                  : 1;
              return Column(
                children: [
                  for (var index = 0; index < items.length; index += columns)
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var offset = 0;
                              offset < columns;
                              offset++
                            ) ...[
                              if (offset > 0) const SizedBox(width: 10),
                              Expanded(
                                child: index + offset < items.length
                                    ? _GearItemCard(
                                        item: items[index + offset],
                                        category: category,
                                        horizontal: columns == 1,
                                      )
                                    : const SizedBox(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GearItemCard extends StatelessWidget {
  const _GearItemCard({
    required this.item,
    required this.category,
    required this.horizontal,
  });
  final String item;
  final GearGuideCategory category;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = switch (category) {
      GearGuideCategory.waterAndFood =>
        dark ? const Color(0xFF8BC9EA) : const Color(0xFF28749D),
      GearGuideCategory.safety =>
        dark ? const Color(0xFFF0B9A0) : const Color(0xFFAE6140),
      GearGuideCategory.weather =>
        dark ? const Color(0xFF9DD4C9) : const Color(0xFF387F72),
      GearGuideCategory.footing =>
        dark ? const Color(0xFFBCD0A1) : const Color(0xFF5F7E3B),
      GearGuideCategory.navigation =>
        dark ? const Color(0xFFE3CA85) : const Color(0xFF94721F),
      GearGuideCategory.camping =>
        dark ? const Color(0xFFC6BCE5) : const Color(0xFF7C639F),
    };
    final icon = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? .16 : .09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .13)),
      ),
      child: Icon(_gearIcon(item), color: accent, size: 21),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w700,
            letterSpacing: -.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          GearGuideCatalog.reasonFor(item),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            Color.alphaBlend(
              accent.withValues(alpha: dark ? .07 : .025),
              scheme.surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Color.alphaBlend(
            accent.withValues(alpha: .12),
            scheme.outlineVariant.withValues(alpha: .4),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .08 : .025),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: horizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: text),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [icon, const SizedBox(height: 12), text],
            ),
    );
  }

  static IconData _gearIcon(String item) => switch (item) {
    'Drinking water' || 'Extra drinking water' => Icons.water_drop_outlined,
    'Energy snack' ||
    'Extra food for delays' ||
    'Meals for each day + reserve' => Icons.restaurant_outlined,
    'Water filter or tablets' => Icons.filter_alt_outlined,
    'First-aid kit' || 'Blister care' => Icons.medical_services_outlined,
    'Emergency whistle' => Icons.campaign_outlined,
    'Headlamp with spare batteries' => Icons.flashlight_on_outlined,
    'Emergency blanket' ||
    'Sleeping bag and sleeping mat' => Icons.layers_outlined,
    'Raincoat' || 'Pack rain cover' => Icons.umbrella_outlined,
    'Sun protection (hat, sunscreen)' => Icons.wb_sunny_outlined,
    'Dry bag / waterproof phone pouch' => Icons.phonelink_lock_outlined,
    'Spare dry socks' || 'Warm clothing layer' => Icons.checkroom_outlined,
    'Grippy hiking footwear' ||
    'Secure water-crossing footwear' ||
    'Trekking poles' => Icons.hiking_rounded,
    'Power bank' => Icons.battery_charging_full_rounded,
    'Physical map' => Icons.map_outlined,
    'Compass' => Icons.explore_outlined,
    'Satellite communicator if no signal' => Icons.satellite_alt_outlined,
    'Multi-tool' => Icons.build_outlined,
    'Tent or suitable shelter' => Icons.festival_outlined,
    'Stove and fuel where permitted' => Icons.local_fire_department_outlined,
    'Camp permit / booking' => Icons.confirmation_number_outlined,
    'Waste bags' => Icons.delete_outline_rounded,
    _ => Icons.backpack_outlined,
  };
}
