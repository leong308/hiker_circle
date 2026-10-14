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
        onTap: () =>
            _open(context, const _GuidedHelpPage(guide: _planningGuide)),
      ),
      _GuideLink(
        icon: Icons.groups_2_rounded,
        title: 'Team hike basics',
        subtitle: 'Joining, readiness and staying together',
        onTap: () => _open(context, const _GuidedHelpPage(guide: _teamGuide)),
      ),
      _GuideLink(
        icon: Icons.sos_rounded,
        title: 'Using SOS safely',
        subtitle: 'Contacts, alerts and emergency help',
        onTap: () => _open(context, const _GuidedHelpPage(guide: _sosGuide)),
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
          _GuidedHelpPage(guide: _accountGuide, isAdmin: isAdmin),
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

class _HelpStepMeta {
  const _HelpStepMeta({
    required this.icon,
    required this.eyebrow,
    required this.stage,
  });

  final IconData icon;
  final String eyebrow;
  final String stage;
}

const _planStepMeta = <_HelpStepMeta>[
  _HelpStepMeta(
    icon: Icons.explore_rounded,
    eyebrow: 'Choose with confidence',
    stage: 'Before hike',
  ),
  _HelpStepMeta(
    icon: Icons.map_rounded,
    eyebrow: 'Know the route',
    stage: 'Before hike',
  ),
  _HelpStepMeta(
    icon: Icons.cloud_rounded,
    eyebrow: 'Check the full window',
    stage: 'Before hike',
  ),
  _HelpStepMeta(
    icon: Icons.backpack_rounded,
    eyebrow: 'Prepare for the conditions',
    stage: 'Before hike',
  ),
  _HelpStepMeta(
    icon: Icons.navigation_rounded,
    eyebrow: 'Stay aware as you move',
    stage: 'On trail',
  ),
  _HelpStepMeta(
    icon: Icons.flag_rounded,
    eyebrow: 'Close the loop',
    stage: 'After hike',
  ),
  _HelpStepMeta(
    icon: Icons.signal_cellular_connected_no_internet_4_bar_rounded,
    eyebrow: 'Plan beyond coverage',
    stage: 'Before + on trail',
  ),
];

class _HelpGuide {
  const _HelpGuide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.articles,
    required this.steps,
    required this.overview,
    required this.noticeTitle,
    required this.notice,
    this.sourceTitle,
    this.sourceUrl,
  });
  final String id, title, subtitle, badge, heroTitle, heroSubtitle;
  final List<HelpArticle> articles;
  final List<_HelpStepMeta> steps;
  final List<
    ({IconData icon, String title, String detail, String count, int start})
  >
  overview;
  final String noticeTitle, notice;
  final String? sourceTitle, sourceUrl;
}

const _planningGuide = _HelpGuide(
  id: 'plan',
  title: 'Plan & track',
  subtitle: 'From choosing a trail to getting home',
  badge: 'PLAN → TRACK → REVIEW',
  heroTitle: 'Your hike in 7 clear steps',
  heroSubtitle:
      'Swipe through practical guidance from choosing a trail to getting home.',
  articles: planningHelp,
  steps: _planStepMeta,
  overview: [
    (
      icon: Icons.backpack_rounded,
      title: 'Before the hike',
      detail: 'Choose, understand, check and prepare',
      count: '4 steps',
      start: 0,
    ),
    (
      icon: Icons.navigation_rounded,
      title: 'On the trail',
      detail: 'Track progress and handle weak signal',
      count: '2 topics',
      start: 4,
    ),
    (
      icon: Icons.flag_rounded,
      title: 'After the hike',
      detail: 'Finish safely and review your record',
      count: '1 step',
      start: 5,
    ),
  ],
  noticeTitle: 'Conditions can change quickly',
  notice:
      'Follow closures and local instructions, keep a backup plan, and turn back when the route exceeds your ability.',
);

