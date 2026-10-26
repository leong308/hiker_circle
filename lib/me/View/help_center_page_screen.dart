part of '../help_center_page_feature.dart';

/// Displays the help center page.
class HelpCenterPage extends StatelessWidget {
  /// Creates help center page.
  const HelpCenterPage({super.key, this.isAdmin = false});
  final bool isAdmin;

  /// Builds this widget from its current presentation state.
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

/// Opens.
void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// Displays the hike basics page.
class HikeBasicsPage extends StatefulWidget {
  /// Creates hike basics page.
  const HikeBasicsPage({super.key});

  /// Creates the presentation state for this widget.
  @override
  State<HikeBasicsPage> createState() => _HikeBasicsPageState();
}

/// Manages the hike basics page presentation and lifecycle.
class _HikeBasicsPageState extends State<HikeBasicsPage> {
  late final _HikeBasicsPageStateViewModel _screenModel;

  /// Returns category.
  String get _category => _screenModel.stateCategory;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Delegates choose category to the ViewModel.
  Future<void> _chooseCategory() => _screenModel.commandChooseCategory();

  /// Builds this widget from its current presentation state.
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
          'Outdoor safety guidance and Malaysian weather and air-quality advice.',
        ),
        _SourceLink(
          title: 'Weather phenomena · MET Malaysia',
          url: 'https://www.met.gov.my/en/pendidikan/fenomena-cuaca/',
        ),
        _SourceLink(
          title: 'Haze advice · Ministry of Health Malaysia',
          url:
              'https://www.moh.gov.my/teras/info-kesihatan/jerebu/artikel-dan-panduan-pengguna-berkaitan-jerebu/health-advisory-for-workplaces-during-haze',
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

  /// Presents the choose category effect1 UI.
  Future<String?>
  _presentChooseCategoryEffect1() => showModalBottomSheet<String>(
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

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikeBasicsPageStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.effectPresentChooseCategoryEffect1 =
        _presentChooseCategoryEffect1;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
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

/// Displays the guided help page.
class _GuidedHelpPage extends StatefulWidget {
  /// Creates guided help page.
  const _GuidedHelpPage({required this.guide, this.isAdmin = false});
  final _HelpGuide guide;
  final bool isAdmin;

  /// Creates the presentation state for this widget.
  @override
  State<_GuidedHelpPage> createState() => _GuidedHelpPageState();
}

/// Manages the guided help page presentation and lifecycle.
class _GuidedHelpPageState extends State<_GuidedHelpPage> {
  late final _GuidedHelpPageStateViewModel _screenModel;

  /// Returns resume page.
  int get _resumePage => _screenModel.stateResumePage;

  /// Updates resume page.
  set _resumePage(int value) => _screenModel.stateResumePage = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Delegates open guide to the ViewModel.
  Future<void> _openGuide([int? initialPage]) =>
      _screenModel.commandOpenGuide(initialPage);

  /// Builds this widget from its current presentation state.
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

  /// Presents the open guide effect1 UI.
  Future<void> _presentOpenGuideEffect1(int? initialPage) =>
      showModalBottomSheet<void>(
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

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _GuidedHelpPageStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.effectPresentOpenGuideEffect1 = _presentOpenGuideEffect1;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the help guide hero.
class _HelpGuideHero extends StatelessWidget {
  /// Creates help guide hero.
  const _HelpGuideHero({
    required this.guide,
    required this.onStart,
    required this.resumePage,
  });

  final _HelpGuide guide;
  final int resumePage;

  final VoidCallback onStart;

  /// Builds this widget from its current presentation state.
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

/// Displays the help topic stop.
class _HelpTopicStop extends StatelessWidget {
  /// Creates help topic stop.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the help guide overlay.
class _HelpGuideOverlay extends StatefulWidget {
  /// Creates help guide overlay.
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

  /// Creates the presentation state for this widget.
  @override
  State<_HelpGuideOverlay> createState() => _HelpGuideOverlayState();
}

/// Manages the help guide overlay presentation and lifecycle.
class _HelpGuideOverlayState extends State<_HelpGuideOverlay> {
  late final PageController _pageController;
  final ScrollController _stepController = ScrollController();
  int _page = 0;

  /// Initializes bindings and starts the screen lifecycle.
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _pageController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  /// Computes go to.
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

  /// Computes on page changed.
  void _onPageChanged(int page) {
    setState(() => _page = page);
    widget.onProgress(page);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStep(page));
  }

  /// Computes scroll to step.
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

  /// Builds this widget from its current presentation state.
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

/// Computes help animation.
Duration _helpAnimation(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

const _green = Color(0xFF34A853);

/// Computes surface.
Color _surface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF141C17)
    : Colors.white;

/// Displays the help scaffold.
class _HelpScaffold extends StatelessWidget {
  /// Creates help scaffold.
  const _HelpScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;

  /// Builds this widget from its current presentation state.
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

/// Displays the explanation.
class _Explanation extends StatelessWidget {
  /// Creates explanation.
  const _Explanation({required this.label, required this.text});
  final String label, text;

  /// Builds this widget from its current presentation state.
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

/// Displays the guide icon.
class _GuideIcon extends StatelessWidget {
  /// Creates guide icon.
  const _GuideIcon(this.icon);
  final IconData icon;

  /// Builds this widget from its current presentation state.
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

/// Displays the guide link.
class _GuideLink extends StatelessWidget {
  /// Creates guide link.
  const _GuideLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
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

/// Displays the source link.
class _SourceLink extends StatelessWidget {
  /// Creates source link.
  const _SourceLink({required this.title, required this.url});
  final String title, url;

  /// Builds this widget from its current presentation state.
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

/// Computes condition marker.
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
