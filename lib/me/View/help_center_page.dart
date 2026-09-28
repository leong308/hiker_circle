import '../../core/widgets/static_hazard_marker.dart';
import '../../core/widgets/community_hazard_marker.dart';
import '../../trail/Model/trail_hazard_categories.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/page_header_style.dart';
import '../../feedback/feedback_page.dart';
import '../../home/View/first_aid_guide_page.dart';
import '../Model/help_center_content.dart';

class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key, this.isAdmin = false});
  final bool isAdmin;

  @override
  Widget build(BuildContext context) => _HelpScaffold(
    title: 'Help Center',
    subtitle: 'A little guidance for every hike',
    children: [
      _HelpCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.explore_rounded, color: _green, size: 32),
              const SizedBox(height: 12),
              Text(
                'Start with the trail',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Understand the conditions, know what to do, and prepare with confidence.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _open(context, const HikeBasicsPage()),
                icon: const Icon(Icons.terrain_rounded),
                label: const Text('Explore Hike Basics'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      const _HelpLabel('YOUR GUIDES'),
      _GuideLink(
        icon: Icons.route_rounded,
        title: 'Plan & track a hike',
        subtitle: 'Trails, preparation, maps and history',
        onTap: () => _open(context, const _PlanTrackHelpPage()),
      ),
      _GuideLink(
        icon: Icons.groups_2_rounded,
        title: 'Team hike basics',
        subtitle: 'Joining, readiness and staying together',
        onTap: () => _open(
          context,
          const _HelpArticlePage(
            title: 'Team hike basics',
            subtitle: 'Prepare and move as a group',
            articles: teamHelp,
          ),
        ),
      ),
      _GuideLink(
        icon: Icons.sos_rounded,
        title: 'Using SOS safely',
        subtitle: 'Contacts, alerts and emergency help',
        onTap: () => _open(
          context,
          const _HelpArticlePage(
            title: 'Using SOS safely',
            subtitle: 'Know your options before you need them',
            articles: sosHelp,
          ),
        ),
      ),
      _GuideLink(
        icon: Icons.medical_services_outlined,
        title: 'First-aid guide',
        subtitle: 'Open the app’s first-aid guidance',
        onTap: () => _open(context, const FirstAidGuidePage()),
      ),
      _GuideLink(
        icon: Icons.manage_accounts_outlined,
        title: 'Account & troubleshooting',
        subtitle: 'Login, permissions and common problems',
        onTap: () => _open(
          context,
          _HelpArticlePage(
            title: 'Account & support',
            subtitle: 'Get back to your hike',
            articles: accountHelp,
            isAdmin: isAdmin,
          ),
        ),
      ),
      const SizedBox(height: 12),
      const _HelpLabel('NEED A HAND?'),
      _GuideLink(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Report a problem',
        subtitle: 'Send feedback or suggest an improvement',
        onTap: () => _open(context, FeedbackPage(isAdmin: isAdmin)),
      ),
    ],
  );
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class HikeBasicsPage extends StatefulWidget {
  const HikeBasicsPage({super.key});
  @override
  State<HikeBasicsPage> createState() => _HikeBasicsPageState();
}

class _HikeBasicsPageState extends State<HikeBasicsPage> {
  String _category = 'All';
  Future<void> _chooseCategory() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: _surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              Text(
                'Choose a category',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              for (final category in [
                'All',
                ...trailConditionGuides.map((entry) => entry.category).toSet(),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    key: ValueKey('category-$category'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    selected: category == _category,
                    selectedColor: _green,
                    selectedTileColor: _green.withValues(alpha: 0.10),
                    title: Text(
                      category == 'All' ? 'All conditions' : category,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${trailConditionGuides.where((entry) => category == 'All' || entry.category == category).length} conditions',
                    ),
                    trailing: category == _category
                        ? const Icon(Icons.check_circle_rounded, color: _green)
                        : const Icon(Icons.circle_outlined, size: 22),
                    onTap: () => Navigator.of(context).pop(category),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _category = selected);
  }

  @override
  Widget build(BuildContext context) {
    final entries = trailConditionGuides
        .where((entry) => (_category == 'All' || entry.category == _category))
        .toList();
    return _HelpScaffold(
      title: 'Hike Basics',
      subtitle: 'Know the conditions. Know your next step.',
      children: [
        const _HelpCard(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Map cautions and hiker reports help you plan. They do not confirm current conditions. Follow local signs and closures; turn back when unsure.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        _HelpCard(
          child: ListTile(
            key: const ValueKey('condition-category-selector'),
            onTap: _chooseCategory,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 6,
            ),
            leading: const _GuideIcon(Icons.tune_rounded),
            title: const Text(
              'Browse by category',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              _category == 'All' ? 'All conditions' : _category,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            trailing: const Icon(Icons.expand_more_rounded, color: _green),
          ),
        ),
        const SizedBox(height: 18),
        _HelpLabel(
          '${entries.length} ${entries.length == 1 ? 'CONDITION' : 'CONDITIONS'}',
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HelpCard(
              child: ExpansionTile(
                key: PageStorageKey(entry.title),
                leading: _conditionMarker(entry),
                title: Text(
                  entry.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(entry.category),
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  _Explanation(label: 'What it means', text: entry.meaning),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _Explanation(
                      label: 'What to do',
                      text: entry.action,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const _HelpLabel('FURTHER READING'),
        const Text(
          'General outdoor safety guidance from national park and conservation services.',
        ),
        _SourceLink(
          title: 'Hiking safety · National Park Service',
          url: 'https://www.nps.gov/grsm/planyourvisit/hikingsafety.htm',
        ),
        _SourceLink(
          title: 'River safety · Department of Conservation',
          url:
              'https://www.doc.govt.nz/parks-and-recreation/know-before-you-go/river-crossing-safety/',
        ),
        _SourceLink(
          title: 'Lightning safety · National Park Service',
          url: 'https://www.nps.gov/romo/planyourvisit/lightning-safety.htm',
        ),
      ],
    );
  }
}

class _HelpArticlePage extends StatelessWidget {
  const _HelpArticlePage({
    required this.title,
    required this.subtitle,
    required this.articles,
    this.isAdmin,
  });
  final String title, subtitle;
  final List<HelpArticle> articles;
  final bool? isAdmin;
  @override
  Widget build(BuildContext context) => _HelpScaffold(
    title: title,
    subtitle: subtitle,
    children: [
      for (var i = 0; i < articles.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _HelpCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _green.withValues(alpha: 0.12),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Explanation(
                      label: articles[i].title,
                      text: articles[i].text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (isAdmin != null)
        FilledButton.icon(
          onPressed: () => _open(context, FeedbackPage(isAdmin: isAdmin!)),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Open Feedback'),
        ),
    ],
  );
}

enum _PlanPhase { before, during, after }

extension on _PlanPhase {
  String get label => switch (this) {
    _PlanPhase.before => 'Before hike',
    _PlanPhase.during => 'On trail',
    _PlanPhase.after => 'After hike',
  };
}

class _PlanStepMeta {
  const _PlanStepMeta({
    required this.icon,
    required this.eyebrow,
    required this.phases,
  });

  final IconData icon;
  final String eyebrow;
  final Set<_PlanPhase> phases;
}

const _planStepMeta = <_PlanStepMeta>[
  _PlanStepMeta(
    icon: Icons.explore_rounded,
    eyebrow: 'Choose with confidence',
    phases: {_PlanPhase.before},
  ),
  _PlanStepMeta(
    icon: Icons.map_rounded,
    eyebrow: 'Know the route',
    phases: {_PlanPhase.before},
  ),
  _PlanStepMeta(
    icon: Icons.cloud_rounded,
    eyebrow: 'Check the full window',
    phases: {_PlanPhase.before},
  ),
  _PlanStepMeta(
    icon: Icons.backpack_rounded,
    eyebrow: 'Prepare for the conditions',
    phases: {_PlanPhase.before},
  ),
  _PlanStepMeta(
    icon: Icons.navigation_rounded,
    eyebrow: 'Stay aware as you move',
    phases: {_PlanPhase.during},
  ),
  _PlanStepMeta(
    icon: Icons.flag_rounded,
    eyebrow: 'Close the loop',
    phases: {_PlanPhase.after},
  ),
  _PlanStepMeta(
    icon: Icons.signal_cellular_connected_no_internet_4_bar_rounded,
    eyebrow: 'Plan beyond coverage',
    phases: {_PlanPhase.before, _PlanPhase.during},
  ),
];

class _PlanTrackHelpPage extends StatefulWidget {
  const _PlanTrackHelpPage();

  @override
  State<_PlanTrackHelpPage> createState() => _PlanTrackHelpPageState();
}

class _PlanTrackHelpPageState extends State<_PlanTrackHelpPage> {
  Future<void> _openGuide() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _PlanGuideOverlay(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    return _HelpScaffold(
      title: 'Plan & track',
      subtitle: 'From choosing a trail to getting home',
      children: [
        _PlanJourneyHero(onStart: _openGuide),
        const SizedBox(height: 22),
        Text(
          'At a glance',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: text,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'The guide follows the same flow as a real hike.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: secondary),
        ),
        const SizedBox(height: 12),
        const _PlanOverviewRow(
          icon: Icons.backpack_rounded,
          title: 'Before the hike',
          detail: 'Choose, understand, check and prepare',
          count: '4 steps',
        ),
        const SizedBox(height: 9),
        const _PlanOverviewRow(
          icon: Icons.navigation_rounded,
          title: 'On the trail',
          detail: 'Track progress and handle weak signal',
          count: '2 topics',
        ),
        const SizedBox(height: 9),
        const _PlanOverviewRow(
          icon: Icons.flag_rounded,
          title: 'After the hike',
          detail: 'Finish safely and review your record',
          count: '1 step',
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: dark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _green.withValues(alpha: 0.28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: _green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conditions can change quickly',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Follow closures and local instructions, keep a backup plan, and turn back when the route exceeds your ability.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanJourneyHero extends StatelessWidget {
  const _PlanJourneyHero({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E7D42), Color(0xFF0B3E26)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF146B39).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'PLAN → TRACK → REVIEW',
                        style: TextStyle(
                          color: Color(0xFFB8EDC9),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your hike in 7 clear steps',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Swipe through practical guidance from choosing a trail to getting home.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        height: 1.42,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox.square(
                dimension: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 64,
                      child: CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 6,
                        color: const Color(0xFF8CE7A8),
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '7',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'STEPS',
                          style: TextStyle(
                            color: Color(0xFFB8EDC9),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('plan-guide-start'),
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF145C34),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start guide'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanOverviewRow extends StatelessWidget {
  const _PlanOverviewRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.count,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String count;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: _green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: text, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(color: secondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count,
            style: const TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanJourneyStop extends StatelessWidget {
  const _PlanJourneyStop({
    super.key,
    required this.number,
    required this.icon,
    required this.title,
    required this.reviewed,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final IconData icon;
  final String title;
  final bool reviewed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final border = dark ? const Color(0xFF2B3A31) : const Color(0xFFD9E1DC);
    return SizedBox(
      width: 104,
      child: Material(
        color: selected
            ? _green.withValues(alpha: dark ? 0.18 : 0.10)
            : _surface(context),
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected ? _green : border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: _green, size: 20),
                    const Spacer(),
                    if (reviewed)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _green,
                        size: 17,
                      )
                    else
                      Text(
                        '$number',
                        style: const TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: text,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
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

class _PlanGuideCard extends StatelessWidget {
  const _PlanGuideCard({
    required this.index,
    required this.article,
    required this.meta,
    required this.expanded,
    required this.reviewed,
    required this.selected,
  });

  final int index;
  final HelpArticle article;
  final _PlanStepMeta meta;
  final bool expanded;
  final bool reviewed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final border = dark ? const Color(0xFF2B3A31) : const Color(0xFFD9E1DC);
    return Material(
      key: ValueKey('plan-step-card-$index'),
      color: _surface(context),
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: selected ? _green.withValues(alpha: 0.7) : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              key: ValueKey('plan-step-toggle-$index'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: reviewed
                            ? _green
                            : _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: reviewed
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : Icon(meta.icon, color: _green),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${meta.phases.map((phase) => phase.label.toUpperCase()).join(' + ')} · STEP ${index + 1}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: _green,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.45,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta.eyebrow,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: text.withValues(alpha: 0.66)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            article.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: text,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(color: border, height: 1),
                    const SizedBox(height: 14),
                    Text(
                      article.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: text,
                        height: 1.52,
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 240),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanGuideOverlay extends StatefulWidget {
  const _PlanGuideOverlay();

  @override
  State<_PlanGuideOverlay> createState() => _PlanGuideOverlayState();
}

class _PlanGuideOverlayState extends State<_PlanGuideOverlay> {
  late final PageController _pageController;
  final ScrollController _stepController = ScrollController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stepController.hasClients) return;
      final target = (page * 113.0).clamp(
        0.0,
        _stepController.position.maxScrollExtent,
      );
      _stepController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    final border = dark ? const Color(0xFF2B3A31) : const Color(0xFFD9E1DC);
    final lastPage = _page == planningHelp.length - 1;
    return FractionallySizedBox(
      key: const ValueKey('plan-guide-overlay'),
      heightFactor: 0.92,
      child: Material(
        color: dark ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan & track guide',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: text,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Swipe sideways or tap a step',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: secondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('plan-guide-close'),
                    tooltip: 'Close guide',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Row(
                children: [
                  Text(
                    'Step ${_page + 1} of ${planningHelp.length}',
                    key: const ValueKey('plan-guide-step-count'),
                    style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: (_page + 1) / planningHelp.length,
                        color: _green,
                        backgroundColor: border,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 98,
              child: ListView.separated(
                key: const ValueKey('plan-guide-step-strip'),
                controller: _stepController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: planningHelp.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (context, index) => _PlanJourneyStop(
                  key: ValueKey('plan-journey-stop-$index'),
                  number: index + 1,
                  icon: _planStepMeta[index].icon,
                  title: planningHelp[index].title,
                  reviewed: false,
                  selected: _page == index,
                  onTap: () => _goTo(index),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('plan-guide-pages'),
                controller: _pageController,
                itemCount: planningHelp.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: SingleChildScrollView(
                    child: _PlanGuideCard(
                      index: index,
                      article: planningHelp[index],
                      meta: _planStepMeta[index],
                      expanded: true,
                      reviewed: false,
                      selected: true,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  IconButton.outlined(
                    key: const ValueKey('plan-guide-previous'),
                    tooltip: 'Previous step',
                    onPressed: _page == 0 ? null : () => _goTo(_page - 1),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                  Row(
                    children: List<Widget>.generate(
                      planningHelp.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == _page ? 16 : 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: index == _page
                              ? _green
                              : secondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton.filled(
                    key: const ValueKey('plan-guide-next'),
                    tooltip: lastPage ? 'Close guide' : 'Next step',
                    onPressed: lastPage
                        ? () => Navigator.of(context).pop()
                        : () => _goTo(_page + 1),
                    icon: Icon(
                      lastPage
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _green = Color(0xFF34A853);
Color _surface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF141C17)
    : Colors.white;

class _HelpScaffold extends StatelessWidget {
  const _HelpScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PageHeaderAction(
                          tooltip: 'Back',
                          icon: Icons.chevron_left_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                          color: _green,
                          surface: _surface(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: PageHeaderStyle.title(
                                  context,
                                  dark
                                      ? const Color(0xFFEAF4EE)
                                      : const Color(0xFF111111),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: PageHeaderStyle.subtitle(
                                  context,
                                  dark
                                      ? const Color(0xFFA8B8AE)
                                      : const Color(0xFF6E6E73),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                  sliver: SliverList.list(children: children),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: _surface(context),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _HelpLabel extends StatelessWidget {
  const _HelpLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.label, required this.text});
  final String label, text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    ],
  );
}

class _GuideIcon extends StatelessWidget {
  const _GuideIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _green.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: _green, size: 22),
  );
}

class _GuideLink extends StatelessWidget {
  const _GuideLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _HelpCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _GuideIcon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    ),
  );
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.title, required this.url});
  final String title, url;
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(alignment: Alignment.centerLeft),
    onPressed: () async {
      var opened = false;
      try {
        opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the guide. Please try again.'),
          ),
        );
      }
    },
    child: Text('$title ↗'),
  );
}

Widget _conditionMarker(TrailConditionGuide entry) {
  if (entry.types.isNotEmpty && entry.types.first != 'generic') {
    return StaticHazardMarkerIcon(
      kind: staticHazardMarkerKindForType(entry.types.first),
    );
  }
  if (trailHazardReportCategories.values.any(
    (category) => category.$2.contains(entry.title),
  )) {
    return const CommunityHazardMarkerIcon();
  }
  return const StaticHazardMarkerIcon(kind: StaticHazardMarkerKind.generic);
}