const _teamGuide = _HelpGuide(
  id: 'team',
  title: 'Team hike basics',
  subtitle: 'Prepare and move as a group',
  badge: 'JOIN → READY → TOGETHER',
  heroTitle: 'One team. One shared plan.',
  heroSubtitle:
      'From finding your group to a safe return, explore 7 practical steps.',
  articles: teamHelp,
  steps: [
    _HelpStepMeta(
      icon: Icons.group_add_rounded,
      eyebrow: 'Find your people',
      stage: 'Join & coordinate',
    ),
    _HelpStepMeta(
      icon: Icons.forum_rounded,
      eyebrow: 'Agree on the details',
      stage: 'Join & coordinate',
    ),
    _HelpStepMeta(
      icon: Icons.backpack_rounded,
      eyebrow: 'Everyone prepares',
      stage: 'Get ready',
    ),
    _HelpStepMeta(
      icon: Icons.play_circle_rounded,
      eyebrow: 'The host starts the hike',
      stage: 'Get ready',
    ),
    _HelpStepMeta(
      icon: Icons.groups_rounded,
      eyebrow: 'Move at the group’s pace',
      stage: 'On trail & return',
    ),
    _HelpStepMeta(
      icon: Icons.location_searching_rounded,
      eyebrow: 'Check people, not just dots',
      stage: 'On trail & return',
    ),
    _HelpStepMeta(
      icon: Icons.flag_rounded,
      eyebrow: 'Confirm everyone is home',
      stage: 'On trail & return',
    ),
  ],
  overview: [
    (
      icon: Icons.group_add_rounded,
      title: 'Join & coordinate',
      detail: 'Membership, meeting point and group chat',
      count: '2 steps',
      start: 0,
    ),
    (
      icon: Icons.fact_check_rounded,
      title: 'Ready & start',
      detail: 'Personal checks and the host’s launch',
      count: '2 steps',
      start: 2,
    ),
    (
      icon: Icons.groups_rounded,
      title: 'Together & back',
      detail: 'Pace, updates and finishing your session',
      count: '3 steps',
      start: 4,
    ),
  ],
  noticeTitle: 'Check in with each other',
  notice:
      'Agree on regroup points and a plan for lost signal. A map dot cannot tell you whether a teammate is okay.',
);

const _sosGuide = _HelpGuide(
  id: 'sos',
  title: 'Using SOS safely',
  subtitle: 'Know the controls before you need them',
  badge: 'PREPARE → ALERT → GET HELP',
  heroTitle: 'Know your next move.',
  heroSubtitle:
      'Learn the controls, safe tests and alert status in 8 focused topics.',
  articles: sosHelp,
  steps: [
    _HelpStepMeta(
      icon: Icons.contact_phone_rounded,
      eyebrow: 'Prepare your safety network',
      stage: 'Prepare & practise',
    ),
    _HelpStepMeta(
      icon: Icons.touch_app_rounded,
      eyebrow: 'Practise without a real alert',
      stage: 'Prepare & practise',
    ),
    _HelpStepMeta(
      icon: Icons.settings_remote_rounded,
      eyebrow: 'Keep the button ready',
      stage: 'Prepare & practise',
    ),
    _HelpStepMeta(
      icon: Icons.sos_rounded,
      eyebrow: 'Tap, countdown, alert',
      stage: 'Understand alerts',
    ),
    _HelpStepMeta(
      icon: Icons.volume_off_rounded,
      eyebrow: 'A discreet alert',
      stage: 'Understand alerts',
    ),
    _HelpStepMeta(
      icon: Icons.health_and_safety_rounded,
      eyebrow: 'Know your enabled features',
      stage: 'Understand alerts',
    ),
    _HelpStepMeta(
      icon: Icons.mark_chat_read_rounded,
      eyebrow: 'Check what actually sent',
      stage: 'Delivery & help',
    ),
    _HelpStepMeta(
      icon: Icons.emergency_rounded,
      eyebrow: 'Reach emergency services',
      stage: 'Delivery & help',
    ),
  ],
  overview: [
    (
      icon: Icons.shield_outlined,
      title: 'Prepare & practise',
      detail: 'Contacts, safe tests and a paired button',
      count: '3 topics',
      start: 0,
    ),
    (
      icon: Icons.sos_rounded,
      title: 'Understand alerts',
      detail: 'Manual, Duress and automatic detection',
      count: '3 topics',
      start: 3,
    ),
    (
      icon: Icons.contact_phone_rounded,
      title: 'Delivery & help',
      detail: 'Queued alerts and emergency assistance',
      count: '2 topics',
      start: 6,
    ),
  ],
  noticeTitle: 'An alert is only one part of getting help',
  notice:
      'Delivery and nearby responses depend on connectivity and other people. For immediate danger in Malaysia, call 999 when possible.',
  sourceTitle: 'Malaysia emergency line · Official guidance',
  sourceUrl:
      'https://www.malaysia.gov.my/en/categories/safety-and-community/public-safety/mers-999-emergency-line',
);

