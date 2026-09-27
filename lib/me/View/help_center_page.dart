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
        onTap: () => _open(
          context,
          const _HelpArticlePage(
            title: 'Plan & track',
            subtitle: 'From choosing a trail to getting home',
            articles: planningHelp,
          ),
        ),
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