const _accountGuide = _HelpGuide(
  id: 'account',
  title: 'Account & troubleshooting',
  subtitle: 'Secure your account. Get back on track.',
  badge: 'SIGN IN → CHECK → RESOLVE',
  heroTitle: 'Find the fix, step by step.',
  heroSubtitle:
      'Jump to the topic you need, from verification to delayed updates.',
  articles: accountHelp,
  steps: [
    _HelpStepMeta(
      icon: Icons.login_rounded,
      eyebrow: 'Start with your registered number',
      stage: 'Your account',
    ),
    _HelpStepMeta(
      icon: Icons.password_rounded,
      eyebrow: 'Use the latest code',
      stage: 'Your account',
    ),
    _HelpStepMeta(
      icon: Icons.security_rounded,
      eyebrow: 'Keep a working sign-in method',
      stage: 'Your account',
    ),
    _HelpStepMeta(
      icon: Icons.lock_reset_rounded,
      eyebrow: 'Follow your linked recovery method',
      stage: 'Your account',
    ),
    _HelpStepMeta(
      icon: Icons.app_settings_alt_rounded,
      eyebrow: 'Check the phone’s permissions',
      stage: 'Your phone & data',
    ),
    _HelpStepMeta(
      icon: Icons.cloud_sync_rounded,
      eyebrow: 'Read the last updated time',
      stage: 'Your phone & data',
    ),
    _HelpStepMeta(
      icon: Icons.sync_rounded,
      eyebrow: 'Give pending data time to sync',
      stage: 'Your phone & data',
    ),
    _HelpStepMeta(
      icon: Icons.chat_bubble_outline_rounded,
      eyebrow: 'Help us reproduce the issue',
      stage: 'Get support',
    ),
  ],
  overview: [
    (
      icon: Icons.manage_accounts_outlined,
      title: 'Sign-in & security',
      detail: 'Codes, login methods and recovery',
      count: '4 topics',
      start: 0,
    ),
    (
      icon: Icons.phonelink_setup_rounded,
      title: 'Phone & updates',
      detail: 'Permissions, saved weather and syncing',
      count: '3 topics',
      start: 4,
    ),
    (
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Get support',
      detail: 'Capture a problem and follow its reply',
      count: '1 topic',
      start: 7,
    ),
  ],
  noticeTitle: 'Keep your private details private',
  notice:
      'Never share passwords or verification codes. Remove private information from screenshots before sending feedback.',
);

class _GuidedHelpPage extends StatefulWidget {
  const _GuidedHelpPage({required this.guide, this.isAdmin = false});
  final _HelpGuide guide;
  final bool isAdmin;
  @override
  State<_GuidedHelpPage> createState() => _GuidedHelpPageState();
}

class _GuidedHelpPageState extends State<_GuidedHelpPage> {
  bool _guideOpen = false;
  int _resumePage = 0;

  Future<void> _openGuide([int? initialPage]) async {
    if (_guideOpen) return;
    _guideOpen = true;
    _resumePage = initialPage ?? _resumePage;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (_) => _HelpGuideOverlay(
          guide: widget.guide,
          initialPage: initialPage ?? _resumePage,
          onProgress: (page) => _resumePage = page,
          onFeedback: widget.guide.id == 'account'
              ? () => _open(context, FeedbackPage(isAdmin: widget.isAdmin))
              : null,
        ),
      );
    } finally {
      _guideOpen = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final guide = widget.guide;
    final colors = Theme.of(context).colorScheme;
    return _HelpScaffold(
      title: guide.title,
      subtitle: guide.subtitle,
      children: [
        _HelpGuideHero(
          guide: guide,
          resumePage: _resumePage,
          onStart: () => _openGuide(),
        ),
        const SizedBox(height: 22),
        Text(
          'At a glance',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          'Tap a section to jump in, or follow the whole guide.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final section in guide.overview) ...[
          _HelpOverviewRow(
            icon: section.icon,
            title: section.title,
            detail: section.detail,
            count: section.count,
            onTap: () => _openGuide(section.start),
          ),
          const SizedBox(height: 9),
        ],
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _green.withValues(alpha: 0.28)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: _green),
              const SizedBox(width: 12),
              Expanded(
                child: _Explanation(
                  label: guide.noticeTitle,
                  text: guide.notice,
                ),
              ),
            ],
          ),
        ),
        if (guide.id == 'account') ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('account-feedback'),
            onPressed: () =>
                _open(context, FeedbackPage(isAdmin: widget.isAdmin)),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Open Feedback'),
          ),
        ],
        if (guide.sourceUrl != null)
          _SourceLink(title: guide.sourceTitle!, url: guide.sourceUrl!),
      ],
    );
  }
}

class _HelpGuideHero extends StatelessWidget {
  const _HelpGuideHero({
    required this.guide,
    required this.onStart,
    required this.resumePage,
  });

  final _HelpGuide guide;
  final int resumePage;

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final showCount =
        MediaQuery.sizeOf(context).width >= 380 &&
        MediaQuery.textScalerOf(context).scale(14) <= 18;
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
                      child: Text(
                        guide.badge,
                        style: TextStyle(
                          color: Color(0xFFB8EDC9),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      guide.heroTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      guide.heroSubtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        height: 1.42,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCount) const SizedBox(width: 14),
              if (showCount)
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
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${guide.articles.length}',
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
                  key: ValueKey('${guide.id}-guide-start'),
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF145C34),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    resumePage == 0 ? 'Start guide' : 'Continue guide',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpOverviewRow extends StatelessWidget {
  const _HelpOverviewRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    return Material(
      color: _surface(context),
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
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
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count,
                    style: const TextStyle(
                      color: _green,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _green,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpTopicStop extends StatelessWidget {
  const _HelpTopicStop({
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
            duration: _helpAnimation(context, 180),
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

class _HelpTopicCard extends StatelessWidget {
  const _HelpTopicCard({
    required this.index,
    required this.article,
    required this.meta,
    required this.expanded,
    required this.reviewed,
    required this.selected,
  });

  final int index;
  final HelpArticle article;
  final _HelpStepMeta meta;
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
        duration: _helpAnimation(context, 220),
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
                            '${meta.stage.toUpperCase()} · STEP ${index + 1}',
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
                    if (article.location != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.near_me_outlined,
                              color: _green,
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                article.location!,
                                style: TextStyle(
                                  color: text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (article.actions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'What to do',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      for (
                        var action = 0;
                        action < article.actions.length;
                        action++
                      )
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _green.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${action + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _green,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  article.actions[action],
                                  style: TextStyle(color: text, height: 1.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (article.tip != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: text.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              article.tip!,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: text.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: _helpAnimation(context, 240),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpGuideOverlay extends StatefulWidget {
  const _HelpGuideOverlay({
    required this.guide,
    this.initialPage = 0,
    required this.onProgress,
    this.onFeedback,
  });
  final _HelpGuide guide;
  final int initialPage;
  final ValueChanged<int> onProgress;
  final VoidCallback? onFeedback;

  @override
  State<_HelpGuideOverlay> createState() => _HelpGuideOverlayState();
}

class _HelpGuideOverlayState extends State<_HelpGuideOverlay> {
  late final PageController _pageController;
  final ScrollController _stepController = ScrollController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _pageController = PageController(
      viewportFraction: 0.92,
      initialPage: _page,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStep(_page));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(page);
      return;
    }
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    widget.onProgress(page);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStep(page));
  }

  void _scrollToStep(int page) {
    if (!mounted || !_stepController.hasClients) return;
    final target = (page * 113.0).clamp(
      0.0,
      _stepController.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _stepController.jumpTo(target);
      return;
    }
    _stepController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    final border = dark ? const Color(0xFF2B3A31) : const Color(0xFFD9E1DC);
    final lastPage = _page == widget.guide.articles.length - 1;
    return FractionallySizedBox(
      key: ValueKey('${widget.guide.id}-guide-overlay'),
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
              child: PageHeader(
                title: switch (widget.guide.id) {
                  'plan' => 'Plan & track guide',
                  'team' => 'Team hike guide',
                  'sos' => 'SOS guide',
                  _ => 'Account guide',
                },
                subtitle: 'Swipe sideways or tap a step',
                actions: [
                  PageHeaderAction(
                    key: ValueKey('${widget.guide.id}-guide-close'),
                    tooltip: 'Close guide',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close_rounded,
                    color: _green,
                    surface: _surface(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Row(
                children: [
                  Text(
                    'Step ${_page + 1} of ${widget.guide.articles.length}',
                    key: ValueKey('${widget.guide.id}-guide-step-count'),
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
                        value: (_page + 1) / widget.guide.articles.length,
                        color: _green,
                        backgroundColor: border,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(12) > 16
                  ? 116
                  : 98,
              child: ListView.separated(
                key: ValueKey('${widget.guide.id}-guide-step-strip'),
                controller: _stepController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: widget.guide.articles.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (context, index) => _HelpTopicStop(
                  key: ValueKey('${widget.guide.id}-journey-stop-$index'),
                  number: index + 1,
                  icon: widget.guide.steps[index].icon,
                  title: widget.guide.articles[index].title,
                  reviewed: false,
                  selected: _page == index,
                  onTap: () => _goTo(index),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: PageView.builder(
                key: ValueKey('${widget.guide.id}-guide-pages'),
                controller: _pageController,
                itemCount: widget.guide.articles.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _HelpTopicCard(
                          index: index,
                          article: widget.guide.articles[index],
                          meta: widget.guide.steps[index],
                          expanded: true,
                          reviewed: false,
                          selected: true,
                        ),
                        if (index == widget.guide.articles.length - 1 &&
                            widget.onFeedback != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 14),
                            child: FilledButton.icon(
                              key: const ValueKey('account-guide-feedback'),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                              label: const Text('Open Feedback'),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onFeedback!();
                              },
                            ),
                          ),
                      ],
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
                    key: ValueKey('${widget.guide.id}-guide-previous'),
                    tooltip: 'Previous step',
                    onPressed: _page == 0 ? null : () => _goTo(_page - 1),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                  Row(
                    children: List<Widget>.generate(
                      widget.guide.articles.length,
                      (index) => AnimatedContainer(
                        duration: _helpAnimation(context, 180),
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
                    key: ValueKey('${widget.guide.id}-guide-next'),
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

Duration _helpAnimation(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

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
                    child: PageHeader(
                      title: title,
                      subtitle: subtitle,
                      onBack: () => Navigator.of(context).pop(),
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
